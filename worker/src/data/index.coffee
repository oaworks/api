
# TODO be able to receive bulk json lists or formatted bulk strings. Need to stick the useful default values into each
# those would be createdAt, created_date (in default templates format for ES 7.1) and user ID of the action?

# TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
# alias can be set on create, and may be best just to use an alias every time
# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html
# can also use aliases and alternate routes to handle auth to certain subsets of date
# aliased mappings can also have a filter applied, so only the filter results get returned

# TODO if index SHOULD be available but fails, write to kv if that's available? But don't end up in a loop...
# anything found by _schedule in kv that isn't set to _kv will get written to index once it becomes available

S.index ?= {}
S.index.name ?= S.name ? 'Paradigm'
S.index.name = '' if typeof S.index.name isnt 'string'
S.index.name = S.index.name.toLowerCase().replace /\s/g, ''
S.index.url ?= S.bg + '/index' if typeof S.bg is 'string'

P.index = (route, data, qopts) ->
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
        data = @body
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
        return await @index._indices()
      else if @parts.length is 2 # called direct on an index
        route = @parts[1]
      else if @parts.length > 2 # called on index/key route
        '''lp = @parts[@parts.length-1]
        lpp = @parts[@parts.length-2]
        if (typeof P.index[lp] is 'function' and not lp.startsWith '_') or lpp is 'suggest'
          return @index[if lpp is 'suggest' then 'suggest' else lp] @route
        else'''
        # most IDs will only be at position 3 but for example using a DOI as an ID would spread it across 3 and 4
        route = @parts[1] + '/' + @parts.slice(2).join '_' # so combine them with an underscore - IDs can't have a slash in them
    else if this?.fn?
      # auth should not matter here because providing route or data means the function is being handled elsehwere, which should deal with auth
      route = @fn.replace /\./g, '_' # if the wrapping function wants data other than that defined by the URL route it was called on, it MUST specify the route manually
      # what if the @parts indicate this is a request for a specific record though, not just an index?
      route += '/' + @parts.join('_').replace(route + '_', '') if @parts.join('.') isnt @fn

  return undefined if typeof route isnt 'string'
  route = route.replace(/\/$/,'') if route.endsWith '/'
  if typeof data is 'object' and not Array.isArray(data) and data._id
    dni = data._id.replace /\//g, '_'
    route += '/' + data._id if route.indexOf('/') is -1 and route.indexOf(dni) is -1
    delete data._id # ID can't go into the data for ES7.x

  route = route.toLowerCase()
  rpl = route.split('/').length
  cidx = if this?.index? then @index else P.index # allow either P.index or a contextualised @index to be used
  if (this?.parts? and @parts[0] is 'index' and (@request.method is 'DELETE' or @params._delete)) or data is ''
    # DELETE can happen on index or index/key, needs no additional route parts for index but index/key has to happen on _doc
    # TODO for @params._delete allow a passthrough of data in case it is a delete by query, once _submit is updated to handle that if still possible
    ret = await cidx._submit route.replace('/', '/_doc/'), ''
    return undefined #ret.acknowledged is true or ret.result is 'deleted'
  else if rpl is 1
    # CREATE can happen on index if index params are provided or empty object is provided
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
    # simplest create would be {} or settings={number_of_shards:1} where 1 is default anyway
    if (typeof data is 'string' and (data is '' or data.indexOf('\n') isnt -1)) or Array.isArray data
      if data is ''
        return cidx._submit route, data
      else
        return cidx._bulk route, data # bulk create (TODO what about if wanting other bulk actions?)
    else if typeof data is 'object'
      if cidx._q data
        return cidx._submit route + '/_search', await cidx.translate data, qopts
      else
        chk = if this?.copy? then @copy(data) else P.copy data
        delete chk[c] for c in ['settings', 'aliases', 'mappings']
        if JSON.stringify(chk) is '{}'
          if not await cidx._submit route
            ind = if not cidx._q(data) then {settings: data.settings, aliases: data.aliases, mappings: data.mappings} else {}
            await cidx._submit route, ind # create the index
          return cidx._submit route + '/_search' # just do a search
        else
          return cidx._submit route + '/_doc', data # create a single record without ID (if it came with ID it would have been caught above and converted to route with multiple parts)
    else
      return cidx._submit route + '/_search'
  else if rpl is 2 and (not data? or typeof data is 'object' and not Array.isArray data)
    # CREATE or overwrite on index/key if data is provided - otherwise just GET the _doc
    # Should @params be able to default to write data on index/key?
    # TODO check how ES7.x accepts update with script in them
    if data? and JSON.stringify(data) isnt '{}'
      route = if data is '' then route else if data.script? then route + '/_update?retry_on_conflict=2' else route.replace '/', '/_doc/' # does PUT create work if it already exists? or PUT _doc? or POST _create?
      return cidx._submit route, data
    else # or just get the record
      ret = await cidx._submit route.replace '/', '/_doc/'
      if typeof ret is 'object' and (ret._source or ret.fields)
        rex = ret._source ? ret.fields
        rex._id ?= ret._id # if _id can no longer be stored in the _source in ES7.x
        ret = rex
      return ret

  return undefined


# calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
# call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
P.index._submit = (route, data, method, deletes=true) -> # deletes is true in dev, but remove or add auth control for live
  route = route.toLowerCase() # force lowercase on all IDs so that can deal with users giving incorrectly cased IDs for things like DOIs which are defined as case insensitive
  route = route.replace('/','') if route.indexOf('/') is 0 # gets added back in when combined with the url
  route = route.replace(/\/$/,'') if route.endsWith '/'
  method ?= if route is '_pit' or data is '' then 'DELETE' else if data? and (route.indexOf('/') is -1 or route.indexOf('/_create') isnt -1 or (route.indexOf('/_doc') isnt -1 and not route.endsWith('/_doc'))) then 'PUT' else if data? or route.split('/').pop().split('?')[0] in ['_refresh', '_pit', '_aliases'] then 'POST' else 'GET'
  # TODO if data is a query that also has a _delete key in it, remove that key and do a delete by query? and should that be bulked? is dbq still allowed in ES7.x?
  return false if method is 'DELETE' and (deletes isnt true or route.indexOf('/_all') isnt -1) # nobody can delete all via the API
  if not route.startsWith 'http' # which it probably doesn't
    if @S.index.name and not route.startsWith(@S.index.name) and not route.startsWith('_')
      prefix = await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
      # TODO could allow prefix to be a list of names, and if index name is in the list, alias the index into those namespaces, to share indexes between specific instances rather than just one or global
      route = @S.index.name + '_' + route if prefix isnt false
    url = if this?.S?.index?.url then @S.index.url else S.index?.url
    url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
    if typeof url isnt 'string'
      return undefined
    route = url + '/' + route
  
  if not route.startsWith 'http'
    console.log 'NO INDEX URL AVAILABLE'
    return undefined

  opts = if route.indexOf('/_bulk') isnt -1 or typeof data?.headers is 'object' then data else body: data # fetch requires data to be body
  if route.indexOf('/_search') isnt -1
    # avoid hits.total coming back as object in new ES, because it also becomes vague
    # see hits.total https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-7.0.html
    route += (if route.indexOf('?') is -1 then '?' else '&') + 'rest_total_hits_as_int=true'

  if @S.dev
    console.log 'INDEX ' + route
    console.log method + ' ' + if not data? then '' else JSON.stringify(if Array.isArray(data) and data.length then data[0] else data).substr(0, 1000)

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


P.index._mapping = (route) ->
  return false if typeof route isnt 'string'
  route = route.replace /^\//, '' # remove any leading /
  route = route + '/' if route.indexOf('/') is -1
  route = route.replace('/','/_mapping') if route.indexOf('_mapping') is -1
  return await @index._submit route

