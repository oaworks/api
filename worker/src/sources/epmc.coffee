

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

P.src.epmc = _index: true, _prefix: false, _key: 'id' # id will be the pubmed ID from the looks of it

P.src.epmc.search = (qrystr, from, size) ->
  qrystr ?= @params.search ? @params.epmc ? @params.doi ? ''
  qrystr = 'DOI:' + qrystr if qrystr.startsWith('10.') and not qrystr.includes(' ') and qrystr.split('/').length >= 2
  qrystr = 'PMCID:PMC' + qrystr.toLowerCase().replace('pmc','') if typeof qrystr is 'string' and not qrystr.startsWith('PMCID:') and qrystr.toLowerCase().startsWith('pmc') and not qrystr.includes ' '
  qrystr = 'PMCID:PMC' + qrystr if typeof qrystr is 'number'
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + ' sort_date:y&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  url += '&cursorMark=' + from if from? # used to be a from pager, but now uses a cursor
  ret = {}
  await @sleep 250
  res = await @fetch url
  ret.total = res.hitCount
  ret.data = res.resultList?.result ? []
  ret.cursor = res.nextCursorMark
  if ret.data.length
    @waitUntil @src.epmc ret.data
  return ret

P.src.epmc.doi = (ident) ->
  ident ?= @params.doi
  exists = await @src.epmc 'doi:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else
    res = await @src.epmc.search 'DOI:' + ident
    return if res.total then res.data[0] else undefined

P.src.epmc.pmid = (ident) ->
  ident ?= @params.pmid
  exists = await @src.epmc 'pmid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else
    res = await @src.epmc.search 'EXT_ID:' + ident + ' AND SRC:MED'
    return if res.total then res.data[0] else undefined

P.src.epmc.pmc = (ident) ->
  ident ?= @params.pmc ? @params.pmcid
  ident = 'PMC' + ident.toLowerCase().replace 'pmc', ''
  exists = await @src.epmc 'pmcid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else
    res = await @src.epmc.search 'PMCID:' + ident
    return if res.total then res.data[0] else undefined

P.src.epmc.title = (title) ->
  title ?= @params.title
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  exists = await @src.epmc 'title:"' + title + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else
    res = await @src.epmc.search 'title:"' + title + '"'
    return if res.total then res.data[0] else undefined

P.src.epmc.licence = (pmcid, rec, fulltext, refresh) ->
  pmcid ?= @params.licence ? @params.pmcid ? @params.epmc
  pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc','') if pmcid
  refresh ?= @refresh
  if pmcid and not rec?
    rec = await @src.epmc.pmc pmcid
  if rec or fulltext
    if rec?.calculated_licence? and not refresh
      return rec.calculated_licence
    else
      pmcid ?= rec?.pmcid
      if rec?.license and typeof rec.license is 'string'
        lics = licence: rec.license, source:'epmc_api'
        lics.licence = lics.licence.replace(/ /g,'-') if lics.licence.startsWith 'cc'
      else
        if not fulltext and pmcid
          fulltext = await @src.epmc.xml pmcid, rec
        if @licence?
          if typeof fulltext is 'string' and fulltext.startsWith '<'
            lics = await @licence undefined, fulltext, '<permissions>', '</permissions>'
            lics.source = 'epmc_xml_permissions' if lics?.licence?
          if not lics?.licence?
            lics = await @licence undefined, fulltext
            lics.source = 'epmc_xml_outside_permissions' if lics?.licence?
        if not lics?.licence? and typeof fulltext is 'string' and fulltext.includes '<permissions>'
          lics = licence: 'non-standard-licence', source: 'epmc_xml_permissions'
  
        if pmcid and @licence? and (not lics?.licence? or lics?.licence is 'non-standard-licence')
          await @sleep 1000
          url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace 'pmc', ''
          if pg = await @puppet url
            try lics = await @licence undefined, pg
            lics.source = 'epmc_html' if lics?.licence?
    
    if lics?.licence?
      rec.calculated_licence = lics
      await @src.epmc rec.id, rec
      return lics

  return

P.src.epmc.xml = (pmcid, rec) ->
  pmcid ?= @params.xml ? @params.pmcid ? @params.epmc
  pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc','') if pmcid
  if pmcid
    try
      ft = await fs.readFile '/home/cloo/static/epmc/fulltext/' + pmcid + '.xml'
      return ft.toString()
    catch
      rec ?= await @src.epmc.pmc pmcid
      if not rec?.no_ft
        await @sleep 200
        ft = await @fetch 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML'
        if typeof ft is 'string' and ft.length
          try await fs.writeFile '/home/cloo/static/epmc/fulltext/' + pmcid + '.xml', ft
          return ft
        else if rec?
          rec.no_ft = true
          await @src.epmc rec.id, rec
  return
  
P.src.epmc.aam = (pmcid, rec, fulltext) ->
  pmcid ?= @params.aam ? @params.pmcid ? @params.epmc
  if typeof fulltext is 'string' and fulltext.includes('pub-id-type=\'manuscript\'') and fulltext.includes('pub-id-type="manuscript"')
    return aam: true, info: 'fulltext'
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    try rec = await @src.epmc.pmc(pmcid) if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      fulltext = await @src.epmc.xml pmcid, rec
      if typeof fulltext is 'string' and fulltext.includes('pub-id-type=\'manuscript\'') and fulltext.includes('pub-id-type="manuscript"')
        return aam: true, info: 'fulltext'
      else
        await @sleep 2000
        pg = await @puppet 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace 'pmc', ''
        if not pg
          return aam: false, info: 'not in EPMC (404)'
        else if typeof pg is 'string'
          s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal'
          s2 = 'Author manuscript; available in PMC'
          s3 = 'logo-nihpa.gif'
          s4 = 'logo-wtpa2.gif'
          if pg.includes(s1) or pg.includes(s2) or pg.includes(s3) or pg.includes(s4)
            return aam: true, info: 'splashpage'
          else
            return aam: false, info: 'EPMC splashpage checked, no indicator found'
        else if pg?
          return info: 'EPMC was accessed but aam could not be decided from what was returned'
        else #if typeof pg is 'object' and pg.status is 403
          return info: 'EPMC may be blocking access, AAM status unknown'
  return aam: false, info: ''

