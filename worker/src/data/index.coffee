
# TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
# alias can be set on create, and may be best just to use an alias every time
# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html
# can also use aliases and alternate routes to handle auth to certain subsets of date
# aliased mappings can also have a filter applied, so only the filter results get returned

# TODO if index SHOULD be available but fails, write to kv if that's available? But don't end up in a loop.
# schedule would then have to pick them up and write them to index later once it becomes available again

S.index ?= {}
S.index.name ?= S.name ? 'Paradigm'
S.index.name = '' if typeof S.index.name isnt 'string'
S.index.name = S.index.name.toLowerCase().replace /\s/g, ''
S.index.url ?= S.bg + '/index' if typeof S.bg is 'string'

# route must be a string (or derived from URL params)
# any _ route is a control request (can only come from internal, not via API) e.g. _mapping, _scroll, etc
# a route without /_ and /... is an index (or all indices)
# in which case data can be a record to save (or update) or a query
# if a query, it plus opts must be identifiable as such by P.index.translate
# no data at all is also a query - queries will return the full ES _search result object
# this can be overridden by setting opts to 1, in which case only the _source of the first hit is returned
# to loop over all search results (or a specified max number of results), set opts to -1?
# and provide the foreach param

# if not a query, it's a record which may or may not have an _id (if has _id it could be a save or update)
# a route without /_ but with /... is a record. Anything after the slash must be the ID
# if there is no data the _source (with _id?) of the specific record will be returned
# if there is data it will replace the record (any _id in the data will be removed, it cannot overwrite the route)
# if data is a list it will be bulk loaded to the index

# delete is achieved by setting data to '' (works for either a route without /... to delete the index, or with /... to delete a record)
# delete can only be achieved with '' internally, or by a request method of DELETE or URL param of _delete and suitable auth
# delete by query can also work this way

