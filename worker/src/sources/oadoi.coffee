
S.src.oadoi ?= {}
try S.src.oadoi = JSON.parse SECRETS_OADOI

P.src.oadoi = _index: settings: number_of_shards: 9
P.src.oadoi._key = 'doi'
P.src.oadoi._prefix = false

P.src.oadoi.search = (doi) ->
  doi ?= @params.oadoi ? @params.doi ? @params.search
  if typeof doi is 'string' and doi.startsWith '10.'
    await @sleep 900
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return

P.src.oadoi.doi = (doi, refresh) ->
  doi ?= @params.doi
  refresh = @refresh if not refresh? and @fn is 'src.oadoi.doi'
  if typeof doi is 'string' and doi.startsWith '10.'
    if refresh isnt true and exists = await @src.oadoi doi
      if typeof refresh isnt 'number' or (exists.updated? and (new Date(exists.updated).valueOf()) > (Date.now() - refresh))
        return exists

    try
      console.log 'getting from OADOI', doi
      await @sleep 500
      url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
      if res = await @fetch url
        if res.doi
          try await @src.oadoi await @src.oadoi._format res
          return res
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

P.src.oadoi.oa = type: (issns) ->
  issns ?= @params.type ? @params.issn ? @params.issns
  if typeof issns is 'string' and issns.startsWith('10.') and rec = await @src.oadoi.doi issns
    issns = rec.journal_issns
  if issns and typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    types = await @src.oadoi.terms 'oa_status.keyword', 'journal_issns.keyword:*' + issns.join('* OR journals_issns.keyword:*') + '*'
    if types.length is 1
      calculated = types[0].term
    else if types.length is 0
      calculated = 'unknown'
    else if JSON.stringify(types).toLowerCase().includes '"hybrid"'
      calculated = await @src.oadoi.hybrid issns
    else if types[1].count / types[0].count > .001
      calculated = types[0].term
    else
      calculated = 'unknown'
    return issn: issns, calculated: calculated, types: types
  else
    return issn: issns, calculated: '', types: []

# if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
# https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-




# https://support.unpaywall.org/support/solutions/articles/44001867302-unpaywall-change-notes
# https://unpaywall.org/products/data-feed/changefiles
P.src.oadoi.load = (url, tgt, toalias, clear, esurl) ->
  url ?= @params.url ? 'https://api.unpaywall.org/feed/snapshot'
  started = await @epoch()
  batchsize = 30000 # how many records to batch upload at a time - 20k ran smooth, took about 6 hours.
  #howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  infile = @S.directory + '/import/oadoi/snapshot.jsonl' # where the lines should be read from
  # could also be possible to stream this from oadoi source via api key, which always returns the snapshot from the previous day 0830
  # streaming caused timeouts so download first if not present
  # http://api.unpaywall.org/feed/snapshot?api_key=
  try
    stats = await fs.stat infile # check if file exists in async fs promises which does not have .exists
  catch
    console.log 'OADOI downloading snapshot'
    url += (if url.includes('?') then '&' else '?') + 'api_key=' + @S.src.oadoi.apikey if not url.includes 'api_key='
    console.log url
    resp = await fetch url
    wstr = fs.createWriteStream infile
    await new Promise (resolve, reject) =>
      resp.body.pipe wstr
      resp.body.on 'error', reject
      wstr.on 'finish', resolve
    console.log 'snapshot downloaded'

  #lastfile = @S.directory + '/import/oadoi/last' # where to record the ID of the last item read from the file
  #try lastrecord = (await fs.readFile lastfile).toString() if not @refresh

  tgt ?= 'src_oadoi'
  toalias ?= @params.toalias
  toalias += '' if typeof toalias is 'number'
  clear ?= @params.clear
  #esurl = ''

  console.log 'loading oadoi', tgt, toalias, esurl
  if clear #if not lastrecord
    try
      await @index._send tgt, '', undefined, false, toalias, esurl
      console.log 'cleared'
      await @sleep 20000
    await @index._send tgt, {settings: {number_of_shards: 9}}, undefined, false, toalias, esurl
    console.log 'mapped'
    await @sleep 5000

  total = 0
  batches = []
  batch = []
  lines = ''
  complete = false

  _batch = =>
    if batches.length
      pb = batches.shift()
      total += pb.length
      console.log 'OADOI bulk loading', pb.length, total, batches.length
      await @index._bulk tgt, pb, undefined, undefined, false, toalias, esurl

  '''
  # it appears it IS gz compressed even if they provide it without the .gz file extension
  for await line from readline.createInterface input: fs.createReadStream(infile).pipe zlib.createGunzip() #, crlfDelay: Infinity
  '''

  strm = fs.createReadStream(infile) #.pipe zlib.createGunzip() # 2025 reload had a Z_BUF_ERROR so tried manually decompressing first
  strm.on 'data', (chunk) =>
    line = chunk.toString 'utf8'
    lines += line if typeof line is 'string' and line
    while lines.includes '\n'
      [lp, lines] = lines.replace('\n', 'X0X0X0X0X0X0X0X0X0X0X0').split('X0X0X0X0X0X0X0X0X0X0X0') # cheap split on first occurrence
      rec = {}
      try rec = JSON.parse lp #.trim().replace /\,$/, ''
      if rec?.doi
        rec = await @src.oadoi._format rec
        batch.push rec
      else
        console.log 'oadoi load failed to parse record from string', lp
      if batch.length is batchsize
        batches.push batch
        batch = []
        _batch()
    lines ?= ''

  strm.on 'error', (err) => console.log 'oadoi load file stream error', JSON.stringify err
  strm.on 'end', () =>
    console.log 'stream complete for oadoi load'
    complete = true

  while not complete
    console.log 'oadoi load streaming file', lines.length, total, Math.floor((Date.now()-started)/1000/60) + 'm'
    await @sleep 30000
  while batches.length
    await _batch()

  ended = Date.now()
  console.log 'oadoi load complete', total, started, ended, Math.floor((ended-started)/1000/60) + 'm'
  return total

