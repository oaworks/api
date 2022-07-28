
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

P.src.openalex.load = (what, changes, clear, sync) ->
  what ?= @params.load ? @params.openalex
  return false if what not in ['works', 'venues', 'authors', 'institutions', 'concepts']

  clear ?= @params.clear ? false
  sync ?= @params.sync ? false

  await @src.openalex[what]('') if clear is true
  
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going
  batchsize = 30000 # how many records to batch upload at a time
  total = 0
  batch = []
  infiles = @S.directory + '/openalex/openalex-snapshot/data/' + what

  if typeof changes is 'string'
    changes = [changes]
  else if changes is true
    console.log 'Checking for Openalex changes in', what
    changes = []
    manifest = JSON.parse (await fs.readFile infiles + '/manifest').toString()
    last = await @epoch manifest.entries[manifest.entries.length-1].url.split('=')[1].split('/')[0]
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
      await @_child 'aws', ['s3', 'sync', 's3://openalex/data/' + what + '/updated_date=' + change, infiles + '/updated_date=' + change, '--no-sign-request']

  for updated in await fs.readdir infiles # folder names are like updated_date=2022-04-30
    if updated isnt 'manifest' and (not changes or changes.length is 0 or updated.split('=')[1] in changes)
      # if we find in future there is no need to download a whole copy of openalex, instead of s3 sync the whole lot it may be better 
      # to just use streams of the files in each change folder direct from s3, and never have to land them on disk
      for infile in await fs.readdir infiles + '/' + updated
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
              rec._id = rec.doi ? rec.DOI
              rec._id = '10.' + rec._id.split('/10.').pop() if rec._id.includes('http') and rec._id.includes '/10.'
              rec._id = rec.id.split('/').pop() if not rec._id or not rec._id.startsWith '10.'
            catch
              rec._id = rec.id.split('/').pop()
            if rec.abstract_inverted_index?
              abs = []
              for word of rec.abstract_inverted_index
                abs[n] = word for n in rec.abstract_inverted_index[word]
              rec.abstract = abs.join(' ') if abs.length
              delete rec.abstract_inverted_index
          batch.push rec
          if batch.length is batchsize
            console.log 'Openalex ' + what + ' bulk loading', updated, infile, batch.length, total
            await @src.openalex[what] batch
            batch = []
        console.log 'removing', infiles + '/' + updated + '/' + infile
        await fs.unlink infiles + '/' + updated + '/' + infile
      await fs.rmdir infiles + '/' + updated

  await @src.openalex[what](batch) if batch.length
  console.log total
  return total

P.src.openalex.load._bg = true
P.src.openalex.load._async = true
P.src.openalex.load._auth = 'root'

P.src.openalex.changes = (what) ->
  what ?= @params.changes ? @params.openalex
  whats = ['works', 'venues', 'authors', 'institutions', 'concepts']
  if what
    return false if what not in whats
  else
    what = whats

  total = 0
  for w in (if Array.isArray(what) then what else [what])
    total += await @src.openalex.load w, true
    
  return total

P.src.openalex.changes._bg = true
P.src.openalex.changes._async = true
P.src.openalex.changes._auth = 'root'
# add changes onto a schedule as well



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