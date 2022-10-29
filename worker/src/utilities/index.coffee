
# TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
# alias can be set on create, and may be best just to use an alias every time
# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html
# can also use aliases and alternate routes to handle auth to certain subsets of date
# aliased mappings can also have a filter applied, so only the filter results get returned

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

  route = route.toLowerCase()
  rpl = route.split('/').length
  this.index ?= P.index # allow either P.index or a contextualised @index to be used
  if (this?.parts? and @parts[0] is 'index' and @parts[1] is route.split('/')[0] and (@request.method is 'DELETE' or @params._delete)) or data is ''
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
      if JSON.stringify(data) isnt '{}' and qr = await @index.translate data, opts
        return @index._send route + '/_search' + rqp, qr
      else if typeof data is 'object'
        chk = if this?.copy? then @copy(data) else P.copy data
        delete chk[c] for c in ['settings', 'aliases', 'mappings']
        if JSON.stringify(chk) is '{}'
          if not await @index._send route + rqp
            await @index._send route + rqp, {settings: data.settings, aliases: data.aliases, mappings: (data.mappings ? data.mapping)} # create the index
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
P.index._caches = false

P.index.status = () ->
  res = status: 'green', docs: 0, size: 0, shards: 0, failed: 0
  try
    stats = await @index._send '_nodes/stats/indices/search'
    for i of stats.nodes
      res.scrolls ?= 0
      res.scrolls += stats.nodes[i].indices.search.open_contexts
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
          res.indices[i].failed ?= 0
          res.indices[i].failed += 1 if sh.state is 'UNASSIGNED'
      res.docs += res.indices[i].docs
      try res.size += parseInt res.indices[i].size.replace 'mb', ''
      res.shards += res.indices[i].shards
      res.failed += res.indices[i].failed
  res.size = Math.ceil (res.size/1000) + 'gb'
  try
    res.status = 'red' if res.cluster.status not in ['green','yellow'] # accept yellow for single node cluster (or configure ES itself to accept that as green)
    for k in ['cluster_name', 'number_of_nodes', 'number_of_data_nodes', 'unassigned_shards']
      delete res.cluster[k] # or delete all of cluster info?
  return res



P.index.keys = (route, type) ->
  # type could most usefully be "text" to show fields that can be suggested on, or long or date (lists of types can be provided)
  # https://www.elastic.co/guide/en/elasticsearch/reference/6.8/mapping-types.html
  route ?= @params.index ? @params.keys ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/keys', ''
  type ?= @params.type ? @params.types
  type = [type] if typeof type is 'string'
  keys = if type is true then {} else []
  mapping = if typeof route is 'object' then route else await @index.mapping route
  _keys = (m, depth='') =>
    depth += '.' if depth
    for k of m
      if m[k].properties?
        await _keys m[k].properties, depth+k
      else if not type or type is true or m[k].type in type
        if type is true
          keys[depth+k] = m[k].type
        else
          keys.push(depth+k) if depth+k not in keys
  await _keys(mapping) if typeof mapping is 'object'
  return keys

P.index.terms = (route, key, qry, size=100, counts=true, order="count") ->
  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/terms', ''
  if not key or not qry
    key ?= @params.terms ? @params.key
    if not key? and route.indexOf('/') isnt -1
      [route, key] = route.split '/'
    return [] if not key
    cq = @copy @params
    delete cq[k] for k in ['index', 'route', 'terms', 'key']
  qry = await @index.translate(qry) if qry?
  qry ?= await @index.translate cq
  query = if typeof qry is 'object' then qry else size: 0, query: bool: must: [], filter: [exists: field: key]
  query.query.bool.must.push(query_string: query: qry) if typeof qry is 'string'
  query.aggregations ?= {}
  query.size ?= 0
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

