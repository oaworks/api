
try S.report = JSON.parse SECRETS_REPORT
S.report ?= {}

P.report = () -> return 'OA.Works report'
P.report.works = _index: true



P.report.suggestables = _index: true
P.report.suggestions = ->
  org = @params.org
  field = @params.field
  if org and field
    res = []
    fieldname = field.toLowerCase().replace('.keyword','').replace /[^a-z0-9]/g, '' # sort on fieldname may require .keyword when field is textual
    q = (@params.q ? '*').toString()
    max = @params.max ? @params.size ? 1000
    exact = @params.exact ? true
    keyword = if q is '*' then false else @params.keyword ? true
    wildcard = if q is '*' then false else @params.wildcard ? true
    suffix = if not wildcard then false else @params.suffix ? true
    prefix = if not wildcard then false else @params.prefix ? true
    fuzzy = @params.fuzzy ? true
    sort = @params.sort # asc or desc, or fieldname:asc etc
    sort = fieldname + ':' + sort if sort and not sort.includes ':'
    _find = (fq) =>
      try
        console.log fq
        for await rec from @index._for 'paradigm' + (if S.dev then '_b' else '') + '_report_suggestables', 'org.keyword:"' + org + '" AND field.keyword:"' + field + '" AND ' + fq, max: max, sort: sort
          res.push(rec[fieldname]) if rec[fieldname] and rec[fieldname] not in res
    cq = q.replace /[\,\.\!\;\?\/\:\-]/g, ' '
    console.log cq
    if exact
      await _find(fieldname + '.keyword:' + q) if keyword
      await _find(fieldname + ':' + cq.split(' ').join(' AND ' + fieldname + ':')) if not res.length
    if wildcard
      await _find(fieldname + ':' + cq.split(' ').join(' AND ' + fieldname + ':') + '*') if not res.length or suffix
      await _find(fieldname + ':' + cq.split(' ').join('~ AND ' + fieldname + ':') + '~') if not res.length and fuzzy
      await _find((fieldname + ':' + cq.split(' ').join(' AND ' + fieldname + ':') + '*').replace(/:([^:]*)$/, ':*$1')) if not res.length and prefix
    return res
  else
    res = total: await @report.suggestables.count()
    res.options = org: 'Org name (required)', field: 'Field name (required)', q: 'search term, default *', size: 'How many to return, default 1000', exact: 'Do exact match, default true, will try matching an entire keyword (Gates Foundation), then tries partials (Foundation)', keyword: 'Default true, if false then exact match will not try keyword first', wildcard: 'Default true, enables wildcard searches after exact searches', suffix: 'The default wildcard search, appends * to the query, unless set to false', fuzzy: 'Default false, if true will try fuzzy match ONLY if previous searches fail (slower)', prefix: 'Default false, if true will try *query* wildcard match ONLY if previous searches fail (slowest)'
    # sort: 'Order, asc/desc, default asc', 
    res.field = {}
    res.field[f.term] = f.count for f in await @report.suggestables.terms 'field'      
    res.org = await @report.suggestables.terms 'org'
    for o in res.org
      o.works = await @report.works.count 'orgs.keyword:"' + o.term + '" AND NOT orgs_by_query:*'
      o.field = {}
      o.field[f.term] = f.count for f in await @report.suggestables.terms 'field', 'org.keyword:"' + o.term + '"'
    return res
P.report.suggestify = (orgs, fields, clear) ->
  started = Date.now()
  orgs = @params.orgs.split(',') if @params.orgs
  orgs ?= ['Gates Foundation', 'Robert Wood Johnson Foundation', 'Michael J. Fox Foundation', 'Wellcome Trust', 'Templeton World Charity Foundation', 'Howard Hughes Medical Institute', 'Parkinson’s Progression Markers Initiative']
  fields = @params.fields.split(',') if @params.fields
  fields ?= ['journal', 'authorships.institutions.display_name', 'authorships.author.orcid', 'authorships.author.display_name', 'concepts.display_name', 'supplements.publisher_simple', 'supplements.host_venue.display_name', 'supplements.grantid__bmgf', 'supplements.program__bmgf', 'supplements.grantid__rwjf', 'supplements.program__rwjf', 'supplements.grantid__mjff', 'supplements.grantid__twcf', 'supplements.program__twcf']
  fields = (f.replace('.keyword', '') for f in fields)
  # an example, PPMI for authorships.author.display_name, with only about 7.5k records has over 80k author name strings (some could be dups)
  #merge = @params.merge ? false # it takes 90 minutes to build Gates with merging. 30 minutes without
  batch = []
  total = 0
  clear ?= @params.clear ? false
  if clear is true
    if @params.orgs and not @params.fields
      for o in orgs
        console.log 'clearing suggestables for org', o
        bd = []
        for await rec from @index._for 'paradigm' + (if S.dev then '_b' else '') + '_report_suggestables', 'org.keyword:"' + o + '"', include: ['_id']
          bd.push rec._id
        await @index._bulk 'paradigm' + (if S.dev then '_b' else '') + '_report_suggestables', bd, 'delete'
    else
      await @report.suggestables ''

  console.log 'suggestify starting for orgs and fields:'
  console.log orgs
  console.log fields

  for o in orgs
    console.log 'building suggestables for org', o
    uniques = {}
    batches = {}
    for await rec from @index._for 'paradigm' + (if S.dev then '_b' else '') + '_report_works', 'orgs.keyword:"' + o + '" AND NOT orgs_by_query:*', include: fields
      for field in fields
        vals = await @dot rec, field
        vals = [vals] unless Array.isArray vals
        uniques[field] ?= []
        batches[field] ?= []
        for v in vals
          if v and (v = v.replace('https://orcid.org/', '')) and v not in uniques[field]
            uniques[field].push v
            vr = org: o, field: field
            vr[field.toLowerCase().replace /[^a-z0-9]/g, ''] = v
            batches[field].push vr
    for b of batches
      if batches[b].length
        console.log 'suggestify saving batch', o, b, batches[b].length
        await @report.suggestables batches[b]
        total += batches[b].length
        console.log 'suggestify saved batch', o, b, batches[b].length, total

  console.log orgs
  console.log fields
  console.log 'suggestify total saved', total, 'in', (Date.now() - started)/1000, 'seconds'
  return total
P.report.suggestify._bg = true
P.report.suggestify._async = true
P.report.suggestify._log = false
P.report.suggestify._auth = '@oa.works'




P.report.chat = (prompt, role, id, text) ->
  pmcid = @params.pmcid
  if pmcid
    text = await @src.epmc.xml pmcid
    text = text.split('<ref-list>')[0].replace(/\n/g, ' ').replace(/(<([^>]+)>)/ig, '') if @params.xml isnt true
  prompt ?= @params.prompt ? 'Please return the data availability statement'
  prompt += ' of the following research article: ' + text if text
  role ?= @params.role ? 'You are a terse text and data mining extraction tool in the scientific research publishing field'
  if text
    return @src.openai.chat prompt, role, @params.model, @params.json
  else
    return {}

#P.report.chat._auth = '@oa.works'



_queue_batch = []
_queued_batch = []
_queue_batch_last = false
_do_batch = []
_done_batch = []
_processing_idents = []
_processing_errors = {}
_processing_orgs = {} # keep track of orgs that have been retrieved from index during processing to reduce lookups
_processed_batch = []
_processed_batch_last = false

P.report._handle_queue = ->
  _queue_batch_last = Date.now() if _queue_batch_last is false
  console.log 'handle queue checking for queued values to handle', _queue_batch.length, _queue_batch_last
  if _queue_batch.length > 3000 or (_queue_batch.length and Date.now() > (_queue_batch_last + 30000))
    console.log 'handle queue saving batch', _queue_batch.length
    batch = []
    while d = _queue_batch.shift()
      _queued_batch.shift()
      d.createdAt = Date.now()
      d._id ?= d.identifier.toLowerCase()
      batch.push d
      if batch.length >= 10000
        await @report.queued batch
        batch = []
    @report.queued(batch) if batch.length
    _queue_batch_last = Date.now()
  @report._handle_processed() if _processed_batch_last is false
  setTimeout @report._handle_queue, 5000

P.report._handle_processed = ->
  _processed_batch_last = Date.now() if _processed_batch_last is false
  if _processed_batch.length >= 3000 or (_processed_batch.length and Date.now() > (_processed_batch_last + 30000))
    console.log 'handle processed saving batch', _processed_batch.length
    pb = _processed_batch
    _processed_batch = [] # or a risk of deleting unsaved ones here
    db = _done_batch
    _done_batch = []
    @report.works pb # NOTE - if these are NOT run on separate worker processes (see below) there could be duplication here
    #await @index._bulk 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_queued', db, 'delete'
    await @report.queued(ddd, '') while ddd = db.shift()
    _processed_batch_last = Date.now()
  setTimeout @report._handle_processed, 5000

