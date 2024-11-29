
try S.report = JSON.parse SECRETS_REPORT
S.report ?= {}

P.report = () -> return 'OA.Works report'



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
  @report._handle_queue() if _queue_batch_last is false
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

P.report._domidqueue = -> return @report._runqueue undefined, undefined, undefined, true
P.report._domidqueue._log = false
P.report._domidqueue._bg = true

P.report._domidreversequeue = -> return @report._runqueue undefined, undefined, 'asc', true
P.report._domidreversequeue._log = false
P.report._domidreversequeue._bg = true

P.report._doreversequeue = -> return @report._runqueue undefined, undefined, 'asc'
P.report._doreversequeue._log = false
P.report._doreversequeue._bg = true

P.report._dochangesqueue = -> return @report._runqueue undefined, 'action:"changes" OR action:"years"'
P.report._dochangesqueue._log = false
P.report._dochangesqueue._bg = true


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
  try doi = doi.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').replace(/^\//, '').split(' ')[0].split('&')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim()
  try doi = doi.split('#')[0]
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

P.report.orgs.queries = (org, doi) ->
  org ?= @params.org
  doi ?= @params.queries ? @params.doi
  ret = {}
  batch = []
  processed = 0
  for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', (if org then 'name:"' + org + '"' else 'paid:true'), scroll: '30m'
    for an of (o.analysis ? [])
      if o.analysis[an].query? and not o.analysis[an].make_key in [false, 'false', 'False', 'FALSE']
        q = o.analysis[an].query
        q = '(' + q + ') AND  DOI.keyword:"' + doi + '"' if doi
        for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', q, scroll: '30m'
          dv = o.analysis[an].value ? true
          dv = [dv] if o.analysis[an].list
          if doi
            ret[o.analysis[an].key ? o.analysis[an].name ? an] = dv
          else
            # check how this would handle dot notations...
            rec[o.analysis[an].key ? o.analysis[an].name ? an] = dv
            batch.push rec
            processed += 1
            if batch.length > 20000
              await @report.works batch
              batch = []
  if batch.length
    await @report.works batch
  return if doi then ret else processed
P.report.orgs.queries._log = false
P.report.orgs.queries._bg = true
P.report.orgs.queries._async = true
P.report.orgs.queries._auth = '@oa.works'



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
      if ok.org in rol
        return @decrypt email
  return
P.report.email._log = false
try P.oareport.email = P.report.email # temporary for oareport development


# curl -X PUT http://localhost:9200/paradigm_b_report_works/_settings -H 'Content-Type: application/json' -d '{"index.mapping.total_fields.limit": 2000}'
# put in opensearch.yml: indices.query.bool.max_clause_count: 20000

