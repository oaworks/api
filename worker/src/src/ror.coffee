
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