P.report.queued = _index: true #, _auth: '@oa.works'
P.report.queue = (idents, openalex, refresh, everything, action = 'default') -> # idents could be DOIs, openalex IDs or PMCIDs
  if @params.empty
    if typeof @params.empty is 'string'
      for await qp from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_queued', 'action.keyword:"' + @params.empty + '"'
        await @report.queued qp._id, ''
    else
      await @report.queued ''
  idents ?= @params.queue ? @params.doi ? @params.openalex ? @params.pmcid
  refresh ?= @refresh
  everything ?= @params.everything
  #try console.log _queue_batch_last
  #try console.log idents.length
  if _queue_batch_last is false
    @report._handle_queue() 
  if idents # can be list of DOI strings and/or openalex strings, or objects with DOI and/or openalex, plus optional refresh, everything, action
    for ident in (if not Array.isArray(idents) then [idents] else idents)
      try
        theid = if typeof ident is 'object' then (ident.ident ? ident.identifier ? ident.DOI ? ident.doi ? ident.openalex ? ident.pmcid) else ident
        theid = theid.replace('w', 'W') if theid.startsWith 'w'
        theid = theid.replace('pmc', 'PMC') if theid.startsWith 'pmc'
        if not theid.includes('10.') or theid = await @report.cleandoi theid
          theidl = theid.toLowerCase()
          if theid and typeof theid is 'string' and (theid.startsWith('10.') or theid.startsWith('W') or theid.startsWith('PMC')) and theidl not in _queued_batch and theidl not in _done_batch
            _queued_batch.push theidl
            rf = if typeof ident is 'object' and ident.refresh? then ident.refresh else (refresh ? inq?.refresh)
            rf = if rf is true then 0 else if rf is false then undefined else rf
            _queue_batch.push identifier: theid, refresh: rf, everything: (if typeof ident is 'object' and ident.everything? then ident.everything else (everything ? inq?.everything)), action: (if typeof ident is 'object' and ident.action? then ident.action else action)
  return queue: _queue_batch.length
P.report.queue._bg = true
P.report.queue._log = false
P.report.queue._auth = '@oa.works'

P.report._runqueue = (ident, qry, ord, mid) ->
  qry ?= 'action:"default"'
  ord ?= 'desc'
  if ident?
    qry = 'for requested identifier ' + ident
  else
    if not _do_batch.length
      if mid
        if mid is true
          earliest = (await @report.queued qry, size: 1, sort: createdAt: 'asc').createdAt
          mid = earliest + Math.floor ((await @report.queued qry, size: 1, sort: createdAt: 'desc').createdAt - earliest) / 2
          console.log 'queue midpoint', mid
        qry = '(' + qry + ') AND createdAt:' + (if ord is 'desc' then '<' else '>') + mid
      q = await @report.queued qry, size: 2000, sort: createdAt: ord
      if not q?.hits?.total and qry is 'action:"default"' #and (not @S.async_runner? or (await @keys(@S.async_runner)).length < 2) #isnt '*' # do anything if there are no specific ones to do
        console.log 'no queued records found for specified qry', qry, 'checking for any other queued records...'
        q = await @report.queued 'NOT action:*', size: 2000, sort: createdAt: ord
        qry = 'queried * as none for qry ' + qry
      if mid and q?.hits?.total and q.hits.total < 5000
        console.log 'not queueing on mid ' + ord + ' queue when only ' + q.hits.total + ' records to process, waiting 5s...'
        await @sleep 5000
      else if ord isnt 'desc' and q?.hits?.total and q.hits.total < 10000
        console.log 'not queueing on reverse ' + ord + ' queue when only ' + q.hits.total + ' records to process, waiting 5s...'
        await @sleep 5000
      else
        if not q?.hits?.total and not _queue_batch.length
          console.log 'no queued records to process, waiting 5s...'
          await @sleep 5000
        _do_batch.push(qd._source) for qd in (q?.hits?.hits ? []) when qd._source.identifier not in _processing_idents and qd._source.identifier not in _done_batch and qd._source.identifier not in _do_batch
    else
      qry = ''
    opts = _do_batch.shift()
    ident = opts?.identifier ? opts?.DOI
  console.log 'report run queue', _processing_idents.length, _do_batch.length #, qry, ident, opts, _done_batch.length, _processed_batch.length, _processing_idents
  if typeof ident is 'string' and (ident.startsWith('10.') or ident.startsWith('W') or ident.startsWith('PMC')) and ident not in _processing_idents and ident not in _done_batch
    await @sleep 10
    while _processing_idents.length >= 5
      await @sleep 500
    _processing_idents.push ident
    @report.works.process ident, undefined, opts?.refresh, opts?.everything, opts?.action, undefined, ident
  @report._handle_queue() if _queue_batch_last is false
  return true

# for each of the below, add a loop schedule to have them running - run them on SEPARATE worker processes, via settings
P.report._doqueue = -> return @report._runqueue()
P.report._doqueue._log = false
P.report._doqueue._bg = true

P.report._doreversequeue = -> return @report._runqueue undefined, undefined, 'asc'
P.report._doreversequeue._log = false
P.report._doreversequeue._bg = true


P.report.dev2live = (reverse) ->
  toalias = @params.toalias
  toalias += '' if typeof toalias is 'number'
  qry = if @params.org then 'orgs.keyword:"' + @params.org + '"' else @params.q
  if not reverse
    f = 'paradigm_b_report_works'
    t = 'paradigm_report_works'
  else
    f = 'paradigm_report_works'
    t = 'paradigm_b_report_works'
  if @params.clear
    await @index._send t, '', undefined, false, toalias
  counter = 0
  batch = []
  console.log 'report works running', (if reverse then 'live2dev' else 'dev2live'), f, t, toalias, qry
  for await rm from @index._for f, qry, scroll: '30m' # q, opts, prefix, alias
    counter += 1
    batch.push rm
    if batch.length is 50000
      console.log 'report works', (if reverse then 'live2dev' else 'dev2live'), f, t, toalias, counter
      await @index._bulk t, batch, undefined, undefined, false, toalias
      batch = []

  if batch.length
    console.log 'report works', (if reverse then 'live2dev' else 'dev2live'), f, t, toalias, counter, 'remaining', batch.length
    await @index._bulk t, batch, undefined, undefined, false, toalias
    batch = []

  console.log counter, 'report works', (if reverse then 'live2dev' else 'dev2live'), f, t, toalias, 'complete', (if qry then 'for query ' + qry else '')
  return counter
P.report.dev2live._async = true
P.report.dev2live._bg = true
P.report.dev2live._auth = '@oa.works'

P.report.live2dev = () ->
  return @report.dev2live true
P.report.live2dev._async = true
P.report.live2dev._bg = true
P.report.live2dev._auth = 'root'

P.report.oapolicy = _sheet: S.report.oapolicy_sheet, _format: (recs=[]) ->
  ready = []
  bs = 0
  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    nr = {}
    for h of rec
      if typeof rec[h] is 'string'
        rec[h] = rec[h].trim()
        if rec[h].toLowerCase() is 'true'
          rec[h] = true
        else if rec[h].toLowerCase() is 'false'
          rec[h] = false
        else if ((rec[h].startsWith('[') and rec[h].endsWith(']')) or (rec[h].startsWith('{') and rec[h].endsWith('}')))
          try
            rec[h] = JSON.parse rec[h]
          catch err
            console.log 'cant parse ' + h, rec[h], err
            bs += 1
        else if rec[h].includes ';'
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split ';'
      if rec[h]? and rec[h] isnt ''
        if h.includes '.'
          try @dot nr, h, rec[h]
        else
          nr[h] = rec[h]
    if JSON.stringify(nr) isnt '{}'
      #nr._id = nr.uid
      ready.push nr
  return if ready.length is 1 then ready[0] else ready

P.report.cleandoi = (doi) -> # 10.1002/1096-8628(20000717)93:2<110::aid-ajmg6>3.0.co;2-9 ? or 10.36108_njsa_0202_81(0210 ? or 10.12688_gatesopenres.13118.1)
  doi ?= @params.cleandoi ? @params.doi
  try doi = doi.split(',http')[0] # due to dirty data
  try doi = '10.' + doi.split('/10.')[1] if doi.startsWith 'http'
  try doi = doi.toLowerCase().replace('doi ', '') if doi.startsWith 'doi '
  try doi = doi.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').split(' ')[0].split('&')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim()
  try doi = doi.split('#')[0]
  try doi = doi.replace(/^\/+/, '') if doi.startsWith '/'
  try doi = doi.replace(/\/+$/, '') if doi.endsWith '/'
  try doi = doi.replace /#/g, '%23'
  try doi = doi.replace /\,$/, ''
  try doi = doi.replace /\.$/, ''
  try doi = doi.replace(/\)$/, '') if not doi.includes '(' # it seems brackets are pretty common in DOIs, but some of our sheet processing appends a close bracket without an open
  if typeof doi is 'string' and doi.startsWith('10.') and not doi.includes '@'
    return doi
  else
    return
P.report.cleandoi._log = false

_report_publishers = []
P.report.publishers = _sheet: '1M2s1KBycWI5j7SIfIY0mzfkRC4cYr0HoROP7MR6k3GU'

P.report.orgs = _sheet: S.report.orgs_sheet, _format: (recs=[], encrypt) ->
  ready = []
  bs = 0
  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    nr = {}
    for h of rec
      if typeof rec[h] is 'string'
        rec[h] = rec[h].trim()
        if rec[h].toLowerCase() is 'true'
          rec[h] = true
        else if rec[h].toLowerCase() is 'false'
          rec[h] = false
        else if ((rec[h].startsWith('[') and rec[h].endsWith(']')) or (rec[h].startsWith('{') and rec[h].endsWith('}')))
          try
            rec[h] = JSON.parse rec[h]
          catch err
            console.log 'cant parse ' + h, rec[h], err
            bs += 1
        else if rec[h].includes ';'
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split ';'
      if h.includes '.'
        try @dot nr, h, rec[h]
      else
        nr[h] = rec[h]
    if Array.isArray nr.sheets
      if encrypt isnt false
        for s in nr.sheets
          s.url = await @encrypt s.url
    else
      delete nr.sheets
    ready.push(nr) if JSON.stringify(nr) isnt '{}'
  return if ready.length is 1 then ready[0] else ready