P.index.keys = (route) ->
  try
    route ?= @fn.replace /\./g, '/'
    route = route.replace('index/', '').replace '/keys', ''
  keys = []
  _keys = (mapping, depth='') =>
    mapping ?= if typeof route is 'object' then route else await @index._mapping route
    mapping.properties = mapping[route]?.mappings?.properties ? mapping.properties
    if mapping.properties?
      depth += '.' if depth.length
      for k of mapping.properties
        keys.push(depth+k) if depth+k not in keys
        if mapping.properties[k].properties?
          await _keys mapping.properties[k], depth+k
  await _keys()
  return keys

P.index.terms = (route, key, qry, size=1000, counts=true, order="count") ->
  try
    route ?= @fn.replace /\./g, '/'
    route = route.replace('index/', '').replace '/terms', ''
    if not key? and route.indexOf('/') isnt -1
      [route, key] = route.split '/'
    cp @copy @params
    delete cp.index
    if cp.size?
      size = cp.size
      delete cp.size
    if cp.counts?
      counts = cp.counts
      delete cp.counts
    if cp.order?
      order = cp.order
      delete cp.order
    if not qry? and @index._q cp
      qry = await @index.translate cp
  return [] if not key
  query = if typeof qry is 'object' then qry else size: 0, query: bool: must: [], filter: [exists: field: key]
  query.query.bool.must.push(query_string: query: qry) if typeof qry is 'string'
  query.aggregations ?= {}
  # order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
  if order is 'count' # convert for ES7.x
    order = _count: 'desc' # default
  else if order is 'reverse_count'
    order = _count: 'asc'
  else if order is 'term'
    order = _key: 'asc'
  else if order is 'reverse_term'
    order = _key: 'desc'
  query.aggregations[key] = terms: field: key + (if key.indexOf('.keyword') is -1 then '.keyword' else ''), size: size, order: order
  ret = await @index._submit '/' + route + '/_search', query, 'POST'
  res = []
  for p in ret?.aggregations?[key]?.buckets ? []
    res.push if counts then {term: p.key, count: p.doc_count} else p.key
  return res

P.index.suggest = (route, key, qry, size=100, counts=false, order="term") ->
  if not route.endsWith 'suggest'
    [route, q] = route.split '/suggest/'
    key ?= route.split('/').pop()
    route = route.replace '/' + key, ''
    if q and not qry?
      qry = key + ':' + q + '*'
  res = []
  for k in await @index.terms route, key, qry, size, counts, order
    res.push(k) if not q or k.toLowerCase().indexOf(q.toLowerCase()) is 0 # or match at start?
  if res.length is 0 and q and typeof qry is 'string'
    qry = qry.replace ':', ':*'
    for k in await @index.terms route, key, qry, size, counts, order
      res.push(k) if not q or k.toLowerCase().indexOf(q.toLowerCase()) isnt -1 # or match at start?
  return res

P.index.count = (route, key, qry) ->
  try route ?= @params.index ? @params.route ? @fn.replace /\./g, '_'
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  try key ?= @params.count ? @params.key
  try
    cq = @copy @params
    delete cq[k] for k in ['index', 'route', 'count', 'key']
    qry = await @index.translate(cq) if not qry? and @index._q cq
  qry ?= query: bool: must: [], filter: []
  if key
    key += '.keyword' if key.indexOf('.keyword') is -1
    qry.size = 0
    qry.aggs =
      keyed:
        cardinality:
          field: key
          precision_threshold: 40000 # this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
    ret = await @index._submit '/' + route + '/_search', qry, 'POST'
    return ret?.aggregations?.keyed?.value
  else
    ret = await @index._submit '/' + route + '/_search', qry, 'POST'
    return ret?.hits?.total

P.index.min = (route, key, qry) ->
  try
    route ?= @fn.replace /\./g, '/'
    route = route.replace('index/', '').replace '/min', ''
    if not key? and route.indexOf('/') isnt -1
      [route, key] = route.split '/'
    delete @params.index
    if @index._q @params
      qry ?= await @index.translate @params
  query = if typeof key is 'object' then key else if qry? then qry else query: bool: must: [], filter: [exists: field: key]
  query.size = 0
  query.aggs = min: min: field: key
  ret = await @index._submit '/' + route + '/_search', query, 'POST'
  return ret.aggregations.min.value

