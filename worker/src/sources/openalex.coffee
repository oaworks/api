
S.src.openalex ?= {}
try S.src.openalex = JSON.parse SECRETS_OPENALEX

# https://docs.openalex.org/api

# aws s3 sync 's3://openalex' 'openalex' --no-sign-request

# querying openalex
# https://help.openalex.org/api/filtering/

# rate limits - they do change them...
# https://help.openalex.org/api/authentication/

P.src.openalex = -> return true

P.src.openalex.works = _index: {settings: {number_of_shards: 15}}, _prefix: false

P.src.openalex.works._format = (rec) ->
  for kt in ['concepts', 'topics', 'keywords', 'sustainable_development_goals', 'domains', 'fields', 'subfields', 'authorships', 'locations']
    for xc in rec[kt] ? []
      try xc.score = Math.floor(xc.score) if xc.score?
      try xc.id = 'https://openalex.org/' + xc.id if xc.id? and typeof xc.id isnt 'string'
      for sub in ['source', 'author', 'institutions', 'domain', 'field', 'subfield']
        try xc[sub].id = 'https://openalex.org/' + xc[sub].id if xc[sub]?.id? and typeof xc[sub].id isnt 'string'
  for mr in ['best_oa_location', 'primary_location', 'primary_topic']
    try rec[mr].score = Math.floor(rec[mr].score) if rec[mr]?.score
    try rec[mr].id = 'https://openalex.org/' + rec[mr].id if rec[mr]?.id? and typeof rec[mr].id isnt 'string'
    for sub in ['source', 'domain', 'field', 'subfield']
      try rec[mr][sub].id = 'https://openalex.org/' + rec[mr][sub].id if rec[mr][sub]?.id? and typeof rec[mr][sub].id isnt 'string'
  try
    rec._id = rec.doi ? rec.DOI ? rec.ids?.doi
    rec._id = '10.' + rec._id.split('/10.').pop() if rec._id.includes('http') and rec._id.includes '/10.'
    rec._id = rec.id.split('/').pop() if not rec._id or not rec._id.startsWith '10.'
  catch
    try
      rec._id = rec.id.split('/').pop()
    catch
      rec._id = await @uid()
      console.log 'Openalex work with no DOI or ID, assigned', rec._id
  try
    abs = []
    for word of rec.abstract_inverted_index
      abs[n] = word for n in rec.abstract_inverted_index[word]
    rec.abstract = abs.join(' ') if abs.length
  try delete rec.abstract_inverted_index
  rec.retrievedAt = Date.now()
  return rec

P.src.openalex.works.find = (doi, openalex, pmcid, pmid, refresh) ->
  if not doi and not openalex and not pmcid and not pmid and (ident = @params.find)
    if ident.startsWith '10.'
      doi = ident
    else if ident.toLowerCase().startsWith 'w'
      openalex = ident
    else if ident.toLowerCase().startsWith 'pmc'
      pmcid = ident
    else
      pmid = ident
  refresh = @refresh if not refresh? and @fn is 'src.openalex.works.find'
  refresh = true if refresh is 0
  if refresh isnt true
    qr = if doi then  'ids.doi.keyword:"https://doi.org/' + doi + '" OR doi.keyword:"https://doi.org/' + doi + '"' else ''
    qr += (if qr then ' OR ' else '') + 'id.keyword:"https://openalex.org/' + openalex + '"' if openalex
    if pmcid
      pml = pmcid.toLowerCase().replace 'pmc', ''
      qr += (if qr then ' OR ' else '') + 'ids.pmcid.keyword:"https://www.ncbi.nlm.nih.gov/pmc/articles/' + pml + '"'
      qr += ' OR locations.landing_page_url.keyword:"https://www.ncbi.nlm.nih.gov/pmc/articles/' + pml + '" OR locations.landing_page_url.keyword:"https://europepmc.org/articles/pmc' + pml + '"'
    if pmid
      qr += (if qr then ' OR ' else '') + 'ids.pmid.keyword:"https://pubmed.ncbi.nlm.nih.gov/' + pmid + '"'
      qr += ' OR locations.landing_page_url.keyword:"https://pubmed.ncbi.nlm.nih.gov/' + pmid + '"'
    found = await @src.openalex.works(doi) if doi
    found = await @src.openalex.works(qr, 1) if not found
    if found and (typeof refresh isnt 'number' or not found.retrievedAt or (Date.now() - refresh) <= found.retrievedAt)
      return found

  if doi
    res = await @fetch ('https://api.openalex.org/works/https://doi.org/' + doi + '?mailto=' + (@S.mail?.to ? 'sysadmin@oa.works') + (if @S.src.openalex?.apikey then '&api_key=' + @S.src.openalex.apikey else '')), {rate: ['openalex', 80]}
  if not res and openalex
    res = await @fetch ('https://api.openalex.org/works/' + openalex + '?mailto=' + (@S.mail?.to ? 'sysadmin@oa.works') + (if @S.src.openalex?.apikey then '&api_key=' + @S.src.openalex.apikey else '')), {rate: ['openalex', 80]}
  if not res and pmid
    res = await @fetch ('https://api.openalex.org/works/pmid:' + pmid + '?mailto=' + (@S.mail?.to ? 'sysadmin@oa.works') + (if @S.src.openalex?.apikey then '&api_key=' + @S.src.openalex.apikey else '')), {rate: ['openalex', 80]}

  if typeof res is 'object' and res.id
    found = await @src.openalex.works._format res
    await @src.openalex.works found
  return found

