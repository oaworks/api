
# https://ror.readme.io/docs/rest-api

P.src.ror = (rid) ->
  rid ?= @params.ror
  if typeof rid is 'string' and not rid.includes ' '
    rid = rid.split('/').pop() # just in case it was the full ROR URL (which is their official ID)
    if rid.length < 11 # are all RORs 9 long...?
      return @src.ror._format await @fetch 'https://api.ror.org/organizations/' + rid
  return
    
P.src.ror._index = true
P.src.ror._prefix = false

P.src.ror.query = (q) ->
  q ?= @params.query ? @params.q
  if typeof q is 'string'
    return @fetch 'https://api.ror.org/organizations?query="' + q + '"'
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

P.src.ror._format = (rec) ->
  try rec._id = rec.id.split('/').pop()
  return rec




# https://ror.readme.io/docs/rest-api
# https://ror.readme.io/docs/data-dump

# data dump comes from:
# https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent
# and within the result object, filename is at hits.hits[0].files[0].links.self
# presumably always the first one?
# it's a zip, once unzipped is a JSON list, and the objects are NOT in jsonlines
# but they are pretty-printed, so risk identify start and end of objects by their whitespacing

P.src.ror.load = () ->
  batchsize = 20000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  infile = @S.directory + '/ror/2021-03-25-ror-data.json' # where the lines should be read from

  await @src.ror('') if @refresh

  total = 0
  batch = []

  startobj = false
  endobj = false
  lobj = ''
  for await line from readline.createInterface input: fs.createReadStream infile
    break if total is howmany
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
        rec = await @src.ror._format JSON.parse lobj
        lobj = ''
        total += 1
        batch.push rec
        if batch.length is batchsize
          console.log 'ROR bulk loading', batch.length, total
          await @src.ror batch
          batch = []

  await @src.ror(batch) if batch.length
  console.log total
  return total

P.src.ror.load._bg = true
P.src.ror.load._async = true
P.src.ror.load._auth = 'root'

