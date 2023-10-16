
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
  try
    for xc in rec.concepts
      xc.score = Math.floor(xc.score) if xc.score?
  try
    rec._id = rec.doi ? rec.DOI ? rec.ids?.doi
    rec._id = '10.' + rec._id.split('/10.').pop() if rec._id.includes('http') and rec._id.includes '/10.'
    rec._id = rec.id.split('/').pop() if not rec._id or not rec._id.startsWith '10.'
  catch
    rec._id = rec.id.split('/').pop()
  try
    abs = []
    for word of rec.abstract_inverted_index
      abs[n] = word for n in rec.abstract_inverted_index[word]
    rec.abstract = abs.join(' ') if abs.length
  try delete rec.abstract_inverted_index
  return rec

P.src.openalex.works.doi = (doi, refresh) ->
  doi ?= @params.doi
  refresh ?= @params.refresh
  if refresh or not found = await @src.openalex.works 'ids.doi:"https://doi.org/' + doi + '"', 1
    if found = await @fetch 'https://api.openalex.org/works/https://doi.org/' + doi + (if @S.src.openalex?.apikey then '?api_key=' + @S.src.openalex.apikey else '')
      if found.id
        found = await @src.openalex.works._format found
        @waitUntil @src.openalex.works found
  return found

P.src.openalex.load = (what, changes, clear, sync, last) ->
  what ?= @params.load ? @params.openalex ? 'works'
  return false if what not in ['works'] #, 'venues', 'authors', 'institutions', 'concepts']

  clear ?= @params.clear ? false
  sync ?= @params.sync ? false

  if clear is true
    await @src.openalex[what] ''
    await @sleep 60000
  
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going
  maxbatchsize = 10000 # how many records to batch upload at a time
  total = 0
  infiles = @S.directory + '/import/openalex/data/' + what

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
      # can also just import certain types, like at s3://openalex/data/works
      synced = await @_child 'aws', ['s3', 'sync', 's3://openalex', @S.directory + '/import/openalex', '--no-sign-request']
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
  else if sync is true
    console.log 'Openalex load syncing', what
    synced = await @_child 'aws', ['s3', 'sync', 's3://openalex/data/' + what, infiles, '--no-sign-request']
    console.log 'Openalex sync returned', synced

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
  for updated in await fs.readdir infiles # folder names are like updated_date=2022-04-30
    if not updated.startsWith('manifest') and (not changes or changes.length is 0 or updated.split('=')[1] in changes)
      # if we find in future there is no need to download a whole copy of openalex, instead of s3 sync the whole lot it may be better 
      # to just use streams of the files in each change folder direct from s3, and never have to land them on disk
      _dofile = (infile) =>
        batch = []
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
            rec = await @src.openalex.works._format rec
          batch.push rec
          if batch.length >= maxbatchsize
            console.log 'Openalex ' + what + ' bulk loading', updated, infile, batch.length, total
            await @src.openalex[what] batch
            batch = []
        if batch.length
          console.log 'Openalex ' + what + ' bulk loading final set for', updated, infile, batch.length, expectedfiles, processedfiles, total
          await @src.openalex[what] batch
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
P.src.openalex.load._log = false
P.src.openalex.load._auth = 'root'

P.src.openalex.changes = (what, last) ->
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
  queued = 0
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

                if rec._id.startsWith('10.') and rec.authorships? and rec.publication_year in ['2023', '2022', 2023, 2022]
                  doq = false
                  for a in rec.authorships
                    break if doq
                    for i in (a.institutions ? [])
                      break if doq
                      doq = rec._id if i.display_name?
                  if doq
                    try await @report.queue doq, undefined, undefined, undefined, 'changes'
                    queued += 1

              batch.push rec
            
            if batch.length >= 10000
              console.log 'Openalex ' + what + ' ' + filter + ' bulk loading changes', batch.length, total, queued
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

  ended = await @epoch() # schedule this to loop, and run at most every hour
  if @fn isnt 'src.openalex.changes' and ended - started < 3600000
    console.log 'Openalex changes waiting to loop'
    await @sleep 3600000 - (ended - started) 
  console.log 'Openalex changes changed', total, queued
  return total

P.src.openalex.changes._log = false
P.src.openalex.changes._bg = true
P.src.openalex.changes._async = true
#P.src.openalex.changes._auth = 'root'
