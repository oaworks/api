
P.src.rs = _index: true, _prefix: false
P.src.rs.retrieve = (since) ->
  max = @params.max
  retrieve = @params.retrieve
  save = @params.save
  refresh = @params.refresh
  plus = @params.plus ? true
  limit = @params.limit ? 500 #1000 # 100 worked fine but was of course slow, around 5 or 6 days to get all relevant records
  empty = @params.empty
  await @src.rs('') if empty
  q = @params.q ? 'prefix.keyword:"10.21203" AND DOI:"v1" AND type.keyword:"posted-content"'
  opts = include: ['DOI'], scroll: '30m'
  # TODO see changes function below, this could actually be done by pulling from RS, but for now we do by searching our crossref.
  if since and (not @params.q or @params.since)
    if typeof since is 'string' and since.includes ' ' # RS uses createdAt dates like 2025-06-11 05:08:20
      since = await @epoch since.replace ' ', 'T'
    q += ' AND created.timestamp:>' + since
    #opts.sort = 'created.timestamp:desc'
  started = Date.now()
  rsapi = 'https://www.researchsquare.com/api/' # with search/ or article/
  res = started: started, ended: undefined, took: undefined, limit: limit, empty: empty, since: since, q: q, expected: 0, total: 0, refresh: refresh, existed: undefined, existing: 0, local: 0, tried: 0, retrieved: 0, max: max, save: save, saved: 0, confirm: 0
  res.expected = await @src.crossref.works.count q
  res.existed = await @report.works.count 'DOI:"10.21203" AND DOI:"v1"'
  batch = []
  for await rec from @index._for 'src_crossref_works', q, opts
    break if (max and res.tried >= max) or (retrieve and res.tried >= retrieve)
    res.total += 1
    rsid = rec.DOI.split('.').pop()
    rsid = 'rs-' + rsid if not rsid.startsWith 'rs-' # RS API expects rs- prefix but some do not have them
    rsurl = rsapi + 'article/' + rsid
    if res.total % 100 is 0
      res.took = Date.now() - started
      console.log rsurl
      console.log res
    else if max <= 10
      console.log rsurl
    if not refresh and not plus and exists = await @report.works rec.DOI
      console.log(rec.DOI, 'already exists in report/works') if max <= 10
      res.existing += 1
    else if not refresh and not empty and local = await @src.rs 'identity.keyword:"' + rsid + '"', 1 # rec.DOI
      console.log(rec.DOI, 'already exists in local RS') if max <= 10
      res.local += 1
    else 
      res.tried += 1
      if article = await @fetch rsurl
        await @sleep res.limit
        if article.identity is rsid.split('/')[0]
          try
            article = JSON.parse JSON.stringify(article).replace /""/g, 'null' # research square defaults any key to "" but that causes type matching issues so null them
          catch err
            console.log article
            console.log err, typeof article
          for k in ['nonDraftVersions'] # fix things we see type issues with - in this case the editorialEvents.content is sometimes 0 and sometimes a string
            article[k] = JSON.stringify article[k]
          for ok in ['declarations'] # and some things need to be an object but may be an empty string (or something)
            delete article[ok] if typeof article[ok] isnt 'object'
          delete article.updatedAt if article.updatedAt? and not article.updatedAt # some dates exist but seem to perhaps be an empty string, causing it to not index as a date
          res.retrieved += 1
          article.DOI = rec.DOI.toLowerCase()
          article._id = article.DOI.replace /\//g, '_'
          batch.push article
    if batch.length >= 500
      await @src.rs(batch) if save isnt false
      res.saved += batch.length
      batch = []
  if batch.length
    await @src.rs(batch) if save isnt false
    res.saved += batch.length
    batch = []
  await @sleep 5000
  res.confirm = await @src.rs.count()
  res.ended = Date.now()
  res.took = res.ended - started
  console.log res
  await @mail to: @S.log.logs, subject: 'Report RS retrieved ' + res.retrieved, text: JSON.stringify res, '', 2
  return res
P.src.rs.retrieve._log = false
P.src.rs.retrieve._bg = true
P.src.rs.retrieve._async = true
P.src.rs.retrieve._auth = '@oa.works'

P.src.rs.changes = (since) ->
  # can get from RS API since a date using
  # https://www.researchsquare.com/api/search?postedAfter=2025-06-10
  # and would need to paginate - but for now, just triggering based on our local crossref index
  since ?= @params.changes ? @params.since
  if not since
    last = await @src.rs '*', sort: 'createdAt.keyword:desc', size: 1
    since = last.createdAt
  console.log 'Running report RS retrieve for new crossref records since', since
  res = await @src.rs.retrieve since
  return res
P.src.rs.changes._log = false
P.src.rs.changes._bg = true
P.src.rs.changes._async = true
P.src.rs.changes._auth = '@oa.works'
  


P.src.rs.check = ->
  res = rows: 0, checked: 0, failed: [], found: 0, not_found: [], dups: 0, ids: []
  max = @params.max
  for doi in dois = (await fs.readFile @S.static.folder + '/rscheck.csv', 'utf8').split '\n'
    break if max and res.rows >= max
    res.rows += 1
    if doi
      id = doi.replace('10.21203/', '').split('/v')[0].split('.').pop()
      id = 'rs-' + id if id and not id.startsWith 'rs-'
      doid = doi + '_(' + id + ')'
      console.log(res.rows, doi, id) if max or res.rows % 50 is 0
      if id
        if doid in res.ids
          res.dups += 1
        else
          res.ids.push doid
        res.checked += 1
        exists = false
        if exists = await @src.rs 'identity.keyword:"' + id + '"'
          console.log exists.identity, 'exists in report/rs'
          res.found += 1
        else
          res.not_found.push '(' + res.rows + ')_' + doid
          console.log doid, 'not found in report/rs'
      else
        res.failed.push '(' + res.rows + ')_' + doid
  return res