P.report.works = _index: true
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
      openalex ?= await @src.openalex.works 'ids.pmcid:"' + givenpmcid.toLowerCase().replace('pmc', '') + '"', 1 # openalex does not store them with the PMC prefix, they are in URL format without it
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
          ox = if openalex.startsWith('W') then await @src.openalex.works('id.keyword:"https://openalex.org/' + openalex + '"') else await @src.openalex.works.doi openalex, (@params.refresh_sources ? false)
          try ox = ox.hits.hits[0]._source if ox?.hits?.hits?.length
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
    cr = xref if typeof cr is 'string' and xref = await @src.crossref.works.doi cr, (@params.refresh_sources ? false) # not exists? and 
    cr = undefined if typeof cr is 'object' and not cr.DOI

    exists = await @report.works(if typeof cr is 'string' then cr else cr.DOI) if cr? and not exists?
    exists = undefined if exists?.DOI and exists.DOI.toLowerCase() isnt (if typeof cr is 'string' then cr else if typeof cr is 'object' and cr.DOI then cr.DOI else '').toLowerCase()
    if refresh isnt true
      if exists? and not everything
        rec.PMCID = exists.PMCID if exists.PMCID?
        rec.pubtype = exists.pubtype if exists.pubtype?
        rec.tried_epmc_licence = exists.tried_epmc_licence if exists.tried_epmc_licence?
        rec.epmc_licence = exists.epmc_licence if exists.epmc_licence?
        rec.pmc_has_data_availability_statement = exists.pmc_has_data_availability_statement if exists.pmc_has_data_availability_statement?
        rec.data_availability_statement = exists.data_availability_statement if exists.data_availability_statement?
        rec.data_availability_url = exists.data_availability_url if exists.data_availability_url?
        rec.data_availability_doi = exists.data_availability_doi if exists.data_availability_doi?      
      refresh = true if not exists?.updated or (refresh and refresh isnt true and exists and exists.updated < refresh)

    openalex = await @src.openalex.works.doi((if typeof cr is 'object' then cr.DOI else cr), (@params.refresh_sources ? false)) if cr? and not openalex?
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

    if (refresh or not exists?.oadoi) and rec.DOI
      rec.oadoi = true
      oadoi = await @src.oadoi rec.DOI
      for loc in oadoi?.oa_locations ? []
        if loc.host_type is 'publisher'
          rec.publisher_license ?= loc.license
          rec.publisher_url_for_pdf ?= loc.url_for_pdf
          rec.publisher_version ?= loc.version
        if loc.host_type is 'repository'
          if loc.url and loc.url.toLowerCase().includes 'pmc'
            if not rec.PMCID
              pp = loc.url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0].split('.')[0].replace(/[^0-9]/g, '')
              rec.PMCID = 'PMC' + pp if pp.length and not isNaN parseInt pp
            if loc.license and not rec.epmc_licence
              rec.epmc_licence = loc.license
          if not rec.repository_url or not rec.repository_url.includes('pmc') or (not rec.repository_url.includes('ncbi.') and loc.url.includes('ncbi.'))
            for ok in ['license', 'url_for_pdf', 'url', 'version']
              rec['repository_' + ok] = loc[ok] if loc[ok]
      if rec.repository_url and (rec.repository_url.toLowerCase().includes('europepmc.') or rec.repository_url.toLowerCase().includes('ncbi.'))
        rec.PMCID ?= 'PMC' + rec.repository_url.toLowerCase().split('pmc').pop().split('/')[0].split('#')[0].split('?')[0].split('.')[0].replace(/[^0-9]/g, '')
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
    mturk_has_data_availability_statement = undefined
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
        mturk_has_data_availability_statement = sup.mturk_has_data_availability_statement if sup.mturk_has_data_availability_statement?
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
        rec[k] ?= exists[k] for k of exists when k not in ['orgs_by_query']
      rec.PMCID ?= exists.PMCID

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

    #everything = true if rec.orgs.length #and (refresh or (exists?.orgs ? []).length isnt rec.orgs.length) # control whether to run time-expensive things on less important records
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
    if (rec.DOI or rec.PMCID) and (epmc? or not rec.PMCID or not rec.pubtype?) #or not rec.submitted_date or not rec.accepted_date # only thing restricted to orgs supplements for now is remote epmc lookup and epmc licence calculation below
      if epmc? or (everything and epmc = (if rec.PMCID then await @src.epmc.pmc(rec.PMCID, refresh) else await @src.epmc.doi rec.DOI, refresh))
        rec.PMCID = epmc.pmcid if not rec.PMCID and epmc.pmcid
        #rec.submitted_date ?= epmc.firstIndexDate - removed as found to be not accurate enough https://github.com/oaworks/Gates/issues/559
        #rec.accepted_date ?= epmc.firstPublicationDate
        for pt in (epmc.pubTypeList?.pubType ? [])
          rec.pubtype ?= []
          rec.pubtype.push(pt) if pt not in rec.pubtype

    if (everything or epmc?) and rec.PMCID and not rec.epmc_licence and (refresh or not rec.tried_epmc_licence) #  and rec.repository_url_in_pmc
      rec.tried_epmc_licence = true
      lic = await @src.epmc.licence rec.PMCID, epmc, undefined, refresh
      rec.epmc_licence = lic?.licence
    rec.pmc_has_data_availability_statement ?= rec.PMCID and await @src.pubmed.availability rec.PMCID
    if everything and rec.PMCID and (refresh or not rec.data_availability_statement or not rec.submitted_date) # restrict to everything?
      rec.data_availability_statement = await @src.epmc.statement rec.PMCID, epmc, refresh
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

    rec.is_oa = rec.oadoi_is_oa or rec.crossref_is_oa or rec.journal_oa_type in ['gold']
    rec.has_data_availability_statement = if rec.pmc_has_data_availability_statement or mturk_has_data_availability_statement or (rec.DOI and (rec.DOI.startsWith('10.1186') or rec.DOI.startsWith('10.12688') or rec.DOI.startsWith('10.1371'))) then true else rec.pmc_has_data_availability_statement ? mturk_has_data_availability_statement
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


