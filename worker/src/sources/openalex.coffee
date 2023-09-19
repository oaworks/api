
S.src.openalex ?= {}
try S.src.openalex = JSON.parse SECRETS_OPENALEX

# https://docs.openalex.org/api
# https://docs.openalex.org/download-snapshot/snapshot-data-format
# https://docs.openalex.org/download-snapshot/download-to-your-machine
# aws s3 sync 's3://openalex' 'openalex-snapshot' --no-sign-request

# note for resizing storage volume:
# sudo resize2fs /dev/sdv (or whatever the identity of the volume is)

P.src.openalex = () ->
  return true

P.src.openalex.authors = _index: {settings: {number_of_shards: 9}}, _prefix: false
P.src.openalex.works = _index: {settings: {number_of_shards: 9}}, _prefix: false
P.src.openalex.institutions = _index: true, _prefix: false
P.src.openalex.concepts = _index: true, _prefix: false
P.src.openalex.venues = _index: true, _prefix: false

P.src.openalex.works.doi = (doi, refresh) ->
  doi ?= @params.doi
  refresh ?= @refresh
  if refresh or not found = await @src.openalex.works 'ids.doi:"https://doi.org/' + doi + '"', 1
    if found = await @fetch 'https://api.openalex.org/works/https://doi.org/' + doi + '?api_key=' + @S.src.openalex.apikey
      if found.id? # somehow managed to get back a positive response that had no ID. So can it be a valid record? assume no.
        if found.abstract_inverted_index?
          abs = []
          for word of found.abstract_inverted_index
            abs[n] = word for n in found.abstract_inverted_index[word]
          found.abstract = abs.join(' ') if abs.length
          delete found.abstract_inverted_index
        try
          for xc in found.concepts
            found.score = Math.floor(found.score) if found.score?
        try
          found._id = found.doi ? found.DOI ? found.ids?.doi
          found._id = '10.' + found._id.split('/10.').pop() if found._id.includes('http') and found._id.includes '/10.'
          found._id = found.id.split('/').pop() if not found._id or not found._id.startsWith '10.'
        catch
          found._id = found.id.split('/').pop()
        @waitUntil @src.openalex.works doi.toLowerCase(), found
  return found