P.index.max = (route, key, qry) ->
  try
    route ?= @fn.replace /\./g, '/'
    route = route.replace('index/', '').replace '/max', ''
    if not key? and route.indexOf('/') isnt -1
      [route, key] = route.split '/'
    delete @params.index
    if @index._q @params
      qry ?= await @index.translate @params
  query = if typeof key is 'object' then key else if qry? then qry else query: bool: must: [], filter: [exists: field: key]
  query.size = 0
  query.aggs = max: max: field: key
  ret = await @index._submit '/' + route + '/_search', query,'POST'
  return ret.aggregations.max.value

P.index.range = (route, key, qry) ->
  try
    route ?= @fn.replace /\./g, '/'
    route = route.replace('index/', '').replace '/range', ''
    if not key? and route.indexOf('/') isnt -1
      [route, key] = route.split '/'
    delete @params.index
    if @index._q @params
      qry ?= await @index.translate @params
  query = if typeof key is 'object' then key else if qry? then qry else query: bool: must: [], filter: [exists: field: key]
  query.size = 0
  query.aggs = min: {min: {field: key}}, max: {max: {field: key}}
  ret = await @index._submit '/' + route + '/_search', query, 'POST'
  return {min: ret.aggregations.min.value, max: ret.aggregations.max.value}

# previously used scan/scroll for each, but now use pit and search_after
# can still manually make scan/scroll calls if desired, see:
#  scan, scroll='10m'
#  if scan is true
#    route += (if route.indexOf('?') is -1 then '?' else '&')
#    if not data? or (typeof data is 'object' and not data.sort?) or (typeof data is 'string' and data.indexOf('sort=') is -1)
#      route += 'search_type=scan&'
#    route += 'scroll=' + scroll
#  else if scan?
#    route = '/_search/scroll?scroll_id=' + scan + (if action isnt 'DELETE' then '&scroll=' + scroll else '')
P.index._each = (route, q, opts, fn) ->
  # use search_after for each
  # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/paginate-search-results.html#search-after
  # each executes the function for each record. If the function makes changes to a record and saves those changes, 
  # this can cause many writes to the collection. So, instead, that sort of function could return something
  # and if the action has also been specified then all the returned values will be used to do a bulk write to the collection index.
  # suitable returns would be entire records for insert, record update objects for update, or record IDs for remove
  # this does not allow different actions for different records that are operated on - so has to be bulks of the same action
  if fn is undefined and opts is undefined and typeof q is 'function'
    fn = q
    q = '*'
  if fn is undefined and typeof opts is 'function'
    fn = opts
    opts = undefined
  opts ?= {}
  if opts.keep_alive?
    ka = opts.keep_alive
    delete opts.keep_alive
  else
    ka = '5m'
  if opts.action
    action = opts.action
    delete opts.action
  else
    action = false
  qy = await @index.translate q, opts
  qy.from = 0 # from has to be 0 for search_after
  qy.size ?= 1000 # 10000 is max and would be fine for small records...
  pit = await @index(route + '/_pit?keep_alive=' + ka).id # here route should be index name
  qy.pit = id: pit, keep_alive: ka # this gives a point in time ID that will be kept alive for given time, so changes don't ruin the result order
  # note sort should contain a tie-breaker on a record unique value, so check even if there is a sort
  # also what if there is no createdAt field? what to sort on?
  qy.sort ?= [{createdAt: 'asc'}]
  processed = 0
  updates = []
  total = false
  while res?.hits?.hits? and (total is false or processed < total)
    res = await @index route, qy
    total = res.hits.total if total is false
    for h in res.hits.hits
      processed += 1
      fn = fn.bind this
      fr = fn h._source ? h.fields ? {_id: h._id}
      updates.push(fr) if fr? and (typeof fr is 'object' or typeof fr is 'string')
      qy.search_after = h.sort
    qy.pit.id = res.pit_id
  if action and updates.length # TODO should prob do this during the while loop above, once updates reaches some number
    @index._bulk route, updates, action
  @index._submit '/_pit', id: pit # delete the pit

