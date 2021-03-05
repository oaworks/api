
# limit, cron/job/batch (note workers now has a schedule ability too. explore that but consider vendor lock-in)

# _auth - if true an authorised user is required. If a string or a list, an authorised user with that role is required. always try to find user even if auth is not required, so that user is optionally available
# _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache) (note below, if cache is required for test, should everything just always be cached but then just not checked if _cache is false?
# _kv - if true store the result in CF workers KV, and check for it on new requests - like a cache, but global, with 1s eventual consistency whereas cache is regional
# _index - if true send the result to an index. Or can be an object of index initialisation settings, mappings, aliases
# _key - optional which key, if not default _id, to use from a function result object to save it as - along with the function route which will be derived if not provided
# _sheet - if true get a sheet ID from settings for the given endpoint, if string then it is the sheet ID. If present it implies _index:true if _index is not set

# _.async (start the function but don't wait for it to finish, get an ID to query its result later?)
# _.retry (a number of times to retry, or a retry settings obj see below)
# _.history (if true save a copy of every change and the request that changed somewhere. Or enough just to save the requests and replay them?)


try S = JSON.parse SECRETS_SETTINGS # from CF variable this will need parsed, so just default to passing them as strings and parsing them
S ?= {} # and just in case it wasn't found
S.name ?= 'N2'
S.version ?= '5.2.1'
S.env ?= 'dev'
S.dev ?= S.env is 'dev'
S.bg ?= 'https://dev.api.cottagelabs.com/log/remote'
# TODO replace bg with a proper bg endpoint for workers to send to (or fail open)
# once bg goes into permanent settings, the background server starter shouod remove it and replace it with true or nothing
S.headers ?= {}
#  'Access-Control-Allow-Methods': 'HEAD, GET, PUT, POST, DELETE, OPTIONS'
#  'Access-Control-Allow-Origin': '*'
#  'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control'
S.svc ?= {}
S.src ?= {}

try
  addEventListener 'fetch', (event) ->
    #event.passThroughOnException() # let exceptions happen and pass request through to the origin
    event.respondWith P.call event

'''try
  addEventListener 'scheduled', (event) ->
    https://developers.cloudflare.com/workers/runtime-apis/scheduled-event
    TODO need to configure this to run when the schedule calls. What to run on schedule?
    event.type will always be 'scheduled'
    event.scheduledTime ms timestamp of the scheduled time. Can be parsed with new Date(event.scheduledTime)
    event.waitUntil should be passed a promise. The first to fail will be recorded as fail on Cron past events UI. Otherwise will record as success
    event.waitUntil P.call event'''


