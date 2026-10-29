

# Europe PMC client
# https://europepmc.org/RestfulWebService
# https://www.ebi.ac.uk/europepmc/webservices/rest/search/
# https://europepmc.org/Help#fieldsearch

# EBI rate limit appears to be 10r/s and 500/min. So 8r/s would do.
# https://groups.google.com/a/ebi.ac.uk/g/epmc-webservices/c/x3PLL09mels/m/0CNRHdbfAwAJ

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
  # removed sort_date:y from query due to https://github.com/oaworks/discussion/issues/3738#issuecomment-4134013512
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  url += '&cursorMark=' + from if from?
  ret = {}
  try
    res = await @fetch url, rate: ['ebi', 8]
    ret.total = res.hitCount
    ret.data = res.resultList?.result ? []
    ret.cursor = res.nextCursorMark
  if ret.data?.length
    @waitUntil @src.epmc ret.data
  return ret

P.src.epmc.doi = (ident, refresh, year) ->
  refresh ?= @refresh if not ident
  ident ?= @params.doi
  if ident and ident.startsWith('10.') and ident.split('/').length >= 2 and ident.split(' ').length is 1
    exists = await @src.epmc 'doi:"' + ident + '"'
    ly = parseInt((await @date()).split('-')[0]) - 3 # don't check again if already more than 3 years old, it is unlikely to change or turn up
    if exists?.hits?.total and (rt = exists.hits.hits[0]._source)
      yr = ((rt.pubYear ? rt.journalInfo.yearOfPublication ? rt.firstPublicationDate ? '') + '').split('-')[0]
      if typeof yr is 'string' and yr.length is 4 and parseInt(yr) <= ly
        return rt
    if not refresh and (ne = await @src.epmc.notinepmc ident) and (ne.year ? ly) < ly and Date.now() - (ne.checkedAt ? 0) < 2419200000
      return
    else
      res = await @src.epmc.search 'DOI:' + ident
      if res.total
        if not res.data[0].doi
          res.data[0].doi = ident
          @waitUntil @src.epmc res.data[0]
        return res.data[0]
      else if res.total? # because on 21/08/2025 the whole API disappeared - we don't want to record that as not being in
        await @src.epmc.notinepmc id: ident.replace(/\//g, '_'), doi: ident, year: year, checkedAt: Date.now()
  return

P.src.epmc.pmc = (ident, refresh, year) ->
  refresh ?= @refresh if not ident
  ident ?= @params.pmc ? @params.pmcid
  if ident
    ident = ident.toLowerCase().replace('pmc', '') if typeof ident is 'string'
    if ident and (typeof ident is 'number' or (typeof parseInt(ident) is 'number' and ident.split('.').length is 1 and ident.split(' ').length is 1))
      ident = 'PMC' + ident
      exists = await @src.epmc 'pmcid:"' + ident + '"'
      ly = parseInt((await @date()).split('-')[0]) - 3 # don't check again if already more than 3 years old, it is unlikely to change or turn up
      if exists?.hits?.total and (rt = exists.hits.hits[0]._source)
        yr = ((rt.pubYear ? rt.journalInfo.yearOfPublication ? rt.firstPublicationDate ? '') + '').split('-')[0]
        if typeof yr is 'string' and yr.length is 4 and parseInt(yr) <= ly
          return rt
      if not refresh and (ne = await @src.epmc.notinepmc ident) and (ne.year ? ly) < ly and Date.now() - (ne.checkedAt ? 0) < 2419200000 # don't check again within 28 days
        return
      else
        res = await @src.epmc.search 'PMCID:' + ident
        if res.total
          return res.data[0]
        else if res.total? # because on 21/08/2025 the whole API disappeared - we don't want to record that as not being in
          await @src.epmc.notinepmc id: ident, pmcid: ident, year: year, checkedAt: Date.now()
  return

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
        if not lics?.licence? and typeof fulltext is 'string' and fulltext.includes '<permissions>'
          lics = licence: 'non-standard-licence', source: 'epmc_xml_permissions'
  
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
    if not refresh
      try
        ft = await fs.readFile @S.directory + '/epmc/fulltext/' + pmcid + '.xml'
        return ft.toString()

    if rec?
      ft = await @fetch 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML', rate: ['ebi', 8]
    if typeof ft isnt 'string' or not ft.length
      ft = await @fetch 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=' + pmcid, rate: ['ncbi', 3]

    if typeof ft is 'string' and ft.length
      try await fs.writeFile @S.directory + '/epmc/fulltext/' + pmcid + '.xml', ft
      return ft

  return



P.src.epmc.submitted = (pmcid, rec, refresh) ->
  pmcid ?= @params.submitted ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  refresh ?= @refresh
  if pmcid
    pmcid = 'PMC' + (pmcid + '').toLowerCase().replace('pmc', '')
    try
      if ft = await @src.epmc.xml pmcid, rec, refresh
        ft = ft.split('<article-meta')[1].split('/article-meta')[0].split('date-type="received"')[1].split('</date')[0]
        if ft.includes '<year'
          yt = ft.split('<year')[1].split('</year>')[0].split('>').pop()
          try
            yt += '-' + ft.split('<month')[1].split('</month>')[0].split('>').pop()
          catch
            yt += '-01'
          try
            yt += '-' + ft.split('<day')[1].split('</day>')[0].split('>').pop()
          catch
            yt += '-01'
          ft = yt
        else if ft.includes '<'
          ft = ft.replace('>', '').split('<')[0]
        else
          ft = ft.split('"')[1]
        ft = ft.replace('\n', '').trim()
        if ft
          if ft.length isnt 10
            nft = []
            nft.push(if ftp.length is 1 then '0' + ftp else ftp) for ftp in ft.split('T')[0].split '-'
            ft = nft.join '-'
          return ft
  return


P.src.epmc.statement = (pmcid, rec, refresh, verbose) ->
  pmcid ?= @params.statement ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  if pmcid and pmcid.startsWith '10.'
    rec ?= await @src.epmc.doi pmcid, refresh
    pmcid = undefined
  pmcid ?= rec?.pmcid
  refresh ?= @refresh
  verbose ?= @params.verbose
  pres = []
  posts = []
  splitted = []
  tags = []
  statements = []
  if pmcid and pmcid.toLowerCase().startsWith 'pmc'
    pmcid = 'PMC' + (pmcid + '').toLowerCase().replace('pmc', '')
    if ft = await @src.epmc.xml pmcid, rec, refresh
      ft = (ft.split('<ref-list')[0] + ft.split('/ref-list>').pop())
      sstr = ''
      for split in ['"data', '>Data', '>Research data', '>Availab', '>data', '>Code', '>code']
        try
          if ft.includes split
            splitted.push split
            splits = ft.split split
            pre = splits.shift()
            while pre and part = splits.shift()
              pres.push pre.slice -1000
              tag = pre.split('<').pop().split('>')[0].split(' ')[0].replace('/', '')
              tag = pre.split('</' + tag + '>').pop().split('><' + tag)[0].split('<').pop().split('>')[0].split(' ')[0].replace('/', '') if not split.startsWith('"') and pre.endsWith '><' + tag
              post = (if split.startsWith('"') then part.split(/\>(.*)/s)[1] else if part.startsWith('il') or part.startsWith('l') then 'Availab' else if split.startsWith('>Research data') then 'Research data' else 'Data') + part
              posts.push post.slice 0, 1000
              if post.includes('</' + tag + '>') and post.indexOf('</' + tag + '>') < 40
                try
                  ps = pre.split '<'
                  nt = ps[ps.length-2].split('>')[0].split(' ')[0]
                  tag = nt if not nt.startsWith '/'
              tags.push tag
              psls = pre.split('<' + tag)
              if psls.includes '\n '
                splitter = '\n' + (psls.slice(0, psls.length-1)).pop().split('\n').pop() + '</' + tag + '>'
              else
                splitter = '</' + tag + '>'
              if post.split('</' + tag + '>')[0].includes '\n'
                while not post.includes(splitter) and splits.length
                  post += (if split.startsWith('>') then '>' else '') + (if splits[0].startsWith('il') or splits[0].startsWith('l') then 'Availab' else 'Data') +  splits.shift()
              post = post.split(splitter)[0]
              post = post.replace('</title>', '|TTT|').replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
              ppl = (pres[pres.length-1].split(splitter).pop()+post).toLowerCase()
              if post.length > 20 and post.length < 3000 and (ppl.includes('availab') or ppl.includes('accessib') or ppl.includes('data shar') or ppl.includes('research data')) and (ppl.includes('data') or ppl.includes('code'))
                [ttl, post] = post.split '|TTT|'
                post ?= ttl
                clean = (await @decode post.trim()).replace(/"/g, '').replace(/\s+/g, ' ')
                clean = clean.replace('<title', '').replace('<p', '')
                clean = clean.trim()
                clo = clean.toLowerCase()
                ttlclo = ttl.toLowerCase() + clo
                if clean.length > 1 and (ttlclo.includes('data') or ttlclo.includes('code') or ttlclo.includes('availab') or ttlclo.includes('accessib')) and not sstr.includes clo
                  sstr += clo
                  statements.push clean
              pre = part
  if verbose
    return pmcid: pmcid, file: (@S.static?.url ? 'https://static.oa.works') + '/epmc/fulltext/' + pmcid + '.xml', pres: pres, posts: posts, splits: splitted, tags: tags, statements: statements, url: (if statements then await @src.epmc.statement.url(undefined, undefined, statements, refresh) else undefined)
  else
    return if statements.length then statements else undefined

P.src.epmc.statement.url = (pmcid, rec, statements, refresh) ->
  statements ?= await @src.epmc.statement pmcid, rec, refresh
  res = []
  _splurl = (das, s) =>
    daus = das.split(s)
    daus.shift()
    for dau in daus
      dau = s + dau.split(' ')[0]
      if dau.length > 10 and dau.includes '/'
        dau = dau.toLowerCase()
        dau = dau.split(')')[0].replace('(', '') if dau.includes(')') and (das.includes('(h') or das.includes('(10'))
        dau = dau.slice(0, -1) if dau.endsWith('.')
        dau = 'https://doi.org/' + dau if dau.startsWith '10.'
        res.push(dau) if dau not in res
  for d in (statements ? [])
    await _splurl(d, 'http') if d.includes 'http'
    await _splurl(d, '10.') if d.includes '10.'
  return if res.length then res else undefined