P.src.openalex.load = (what, changes, clear, sync, last) ->
  what ?= @params.load ? @params.openalex
  return false if what not in ['works', 'venues', 'authors', 'institutions', 'concepts']

  clear ?= @params.clear ? false
  sync ?= @params.sync ? false

  if clear is true
    await @src.openalex[what] ''
    await @sleep 300000
  
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going
  maxbatchsize = 30000 # how many records to batch upload at a time
  total = 0
  infiles = @S.directory + '/openalex/openalex-snapshot/data/' + what

  if typeof changes is 'string'
    changes = [changes]
  else if changes is true
    console.log 'Checking for Openalex changes in', what
    changes = []
    try
      manifest = JSON.parse (await fs.readFile infiles + '/manifest').toString()
      last = await @epoch manifest.entries[manifest.entries.length-1].url.split('=')[1].split('/')[0]
    catch
      last = 0
    if sync
      synced = await @_child 'aws', ['s3', 'sync', 's3://openalex', @S.directory + '/openalex/openalex-snapshot', '--no-sign-request']
      console.log 'Openalex sync returned', synced
    else
      await fs.writeFile infiles + '/manifest', await @fetch 'https://openalex.s3.amazonaws.com/data/' + what + '/manifest', buffer: true
      console.log 'Openalex manifest updated'
    hasnew = false
    manifest = JSON.parse (await fs.readFile infiles + '/manifest').toString()
    for entry in manifest.entries
      de = entry.url.split('=')[1].split('/')[0]
      if not hasnew
        hasnew = true if (await @epoch de) > last
      changes.push(de) if hasnew and de not in changes
    console.log('Found changes', changes) if changes.length

  if not sync and changes and changes.length
    for change in changes
      console.log 'Openalex syncing files', what, change
      try
        stats = await fs.stat infiles + '/updated_date=' + change
      catch
        await @_child 'aws', ['s3', 'sync', 's3://openalex/data/' + what + '/updated_date=' + change, infiles + '/updated_date=' + change, '--no-sign-request']

  expectedfiles = 0
  processedfiles = 0
  running = 0
  maxrunners = 3
  keys = []
  for updated in await fs.readdir infiles # folder names are like updated_date=2022-04-30
    if not updated.startsWith('manifest') and (not changes or changes.length is 0 or updated.split('=')[1] in changes)
      # if we find in future there is no need to download a whole copy of openalex, instead of s3 sync the whole lot it may be better 
      # to just use streams of the files in each change folder direct from s3, and never have to land them on disk
      _dofile = (infile) =>
        batch = []
        deletes = []
        for await line from readline.createInterface input: fs.createReadStream(infiles + '/' + updated + '/' + infile).pipe zlib.createGunzip() #, crlfDelay: Infinity
          break if total is howmany
          rec = JSON.parse line.trim().replace /\,$/, ''
          total += 1
          if what in ['venues', 'institutions', 'concepts', 'authors']
            rec._id = rec.id.split('/').pop()
            if what is 'authors' and rec.x_concepts?
              for xc in rec.x_concepts
                xc.score = Math.floor(xc.score) if xc.score?
          else if what is 'works'
            try
              for xc in rec.concepts
                xc.score = Math.floor(xc.score) if xc.score?
            try
              rec._id = rec.doi ? rec.DOI ? rec.ids?.doi
              rec._id = '10.' + rec._id.split('/10.').pop() if rec._id.includes('http') and rec._id.includes '/10.'
              rec._id = rec.id.split('/').pop() if not rec._id or not rec._id.startsWith '10.'
            catch
              rec._id = rec.id.split('/').pop()
            deletes.push(rec.id) if changes and rec.id and rec._id and rec._id.startsWith('10.') and rec._id isnt rec.id and prev = await @src.openalex.works {_id: rec.id}, 1
            try
              abs = []
              for word of rec.abstract_inverted_index
                abs[n] = word for n in rec.abstract_inverted_index[word]
              rec.abstract = abs.join(' ') if abs.length
            try delete rec.abstract_inverted_index
          try
            for fk of flattened = await @flatten rec
              if fk not in keys
                keys.push fk
                console.log 'openalex seeing new key', keys.length, fk
          batch.push rec
          if batch.length >= maxbatchsize
            console.log 'Openalex ' + what + ' bulk loading', updated, infile, batch.length, total
            await @src.openalex[what] batch
            batch = []
        await @index._bulk('src_openalex_works', deletes, 'delete') if deletes.length
        await @src.openalex[what](batch) if batch.length
        console.log 'removing', infiles + '/' + updated + '/' + infile
        await fs.unlink infiles + '/' + updated + '/' + infile
        processedfiles += 1
        running -= 1
        return true

      for inf in await fs.readdir infiles + '/' + updated
        console.log 'Openalex load running', running
        expectedfiles += 1
        while running is maxrunners
          await @sleep 5000
          console.log 'Openalex load running', running
        running += 1
        _dofile inf

      while running isnt 0
        await @sleep 5000
      await fs.rmdir infiles + '/' + updated

  console.log expectedfiles, processedfiles, total
  return expected: expectedfiles, processed: processedfiles, total: total

P.src.openalex.load._bg = true
P.src.openalex.load._async = true
P.src.openalex.load._auth = 'root'

