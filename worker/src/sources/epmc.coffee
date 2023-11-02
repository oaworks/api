

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
P.src.epmc.notinepmc = _index: true, _prefix: false, _key: 'id', _hide: true # keep track of ones we already looked up

P.src.epmc.search = (qrystr, from, size) ->
  qrystr ?= @params.search ? @params.epmc ? @params.doi ? ''
  qrystr = 'DOI:' + qrystr if qrystr.startsWith('10.') and not qrystr.includes(' ') and qrystr.split('/').length >= 2
  qrystr = 'PMCID:PMC' + qrystr.toLowerCase().replace('pmc','') if typeof qrystr is 'string' and not qrystr.startsWith('PMCID:') and qrystr.toLowerCase().startsWith('pmc') and not qrystr.includes ' '
  qrystr = 'PMCID:PMC' + qrystr if typeof qrystr is 'number'
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + ' sort_date:y&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  url += '&cursorMark=' + from if from? # used to be a from pager, but now uses a cursor
  ret = {}
  await @sleep 150
  res = await @fetch url
  ret.total = res.hitCount
  ret.data = res.resultList?.result ? []
  ret.cursor = res.nextCursorMark
  if ret.data.length
    @waitUntil @src.epmc ret.data
  return ret

P.src.epmc.doi = (ident, refresh) ->
  refresh ?= @refresh if not ident
  ident ?= @params.doi
  exists = await @src.epmc 'doi:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else if not refresh and Date.now() - ((await @src.epmc.notinepmc ident)?.checkedAt ? 0) < 1000*60*60*24*3 # if we checked in the last three days, don't check again
    return
  else
    res = await @src.epmc.search 'DOI:' + ident
    if res.total
      if not res.data[0].doi
        res.data[0].doi = ident
        @waitUntil @src.epmc res.data[0]
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident.replace(/\//g, '_'), doi: ident, checkedAt: Date.now()
      return

P.src.epmc.pmid = (ident, refresh) ->
  refresh ?= @refresh if not ident
  ident ?= @params.pmid
  exists = await @src.epmc 'pmid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else if not refresh and Date.now() - ((await @src.epmc.notinepmc ident)?.checkedAt ? 0) < 1000*60*60*24*3
    return
  else
    res = await @src.epmc.search 'EXT_ID:' + ident + ' AND SRC:MED'
    if res.total
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident, pmid: ident, checkedAt: Date.now()
      return

P.src.epmc.pmc = (ident, refresh) ->
  refresh ?= @refresh if not ident
  ident ?= @params.pmc ? @params.pmcid
  ident = 'PMC' + ident.toLowerCase().replace 'pmc', ''
  exists = await @src.epmc 'pmcid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else if not refresh and Date.now() - ((await @src.epmc.notinepmc ident)?.checkedAt ? 0) < 1000*60*60*24*3
    return
  else
    res = await @src.epmc.search 'PMCID:' + ident
    if res.total
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident, pmcid: ident, checkedAt: Date.now()
      return

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
  refresh ?= @refresh if not pmcid
  pmcid ?= @params.licence ? @params.pmcid ? @params.epmc
  pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc','') if pmcid
  if pmcid and not rec?
    rec = await @src.epmc.pmc pmcid, refresh
  if rec or fulltext
    if rec?.calculated_licence? and not refresh
      return if rec.calculated_licence.licence is 'not found' then undefined else rec.calculated_licence
    else
      pmcid ?= rec?.pmcid
      if rec?.license and typeof rec.license is 'string'
        lics = licence: rec.license, source:'epmc_api'
        lics.licence = lics.licence.replace(/ /g,'-') if lics.licence.startsWith 'cc'
      else
        if not fulltext and pmcid
          fulltext = await @src.epmc.xml pmcid, rec, refresh
        if @licence? and fulltext
          if typeof fulltext is 'string' and fulltext.startsWith '<'
            lics = await @licence undefined, fulltext, '<permissions>', '</permissions>'
            lics.source = 'epmc_xml_permissions' if lics?.licence?
          if not lics?.licence?
            lics = await @licence undefined, fulltext
            lics.source = 'epmc_xml_outside_permissions' if lics?.licence?
        if not lics?.licence? and typeof fulltext is 'string' and fulltext.includes '<permissions>'
          lics = licence: 'non-standard-licence', source: 'epmc_xml_permissions'
  
        #if pmcid and @licence? and (not lics?.licence? or lics?.licence is 'non-standard-licence')
        #  await @sleep 1000
        #  url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace 'pmc', ''
        #  if pg = await @puppet url
        #    try lics = await @licence undefined, pg
        #    lics.source = 'epmc_html' if lics?.licence?
    
    if lics?.licence?
      rec.calculated_licence = lics
      await @src.epmc rec.id, rec
      return lics
    else
      rec.calculated_licence = licence: 'not found'
      await @src.epmc rec.id, rec

  return

_last_ncbi = Date.now()
_ncbi_running = 0
P.src.epmc.xml = (pmcid, rec, refresh) ->
  pmcid ?= @params.xml ? @params.pmcid ? @params.epmc
  pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc','') if pmcid
  refresh ?= @refresh
  if pmcid
    try
      ft = await fs.readFile @S.directory + '/epmc/fulltext/' + pmcid + '.xml'
      return ft.toString()
    catch
      rec ?= await @src.epmc.pmc pmcid, refresh
      if refresh or not rec?.no_ft
        ncdl = Date.now() - _last_ncbi
        while ncdl < 500 or _ncbi_running >= 2 # should be able to hit 3r/s although it's possible we call from other workers on same server. This will have to do for now
          await @sleep(500 - ncdl)
          ncdl = Date.now() - _last_ncbi
        _last_ncbi = Date.now()
        _ncbi_running += 1
        # without sleep (and at 150, 300, 400) threw rate limit error on ncbi and ebi - this does not guarantee it because other calls could be made, but is a quick fix
        # try ncbi first as it is faster but it does not have everything in epmc - however when present the xml files are the same
        url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=' + pmcid
        ft = await @fetch url
        _ncbi_running -= 1
        if (typeof ft isnt 'string' or not ft.length) and rec? # if it is in epmc, can try getting from there instead
          url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML'
          ft = await @fetch url
        if typeof ft is 'string' and ft.length
          try await fs.writeFile @S.directory + '/epmc/fulltext/' + pmcid + '.xml', ft
          return ft
        else if rec?
          rec.no_ft = true
          await @src.epmc rec.id, rec
  return

P.src.epmc.fulltext = (pmcid) -> # check fulltext exists in epmc explicitly
  pmcid ?= @params.fulltext ? @params.pmcid ? @params.epmc
  if pmcid
    await @sleep 150
    exists = await @fetch 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML', method: 'HEAD'
    return exists?.status is 200
  else
    return

P.src.epmc.aam = (pmcid, rec, fulltext, refresh) ->
  pmcid ?= @params.aam ? @params.pmcid ? @params.epmc
  if typeof fulltext is 'string' and fulltext.includes('pub-id-type=\'manuscript\'') and fulltext.includes('pub-id-type="manuscript"')
    return aam: true, info: 'fulltext'
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    try rec = await @src.epmc.pmc(pmcid, refresh) if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      fulltext = await @src.epmc.xml pmcid, rec, refresh
      if typeof fulltext is 'string' and fulltext.includes('pub-id-type=\'manuscript\'') and fulltext.includes('pub-id-type="manuscript"')
        return aam: true, info: 'fulltext'
      else
        await @sleep 1000
        url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace 'pmc', ''
        #pg = await @puppet url
        pg = await @fetch url
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




P.src.epmc.statement = (pmcid, rec, refresh, verbose) ->
  # because of xml parsing issues with embedded html in pmc xml, just regex it out if present
  # pubmed data does not hold corresponding statements to pmc, but the pmc records from ncbi do contain them as they are the same as fulltext records from epmc
  # see <notes notes-type="data-availability"> in
  # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
  # or <custom-meta id="data-availability"> in 
  # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9009769
  # which also has it in "notes" but with no type and no other content <notes> but a <title> of Data Availability
  # catches most of https://www.ncbi.nlm.nih.gov/books/NBK541158/
  pmcid ?= @params.statement ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  refresh ?= @refresh
  verbose ?= @params.verbose
  pres = []
  posts = []
  splits = []
  tags = []
  statements = []
  if pmcid
    pmcid = 'PMC' + (pmcid + '').toLowerCase().replace('pmc', '')
    if ft = await @src.epmc.xml pmcid, rec, refresh
      sstr = ''
      for split in ['"data', '>Data', '>Availab', '>data', '>Code', '>code']
        try
          if ft.includes split
            splits.push split
            pre = ''
            splits = ft.split split
            while part = splits.shift()
              if not pre
                pre = part
              else
                pres.push pre.slice -1000
                tag = pre.split('<').pop().split('>')[0].split(' ')[0]
                tags.push tag
                post = (if split.startsWith('"') then part.split(/\>(.*)/s)[1] else if part.startsWith('il') or part.startsWith('l') then 'Availab' else 'Data') + part #  if part.substr(0,6).includes('ode') then 'Code' else
                posts.push post.slice 0, 1000
                if post.includes('</' + tag) and post.indexOf('</' + tag) < 40
                  ps = pre.split '<'
                  nt = ps[ps.length-2].split('>')[0].split(' ')[0]
                  if not nt.startsWith '/'
                    tag = nt
                psls = pre.split('<' + tag)
                splitter = '\n' + (psls.slice(0, psls.length-1)).pop().split('\n').pop() + '</' + tag
                if post.split('</' + tag)[0].includes '\n'
                  while not post.includes(splitter) and splits[0] #and splits[0].includes splitter
                    post += (if split.startsWith('>') then '>' else '') + (if splits[0].startsWith('il') or splits[0].startsWith('l') then 'Availab' else 'Data') +  splits.shift()
                post = post.split(splitter)[0]
                post = post.replace('</title>', '|TTT|').replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
                ppl = (pre+post).toLowerCase()
                if post.length > 20 and post.length < 3000 and (ppl.includes('availab') or ppl.includes('accessib')) and ((pre+post).toLowerCase().includes('data') or (pre+post).toLowerCase().includes('code'))
                  post = post.split('|TTT|')[1] if post.includes '|TTT|'
                  clean = (await @decode post.trim()).replace(/"/g, '').replace(/\s+/g, ' ')
                  clean = clean.replace('<title', '').replace('<p', '')
                  clean = clean.trim()
                  clo = clean.toLowerCase()
                  if clean.length > 20 and (clo.includes('data') or clo.includes('code') or clo.includes('availab') or clo.includes('accessib')) and not sstr.includes clo
                    sstr += clo
                    statements.push clean
                pre = ''
  if verbose
    return pmcid: pmcid, file: 'https://static.oa.works/epmc/fulltext/' + pmcid + '.xml', pres: pres, posts: posts, splits: splits, tags: tags, statements: statements, url: (if statements then await @src.epmc.statement.url(undefined, undefined, statements, refresh) else undefined)
  else
    return if statements.length then statements else undefined

P.src.epmc.statement.url = (pmcid, rec, statements, refresh) ->
  statements ?= await @src.epmc.statement pmcid, rec, refresh
  res = []
  for das in (statements ? [])
    if das.includes('http') or das.includes '10.'
      dau = if das.includes('http') then 'http' + das.split('http')[1].split(' ')[0] else '10.' + das.split('10.')[1].split(' ')[0]
      if dau.length > 10 and dau.includes '/'
        dau = dau.toLowerCase()
        dau = dau.split(')')[0].replace('(', '') if dau.includes(')') and (das.includes('(h') or das.includes('(10'))
        dau = dau.slice(0, -1) if dau.endsWith('.')
        res.push(dau) if dau not in res
  return if res.length then res else undefined


'''P.src.epmc.das = (pmcid, verbose) -> # restrict to report/works records if pmcid is directly provided?
  max = pmcid ? @params.das ? 100 # ['PMC9722710', 'PMC8012878', 'PMC6198754'] # multiples PMC8012878. code? PMC6198754. Another example for something? was PMC9682356
  max = max.split(',') if typeof max is 'string'
  verbose ?= @params.verbose
  res = total: 0, files: 0, data: 0, available: 0, statement: 0, close: 0, closer: 0, prep: 0, das: 0, records: []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', '(PMCID:' + (if typeof max is 'number' then '*' else max.join(' OR PMCID:')) + ') AND orgs:Melinda', include: ['PMCID'], sort: 'PMCID.keyword': 'asc'
    break if typeof max is 'number' and res.records.length is max
    try ft = (await fs.readFile @S.directory + '/epmc/fulltext/' + rec.PMCID + '.xml').toString()
    if ft
      res.files += 1
      ex = pmcid: rec.PMCID, file: 'https://static.oa.works/epmc/fulltext/' + rec.PMCID + '.xml', splits: [], tag: [], pre: [], post: [], das: []
      ftl = ft.toLowerCase()
      if ftl.includes('>data') or ftl.includes('"data') or ftl.includes(' data') or ftl.includes('>code') or ftl.includes ' code'
        res.data += 1
        if ftl.includes 'availab'
          res.available += 1
          matches = ftl.match /.{100}[>" ](code|data|availab).{1,50}(availab|code|data).{200}/g
          if matches? and matches.length and matches[0].includes('data') and matches[0].includes('availab')
            res.close += 1
            ex.close = matches
          if ftl.includes 'statement'
            res.statement += 1
            matches = ftl.match /.{100}[>" ](code|data|availab|statement).{1,50}(availab|code|data|statement).{1,50}(availab|code|data|statement).{200}/g
            if matches? and matches.length and (matches[0].includes('data') or matches[0].includes('code')) and matches[0].includes('availab') and matches[0].includes('statement')
              res.closer += 1 
              ex.closer = matches 

      for split in ['"data', '>Data', '>Availab', '>data', '>Code', '>code']
        if ft.includes split
          ex.splits.push split
          pre = ''
          splits = ft.split split
          while part = splits.shift()
            if not pre
              pre = part
            else
              ex.pre.push pre.slice -1000
              tag = pre.split('<').pop().split('>')[0].split(' ')[0]
              post = (if split.startsWith('"') then part.split(/\>(.*)/s)[1] else if part.startsWith('il') or part.startsWith('l') then 'Availab' else 'Data') + part #  if part.substr(0,6).includes('ode') then 'Code' else
              ex.post.push post.slice 0, 1000
              if post.includes('</' + tag) and post.indexOf('</' + tag) < 40
                ps = pre.split '<'
                nt = ps[ps.length-2].split('>')[0].split(' ')[0]
                if not nt.startsWith '/'
                  #post = post.replace('</' + tag + '>', ': ').replace('::', ':').replace('.:', ':')
                  tag = nt
              ex.tag.push tag
              #splitter = '\n' + pre.split('<' + tag)[0].split('\n').pop().split('<')[0] + '</' + tag
              psls = pre.split('<' + tag)
              splitter = '\n' + (psls.slice(0, psls.length-1)).pop().split('\n').pop() + '</' + tag
              if post.split('</' + tag)[0].includes '\n'
                while not post.includes(splitter) and splits[0] #and splits[0].includes splitter
                  post += (if split.startsWith('>') then '>' else '') + (if splits[0].startsWith('il') or splits[0].startsWith('l') then 'Availab' else 'Data') +  splits.shift()
              post = post.split(splitter)[0]
              #post = post.split(/\>(.*)/s)[1]
              #post = post.replace('</', ': </').replace('::', ':').replace('.:', ':') if post.split('</').length > 2
              post = post.replace('</title>', '|TTT|').replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
              if post.length > 20 and post.length < 3000 and (pre+post).toLowerCase().includes('availab') and ((pre+post).toLowerCase().includes('data') or (pre+post).toLowerCase().includes('code'))
                post = post.split('|TTT|')[1] if post.includes '|TTT|'
                clean = (await @decode post.trim()).replace(/"/g, '').replace(/\s+/g, ' ')
                ex.das.push(clean) if clean not in ex.das
                delete ex.close
                delete ex.closer
              pre = ''

      res.records.push if verbose is false then {file: ex.file, das: ex.das} else ex
      res.das += 1 if ex.das.length
      res.prep += 1 if ex.pre and ex.post

  res.total = res.records.length
  res = {total: res.total, das: res.das, records: res.records} if verbose is false
  res = (if res.records.length and res.records[0].das.length then res.records[0].das[0] else false) if verbose is false and res.total is 1
  return res
'''

