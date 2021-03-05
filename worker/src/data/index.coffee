
# TODO be able to receive bulk json lists or formatted bulk strings. Need to stick the useful default values into each
# those would be createdAt, created_date (in default templates format for ES 7.1) and user ID of the action?

# TODO if history true, saving any change should be preceded by saving a copy to a history index, with a note of the user making the change
# could automatically save every change to a history index. Can put all history records into the same index?
# as long as the change is stored as a text string it wouldn't matter, as uuids won't clash anyway, and just record the source index
# perhaps separate histories into timestamped indexes? which es7 uses "data streams" for...

# TODO if also sheet param, sync from sheet at some interval
# so then don't accept changes on the API? Or merge them somehow? That would require developing the google src further
# to begin, prob just refuse edits if sheet - manage sheet here or at higher leve, or in a sheet function?

# TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
# alias can be set on create, and may be best just to use an alias every time
# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html

# TODO can also use aliases and alternate routes to handle auth to certain subsets of date
# aliased mappings can also have a filter applied, so only the filtered results get returned

# TODO if index isn't available use a lunr file if possible as a fallback?

# TOD if index SHOULD be available but fails, write to kv if that's available? But don't end up in a loop...
# anything found by _schedule in kv that isn't set to _kv will get written to index once it becomes available

S.index ?= {}
S.index.name ?= S.name ? 'n2'
# need at least an S.index.url here as well

P.index = (route, data) ->
  console.log route
  console.log data
  if not route and not data? and this?.parts? and @parts.length and @parts[0] is 'index'
    if @parts.length > 1 and (@parts[1].startsWith('.') or @parts[1].startsWith('_') or @parts[1] in ['svc','src'] or P[@parts[1]]?) #  or @parts[1].startsWith('svc_') or @parts[1].startsWith('src_'))
      # don't allow direct calls to index if the rest of the params indicate an existing route
      # if not an existing route, a user with necessary auth could create/interact with a specified index
      # for indexes not on a specified route, their config such as auth etc will need to be passed at creation and stored somewhere
      return status: 403 # for now this isn't really stopping things, for example svc_crossref_works

  if typeof route is 'object'
    data = route
    route = undefined
    
  if not route and not data? # only take data from incoming if directly on the index route
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
  
  if not route
    if @parts[0] is 'index' # need custom auth for who can create/remove indexes and records directly?
      if @parts.length is 1
        return await @index._indices()
      else if @parts.length is 2 # called direct on an index
        route = @parts[1]
      else if @parts.length > 2 # called on index/key route
        # most IDs will only be at position 3 but for example using a DOI as an ID would spread it across 3 and 4
        route = @parts[1] + '/' + @parts.slice(2).join '_' # so combine them with an underscore - IDs can't have a slash in them
    else
      # auth should not matter here because providing route or data means the function is being handled elsehwere, which should deal with auth
      route = @fn.replace /\./g, '_' # if the wrapping function wants data other than that defined by the URL route it was called on, it MUST specify the route manually
      # what if the @parts indicate this is a request for a specific record though, not just an index?
      route += '/' + @parts.join('_').replace(route + '_', '') if @parts.join('.') isnt @fn

  if typeof data is 'object' and not Array.isArray(data) and data._id
    dni = data._id.replace /\//g, '_'
    route += '/' + data._id if route.indexOf('/') is -1 and route.indexOf(dni) is -1
    delete data._id # ID can't go into the data for ES7.x

  route = route.toLowerCase()
  rpl = route.split('/').length
  if (@parts[0] is 'index' and (@request.method is 'DELETE' or @params._delete)) or data is ''
    # DELETE can happen on index or index/key, needs no additional route parts for index but index/key has to happen on _doc
    # TODO for @params._delete allow a passthrough of data in case it is a delete by query, once _submit is updated to handle that if still possible
    ret = await @index._submit route.replace('/', '/_doc/'), ''
    return undefined #ret.acknowledged is true or ret.result is 'deleted'
  else if rpl is 1
    # CREATE can happen on index if index params are provided or empty object is provided
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
    # simplest create would be {} or settings={number_of_shards:1} where 1 is default anyway
    if typeof data is 'string' and data.indexOf('\n') is -1
      try data = @index.translate data
    if typeof data is 'string' or Array.isArray data
      return @index._bulk route, data # bulk create (TODO what about if wanting other bulk actions?)
    else if typeof data is 'object'
      if @index._q data
        return @index._submit route + '/_search', @index.translate data
      else
        chk = @copy data
        delete chk[c] for c in ['settings', 'aliases', 'mappings']
        if JSON.stringify(chk) is '{}'
          if not await @index._submit route
            ind = if not @index._q(data) then {settings: data.settings, aliases: data.aliases, mappings: data.mappings} else {}
            await @index._submit route, ind # create the index
          return @index._submit route + '/_search' # just do a search
        else
          return @index._submit route + '/_doc', data # create a single record without ID (if it came with ID it would have been caught above and converted to route with multiple parts)
    else
      return @index._submit route + '/_search'
  else if rpl is 2 and (not data? or typeof data is 'object' and not Array.isArray data)
    # CREATE or overwrite on index/key if data is provided - otherwise just GET the _doc
    # Should @params be able to default to write data on index/key?
    # TODO check how ES7.x accepts update with script in them
    if data? and JSON.stringify(data) isnt '{}'
      route = if data.script? then route + '/_update?retry_on_conflict=2' else route.replace '/', '/_create/' # does PUT create work if it already exists? or PUT _doc? or POST _create?
      return @index._submit route, data
    else # or just get the record
      ret = await @index._submit route.replace '/', '/_doc/'
      if typeof ret is 'object' and (ret._source or ret.fields)
        rex = ret._source ? ret.fields
        rex._id ?= ret._id # if _id can no longer be stored in the _source in ES7.x
        ret = rex
      return ret

  return undefined


# calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
# call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
# what about namespacing to env? do here or above, or neither?
P.index._submit = (route, data, method, deletes=true) -> # deletes is true in dev, but remove or add auth control for live
  console.log route
  console.log data
  route = route.toLowerCase() # force lowercase on all IDs so that can deal with users giving incorrectly cased IDs for things like DOIs which are defined as case insensitive
  route = route.replace('/','') if route.indexOf('/') is 0 # gets added back in when combined with the url
  method ?= if route is '/_pit' or data is '' then 'DELETE' else if data? and (route.indexOf('/') is -1 or route.indexOf('/_create') isnt -1 or (route.indexOf('/_doc') isnt -1 and not route.endsWith('/_doc'))) then 'PUT' else if data? or route.split('/').pop().split('?')[0] in ['_refresh', '_pit', '_aliases'] then 'POST' else 'GET'
  # TODO if data is a query that also has a _delete key in it, remove that key and do a delete by query? and should that be bulked? is dbq still allowed in ES7.x?
  console.log method
  return false if method is 'DELETE' and (deletes isnt true or route.indexOf('/_all') isnt -1) # nobody can delete all via the API
  if not route.startsWith 'http' # which it probably doesn't
    url = if this?.S?.index?.url then @S.index.url else S.index?.url
    url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
    if typeof url isnt 'string'
      return undefined
    route = url + '/' + route
  #if dev and route.indexOf('_dev') is -1 and route.indexOf('/_') isnt 0
  #  rpd = route.split '/'
  #  rpd[1] += '_dev'
  #  rpd[1] = rpd[1].replace(',','_dev,')
  #  route = rpd.join '/'
  opts = if route.indexOf('/_bulk') isnt -1 or typeof data?.headers is 'object' then data else body: data # fetch requires data to be body

  #opts.retry = 3
  opts.method = method
  res = if this?.fetch? then await @fetch(route, opts) else await P.fetch route, opts # is it worth having P. as opposed to @ options?
  if not res? or (typeof res is 'object' and typeof res.status is 'number' and res.status >= 400 and res.status <= 600)
    # fetch returns undefined for 404, otherwise any other error from 400 is returned like status: 400
    # write a log / send an alert?
    #em = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', method: method, url: url, route: route, opts: opts, error: err.toString()
    #if this?.log? then @log(em) else P.log em
    # do anything for 409 (version mismatch?)
    return undefined
  else
    try res.q = opts.body if @S.dev and opts?.body?.query?
    return res


P.index._mapping = (route) ->
  return false if typeof route isnt 'string'
  route = route.replace /^\//, '' # remove any leading /
  route = route + '/' if route.indexOf('/') is -1
  route = route.replace('/','/_mapping') if route.indexOf('_mapping') is -1
  return await @index._submit route

