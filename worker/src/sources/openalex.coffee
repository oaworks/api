
# https://docs.openalex.org/api
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

  clear ?= @params.clear ? true
  sync ?= @params.sync ? true

  await @src.openalex[what]('') if clear is true
  
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going
  batchsize = 30000 # how many records to batch upload at a time
  total = 0
  batch = []
  infiles = @S.directory + '/openalex/openalex-snapshot/data/' + what

  if typeof changes is 'string'
    changes = [changes]
  else if changes is true
    console.log 'Checking for Openalex changes'
    changes = []
    manifest = JSON.parse (await fs.readFile infiles + '/manifest').toString()
    console.log manifest
    last = manifest.entries[manifest.entries.length-1].url.split('=')[1].split('/')[0]
    #if sync
    #  synced = await @_child 'aws', ['s3', 'sync', 's3://openalex', @S.directory + '/openalex/openalex-snapshot', '--no-sign-request']
    #  console.log 'sync returned', synced
    hasnew = false
    manifest = JSON.parse (await fs.readFile infiles + '/manifest').toString()
    for entry in manifest.entries
      hasnew = true if entry.url.includes last
      if hasnew and not entry.url.includes last
        ne = entry.url.split('=')[1].split('/')[0]
        changes.push(ne) if ne not in changes
    console.log('Found changes', changes) if changes.length
    # TODO could add some maintenance to get rid of old updated files that are no longer needed
  
  if not changes or (Array.isArray(changes) and changes.length)
    for updated in await fs.readdir infiles # folder names are like updated_date=2022-04-30
      if updated isnt 'manifest' and (not changes or updated.split('=')[1] in changes)
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
  