P.index = (route, data, opts, foreach) ->
  if typeof route is 'object'
    data = route
    route = undefined

  if not route? and not data? and this?.parts? and @parts.length and @parts[0] is 'index'
    if @parts.length > 1 and (@parts[1].startsWith('.') or @parts[1].startsWith('_') or @parts[1] in ['svc','src']) #or P[@parts[1]]?) #  or @parts[1].startsWith('svc_') or @parts[1].startsWith('src_'))
      # don't allow direct calls to index if the rest of the params indicate an existing route
      # if not an existing route, a user with necessary auth could create/interact with a specified index
      # for indexes not on a specified route, their config such as auth etc will need to be passed at creation and stored somewhere
      return status: 403 # for now this isn't really stopping things, for example svc_crossref_works
    else
      if typeof @body is 'object'
        data = @copy @body
      else if typeof @body is 'string'
        data = @body if @body isnt '' # have to specify a DELETE method, or the _delete param on API, not just an empty body
      else
        data = @copy @params
      delete data.route
      delete data.index
      delete data[@fn.split('.').pop()] # get rid of any default ID value holder from the end of a wrapper URL param
      delete data._id # no provision of scripts or index or _id by params - has to be by URL route, or provided directly
      return undefined if data.script? or JSON.stringify(data).toLowerCase().indexOf('<script') isnt -1

  if typeof data is 'object' and not Array.isArray data
    route ?= data.route ? data.index
    delete data.route
    delete data.index
  
  if not route?
    if this?.parts? and @parts[0] is 'index' # need custom auth for who can create/remove indexes and records directly?
      if @parts.length is 1
        res = []
        for i of (await @index._send '_stats').indices
          res.push(i) if not i.startsWith('.') and not i.startsWith 'security-'
        return res
      else if @parts.length is 2 # called direct on an index
        route = @parts[1]
      else if @parts.length > 2 # called on index/key route
        # most IDs will only be at position 3 but for example using a DOI as an ID would spread it across 3 and 4
        route = @parts[1] + '/' + @parts.slice(2).join '_' # so combine them with an underscore - IDs can't have a slash in them
    else if this?.fn?
      route = @fn.replace /\./g, '_' # if the wrapping function wants data other than that defined by the URL route it was called on, it MUST specify the route manually
      # what if the @parts indicate this is a request for a specific record though, not just an index?
      route += '/' + @parts.join('_').replace(route + '_', '') if @parts.join('.') isnt @fn

  return undefined if typeof route isnt 'string'
  if route.includes '?'
    [route, rqp] = route.split '?'
    rqp = '?' + rqp
  else
    rqp = ''
  route = route.replace(/\/$/,'') if route.endsWith '/'
  if typeof data is 'object' and not Array.isArray(data) and data._id
    data = if this?.copy? then @copy(data) else P.copy data
    dni = data._id.replace /\//g, '_'
    route += '/' + dni if route.indexOf('/') is -1 and route.indexOf(dni) is -1
    delete data._id # ID can't go into the data for ES7.x

  # TODO if data is a record to save, should default fields such as createdAt ALWAYS be added here?
  # e.g rec.createdAt = Date.now()
  route = route.toLowerCase()
  rpl = route.split('/').length
  this.index ?= P.index # allow either P.index or a contextualised @index to be used
  if (this?.parts? and @parts[0] is 'index' and (@request.method is 'DELETE' or @params._delete)) or data is ''
    # DELETE can happen on index or index/key, needs no additional route parts for index but index/key has to happen on _doc
    # TODO for @params._delete allow a passthrough of data in case it is a delete by query, once _send is updated to handle that if still possible
    ret = await @index._send route.replace('/', '/_doc/') + rqp, ''
    return undefined #ret.acknowledged is true or ret.result is 'deleted'
  else if rpl is 1
    # CREATE can happen on index if index params are provided or empty object is provided
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
    # simplest create would be {} or settings={number_of_shards:1} where 1 is default anyway
    if (typeof data is 'string' and (data is '' or data.indexOf('\n') isnt -1)) or Array.isArray data
      if data is ''
        return @index._send route + rqp, data
      else
        return @index._bulk route + rqp, data # bulk create (TODO what about if wanting other bulk actions?)
    else if typeof data in ['object', 'string']
      if qr = await @index.translate data, opts
        return @index._send route + '/_search' + rqp, qr
      else if typeof data is 'object'
        chk = if this?.copy? then @copy(data) else P.copy data
        delete chk[c] for c in ['settings', 'aliases', 'mappings']
        if JSON.stringify(chk) is '{}'
          if not await @index._send route + rqp
            ind = if not await @index.translate(data) then {settings: data.settings, aliases: data.aliases, mappings: data.mappings} else {}
            await @index._send route + rqp, ind # create the index
          return @index._send route + '/_search' + rqp # just do a search
        else
          ret = await @index._send route + '/_doc' + rqp, data # create a single record without ID (if it came with ID it would have been caught above and converted to route with multiple parts)
          return if ret?.result is 'created' and ret._id then ret._id else ret
    else
      return @index._send route + '/_search' + rqp
  else if rpl is 2 and (not data? or typeof data is 'object' and not Array.isArray data)
    # CREATE or overwrite on index/key if data is provided - otherwise just GET the _doc
    # Should @params be able to default to write data on index/key?
    # TODO check how ES7.x accepts update with script in them
    route = route.replace('/', '/_doc/') if not route.startsWith('_') and not route.includes '/_'
    if data? and JSON.stringify(data) isnt '{}'
      if typeof data is 'object' and data.script?
        route += '_update'
        rqp += (if rqp.length then '&' else '?') + 'retry_on_conflict=2'
      ret = await @index._send route + rqp, data
      return if ret?.result is 'created' and ret._id then ret._id else ret
    else # or just get the record
      ret = await @index._send route + rqp
      if typeof ret is 'object' and (ret._source or ret.fields)
        rex = ret._source ? ret.fields
        rex._id ?= ret._id # if _id can no longer be stored in the _source in ES7.x
        ret = rex
      return ret

  return undefined

P.index._auths = 'system'
P.index._hides = true
P.index._wraps = false
P.index._caches = false

