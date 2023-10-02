
S.src.oadoi ?= {}
try S.src.oadoi = JSON.parse SECRETS_OADOI

'''P.src.oadoi = (doi) ->
  doi ?= @params?.oadoi ? @params?.doi
  if typeof doi is 'string' and doi.startsWith '10.'
    await @sleep 900
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return'''
    
#P.src.oadoi._index = settings: number_of_shards: 9
P.src.oadoi = _index: settings: number_of_shards: 9
P.src.oadoi._key = 'doi'
P.src.oadoi._prefix = false

P.src.oadoi.search = (doi) ->
  doi ?= @params?.oadoi ? @params?.doi ? @params?.search
  if typeof doi is 'string' and doi.startsWith '10.'
    await @sleep 900
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return

P.src.oadoi.hybrid = (issns) ->
  # there is a concern OADOI sometimes says a journal is closed on a particular 
  # record when it is actually a hybrid. So check if some records for 
  # a given journal are hybrid, and if so the whole journal is hybrid.
  issns ?= @params.hybrid ? @params.issn ? @params.issns
  if typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    q = 'journal_issns.keyword:*' + issns.join('* OR journals_issns.keyword:*') + '*'
    q = '(' + q + ')' if q.includes ' OR '
    closed = await @src.oadoi.count q + ' AND oa_status:"closed"'
    hybrid = await @src.oadoi.count q + ' AND oa_status:"hybrid"'
    if closed and hybrid / closed > .001
      return true
    else
      return false
  else
    return

# if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
# https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-




# https://support.unpaywall.org/support/solutions/articles/44001867302-unpaywall-change-notes
# https://unpaywall.org/products/data-feed/changefiles
P.src.oadoi.load = () ->
  batchsize = 30000 # how many records to batch upload at a time - 20k ran smooth, took about 6 hours.
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  infile = @S.directory + '/oadoi/snapshot.jsonl' # where the lines should be read from
  # could also be possible to stream this from oadoi source via api key, which always returns the snapshot from the previous day 0830
  # http://api.unpaywall.org/feed/snapshot?api_key=
  lastfile = @S.directory + '/oadoi/last' # where to record the ID of the last item read from the file
  try lastrecord = (await fs.readFile lastfile).toString() if not @refresh

  await @src.oadoi('') if not lastrecord

  total = 0
  batch = []

  # it appears it IS gz compressed even if they provide it without the .gz file extension
  for await line from readline.createInterface input: fs.createReadStream(infile).pipe zlib.createGunzip() #, crlfDelay: Infinity
    break if total is howmany
    try
      rec = JSON.parse line.trim().replace /\,$/, ''
      if not lastrecord or lastrecord is rec.doi
        lastrecord = undefined
        total += 1
        rec._id = rec.doi.replace /\//g, '_'
        batch.push rec
        if batch.length is batchsize
          console.log 'OADOI bulk loading', batch.length, total
          await @src.oadoi batch
          batch = []
          await fs.writeFile lastfile, rec.doi

  await @src.oadoi(batch) if batch.length
  console.log total
  return total

P.src.oadoi.load._bg = true
P.src.oadoi.load._async = true
P.src.oadoi.load._auth = 'root'


P.src.oadoi.changes = (oldest) ->
  batchsize = 30000
  # the 2021-08-19 file was very large, 139M compressed and over 1.2GB uncompressed, and trying to stream it kept resulting in zlib unexpected end of file error
  # suspect it can't all be streamed before timing out. So write file locally then import then delete, and write 
  # error file dates to a list file, and manually load them separately if necessary

  uptofile = @S.directory + '/oadoi/upto' # where to record the ID of the most recent change day file that's been processed up to
  errorfile = @S.directory + '/oadoi/errors'

  oldest ?= @params.changes
  if not oldest
    try oldest = parseInt (await fs.readFile uptofile).toString()
  if not oldest
    try
      last = await @src.oadoi '*', size: 1, sort: updated: order: 'desc'
      oldest = (new Date(last.updated)).valueOf()
  if not oldest # or could remove this to just allow running back through all
    console.log 'Timestamp day to work since is required - run load first to auto-generate'
    return

  changes = await @fetch 'https://api.unpaywall.org/feed/changefiles?api_key=' + @S.src.oadoi.apikey + '&interval=day'
  #seen = []
  #dups = 0
  counter = 0
  days = 0
  upto = false
  for lr in changes.list.reverse() # list objects go back in order from most recent day
    lm = (new Date(lr.last_modified)).valueOf()
    console.log lr.last_modified, lm, oldest, last?.updated
    #if oldest and lm <= oldest
    #  break
    if lr.filetype is 'jsonl' and (not oldest or lm > oldest) #and lr.date not in ['2021-08-19'] # streaming this file (and some others) causes on unexpected end of file error
      console.log 'OADOI importing changes for', lr.last_modified
      days += 1
      batch = []

      lc = 0
      lfl = @S.directory + '/oadoi/' + lr.date + '.jsonl.gz'

      resp = await fetch lr.url
      wstr = fs.createWriteStream lfl
      await new Promise (resolve, reject) =>
        resp.body.pipe wstr
        resp.body.on 'error', reject
        wstr.on 'finish', resolve

      #for await line from readline.createInterface input: (await fetch lr.url).body.pipe zlib.createGunzip().on('error', (err) -> fs.appendFile(errorfile, lr.date); console.log err)
      for await line from readline.createInterface input: fs.createReadStream(lfl).pipe zlib.createGunzip()
        upto = lm #if upto is false
        lc += 1
        rec = JSON.parse line.trim().replace /\,$/, ''
        #if rec.doi in seen
        #  dups += 1
        #else
        #seen.push rec.doi # work backwards so don't bother saving old copies of the same records
        rec._id = rec.doi.replace /\//g, '_'
        batch.push rec
        counter += 1
        if batch.length >= batchsize
          console.log 'OADOI bulk loading changes', days, batch.length, lc #, seen.length, dups
          await @src.oadoi batch
          batch = []

      await @src.oadoi(batch) if batch.length
      fs.unlink lfl

    if upto
      try await fs.writeFile uptofile, upto
    
  console.log days, counter #, seen.length, dups
  return counter #seen.length

P.src.oadoi.changes._bg = true
P.src.oadoi.changes._async = true
P.src.oadoi.changes._auth = 'root'
P.src.oadoi.changes._notify = false




