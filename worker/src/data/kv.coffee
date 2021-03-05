
# https://developers.cloudflare.com/workers/runtime-apis/kv
# Keys are always returned in lexicographically sorted order according to their UTF-8 bytes.
# NOTE these need to be awaited when necessary, as the val will be a Promise

# should it be possible to call kv context from background at all?
# if ONLY on background with no worker, something needs to be able to write to kv, or a stand-in of kv

# if no kv, use an ES index if available as a simple kv store
# later can also write in a redis fallback here#

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
      else if @body?
        val = @body
      else if @params.val
        val = @params.val
      else
        val = @params
        delete val[k] for k in ['key', 'kv', 'refresh', 'apikey']
        delete val[k] for k in @parts
      val = JSON.parse(val) if typeof val is 'string' and (val.indexOf('[') is 0 or val.indexOf('{') is 0)
      val = undefined if JSON.stringify(val) in ['{}', '[]']
  val = '' if typeof val is 'object' and JSON.stringify(val) in ['{}', '[]']
  if typeof key is 'object' and not val?
    val = key
    key = val._id ? await @uid()
  if key? and @S.kv and global[@S.kv]?
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
      try value = JSON.parse value
      try metadata = JSON.parse metadata
      if val is ''
        @waitUntil global[@S.kv].delete key # remove a key after retrieval
      return if metadata is true then {value: value, metadata: metadata} else value
  else
    return undefined

# NOTE that count on kv is expensive because it requires listing everything
P.kv.count = (prefix) ->
  counter = 0
  if @S.kv and global[@S.kv]?
    prefix ?= @params.kv ? @params.prefix
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
          rs = await @kv k.name
          rs.id ?= k.name if rs?
          res.push rs
      complete = if size and counter is size then true else ls.list_complete
  return res