P.index.suggest = (route, key, qry, size=100, include) ->
  if not key or not qry
    key ?= @params.suggest ? @params.key
    [key, qry] = key.split('/') if typeof key is 'string' and key.includes '/'
  return @index.keys(route, 'text') if not key

  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').split('/suggest')[0]
  include ?= @params.include
  include = include.replace(/,\s/g, ',').split(',') if typeof include is 'string'
  include.push(key) if Array.isArray(include) and key not in include

  if typeof qry is 'string'
    qry = qry.trim()
    ql = qry.toLowerCase()
    tqr = should: [{match: {}}, {prefix: {}}, {query_string: {query: key + ':' + qry.split(' ').join(' AND ' + key + ':') + '*'}}]
    tqr.should[0].match[key] = query: qry, boost: 3
    tqr.should[1].prefix[key] = value: qry, boost: 2

  res = []
  seen = []

  if include # NOTE to include extra vals this has to be a search of records, and it may not find all possible values, whereas the terms option without include will
    for await rec from @index._for route, (tqr ? qry), sort: key + '.keyword', until: size, include: (if include is true then [key] else include)
      if k = await @dot rec, key
        while Array.isArray(k) and ak = k.shift()
          k = ak if ak.toLowerCase().includes ql
        kl = k.toLowerCase()
        res.push(rec) if kl not in seen and (not ql or kl.includes ql)
        seen.push kl
  else
    for k in await @index.terms route, key, (tqr ? qry), size, false, 'term'
      kl = k.toLowerCase()
      console.log kl
      res.push(k) if kl not in seen and (not ql or kl.includes ql)
      seen.push kl
  return res

P.index.count = (route, qry, key) ->
  key ?= @params.count ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '_'
  route = route.replace('index/', '').split('/count')[0]
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'count', 'key']
  qry = qr if not qry? and qr = await @index.translate cq
  qry = await @index.translate(qry) if typeof qry is 'string'
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

P.index.percent = (route, qry, key) ->
  key ?= @params.count ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '_'
  route = route.replace('index/', '').split('/count')[0]
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'count', 'key']
  qry = qr if not qry? and qr = await @index.translate cq
  qry = await @index.translate(qry) if typeof qry is 'string'
  qry ?= query: bool: must: [], filter: []
  total = await @index.count route, '*'
  count = 0
  if key
    key += '.keyword' if not key.endsWith '.keyword'
    qry.size = 0
    qry.aggs = keyed: cardinality: field: key, precision_threshold: 40000 # this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
    ret = await @index._send '/' + route + '/_search', qry, 'POST'
    count = ret?.aggregations?.keyed?.value
  else
    ret = await @index._send '/' + route + '/_search', qry, 'POST'
    count = ret?.hits?.total
  return Math.ceil((count/total)*10000)/100

P.index.min = (route, key, qry, end='min') ->
  key ?= @params[end] ? @params.key
  route ?= @params.index ? @fn.replace /\./g, '/'
  route = route.replace('index/', '').replace '/' + end, ''
  if route.indexOf('/') isnt -1
    [route, key] = route.split '/'
  cq = @copy @params
  delete cq[k] for k in ['index', 'route', 'min', 'max', 'key', 'sum']
  qry ?= await @index.translate cq
  query = if typeof key is 'object' then key else if qry? then qry else query: bool: must: [], filter: [exists: field: key]
  query.size = 0
  if end is 'sum'
    query.aggs = sum: sum: field: key
  else
    query.aggs = {}
    query.aggs.min = {min: {field: key}} if end in ['min', 'range']
    query.aggs.max = {max: {field: key}} if end in ['max', 'range']
  ret = await @index._send '/' + route + '/_search', query, 'POST'
  return if end is 'range' then {min: ret.aggregations.min.value, max: ret.aggregations.max.value} else ret.aggregations[end].value

P.index.max = (route, key, qry) -> return @index.min route, key, qry, 'max'
P.index.range = (route, key, qry) -> return @index.min route, key, qry, 'range'
P.index.sum = (route, key, qry) -> return @index.min route, key, qry, 'sum'

P.index.mapping = (route) ->
  route = route.replace /^\//, '' # remove any leading /
  route = route + '/' if route.indexOf('/') is -1
  route = route.replace('/','/_mapping') if route.indexOf('_mapping') is -1
  ret = await @index._send route
  rtm = (await @keys ret)[0] #route.replace('/_mapping', '').replace(/\//g, '_').replace(/^_/, '')
  return ret[rtm].mappings.properties