P.index.status = () ->
  res = status: 'green'
  res.indices = {}
  s = await @index._send '_stats'
  shards = await @index._send '_cat/shards?format=json'
  for i of s.indices
    if not i.startsWith('.') and not i.startsWith 'security-'
      # is primaries or total better for numbers here?
      res.indices[i] = docs: s.indices[i].primaries.docs.count, size: Math.ceil(s.indices[i].primaries.store.size_in_bytes / 1024 / 1024) + 'mb'
      for sh in shards
        if sh.index is i and sh.prirep is 'p'
          res.indices[i].shards ?= 0
          res.indices[i].shards += 1
  try
    res.status = 'red' if res.cluster.status not in ['green','yellow'] # accept yellow for single node cluster (or configure ES itself to accept that as green)
    for k in ['cluster_name', 'number_of_nodes', 'number_of_data_nodes', 'unassigned_shards']
      delete res.cluster[k] # or delete all of cluster info?
  return res



P.index.keys = (route) ->
  route ?= @params.index ? @params.keys ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/keys', ''
  keys = []
  _keys = (mapping, depth='') =>
    mapping ?= if typeof route is 'object' then route else await @index.mapping route
    mapping.properties = mapping[route]?.mappings?.properties ? mapping[@S.index.name + '_' + route]?.mappings?.properties ? mapping.properties
    if mapping.properties?
      depth += '.' if depth.length
      for k of mapping.properties
        keys.push(depth+k) if depth+k not in keys
        if mapping.properties[k].properties?
          await _keys mapping.properties[k], depth+k
  await _keys()
  return keys

P.index.terms = (route, key, qry, size=1000, counts=true, order="count") ->
  key ?= @params.terms ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/terms', ''
  if not key? and route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  return [] if not key
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'terms', 'key']
  qry ?= await @index.translate cq
  query = if typeof qry is 'object' then qry else size: 0, query: bool: must: [], filter: [exists: field: key]
  query.query.bool.must.push(query_string: query: qry) if typeof qry is 'string'
  query.aggregations ?= {}
  size = @params.size if @params.size?
  counts = @params.counts if @params.counts?
  order = @params.order if @params.order?
  # order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
  ords = count: {_count: 'desc'}, reverse_count: {_count: 'asc'}, term: {_key: 'asc'}, reverse_term: {_key: 'desc'} # convert for ES7.x
  order = ords[order] if typeof order is 'string' and ords[order]?
  query.aggregations[key] = terms: field: key + (if key.endsWith('.keyword') then '' else '.keyword'), size: size, order: order
  ret = await @index._send '/' + route + '/_search', query, 'POST'
  res = []
  for p in ret?.aggregations?[key]?.buckets ? []
    res.push if counts then {term: p.key, count: p.doc_count} else p.key
  return res

P.index.suggest = (route, key, qry, size, counts=false, order="term") ->
  key ?= @params.suggest ? @params.key
  [key, qry] = key.split('/') if key.indexOf('/') isnt -1
  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').split('/suggest')[0]
  res = []
  for k in await @index.terms route, key, qry, size, counts, order
    res.push(k) if typeof qry isnt 'string' or k.toLowerCase().indexOf(qry.toLowerCase()) is 0 # match at start
  if res.length is 0 and typeof qry is 'string' and not qry.endsWith '*'
    for k in await @index.terms route, key, qry + '*', size, counts, order
      res.push(k) if k.toLowerCase().indexOf(qry.toLowerCase()) isnt -1
  if res.length is 0 and typeof qry is 'string' and not qry.startsWith '*'
    for k in await @index.terms route, key, '*' + qry + '*', size, counts, order
      res.push(k) if k.toLowerCase().indexOf(qry.toLowerCase()) isnt -1
  return res

P.index.count = (route, key, qry) ->
  key ?= @params.count ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '_'
  route = route.replace('index/', '').split('/count')[0]
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'count', 'key']
  qry = qr if not qry? and qr = await @index.translate cq
  qry ?= query: bool: must: [], filter: []
  if key
    key += '.keyword' if not key.endsWith '.keyword'
    qry.size = 0
    qry.aggs = keyed: cardinality: field: key, precision_threshold: 40000 # this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
    ret = await @index._send '/' + route + '/_search', qry, 'POST'
    return ret?.aggregations?.keyed?.value
  else
    ret = await @index._send '/' + route + '/_search', qry, 'POST'
    return ret?.hits?.total