P.report.orgs.orgkeys = _index: true, _auth: '@oa.works'
P.report.orgs.key = (org) ->
  org ?= @params.org
  return undefined if not org?
  org = org.toLowerCase()
  rec = await @report.orgs.orgkeys 'org.keyword:"' + org + '"', 1
  if not rec? or @refresh
    if rec?
      rec.lastRefreshedAt = await @epoch()
      try rec.lastRefreshedBy = @user.email
    else
      rec = org: org, createdAt: await @epoch()
      try rec.createdBy = @user.email
    key = await @uid()
    rec.key = await @encrypt key
    await @report.orgs.orgkeys rec
    return key
  else
    rec.lastRetrievedAt = await @epoch()
    try rec.lastRetrievedBy = @user.email
    await @report.orgs.orgkeys rec
    return @decrypt rec.key
P.report.orgs.key._log = false
P.report.orgs.key._auth = '@oa.works'

P.report.orgs.supplements = _index: true, _auth: '@oa.works'
P.report.orgs.supplements.load = (orgname, sheetname, clear) ->
  started = await @epoch()
  if @fn is 'report.orgs.supplements.load'
    clear ?= @params.clear
  await @report.orgs.supplements('') if clear
  orgname ?= @params.org
  sheetname ?= @params.sheet
  recs = await @src.google.sheets S.report.orgs_sheet
  total = 0
  idents = []
  replacements = {}
  sheets = []
  sheets_latest = {}
  sheetnames = []
  if not clear
    replacements[sup.replaced] = sup.DOI for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'replaced:*'

  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    org = {}
    for h of rec
      if typeof rec[h] is 'string'
        rec[h] = rec[h].trim()
        if rec[h].toLowerCase() is 'true'
          rec[h] = true
        else if rec[h].toLowerCase() is 'false'
          rec[h] = false
        else if ((rec[h].startsWith('[') and rec[h].endsWith(']')) or (rec[h].startsWith('{') and rec[h].endsWith('}')))
          try rec[h] = JSON.parse rec[h]
        else if rec[h].includes ';'
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split ';'
      if h.includes '.'
        try await @dot org, h, rec[h]
      else
        org[h] = rec[h]
    if Array.isArray org.sheets
      for s in org.sheets
        if (not orgname or org.name is orgname) and (not sheetname or s.name is sheetname)
          console.log org.name, s.name, s.url
          rc = 0
          osdids = []
          headers = []
          rows = []
          update = @params.update ? true
          last = false
          sups = []
          await @sleep 1000
          if not @params.update? # can force an update on URL call
            try
              check = await @src.google.sheets sheetid: s.url, sheet: 'm_admin', headers: false
              await @sleep 1000 # more sleeps to avoid google 429 sadness
              if Array.isArray(check) and check.length and check[0][0].toLowerCase() is 'last updated' and last = check[0][1]
                [ld, lt] = last.split ' '
                ld = ld.split('/').reverse().join('-')
                last = await @epoch ld + 'T' + lt
                console.log org.name, s.name, 'last updated', last
                if typeof last is 'number' and last > 1577836800000 # start of 2020, just in case of a bad date
                  if not latest = sheets_latest[s.name]
                    try latest = await @report.orgs.supplements 'sheets.keyword:"' + s.name + '"', size: 1, sort: updated: 'desc'
                    if latest?.hits?.hits?
                      latest = latest.hits.hits[0]._source
                      sheets_latest[s.name] = latest
                  update = last if latest?.updated and last <= latest.updated
              else if not Array.isArray(check) or not check.length
                update = false
              else
                if not latest = sheets_latest[s.name]
                  try latest = await @report.orgs.supplements 'sheets.keyword:"' + s.name + '"', size: 1, sort: updated: 'desc'
                  if latest?.hits?.hits?
                    latest = latest.hits.hits[0]._source
                    sheets_latest[s.name] = latest
                update = false if latest?.updated and latest.updated >= (started - 86400000)
            catch
              update = false
          if update isnt true
            console.log org.name, s.name, 'NOT loading because', last, 'is not after', update
          else
            await @sleep 1000
            try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
            tries = 0
            while (not Array.isArray(rows) or not rows.length) and tries < 5 # https://github.com/oaworks/Gates/issues/375
              await @sleep 5000
              tries += 1
              try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
            if Array.isArray(rows) and rows.length
              headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
              for row in rows
                rc += 1
                rr = org: org.name, sheets: s.name, ror: org.ror, paid: (if org.paid is true then org.paid else undefined) # check paid explicitly because some had an empty string instead of a bool
                for hp of headers
                  h = headers[hp]
                  if h.toLowerCase() is 'pmcid'
                    rr[h] = row[hp]
                    rr.pmcid = 'PMC' + row[hp].toLowerCase().replace('pmc', '')
                  else if h in ['doi', 'DOI']
                    rr[h] = row[hp]
                  else
                    hpv = ''
                    if h in ['apc_cost', 'wellcome.apc_paid_actual_currency_excluding_vat', 'wellcome.apc_paid_gbp_inc_vat_if_charged', 'wellcome.additional_publication_fees_gbp', 'wellcome.amount_of_apc_charged_to_coaf_grant_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_rcuk_oa_fund_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_wellcome_grant_inc_vat_in_gbp']
                      try hpv = parseFloat row[hp]
                    else
                      hpv = if typeof row[hp] is 'number' then row[hp] else if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if h.toLowerCase() in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else row[hp]
                      hpv = row[hp].split(';') if typeof row[hp] is 'string' and row[hp].includes(';')
                    if hpv? and hpv isnt ''
                      if h.includes '.'
                        await @dot rr, h, hpv
                      else
                        rr[h] = hpv
                if not rr.doi
                  rr.doi = (rr.DOI ? '') + ''
                else
                  rr.DOI ?= rr.doi + ''
                try rr.DOI = '10.' + rr.DOI.split('/10.')[1] if rr.DOI.startsWith 'http'
                try rr.DOI = rr.DOI.toLowerCase().replace('doi ', '') if rr.DOI.startsWith 'doi '
                try rr.DOI = rr.DOI.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').replace(/^\//, '').split(' ')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim()
                try rr.DOI = rr.DOI.split(',http')[0] # due to dirty data
                if (typeof rr.DOI is 'string' and rr.DOI.startsWith('10.') and not rr.DOI.includes '@') or rr.openalex or rr.pmcid
                  if not clear and rr.DOI and replacements[rr.DOI]?
                    rr.replaced = rr.DOI
                    rr.DOI = replacements[rr.DOI]
                  rr.email = await @encrypt(rr.email) if typeof rr.email is 'string' and rr.email.includes '@'
                  rr.osdid = (org.name.replace(/[^a-zA-Z0-9-_ ]/g, '') + '_' + s.name + '_' + (rr.DOI ? rr.openalex ? rr.pmcid)).replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
                  rr._id = rr.osdid
                  osdids.push rr.osdid
                  if (rr.DOI ? rr.openalex ? rr.pmcid) not in idents
                    '''kc = false
                    if not clear
                      present = await @report.works 'supplements.osdid.keyword:"' + rr.osdid + '"', 1
                      present = present.hits.hits[0]._source if present?.hits?.hits? and present.hits.hits.length
                      try
                        for prs in present.supplements
                          if prs.osdid is rr.osdid
                            present = prs
                            break
                      if present?
                        kc = await @copy rr
                        delete kc.updated
                        for k of present
                          break if k not in ['updated'] and JSON.stringify(rr[k] ? '').toLowerCase() isnt JSON.stringify(present[k]).toLowerCase() # JSON string match on object isn't guaranteed but probably likely enough for the number of times we'll need it
                          delete kc[k]'''
                    idents.push(rr.DOI ? rr.openalex ? rr.pmcid) #if clear or JSON.stringify(kc) isnt '{}'
                  rr.updated = started
                  sups.push rr
                  total += 1
              console.log org.name, s.name, sups.length, idents.length
              await @report.orgs.supplements sups
            await @sleep 2000
            for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'org.keyword:"' + org.name + '" AND sheets.keyword:"' + s.name + '"', scroll: '30m', include: ['osdid', 'DOI', 'openalex', 'pmcid']
              if sup.osdid not in osdids
                await @report.orgs.supplements sup.osdid, ''
                idents.push(sup.DOI ? sup.openalex ? sup.pmcid) if (sup.DOI ? sup.openalex ? sup.pmcid) not in idents # need to rerun for ones where something has been deleted too so that deleted supplements get removed from the work
          sheets.push org: org.name, sheet: s.name, rows: rc, update: update, supplements: sups.length
          sheetnames.push s.name

  # check for sheets that have since been removed
  if not clear and not orgname and not sheetname
    for aps in await @report.works.suggest 'supplements.sheets', undefined, 5000
      if aps not in sheetnames
        for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'sheets.keyword:"' + aps + '"', scroll: '30m', include: ['osdid']
          await @report.orgs.supplements sup.osdid, ''
        for await osw from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'supplements.sheets.keyword:"' + aps + '"', scroll: '30m', include: ['DOI', 'openalex', 'pmcid']
          idents.push(osw.DOI ? osw.openalex ? osw.pmcid) if (osw.DOI and osw.DOI not in idents) or (not osw.DOI and osw.openalex and osw.openalex not in idents) or (not osw.DOI and not osw.openalex and osw.pmcid and osw.pmcid not in idents)

  if clear # need to check to run everything that had a supplement
    for ptc in await @report.works 'orgs:* OR supplements.sheets:*', include: ['DOI', 'openalex', 'pmcid']
      idents.push(ptc.DOI ? ptc.openalex) if (ptc.DOI and ptc.DOI not in idents) or (not ptc.DOI and ptc.openalex and ptc.openalex not in idents) or (not ptc.DOI and not ptc.openalex and ptc.pmcid and ptc.pmcid not in idents)

  await @sleep 60000 # wait a while for the supplements index to finish building and then run the processing for identifiers
  console.log 'report orgs supplements load', total, idents.length, await @epoch() - started
  if idents.length
    console.log 'report orgs supplements load ready to call works load', idents.length
    await @report.works.load undefined, undefined, idents, undefined, undefined, started, undefined, sheets
  return total