# use this like: for await rec from @index._for route, q, opts
# see index._each below for example of how to call this for/yield generator
P.index._for = (route, q, opts, prefix) ->
  opts = {until: opts} if typeof opts is 'number'
  if opts?.scroll # set this longer, e.g. 10m, if the processing to be done with the records may take longer than a minute
    scroll = opts.scroll
    scroll += 'm' if typeof scroll is 'number' or not scroll.endsWith 'm'
    delete opts.scroll
  else
    scroll = '2m'
  if opts?.until or opts?.max
    max = opts.until ? opts.max
    delete opts.until
    delete opts.max
  q ?= '*'
  qy = await @index.translate q, opts
  qy.from ?= 0
  qy.size ?= 500
  qy.sort ?= ['_doc'] # performance improved for scrolling sorted on _doc if no other sort was configured
  # use scan/scroll for each, because _pit is only available in "default" ES, which ES means is NOT the open one, so our OSS distro does not include it!
  # https://www.elastic.co/guide/en/elasticsearch/reference/7.10/paginate-search-results.html#search-after
  res = await @index._send route + '/_search?scroll=' + scroll, qy, undefined, prefix
  if res?._scroll_id
    prs = res._scroll_id.replace /==$/, ''
  max = res.hits.total if res?.hits?.total and (not max? or max > res.hits.total)
  counter = 0
  loop
    if (not res?.hits?.hits or res.hits.hits.length is 0) and res?._scroll_id # get more if possible
      res = await @index._send '/_search/scroll?scroll=' + scroll + '&scroll_id=' + res._scroll_id, undefined, undefined, prefix
      if res?._scroll_id isnt prs
        await @index._send '/_search/scroll?scroll_id=' + prs, '', undefined, prefix
        prs = res?._scroll_id
    if counter isnt max and res?.hits?.hits? and res.hits.hits.length
      counter += 1
      r = res.hits.hits.shift()
      ret = r._source ? r.fields
      ret._id ?= r._id
      yield ret
    else
      await @index._send('/_search/scroll?scroll_id=' + prs, '', undefined, prefix) if prs # don't keep too many old scrolls open (default ES max is 500)
      break
  return

P.index._each = (route, q, opts, fn, prefix) ->
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
    chk = await @index._send route, qy, undefined, prefix
    if chk?.hits?.total? and chk.hits.total isnt 0
      # try to make query result size not take up more than about 1gb. In a scroll-scan size is per shard, not per result set
      max_size = Math.floor(1000000000 / (Buffer.byteLength(JSON.stringify(chk.hits.hits[0])) * chk._shards.total))
      sz = max_size if max_size < sz
    qy.size = sz

  processed = 0
  updates = []
  for await rec from @index._for route, (qy ? q), opts, prefix
    fr = await fn.call this, rec
    processed += 1
    updates.push(fr) if fr? and (typeof fr is 'object' or typeof fr is 'string')
    if action and updates.length > sz
      await @index._bulk route, updates, action, undefined, prefix
      updates = []
  @index._bulk(route, updates, action, undefined, prefix) if action and updates.length # catch any left over
  console.log('_each processed ' + processed) if @S.dev and @S.bg is true