P.index.min = (route, key, qry, end='min') ->
  key ?= @params[end] ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/' + end, ''
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'min', 'max', 'key']
  qry ?= await @index.translate cq
  query = if typeof key is 'object' then key else if qry? then qry else query: bool: must: [], filter: [exists: field: key]
  query.size = 0
  query.aggs = {}
  query.aggs.min = {min: {field: key}} if end in ['min', 'range']
  query.aggs.max = {max: {field: key}} if end in ['max', 'range']
  ret = await @index._send '/' + route + '/_search', query, 'POST'
  return if end is 'range' then {min: ret.aggregations.min.value, max: ret.aggregations.max.value} else ret.aggregations[end].value

P.index.max = (route, key, qry) -> return @index.min route, key, qry, 'max'
P.index.range = (route, key, qry) -> return @index.min route, key, qry, 'range'

P.index.mapping = (route) ->
  route = route.replace /^\//, '' # remove any leading /
  route = route + '/' if route.indexOf('/') is -1
  route = route.replace('/','/_mapping') if route.indexOf('_mapping') is -1
  return @index._send route

P.index.history = (route, key) ->
  # TODO get the history of a record by a query of the log
  try key ?= @params.history ? @params.index
  return []


# use this like: for rec from @index._for route, q, opts
# see index._each below for example of how to call this for/yield generator
P.index._for = (route, q, opts) ->
  if opts?.scroll
    scroll = opts.scroll
    scroll += 'm' if typeof scroll is 'number' or not scroll.endsWith 'm'
    delete opts.scroll
  else
    scroll = '10m'
  qy = await @index.translate q, opts
  qy.from ?= 0
  qy.size ?= 500
  # use scan/scroll for each, because _pit is only available in "default" ES, which ES means is NOT the open one, so our OSS distro does not include it!
  # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/paginate-search-results.html#search-after
  res = await @index route + '?scroll=' + scroll, qy
  delete res._scroll_id if res?.hits?.total? and res.hits.total is res.hits.hits.length
  loop
    if (not res?.hits?.hits or not res?.hits?.hits.length) and res?._scroll_id
      res = await @index '/_search/scroll?scroll=' + scroll + '&scroll_id=' + res._scroll_id
    if res?.hits?.hits? and res.hits.hits.length
      r = res.hits.hits.shift()
      ret = r._source ? r.fields
      ret._id ?= r._id
      yield ret
  return

P.index._each = (route, q, opts, fn) ->
  # Performs a function on each record. If the function should make changes to a record, optionally 
  # avoid many writes by having the function return the record object or the string ID, and specify 
  # an "action" in opts. returned objects can then be bulk "insert" or "update", or string IDs for "remove"
  if not fn? and not opts? and typeof q is 'function'
    fn = q
    q = '*'
  if not fn? and typeof opts is 'function'
    fn = opts
    opts = undefined
  opts ?= {}
  if typeof opts is 'string'
    action = opts
    opts = undefined
  if opts?.action
    action = opts.action
    delete opts.action
  sz = opts.size ? (if typeof q is 'object' and q.size? then q.size else 1000)
  if sz > 50
    qy = await @index.translate q, opts
    qy.size = 1
    chk = await @index route, qy
    if chk?.hits?.total? and chk.hits.total isnt 0
      # make sure that query result size does not take up more than about 1gb. In a scroll-scan size is per shard, not per result set
      max_size = Math.floor(1000000000 / (Buffer.byteLength(JSON.stringify(chk.hits.hits[0])) * chk._shards.total))
      sz = max_size if max_size < sz
    qy.size = sz

  processed = 0
  updates = []
  for rec from @index._for route, (qy ? q), opts # TODO check if this needs await
    fr = await fn.apply this, rec
    processed += 1
    updates.push(fr) if fr? and (typeof fr is 'object' or typeof fr is 'string')
    if action and updates.length > sz
      await @index._bulk route, updates, action
      updates = []
  @index._bulk(route, updates, action) if action and updates.length # catch any left over
  console.log('_each processed ' + processed) if @S.dev and @S.bg is true

