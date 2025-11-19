
S.src.openalex ?= {}
try S.src.openalex = JSON.parse SECRETS_OPENALEX

# https://docs.openalex.org/api
# https://docs.openalex.org/download-snapshot/snapshot-data-format
# https://docs.openalex.org/download-snapshot/download-to-your-machine

# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
# unzip awscliv2.zip
# sudo ./aws/install

# aws s3 sync 's3://openalex' 'openalex' --no-sign-request

# note for resizing storage volume:
# sudo resize2fs /dev/sdv (or whatever the identity of the volume is)

P.src.openalex = () ->
  return true

P.src.openalex.works = _index: {settings: {number_of_shards: 15}}, _prefix: false
#P.src.openalex.authors = _index: {settings: {number_of_shards: 15}}, _prefix: false
#P.src.openalex.institutions = _index: true, _prefix: false
#P.src.openalex.concepts = _index: true, _prefix: false
#P.src.openalex.venues = _index: true, _prefix: false

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
  return rec

P.src.openalex.works.doi = (doi, refresh, save) ->
  doi ?= @params.doi
  refresh = @refresh if not refresh? and @fn is 'src.openalex.works.doi'
  save ?= @params.save ? true
  if refresh or not found = await @src.openalex.works 'ids.doi.keyword:"https://doi.org/' + doi + '"', 1
    if found = await @fetch 'https://api.openalex.org/works/https://doi.org/' + doi + (if @S.src.openalex?.apikey then '?api_key=' + @S.src.openalex.apikey else '')
      if found.id
        found = await @src.openalex.works._format found
        await @src.openalex.works(found) if save
  return found

P.src.openalex.works.title = (title) ->
  if title ?= @params.title
    return await @src.openalex.works 'title:"' + title + '"', 1
  else
    return

P.src.openalex.oa = type: (issns) ->
  issns ?= @params.type ? @params.issn ? @params.issns
  if typeof issns is 'string' and issns.startsWith('10.') and rec = await @src.openalex.works.doi issns
    issns = rec.primary_location?.source?.issn
  if typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN ? issns.primary_location?.source?.issn
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    types = await @src.openalex.works.terms 'open_access.oa_status.keyword', 'locations.source.issn.keyword:"' + issns.join('" OR locations.source.issn.keyword:') + '"'
    if types.length is 1
      calculated = types[0].term
    else if types.length is 0
      calculated = 'unknown'
    else if JSON.stringify(types).toLowerCase().includes '"hybrid"'
      calculated = await @src.openalex.hybrid issns
    else if types[1].count / types[0].count > .001
      calculated = types[0].term
    else
      calculated = 'unknown'
    return issn: issns, calculated: calculated, types: types
  else
    return issn: issns, calculated: '', types: []

P.src.openalex.manifest = ->
  what = @params.manifest ? @params.openalex ? 'works'
  return false if what not in ['works']
  res = last: '', previous:'', manifest: await @fetch 'https://openalex.s3.amazonaws.com/data/' + what + '/manifest'
  _ls = (m) =>
    ret = ''
    last = 0
    for entry in m.entries
      esd = entry.url.split('=')[1].split('/')[0]
      de = await @epoch esd
      if de > last
        last = de
        ret = esd
    return ret
  res.last = await _ls res.manifest
  try res.previous = await _ls JSON.parse (await fs.readFile @S.directory + '/import/openalex/data/' + what + '/manifest').toString()
  return res

_openalex_load_running = false
P.src.openalex.load = (what, changes, clear, sync, last, toalias) ->
  if _openalex_load_running
    console.log 'Openalex load already running, skipping'
    return false
  _openalex_load_running = true
  started = await @epoch()
  what ?= @params.load ? @params.openalex ? 'works'
  return false if what not in ['works'] #, 'venues', 'authors', 'institutions', 'concepts']

  onlyinfo = @params.onlyinfo ? false
  changes ?= @params.changes
  infiles = @S.directory + '/import/openalex/data/' + what

  toalias ?= @params.toalias
  toalias += '' if typeof toalias is 'number'
  toalias = '15032024'

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
  if sync # can import all or certain types, e.g s3://openalex or s3://openalex/data/works
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
    # if we find in future there is no need to download a whole copy of openalex, instead of s3 sync the whole lot it may be better 
    # to just use streams of the files in each change folder direct from s3, and never have to land them on disk
    batch = []
    for await line from readline.createInterface input: fs.createReadStream(flo).pipe zlib.createGunzip() #, crlfDelay: Infinity
      rec = JSON.parse line.trim().replace /\,$/, ''
      total += 1
      #if what in ['venues', 'institutions', 'concepts', 'authors']
      #  rec._id = rec.id.split('/').pop()
      #  if what is 'authors' and rec.x_concepts?
      #    for xc in rec.x_concepts
      #      xc.score = Math.floor(xc.score) if xc.score?
      #else if what is 'works'
      batch.push await @src.openalex.works._format rec
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
    if not updated.startsWith('manifest') #and (not changes? or updated.split('=')[1] in changes) # run any file that exists, and delete once done so not re-used
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
#P.src.openalex.load._async = true
P.src.openalex.load._log = false
P.src.openalex.load._auth = 'root'