P.report.orgs.supplements.load._bg = true
P.report.orgs.supplements.load._async = true
P.report.orgs.supplements.load._log = false
#P.report.orgs.supplements.load._auth = '@oa.works'




P.report.emails = _sheet: S.report.emails_sheet, _key: 'doi', _auth: '@oa.works'
P.report.email = (doi) ->
  return undefined if not doi and not @params.orgkey
  doi ?= @params.email ? @params.doi
  return undefined if not doi?
  rec = await @report.works doi
  if (email = rec?.email ? rec?.outreach?.email_address)
    return email if email.includes '@'
    rpke = await @encrypt @params.orgkey
    ok = await @report.orgs.orgkeys 'key.keyword:"' + rpke + '"', 1
    if typeof ok?.org is 'string' and ok.org.length
      rol = []
      rol.push(rou.toLowerCase()) for rou in rec.orgs
      if 'gates foundation' in rol and ok.org.toLowerCase().includes 'gates foundation'
        return @decrypt email # a special case for gates due to a name change issue caused in the data https://github.com/oaworks/discussion/issues/3328
      if ok.org.toLowerCase() in rol
        return @decrypt email
  return
P.report.email._log = false
try P.oareport.email = P.report.email # temporary for oareport development


# curl -X PUT http://localhost:9200/paradigm_b_report_works/_settings -H 'Content-Type: application/json' -d '{"index.mapping.total_fields.limit": 2000}'
# put in opensearch.yml: indices.query.bool.max_clause_count: 20000