P.index._bulk = (route, data, action='index', bulk=50000, prefix) ->
  action = 'index' if action is true
  prefix ?= await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
  if prefix isnt false # need to do this here as well as in _send so it can be set below in each object of the bulk
    route = (if typeof prefix is 'string' then prefix else @S.index.name) + '_' + route
  this.index ?= P.index
  if typeof data is 'string' and data.indexOf('\n') isnt -1
    # TODO should this check through the string and make sure it only indexes to the specified route?
    await @index._send '/_bulk', {body:data, headers: {'Content-Type': 'application/x-ndjson'}}, undefined, prefix # new ES 7.x requires this rather than text/plain
    return true
  else
    rows = if typeof data is 'object' and not Array.isArray(data) and data?.hits?.hits? then data.hits.hits else data
    rows = [rows] if not Array.isArray rows
    counter = 0
    errorcount = 0
    pkg = ''
    for r of rows
      row = rows[r]
      counter += 1
      if typeof row is 'object'
        rid = row._id ? row._source?._id ? await @uid()
        rid = rid.replace(/\//g, '_') if typeof rid is 'string'
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
        rs = await @index._send '/_bulk', {body:pkg, headers: {'Content-Type': 'application/x-ndjson'}}, undefined, prefix
        if this?.S?.dev and this?.S?.bg is true and rs?.errors
          errors = []
          for it in rs.items
            try
              if it[action].status not in [200, 201]
                errors.push it[action]
                errorcount += 1
            catch
              errorcount += 1
          try console.log errors
          try console.log (if errors.length is 0 then 'SOME' else errors.length), 'INDEX ERRORS BULK LOADING', rs.items.length
        pkg = ''
        counter = 0
    return rows.length - errorcount

#P.index._refresh = (route) -> return @index._send route.replace(/^\//, '').split('/')[0] + '/_refresh'



# query formats that can be accepted:
#  'A simple string to match on'
#  'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
#  '?q=query params directly as string'
#  {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
#  {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "must_not", "filter", "should" as well)
#  also works for: filter (restrict), must (and), must_not (not), should (or)
#  values can be (singular or lists of) strings, or objects with one key with a string value indicating a term query, or properly structured query parts
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
P.index.translate = (q, opts) ->
  q ?= this?.params if this?.route and this.route.startsWith 'index' # return undefined if q isnt a string or object that can become a valid query
  if typeof q is 'string'
    return undefined if q is '' or q.indexOf('\n') isnt -1 # this would likely be a bulk load string
  else
    return undefined if typeof q isnt 'object' or Array.isArray q
    for k in ['settings', 'aliases', 'mappings', 'index', '_id']
      return undefined if q[k]?
    qs = false
    if q.source
      try qs = JSON.parse decodeURIComponent q.source
    return undefined if JSON.stringify(q) isnt '{}' and not q.q? and not q.query? and qs is false and not q.must? and not q.should? and not q.must_not? and not q.filter? and not q.aggs? and not q.aggregations?

  try q = @copy(q) if typeof q is 'object' # copy objects so don't interfere with what was passed in
  try opts = @copy(opts) if typeof opts is 'object'
  opts ?= {}
  opts = {fields: opts} if typeof opts is 'string' or Array.isArray opts
  opts = {random: true} if opts is 'random'
  opts = {size: opts} if typeof opts is 'number'
  opts = {newest: true} if opts is true
  opts = {newest: false} if opts is false
  if opts.newest?
    opts.sort = createdAt: if opts.newest then 'desc' else 'asc'
    delete opts.newest

  qry = opts?.query ? {}
  qry.query ?= {}
  qry.query.bool ?= must: [], filter: []

  if typeof q is 'string'
    sq = query_string: query: q
    if opts?.fields?
      sq.query_string.fields = if typeof opts.fields is 'string' then opts.fields.split(',') else opts.fields
      delete opts.fields
    qry.query.bool.filter.push sq
  else if typeof q is 'object'
    if q.query?
      qry = q # assume already a query
    else
      if q.source?
        if typeof q.source is 'string' and typeof qs is 'object'
          qry = qs
        else if typeof q.source is 'object'
          qry = q.source
      else if q.q?
        if typeof q.q is 'object'
          qry.query = q.q # if an object assume it's a correct one
        else
          q.q = decodeURIComponent q.q
          if q.prefix? and q.q.indexOf(':') isnt -1
            delete q.prefix
            pfx = {}
            qpts = q.q.split ':'
            pfx[qpts[0]] = qpts[1]
            qry.query.bool.must.push prefix: pfx # TODO check if prefix can still be used in ES7.x and if it can go in filter instead of must
          else if q.fields?
            qry.query.bool.filter.push query_string: query: q.q, fields: q.fields.split ','
            delete q.fields
          else
            qry.query.bool.filter.push query_string: query: q.q
      opts[o] ?= q[o] for o of q

  # simple convenience catch for old-style queries - NOT complete, only works if they were basic filtered bool queries perhaps with directly translatable facets
  if qry.query?.filtered?.query?.bool?
    qry.query.bool = qry.query.filtered.query.bool
    qry.query.bool.filter = qry.query.filtered.filter
    delete qry.query.filtered
  if qry.facets?
    qry.aggregations = JSON.parse JSON.stringify(qry.facets).replace(/\.exact/g, '.keyword')
    delete qry.facets

  if qry.query? and not qry.query.bool? and JSON.stringify qry.query isnt '{}'
    qry.query = bool: must: [], filter: [qry.query]
  qry.query ?= bool: must: [], filter: []
  qry.query.bool ?= must: [], filter: []
  qry.query.bool.filter ?= []

  if typeof opts.sort is 'string'
    sorts = [] # https://www.elastic.co/guide/en/elasticsearch/reference/7.x/sort-search-results.html
    for so in opts.sort.split ','
      [k, o] = so.split ':'
      if not o
        sorts.push k.trim()
      else
        sorts.push {}
        sorts[sorts.length-1][k.trim()] = o.trim()
    opts.sort = sorts

  if opts.random
    fq = {function_score: {random_score: {}}}
    fq.function_score.random_score.seed = seed if opts.seed?
    fq.function_score.query = qry.query
    qry.query = fq # TODO check how function_score and random seed work now in ES7.x
    delete opts.random
    delete opts.seed
  if inc = opts._include ? opts.include ? opts._includes ? opts.includes
    qry._source ?= {}
    qry._source.includes = if typeof inc is 'string' then inc.replace(/,\s/g, ',').split(',') else inc
  if exc = opts._exclude ? opts.exclude ? opts._excludes ? opts.excludes
    qry._source ?= {}
    qry._source.excludes = if typeof exc is 'string' then exc.replace(/,\s/g, ',').split(',') else exc
    for i in qry._source?.includes ? []
      qry._source.excludes = qry._source.excludes.filter (v) -> return v isnt i 

  for tp in ['filter', 'restrict', 'must', 'and', 'must_not', 'not', 'should', 'or']
    if opts[tp]?
      ls = if Array.isArray(opts[tp]) then opts[tp] else [opts[tp]]
      delete opts[tp]
      etp = if tp in ['filter', 'restrict', 'must', 'and'] then 'filter' else if tp in ['must_not', 'not'] then 'must_not' else 'should'
      qry.query.bool[etp] ?= []
      for rs in ls
        if typeof rs is 'object'
          rkeys = @keys rs
          rs = {term: rs} if rkeys.length is 1 and typeof rs[rkeys[0]] isnt 'object'
        else
          rs = {query_string: {query: rs}}
        qry.query.bool[etp].push rs

  if opts.terms?
    try opts.terms = opts.terms.replace(/,\s/g, ',').split(',')
    qry.aggregations ?= {}
    for tm in opts.terms
      qry.aggregations[tm] = { terms: { field: tm + (if tm.endsWith('.keyword') then '' else '.keyword'), size: 1000 } }
    delete opts.terms
  for af in ['aggs','aggregations']
    if opts[af]?
      qry[af] ?= {}
      qry[af][f] = opts[af][f] for f of opts[af]
      delete opts[af]

  for k, v of opts
    #v = v.replace(/,\s/g, ',').split(',') if k in ['fields'] and typeof v is 'string' and v.indexOf(',') isnt -1
    if k in ['from', 'size'] and typeof v isnt 'number'
      try
        v = parseInt v
        v = undefined if isNaN v
    # some URL params that may be commonly used in this API along with valid ES URL query params will be removed here by default too
    # this makes it easy to handle them in routes whilst also just passing the whole params here and still get back a valid ES query
    qry[k] = v if v? and k not in ['apikey', '_', 'callback', 'refresh', 'key', 'counts', 'index', 'search', 'source', 'q'] and k.replace('_', '').replace('s', '') not in ['include', 'exclude']

  try
    # order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
    ords = count: {_count: 'desc'}, reverse_count: {_count: 'asc'}, term: {_key: 'asc'}, reverse_term: {_key: 'desc'} # convert for ES7.x
    for ag of qry.aggregations
      if typeof qry.aggregations[ag].terms?.order is 'string' and ords[qry.aggregations[ag].terms.order]?
        qry.aggregations[ag].terms.order = ords[qry.aggregations[ag].terms.order]
     
  # no filter query or no main query can cause issues on some queries especially if certain aggs/terms are present, so insert some default searches if necessary
  #qry.query = { match_all: {} } if typeof qry is 'object' and qry.query? and JSON.stringify(qry.query) is '{}'
  # clean slashes out of query strings
  if qry.query?.bool?
    for bm of qry.query.bool
      for b of qry.query.bool[bm]
        if typeof qry.query.bool[bm][b].query_string?.query is 'string' and qry.query.bool[bm][b].query_string.query.indexOf('/') isnt -1 and qry.query.bool[bm][b].query_string.query.indexOf('"') is -1
          qry.query.bool[bm][b].query_string.query = '"' + qry.query.bool[bm][b].query_string.query + '"'
  delete qry._source if qry._source? and qry.fields?
  #console.log JSON.stringify qry
  return qry

P.index.translate._auth = false

# calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
# call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
P.index._send = (route, data, method, prefix) ->
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
      prefix ?= await @dot P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'
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

  provided_scroll_id = false
  if route.includes('/_search') and typeof data is 'object' and (data.scroll_id? or data.scroll)
    data.scroll = '2m' if data.scroll is true
    data.scroll += 'm' if typeof data.scroll is 'number' or (typeof data.scroll is 'string' and not data.scroll.endsWith 'm')
    route += (if route.indexOf('?') is -1 then '?' else '&') + 'scroll=' + (data.scroll ? '2m')
    if data.scroll_id
      provided_scroll_id = data.scroll_id
      route = route.split('://')[0] + '://' + route.split('://')[1].split('/')[0] + '/_search/scroll' + (if route.includes('?') then '?' + route.split('?')[1] else '')
      route += (if route.indexOf('?') is -1 then '?' else '&') + 'scroll_id=' + data.scroll_id
      data = undefined
    else
      delete data.scroll_id
      delete data.scroll

  route = route += rqp
  opts = if route.indexOf('/_bulk') isnt -1 or (typeof data is 'object' and typeof data.headers is 'object') then data else body: data # fetch requires data to be body
  if route.indexOf('/_search') isnt -1 and method in ['GET', 'POST'] # scrolling isn't a new search so ignore a scroll DELETE otherwise adding the param would error
    # avoid hits.total coming back as object in new ES, because it also becomes vague
    # see hits.total https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-7.0.html
    route += (if route.indexOf('?') is -1 then '?' else '&') + 'rest_total_hits_as_int=true'

  #if @S.dev and @S.bg is true and not data?.query? and not route.includes('/_doc/') and (method is 'DELETE' or not route.includes '_search/scroll')
  #  console.log 'INDEX', method, route
    #console.log method(JSON.stringify(if Array.isArray(data) and data.length then data[0] else data).substr(0, 3000)) if data

  #opts.retry = 3
  opts.method = method
  res = await @fetch route, opts
  #if @S.dev and @S.bg is true
  #  try console.log 'INDEX QUERY FOUND', res.hits.total, res.hits.hits.length
  if not res? or (typeof res is 'object' and typeof res.status is 'number' and res.status >= 400 and res.status <= 600)
    # fetch returns undefined for 404, otherwise any other error from 400 is returned like status: 400
    # write a log / send an alert?
    #em = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', method: method, url: url, route: route, opts: opts, error: err.toString()
    #if this?.log? then @log(em) else P.log em
    # do anything for 409 (version mismatch?)
    return undefined
  else
    try res.q = data if @S.dev and data?.query?
    res._scroll_id = res._scroll_id.replace(/==$/, '') if res?._scroll_id
    await @index._send('/_search/scroll?scroll_id=' + provided_scroll_id, '') if provided_scroll_id and provided_scroll_id isnt res?._scroll_id
    return res