P.index._bulk = (route, data, action='index', bulk=50000) ->
  # https://www.elastic.co/guide/en/elasticsearch/reference/1.4/docs-bulk.html
  # https://www.elastic.co/guide/en/elasticsearch/reference/1.4/docs-update.html
  prefix = await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
  route = @S.index.name + '_' + route if prefix isnt false # need to do this here as well as in _submit so it can be set below in each object of the bulk
  cidx = if this?.index? then @index else P.index
  if typeof data is 'string' and data.indexOf('\n') isnt -1
    # TODO should this check through the string and make sure it only indexes to the specified route?
    await cidx._submit '/_bulk', {body:data, headers: {'Content-Type': 'application/x-ndjson'}} # new ES 7.x requires this rather than text/plain
    return true
  else
    rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
    rows = [rows] if not Array.isArray rows
    counter = 0
    pkg = ''
    for r of rows
      counter += 1
      row = rows[r]
      rid = undefined
      if typeof row is 'object'
        if row._source?
          row = row._source
        if row._id
          rid = row._id
          delete row._id # newer ES 7.x won't accept the _id in the object itself
        else
          rid = if this?.uid? then @uid() else P.uid()
      meta = {}
      meta[action] = {"_index": route }
      meta[action]._id = if action is 'delete' and typeof row is 'string' then row else rid # what if action is delete but can't set an ID?
      pkg += JSON.stringify(meta) + '\n'
      if action is 'create' or action is 'index'
        pkg += JSON.stringify(row) + '\n'
      else if action is 'update'
        pkg += JSON.stringify({doc: row}) + '\n' # is it worth expecting other kinds of update in bulk import?
      # don't need a second row for deletes
      if counter is bulk or parseInt(r) is (rows.length - 1) or pkg.length > 70000000
        rs = await cidx._submit '/_bulk', {body:pkg, headers: {'Content-Type': 'application/x-ndjson'}}
        if this?.S?.dev and rs?.errors
          errs = []
          for i in rs.items
            for k of i
              errs.push(i) if i[k].status >= 300
          console.log 'Bulk load errors: ' + errs.length + ', like: ' + JSON.stringify errs[0]
        pkg = ''
        counter = 0
    return rows.length

P.index._indices = (verbose=false) ->
  res = if verbose then {} else []
  s = await @index._submit '_stats'
  shards = if not verbose then [] else await @index._submit '_cat/shards?format=json'
  for i of s.indices
    if i not in [] and not i.startsWith('.') and not i.startsWith 'security-'
      if verbose
        # is primaries or total better for numbers here?
        res[i] = { docs: s.indices[i].primaries.docs.count, size: Math.ceil(s.indices[i].primaries.store.size_in_bytes / 1024 / 1024) + 'mb' } 
        for sh in shards
          if sh.index is i and sh.prirep is 'p'
            res[i].shards ?= 0
            res[i].shards += 1
      else
        res.push i
  return res

P.index.status = () ->
  res = status: 'green'
  res.indices = await @index._indices true
  try
    res.status = 'red' if res.cluster.status not in ['green','yellow'] # accept yellow for single node cluster (or configure ES itself to accept that as green)
    for k in ['cluster_name', 'number_of_nodes', 'number_of_data_nodes', 'unassigned_shards']
      delete res.cluster[k] # or delete all of cluster info?
  return res
P.index.status._cache = false