P.index._bulk = (route, data, action='index', bulk=50000) ->
  action = 'index' if action is true
  prefix = await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
  route = @S.index.name + '_' + route if prefix isnt false # need to do this here as well as in _send so it can be set below in each object of the bulk
  this.index ?= P.index
  if typeof data is 'string' and data.indexOf('\n') isnt -1
    # TODO should this check through the string and make sure it only indexes to the specified route?
    await @index._send '/_bulk', {body:data, headers: {'Content-Type': 'application/x-ndjson'}} # new ES 7.x requires this rather than text/plain
    return true
  else
    rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
    rows = [rows] if not Array.isArray rows
    counter = 0
    pkg = ''
    for r of rows
      row = rows[r]
      counter += 1
      if typeof row is 'object'
        rid = row._id ? row._source?._id
        row = row._source if row._source
        delete row._id # newer ES 7.x won't accept the _id in the object itself
      meta = {}
      meta[action] = {"_index": route }
      meta[action]._id = if action is 'delete' and typeof row in ['string', 'number'] then row else rid # what if action is delete but can't set an ID?
      pkg += JSON.stringify(meta) + '\n'
      if action is 'create' or action is 'index'
        pkg += JSON.stringify(row) + '\n'
      else if action is 'update'
        pkg += JSON.stringify({doc: row}) + '\n' # is it worth expecting other kinds of update in bulk import?
      # don't need a second row for deletes
      if counter is bulk or parseInt(r) is (rows.length - 1) or pkg.length > 70000000
        rs = await @index._send '/_bulk', {body:pkg, headers: {'Content-Type': 'application/x-ndjson'}}
        if this?.S?.dev and rs?.errors
          console.log rs.items
        pkg = ''
        counter = 0
    return rows.length

#P.index._refresh = (route) -> return @index._send route.replace(/^\//, '').split('/')[0] + '/_refresh'


'''
# fetches everything of route from kv into the index
P.index.kv = (route) -> 
  route ?= @params.index ? @params.kv
  total = 0
  if typeof route is 'string' and route.length
    route = route.replace(/\./g, '/').replace(/_/g, '/')
    if not exists = await @index route
      idx = await @dot P, route.replace(/\//g, '.')
      if typeof idx is 'object' and typeof idx._index is 'object' and (idx._index.settings? or idx._index.aliases? or idx._index.mappings?)
        await @index route, idx._index
    klogs = []
    await @kv._each route, (lk) ->
      if lk.indexOf('/') isnt -1
        l = await @kv lk
        l._id ?= lk.split('/').pop()
        klogs.push l
      if klogs.length >= 1000
        await @index route, klogs
        total += klogs.length
        klogs = []
    if klogs.length # save any remaining ones
      total += klogs.length
      @waitUntil @index route, klogs
      klogs = []
  return total
P.index.kv._bg = true
'''