P.src.oadoi.load._bg = true
P.src.oadoi.load._async = true
P.src.oadoi.load._log = false
P.src.oadoi.load._auth = 'root'


# https://groups.google.com/g/unpaywall/c/0nEpQ-ImE-4
P.src.oadoi.load2025 = ->
  # use the full file to rebuild
  # https://api.unpaywall.org/full-snapshot?api_key=myapikey
  # 2025 was a single 36G jsonl.gz file, manually downloaded and unzipped
  return @src.oadoi.load undefined, undefined, '2025', true, (if @S.dev then 'http://10.108.0.3:9200' else undefined)
P.src.oadoi.load2025._bg = true
P.src.oadoi.load2025._async = true
P.src.oadoi.load2025._log = false
P.src.oadoi.load2025._auth = 'root'

P.src.oadoi['2025'] = _index: true
P.src.oadoi['2025']._key = 'doi'
P.src.oadoi['2025']._prefix = false


P.src.oadoi.changes = (oldest, tgt, toalias, esurl) ->
  batchsize = 30000
  # the 2021-08-19 file was very large, 139M compressed and over 1.2GB uncompressed, and trying to stream it kept resulting in zlib unexpected end of file error
  # suspect it can't all be streamed before timing out. So write file locally then import then delete, and write 
  # error file dates to a list file, and manually load them separately if necessary

  tgt ?= 'src_oadoi'
  toalias ?= @params.toalias
  toalias += '' if typeof toalias is 'number'
  toalias = '2025'

  # where to record the ID of the most recent change day file that's been processed up to
  uptofile = @S.directory + '/import/oadoi/upto' + (if toalias then '_' + toalias else '')
  #errorfile = @S.directory + '/import/oadoi/errors'

  oldest ?= @params.changes
  if not oldest
    try oldest = parseInt (await fs.readFile uptofile).toString()
  if not oldest
    try
      #last = await @src.oadoi '*', size: 1, sort: updated: order: 'desc'
      #oldest = (new Date(last.updated)).valueOf()
      q = await @index.translate '*', {size: 1, sort: {updated: {order: 'desc'}}}
      qrr = await @index._send tgt + '/_search', q, undefined, false, toalias, esurl
      last = qrr.hits.hits[0]._source
      oldest = last.updated
  if typeof oldest is 'string'
    try
      oldest = (new Date(oldest)).valueOf()
    catch
      oldest = parseInt oldest
  if typeof oldest isnt 'number' # or could remove this to just allow running back through all
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
      lfl = @S.directory + '/import/oadoi/' + lr.date + '.jsonl.gz'

      resp = await fetch lr.url
      wstr = fs.createWriteStream lfl
      await new Promise (resolve, reject) =>
        resp.body.pipe wstr
        resp.body.on 'error', reject
        wstr.on 'finish', resolve

      #for await line from readline.createInterface input: (await fetch lr.url).body.pipe zlib.createGunzip().on('error', (err) -> fs.appendFile(errorfile, lr.date); console.log err)
      for await line from readline.createInterface input: fs.createReadStream(lfl).pipe zlib.createGunzip()
        upto = lm # if upto is false
        lc += 1
        rec = JSON.parse line.trim().replace /\,$/, ''
        rec = await @src.oadoi._format rec
        batch.push rec
        counter += 1
        if batch.length >= batchsize
          console.log 'OADOI bulk loading changes', days, batch.length, lc #, seen.length, dups
          await @index._bulk tgt, batch, undefined, undefined, false, toalias, esurl
          batch = []

      if batch.length
        await @index._bulk tgt, batch, undefined, undefined, false, toalias, esurl
      fs.unlink lfl

    if upto
      try await fs.writeFile uptofile, upto
  
  dt = await @datetime()
  await @mail to: @S.log?.logs, subject: 'OADOI changes ' + counter + ' at ' + dt, text: JSON.stringify 'Changes found ' + counter + ' over ' + days + ' for ' + oldest + ' to ' + upto
  console.log 'oadoi changes complete', days, counter #, seen.length, dups
  return counter #seen.length

P.src.oadoi.changes._bg = true
P.src.oadoi.changes._async = true
P.src.oadoi.changes._log = false
P.src.oadoi.changes._auth = 'root'
P.src.oadoi.changes._notify = false



P.src.oadoi._format = (rec) ->
  # given a record direct from oadoi fix it so that it can be indexed.
  # known issues - they use "deprecated" string in values that used to be dates, which breaks date typing.
  fixes = ['updated', 'evidence']
  for loc in (rec.oa_locations ? [])
    for k in fixes
      loc[k] = undefined if loc[k] and typeof loc[k] is 'string' and loc[k].includes 'deprecated'
  for ol in ['best_oa_location', 'first_oa_location']
    if rec[ol]?
      for k in fixes
        rec[ol][k] = undefined if rec[ol][k] and typeof rec[ol][k] is 'string' and rec[ol][k].includes 'deprecated'
  rec._id = rec.doi.replace(/\//g, '_').toLowerCase()
  return rec