P.report.works.load = (timestamp, org, idents, year, clear, supplements, everything, info) ->
  started = await @epoch()
  year ?= @params.load ? (await @date()).split('-')[0] # load could be supplements or everything but in that case year is not used anyway
  org ?= @params.org ? @params.orgs ? @params.load is 'orgs'
  idents = @params.load if not idents? and typeof @params.load is 'string' and (@params.load.startsWith('10.') or @params.load.toLowerCase().startsWith('pmc') or @params.load.toLowerCase().startsWith('w'))
  idents = [idents] if typeof idents is 'string'
  if @fn.startsWith 'report.works.load'
    clear ?= @params.clear
  refresh = @refresh
  everything ?= @params.everything ? @params.load is 'everything'

  #await @report.works('') if clear

  total = 0

  if @params.q
    idents ?= []
    for await sw from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', @params.q, scroll: '5m', include: ['DOI', 'openalex', 'PMCID']
      idents.push sw.DOI ? sw.openalex ? sw.PMCID
      console.log('report works preparing to load from query', idents.length) if idents.length % 1000 is 0
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
        #if ol.id and ol.id.includes('/') and (not oodoi or (oodoi not in oo and oodoi not in cc))
        #  await @report.queue undefined, (oodoi ? ol.id.split('/').pop()), (timestamp ? refresh), everything
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
  await @mail to: ['mark+notifications@oa.works', 'joe+notifications@oa.works'], subject: 'OA report works loaded ' + total, text: text
  return total
P.report.works.load._log = false
P.report.works.load._bg = true
P.report.works.load._async = true
P.report.works.load._auth = '@oa.works'

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



'''
P.report.works.check = (year) ->
  year ?= @params.check ? @params.year ? '2023'
  seen = []
  not_in_works = []
  crossref_seen_openalex = []
  res = year: year, crossref: 0, crossref_count: 0, openalex: 0, openalex_count: 0, crossref_in_works: 0, crossref_in_works_had_openalex: 0, crossref_not_in_works_in_openalex: 0, openalex_already_seen_in_works_by_crossref: 0, openalex_in_works: 0, openalex_in_works_by_id: 0, openalex_with_doi_but_not_seen: 0, openalex_not_in_works: 0, duplicates: 0
  await fs.writeFile @S.static.folder + '/report_check_missing_' + year + '.json', '['

  cq = '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
  res.crossref_count = await @src.crossref.works.count cq
  await fs.writeFile @S.static.folder + '/report_check_' + year + '.json', JSON.stringify res, '', 2
  for await cr from @index._for 'src_crossref_works', cq, include: ['DOI'], scroll: '30m'
    console.log(res) if res.crossref % 100 is 0
    if cr.DOI not in seen
      seen.push cr.DOI
    else
      res.duplicates += 1
    res.crossref += 1
    res.crossref_in_works += 1 if worked = await @report.works cr.DOI
    if not worked and cr.DOI not in not_in_works
      await fs.appendFile @S.static.folder + '/report_check_missing_' + year + '.json', (if not_in_works.length then ',' else '') + '\n"' + cr.DOI + '"'
      not_in_works.push cr.DOI
    if worked?.openalex
      res.crossref_in_works_had_openalex += 1
      crossref_seen_openalex.push cr.DOI
    else if olx = await @src.openalex.works.count 'ids.doi.keyword:"https://doi.org/' + cr.DOI + '"'
      res.crossref_not_in_works_in_openalex += 1

  oq = 'authorships.institutions.display_name:* AND publication_year:' + year
  res.openalex_count = await @src.openalex.works.count oq
  await fs.writeFile @S.static.folder + '/report_check_' + year + '.json', JSON.stringify res, '', 2
  for await ol from @index._for 'src_openalex_works', oq, include: ['id', 'ids'], scroll: '30m'
    console.log(res) if res.openalex % 100 is 0
    res.openalex += 1
    oodoi = if ol.ids?.doi then '10.' + ol.ids.doi.split('/10.')[1] else undefined
    if oodoi
      res.openalex_already_seen_in_works_by_crossref += 1 if oodoi in crossref_seen_openalex
      if oodoi not in seen
        res.openalex_with_doi_but_not_seen += 1 if oodoi
        seen.push oodoi
      else
        res.duplicates += 1
    olid = ol.id.split('/').pop()
    if oodoi and worked = await @report.works oodoi
      res.openalex_in_works += 1
    else if worked = await @report.works 'openalex.keyword:"' + olid + '"', 1
      res.openalex_in_works += 1
      res.openalex_in_works_by_id += 1
    else
      res.openalex_not_in_works += 1
    if not worked and (oodoi ? olid) not in not_in_works
      await fs.appendFile @S.static.folder + '/report_check_missing_' + year + '.json', (if not_in_works.length then ',' else '') + '\n"' + (oodoi ? olid) + '"'
      not_in_works.push oodoi ? olid

  res.seen = seen.length
  res.not_in_works = not_in_works.length

  await fs.appendFile @S.static.folder + '/report_check_missing_' + year + '.json', '\n]'
  await fs.writeFile @S.static.folder + '/report_check_seen_' + year + '.json', JSON.stringify seen, '', 2
  await fs.writeFile @S.static.folder + '/report_check_' + year + '.json', JSON.stringify res, '', 2
  console.log res
  return res
P.report.works.check._async = true
P.report.works.check._bg = true
P.report.works.check._auth = '@oa.works'
'''


