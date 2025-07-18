
# https://ror.readme.io/docs/rest-api

# NOTE, TODO, ROR will update their API in 2025:
# https://ror.org/blog/2025-06-11-v1-sunset/

P.src.ror = _index: true, _prefix: false

P.src.ror.query = (q) ->
  q ?= @params.query ? @params.q
  if typeof q is 'string'
    return @fetch 'https://api.ror.org/organizations?query="' + q + '"'
  return

P.src.ror.ror = (rid, refresh) ->
  refresh ?= @refresh
  rid ?= @params.ror
  if typeof rid is 'string' and not rid.includes ' '
    rid = rid.split('/').pop() # just in case it was the full ROR URL (which is their official ID)
    if rid.length < 11 # are all RORs 9 long...?
      res = if refresh then undefined else await @src.ror rid
      if res?.id or res?.hits?.total is 1
        return if res.id then res else res.hits.hits[0]._source
      else
        res = await @fetch 'https://api.ror.org/organizations/' + rid
        if res?.id
          rr = await @src.ror._format res
          @waitUntil @src.ror rr
          return rr
  return

P.src.ror.grid = (grid) ->
  grid ?= @params.grid
  if typeof grid is 'string' and grid.startsWith 'grid.'
    res = await @src.ror 'external_ids.GRID.all:"' + grid + '"'
    if res?.id or res?.hits?.total is 1
      return if res.id then res else res.hits.hits[0]._source
    else
      res = await @src.ror.query grid
      if res?.items?[0]
        rr = await @src.ror._format res.items[0]
        @waitUntil @src.ror rr
        return rr
  return

P.src.ror.title = (title) ->
  title ?= @params.title ? @params.q
  if typeof title is 'string'
    if not @refresh
      res = await @src.ror 'title:"' + title + '"'
    if res?.id or res?.hits?.total is 1
      return if res.id then res else res.hits.hits[0]._source
    else
      res = await @src.ror.query title
      if res?.items?[0]
        rr = await @src.ror._format res.items[0]
        @waitUntil @src.ror rr
        return rr
  return

P.src.ror._format = (rec, created) ->
  try rec._id = rec.id.split('/').pop()
  rec.createdAt ?= created ? await @epoch()
  return rec




# https://ror.readme.io/docs/rest-api
# https://ror.readme.io/docs/data-dump

# data dump comes from:
# https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent
# and within the result object, filename is at hits.hits[0].files[0].links.self
# presumably always the first one?
# it's a zip, once unzipped is a JSON list, and the objects are NOT in jsonlines
# but they are pretty-printed, so risk identify start and end of objects by their whitespacing

P.src.ror.dumps = () ->
  return @fetch 'https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent'

P.src.ror.load = (refresh) ->
  refresh ?= @refresh
  total = 0
  batch = []
  
  try
    files = await @src.ror.dumps()
    if not refresh?
      latest = await @epoch files.hits.hits[0].created.split('+')[0]
      last = await @src.ror 'src:*', {sort: {'createdAt': 'desc'}, size: 1}
      last = last.hits.hits[0]._source if last?.hits?
  
  console.log latest, last?.createdAt, last?.src

  if refresh or not last? or not latest? or (last? and latest? and last.createdAt < latest)
    fn = files.hits.hits[0].files[0].links.self
    console.log fn
    created = await @epoch()
    startobj = false
    endobj = false
    lobj = ''

    dfn = fn.replace('/content', '').split('/').pop() # this will be a .zip
    rfn = @S.directory + '/import/ror/' + dfn
    resp = await fetch fn
    wstr = fs.createWriteStream rfn
    await new Promise (resolve, reject) =>
      resp.body.pipe wstr
      resp.body.on 'error', reject
      wstr.on 'finish', resolve
    await @_child 'unzip', [rfn, '-d', @S.directory + '/import/ror/']
    console.log 'ROR snapshot downloaded'

    await @src.ror ''

    #for await line from readline.createInterface input: fs.createReadStream infile
    #for await line from readline.createInterface input: (await fetch fn).body.pipe zlib.createGunzip() # headers: 'accept-encoding': 'gzip,deflate'
    for await line from readline.createInterface input: fs.createReadStream(rfn.replace '.zip', '.json') #.pipe zlib.createGunzip() #, crlfDelay: Infinity 
      try
        if not startobj and line.length is 5 and line.replace(/\s\s\s\s/,'') is '{'
          startobj = true
          lobj = '{'
        else if not endobj and line.replace(',', '').length is 5 and line.replace(/\s\s\s\s/,'').replace(',', '') is '}'
          endobj = true
          lobj += '}'
        else if line not in ['[', ']']
          lobj += line
        if startobj is true and endobj is true
          startobj = false
          endobj = false
          rec = await @src.ror._format JSON.parse(lobj), created
          rec.src = fn
          rec.createdAt ?= created
          lobj = ''
          total += 1
          batch.push rec
          if batch.length is 20000 # how many records to batch upload at a time
            console.log 'ROR bulk loading', batch.length, total
            await @src.ror batch
            batch = []

  await @src.ror(batch) if batch.length
  console.log total
  return total

P.src.ror.load._bg = true
P.src.ror.load._async = true
P.src.ror.load._auth = 'root'