P.src.openalex.works.doi = (doi, refresh) ->
  refresh = @refresh if not refresh? and @fn is 'src.openalex.works.doi'
  doi ?= @params.doi
  return @src.openalex.works.find doi, undefined, undefined, undefined, refresh


_openalex_load_running = false
P.src.openalex.load = (what, changes, clear, sync, last, toalias) ->
  if _openalex_load_running
    console.log 'Openalex load already running, skipping'
    return false
  _openalex_load_running = true
  started = await @epoch()
  what ?= @params.load ? @params.openalex ? 'works'
  return false if what not in ['works']

  onlyinfo = @params.onlyinfo ? false
  changes ?= @params.changes
  infiles = @S.directory + '/import/openalex/data/' + what

  toalias ?= @params.toalias ? '15032024'
  toalias += '' if typeof toalias is 'number'

  clear ?= @params.clear
  if clear
    console.log 'clearing', what, toalias
    await @index._send 'src_openalex_' + what, '', undefined, false, toalias
    await @sleep 20000
    await @index._send 'src_openalex_' + what, {settings: {number_of_shards: 15}}, undefined, false, toalias
    console.log 'cleared and mapped'
    await @sleep 1000

  last ?= 0
  lasth = ''
  try
    pm = (await fs.readFile infiles + '/manifest').toString()
    for entry in JSON.parse(pm).entries
      esd = entry.url.split('=')[1].split('/')[0]
      de = await @epoch esd
      if de > last
        last = de
        lasth = esd

  sync ?= @params.sync ? false
  if sync
    console.log 'Openalex load syncing', what
    synced = await @_child 'aws', ['s3', 'sync', 's3://openalex/data/' + what, infiles, '--no-sign-request']
    console.log 'Openalex sync returned', synced

  changes = [changes] if typeof changes is 'string'
  if changes is true
    console.log 'Checking for Openalex changes in', what
    changes = []
    if not sync
      await fs.writeFile infiles + '/manifest' + (if onlyinfo then 'info' else ''), await @fetch 'https://openalex.s3.amazonaws.com/data/' + what + '/manifest', buffer: true
      console.log 'Openalex manifest ' + (if onlyinfo then 'temp saved for info' else 'updated')
    for entry in JSON.parse((await fs.readFile infiles + '/manifest' + (if onlyinfo then 'info' else '')).toString()).entries
      de = entry.url.split('=')[1].split('/')[0]
      changes.push(de) if de not in changes and await @epoch(de) > last

  console.log changes, last, lasth
  for change in changes ? []
    console.log 'Openalex checking if sync required for possibly changed files', what, change
    try
      stats = await fs.stat infiles + '/updated_date=' + change
    catch
      await @_child 'aws', ['s3', 'sync', 's3://openalex/data/' + what + '/updated_date=' + change, infiles + '/updated_date=' + change, '--no-sign-request']
      console.log change, 'was not present, now synced'

  caughtup = true # ['2024-02-21', 'part_043'] # set to list of values to match on file name e.g if had to kill earlier part way through
  total = 0
  expectedfiles = 0
  processedfiles = 0
  running = []
  maxrunners = 5

  _dofile = (flo) =>
    batch = []
    for await line from readline.createInterface input: fs.createReadStream(flo).pipe zlib.createGunzip() #, crlfDelay: Infinity
      rec = JSON.parse line.trim().replace /\,$/, ''
      total += 1
      rec = await @src.openalex.works._format rec
      batch.push rec
      if batch.length >= 20000
        console.log 'Openalex ' + what + ' ' + toalias + ' bulk loading', flo, batch.length, total
        await @index._bulk 'src_openalex_' + what, batch, undefined, undefined, false, toalias
        batch = []
    if batch.length
      console.log 'Openalex ' + what + ' ' + toalias + ' bulk loading final set for', flo, batch.length, expectedfiles, processedfiles, total
      await @index._bulk 'src_openalex_' + what, batch, undefined, undefined, false, toalias
    console.log 'removing', flo
    await fs.unlink flo
    processedfiles += 1
    running.splice running.indexOf(flo), 1
    return true

  for updated in await fs.readdir infiles # folder names are like updated_date=2022-04-30
    if not updated.startsWith('manifest') # run any file that exists, and delete once done so not re-used
      for inf in await fs.readdir infiles + '/' + updated
        if not caughtup
          console.log 'awaiting catch up', updated, inf, caughtup
          caughtup = true if updated.includes(caughtup[0]) and (caughtup.length is 1 or inf.includes caughtup[1])
        else
          oe = false #parseInt(inf.split('_')[1]) % 2
          if oe is false or (oe is 0 and S.port is 4006) or (oe is 1 and S.port is 4003)
            expectedfiles += 1
            while running.length is maxrunners
              await @sleep 3000
            flo = infiles + '/' + updated + '/' + inf
            if onlyinfo
              console.log 'Openalex load would run', flo
            else
              running.push flo
              console.log 'Openalex load running', running
              _dofile flo
          else
            console.log 'skipping', oe, inf

      while running.length isnt 0
        await @sleep 5000
      try await fs.rmdir infiles + '/' + updated

  if onlyinfo
    try await fs.unlink infiles + '/manifestinfo'
  else if pm? and Array.isArray(changes) and changes.length
    await fs.writeFile infiles + '/manifestprevious', pm
  ended = await @epoch()
  ret = started: started, took: ended - started, expected: expectedfiles, processed: processedfiles, total: total, sync: sync, last: last, lasth: lasth, changes: changes
  if (total > 0 or (new Date()).getDay() is 1) and not onlyinfo
    dt = await @datetime()
    await @mail to: @S.log?.logs, subject: 'Openalex works load or changes ' + total + ' at ' + dt, text: JSON.stringify ret
  console.log ret
  _openalex_load_running = false
  return ret