'''P.report.fixmedline = ->
  fixes = []
  checked = 0
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'DOI:* AND submitted_date:* AND PMCID:*', scroll: '30m', include: ['DOI', 'PMID']
    checked += 1
    console.log('fix medline checked', checked) if checked % 1000 is 0
    from_crossref = false
    if cr = await @src.crossref.works rec.DOI
      for ass in (cr.assertion ? [])
        if (ass.label ? '').toLowerCase().includes 'received'
          from_crossref = true
          break
    from_pubmed = false
    if not from_crossref
      if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else await @src.pubmed.doi rec.DOI)
        from_pubmed = true if pubmed.dates?.PubMedPubDate_received?.date
    if not from_crossref and not from_pubmed
      fixes.push rec.DOI
      console.log 'fix medline found', fixes.length, 'to fix'
  batch = []
  if fixes.length
    for DOI in fixes
      if rec = await @report.works DOI
        delete rec.submitted_date
        delete rec.accepted_date
        batch.push rec
      if batch.length is 5000
        await @report.works batch
        batch = []
    if batch.length
      await @report.works batch
  console.log 'fix medline completed with', fixes.length, 'fixed'
  return fixes.length
P.report.fixmedline._bg = true
P.report.fixmedline._async = true
P.report.fixmedline._auth = '@oa.works'
'''


'''
P.report.fixtitle = ->
  fixes = 0
  checked = 0
  batch = []
  for alpha in 'abcdefghijklmnopqrstuvwxyz'.split ''
    for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'title.keyword:"' + alpha + '" OR title.keyword:"' + alpha.toUpperCase() + '"', scroll: '30m'
      checked += 1
      console.log('fix title checked', alpha, checked, fixes) if checked % 1000 is 0
      if rec.title.length is 1
        if oadoi = await @src.oadoi rec.DOI
          rec.title = oadoi.title if oadoi.title
        if rec.title.length is 1 and openalex = await @src.openalex.works rec.DOI
          rec.title = openalex.title if openalex.title
        if rec.title.length is 1 and cr = await @src.crossref.works rec.DOI
          rec.title = cr.title if cr.title
          rec.title = rec.title[0] if typeof rec.title isnt 'string'
        if rec.title.length isnt 1
          fixes += 1
          batch.push rec
        if batch.length is 20000
          await @report.works batch
          batch = []
  if batch.length
    await @report.works batch
  console.log 'fix title completed with', checked, fixes
  return fixes
P.report.fixtitle._bg = true
P.report.fixtitle._async = true
P.report.fixtitle._auth = '@oa.works'
'''

'''
P.report.fixcroa = ->
  fixes = 0
  checked = 0
  batch = []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'crossref_is_oa:true', scroll: '30m'
    checked += 1
    console.log('fix crossref is OA checked', checked, fixes) if checked % 100 is 0
    if cr = await @src.crossref.works rec.DOI
      if cr.is_oa isnt true
        fixes += 1
        rec.crossref_is_oa = false
        batch.push rec
    if batch.length is 20000
      await @report.works batch
      batch = []
  if batch.length
    await @report.works batch
  console.log 'fix crossref is OA completed with', checked, fixes
  return fixes
P.report.fixcroa._bg = true
P.report.fixcroa._async = true
P.report.fixcroa._auth = '@oa.works'
'''

P.report.removeobq = ->
  checked = 0
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'orgs_by_query:*', scroll: '30m', include: ['DOI', 'openalex', 'PMCID']
    checked += 1
    @report.queue (rec.DOI ? rec.openalex ? rec.PMCID), undefined, true
    console.log('fix orgs by query', checked) if checked % 100 is 0
  console.log 'fix orgs by query completed with', checked
  return checked
