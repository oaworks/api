

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
  else if not refresh and ne = await @src.epmc.notinepmc ident
    return
  else
    res = await @src.epmc.search 'DOI:' + ident
    if res.total
      if not res.data[0].doi
        res.data[0].doi = ident
        @waitUntil @src.epmc res.data[0]
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident.replace(/\//g, '_'), doi: ident
      return

P.src.epmc.pmid = (ident, refresh) ->
  refresh ?= @refresh if not ident
  ident ?= @params.pmid
  exists = await @src.epmc 'pmid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else if not refresh and ne = await @src.epmc.notinepmc ident
    return
  else
    res = await @src.epmc.search 'EXT_ID:' + ident + ' AND SRC:MED'
    if res.total
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident, pmid: ident
      return

P.src.epmc.pmc = (ident, refresh) ->
  refresh ?= @refresh if not ident
  ident ?= @params.pmc ? @params.pmcid
  ident = 'PMC' + ident.toLowerCase().replace 'pmc', ''
  exists = await @src.epmc 'pmcid:"' + ident + '"'
  if exists?.hits?.total
    return exists.hits.hits[0]._source
  else if not refresh and ne = await @src.epmc.notinepmc ident
    return
  else
    res = await @src.epmc.search 'PMCID:' + ident
    if res.total
      return res.data[0]
    else
      await @src.epmc.notinepmc id: ident, pmcid: ident
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
    rec = await @src.epmc.pmc pmcid
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
          fulltext = await @src.epmc.xml pmcid, rec
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
        await @sleep 150 # without timeout threw rate limit error on ncbi and ebi - this does not guarantee it because other calls could be made, but is a quick fix
        # try ncbi first as it is faster but it does not have everything in epmc - however when present the xml files are the same
        url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=' + pmcid
        ft = await @fetch url
        if (typeof ft isnt 'string' or not ft.length) and rec? # if it is in epmc, can try getting from there instead
          url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML'
          ft = await @fetch url
        if typeof ft is 'string' and ft.length
          try await fs.writeFile '/home/cloo/static/epmc/fulltext/' + pmcid + '.xml', ft
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





P.src.epmc.statement = (pmcid, rec) ->
  pmcid ?= @params.statement ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  if pmcid
    pmcid = 'PMC' + (pmcid + '').toLowerCase().replace('pmc', '')
    if xml = await @src.epmc.xml pmcid, rec
      # because of xml parsing issues with embedded html in pmc xml, just regex it out if present
      # pubmed data does not hold corresponding statements to pmc, but the pmc records from ncbi do contain them as they are the same as fulltext records from epmc
      # see <notes notes-type="data-availability"> in
      # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
      # or <custom-meta id="data-availability"> in 
      # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9009769
      # which also has it in "notes" but with no type and no other content <notes> but a <title> of Data Availability
      # catches most of https://www.ncbi.nlm.nih.gov/books/NBK541158/
      statement = ''
      strs = []
      if xml.includes 'type="data-availability">'
        statement = xml.split('type="data-availability">')[1].split('</sec>')[0].split('</notes>')[0]
        statement = statement.split('<title>').pop().split('</title')[0] if statement.includes '<title>'
      else if xml.includes 'id="data-availability"'
        statement = xml.split('id="data-availability"')[1]
        statement = statement.split('meta-value>')[1].split(',')[0] if statement.includes 'meta-value'
      if not statement and xml.includes '<notes>'
        for ps in xml.split '<notes>'
          psl = ps.toLowerCase()
          if psl.includes('data availability') or psl.includes('data accessibility') or psl.includes 'supporting data'
            statement = ps.split('</title>')[1] if ps.includes '</title>'
            statement = statement.split('</notes>')[0]
            break
      # if still no statement could look in other fields, but they mostly appear in notes and are of more certain quality when they do
      #statement = '' if statement.includes '<def-item' # seem to be more junk in these
      if statement
        statement = statement.split('<list-item').pop().split('>').pop() if statement.includes '<list-item'
        # most examples so far are a statement paragraph with zero or one url...
        statement = statement.replace(/<[ap].*?>/gi, '').replace(/<\/[ap]>/gi, '').replace(/<xref.*?>/gi, '').replace(/<\/xref>/gi, '').replace(/<ext.*?>/gi, '').replace(/<\/ext.*?>/gi, '').replace(/<br>/gi, '').replace(/\n/g, '').split('</')[0].trim()
        return statement if statement.length > 10 # hard to be a good statement if shorter than this
  return

P.src.epmc.dass = ->
  # what about code availability statements without data availability e.g. PMC6198754
  max = @params.dass ? 1
  res = []
  had = 0
  fl = 0
  prep = 0
  saysdata = 0
  saysavail = 0
  saysstate = 0
  daclose = 0
  dasclose = 0
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'PMCID:PMC9722710 AND orgs:Melinda', include: ['PMCID'] #, sort: 'PMCID': 'asc'
    break if res.length is max
    try ft = (await fs.readFile '/home/cloo/static/epmc/fulltext/' + rec.PMCID + '.xml').toString()
    if ft
      fl += 1
      ex = pmcid: rec.PMCID # catch multiple relevant statements like in PMC8012878, or PMC9722710 where there are sec within sec all part of the statement (and after an earlier false data match)
      ftl = ft.toLowerCase()
      if ftl.includes('>data') or ftl.includes('"data') or ftl.includes ' data'
        saysdata += 1
        if ftl.includes 'availab'
          saysavail += 1
          matches = ftl.match /.{100}[>" ](data|availab).{1,50}(availab|data).{200}/g
          if matches? and matches.length and matches[0].includes('data') and matches[0].includes('availab')
            daclose += 1
            ex.close = matches[0]
            ex.index = matches.index
          if ftl.includes 'statement'
            saysstate += 1
            matches = ftl.match /.{100}[>" ](data|availab|statement).{1,50}(availab|data|statement).{1,50}(availab|data|statement).{200}/g
            if matches? and matches.length and smatches[0].includes('data') and matches[0].includes('availab') and matches[0].includes('statement')
              dasclose += 1 
              ex.closer = matches[0] 
              ex.index = matches.index
      if ft.includes '"data'
        [pre, post] = ft.split '"data'
        ex.pre = pre.slice -100
        ex.post = post.slice 0, 1000
        ex.tag = pre.split('<').pop().split('>')[0].split(' ')[0]
        post = post.split('</' + ex.tag)[0]
        post = post.split(/\>(.*)/s)[1]
        post = post.replace('</', ': </').replace('::', ':').replace('.:', ':') if post.split('</').length > 2
        post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
        ex.das = (await @decode post.trim()).replace(/"/g, '').replace(/\s+/g, ' ') if post.length > 20 and post.length < 1000 and (ex.pre+post).toLowerCase().includes('availab') and (ex.pre+post).toLowerCase().includes('data')
      if not ex.das and (ft.includes('>Data') or ft.includes('>Availab') or ft.includes('>data'))
        [pre, post] = ft.split(if ft.includes('>Data') then '>Data' else if ft.includes('>Availab') then '>Availab' else '>data')
        ex.pre = pre.slice -100
        ex.post = post.slice 0, 1000
        post = (if post.startsWith('il') or post.startsWith('l') then 'Availab' else 'Data ') + post
        ex.tag = pre.split('<').pop().split(' ')[0]
        if post.indexOf('</' + ex.tag) < 40
          post = post.replace('</' + ex.tag + '>', ': ').replace('::', ':').replace('.:', ':')
          ps = pre.split '<'
          ex.tag = ps[ps.length-2].split(' ')[0]
        post = post.split('</' + ex.tag)[0]
        post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
        ex.das = (await @decode post.trim()).replace(/"/g, '').replace(/\s+/g, ' ') if post.length > 20 and post.length < 1000 and (ex.pre+post).toLowerCase().includes('availab') and (ex.pre+post).toLowerCase().includes('data')
      res.push(ex) #pmcid: ex.pmcid, das: ex.das) #if ex.das
      had += 1 if ex.das
      prep += 1 if ex.pre and ex.post
  return total: res.length, files: fl, data: saysdata, available: saysavail, statement: saysstate, close: daclose, closer: dasclose, index: -1, prep: prep, das: had, records: res



P.src.epmc.das = (pmcid, verbose) -> # restrict to report/works records if pmcid is directly provided?
  max = pmcid ? @params.das ? 100 # ['PMC9722710', 'PMC8012878', 'PMC6198754'] # multiples PMC8012878. code? PMC6198754. Another example for something? was PMC9682356
  max = max.split(',') if typeof max is 'string'
  verbose ?= @params.verbose
  res = total: 0, files: 0, data: 0, available: 0, statement: 0, close: 0, closer: 0, prep: 0, das: 0, records: []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', '(PMCID:' + (if typeof max is 'number' then '*' else max.join(' OR PMCID:')) + ') AND orgs:Melinda', include: ['PMCID'], sort: 'PMCID.keyword': 'asc'
    break if typeof max is 'number' and res.records.length is max
    try ft = (await fs.readFile '/home/cloo/static/epmc/fulltext/' + rec.PMCID + '.xml').toString()
    if ft
      res.files += 1
      ex = pmcid: rec.PMCID, file: 'https://static.oa.works/epmc/fulltext/' + rec.PMCID + '.xml', splits: [], tag: [], pre: [], post: [], das: []
      ftl = ft.toLowerCase()
      if ftl.includes('>data') or ftl.includes('"data') or ftl.includes ' data'
        res.data += 1
        if ftl.includes 'availab'
          res.available += 1
          matches = ftl.match /.{100}[>" ](data|availab).{1,50}(availab|data).{200}/g
          if matches? and matches.length and matches[0].includes('data') and matches[0].includes('availab')
            res.close += 1
            ex.close = matches
          if ftl.includes 'statement'
            res.statement += 1
            matches = ftl.match /.{100}[>" ](data|availab|statement).{1,50}(availab|data|statement).{1,50}(availab|data|statement).{200}/g
            if matches? and matches.length and matches[0].includes('data') and matches[0].includes('availab') and matches[0].includes('statement')
              res.closer += 1 
              ex.closer = matches 

      for split in ['"data', '>Data', '>Availab', '>data']
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
              post = if split.startsWith('"') then part.split(/\>(.*)/s)[1] else (if part.startsWith('il') or part.startsWith('l') then 'Availab' else 'Data') + part
              ex.post.push post.slice 0, 1000
              if post.includes('</' + tag) and post.indexOf('</' + tag) < 40
                ps = pre.split '<'
                nt = ps[ps.length-2].split('>')[0].split(' ')[0]
                if not nt.startsWith '/'
                  #post = post.replace('</' + tag + '>', ': ').replace('::', ':').replace('.:', ':')
                  tag = nt
              ex.tag.push tag
              splitter = '\n' + pre.split('<' + tag)[0].split('\n').pop().split('<')[0] + '</' + tag
              if post.split('</' + tag)[0].includes '\n'
                while not post.includes(splitter) and splits[0] #and splits[0].includes splitter
                  post += (if split.startsWith('>') then '>' else '') + (if splits[0].startsWith('il') or splits[0].startsWith('l') then 'Availab' else 'Data') +  splits.shift()
              post = post.split(splitter)[0]
              #post = post.split(/\>(.*)/s)[1]
              #post = post.replace('</', ': </').replace('::', ':').replace('.:', ':') if post.split('</').length > 2
              post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace /(<([^>]+)>)/ig, ''
              if post.length > 20 and post.length < 3000 and (pre+post).toLowerCase().includes('availab') and (pre+post).toLowerCase().includes('data')
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