P.src.openalex.load._bg = true
P.src.openalex.load._async = true
P.src.openalex.load._log = false
P.src.openalex.load._auth = '@oa.works'

P.src.openalex.changes = (what) ->
  started = await @epoch()
  console.log 'Openalex checking for changes by running load on comparison to manifest'
  ret = await @src.openalex.load undefined, true

  ended = await @epoch()
  took = ended - started
  if @fn isnt 'src.openalex.changes' and P.src.openalex.changes._schedule is 'loop'
    while took < 3600000
      remaining = 3600000 - took
      console.log 'Openalex changes waiting', remaining, 'to loop'
      await @sleep remaining
      ended = await @epoch()
      took = ended - started
  console.log 'Openalex changes took', ended - started
  return ret

P.src.openalex.changes._log = false
P.src.openalex.changes._bg = true
P.src.openalex.changes._async = true
P.src.openalex.changes._auth = '@oa.works'


P.src.openalex.sources = _index: true, _prefix: false
P.src.openalex.sources.load = ->
  await @src.openalex.sources ''
  total = 0
  batch = []
  url = 'https://api.openalex.org/sources?' + (if @S.src.openalex?.apikey then 'api_key=' + @S.src.openalex.apikey + '&' else '') + 'per-page=200&cursor='
  res = await @fetch url + '*'
  while res? and typeof res is 'object' and Array.isArray(res.results) and res.results.length
    for rec in res.results
      rec._id = rec.id.split('/').pop()
      batch.push rec
    if batch.length >= 20000
      total += batch.length
      await @src.openalex.sources batch
      batch = []
    else
      await @sleep 200
    if res.meta?.next_cursor
      res = await @fetch url + encodeURIComponent res.meta.next_cursor
  await @src.openalex.sources(batch) if batch.length
  return total
P.src.openalex.sources.load._async = true
P.src.openalex.sources.load._bg = true
P.src.openalex.sources.load._auth = '@oa.works'