P.report.works.process = (cr, openalex, refresh, everything, action, replaced, queued) ->
  try
    started = await @epoch()
    cr ?= @params.process
    givenpmcid = false
    refresh = true if refresh is 0
    refresh ?= @refresh
    everything ?= @params.everything # if so then runs epmc and permissions, which otherwise only run for records with orgs providing supplements

    rec = {}

    if typeof cr is 'string' and cr.toLowerCase().startsWith 'pmc'
      givenpmcid = cr.toLowerCase().replace('pmc', 'PMC')
      cr = undefined
      #openalex ?= await @src.openalex.works 'ids.pmcid:"' + givenpmcid.toLowerCase().replace('pmc', '') + '"', 1 # openalex does not store them with the PMC prefix, they are in URL format without it
      openalex ?= await @src.openalex.works.find undefined, undefined, givenpmcid, undefined, true
      if not openalex? and epmc = await @src.epmc.pmc givenpmcid, refresh
        cr = epmc.doi

    if not openalex and cr and (cr.includes('openalex.org/') or cr.startsWith('W'))
      cr = cr.split('openalex.org/')[1] if cr.includes 'openalex.org/'
      openalex = cr
      cr = undefined
    
    if typeof openalex is 'string'
      openalex = openalex.split(if openalex.includes('doi.org') then 'doi.org/' else '/').pop()
      openalex = openalex.replace /\/$/, ''
      if openalex.startsWith '10.'
        openalex = openalex.toLowerCase()
        cr ?= openalex
      if openalex.startsWith('W') or openalex.startsWith '10.'
        try
          #ox = if openalex.startsWith('W') then await @src.openalex.works('id.keyword:"https://openalex.org/' + openalex + '"') else await @src.openalex.works.doi openalex, (@params.refresh_sources ? false)
          #try ox = ox.hits.hits[0]._source if ox?.hits?.hits?.length
          ox = await @src.openalex.works.find (if openalex.startsWith('10.') then openalex else undefined), (if openalex.startsWith('10.') then undefined else openalex), undefined, undefined, true
          openalex = ox if ox?.id
    if (typeof openalex is 'object' and openalex.ids?.doi) or (typeof openalex is 'string' and openalex.startsWith '10.')
      soad = (if typeof openalex is 'string' then openalex else openalex.ids.doi.split('.org/')[1]).toLowerCase()
      exists = await @report.works soad # must look up prev record in every case now, in case we need to track orgs by query
      exists = undefined if exists?.DOI and exists.DOI.toLowerCase() isnt soad
      refresh = true if exists?.updated or (refresh and refresh isnt true and exists and exists.updated < refresh)
    openalex = undefined if typeof openalex is 'string' and not (openalex.startsWith('W') or openalex.startsWith('10.'))

    cr = openalex.ids.doi if not cr? and typeof openalex is 'object' and openalex?.ids?.doi
    cr = cr.split('doi.org/').pop() if typeof cr is 'string' and cr.includes 'doi.org/'
    cr = undefined if typeof cr is 'string' and not cr.startsWith '10.'
    cr = cr.toLowerCase() if typeof cr is 'string'
    cr = xref if typeof cr is 'string' and xref = await @src.crossref.works.doi cr, @params.refresh
    cr = undefined if typeof cr is 'object' and not cr.DOI

    exists = await @report.works(if typeof cr is 'string' then cr else cr.DOI) if cr? and not exists?
    exists = undefined if exists?.DOI and exists.DOI.toLowerCase() isnt (if typeof cr is 'string' then cr else if typeof cr is 'object' and cr.DOI then cr.DOI else '').toLowerCase()
    if refresh isnt true
      if exists? and not everything
        rec.PMCID = exists.PMCID if exists.PMCID? and exists.PMCID isnt 'PMC'
        rec.pubtype = exists.pubtype if exists.pubtype?
        #rec.tried_epmc_licence = exists.tried_epmc_licence if exists.tried_epmc_licence?
        #rec.epmc_licence = exists.epmc_licence if exists.epmc_licence?
        # this has to be checked every time from the supps, so don't set it again
        #rec.pmc_has_data_availability_statement = exists.pmc_has_data_availability_statement if exists.pmc_has_data_availability_statement
        rec.data_availability_statement = exists.data_availability_statement if exists.data_availability_statement?
        rec.data_availability_url = exists.data_availability_url if exists.data_availability_url?
        rec.data_availability_doi = exists.data_availability_doi if exists.data_availability_doi?      
        rec.has_data_availability_statement = true if exists.data_availability_statement #or exists.has_data_availability_statement
      refresh = true if not exists?.updated or (refresh and refresh isnt true and exists and exists.updated < refresh)

    openalex = await @src.openalex.works.find((if typeof cr is 'object' then cr.DOI else cr), undefined, undefined, undefined, true) if cr? and not openalex?
    openalex = undefined if typeof openalex is 'string' or not openalex?.id

    if typeof cr is 'object' and cr.DOI
      refresh = true if exists?.updated and cr.indexed?.timestamp and exists.updated < cr.indexed.timestamp
      rec.DOI = cr.DOI.toLowerCase()
      rec.published_year = cr.year
      rec.published_date = cr.published
      rec.issn = cr.ISSN
      rec[crv] = cr[crv] for crv in ['subject', 'subtitle', 'volume', 'issue', 'publisher', 'funder', 'subtype', 'assertion', 'relation']
      for ass in (cr.assertion ? [])
        assl = (ass.label ? '').toLowerCase()
        if assl.includes('accepted') and assl.split(' ').length < 3
          ad = await @dateparts ass.value
          if ad?.date
            if ad.timestamp
              rec.accepted_date ?= ad.date
            else
              rec.bad_accepted_date ?= 'bad date ' + ad.date
        if assl.includes 'received'
          sd = await @dateparts ass.value
          if sd?.date
            if sd.timestamp
              rec.submitted_date ?= sd.date
            else
              rec.bad_submitted_date ?= 'bad date ' + sd.date
      delete f['doi-asserted-by'] for f in rec.funder ? []
      rec.title = cr.title[0] if cr.title and typeof cr.title isnt 'string' and cr.title.length
      rec.journal = cr['container-title'][0] if cr['container-title'] and cr['container-title'].length
      rec['reference-count'] = cr['reference-count'] if cr['reference-count']?
      for lc in cr.license ? []
        if lc['content-version'] in ['am', 'vor', 'tdm', 'unspecified']
          rec['crossref_license_url_' + lc['content-version']] = lc.URL
          rec.publisher_license_crossref = lc.URL if not rec.publisher_license_crossref or rec.publisher_license_crossref.length < lc.URL.length
      rec.crossref_is_oa = if not cr.is_oa? then false else cr.is_oa

      brd = []
      _rsup = (sup, ud) =>
        sup.DOI = cr.DOI
        sup.replaced = ud
        await @report.orgs.supplements sup.osdid, ''
        sup._id = sup.osdid = sup.osdid.split('_10.')[0] + '_' + sup.DOI.replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
        brd.push sup
      for ud in (cr['update-to'] ? [])
        if ud.DOI isnt cr.DOI and ud.type and ud.type.toLowerCase() not in ['erratum', 'correction'] # some new version statements are for the same DOI, so no point changing anything
          rec.replaces = []
          rec.replaces.push DOI: ud.DOI, type: ud.type, updated: ud.updated?.timestamp
          await @report.works(ud.DOI, '') if ude = await @report.works ud.DOI
          _rsup(sup, ud.DOI) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + ud.DOI + '"'
      #vseens = []
      #for rtype in ['is-same-as', 'is-version-of', 'has-version'] # NOTE that these can be reciprocal and more than dual, and not always fully related, so can cause recurring loops. e.g. see https://bg.beta.oa.works/src/crossref/works/10.26434/chemrxiv-2021-vfkqb-v3
      #  for rr in (cr.relation?[rtype] ? []) # so we can't be sure which is the 'newest' or 'best' version, or that we will always know of all versions the first time round. So just note their relation to each other and default to whichever one got into the index first
      #    if rr['id-type'] is 'doi' and rr.id not in vseens and rr.id isnt cr.DOI and rr.id isnt replaced and newer = await @report.works rr.id # crossref is also capable of saying a DOI is the same as another DOI that does not exist in crossref, but in that case it won't exist in report works yet either
      #      _rsup(sup, rr.id) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + cr.DOI + '"'
      #    vseens.push rr.id
      #    break if newer?
      #  break if newer?
      await @report.orgs.supplements(brd) if brd.length
      #if newer?
      #  return @report.works.process newer, openalex, refresh, everything, action, cr.DOI
      if replaced # if this was passed in by a secondary call to process
        rec.replaces ?= []
        rec.replaces.push DOI: replaced, type: 'relation'

    if openalex?
      try refresh = true if exists?.updated and not openalex.is_paratext and not openalex.is_retracted and openalex.updated_date and exists.updated < await @epoch openalex.updated_date
      rec.openalx = JSON.parse JSON.stringify openalex
      delete rec.openalx[dodgy] for dodgy in ['topics', 'primary_topic', 'keywords', 'concepts', 'domains', 'fields', 'subfields'] # avoid data type changes on openalex that caused save fails due to mapping mismatch
      rec.publisher_license_v2 = rec.openalx.primary_location?.license # primary location is NOT always present
      for ll in (rec.openalx.locations ? [])
        rec.publisher_license_v2 = ll.license if ll.license and (not rec.publisher_license_v2 or ll.license.length < rec.publisher_license_v2) and ll.source?.type is 'journal'
        rec.repository_license_v2 = ll.license if ll.license and (not rec.repository_license_v2 or ll.license.length < rec.repository_license_v2) and ll.source?.type is 'repository'
      rec.openalex = openalex.id.split('/').pop() if openalex.id
      rec.DOI = openalex.ids.doi.split('doi.org/').pop().toLowerCase() if not rec.DOI and openalex.ids?.doi?
      rec.PMID = openalex.ids.pmid.split('/').pop() if openalex.ids?.pmid
      rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if not rec.PMCID and openalex.ids?.pmcid
      rec.title = openalex.title if openalex.title
      rec[ok] = openalex[ok] for ok in ['authorships', 'concepts', 'cited_by_count', 'type', 'is_paratext', 'is_retracted']
      rec.published_date = openalex.publication_date if openalex.publication_date
      rec.published_year = openalex.publication_year if openalex.publication_year
      rec.issn = openalex.host_venue.issn if openalex.host_venue?.issn and openalex.host_venue.issn.length
      rec.biblio = openalex.biblio if openalex.biblio
      rec['referenced_works'] = openalex['referenced_works'].length if openalex['referenced_works']
      for c in rec.concepts ? []
        delete c.wikidata
        try c.score = Math.floor(c.score * 100)
      for a in rec.authorships ? []
        delete i.type for i in a.institutions ? []
        a.author.orcid_number = a.author.orcid.split('/').pop() if a.author?.orcid and a.author.orcid.includes 'orcid.org/'

    rec.DOI = cr.toLowerCase() if not rec.DOI and typeof cr is 'string'
    rec.PMCID = givenpmcid if givenpmcid and not rec.PMCID

    if rec.DOI #and (refresh or not exists?.oadoi) # or (exists? and exists.updated < (Date.now() - 604800000)))
      oadoi = await @src.oadoi.doi rec.DOI, (if rec.published_year and rec.published_year > 2023 then 4838400000 else undefined) # adding the refresh here to force some 2025 updates to anything over 8 weeks old but prob don't do long term because of rate limits
      rec.oadoi = oadoi?
      for loc in oadoi?.oa_locations ? []
        if loc.host_type is 'publisher'
          rec.publisher_license ?= loc.license
          rec.publisher_url_for_pdf ?= loc.url_for_pdf
          rec.publisher_version ?= loc.version
        if loc.host_type is 'repository'
          if loc.url and loc.url.toLowerCase().includes 'pmc'
            if not rec.PMCID
              pp = loc.url.toLowerCase().split('pmc').pop().split('articles/').pop().split('/')[0].split('?')[0].split('#')[0].split('.')[0].replace(/[^0-9]/g, '')
              rec.PMCID = 'PMC' + pp if pp.length and not isNaN parseInt pp
            #if loc.license and not rec.epmc_licence
            #  rec.epmc_licence = loc.license
          if not rec.repository_url or not rec.repository_url.includes('pmc') or (not rec.repository_url.includes('ncbi.') and loc.url.includes('ncbi.'))
            for ok in ['license', 'url_for_pdf', 'url', 'version']
              rec['repository_' + ok] = loc[ok] if loc[ok]
      if rec.repository_url and (rec.repository_url.toLowerCase().includes('europepmc.') or rec.repository_url.toLowerCase().includes('ncbi.'))
        rec.PMCID ?= 'PMC' + rec.repository_url.toLowerCase().split('pmc').pop().split('articles/').pop().split('/')[0].split('#')[0].split('?')[0].split('.')[0].replace(/[^0-9]/g, '')
        rec.repository_url_in_pmc = true
      if oadoi?
        rec.best_oa_location_url = oadoi.best_oa_location?.url
        rec.best_oa_location_url_for_pdf = oadoi.best_oa_location?.url_for_pdf
        rec.oa_status = oadoi.oa_status
        rec.has_repository_copy = oadoi.has_repository_copy
        rec.has_oa_locations_embargoed = if oadoi.oa_locations_embargoed? and oadoi.oa_locations_embargoed.length then true else false
        rec.title = oadoi.title
        rec.issn = oadoi.journal_issns.split(',') if not rec.issn and typeof oadoi.journal_issns is 'string' and oadoi.journal_issns.length
        rec.journal ?= oadoi.journal_name
        rec.publisher ?= oadoi.publisher
        rec.published_date = oadoi.published_date if oadoi.published_date
        rec.published_year = oadoi.year if oadoi.year
        rec.oadoi_is_oa = oadoi.is_oa if oadoi.is_oa?

    corresponding_author_ids = []
    rec.supplements = []
    rec.orgs = []
    #mturk_has_data_availability_statement = undefined
    #has_data_availability_statement_ic = undefined
    if rec.DOI or rec.openalex or rec.PMCID
      sqq = ''
      if rec.DOI
        sqq += 'DOI.keyword:"' + rec.DOI + '"'
      if rec.openalex
        sqq += (if sqq then ' OR ' else '') + 'openalex.keyword:"' + rec.openalex + '"'
      if rec.PMCID
        sqq += (if sqq then ' OR ' else '') + 'pmcid.keyword:"' + rec.PMCID + '"'
      for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', sqq, sort: 'osdid.keyword': 'asc'
        rec.orgs.push(sup.org) if sup.org not in rec.orgs
        rec.paid = true if sup.paid
        rec.email = sup.email if not rec.email and sup.email
        rec.author_email_name = sup.author_email_name_ic if sup.author_email_name_ic
        rec.has_data_availability_statement = true if sup.has_data_availability_statement_ic
        rec.has_data_availability_statement = false if rec.has_data_availability_statement isnt true and sup.has_data_availability_statement_ic is false
        rec.has_data_availability_statement = true if sup.mturk_has_data_availability_statement
        rec.has_data_availability_statement = false if rec.has_data_availability_statement isnt true and sup.mturk_has_data_availability_statement is false
        rec.pmc_has_data_availability_statement = sup.pmc_has_data_availability_statement if sup.pmc_has_data_availability_statement?
        if sup.corresponding_author_ids
          for cid in (if typeof sup.corresponding_author_ids is 'string' then sup.corresponding_author_ids.split(',') else sup.corresponding_author_ids)
            corresponding_author_ids.push(cid) if cid not in corresponding_author_ids
        #for k of sup
        #  rec[k] = sup[k] if rec[k]?
        #  delete rec[k] if rec[k]? and sup[k] is 'NULL'
        rec.supplements.push sup

    for cid in (rec.openalx?.corresponding_author_ids ? [])
      corresponding_author_ids.push(cid) if cid not in corresponding_author_ids
    rec.corresponding_authors = []
    for atp in (rec.openalx?.authorships ? [])
      rec.corresponding_authors.push(atp) if atp.author?.id in corresponding_author_ids

    rec.openalx.authors_count = rec.openalx.authorships.length if rec.openalx?.authorships? and not rec.openalx.authors_count?

    if exists?
      if not refresh?
        rec.author_email_name = exists.author_email_name if not rec.author_email_name and exists.author_email_name and exists.email and rec.email and rec.email.toLowerCase() is exists.email.toLowerCase()
        rec[k] ?= exists[k] for k of exists when k not in ['orgs_by_query', 'PMCID']
      rec.PMCID = exists.PMCID if (not rec.PMCID or rec.PMCID is 'PMC') and exists.PMCID? and exists.PMCID isnt 'PMC'

    #if rec.DOI and not refresh?
    #  for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', 'paid:true', scroll: '10m'
    #    if o.name not in rec.orgs and o.source?.crossref
    #      try o.source.crossref = decodeURIComponent(decodeURIComponent(o.source.crossref)) if o.source.crossref.includes '%'
    #      try rec.orgs.push(o.name) if matches = await @src.crossref.works '(' + o.source.crossref + ') AND DOI.keyword:"' + rec.DOI + '"', 1
    #    if o.name not in rec.orgs and o.source?.openalex
    #      try o.source.openalex = decodeURIComponent(decodeURIComponent(o.source.openalex)) if o.source.openalex.includes '%'
    #      try rec.orgs.push(o.name) if matches = await @src.openalex.works '(' + o.source.openalex + ') AND ids.doi.keyword:"https://doi.org/' + rec.DOI + '"', 1

    if rec.authorships? and rec.email and not rec.author_email_name and (refresh or not exists?.authorships? or not exists?.email)
      email = if rec.email.includes('@') then rec.email else await @decrypt rec.email
      if rec.authorships.length is 1
        rec.author_email_name = 'Dr. ' + rec.authorships[0].author?.display_name
      else
        ren = email.split('@')[0].toLowerCase().replace /[^a-z]/g, ''
        best_initial = ''
        best_name = ''
        best_score = 1000000
        for rn in rec.authorships
          if ran = rn.author?.display_name
            lvs = await @levenshtein ren, ran.toLowerCase().replace /[^a-z]/g, ''
            score = lvs.distance / ran.length
            if score < best_score
              best_score = score
              best_name = ran
            if best_score > .2 and (ren.endsWith(ran.split(' ').pop().toLowerCase()) or (ran.split(' ')[0].length > 4 and ren.includes ran.split(' ')[0].toLowerCase()))
              best_score = .1
              best_name = ran
            if not best_initial and ren.startsWith (ran.split(' ')[0].slice(0,1) + ran.split(' ').pop().slice(0,1)).toLowerCase()
              best_initial = ran
        if best_name and best_score < .7
          rec.author_email_name = 'Dr. ' + best_name.split(' ').pop()
        if not rec.author_email_name and best_initial
          rec.author_email_name = 'Dr. ' + best_initial

    rec.email = await @encrypt(rec.email) if typeof rec.email is 'string' and rec.email.includes '@'

    if rec.publisher and (refresh? or not rec.publisher_simple)
      if not _report_publishers.length
        rpa = await @report.publishers '*', 10000
        rpa = rpa.hits.hits if not Array.isArray(rpa) and rpa?.hits?.hits?
        _report_publishers.push(rp._source ? rp) for rp in (rpa ? [])
      publ = rec.publisher.toLowerCase()
      for pub in _report_publishers
        if pub.publisher and publ.includes pub.publisher.toLowerCase()
          rec.publisher_simple = pub.publisher_display_name
          break

    #if (not exists? and rec.orgs.length) or (exists?.orgs ? []).length isnt rec.orgs.length or (rec.paid and rec.paid isnt exists?.paid) #or not exists.journal_oa_type
    if not rec.PMCID or not rec.PMID or not rec.pubtype? or not rec.submitted_date or not rec.accepted_date
      if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else if rec.DOI then await @src.pubmed.doi(rec.DOI) else undefined) # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
        rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if not rec.PMCID and pubmed?.identifier?.pmc
        rec.PMID = pubmed.identifier.pubmed if not rec.PMID and pubmed?.identifier?.pubmed
        rec.pubtype = pubmed.type # this is a list
        rec.submitted_date ?= pubmed.dates?.PubMedPubDate_received?.date
        rec.accepted_date ?= pubmed.dates?.PubMedPubDate_accepted?.date

    if rec.DOI and not rec.journal_oa_type # restrict permissions only to records with orgs supplements? for now no
      # can permissions work well enough if there is no DOI? For now assume not
      permissions = await @permissions (await @copy rec), undefined, undefined, oadoi, cr, started - 1209600000 # (if refresh then undefined else started - 1209600000) # use cached best permissions up to two weeks old
      rec.can_archive = permissions?.best_permission?.can_archive
      rec.can_archive = true if not rec.can_archive? and ((oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj)
      rec.version = permissions?.best_permission?.version
      rec.journal_oa_type = await @permissions.journals.oa.type rec.issn, undefined, oadoi, cr # calculate journal oa type separately because it can be different for a journal in general than for what permissions calculates in more specificity
      rec.journal_oa_type ?= 'unsuccessful'

    everything = true if rec.supplements.length #and (refresh or (exists?.orgs ? []).length isnt rec.orgs.length) # control whether to run time-expensive things on less important records
    for por in (rec.orgs ? [])
      port = por.toLowerCase().trim()
      if port not in ['fwf austrian science fund', 'dutch research council', 'national science center', 'uk research and innovation', 'agencia nacional de investigación y desarrollo', 'national natural science foundation of china', 'research foundation - flanders', 'ministry of business, innovation and employment', 'german research foundation', 'national cancer institute']
        everything = true
      else if rec.funder
        try
          port = port.replace /[^a-z ]/g, ''
          _processing_orgs[port] ?= await @report.orgs 'name.keyword:"' + por + '"', 1
          if _processing_orgs[port]?.country_code
            for f in rec.funder
              if f.DOI and _processing_orgs[port].fundref
                for potfr in (if typeof _processing_orgs[port].fundref is 'string' then [_processing_orgs[port].fundref] else _processing_orgs[port].fundref)
                  if f.DOI.includes potfr # crossref funder DOIs have also been seen to have errors prefixing
                    f.country = _processing_orgs[port].country_code
                    break
              if not f.country and f.name  # some crossref records have funder objects that are empty or do not have name
                flc = f.name.toLowerCase().replace /[^a-z ]/g, ''
                if flc.includes(port) or port.includes(flc) or (_processing_orgs[port].aliases ? []).join('').toLowerCase().replace(/[^a-z ]/g, '').includes(flc) or (_processing_orgs[port].acronyms ? '').toLowerCase().includes flc
                  f.country = _processing_orgs[port].country_code
                if not f.country and _processing_orgs[port].acronyms
                  for poac in _processing_orgs[port].acronyms.split ','
                    f.country = _processing_orgs[port].country_code if poac.replace(/[^a-z A-Z]/g, '') in f.name.split ' '
                if not f.country and _processing_orgs[port].aliases
                  for poaa in _processing_orgs[port].aliases
                    f.country = _processing_orgs[port].country_code if flc.includes poaa.toLowerCase().replace /[^a-z ]/g, ''
    
    #alternative way to do funder countries regardless or orgs present - but puts more load on orgs queries and maintains a much larger in-memory orgs object
    #for por in (rec.orgs ? [])
    #  port = por.toLowerCase().trim()
    #  everything = true if port not in ['fwf austrian science fund', 'dutch research council', 'national science center', 'uk research and innovation', 'agencia nacional de investigación y desarrollo', 'national natural science foundation of china', 'research foundation - flanders', 'ministry of business, innovation and employment', 'german research foundation']
    #  if not _processing_orgs[port]?
    #    _processing_orgs[port] = await @report.orgs 'name:"' + port + '" OR aliases:"' + port + '" OR acronyms:"' + port + '"', 1 # save under every alias / acronym / fundref as well?
    #    if _processing_orgs[port]?
    #      for fk in ['name', 'acronyms', 'aliases', 'fundref']
    #        if Array.isArray _processing_orgs[fk]
    #         for anfk in _processing_orgs[fk]
    #          anfkl = anfk.toLowerCase()
    #           _processing_orgs[anfk] = _processing_orgs[port] if anfkl isnt port
    #        else if typeof _processing_orgs[fk] is 'string'
    #          pfkl = _processing_orgs[fk].toLowerCase()
    #          _processing_orgs[pfkl]] = _processing_orgs[port] if pfkl isnt port
    #
    #if rec.funder
    #  for f in rec.funder
    #    if f.DOI
    #      fds = '10.' + f.DOI.split('10.')[1]
    #      _processing_orgs[fds] ?= await @report.orgs 'fundref:"' + fds + '"', 1 # crossref funder DOIs have also been seen to have errors prefixing
    #      f.country = _processing_orgs[fds]?.country_code
    #    if not f.country and f.name # some crossref records have funder objects that are empty or do not have name
    #      flc = f.name.toLowerCase()
    #      _processing_orgs[flc] ?= await @report.orgs 'name:"' + flc + '" OR aliases:"' + flc + '" OR acronyms:"' + flc + '"', 1
    #      for pok of _processing_orgs
    #        pokl = pok.toLowerCase()
    #        f.country = _processing_orgs[pok].country_code if pokl.includes(flc) or flc.includes pokl
    #        break if f.country

    # is it worth restricting everything any more?
    if (rec.DOI or rec.PMCID) #and (epmc? or not rec.PMCID or not rec.pubtype?) #or not rec.submitted_date or not rec.accepted_date # only thing restricted to orgs supplements for now is remote epmc lookup and epmc licence calculation below
      #if epmc? or (everything and epmc = (if rec.PMCID then await @src.epmc.pmc(rec.PMCID, refresh) else await @src.epmc.doi rec.DOI, refresh))
      if epmc ?= (if rec.PMCID then await @src.epmc.pmc(rec.PMCID, refresh) else await @src.epmc.doi rec.DOI, refresh)
        rec.PMCID = epmc.pmcid if not rec.PMCID and epmc.pmcid
        #rec.submitted_date ?= epmc.firstIndexDate - removed as found to be not accurate enough https://github.com/oaworks/Gates/issues/559
        #rec.accepted_date ?= epmc.firstPublicationDate
        for pt in (epmc.pubTypeList?.pubType ? [])
          rec.pubtype ?= []
          rec.pubtype.push(pt) if pt not in rec.pubtype

    #if (everything or epmc?) and rec.PMCID and (refresh or not rec.tried_epmc_licence) #  and rec.repository_url_in_pmc
    rec.has_epmc_fulltext = false # it appears this should default to false in all cases https://github.com/oaworks/discussion/issues/3738#issuecomment-4134013512
    if epmc?
      rec.has_epmc_fulltext = epmc.inEPMC is 'Y'
      delete rec.epmc_licence
      delete rec.tried_epmc_licence
      if rec.has_epmc_fulltext
        rec.tried_epmc_licence = true
        lic = await @src.epmc.licence rec.PMCID, epmc, undefined, refresh
        rec.epmc_licence = lic?.licence
    #if not rec.pmc_has_data_availability_statement # TODO comment these out once Joe happy to go ahead with removing
    #  rec.pmc_has_data_availability_statement = rec.PMCID and await @src.pubmed.availability rec.PMCID
    #  rec.has_data_availability_statement = true if rec.pmc_has_data_availability_statement
    #if everything and rec.PMCID and (refresh or not rec.data_availability_statement or not rec.submitted_date) # restrict to everything?
    #if epmc?
      rec.data_availability_statement = await @src.epmc.statement rec.PMCID, epmc, refresh
      rec.has_data_availability_statement = true if rec.data_availability_statement
      if rec.data_availability_statement and urlordois = await @src.epmc.statement.url rec.PMCID, epmc, rec.data_availability_statement
        for dor in urlordois
          if dor.includes 'doi.org/'
            dord = dor.split('doi.org/')[1].toLowerCase()
            rec.data_availability_doi ?= []
            rec.data_availability_doi.push(dord) if dord not in rec.data_availability_doi
          else
            rec.data_availability_url ?= []
            rec.data_availability_url.push(dor) if dor not in rec.data_availability_url
      rec.submitted_date ?= await @src.epmc.submitted rec.PMCID, epmc

    rec.has_repository_copy = true if rec.PMCID or rec.openalx?.open_access?.any_repository_has_fulltext
    rec.is_oa = rec.oadoi_is_oa or rec.crossref_is_oa or rec.journal_oa_type in ['gold']
    rec.pmc_has_data_availability_statement = false if rec.PMCID and rec.pmc_has_data_availability_statement isnt true # when there is a PMCID, explicitly default to false if there was no supplement to specify it
    #rec.has_data_availability_statement = if rec.data_availability_statement or rec.pmc_has_data_availability_statement or has_data_availability_statement_ic or mturk_has_data_availability_statement or (rec.DOI and (rec.DOI.startsWith('10.1186') or rec.DOI.startsWith('10.12688') or rec.DOI.startsWith('10.1371'))) then true else rec.pmc_has_data_availability_statement ? has_data_availability_statement_ic ? mturk_has_data_availability_statement
    rec.has_data_availability_statement = true if rec.data_availability_statement # probably unnecessary
    rec.has_data_availability_statement = true if rec.DOI and (rec.DOI.startsWith('10.1186') or rec.DOI.startsWith('10.12688') or rec.DOI.startsWith('10.1371'))
    rec.has_data_availability_statement = rec.pmc_has_data_availability_statement if rec.has_data_availability_statement isnt true and rec.pmc_has_data_availability_statement?
    '''for qo in rec.orgs
      try
        qrc = await @report.orgs.queries qo, (rec.DOI ? rec.openalex ? rec.PMCID)
        for qk of qrc
          if Array.isArray qrc[qk]
            rec[qk] = [rec[qk]] if rec[qk]? and not Array.isArray rec[qk]
            rec[qk] ?= []
            for vl in qrc[qk]
              rec[qk].push(vl) if vl not in rec[qk]
          else
            rec[qk] = qrc[qk]'''

    rec._id ?= if rec.DOI then rec.DOI.toLowerCase().replace(/\//g, '_') else if rec.openalex then rec.openalex.toLowerCase() else if rec.PMCID then rec.PMCID.toLowerCase() else undefined # and if no openalex it will get a default ID
    rec.supplemented = await @epoch()
    rec.updated = rec.supplemented
    rec.took = rec.supplemented - started
    rec.supplemented_date = await @datetime rec.supplemented
    rec.updated_date = await @datetime rec.updated
    if @params.process and @params.save isnt false and ((rec.DOI and rec.DOI.toLowerCase() is @params.process.toLowerCase()) or (rec.openalex and rec.openalex.toLowerCase() is @params.process.toLowerCase()) or (rec.PMCID and rec.PMCID.toLowerCase() is @params.process.toLowerCase()))
      await @report.works rec
    else if queued
      _done_batch.push queued.toLowerCase()
      _processed_batch.push(rec) if rec._id?
      _processing_idents.splice _processing_idents.indexOf(queued), 1
    #console.log 'report works processed', rec.DOI, rec.took
    return rec
  catch err
    console.log 'report works process error', err, (if typeof cr is 'object' then cr.DOI else cr)
    if queued
      await @sleep 3000
      _processing_idents.splice _processing_idents.indexOf(queued), 1
      _processing_errors[queued] ?= 0
      _processing_errors[queued] += 1
      if _processing_errors[queued] isnt 4
        @report.queue queued, undefined, refresh, everything, action
      else
        delete _processing_errors[queued]
    return
P.report.works.process._log = false


P.report.works.load = (timestamp, org, idents, year, clear, supplements, everything, info, refresh) ->
  started = await @epoch()
  year ?= @params.load ? (await @date()).split('-')[0] # load could be supplements or everything but in that case year is not used anyway
  org ?= @params.org ? @params.orgs ? @params.load is 'orgs'
  idents = @params.load if not idents? and typeof @params.load is 'string' and (@params.load.startsWith('10.') or @params.load.toLowerCase().startsWith('pmc') or @params.load.toLowerCase().startsWith('w'))
  idents = [idents] if typeof idents is 'string'
  if @fn.startsWith 'report.works.load'
    clear ?= @params.clear
  refresh ?= @refresh
  everything ?= @params.everything ? @params.load is 'everything'

  #await @report.works('') if clear

  total = 0

  if @params.q
    idents ?= []
    for await sw from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', @params.q, scroll: '5m', include: ['DOI', 'openalex', 'PMCID']
      idents.push sw.DOI ? sw.openalex ? sw.PMCID
      console.log('report works preparing to load from query', idents.length) if idents.length % 10000 is 0
    console.log 'report works supplements to load from query', @params.q
  else if @params.load is 'supplements'
    idents ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', (if timestamp then 'updated:<' + timestamp else if org then 'org:"' + org + '"' else undefined), scroll: '5m', include: ['DOI', 'openalex', 'pmcid']
      idents.push sup.DOI ? sup.openalex ? sup.pmcid
    console.log 'report works supplements to load', timestamp, org, idents.length
  else if everything
    idents ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'NOT pmc_has_data_availability_statement:*', scroll: '5m', include: ['DOI', 'openalex', 'PMCID']
      idents.push sup.DOI ? sup.openalex ? sup.PMCID
    console.log 'report works supplements to load everything for records that do not yet have everything', idents.length

  if Array.isArray idents
    console.log 'report works queueing identifiers batch', idents.length
    await @report.queue idents, undefined, (timestamp ? refresh), everything
    total += idents.length
  else
    _crossref = (cq, action) =>
      cq ?= '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
      cq = '(' + cq + ') AND srcday:>' + timestamp if timestamp
      precount = await @src.crossref.works.count cq
      console.log 'report works load crossref by query expects', cq, precount
      for await cr from @index._for 'src_crossref_works', cq, include: ['DOI'], scroll: '30m'
        if org or year isnt @params.load or not ae = await @report.works cr.DOI
          total += 1
          await @report.queue cr.DOI, undefined, (timestamp ? refresh), everything, action

    await _crossref(undefined, 'years') if org isnt true and year is @params.load

    _openalex = (oq, action) =>
      oq ?= 'authorships.institutions.display_name:* AND publication_year:' + year
      oq = '(' + oq + ') AND updated_date:>' + timestamp if timestamp
      precount = await @src.openalex.works.count oq
      console.log 'report works load openalex by query expects', oq, precount
      for await ol from @index._for 'src_openalex_works', oq, include: ['id', 'ids'], scroll: '30m'
        oodoi = if ol.ids?.doi then '10.' + ol.ids.doi.split('/10.')[1] else ol.id.split('openalex.org/').pop()
        if oodoi
          if org or year isnt @params.load or not oodoi.startsWith('10.') or not ae = await @report.works oodoi
            total += 1
            await @report.queue oodoi, undefined, (timestamp ? refresh), everything, action
      
    await _openalex(undefined, 'years') if org isnt true and year is @params.load

    for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', (if typeof org is 'string' then 'name:"' + org + '"' else 'paid:true'), scroll: '10m'
      # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      if o.source?.crossref
        try o.source.crossref = decodeURIComponent(decodeURIComponent(o.source.crossref)) if o.source.crossref.includes '%'
        console.log 'report works load crossref by org', o.name, o.source.crossref
        await _crossref o.source.crossref
      if o.source?.openalex
        try o.source.openalex = decodeURIComponent(decodeURIComponent(o.source.openalex)) if o.source.openalex.includes '%'
        console.log 'report works load openalex by org', o.name, o.source.openalex
        await _openalex o.source.openalex

    if timestamp
      for await crt from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'orgs:* AND updated:<' + timestamp, scroll: '10m'
        await @report.queue(crt.DOI, undefined, (timestamp ? refresh), everything) if updated = await @src.crossref.works.count 'DOI.keyword:"' + crt.DOI + '" AND srcday:>' + timestamp
  
  took = await @epoch() - started
  text = 'Report works queued ' + total + (if @S.dev then ' (dev)' else '') + '\n'
  text += idents.length + ' identifiers were provided to process\n' if idents and idents.length
  text += 'These were derived by searching for provided query' + JSON.stringify(@params.q) + '\n' if @params.q
  text += 'These were derived by searching for all works that already have supplements attached\n' if @params.load is 'supplements'
  text += 'These were derived by searching for all works that have not yet had everything fully processed\n' if everything and not @params.q
  text += 'These were provided by an orgs supplements refresh which took ' + Math.ceil((started - supplements)/1000/60) + 'm\n' if supplements
  text += 'The load process was ' + (if @params.q then 'matched' else 'limited') + ' to ' + org + '\n' if typeof org is 'string'
  text += 'The load process was run for changes since ' + (await @datetime timestamp) + '\n' if timestamp
  text += 'The load process was run for year ' + year + '\n' if year and typeof org isnt 'string' and (@params.load or not timestamp) and not (idents ? []).length
  text += '\n' + JSON.stringify(i) + '\n' for i in (info ? [])
  console.log 'Report works loaded', total, took
  await @mail to: @S.log?.logs, subject: 'Report works loaded ' + total, text: text
  return total
P.report.works.load._log = false
P.report.works.load._bg = true
P.report.works.load._async = true
P.report.works.load._auth = '@oa.works'

P.report.works.load.mains = ->
  orgs = if @params.orgs then @params.orgs.split(',') else ['Gates Foundation', 'Robert Wood Johnson Foundation', 'Wellcome Trust']
  for org in orgs
    await @report.works.load undefined, org, undefined, undefined, undefined, undefined, undefined, undefined, true
  return true
P.report.works.load.mains._log = false
P.report.works.load.mains._bg = true
P.report.works.load.mains._async = true
P.report.works.load.mains._auth = '@oa.works'


P.report.works.changes = (timestamp, org) ->
  # do not reload orgs first before running changes, Joe wants that to remain a manual process
  timestamp ?= @params.changes ? @params.timestamp ? Date.now() - 90000000
  org ?= @params.org
  @report.works.load timestamp, org # start from timestamp a little more than a day ago, by default
  return true
P.report.works.changes._log = false
P.report.works.changes._bg = true
P.report.works.changes._async = true
P.report.works.changes._auth = '@oa.works'


P.report.works.queries = (orgs) ->
  started = Date.now()
  orgs = @params.orgs.split(',') if @params.orgs
  orgs ?= ['Gates Foundation', 'Robert Wood Johnson Foundation', 'Wellcome Trust']

  #if @params.clear
  #  await @report.works ''

  cqs = 
    'Gates Foundation': ['funder:10.13039/100000865,funder:10.13039/501100005370', 'ror-id:0456r8d26,ror-id:033sn5p83', 'container-title:Gates%20Open%20Research', 'issn:2572-4754,issn:3029-0988']
    'Robert Wood Johnson Foundation': ['funder:10.13039/100000867', 'ror-id:02ymmdj85']
    'Michael J. Fox Foundation': ['funder:10.13039/100000864', 'ror-id:03arq3225']
    'Wellcome Trust': ['funder:10.13039/100010269,funder:10.13039/100004440', 'ror-id:029chgv08']
    'Templeton World Charity Foundation': ['funder:10.13039/501100011730', 'ror-id:00x0z1472']
    'Howard Hughes Medical Institute': ['funder:10.13039/100000011,10.13039/100022388', 'ror-id:006w34k90,ror-id:013sk6x84']
  oqs = 
    'Gates Foundation': ['funders.id:F4320306137|F4320323264|F4320310978', 'authorships.institutions.ror:0456r8d26|033sn5p83', 'raw_affiliation_strings.search:melinda%20gates%20foundation|gates%20cambridge%20trust|gates%20ventures', 'locations.source.issn:2572-4754|3029-0988']
    'Robert Wood Johnson Foundation': ['funders.id:F4320306139|F4320309038', 'authorships.institutions.ror:02ymmdj85', 'raw_affiliation_strings.search:Robert Wood Johnson Foundation']
    'Michael J. Fox Foundation': ['funders.id:F4320306136', 'authorships.institutions.ror:03arq3225', 'raw_affiliation_strings.search:Michael J. Fox Foundation']
    'Wellcome Trust': ['funders.id:F4320311904', 'authorships.institutions.ror:029chgv08', 'raw_affiliation_strings.search:Wellcome Trust']
    'Templeton World Charity Foundation': ['funders.id:F4320327239', 'authorships.institutions.ror:00x0z1472', 'raw_affiliation_strings.search:Templeton World Charity Foundation']
    'Howard Hughes Medical Institute': ['funders.id:F4320306082', 'authorships.institutions.ror:006w34k90|013sk6x84', 'raw_affiliation_strings.search:Howard Hughes Medical Institute|Janelia Research Campus|Freeman Hrabowski']

  ids = []
  cvl = 0
  ovl = 0
  svl = 0

  for org in orgs
    console.log 'orgs queries doing org', org
    for o in cqs[org] ? (@params.queries ? '').split ','
      crossref = {}
      cursor = '*'
      console.log 'crossref', org, o
      while cursor? and ans = await @fetch ('https://api.crossref.org/works?mailto=sysadmin@oa.works&filter=' + o + '&rows=1000&cursor=' + encodeURIComponent cursor), {rate: ['crossrefFilter', 3], headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works')}}
        cursor = ans.message?['next-cursor'] # will be null if there are no more to get
        cursor = undefined if not ans.message?.items or ans.message.items.length < 1000 # crossref does not auto remove the last cursor on the last page so need to check for shortness
        for r in (ans.message?.items ? [])
          rid = r.DOI.toLowerCase()
          if rid and rid not in ids
            crossref[rid] = await @src.crossref.works._format r
            ids.push rid
      if cv = Object.values crossref
        cvl += cv.length
        console.log 'report works queries saving crossref records for org', org, cv.length, cvl
        await @src.crossref.works cv # do these per org so the size does not get too big in memory
        cv = undefined
    for o in oqs[org] ? (@params.queries ? '').split ','
      openalex = {}
      cursor = '*'
      #if not @params.clear
      #  o += ',publication_year:>' + (parseInt((await @date()).split('-')[0]) - 3) # to avoid openalex deep cursoring errors
      console.log 'openalex', org, o
      while cursor? and ans = await @fetch ('https://api.openalex.org/works?mailto=sysadmin@oa.works' + (if @S.src.openalex?.apikey then '&api_key=' + @S.src.openalex.apikey else '') + '&filter=' + o + '&per-page=200&cursor=' + encodeURIComponent cursor), {rate: ['openalexFilter', 20, 10000, 86400]}
        cursor = ans.meta.next_cursor # will be null if there are no more to get
        for r in ans.results
          rid = if r.ids?.doi or r.doi then (r.ids?.doi ? r.doi).split('.org/').pop().toLowerCase() else r.id.toLowerCase()
          if rid and rid not in ids
            openalex[rid] = await @src.openalex.works._format r
            ids.push rid
      if ov = Object.values openalex
        ovl += ov.length
        console.log 'report works queries saving openalex records for org', org, ov.length, ovl
        await @src.openalex.works ov
        ov = undefined
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'org.keyword:"' + org + '"'
      svl += 1
      rid = sup.DOI ? sup.pmcid ? sup.openalex
      ids.push(rid) if rid and rid not in ids
    console.log svl

  queued = 0
  while (batch = ids.splice(0, 10000)) and batch.length
    queued += batch.length
    console.log 'report works queries queueing', batch.length, queued
    await @report.queue batch, undefined, true, true
    batch = []

  console.log 'report works queries complete', cvl, ovl, svl, queued, 'elapsed', Date.now() - started
  return queued

P.report.works.queries._async = true

