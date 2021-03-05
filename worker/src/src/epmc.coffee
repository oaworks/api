

# Europe PMC client
# https://europepmc.org/RestfulWebService
# https://www.ebi.ac.uk/europepmc/webservices/rest/search/
# https://europepmc.org/Help#fieldsearch

# GET https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:10.1007/bf00197367&resulttype=core&format=json
# default page is 1 and default pageSize is 25
# resulttype lite is smaller, lacks so much metadata, no mesh, terms, etc
# open_access:y added to query will return only open access articles, and they will have fulltext xml available at a link like the following:
# https://www.ebi.ac.uk/europepmc/webservices/rest/PMC3257301/fullTextXML
# can also use HAS_PDF:y to get back ones where we should expect to be able to get a pdf, but it is not clear if those are OA and available via eupmc
# can ensure a DOI is available using HAS_DOI
# can search publication date via FIRST_PDATE:1995-02-01 or FIRST_PDATE:[2000-10-14 TO 2010-11-15] to get range

P.src.epmc = (qrystr, from, size) ->
  qrystr = 'DOI:' + qrystr if qrystr.indexOf('10.') is 0 and qrystr.indexOf(' ') is -1 and qrystr.split('/').length is 2 
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '%20sort_date:y&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  url += '&cursorMark=' + from if from? # used to be a from pager, but now uses a cursor
  ret = {}
  res = await @fetch url
  ret.total = res.hitCount
  ret.data = res.resultList?.result ? []
  ret.cursor = res.nextCursorMark
  return ret

P.src.epmc.pmid = (ident) ->
  res = @src.epmc 'EXT_ID:' + ident + ' AND SRC:MED'
  return if res.total then res.data[0] else undefined

P.src.epmc.pmc = (ident) ->
  res = @src.epmc 'PMCID:PMC' + ident.toLowerCase().replace 'pmc', ''
  return if res.total then res.data[0] else undefined

P.src.epmc.title = (title) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  res = @src.epmc 'title:"' + title + '"'
  return if res.total then res.data[0] else undefined

P.src.epmc.licence = (pmcid, rec, fulltext) ->
  maybe_licence
  res = @src.epmc('PMC' + pmcid.toLowerCase().replace('pmc','')) if pmcid and not rec
  if res?.total > 0 or rec or fulltext
    rec ?= res.data[0]
    pmcid = rec.pmcid if not pmcid and rec
    if rec.license
      licinapi = {licence: rec.license,source:'epmc_api'}
      licinapi.licence = licinapi.licence.replace(/ /g,'-') if licinapi.licence.indexOf('cc') is 0
      return licinapi
      
    fulltext = @src.epmc.xml(pmcid) if not fulltext and pmcid
    if fulltext isnt 404 and typeof fulltext is 'string' and fulltext.indexOf('<') is 0 and @svc.lantern?
      licinperms = @svc.lantern.licence undefined,undefined,fulltext,'<permissions>','</permissions>'
      if licinperms.licence?
        licinperms.source = 'epmc_xml_permissions'
        return licinperms

      licanywhere = @svc.lantern.licence undefined,undefined,fulltext
      if licanywhere.licence?
        licanywhere.source = 'epmc_xml_outside_permissions'
        return licanywhere

      if fulltext.indexOf('<permissions>') isnt -1
        maybe_licence = {licence:'non-standard-licence',source:'epmc_xml_permissions'}

    if false #pmcid and not noui and @svc?.lantern?.licence?
      # TODO need a way to rate limit and run puppeteer
      url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
      pg = P.job.limit 3000, 'P.http.puppeteer', [url], "EPMCUI"
      if typeof pg is 'string'
        try licsplash = P.service.lantern.licence url, false, pg
        if licsplash?.licence?
          licsplash.source = 'epmc_html'
          return licsplash

    return maybe_licence ? false
  else
    return false

P.src.epmc.xml = (pmcid) ->
  pmcid = pmcid.toLowerCase().replace('pmc','') if pmcid
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/PMC' + pmcid + '/fullTextXML'
  r = await @fetch url
  return r.content

P.src.epmc.aam = (pmcid, rec, fulltext, noui) ->
  if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
    return {aam:true,info:'fulltext'}
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    #rec = @src.epmc.search('PMC' + pmcid.toLowerCase().replace('pmc',''))?.data?[0] if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      fulltext = @src.epmc.xml pmcid
      if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
        resp = {aam:true,info:'fulltext'}
        return resp
      else if false #not noui
        url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
        pg = P.job.limit 3000, 'P.http.puppeteer', [url], "EPMCUI"
        if pg is 404
          resp = {aam:false,info:'not in EPMC (404)'}
          return resp
        else if pg is 403
          return {info: 'EPMC blocking access, AAM status unknown'}
        else if typeof pg is 'string'
          s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal'
          s2 = 'Author manuscript; available in PMC'
          s3 = 'logo-nihpa.gif'
          s4 = 'logo-wtpa2.gif'
          if pg.indexOf(s1) isnt -1 or pg.indexOf(s2) isnt -1 or pg.indexOf(s3) isnt -1 or pg.indexOf(s4) isnt -1
            resp = {aam:true,info:'splashpage'}
            return resp
          else
            resp = {aam:false,info:'EPMC splashpage checked, no indicator found'}
            return resp
        else if pg?
          return {info: 'EPMC was accessed but aam could not be decided from what was returned'}
        else
          return {info: 'EPMC was accessed nothing was returned, so aam check could not be performed'}
  return {aam:false,info:''}