P = () ->
  @started = Date.now() # not strictly accurate in a workers environment, but handy nevertheless
  try console.log(S.version) if S.dev # handy for CF edit UI debug to see if code has updated yet
  # this header is defined later because the built date is added to the end of the file by the deploy script, so it's not known until now
  try S.headers['X-' + S.name] ?= (if S.version then 'v' + S.version else '') + (if S.env then ' ' + S.env else '') + (if S.built then ' built ' + S.built  else '')
  @S = JSON.parse JSON.stringify S
  @params = {}
  # note may need to remove apikey param - but if removing, how does that affect the fact that request is an actual immutable Request object?
  # it probably would appear to change, but may still be in there, then may get saved in cache etc which prob isn't wanted
  # unless results SHOULD differ by apikey? Probably on any route where that is the case, caching should be disabled
  if @request.url? and @request.url.indexOf('?') isnt -1
    for qp in @request.url.split('?')[1].split('&')
      kp = qp.split '='
      @params[kp[0]] = if kp.length is 1 then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'true' then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'false' then false else if qp.endsWith('=') then true else kp[1]
      if typeof @params[kp[0]] is 'string' and @params[kp[0]].replace(/[0-9]/g,'').length is 0 and not @params[kp[0]].startsWith('0')
        kpn = parseInt @params[kp[0]]
        @params[kp[0]] = kpn if not isNaN kpn
      if typeof @params[kp[0]] is 'string' and (@params[kp[0]].startsWith('[') or @params[kp[0]].startsWith('{'))
        try @params[kp[0]] = JSON.parse @params[kp[0]]
  if @request.bodyUsed
    try
      @body = JSON.parse(@request.body) if @request.body.startsWith('{') or @request.body.startsWith('[')
      if typeof @body is 'object' and not Array.isArray @body
        @params[qp] ?= @body[qp] for qp of @body
    try @body ?= @request.body
  if @params.refresh
    @refresh = @params.refresh
    delete @params.refresh
  try @rid = @request.headers.get('cf-ray').slice(0, -4)
  # how / when to remove various auth headers before logging / matching cache?
  # e.g apikey, id, resume, token, access_token, email?
  try @id = @request.headers.get('x-id') ? @request.headers.get('id') ? @request.headers.get('_id') ? @params._id ? @params.id
  try @apikey = @request.headers.get('x-apikey') ? @request.headers.get('apikey') ? @params.apikey ? @params.apiKey
  delete @params.apikey if @params.apikey
  try @cookie = @request.headers.get 'cookie'
  @headers = {}
  @headers[hd[0]] = hd[1] for hd in [...@request.headers] # request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
  @url = @request.url.split('?')[0].replace(/\/$/,'').split('://')[1]
  @parts = @url.split '/'
  @base = @parts.shift()
  @route = @parts.join '/'
  @_logs = [] # place for a running request to dump multiple logs, which will combine and save at the end of the overall request

  if @route is ''
    return P._response.call @, if @request.method in ['HEAD', 'OPTIONS'] then '' else name: @S.name, version: @S.version, env: @S.env, built: (if @S.dev then @S.built else undefined)

  @routes = {}
  @fn = ''
  
  _save = (k, r, f) =>
    if f._kv #_kv should be set for things that MUST be in the kv - they won't be removed, but will be copied to index if _index is also true
      @kv k, r, (if typeof f._kv is 'number' then f._kv else undefined)
    if f._index and (f._kv is false or @S.kv is false or @S.index.immediate is true)  # all indexing is bulked through kv unless _kv is false or overall kv is disabled in settings, or immediate indexing is true
      if not indexed = await @index k, r # later, the _schedule should automatically move anything in kv that matches an indexed endpoint
        # try creating it - if already done it just returns a 404 anyway
        if not indexed = await @index r.split('/')[0], (if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases})
          @log fn: r.split('/')[0].replace(/\_/g, '.'), msg: 'Could not save/create index', level: 'error'
        else
          @index k, r

  _return = (fn, n) =>
    fn._index ?= true if fn._sheet
    if not fn._index and not fn._kv and typeof fn is 'object' and not Array.isArray(fn) and typeof fn[@request.method] isnt 'function'
      return JSON.parse JSON.stringify fn
    else if not fn._index and not fn._kv and typeof fn isnt 'function'
      return fn
    else if not fn._index and not fn._kv and n.indexOf('.') is -1 or n.split('.').pop().indexOf('_') is 0 # don't wrap top-level or underscored methods
      return fn.bind @
    else
      _wrapped = () ->
        st = Date.now() # again, not necessarily going to be accurate in a workers environment
        rt = n.replace /\./g, '_'
        chd = false
        if fn._index and ((@fn is n and @index._q @params) or (@fn isnt n and (arguments.length is 1 and @index._q(arguments[0]))) or (arguments.length is 2 and @index._q(arguments[1])))
          res = @index (if arguments.length is 2 then (arguments[0] ? rt) else rt), (if arguments.length is 2 then arguments[1] else if arguments.length is 1 then arguments[1] else @params)
        # TODO what about a kv direct read or write? should that be handled here too?
        if not res? and not @refresh and (@request.method in ['GET'] or @fn isnt n) and (@fn is n or arguments.length is 1) and (fn._kv or fn._index)
          # look for a pre-made answer if only a key was passed in, or if on the main fn with no data incoming
          # NOTE cache is regional, kv is global but 1s eventually consistent (although KV lookup from same region is immediately consistent)
          # NOTE also cache is not handled in this wrapper, it's handled before or directly in fetch calls - cache here means an already computed result available in index or kv
          # if cache, kv, or index is not configured, they'll all return undefined anyway so this will not block
          if fn._kv
            res = await @kv if arguments.length then rt + '/' + arguments[0].replace(/\//g, '_').replace(rt + '_', '') else undefined
            chd = 'kv' if res? # record if responding with cached result to whichever fn is currently running
          if fn._index and not res?
            res = await @index if arguments.length then rt + '/' + arguments[0].replace(/\//g, '_').replace(rt + '_', '') else undefined
            chd = 'index' if res?
        @cached = chd if chd and @fn.startsWith n # record whether or not the main function result was cached in index or kv
        key = false
        if not res?
          # if it's an index function with a sheet setting, or a sheet param has been provided, what to do by default?
          if typeof fn is 'function' # it could also be an index or kv config object with no default function
            res = await (fn[@request.method] ? fn).apply @, arguments
          if res?
            if fn._kv or fn._index
              try
                key = res[fn._key] ? res._id
                key = if Array.isArray(key) then key[0] else if typeof key isnt 'string' then undefined else key
                key = key.replace(/\//g, '_').replace rt + '_', rt + '/' # anything else to reasonably strip?
                key = rt + '/' + key if key.indexOf(rt) isnt 0
              key = rt + '/' + @uid() if key is false
              key = key.toLowerCase() # uid gen and index enforce this anyway, but to keep neat for logs, do here too
              @waitUntil _save key, res, @copy fn
          else if not arguments.length or arguments[0] is rt
            if fn._index
              res = await @index ...arguments # just return a search endpoint - TODO may restrict this to a count depending on auth
            else if fn._kv
              res = '' # return blank to indicate kv is present, because kv listing or counting is an expensive operation
        #if n isnt @fn # main fn will log at the end - or should each part log as well anyway?
        lg = fn: n, cached: (if chd then chd else undefined), key: (if key then key else if chd and arguments.length then arguments[0].toLowerCase() else undefined)
        #try lg.result = if key then undefined else if chd then (if arguments.length then arguments[0] else undefined) else undefined
        #JSON.stringify res # is it worth storing the whole result here? only if history? or always?
        # if fn._diff, need to decide when or how often to do a diff check and alert
        if fn._index or fn._kv
          try lg.args = JSON.stringify([...arguments]) if arguments.length
          try lg.result = res?
        try lg.took = Date.now() - st
        #try lg.args = JSON.stringify [...arguments]
        @log lg
        return res
      return _wrapped.bind @

  # TODO decide if it's worth also having named params in object names such as _name_
  # TODO add a way to iterate mutliple functions either parallel or serial, adding to results
  # e.g. split url at // for multi functions. Params parallel gives on obj of named results
  # with merge for one result overwriting as they're received, or if only merge then merge in order
  # auth would need to be present for every stage
  fn = undefined
  prs = [...@parts]
  pk = undefined
  _lp = (p, a, n) =>
    wk = false
    if (n is '' or (pk and ('.'+n).endsWith('.' + pk+'.'))) and prs.length
      if typeof p[prs[0]] in ['function', 'object']
        @fn += (if @fn is '' then '' else '.') + prs[0]
        pk = prs.shift()
        wk = pk
      else if pk
        @params[pk] = if @params[pk] then @params[pk] + '/' + prs[0] else prs[0]
        prs.shift()
    for k of p
      a[k] = _return p[k], n + k
      if typeof a[k] in ['function', 'object']
        if typeof a[k] is 'function'
          if not k.startsWith '_'
            fn = a[k] if k is wk and n.indexOf('._') is -1 # URL routes can't call _abc functions or ones under them
            @routes[(n + k)] = '' # TODO this should read from the auth method, and also search top of function for description comment?
        _lp(p[k], a[k], n + k + '.') if not Array.isArray(p[k]) and (not k.startsWith('_') or typeof p[k] is 'function')
  _lp P, @, ''
  if pk and prs.length # catch any remaining url params beyond the max depth of P
    @params[pk] = if @params[pk] then @params[pk] + '/' + prs.join('/') else prs.join('/')

  # if no function found, fall back to server? - fail open setting may be good enough
  # check the blacklist
  res = undefined
  if typeof fn is 'function'
    authd = @auth() # check auth even if no function?
    @user = authd if typeof authd is 'object' and authd._id and authd.email
    if typeof fn._auth is 'function'
      authd = await fn._auth()
    else if fn._auth is true and @user? # just need a logged in user if true
      authd = true
    else if fn._auth? # which should be a string...
      authd = await @auth.role fn._auth # _auth should be true or name of required group.role
    else
      authd = true
    if authd # auth needs to be checked whether the item is cached or not.
      # OR cache could use auth creds as part of the key?
      # but then what about where the result can be the same but served to different people? very likely, so better to auth first every time anyway
      if @request.method in ['HEAD', 'OPTIONS']
        res = ''
      else if fn._cache isnt false and not @refresh and @request.method in ['GET'] and res = await @_cache() # this will return empty if nothing relevant was ever put in there anyway
        # how about POSTs that are obviously queries? how about caching of responses to logged in users, by param or header?
        @cached = 'cache'
        resp = new Response res.body, res
        resp.headers.append 'x-' + @S.name + '-cached', 'cache' # this would leave any prior "index" value, for example. Or use .set to overwrite
        resp.headers.delete 'x-' + @S.name + '-took'
        @log()
        return resp
      else
        # if function set to bg, just pass through? if function times out, pass through? or fail?
        # or only put bg functions in bg code and pass through any routes to unknown functions?
        # but remember bg should be able to run everything if necessary
        _racer = () =>
          res = await fn()
          @completed = true
        await Promise.race [_racer(), @sleep(14500)] # race against time. CF worker will abort after 15s anyway so this has to be lower than that
        # on timeout could call bg server, but may be better to have notifications, and processes that time out should just be moved to bg code anyway
        if not @completed
          res = status: 408
    else
      # Random delay for https://en.wikipedia.org/wiki/Timing_attack https://www.owasp.org/index.php/Blocking_Brute_Force_Attacks#Finding_Other_Countermeasures
      await @sleep 200 * (1 + Math.random())
      res = status: 401

  res ?= '' if @url.replace('.ico','').replace('.gif','').replace('.png','').endsWith '/favicon'
  resp = await @_response res
  if @parts.length and @parts[0] not in ['log','status'] and @request.method not in ['HEAD', 'OPTIONS'] and res? and res isnt ''
    if fn? and fn._cache isnt false and @completed and resp.status is 200
      @_cache undefined, resp.clone(), fn._cache # need to clone here? or is at cache enough? Has to be cached before being read and returned
    @log() # logging from the top level here should save the log to kv - don't log if unlog is present and its value matches a secret key?
  return resp

P._response = (res) ->
  @S.headers ?= {}
  if not res?
    res = 404
    status = 404
  else if typeof res is 'object' and not Array.isArray(res) and ((typeof res.status is 'number' and res.status > 300 and res.status < 600) or res.headers)
    if res.headers?
      @S.headers[h] = res.headers[h] for h of res.headers
      delete res.headers
    status = res.status ? 200
    delete res.status
    keys = @keys res
    if keys.length is 0
      res = status
    else if keys.length is 1 # if only one thing left, set the res to that. e.g. most likely body, content, json
      res = res[keys[0]]
  else
    status = 200
  
  if not @S.headers['Content-Type']?
    try res = JSON.stringify res, '', 2
    @S.headers['Content-Type'] = 'application/json; charset=UTF-8'
  try @S.headers['Content-Length'] ?= Buffer.byteLength res
  try @S.headers['x-' + @S.name + '-took'] = Date.now() - @started
  try @S.headers['x-' + @S.name + '-cached'] = @cached if @cached
  # TODO add formatting if the URL ended with .csv or something like that (or header requested particular format)
  return new Response res, {status: status, headers: @S.headers}

P.src = {}
P.svc = {}