P.src.openalex.changes = (what, last) ->
  what ?= @params.changes ? @params.openalex
  last ?= @params.last # can be a date like 2022-12-13 to match the last updated file date on openalex update files
  # if no last, calculate it as previous day? or read last from index?
  last ?= await @date await @epoch() - 86400000
  # doing this only for works now, as it does not appear the other types get updated in the same way any more
  whats = ['works'] #, 'venues', 'authors', 'institutions', 'concepts']
  if what
    return false if what not in whats
  else
    what = whats

  # https://docs.openalex.org/how-to-use-the-api/get-lists-of-entities/paging
  total = 0
  for w in (if Array.isArray(what) then what else [what])
    try
      batch = []
      deletes = []
      cursor = '*'
      # does created count as an updated, or do we also need to to from_created_date? Created appear to be included already, so all good
      url = 'https://api.openalex.org/' + w + '?filter=from_updated_date:' + last + '&api_key=' + @S.src.openalex.apikey + '&per-page=200&cursor='
      res = await @fetch url + cursor
      while res? and typeof res is 'object' and Array.isArray(res.results) and res.results.length
        for rec in res.results
          try
            for xc in rec.concepts
              xc.score = Math.floor(xc.score) if xc.score?
          try
            rec._id = rec.doi ? rec.DOI ? rec.ids?.doi
            rec._id = '10.' + rec._id.split('/10.').pop() if rec._id.includes('http') and rec._id.includes '/10.'
            rec._id = rec.id.split('/').pop() if not rec._id or not rec._id.startsWith '10.'
          catch
            rec._id = rec.id.split('/').pop()
          deletes.push(rec.id) if rec.id and rec._id and rec._id.startsWith('10.') and rec._id isnt rec.id and prev = await @src.openalex.works {_id: rec.id}, 1
          try
            abs = []
            for word of rec.abstract_inverted_index
              abs[n] = word for n in rec.abstract_inverted_index[word]
            rec.abstract = abs.join(' ') if abs.length
          try delete rec.abstract_inverted_index

          batch.push rec
        
        if batch.length >= 30000
          console.log 'Openalex ' + what + ' bulk loading changes', batch.length, total
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
      await @index._bulk('src_openalex_works', deletes, 'delete') if deletes.length

  return total

P.src.openalex.changes._bg = true
P.src.openalex.changes._async = true
P.src.openalex.changes._auth = 'root'

P.src.openalex.fixids = () ->
  total = 0
  deletes = []
  expected = await @src.openalex.works.count 'NOT DOI:* AND NOT doi:* AND NOT ids.doi:*'
  console.log 'openalex fix IDs expecting to process', expected
  for await rec from @index._for 'src_openalex_works', 'NOT DOI:* AND NOT doi:* AND NOT ids.doi:*', scroll: '30m', include: ['_id', 'id']
    console.log(total, deletes.length) if total % 100 is 0
    total += 1
    deletes.push(rec.id) if count = await @src.openalex.works.count 'id.keyword:"' + rec.id + '" AND (DOI:* OR doi:* OR ids.doi:*)'
    if deletes.length is 30000
      await @index._bulk 'src_openalex_works', deletes, 'delete'
      deletes = []
      console.log 'deleting obsoletes from openalex works', total, expected
  await @index._bulk('src_openalex_works', deletes, 'delete') if deletes.length
  console.log 'deleting obsoletes from openalex works finished having done', total, expected
  return total
P.src.openalex.fixids._bg = true
P.src.openalex.fixids._async = true
P.src.openalex.fixids._auth = 'root'

'''P.src.openalex.loadchanges = (what, last) ->
  what ?= @params.changes ? @params.openalex
  last ?= @params.last # can be a date like 2022-12-13 to match the last updated file date on openalex update files
  whats = ['works', 'venues', 'authors', 'institutions', 'concepts']
  if what
    return false if what not in whats
  else
    what = whats

  total = 0
  for w in (if Array.isArray(what) then what else [what])
    total += await @src.openalex.load w, true, undefined, undefined, last
    
  return total

P.src.openalex.loadchanges._bg = true
P.src.openalex.loadchanges._async = true
P.src.openalex.loadchanges._auth = 'root'
'''

P.src.openalex.latest = (what) ->
  what ?= @params.latest ? @params.openalex
  whats = ['works', 'venues', 'authors', 'institutions', 'concepts']
  return false if what not in whats

  infiles = @S.directory + '/openalex/openalex-snapshot/data/' + what

  res =
    last: undefined
    changes: []
    count: 0
    manifest:
      previous: JSON.parse (await fs.readFile infiles + '/manifest').toString()
      latest: await @fetch 'https://openalex.s3.amazonaws.com/data/' + what + '/manifest'

  res.last = res.manifest.previous.entries[res.manifest.previous.entries.length-1].url.split('=')[1].split('/')[0]
  last = await @epoch res.last

  hasnew = false
  for entry in res.manifest.latest.entries
    de = entry.url.split('=')[1].split('/')[0]
    if not hasnew
      hasnew = true if ( await @epoch de) > last
    if hasnew
      res.changes.push(de) if de not in res.changes
      res.count += entry.meta.record_count

  return res