P.index.keys = (route) ->
  keys = []
  try
    _keys = (mapping, depth='') ->
      mapping ?= if typeof route is 'object' then route else @index._mapping route
      if mapping.properties?
        depth += '.' if depth.length
        for k of mapping.properties
          keys.push(depth+k) if depth+k not in keys
          if mapping.properties[k].properties?
            _keys mapping.properties[k], depth+k
    _keys()
  return keys

P.index.terms = (route, key, qry, size=1000, counts=false, order="count") ->
  # TODO check how to specify if terms facet (which needs to update to agg) needs to be on .keyword rather than just key (like how .exact used to be used)
  query = if typeof qry is 'object' then qry else { query: {"filtered":{"filter":{"exists":{"field":key}}}}, size: 0, facets: {} }
  query.filtered.query = { query_string: { query: qry } } if typeof qry is 'string'
  query.facets ?= {}
  # order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
  query.facets[key] = { terms: { field: key, size: size, order: order } }
  try
    ret = @index._submit '/' + route + '/_search', query, 'POST'
    return if not ret?.facets? then [] else (if counts then ret.facets[key].terms else _.pluck(ret.facets[key].terms,'term'))
  catch err
    return []

P.index.count = (route, key, query) ->
  query ?= { query: {"filtered":{"filter":{"bool":{"must":[]}}}}}
  if key?
    query.size = 0
    query.aggs = {
      "keycard" : {
        "cardinality" : {
          "field" : key,
          "precision_threshold": 40000 # this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
        }
      }
    }
    return @index._submit('/' + route + '/_search', query, 'POST')?.aggregations?.keycard?.value
  else
    return @index._submit('/' + route + '/_search', query, 'POST')?.hits?.total?.value

P.index.min = (route, key, qry) ->
  query = if typeof key is 'object' then key else if qry? then qry else {query:{"filtered":{"filter":{"exists":{"field":key}}}}}
  query.size = 0
  query.aggs = {"min":{"min":{"field":key}}}
  ret = @index._submit '/' + route + '/_search', query, 'POST'
  return ret.aggregations.min.value

P.index.max = (route, key, qry) ->
  query = if typeof key is 'object' then key else if qry? then qry else {query:{"filtered":{"filter":{"exists":{"field":key}}}}}
  query.size = 0
  query.aggs = {"max":{"max":{"field":key}}}
  ret = @index._submit '/' + route + '/_search', query,'POST'
  return ret.aggregations.max.value

P.index.range = (route, key, qry) ->
  query = if typeof key is 'object' then key else if qry? then qry else {query:{"filtered":{"filter":{"exists":{"field":key}}}}}
  query.size = 0
  query.aggs = {"min":{"min":{"field":key}}, "max":{"max":{"field":key}}}
  ret = @index._submit '/' + route + '/_search', query, 'POST'
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
  qy = P.index.translate q, opts
  qy.from = 0 # from has to be 0 for search_after
  qy.size ?= 1000 # 10000 is max and would be fine for small records...
  pit = @index(route + '/_pit?keep_alive=' + ka).id # here route should be index name
  qy.pit = id: pit, keep_alive: ka # this gives a point in time ID that will be kept alive for given time, so changes don't ruin the result order
  # note sort should contain a tie-breaker on a record unique value, so check even if there is a sort
  # also what if there is no createdAt field? what to sort on?
  qy.sort ?= [{createdAt: 'asc'}]
  processed = 0
  updates = []
  total = false
  while res?.hits?.hits? and (total is false or processed < total)
    res = @index route, qy
    total = res.hits.total.value if total is false
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
  #url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  #route += '_dev' if dev and route.indexOf('_dev') is -1
  # TODO need a check somewhere that incoming bulk data is about the relevant index - not bulking data to a different index than the one authorised on the route
  if typeof data is 'string' and data.indexOf('\n') isnt -1
    await @index._submit '/_bulk', {content:data, headers: {'Content-Type': 'text/plain'}}
    return true
  else
    rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
    rows = [rows] if not Array.isArray rows
    counter = 0
    pkg = ''
    for r of rows
      counter += 1
      row = rows[r]
      #row._index += '_dev' if typeof row isnt 'string' and row._index? and row._index.indexOf('_dev') is -1 and dev
      row._id = @uid() if typeof row is 'object' and not row._id? # TODO any other default fields that should be added? createdAt?
      meta = {}
      meta[action] = {"_index": (if typeof row isnt 'string' and row._index? then row._index else route) }
      meta[action]._id = if action is 'delete' and typeof row is 'string' then row else row._id # what if action is delete but can't set an ID?
      pkg += JSON.stringify(meta) + '\n'
      if action is 'create' or action is 'index'
        pkg += JSON.stringify(if row._source then row._source else row) + '\n'
      else if action is 'update'
        delete row._id if row._id?
        pkg += JSON.stringify({doc: row}) + '\n' # is it worth expecting other kinds of update in bulk import?
      # don't need a second row for deletes
      if counter is bulk or parseInt(r) is (rows.length - 1) or pkg.length > 70000000
        await @index._submit '/_bulk', {content:pkg, headers: {'Content-Type': 'text/plain'}}
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
        res[i] = { docs: s.indices[i].primaries.docs.count, size: Math.ceil(s.indices[i].primaries.store.size_in_bytes / 1024 / 1024) } 
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