P.src.openalex.changes = (what) ->
  started = await @epoch()
  console.log 'Openalex checking for changes by running load on comparison to manifest'
  ret = await @src.openalex.load undefined, true

  ended = await @epoch() # schedule this to loop, and run at most every hour
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
P.src.openalex.changes._auth = 'root'


# https://docs.openalex.org/api-entities/sources/get-lists-of-sources
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



P.src.openalex.hybrid = (issns) ->
  issns ?= @params.hybrid ? @params.issn ? @params.issns
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    q = '(locations.source.issn.keyword:"' + issns.join('" OR locations.source.issn.keyword:"') + '" OR locations.source.issn_l.keyword:"' + issns.join('" OR locations.source.issn_l.keyword:"') + '")'
    closed = await @src.openalex.works.count q + ' AND open_access.oa_status:"closed"'
    hybrid = await @src.openalex.works.count q + ' AND open_access.oa_status:"hybrid"'
    #other = await @src.openalex.works.count q + ' AND NOT open_access.oa_status:"closed" AND NOT open_access.oa_status:"hybrid"'
    return closed and hybrid / closed > .001
  else
    return





'''P.src.openalex.changes = (what, last) ->
  started = await @epoch()
  what ?= @params.changes ? @params.openalex ? 'works'
  last = {updated: last} if typeof last isnt 'object'
  last ?= {}
  if @params.last # can be a date like 2022-12-13 to match the last updated file date on openalex update files
    last.updated = @params.last
    last.created = @params.last
  # if no last, calculate it as previous day? or read last from index?
  if not last.updated? or not last.created?
    try last.updated = (await @src.openalex.works 'updated_date:*', size:1, sort: updated_date:'desc').updated_date
    try last.created = (await @src.openalex.works 'created_date:*', size:1, sort: created_date:'desc').created_date
  last.updated ?= (await @datetime await @epoch() - 86400000).replace 'Z', '000' # datetime format for openalex (ISO) 2023-09-25T22:33:51.835860
  last.created ?= (await @datetime await @epoch() - 86400000).replace 'Z', '000'
  # doing this only for works now, as it does not appear the other types get updated in the same way any more
  whats = ['works'] #, 'venues', 'authors', 'institutions', 'concepts']
  if what
    return false if what not in whats
  else
    what = whats

  # https://docs.openalex.org/how-to-use-the-api/get-lists-of-entities/paging
  console.log 'Openalex changes checking from', last
  total = 0
  queued = []
  for w in (if Array.isArray(what) then what else [what])
    for filter in ['updated'] #, 'created'] # apparently, now, (2/10/2023) all records do have an updated_date... 
      if (await @epoch(last.updated)) < started - 3600000 # if it has been at least an hour since something was updated...
        batch = []
        cursor = '*'
        # doing created and updated separately because although we initially thought updated would include created, there is suggestions it does not, in missing records
        # https://github.com/ourresearch/openalex-api-tutorials/blob/main/notebooks/getting-started/premium.ipynb
        url = 'https://api.openalex.org/' + w + '?filter=from_' + filter + '_date:' + last[filter] + '&api_key=' + @S.src.openalex.apikey + '&per-page=200&cursor='
        console.log 'Openalex changes querying', url + cursor
        try
          res = await @fetch url + cursor
          try console.log 'Openalex changes query retrieved', res.results.length
          while res? and typeof res is 'object' and Array.isArray(res.results) and res.results.length
            for rec in res.results
              if w is 'works'
                rec = await @src.openalex.works._format rec

                #if rec._id.startsWith('10.') and rec.authorships? and rec.publication_year in ['2023', '2022', 2023, 2022]
                #  doq = false
                #  for a in rec.authorships
                #    break if doq
                #    for i in (a.institutions ? [])
                #      if i.display_name?
                #        queued.push rec._id
                #        doq = true
                #        break

              batch.push rec
            
            if batch.length >= 10000
              console.log 'Openalex ' + what + ' ' + filter + ' bulk loading changes', batch.length, total, queued.length
              total += batch.length
              await @src.openalex[what] batch
              batch = []

            if res.meta?.next_cursor
              cursor = res.meta.next_cursor
              res = await @fetch url + encodeURIComponent cursor
      
        if batch.length
          total += batch.length
          await @src.openalex[what] batch
          batch = []

  await @report.queue(queued, undefined, undefined, undefined, 'changes') if queued.length

  ended = await @epoch() # schedule this to loop, and run at most every hour
  if @fn isnt 'src.openalex.changes' and ended - started < 3600000
    console.log 'Openalex changes waiting to loop'
    await @sleep 3600000 - (ended - started) 
  console.log 'Openalex changes changed', total, queued.length
  return total
'''