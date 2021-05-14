
# https://developers.cloudflare.com/workers/runtime-apis/kv
# Keys are always returned in lexicographically sorted order according to their UTF-8 bytes.
# NOTE these need to be awaited when necessary, as the val will be a Promise

# this could move to server, if never going to be used from worker - would want to run a worker connecting to a somehow remote kv?
if typeof S.kv is 'string' and S.kv.startsWith('http') and not global[S.kv]
  # kv is a URL back to the worker to access cloudflare kv
  global[S.kv] = {}
  global[S.kv].get = (key) ->
    return P.fetch S.kv + '/' + key
  global[S.kv].getWithMetadata = (key) ->
    ret = await P.fetch S.kv + '/' + key
    return value: ret, metadata: {} # can't get the metadata remotely
  global[S.kv].put = (key, data) ->
    return P.fetch S.kv + '/' + key, body: data
  global[S.kv].delete = (key) ->
    return P.fetch S.kv + '/' + key, method: 'DELETE'
  global[S.kv].list = (prefix, cursor) ->
    return P.fetch S.kv + '/list' + (if prefix then '/' + prefix else '') + (if cursor then '?cursor=' + cursor else '')

'''if typeof S.kv isnt 'string' and S.kv isnt false
  global[S.kv] = {}
  global[S.kv].get = (key) ->
    ret = await P.index 'kv/' + key.replace /\//g, '_'
    try ret.val = JSON.parse ret.val
    return ret.val
  global[S.kv].getWithMetadata = (key) ->
    ret = await P.index 'kv/' + key.replace /\//g, '_'
    try ret.val = JSON.parse ret.val
    return value: ret.val, metadata: {} # can't get the metadata remotely
  global[S.kv].put = (key, data) ->
    return await P.index 'kv/' + key.replace(/\//g, '_'), key: key, val: JSON.stringify data
  global[S.kv].delete = (key) ->
    return await P.index 'kv/' + key.replace(/\//g, '_'), ''
  global[S.kv].list = (prefix, cursor) ->
    # cursor on real kv isnt a from count, but use that for now
    # need to change this to use each properly on index, as from will only go as far as 10k
    ret = await P.index 'kv/', (if prefix then 'key:' + prefix + '*' else '*'), {sort: {key: {order: 'asc'}}, from: cursor}
    res = keys: []
    try
      res.cursor: (cursor ? 0) + 1000
      res.list_complete = true if res.cursor >= ret.hits.total
      for k in ret.hits.hits
        res.keys.push k._source.key
    return res'''


P.kv = (key, val, ttle, metadata, type) ->
  # val can be string, stream, buffer. The type gets inferred.
  # ONE of expire or ttl can optionally be provided, expiration is seconds since epoch timestamp, ttl is seconds from now until expiry
  # so ttle can be either. If ttle*1000 is greater than Date.now it will be used as expiration timestamp in seconds, otherwise will be used as ttl in seconds
  # ttle can also be true, or an object, to cause a merge of val if val is also an object (true entails retrieving it from storage then merging)
  # metadata and type are not necessary, but included here for completeness
  # metadata can be any JSON object under 1024 bytes
  # type is optional, can be "text", "json", "arrayBuffer" or "stream", and that what the val will be provided as.
  if not key?
    key = @params.kv ? @params.key ? @parts.join '_'
    if not val?
      if @request.method is 'DELETE' or @params._delete # TODO this is for easy dev, take out or auth restrict later
        val = ''
      else if @body
        val = @body
      else if @params.val
        val = @params.val
      else
        val = @params
        delete val[k] for k in ['key', 'kv', 'refresh', 'apikey']
        delete val[k] for k in @parts
      val = JSON.parse(val) if typeof val is 'string' and (val.indexOf('[') is 0 or val.indexOf('{') is 0)
      val = undefined if JSON.stringify(val) in ['{}', '[]']
  val = undefined if typeof val is 'object' and JSON.stringify(val) in ['{}', '[]']
  if typeof key is 'object' and not val?
    val = key
    key = val._id ? await @uid()
  if key? and @S.kv and global[@S.kv] # startup checks this and removes @S.kv if there is no matching global, but check again anyway, in case it is set by a running function #(@S.kv.indexOf('http') is 0 or global[@S.kv]?)
    if val? and val isnt ''
      m = metadata: metadata
      if typeof ttle is 'number'
        if (ttle*1000) > Date.now()
          m.expiration = ttle
        else
          m.expirationTtl = ttle
      if typeof val is 'object' # val needs to be string, arrayBuffer, or readableStream
        if ttle is true
          ttle = await @kv key # get the current state of the record
        if typeof ttle is 'object' # this is an update to be merged in
          val[k] ?= ttle[k] for k of ttle # handle dot notations?
      #if @S.kv.indexOf('http') is 0 # has to be a URL route back to the worker
      #  @fetch @S.kv + '/' + key, body: val # send m as well?
      #else
      @waitUntil global[@S.kv].put key, (if typeof val is 'object' then JSON.stringify(val) else val), m
      return val
    else
      #if @S.kv.indexOf('http') is 0
      #  return await @fetch @S.kv + '/' + key # any way or need to get metadata here too?
      #else
      {value, metadata} = await global[@S.kv].getWithMetadata key, type
      if value?
        try value = JSON.parse value
        try metadata = JSON.parse metadata
        if val is ''
          @waitUntil global[@S.kv].delete key # remove a key after retrieval
        return if metadata is true then {value: value, metadata: metadata} else value
      else
        return undefined
  else
    return undefined

P.kv.list = (prefix, cursor) ->
  try prefix ?= @params.kv ? @params.prefix ? @params.list
  try cursor ?= @params.cursor
  return await global[@S.kv].list prefix: prefix, cursor: cursor

# NOTE that count on kv is expensive because it requires listing everything
P.kv.count = (prefix) ->
  counter = 0
  if @S.kv and global[@S.kv]?
    prefix ?= @params.kv ? @params.prefix ? @params.count
    complete = false
    while not complete
      ls = await global[@S.kv].list prefix: prefix, cursor: cursor
      cursor = ls.cursor
      for k in ls.keys
        counter += 1
      complete = ls.list_complete
  return counter

P.kv._each = (prefix, fn, size) ->
  res = []
  if @S.kv and global[@S.kv]?
    complete = false
    counter = 0
    while not complete
      ls = await global[@S.kv].list prefix: prefix, cursor: cursor
      cursor = ls.cursor
      for k in ls.keys
        counter += 1
        if fn is ''
          @waitUntil @kv k.name, ''
        else if typeof fn is 'function'
          res.push await fn.call @, k.name
        else if fn?
          @waitUntil @kv k.name, fn
        else
          if rs = await @kv k.name
            rs._id ?= k.name # worthwhile?
            res.push rs
      complete = if size and counter is size then true else ls.list_complete
  return res


