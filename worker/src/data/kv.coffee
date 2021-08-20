
# https://developers.cloudflare.com/workers/runtime-apis/kv
# Keys are always returned in lexicographically sorted order according to their UTF-8 bytes.
# NOTE these need to be awaited when necessary, as the val will be a Promise

# this is here instead of server because it can be useful to deploy a worker to cloudflare
# that does NOT use a KV on the same account it is deployed to, instead it connects 
# via another instance of Paradigm running on another account to a KV on that secondary account.
# e.g. multiple worker instances on multiple accounts sharing one resume token KV collection.
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
  global[S.kv].list = (opts) ->
    opts ?= {}
    return P.fetch S.kv + '/list' + (if opts.prefix then '/' + opts.prefix else '') + (if opts.cursor then '?cursor=' + opts.cursor else '')

'''if typeof S.kv isnt 'string' and S.kv isnt false
  global[S.kv] = {}
  global[S.kv].get = (key) ->
    kc = 'kv/' + key.replace /\//g, '_'
    ret = await P.index kc
    if ret.expiresAt and ret.expiresAt < Date.now()
      P.index kc, '' # delete
      return
    else
      try ret.val = JSON.parse ret.val
      return ret.val
  global[S.kv].getWithMetadata = (key) ->
    kc = 'kv/' + key.replace /\//g, '_'
    ret = await P.index kc
    try ret.val = JSON.parse ret.val
    try ret.metadata = JSON.parse ret.metadata
    return value: ret.val, metadata: ret.metadata
  global[S.kv].put = (key, data) ->
    kc = 'kv/' + key.replace /\//g, '_'
    return await P.index kc, key: key, val: JSON.stringify data
  global[S.kv].delete = (key) ->
    kc = 'kv/' + key.replace /\//g, '_'
    return await P.index kc, ''
  global[S.kv].list = (opts) ->
    # cursor on real kv isnt a from count, but use that for now
    # need to change this to use each properly on index, as from will only go as far as 10k
    opts ?= {}
    opts.cursor ?= 0
    ret = await P.index 'kv', (if opts.prefix then 'key:' + opts.prefix.replace(/\//g, '_') + '*' else '*'), {sort: {key: {order: 'asc'}}, from: opts.cursor}
    res = keys: []
    try
      res.cursor: opts.cursor + 1000
      if res.cursor >= ret.hits.total
        res.list_complete = true
        delete res.cursor
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
      if @request.method is 'DELETE' #or @params._delete
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
      @waitUntil global[@S.kv].put key, (if typeof val is 'object' then JSON.stringify(val) else val), m
      return val
    else
      {value, metadata} = await global[@S.kv].getWithMetadata key, type
      if value?
        try value = JSON.parse value
        try metadata = JSON.parse metadata
        if val is ''
          @waitUntil global[@S.kv].delete key # remove a key after retrieval
        return if metadata is true then {value: value, metadata: metadata} else value
  return

P.kv._auths = 'system'
P.kv._hides = true
P.kv._caches = false

P.kv.list = (prefix, cursor) ->
  try prefix ?= @params.kv ? @params.prefix ? @params.list
  try cursor ?= @params.cursor
  return await global[@S.kv].list prefix: prefix, cursor: cursor

# NOTE that count on kv is expensive because it requires listing everything
# so these count/prefixes/clear actions are really only for dev convenience
# not good for production scale
P.kv.count = (prefix) ->
  counter = 0
  if @S.kv and global[@S.kv]?
    prefix ?= @params.kv ? @params.prefix ? @params.count
    complete = false
    cursor = undefined
    while not complete
      ls = await global[@S.kv].list prefix: prefix, cursor: cursor
      cursor = ls.cursor
      for k in ls.keys
        counter += 1
      complete = ls.list_complete
  return counter

P.kv.prefixes = () ->
  prefixes = {}
  await @kv._each undefined, (k) ->
    kp = k.split('/')[0]
    prefixes[kp] ?= 0
    prefixes[kp] += 1
  return prefixes

P.kv.clear = (prefix) ->
  if @S.dev
    prefix ?= @params.clear ? @params.kv
    @waitUntil @kv._each prefix, (k) ->
      @waitUntil global[@S.kv].delete k
    return true

# NOTE there is no bulk delete option on the bound kv. It can be done via the API 
# but requires the API tokens which aren't shared in the deployed code. Could be 
# done manually via a script on bg. Or have bg iterate calls to frontend until it 
# can no longer count any existing.
# A LOOPING CLEAR AS ABOVE GETS RID OF ABOUT 200 KV ENTRIES BEFORE IT TIMES OUT

P.kv.delete = (prefix) ->
  if typeof @S.kv is 'string' and @S.kv.startsWith 'http' # which it should if kv is available from bg
    prefix ?= @params.kv ? @params.delete ? @params.prefix
    count = await @fetch @S.kv + '/count' + (if prefix then '/' + prefix else '')
    res = count
    while count and count isnt '0'
      console.log(prefix, count) if @S.dev
      await @fetch @S.kv + '/clear' + (if prefix then '/' + prefix else '')
      await @sleep 500
      count = await @fetch @S.kv + '/count' + (if prefix then '/' + prefix else '')
    return res
P.kv.delete._bg = true

P.kv._each = (prefix, fn) ->
  counter = 0
  if @S.kv and global[@S.kv]?
    if typeof prefix is 'function' and not fn?
      fn = prefix
      prefix = undefined
    complete = false
    cursor = undefined
    while not complete
      ls = await global[@S.kv].list prefix: prefix, cursor: cursor
      cursor = ls.cursor
      for k in ls.keys
        counter += 1
        if typeof fn is 'function'
          @waitUntil fn.call @, k.name
        else if fn is ''
          @waitUntil global[@S.kv].delete k.name
        else if fn?
          @waitUntil @kv k.name, fn
      complete = ls.list_complete