# helper to identify strings or objects that likely should be interpreted as queries
P.index._q = (q, rt) -> # could this be a query as opposed to an _id or index/_id string
  if typeof q is 'object' and not Array.isArray q
    for k in ['settings', 'aliases', 'mappings', 'index']
      return false if q[k] # these keys indicate some sort of index settings object rather than query
    if q.q? or q.query?
      return true # q or query COULD be valid values of an object, in which case don't pass such objects to ambiguous locations such as the first param of an index function
  else if typeof q is 'string' and q.length and q.indexOf('\n') is -1 # newlines indicates a bulk load string
    if typeof rt is 'string' and q.toLowerCase().startsWith rt.toLowerCase()
      return false # handy check for a string that is probably an index route, just to save manually checking elsewhere
    else if q.startsWith('?') or q.startsWith('q=') # like an incoming URL query params string
      return true
    else if q.length < 8 or (if q.indexOf('/') isnt -1 then q.split('/').pop() else q).length > 34 # no _id would be shorter than 8 or longer than 34
      return true
    else
      for c in [' ', ':', '*', '~', '(', ')', '?'] # none of these are present in an ID
        return true if q.indexOf(c) isnt -1
  return false

### query formats that can be accepted:
    'A simple string to match on'
    'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
    '?q=query params directly as string'
    {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
    {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "should" as well)
    {"object":"of key/value pairs, all of which must match"} - so this is an AND terms match/ If keys do not point to strings, they will be assumed to be named ES queries that can drop into the bool
    ["list","of strings to OR match on"] - this is an OR query strings match UNLESS strings contain : then mapped to terms matches
    [{"list":"of objects to OR match"}] - so a set of OR terms matches. If objects are not key: string they are assumed to be full ES queries that can drop into the bool

    Keys can use dot notation

    Options that can be included:
    If options is true, the query will be adjusted to sort by createdAt descending, so returning the newest first (it sets newest:true, see below)
    If options is string 'random' it will convert the query to be a random order
    If options is a number it will be assumed to be the size parameter
    Otherwise options should be an object (and the above can be provided as keys, "newest", "random")
    If newest is true the query will have a sort desc on createdAt. If false, sort will be asc
    If "random" key is provided, "seed" can be provided too if desired, for seeded random queries
    If "restrict" is provided, should point to list of ES queries to add to the and part of the query filter
    Any other keys in the options object should be directly attributable to an ES query object

    For ES 7.x there is no filtered query any more, filter is a value of bool.must
    Filter essentially acts like a must but without scoring. Whereas normal must does score.
    must_not also does not affect score. Not sure about should
    
    Default empty query looks like:
    {query: {bool: {must: [], filter: []}}, size: 10}
###
P.index.translate = (q, opts={}) ->
  q ?= this?.params
  try q = @copy(q) if typeof q is 'object' # copy objects so don't interfere with what was passed in
  try opts = @copy(opts) if typeof opts is 'object'
  opts = {random:true} if opts is 'random'
  opts = {size:opts} if typeof opts is 'number'
  opts = {newest: true} if opts is true
  opts = {newest: false} if opts is false
  qry = opts?.query ? {}
  qry.query ?= {}
  _structure = (sq) ->
    if not sq.query?
      sq.query = bool: must: [], filter: []
    if not sq.query.bool?
      ms = []
      ms.push(sq.query) if JSON.stringify(sq.query) isnt '{}'
      sq.query = bool: must: ms, filter: []
    sq.query.bool.must ?= []
    sq.query.bool.filter ?= []
    return sq
  qry = _structure qry
  if typeof q is 'object'
    delete q[dk] for dk in ['apikey','_','callback','refresh','key','counts','index']
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
      opts.sort = {createdAt:{order:'desc'}} # TODO check this for new ES7.x, and see that createdAt field still exists for new system
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
    if opts.all?
    # TODO newer ES doesn't allow more than 10k by default, need to do scan/scroll or whatever the new equivalent is
      qry.size = 1000000 # just a simple way to try to get "all" records - although passing size would be a better solution, and works anyway
      delete opts.all
    if opts.terms?
      try opts.terms = opts.terms.split(',')
      qry.aggregations ?= {}
      for tm in opts.terms
        qry.aggregations[tm] = { terms: { field: tm + (if tm.indexOf('.keyword') is -1 then '.keyword' else ''), size: 1000 } }
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