# helper to identify strings or objects that likely should be interpreted as queries
P.index._q = (q, rt) -> # could this be a query as opposed to an _id or index/_id string
  if typeof q is 'object' and not Array.isArray q
    for k in ['settings', 'aliases', 'mappings', 'index']
      return false if q[k] # these keys indicate some sort of index settings object rather than query
    if q.q? or q.query?
      return true # q or query COULD be valid values of an object, in which case don't pass such objects to ambiguous locations such as the first param of an index function
  else if typeof q is 'string' and q.indexOf('\n') is -1 # newlines indicates a bulk load string
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
    TODO can add more conveniences for passing options in here, such as simplified terms, etc.

    Default query looks like:
    {query: {filtered: {query: {match_all: {}}, filter: {bool: {must: []}}}}, size: 10}
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
    if not sq.query? or not sq.query.filtered?
      sq.query = filtered: {query: sq.query, filter: {}}
    sq.query.filtered.filter ?= {}
    sq.query.filtered.filter.bool ?= {}
    sq.query.filtered.filter.bool.must ?= []
    if not sq.query.filtered.query.bool?
      ms = []
      ms.push(sq.query.filtered.query) if JSON.stringify(sq.query.filtered.query) isnt '{}'
      sq.query.filtered.query = bool: must: ms
    sq.query.filtered.query.bool.must ?= []
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
      qry.query.filtered.filter.bool.should = []
      for m in q
        if typeof m is 'object' and m?
          for k of m
            if typeof m[k] is 'string'
              tobj = term:{}
              tobj.term[k] #TODO check how a term query on a text string works on newer ES. Does it require the term query to be in .keyword?
              qry.query.filtered.filter.bool.should.push tobj
            else if typeof m[k] in ['number','boolean']
              qry.query.filtered.query.bool.should.push {query_string:{query:k + ':' + m[k]}}
            else if m[k]?
              qry.query.filtered.filter.bool.should.push m[k]
        else if typeof m is 'string'
          qry.query.filtered.query.bool.should ?= []
          qry.query.filtered.query.bool.should.push query_string: query: m
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
        qry.query.filtered.query.bool.must.push prefix: pfx
      else
        qry.query.filtered.query.bool.must.push query_string: query: q.q
      opts ?= {}
      for o of q
        opts[o] ?= q[o] if o not in ['q']
    else
      if q.must?
        qry.query.filtered.filter.bool.must = q.must
      if q.should?
        qry.query.filtered.filter.bool.should = q.should
      if q.must_not?
        qry.query.filtered.filter.bool.must_not = q.must_not
      for y of q # an object where every key is assumed to be an AND term search if string, or a named search object to go in to ES
        if (y is 'fields') or (y is 'sort' and typeof q[y] is 'string' and q[y].indexOf(':') isnt -1) or (y in ['from','size'] and (typeof q[y]is 'number' or not isNaN parseInt q[y]))
          opts ?= {}
          opts[y] = q[y]
        else if y not in ['must','must_not','should']
          if typeof q[y] is 'string'
            tobj = term:{}
            tobj.term[y] = q[y]
            qry.query.filtered.filter.bool.must.push tobj
          else if typeof q[y] in ['number','boolean']
            qry.query.filtered.query.bool.must.push {query_string:{query:y + ':' + q[y]}}
          else if typeof q[y] is 'object'
            qobj = {}
            qobj[y] = q[y]
            qry.query.filtered.filter.bool.must.push qobj
          else if q[y]?
            qry.query.filtered.filter.bool.must.push q[y]
  else if typeof q is 'string'
    if q.indexOf('?') is 0
      qry = q # assume URL query params and just use them as such?
    else if q?
      q = '*' if q is ''
      qry.query.filtered.query.bool.must.push query_string: query: q
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
      if qry.query.filtered
        fq.function_score.query = qry.query.filtered.query
        qry.query.filtered.query = fq
      else
        fq.function_score.query = qry.query
        qry.query = fq
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
      qry.query.filtered.filter.bool.must.push a for a in opts.and
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
    if opts.restrict?
      qry.query.filtered.filter.bool.must.push(rs) for rs in opts.restrict
      delete opts.restrict
    if opts.not? or opts.must_not?
      tgt = if opts.not? then 'not' else 'must_not'
      if Array.isArray opts[tgt]
        qry.query.filtered.filter.bool.must_not = opts[tgt]
      else
        qry.query.filtered.filter.bool.must_not ?= []
        qry.query.filtered.filter.bool.must_not.push(nr) for nr in opts[tgt]
      delete opts[tgt]
    if opts.should?
      if Array.isArray opts.should
        qry.query.filtered.filter.bool.should = opts.should
      else
        qry.query.filtered.filter.bool.should ?= []
        qry.query.filtered.filter.bool.should.push(sr) for sr in opts.should
      delete opts.should
    if opts.all?
    # TODO newer ES doesn't allow more than 10k by default, need to do scan/scroll or whatever the new equivalent is
      qry.size = 1000000 # just a simple way to try to get "all" records - although passing size would be a better solution, and works anyway
      delete opts.all
    if opts.terms?
      try opts.terms = opts.terms.split(',')
      qry.facets ?= {}
      for tm in opts.terms
        qry.facets[tm] = { terms: { field: tm, size: 1000 } }
      delete opts.terms
    for af in ['facets','aggs','aggregations']
      if opts[af]?
        qry[af] ?= {}
        qry[af][f] = opts[af][f] for f of opts[af]
        delete opts[af]
    qry[k] = v for k, v of opts
  # no filter query or no main query can cause issues on some queries especially if certain aggs/terms are present, so insert some default searches if necessary
  qry.query.filtered.query = { match_all: {} } if typeof qry is 'object' and qry.query?.filtered?.query? and JSON.stringify(qry.query.filtered.query) is '{}'
  #qry.query.filtered.query.bool.must = [{"match_all":{}}] if typeof qry is 'object' and qry.query?.filtered?.query?.bool?.must? and qry.query.filtered.query.bool.must.length is 0 and not qry.query.filtered.query.bool.must_not? and not qry.query.filtered.query.bool.should and (qry.aggregations? or qry.aggs? or qry.facets?)
  # clean slashes out of query strings
  if qry.query?.filtered?.query?.bool?
    for bm of qry.query.filtered.query.bool
      for b of qry.query.filtered.query.bool[bm]
        if typeof qry.query.filtered.query.bool[bm][b].query_string?.query is 'string' and qry.query.filtered.query.bool[bm][b].query_string.query.indexOf('/') isnt -1
          qry.query.filtered.query.bool[bm][b].query_string.query = qry.query.filtered.query.bool[bm][b].query_string.query.replace(/\//g,'\\/')
  if qry.query?.filtered?.filter?.bool?
    for fm of qry.query.filtered.filter.bool
      for f of qry.query.filtered.filter.bool[fm]
        if qry.query.filtered.filter.bool[fm][f].query_string?.query? and qry.query.filtered.filter.bool[fm][f].query_string.query.indexOf('/') isnt -1
          qry.query.filtered.filter.bool[fm][f].query_string.query = qry.query.filtered.filter.bool[fm][f].query_string.query.replace(/\//g,'\\/')
  delete qry._source if qry._source? and qry.fields?
  return qry