P.report.removeobq._bg = true
P.report.removeobq._async = true
P.report.removeobq._auth = '@oa.works'


'''
P.report.fixtype = ->
  fixes = 0
  fixols = 0
  nool = 0
  checked = 0
  batch = []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'NOT type:*', scroll: '30m'
    checked += 1
    console.log('fix type checked', checked, fixes, fixols, nool, batch.length) if checked % 100 is 0
    fixed = false
    if ol = await @src.openalex.works rec.DOI
      if ol.type
        fixed = true
        fixes += 1
        rec.type = ol.type
        batch.push rec
    else
      nool += 1
    if not fixed and nol = await @src.openalex.works.doi rec.DOI, true
      console.log 'report fixtype updated openalex', rec.DOI
      fixes += 1
      fixols += 1
      rec.type = nol.type
      batch.push rec
    if batch.length is 5000
      await @report.works batch
      batch = []
  if batch.length
    await @report.works batch
  console.log 'fix type completed with', checked, fixes, fixols, nool
  return fixes
P.report.fixtype._bg = true
P.report.fixtype._async = true
P.report.fixtype._auth = '@oa.works'
'''


P.report.fixsupps = ->
  checked = 0
  removed = 0
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'byquery:*'
    checked += 1
    await @report.orgs.supplements rec._id, ''
    removed += 1
  console.log 'fix supps completed with', checked, removed
  return checked
P.report.fixsupps._bg = true
P.report.fixsupps._async = true
P.report.fixsupps._auth = '@oa.works'


'''
P.report.fixmjff = ->
  checked = 0
  removed = 0
  started = await @report.works.count 'orgs.keyword:"Michael J. Fox Foundation"'
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works_14122023', 'orgs.keyword:"Michael J. Fox Foundation"' #, undefined, false, false
    checked += 1
    if not rec._id.startsWith '10.'
      removed += 1
      #await @report.works rec._id, ''
      #await @index._send 'paradigm_report_works_14122023/_doc/' + rec._id, '', undefined, false, false
  ended = await @report.works.count 'orgs.keyword:"Michael J. Fox Foundation"'
  console.log 'fix mjff completed with', checked, removed, started, ended
  return checked
P.report.fixmjff._bg = true
P.report.fixmjff._async = true
P.report.fixmjff._auth = '@oa.works'
'''

'''P.exports = ->
  for idx in ['paradigm_svc_rscvd']
    total = 0
    fdn = @S.directory + '/report/export_' + idx + '.jsonl'
    try
      out = await fs.createWriteStream fdn #, 'utf-8'
      for await o from @index._for idx, undefined, undefined, false
        await out.write (if total then '\n' else '') + JSON.stringify o
        total += 1
        console.log('exporting', total) if total % 1000 is 0
    catch err
      console.log 'exports error', JSON.stringify err
    console.log idx, 'export done', total
  return true
P.exports._bg = true
P.exports._async = true
P.exports._log = false'''



'''P.reloads = ->
  for idx in ['paradigm_b_users', 'paradigm_b_report_orgs_orgkeys', 'paradigm_users', 'paradigm_report_orgs_orgkeys', 'paradigm_deposits', 'paradigm_ills', 'paradigm_svc_rscvd']
    total = 0
    batch = []
    pre = ''
    for await line from readline.createInterface input: fs.createReadStream @S.directory + '/import/export_' + idx + '.jsonl'
      if line.endsWith '}'
        batch.push JSON.parse pre + line
        pre = ''
        total += 1
      else
        pre += line
    await @index._bulk(idx, batch, undefined, undefined, false) if batch.length
    console.log idx, 'reloaded', total
  return true
P.reloads._bg = true
P.reloads._async = true'''


'''
P.report.test = _index: true, _alias: 'altest2'
P.report.test.add = ->
  toalias = @params.toalias
  toalias += '' if typeof toalias is 'number'
  l = await @dot P, 'report.test._alias'
  await @report.test hello: 'world', alias: l ? 'none'
  await @sleep 2000
  res = count: await @report.test.count(), ford: 0, records: []
  t = 'report_test'
  batch = [{hello: 'world', alias: l ? 'none', batch: 1}, {hello: 'world', alias: l ? 'none', batch: 2}]
  await @index._bulk t, batch, undefined, undefined, undefined, toalias
  await @sleep 2000
  for await i from @index._for 'report_test', '*'
    res.ford += 1
    res.records.push i
  return res
'''