# query formats that can be accepted:
#  'A simple string to match on'
#  'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
#  '?q=query params directly as string'
#  {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
#  {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "should" as well)
#  ["list","of strings to OR match on"] - this is an OR query strings match UNLESS strings contain : then mapped to terms matches
#  [{"list":"of objects to OR match"}] - so a set of OR terms matches. If objects are not key: string they are assumed to be full ES queries that can drop into the bool
#
#  Keys can use dot notation
#  If opts is true, the query will be adjusted to sort by createdAt descending, so returning the newest first (it sets newest:true, see below)
#  If opts is string 'random' it will convert the query to be a random order
#  If opts is a number it will be assumed to be the size parameter
#  Otherwise opts should be an object (and the above can be provided as keys, "newest", "random")
#  If newest is true the query will have a sort desc on createdAt. If false, sort will be asc
#  If "random" key is provided, "seed" can be provided too if desired, for seeded random queries
#  If "restrict" is provided, should point to list of ES queries to add to the and part of the query filter
#  Any other keys in the options object should be directly attributable to an ES query object
#
#  For ES 7.x there is no filtered query any more, filter is a value of bool.must
#  Filter acts like a must but without scoring. Whereas normal must does score.
#  must_not does not affect score. Not sure about should
#  Default empty query: {query: {bool: {must: [], filter: []}}, size: 10}
P.index.translate = (q, opts={}) ->
  q ?= this?.params # return undefined if q isnt a string or object that can become a valid query
  if typeof q is 'string'
    return undefined if q is '' or q.indexOf('\n') isnt -1 # this would likely be a bulk load string
    maybe_route_or_id = q.length > 8 and q.split('/').pop().length < 34 and q.length is q.replace(/\s\:\*~()\?=%/g, '').length
    return undefined if maybe_route_or_id and q.split('/').length is 2 # a route / ID to discern from a route
  else
    return undefined if typeof q isnt 'object'
    if Array.isArray q
      return undefined if not q.length
    else
      for k in ['settings', 'aliases', 'mappings', 'index']
        return undefined if q[k]?
      return undefined if JSON.stringify(q) isnt '{}' and not q.q? and not q.query? and not q.source? #and not q.must? and not q.should? and not q.aggs? and not q.aggregations?

  try q = @copy(q) if typeof q is 'object' # copy objects so don't interfere with what was passed in
  try opts = @copy(opts) if typeof opts is 'object'
  opts = {random:true} if opts is 'random'
  opts = {size:opts} if typeof opts is 'number'
  opts = {newest: true} if opts is true
  opts = {newest: false} if opts is false
  qry = opts?.query ? {}
  qry.query ?= {}
  _structure = (sq) =>
    sq.query ?= bool: must: [], filter: []
    if sq.query?.filtered?.query? # simple convenience catch for old-style queries - NOT complete
      fq = @copy sq
      sq.query = fq.query.filtered.query # should be a bool must for this convenience
      sq.query.bool.filter = fq.query.filtered.filter
    if not sq.query.bool?
      ms = []
      ms.push(sq.query) if JSON.stringify(sq.query) isnt '{}'
      sq.query = bool: must: ms, filter: []
    sq.query.bool.must ?= []
    sq.query.bool.filter ?= []
    return sq
  qry = _structure qry
  if typeof q is 'object'
    delete q[dk] for dk in ['apikey', '_', 'callback', 'refresh', 'key', 'counts', 'index', 'search']
    for ok in ['random','seed'] # is this necessary or is the general push of things other than q to opts good enough?
      opts[ok] = q[ok]
      delete q[ok]
    # some URL params that may be commonly used in this API along with valid ES URL query params will be removed here by default too
    # this makes it easy to handle them in routes whilst also just passing the whole queryParams object into this translation method and still get back a valid ES query
    if JSON.stringify(q).indexOf('[') is 0
      qry.query.bool.should ?= []
      for m in q
        if typeof m is 'object' and m?
          for k of m
            if typeof m[k] is 'string'
              tobj = term:{}
              tobj.term[k] = m[k] #TODO check how a term query on a text string works on newer ES. Does it require the term query to be in .keyword?
              qry.query.bool.should.push tobj
            else if typeof m[k] in ['number','boolean']
              qry.query.bool.should.push {query_string:{query:k + ':' + m[k]}}
            else if m[k]?
              qry.query.bool.should.push m[k]
        else if typeof m is 'string'
          qry.query.bool.should.push query_string: query: m
    else if q.query?
      qry = q # assume already a query
    else if q.source?
      qry = JSON.parse(q.source) if typeof q.source is 'string'
      qry = q.source if typeof q.source is 'object'
      opts ?= {}
      for o of q
        opts[o] ?= q[o] if o not in ['source']
    else if q.q?
      if q.prefix? and q.q.indexOf(':') isnt -1
        delete q.prefix
        pfx = {}
        qpts = q.q.split ':'
        pfx[qpts[0]] = qpts[1]
        qry.query.bool.must.push prefix: pfx
      else
        qry.query.bool.must.push query_string: query: decodeURIComponent q.q
      opts ?= {}
      for o of q
        opts[o] ?= q[o] if o not in ['q']
    else
      for bt in ['must', 'must_not', 'filter', 'should']
        qry.query.bool[bt] = q[bt] if q[bt]?
      for y of q # an object where every key is assumed to be an AND term search if string, or a named search object to go in to ES
        if (y is 'fields') or (y is 'sort' and typeof q[y] is 'string' and q[y].indexOf(':') isnt -1) or (y in ['from','size'] and (typeof q[y]is 'number' or not isNaN parseInt q[y]))
          opts ?= {}
          opts[y] = q[y]
        else if y not in ['must', 'must_not', 'filter', 'should']
          if typeof q[y] is 'string'
            tobj = term:{}
            tobj.term[y] = q[y]
            qry.query.bool.filter.push tobj
          else if typeof q[y] in ['number','boolean']
            qry.query.bool.filter.push {query_string:{query:y + ':' + q[y]}}
          else if typeof q[y] is 'object'
            qobj = {}
            qobj[y] = q[y]
            qry.query.bool.filter.push qobj
          else if q[y]?
            qry.query.bool.filter.push q[y]
  else if typeof q is 'string'
    if q.indexOf('?') is 0
      qry = q # assume URL query params and just use them as such?
    else if q?
      q = '*' if q is ''
      qry.query.bool.must.push query_string: query: q
  qry = _structure qry # do this again to make sure valid structure is present after above changes, and before going through opts which require expected structure
  if opts?
    if opts.newest is true
      delete opts.newest
      opts.sort = {createdAt:{order:'desc'}}
    else if opts.newest is false
      delete opts.newest
      opts.sort = {createdAt:{order:'asc'}}
    delete opts._ # delete anything that may have come from query params but are not handled by ES
    delete opts.apikey
    if opts.fields and typeof opts.fields is 'string' and opts.fields.indexOf(',') isnt -1
      opts.fields = opts.fields.split(',')
    if opts.random
      fq = {function_score: {random_score: {}}}
      fq.function_score.random_score.seed = seed if opts.seed?
      fq.function_score.query = qry.query
      qry.query = fq # TODO check how function_score and random seed work now in ES7.x
      delete opts.random
      delete opts.seed
    if opts._include? or opts.include? or opts._includes? or opts.includes? or opts._exclude? or opts.exclude? or opts._excludes? or opts.excludes?
      qry._source ?= {}
      inc = if opts._include? then '_include' else if opts.include? then 'include' else if opts._includes? then '_includes' else 'includes'
      includes = opts[inc]
      if includes?
        includes = includes.split(',') if typeof includes is 'string'
        qry._source.includes = includes
        delete opts[inc]
      exc = if opts._exclude? then '_exclude' else if opts.exclude? then 'exclude' else if opts._excludes? then '_excludes' else 'excludes'
      excludes = opts[exc]
      if excludes?
        excludes = excludes.split(',') if typeof excludes is 'string'
        for i in includes ? []
          delete excludes[i] if i in excludes
        qry._source.excludes = excludes
        delete opts[exc]
    if opts.and?
      qry.query.bool.filter.push a for a in opts.and
      delete opts.and
    if opts.sort?
      if typeof opts.sort is 'string' and opts.sort.indexOf(',') isnt -1
        if opts.sort.indexOf(':') isnt -1
          os = []
          for ps in opts.sort.split ','
            nos = {}
            nos[ps.split(':')[0]] = {order:ps.split(':')[1]}
            os.push nos
          opts.sort = os
        else
          opts.sort = opts.sort.split ','
      if typeof opts.sort is 'string' and opts.sort.indexOf(':') isnt -1
        os = {}
        os[opts.sort.split(':')[0]] = {order:opts.sort.split(':')[1]}
        opts.sort = os
    if opts.restrict? or opts.filter?
      qry.query.bool.filter.push(rs) for rs in (opts.restrict ? opts.filter)
      delete opts.restrict
    if opts.not? or opts.must_not?
      tgt = if opts.not? then 'not' else 'must_not'
      if Array.isArray opts[tgt]
        qry.query.bool.must_not = opts[tgt]
      else
        qry.query.bool.must_not ?= []
        qry.query.bool.must_not.push(nr) for nr in opts[tgt]
      delete opts[tgt]
    if opts.should?
      if Array.isArray opts.should
        qry.query.bool.should = opts.should
      else
        qry.query.bool.should ?= []
        qry.query.bool.should.push(sr) for sr in opts.should
      delete opts.should
    if opts.terms?
      try opts.terms = opts.terms.split(',')
      qry.aggregations ?= {}
      for tm in opts.terms
        qry.aggregations[tm] = { terms: { field: tm + (if tm.endsWith('.keyword') then '' else '.keyword'), size: 1000 } }
      delete opts.terms
    for af in ['aggs','aggregations']
      if opts[af]?
        qry[af] ?= {}
        qry[af][f] = opts[af][f] for f of opts[af]
        delete opts[af]
    qry[k] = v for k, v of opts
  # no filter query or no main query can cause issues on some queries especially if certain aggs/terms are present, so insert some default searches if necessary
  #qry.query = { match_all: {} } if typeof qry is 'object' and qry.query? and JSON.stringify(qry.query) is '{}'
  # clean slashes out of query strings
  if qry.query?.bool?
    for bm of qry.query.bool
      for b of qry.query.bool[bm]
        if typeof qry.query.bool[bm][b].query_string?.query is 'string' and qry.query.bool[bm][b].query_string.query.indexOf('/') isnt -1 and qry.query.bool[bm][b].query_string.query.indexOf('"') is -1
          qry.query.bool[bm][b].query_string.query = '"' + qry.query.bool[bm][b].query_string.query + '"'
  delete qry._source if qry._source? and qry.fields?
  return qry



# calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
# call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
P.index._send = (route, data, method) ->
  if route.includes '?'
    [route, rqp] = route.split '?'
    rqp = '?' + rqp
  else
    rqp = ''
  route = route.toLowerCase() # force lowercase on all IDs so that can deal with users giving incorrectly cased IDs for things like DOIs which are defined as case insensitive
  route = route.replace('/','') if route.startsWith '/' # gets added back in when combined with the url
  route = route.replace(/\/$/,'') if route.endsWith '/'
  method ?= if data is '' then 'DELETE' else if data? and (route.indexOf('/') is -1 or route.indexOf('/_create') isnt -1 or (route.indexOf('/_doc') isnt -1 and not route.endsWith('/_doc'))) then 'PUT' else if data? or route.split('/').pop().split('?')[0] in ['_refresh', '_aliases'] then 'POST' else 'GET'
  # TODO if data is a query that also has a _delete key in it, remove that key and do a delete by query? and should that be bulked? is dbq still allowed in ES7.x?
  return false if method is 'DELETE' and route.indexOf('/_all') isnt -1 # nobody can delete all via the API
  if not route.startsWith 'http' # which it probably doesn't
    if @S.index.name and not route.startsWith(@S.index.name) and not route.startsWith '_'
      prefix = await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
      # TODO could allow prefix to be a list of names, and if index name is in the list, alias the index into those namespaces, to share indexes between specific instances rather than just one or global
      if prefix isnt false
        route = (if typeof prefix is 'string' then prefix else @S.index.name) + '_' + route
    url = if this?.S?.index?.url then @S.index.url else S.index?.url
    url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
    if typeof url isnt 'string'
      return undefined
    route = url + '/' + route
  
  if not route.startsWith 'http'
    console.log 'NO INDEX URL AVAILABLE'
    return undefined

  route = route += rqp
  opts = if route.indexOf('/_bulk') isnt -1 or typeof data?.headers is 'object' then data else body: data # fetch requires data to be body
  if route.indexOf('/_search') isnt -1
    # avoid hits.total coming back as object in new ES, because it also becomes vague
    # see hits.total https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-7.0.html
    route += (if route.indexOf('?') is -1 then '?' else '&') + 'rest_total_hits_as_int=true'

  if @S.dev
    console.log 'INDEX ' + route
    console.log method + ' ' + if not data? then '' else JSON.stringify(if Array.isArray(data) and data.length then data[0] else data).substr(0, 5000)

  #opts.retry = 3
  opts.method = method
  res = await @fetch route, opts
  if @S.dev
    try console.log 'INDEX QUERY FOUND', res.hits.total, res.hits.hits.length
  if not res? or (typeof res is 'object' and typeof res.status is 'number' and res.status >= 400 and res.status <= 600)
    # fetch returns undefined for 404, otherwise any other error from 400 is returned like status: 400
    # write a log / send an alert?
    #em = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', method: method, url: url, route: route, opts: opts, error: err.toString()
    #if this?.log? then @log(em) else P.log em
    # do anything for 409 (version mismatch?)
    return undefined
  else
    try res.q = data if @S.dev and data?.query?
    return res
