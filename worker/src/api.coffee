
# global S and P are accessible anywhere, and all files are merged into one on build.
# NOTE it IS possible for scripts to persist between cloudflare worker requests, but also not guaranteed or intentional
# so can't rely on them being clean every time, nor rely on them for storing state. Hence every new fetch event builds its own @S and P onto the global

try
  # from CF variable this will need parsed, so just default to passing them as strings and parsing them
  S = JSON.parse SECRETS_SETTINGS
try
  SS = JSON.parse SECRETS_SERVER # backend server can provide overrides in a server.json secrets file
  S[k] = SS[k] for k of SS
S ?= {} # and just in case it wasn't found
S.name ?= 'OA.Works' # this would also be used as the default name for the KV store, if one was not set specifically, as below or in settings
S.kv ?= 'oaworks'
S.version ?= '6.1.0' # the construct script will use this to overwrite any version in the worker and server package.json files
# S.pass can be set to false if there is a bg URL but worker errors should NOT pass through on exception to it (otherwise they will by default)
S.pass = ['docs', 'client', '.well-known'] # if this is a list of strings, any route starting with these will throw error and pass back to bg (this would happen anyway with no function defined for them, but this avoids unnecessary processing)
S.dev ?= true
try S.async = true if process.env.name and process.env.name.endsWith '_async' # optional setting defining a URL to an async worker to pass requests to
try S.async_loop = true if process.env.name and process.env.name.endsWith '_loop' # additional setting defining a URL to pass async looped scheduled requests to
try S.async_schedule = true if process.env.name and process.env.name.endsWith '_schedule' # additional setting defining a URL to pass async scheduled requests to (including looped ones, if async_loop is not set)
S.headers ?=
  'Access-Control-Allow-Methods': 'HEAD, GET, PUT, POST, DELETE, OPTIONS'
  'Access-Control-Allow-Origin': '*'
  'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control'
  'Permissions-Policy': 'interest-cohort=()'
S.formats ?= ['html', 'csv', 'json'] # formats to allow to check for
S.svc ?= {}
S.src ?= {}

# check _auth, refuse if not appropriate
# _auth - if true an authorised user is required. If a string or a list, an authorised user with that role is required. For empty list, cascade the url routes as groups. always try to find user even if auth is not required, so that user is optionally available
# _auths can be used instead to cascade the _auth setting to everything below it

# check cache unless _cache is false, set result from cache if matches
# _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache)
# _caches - can be used to cascade the cache setting to everything below it
# NOTE _auth and _cache are ALWAYS checked first at the incoming request level, and NOT checked for subsequent called functions (fetch can also use cache internally)

# if an _async param was provided, check the async index for a completed result
# if found, delete it and save it to wherever it should be (if anywhere), just as if a normal result had been processed
# return the result to the user (via usual caching, logging etc if appropriate)

# otherwise check for args and/or params
# if args has length, args have priority
# otherwise go with params (or just pass through?)

# _kv - if true store the result in CF workers KV, and check for it on new requests - like a cache, but global, with 1s eventual consistency whereas cache is regional
# _kv gets checked prior to _index UNLESS there are args that appear to be a query
# for _kv, args[0] has to be a string for a key, with no args[1] - otherwise pass through

# _index - if true send the result to an index. Or can be an object of index initialisation settings, mappings, aliases
# _key - optional which key, if not default _id, to use from a result object to save it as - along with the function route which will be derived if not provided
# _prefix - if false, the index is not prefixed with the app/index name, so can be accessed by any running version. Otherwise, an index is only accessible to the app version with the matching prefix.
# _sheet - if true get a sheet ID from settings for the given endpoint, if string then it is the sheet ID. If present it implies _index:true if _index is not set

# _async - if true, don't wait for the result, just return _async:@rid. If bg is configured and _bg isn't false on the function, send to bg. Otherwise just continue it locally.
# _bg - if true pass request to backend server e.g for things that are known will be long running
# this can happen at the top level route or if it calls any function that falls back to bg, the whole query falls back

# by this point, with nothing else available, run the process (by now either on bg or worker, whichever was appropriate)
# if the response indicates an error, e.g. it is an object with a status: 404 or similar, return to the response
# also do not save if a Response object is directly passed as result from the function (and don't send to _response either, just return it)

# if a valid result is available, and wasn't already a record in kv or index, write the result to kv/index if configured to do so
# otherwise result needs to have a _key or _id
# cache the result unless _cache is false or it was an index creation or sheet load

# log the request, and whether or not data was sent, and if a result was achieved, and other useful info

try
  addEventListener 'fetch', (event) ->
    event.passThroughOnException() if S.pass isnt false
    event.respondWith P.call event

_unique = {}
_schedule = {}

P = () ->
  # the context here is the fetch event
  @started = Date.now() # not strictly accurate in a workers environment, but handy nevertheless, used for comparison when logs are finally written

  # make @S settings object local to this fetch event
  # this header is defined later because the built date is added to the end of the file by the deploy script, so it's not known until now
  try S.headers['x-' + S.name.toLowerCase()] ?= (if S.version then 'v' + S.version else '') + (if S.built then ' built ' + S.built  else '')
  @S = JSON.parse JSON.stringify S

  if typeof @waitUntil isnt 'function' # it will be on worker, but not on backend
    @S.bg = true if not @S.bg? or typeof @S.bg is 'string' # or could there be other places there is no waitUntil, but we want to deploy there without it being in bg mode?
    @S.cache ?= false
    @waitUntil = (fn) -> return true # just let it run
  else if not @S.kv # try setting a default key-value store reference on the worker
    # where will backend overwrite this to true? can this be set on the global S, and overwritten on backend?
    @S.kv = @S.name.replace /\s/g, ''
    delete @S.kv if not global[@S.kv]

  # make @params @body, @headers, @cookie
  @params ?= {}
  if @request.url? and @request.url.includes '?'
    pkp = ''
    for qp in @request.url.split('?')[1].split '&'
      #qp = await P.decode qp
      kp = qp.split '='
      if kp[0].length # avoid &&
        if kp.length is 1 and pkp and (kp[0].startsWith(' ') or kp[0].includes('%'))
          @params[pkp] += '&' + decodeURIComponent kp[0] # try to catch things like q="smith & jones"
        else
          @params[kp[0]] = if kp.length is 1 then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'true' then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'false' then false else if qp.endsWith('=') then true else kp[1]
          if typeof @params[kp[0]] is 'string' and @params[kp[0]].replace(/[0-9]/g,'').length is 0 and (@params[kp[0]] is '0' or not @params[kp[0]].startsWith('0'))
            kpn = parseInt @params[kp[0]]
            @params[kp[0]] = kpn if not isNaN kpn
          if typeof @params[kp[0]] is 'string' and @params[kp[0]].includes '%'
            try @params[kp[0]] = decodeURIComponent @params[kp[0]]
          if typeof @params[kp[0]] is 'string' and (@params[kp[0]].startsWith('[') or @params[kp[0]].startsWith('{'))
            try @params[kp[0]] = JSON.parse @params[kp[0]]
        pkp = kp[0]
  @headers = {}
  try
    @headers[hd[0].toLowerCase()] = hd[1] for hd in [...@request.headers] # request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
  catch
    try
      @headers[hk.toLowerCase()] = @request.headers[hk] for hk of @request.headers # backend server passes a normal object, so just use that if not set above
  @headers.ip ?= @headers['x-real-ip'] ? @headers['x-forwarded-for']

  ct = @headers['content-type'] ? ''
  if @S.bg is true
    @body = @request.body if @request.body?
  else if ct.includes '/json'
    @body = await @request.json()
  else if ct.includes 'form' # NOTE below, multipart may need to go to bg if receiving a file to save
    # TODO consider checking for request.arrayBuffer() as file content not in a multipart.
    # and for multipart, check to see if there actually is a file
    # https://stackoverflow.com/questions/14872460/how-to-detect-a-file-upload-examining-the-http-message
    bd = {}
    fd = await @request.formData()
    for entry of fd.entries()
      if entry[0]
        if bd[entry[0]]?
          bd[entry[0]] = [bd[entry[0]]] if not Array.isArray bd[entry[0]]
          bd[entry[0]].push entry[1]
        else
          bd[entry[0]] = entry[1]
    @body = bd if bd? and JSON.stringify(bd) isnt '{}'
  if not @body? and @request.method in ['POST', 'PUT', 'DELETE']
    # TODO get worker to hand off to bg if available, if receiving any sort of file
    try bd = await @request.text() # NOTE this will always be at least an empty string when request method isnt GET
    # can also do URL.createObjectURL @request.blob() here, but would that be useful? Or revert to bg?
    @body = bd if bd
  try @body = JSON.parse(@body) if typeof @body is 'string' and (@body.startsWith('{') or @body.startsWith('['))
  if typeof @body is 'object' and not Array.isArray @body
    for qp of @body
      if qp
        @params[qp] ?= @body[qp]
  try @cookie = @headers.Cookie ? @headers.cookie
  
  # set some request and user IDs / keys in @rid, @apikey, and @refresh
  @rid = @headers['x-' + @S.name.toLowerCase() + '-rid']
  try @rid ?= @headers['cf-ray'] #.slice 0, -4
  @rid ?= P.uid() # @uid is not defined yet
  try @apikey = @headers['x-apikey'] ? @headers.apikey ? @params.apikey
  for rk in ['x-apikey', 'apikey']
    delete @headers[rk] if @headers[rk]?
    delete @params[rk] if @params[rk]?
  if @params.refresh
    @refresh = @params.refresh
    delete @params.refresh # what to do about refresh getting into the cache key?

  # set the @url, the @base, the @route, and the url route parts in @parts
  if not @request.url.startsWith('http://') and not @request.url.startsWith 'https://'
    # in case there's a url param with them as well, check if they're at the start
    # there's no base to the URL passed on the backend server, so here the @base isn't shifted from the parts list
    @url = @request.url.split('?')[0].replace(/^\//,'').replace(/\/$/,'')
    try du = decodeURIComponent(@url) if @url.includes '%'
    @parts = if @url.length then (du ? @url).split('/') else []
    try @base = @headers.host
  else
    @url = @request.url.split('?')[0].replace(/\/$/,'').split('://')[1]
    try du = decodeURIComponent(@url) if @url.includes '%'
    @parts = (du ? @url).split '/'
    @base = @parts.shift()
  if typeof @headers.accept is 'string'
    @format = 'csv' if @headers.accept.includes '/csv'
  if @parts.length and @parts[@parts.length-1].includes '.' # format specified in url takes precedence over header
    pf = @parts[@parts.length-1].split('.').pop().toLowerCase()
    if pf in @S.formats
      @format = pf
      @parts[@parts.length-1] = @parts[@parts.length-1].replace '.' + pf, ''
  if typeof @S.bg is 'string' and Array.isArray(@S.pass) and @parts.length and @parts[0] in @S.pass
    throw new Error() # send to backend to handle requests for anything that should be served from folders on disk

  shn = 'x-' + @S.name.toLowerCase() + '-system'
  if @S.name and @S.system and @headers[shn] is @S.system
    delete @headers[shn]
    @system = true

  @_logs = [] # place for a running request to dump multiple logs, which will combine and save at the end of the overall request

  @route = @parts.join '/'
  @routes = []
  @fn = '' # the function name that was mapped to by the URL routes in the request will be stored here

  if @route is '' # don't bother doing anything, just serve a direct P._response with the API details
    if @request.method in ['HEAD', 'OPTIONS']
      return P._response.call @, ''
    else
      return P._response.call @, name: (@S.name ? 'OA.Works API'), version: @S.version, base: (if @S.dev then @base else undefined), built: @S.built, user: (@user?.email ? undefined)

  # loop through everything defined on P, wrap and configure all functions, and set them onto @ so they can be called in relation to this fetch event
  # also pick up any URL params provided along the way - anything that doesn't map to a function or an object is considered some sort of param
  # params will be added to @params, keyed to whatever the most recent URL part that DID map to a function was
  # so for example /svc/oaworks/find maps to svc.oaworks.find, and /svc/oaworks/find/10.1234/567890 ALSO maps to it, 
  # and puts the remainder of the route (which is a DOI) into @params.find, so the find function can read it from there
  fn = undefined # the actual function to run, once it's found (not just the name of it, which is put in @fn)
  prs = [...@parts]
  pk = undefined
  pks = []
  _lp = (p, a, n, auths, caches) =>
    if pk and @fn.startsWith n
      while prs.length and not p[prs[0]]?
        @params[pk] = (if @params[pk] then @params[pk] + '/' else '') + prs.shift()
        pks.push(pk) if pk not in pks
    for k of p
      if typeof p[k] not in ['function', 'object']
        a[k] = p[k]
      else if p[k]?
        nd = n + (if n then '.' else '') + k
        if typeof p[k] is 'object' and not p[k]._index and not p[k]._indexed and not p[k]._sheet and not p[k]._kv and not p[k]._bg # index, kv, or bg could be objects that need wrapped
          a[k] = JSON.parse JSON.stringify p[k]
        else
          p[k]._auth ?= p[k]._auths ?= auths
          p[k]._auths = nd.split('.') if Array.isArray(p[k]._auths) and p[k]._auths.length is 0 # an empty auth array defaults to group names corresponding to the function subroutes
          p[k]._auth = nd.split('.') if Array.isArray(p[k]._auth) and p[k]._auth.length is 0 # an empty auth array defaults to group names corresponding to the function subroutes
          p[k]._cache ?= p[k]._caches ?= caches
          p[k]._cache ?= false if nd.startsWith 'auth'
          p[k]._index ?= true if p[k]._sheet
          if p[k]._index # add index functions to index endpoints
            for ik in ['keys', 'terms', 'suggest', 'count', 'percent', 'min', 'max', 'range', 'sum', 'average', 'mapping', '_for', '_each', '_bulk', '_refresh'] # of P.index
              p[k][ik] ?= {_indexed: ik, _auth: (if ik.startsWith('_') then 'system' else p[k]._auth)}
          if typeof p[k] is 'function' and not p[k]._index and not p[k]._indexed and not p[k]._kv and not p[k]._bg and (not nd.includes('.') or n.startsWith('index') or nd.split('.').pop().startsWith '_')
            a[k] = p[k].bind @
          else
            a[k] = P._wrapper(p[k], nd).bind @
          for uk of p[k]
            a[k][uk] = p[k][uk] if uk.startsWith '_'
        a[k]._name ?= nd

        if a[k]._schedule and not _schedule[nd] and @S.bg is true and @S.cron isnt false
          console.log 'Adding schedule', a[k]._schedule, nd
          _schedule[nd] = schedule: a[k]._schedule, fn: a[k]
          sfn = (fnm) =>
            return () =>
              fno = _schedule[fnm].fn
              aru = @S.async_runner?[fno._runner ? fnm]
              if @S.dev isnt true and not @S.async and not @S.async_loop and not @S.async_schedule and process.env.pm_id? and process.env.pm_id not in [1, '1']
                console.log 'NOT running scheduled task because not on dev and process pid is not 1', fnm, @datetime()
              else if typeof aru isnt 'string' and not @S.async_schedule and typeof @S.async is 'string'
                console.log 'NOT running scheduled task because not on the available async process', fnm, @datetime()
              else if typeof aru isnt 'string' and typeof @S.async_schedule is 'string' and (fno._schedule isnt 'loop' or not @S.async_loop)
                console.log 'NOT running scheduled task because not on the available async scheduled process', fnm, @datetime()
              else if typeof aru isnt 'string' and typeof @S.async_loop is 'string' and fno._schedule is 'loop'
                console.log 'NOT running scheduled looped task because not on the available loop process', fnm, @datetime()
              else if typeof aru is 'string' and process.env.name and not process.env.name.endsWith (fno._runner ? fnm).replace(/\./g, '_').replace('__', '_')
                console.log 'NOT running scheduled task because not on the specified process runner', (fno._runner ? fnm), @datetime()
              else
                console.log 'scheduled task', fnm, @datetime()
                _schedule[fnm].last = await @datetime()
                delete _schedule[fnm].error
                try
                  if fno._sheet
                    crd = await @_loadsheet _schedule[fnm].fn, fno._name.replace /\./g, '_'
                  else
                    crd = await _schedule[fnm].fn fno._args # args can optionally be provided for the scheduled call
                  try _schedule[fnm].result = JSON.stringify(crd).substr 0, 200
                  _schedule[fnm].success = true
                  console.log 'scheduled task result', crd
                  if fno._schedule is 'loop'
                    console.log 'Schedule looping', fnm
                    lpd = await sfn fnm
                    lpd()
                catch err
                  _schedule[fnm].success = false
                  try _schedule[fnm].error = JSON.stringify err
          if a[k]._schedule in ['loop', 'startup']
            console.log 'Starting scheduled', a[k]._schedule, nd
            lpd = await sfn nd
            lpd()
          else
            cron.schedule a[k]._schedule, sfn nd

        if not k.startsWith '_' # underscored methods cannot be accessed from URLs
          if prs.length and prs[0] is k and @fn.startsWith n
            pk = prs.shift()
            @fn += (if @fn is '' then '' else '.') + pk
            fn = a[k] if typeof a[k] is 'function' and not n.includes '._' # URL routes can't call _abc functions or ones under them
          if typeof a[k] is 'function' and nd.replace('svc.','').replace('src.','').split('.').length is 1 #and ((not nd.startsWith('svc') and not nd.startsWith('src')) or nd.split('.').length < 3)
            @routes.push nd.replace /\./g, '/' # TODO this could check the auth method, and only show things the current user can access, and also search for description / comment? NOTE this is just about visibility, they're still accessible if given right auth (if any)
        _lp(p[k], a[k], nd, (auths ? p[k]._auths), (caches ? p[k]._caches)) if not Array.isArray(p[k]) and (not k.startsWith('_') or typeof a[k] is 'function') and k not in ['fn']
  _lp P, @, ''
  if pk and prs.length # catch any remaining url params beyond the max depth of P
    @params[pk] = if @params[pk] then @params[pk] + '/' + prs.join('/') else prs.join '/'
  for cpk in pks # tidy any params provided within the URL
    @params[cpk] = true if @params[cpk].toLowerCase() is 'true'
    @params[cpk] = false if @params[cpk].toLowerCase() is 'false'
    if typeof @params[cpk] is 'string' and @params[cpk].replace(/[0-9]/g,'').length is 0 and not @params[cpk].startsWith '0'
      pkn = parseInt @params[cpk]
      @params[cpk] = pkn if not isNaN pkn

  console.log('=== ' + (if @system then 'SYSTEM ' else '') + @request.method + ' ===', @base, @fn, @domain, typeof @body) if @S.dev and @S.bg is true

  if typeof fn in ['object', 'function'] and fn._bg and typeof @S.bg is 'string' and @S.bg.startsWith 'http'
    throw new Error()
  else if typeof fn in ['object', 'function'] and (fn._async or (@params.size is 'all' and fn._index and not (process.env.name ? '').endsWith('_makecsv'))) and typeof @S.async is 'string' and (typeof @S.async_runner?[fn._runner ? @fn] isnt 'string' or not process.env.name or not process.env.name.endsWith (fn._runner ? @fn).replace /\./g, '_' )
    asr = if @params.size is 'all' and fn._index and @S.async_runner?._makecsv then @S.async_runner._makecsv else (@S.async_runner?[fn._runner ? @fn] ? @S.async)
    console.log 'Fetching from async process', asr, @request.url
    res = await @fetch asr + @request.url, method: @request.method, headers: @headers, body: @request.body
    delete @format
  else if typeof fn is 'function'
    authd = if @fn is 'auth' then undefined else await @auth()
    @user = authd if typeof authd is 'object' and authd._id and authd.email
    if typeof fn._auth is 'function'
      authd = await fn._auth()
    else if fn._auth is true and @user? # just need a logged in user if true
      authd = true
    else if fn._auth # which should be a string... comma-separated, or a list
      authd = await @auth.role fn._auth # _auth should be true or name of required group.role
    else
      authd = true

    if authd or @system
      if @request.method in ['HEAD', 'OPTIONS']
        res = ''
      else if fn._cache isnt false and not @refresh and (@request.method is 'GET' or (@request.method is 'POST' and await @index.translate @params)) and res = await @cache() # this will return empty if nothing relevant was ever put in there anyway
        # how about caching of responses to logged in users, by param or header?
        @cached = 'cache'
        res = new Response res.body, res # no need to catch this for backend execution because cache function will never find anything on backend anyway
        res.headers.append 'x-' + @S.name.toLowerCase() + '-cached', 'cache' # this would leave any prior "index" value, for example. Or use .set to overwrite
        res.headers.delete 'x-' + @S.name.toLowerCase() + '-took'
      else
        res = await fn()
        @completed = true

    else
      @unauthorised = true
      await @sleep 200 * (1 + Math.random()) # https://en.wikipedia.org/wiki/Timing_attack
      res = status: 401 # not authorised
      res.body = await @auth false # this returns an auth web page if the request appeared to come from a web browser (and not from js)

  res = '' if (not res? or (typeof res is 'object' and res.status is 404)) and @url.replace('.ico','').replace('.gif','').replace('.png','').endsWith 'favicon'
  resp = if typeof res is 'object' and not Array.isArray(res) and typeof res.headers?.append is 'function' then res else await @_response res, fn
  if @parts.length and @parts[0] not in ['log','status'] and (not @system or @parts[0] not in ['kv', 'index']) and @request.method not in ['HEAD', 'OPTIONS'] and res? and res isnt ''
    if @completed and fn._cache isnt false and resp.status is 200 and (typeof res isnt 'object' or Array.isArray(res) or res.hits?.total isnt 0) and (typeof res isnt 'number' or not @refresh)
      si = fn._cache # fn._cache can be a number of seconds for cache to live, so pass it to cache to use if suitable
      si = 60 if not si? and typeof res is 'object' and not Array.isArray(res) and res.hits?.hits? # if this is a search result, cache only 1 minute max if nothing else was set for it
      @cache undefined, resp, si
    else if @refresh
      @cache undefined, ''
    @log() if typeof fn in ['object', 'function'] and fn._log isnt false
  if not @completed and not @cached and not @unauthorised and @S.pass isnt false and typeof @S.bg is 'string' and @request.method not in ['HEAD', 'OPTIONS']
    throw new Error() # TODO check for functions that often timeout and set them to _bg by default
  else
    return resp


# build a suitable response object
# API above calls this to create a response, unless the result of the called function
# is already a suitable response (which itself could use this function, or manually 
# build a response if preferred/necessary)
P._response = (res, fn) ->
  @S.headers ?= {}
  if not res?
    res = 404
    status = 404
  else if @fn isnt 'status' and typeof res is 'object' and not Array.isArray(res) and ((typeof res.status is 'number' and res.status > 300 and res.status < 600) or res.headers)
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
  
  if not @S.headers['Content-Type'] and not @S.headers['content-type']
    if @format and @format in @S.formats
      if typeof res isnt 'string'
        try
          res = await @convert['json2' + @format] res
      if typeof res is 'string' and @format is 'html'
        res = res.replace /\>\</g, '>\n<'
        if not res.includes('<html') and not @params.partial
          ret = '<!DOCTYPE html><html dir="ltr" lang="en">\n<head>\n'
          ret += '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
          if res.includes '<title'
            [pt, tt] = res.split '<title'
            [tt, at] = tt.split '</title>'
            ret += '<title' + tt + '</title>\n'
            res = pt + at
          else if res.includes 'id="title"'
            ret += '<title>' + res.split('id="title"')[1].split('>')[1].split('<')[0] + '</title>\n'
          for hdr in ['<meta ', '<link ']
            if res.includes hdr
              for m in res.split hdr
                rm = hdr + m.split('>')[0]
                res = res.replace rm, ''
                ret += rm + '\n'
          if res.includes '<head>'
            [ph, hh] = res.split '<head>'
            [hh, ah] = hh.split '</head>'
            ret += hh
            res = ph + ah
          ret += '<link rel="icon" href="data:,">' if not ret.includes 'icon'
          ret += '\n</head>\n'
          ret += if not res.includes '<body' then '\n<body>\n' + res + '\n</body>\n' else res
          res = ret + '\n</html>'
      @S.headers['Content-Type'] = if @format is 'html' then 'text/html; charset=UTF-8' else 'text/csv; charset=UTF-8'
    if typeof res isnt 'string'
      try res = JSON.stringify res, '', 2
    @S.headers['Content-Type'] ?= 'application/json; charset=UTF-8'
  try @S.headers['Content-Length'] ?= Buffer.byteLength res
  try @S.headers['x-' + @S.name.toLowerCase() + '-took'] = Date.now() - @started
  try @S.headers['x-' + @S.name.toLowerCase() + '-cached'] = @cached if @cached
  try
    if @S.bg is true
      return status: status, headers: @S.headers, body: res
    else
      return new Response res, {status: status, headers: @S.headers}
  catch
    return status: status, headers: @S.headers, body: res


P._loadsheet = (f, rt) ->
  if f._sheet.startsWith('http') and f._sheet.includes 'csv'
    sht = await @convert.csv2json f._sheet
  else if f._sheet.startsWith('http') and f._sheet.includes 'json'
    sht = await @fetch f._sheet
    sht = [sht] if sht and not Array.isArray sht
  else
    sht = await @src.google.sheets f._sheet
  if Array.isArray(sht) and sht.length
    sht = await f._format.apply(@, [sht]) if typeof f._format is 'function'
    if f._key
      for t in sht
        t._id ?= (t[f._key] ? @uid()).replace(/\//g, '_').toLowerCase()
    await @index rt, ''
    await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: (f._index.mappings ? f._index.mapping), aliases: f._index.aliases}
    await @index rt, sht
    return sht.length
  else
    return 0

# API calls this to wrap functions on P, apart from top level functions and ones 
# that start with _
# wrapper settings declared on each P function specify which wrap actions to apply
# _auth and _cache settings on a P function are handled by API BEFORE _wrapper is 
# used, so _auth and _cache are not handled within the wrapper
# the wrapper logs the function call (whether it was the main API call or subsequent)
P._wrapper = (f, n) -> # the function to wrap and the string name of the function
  return () ->
    started = Date.now() # not accurate in a workers environment, but close enough
    rt = n.replace /\./g, '_'
    lg = fn: n

    # _limit can be true, which stays in place until the function completes, or it can be a number which 
    # will be the lifespan of the limit record in the KV store
    # _limit
    if f._limit
      limited = await @kv 'limit/' + n
      while limited
        lg.limited ?= 0
        lg.limited += limited
        await @sleep limited - started
        limited = await @kv 'limit/' + n

    # check for an _async param request and look to see if it is in the async finished store
    # if so, serve the result otherwise re-serve the param to indicate waiting should continue
    # _async
    if typeof @params._async in ['string', 'number']
      if res = await @kv 'async/' + @params._async, ''
        if typeof res is 'string' and res.includes('/') and not res.includes(' ') and not res.includes(':') and not res.startsWith('10.') and res.split('/').length is 2
          try res = await @kv(res) if f._kv
          try res = await @index(res) if not res? and f._index # async stored the _id for the result
        try res = JSON.parse(res) if typeof res is 'string' and (res.startsWith('{') or res.startsWith('['))
      else
        res = _async: @params._async # user should keep waiting

    # serve the underlying sheet / csv link if configured and asked for it
    # _sheet
    else if @fn is n and f._sheet and @parts.indexOf('sheet') is @parts.length-1
      res = status: 302
      if f._sheet.startsWith 'http'
        res.body = f._sheet
      else if @format is 'json' # TODO make it handle sheet and sheet ID in cases where both are provided
        #res.body = 'https://spreadsheets.google.com/feeds/list/' + f._sheet + '/' + 'default' + '/public/values?alt=json'
        res.body = 'https://sheets.googleapis.com/v4/spreadsheets/' + f._sheet.split('/')[0] + '/values/' + (f._sheetid ? f._sheet.split('/')[1] ? 'Sheet1') + '?alt=json'
      else
        res.body = 'https://docs.google.com/spreadsheets/d/' + f._sheet.split('/')[0]
      res.headers = Location: res.body

    # a function with _index will be given child functions that call the default index child functions - if they're present, call them with the route specified
    else if f._indexed
      args = [...arguments]
      args.unshift rt.replace '_' + f._indexed, ''
      res = await @index[f._indexed] ...args
      
    # index / kv should first be checked if configured
    # for index, to create a new record with a specified ID, ONLY specify it as _id in the object as first argument and no second argument
    # updating / deleting can be done providing key in first argument and object / empty string in second argument
    # for kv, create can be done with ID string as first argument and record/value as second argument
    # _index, _kv
    else if (f._index or f._kv) and (not f._sheet or @fn isnt n or not @refresh)
      if @fn is n
        lg.key = @route.split(n.split('.').pop()).pop().replace(/\//g, '_').replace(/^_/,'').replace(/_$/,'') if @fn.replace(/\./g, '/') isnt @route # action on a specific keyed record
        qry = await @index.translate(if @request.method is 'POST' then @body else @params) if not lg.key and f._index #and not rec?
        # TODO who should be allowed to submit a record remotely?
        #rec = if @request.method is 'PUT' or (lg.key and @request.method is 'POST') then @body else if @request.method is 'DELETE' or @params._delete then '' else undefined
         # and if there is @params._delete, delete by query?
      else if arguments.length # could be a key string and record or could be a query and options (and query could look like a key)
        # could be key or query string - if query string is ambiguous, make it definitive by sending an object with q: 'query string'
        lg.key = arguments[0].replace(/\//g, '_').trim() if typeof arguments[0] is 'string' and arguments[0].length and not arguments[0].includes('\n') and arguments[0].length is arguments[0].replace(/[\s\*~\?="]/g, '').length # removed \: and % from regex to allow DOIs containing : as ID
        lg.key = arguments[0].toString() if typeof arguments[0] is 'number' # some indexes could use a number as an ID
        qry = await @index.translate(arguments[0], arguments[1]) if f._index and not lg.key # check if it can be a query
        rec = if qry? then undefined else if lg.key then arguments[1] else if f._index then arguments[0] else undefined

      if typeof rec is 'object'
        if not Array.isArray rec
          rec._id ?= (lg.key ? rec[f._key] ? @uid()).replace(/\//g, '_').toLowerCase()
          lg.key ?= rec._id.replace(/\//g, '_').toLowerCase()
        else if rec.length
          for c in rec
            c._id ?= (c[f._key] ? @uid()).replace(/\//g, '_').toLowerCase()
      #console.log(n, lg.key, JSON.stringify(rec), JSON.stringify(qry), res, @refresh, typeof f, exists) if @S.dev and @S.bg is true
      
      if rec? or not @refresh or typeof f isnt 'function'
        if f._kv and lg.key
          res = await @kv rt + '/' + lg.key, rec # there may or may not be a rec, as it could just be getting the keyed record
          lg.cached = 'kv' if res? and not rec?
        if f._index
          if @params.size is 'all'
            if @S.bg isnt true
              if typeof @S.bg is 'string'
                throw new Error() # trip out to backend
              else
                res = status: 404
            nfeml = @params.email ? @params.notify ? @user?.email
            if @params.orgkey
              pok = @params.orgkey
              delete @params.orgkey
            pfs = @params.funders ? @params.flatten
            afs = @params.authorships ? @params.flatten
            delete qry.orgkey
            delete qry.funders
            delete qry.authorships
            delete qry.flatten
            delete qry.email
            delete @params.size
            delete qry.size
            tot = await @index.count rt, qry
            if tot > 3000000 or not @S.static?.folder
              res = status: 401
            else
              flid = (if @fn then @fn.replace(/\./g, '_') else '') + '_' + @uid()
              eurl = @S.static.url + '/export/' + flid + '.csv'
              if tot > 100000
                await @mail to: (@S.log?.notify ? 'mark+notifications@oa.works'), text: 'Someone is creating a large csv of size ' + tot + '\n\n' + eurl
              out = @S.static.folder + '/export'
              try
                filecount = (await fs.readdir out).length
                @mail({to: (@S.log?.notify ? 'mark+notifications@oa.works'), text: 'Warning, export file count is ' + filecount + ' they will be deleted at 1000'}) if filecount > 900 and filecount % 20 is 0
                # add auto deletion of old export files?
              catch
                await fs.mkdir out
                filecount = 0
              try
                if filecount > 999
                  for fl in await fs.readdir out
                    await fs.unlink out + '/' + fl
                  @mail {to: (@S.log?.notify ? 'mark+notifications@oa.works'), text: 'Export files had reached 1000 so have been deleted '}
              if filecount > 1000
                res = status: 401
              else
                out += '/' + flid  + '.csv'
                await fs.appendFile out, ''
                if @params.includes?
                  @params.include = @params.includes
                  delete @params.includes
                if @params.excludes?
                  @params.exclude = @params.excludes
                  delete @params.excludes
                if @params.include?
                  ks = if typeof @params.include is 'string' then @params.include.split(',') else @params.include
                  if pok
                    if typeof @params.include is 'string' and not @params.include.includes 'orgs'
                      @params.include += ',orgs'
                    else if Array.isArray(@params.include) and 'orgs' not in @params.include
                      @params.include.push 'orgs'
                    qry._source.includes.push('orgs') if 'orgs' not in qry._source.includes
                else
                  ks = []
                  for ak in await @index.keys rt
                    tk = ak.split('.')[0]
                    ks.push(tk) if tk not in ks and tk isnt '_id'
                if @params.exclude?
                  for ex in (if typeof @params.exclude is 'string' then @params.exclude.split(',') else @params.exclude)
                    pidx = ks.indexOf ex
                    ks = ks.splice(pidx, 1) if pidx isnt -1 and (not pok or ex isnt 'orgs')
                  if pok
                    orgsidx = qry._source.excludes.indexOf 'orgs'
                    qry._source.excludes = qry._source.excludes.splice(orgsidx, 1) if orgsidx isnt -1
                if nfeml
                  await @mail to: nfeml, subject: 'Your export has started (ref: ' + flid + '.csv)', text: 'Your export has started. You can download the file any time, it will keep growing until it is complete, when you will get another notification.<br><br><a href="' + eurl + '">Download CSV</a><br><br>Thanks'
                _makecsv = (rt, qry, out, keys, notify, eurl, pfs, afs, pok) =>
                  first = true
                  if pok?
                    rpke = await @encrypt pok
                    orgk = await @report.orgs.orgkeys 'key.keyword:"' + rpke + '"', 1
                  if pfs or afs
                    keys = ['DOI']
                    keys.push(e) for e in ['funder.name', 'funder.award'] if pfs
                    keys.push(e) for e in ['authorships.institutions.display_name','authorships.institutions.ror', 'authorships.author.orcid', 'authorships.author.raw_affiliation_string'] if afs
                  for key in keys
                    await fs.appendFile out, (if not first then ',"' else '"') + key.replace('supplements.', '') + '"'
                    first = false
                  themax = 100000
                  for ab in ['@oa.works', 'pcastromartin@', 'wbschmal@', 'mailparser.io']
                    themax = 3000000 if notify and notify.includes ab
                  for await blr from @index._for rt, qry, {scroll: '30m', max: themax}
                    await fs.appendFile out, '\n'
                    if pfs or afs
                      names = ''
                      awards = ''
                      institutions = ''
                      rors = ''
                      orcids = ''
                      affiliations = ''
                      if blr.funder? and pfs
                        first = true
                        for funder in blr.funder
                          names += (if first then '' else ';') + (funder.name ? '').replace(/"/g, '')
                          funder.award = funder.award.join(' ') if funder.award? and funder.award.length
                          funder.award ?= ''
                          if Array.isArray funder.award
                            if funder.award.length
                              funder.award = funder.award.join ' '
                            else
                              funder.award = '' 
                          funder.award = funder.award.replace /;/g, ''
                          awards += (if first then '' else ';') + funder.award
                          first = false
                      if blr.authorships? and afs
                        first = true
                        for author in blr.authorships
                          if not first
                            institutions += ';'
                            rors += ';'
                          first = false
                          if author.institutions?
                            fi = true
                            for inst in author.institutions
                              institutions += (if fi then '' else ',') + (inst.display_name ? '').replace(/"/g, '')
                              rors += (if fi then '' else ',') + (inst.ror ? '')
                              fi = false
                          orcids += (if orcids then ',' else '') + author.author.orcid if author.author?.orcid
                          affiliations += (if affiliations then ',' else '') + author.raw_affiliation_string.replace(/"/g, '') if author.raw_affiliation_string
                      await fs.appendFile out, '"' + blr.DOI + (if pfs then '","' + names + '","' + awards else '') + (if afs then '","' + institutions + '","' + rors + '","' + orcids + '","' + affiliations else '') + '"'
                    else
                      first = true
                      for k in keys
                        if k.includes '.'
                          try
                            blfl = await @flatten blr
                          catch
                            blfl = undefined
                        else
                          blfl = blr
                        if Array.isArray blfl
                          if blfl.length and typeof blfl[0] is 'object'
                            st = []
                            for blp in blfl
                              st.push(blp[k]) if blp?[k]?
                            blfl = st
                          nar = {}
                          nar[k] = blfl
                          blfl = nar
                        if not blfl? or not blfl[k]?
                          val = ''
                        else if typeof blfl[k] is 'object'
                          if Array.isArray blfl[k]
                            bljnd = ''
                            for bn in blfl[k]
                              if typeof bn is 'object'
                                if k is 'sheets' and bn.url and ((typeof orgk?.org is 'string' and orgk.org.length and orgk.org is blr.name.toLowerCase()) or (typeof @user?.email is 'string' and @user.email.endsWith('@oa.works')))
                                  bn.url = await @decrypt bn.url
                                bn = JSON.stringify bn
                              bljnd += (if bljnd then ';' else '') + bn if not bljnd.includes bn # Joe doesn't want duplicates kept
                            blfl[k] = bljnd
                          val = JSON.stringify blfl[k]
                        else
                          val = blfl[k]
                        val = val.replace(/"/g, '').replace(/\n/g, '').replace(/\s\s+/g, ' ') if typeof val is 'string'
                        if k in ['sheets.url'] and ((typeof orgk?.org is 'string' and orgk.org.length and orgk.org is blr.name.toLowerCase()) or (typeof @user?.email is 'string' and @user.email.endsWith('@oa.works')))
                          dvs = []
                          dvs.push(await @decrypt vtd) for vtd in (if Array.isArray(val) then val else val.split(','))
                          val = JSON.stringify dvs
                        else if k in ['email', 'supplements.email'] and not val.includes('@') and typeof orgk?.org is 'string' and orgk.org.length
                          rol = []
                          rol.push(rou.toLowerCase()) for rou in (blr.orgs ? [])
                          if orgk.org.toLowerCase() in rol
                            val = await @decrypt val
                        await fs.appendFile out, (if not first then ',"' else '"') + val + '"'
                        first = false
                  if notify
                    await @mail to: notify, subject: 'Your export is complete (ref: ' + out.split('/').pop() + ')', text: 'Your export is complete. We recommend you download and store files elsewhere as soon as possible as we may delete this file at any time.<br><br><a href="' + eurl + '">Download CSV</a><br><br>Thanks'
                @waitUntil _makecsv rt, qry, out, ks, nfeml, eurl, pfs, afs, pok
                delete @format
                res = eurl
          else
            res = await @index rt + (if lg.key then '/' + lg.key else ''), (rec ? qry)
          if not res? and (not lg.key or not rec?) # this happens if the index does not exist yet, so create it (otherwise res would be a search result object)
            await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: (f._index.mappings ? f._index.mapping), aliases: f._index.aliases}
            res = await @index(rt + (if lg.key then '/' + lg.key else ''), (rec ? (if not lg.key then qry else undefined))) if rec isnt ''
          if not res? and not rec? and lg.key and typeof arguments[0] is 'string' and qry = await @index.translate arguments[0], arguments[1]
            qrs = await @index rt, qry
            if qrs?.hits?.total is 1
              for k in await @keys qrs.hits.hits[0]._source
                if (typeof qrs.hits.hits[0]._source[k] is 'string' and arguments[0] is qrs.hits.hits[0]._source[k]) or (Array.isArray(qrs.hits.hits[0]._source[k]) and arguments[0] in qrs.hits.hits[0]._source[k])
                  res = qrs.hits.hits[0]._source
                  res._id ?= qrs.hits.hits[0]._id
                  break
          if qry?.size is 1 and typeof res is 'object' and res.hits?.hits?
            if not res.hits.hits.length
              res = undefined
            else
              res.hits.hits[0]._source._id ?= res.hits.hits[0]._id
              res = res.hits.hits[0]._source
      lg.qry = JSON.stringify(qry) if qry?
      lg.cached = 'index' if res? and not rec? and not lg.cached
      @cached = lg.cached if lg.cached and @fn is n

    # if nothing yet, send to bg for _bg or _sheet functions, if bg is available and not yet on bg
    # _bg, _sheet
    if not res? and (f._bg or f._sheet) and typeof @S.bg is 'string' and @S.bg.startsWith 'http'
      bup = headers: {}, body: rec, params: @copy @params
      bup.params.refresh = true if @refresh
      bup.headers['x-' + @S.name.toLowerCase() + '-rid'] = @rid
      res = await @fetch @S.bg + '/' + rt.replace(/\_/g, '/'), bup # if this takes too long the whole route function will timeout and cascade to bg
      lg.bg = true

    # if nothing yet, and function has _sheet, and it wasn't a specific record lookup attempt, 
    # or it was a specific API call to refresh the _sheet index, or any call where index doesn't exist yet,
    # then (create the index if not existing and) populate the index from the sheet
    # this will happen on background where possible, because above will have routed to bg if it was available
    # _sheet
    if not res? and f._sheet and rec isnt '' and ((@refresh and @fn is n) or not exists = await @index rt)
      res = await @_loadsheet f, rt
      res = undefined if arguments.length or JSON.stringify(@params) isnt '{}' # if there are args, don't set the res, so the function can run afterwards if present

    # if still nothing happened, and the function defined on P really IS a function
    # (it could also be an index or kv config object with no default function)
    # call the function, either _async if the function indicates it, or directly
    # and record limit settings if present to restrict more runnings of the same function
    # _async, _limit
    if not res? and (not f._index or rec isnt '') and typeof f is 'function'
      _as = (rt, f, ar, notify, nn) =>
        if f._limit
          ends = if f._limit is true then 86400 else f._limit
          await @kv 'limit/' + nn, started + ends, ends # max limit for one day
        r = await f.apply @, ar
        delete _unique[nn]
        if typeof r is 'object' and (f._kv or f._index) and not r.took? and not r.hits?
          if f._key and Array.isArray(r) and r.length and not r[0]._id? and r[0][f._key]?
            c._id ?= c[f._key].replace(/\//g, '_').toLowerCase() for c in r
          id = if Array.isArray(r) then '' else '/' + (r[f._key] ? r._id ? @uid()).replace(/\//g, '_').toLowerCase()
          @kv(rt + id, res, f._kv) if f._kv and not Array.isArray r
          @waitUntil(@index(rt + id, r)) if f._index
        if f._limit is true
          await @kv 'limit/' + nn, '' # where limit is true only delay until function completes, then delete limit record
        if f._async and f._schedule isnt 'loop'
          @kv 'async/' + @rid, (if id? and not Array.isArray(r) then rt + id else if Array.isArray(r) then r.length else r), 172800 # lasts 48 hours
          if @fn is nn and f._notify isnt false
            txt = @fn + ' done at ' + (await @datetime undefined, false) + '\n\n' + JSON.stringify(r) + '\n\n' + @base + '/' + rt + '?_async=' + @rid
            @mail({to: notify, text: txt}) if notify
        return r
      if f._async and @fn is n
        lg.async = true
        if f._unique and prid = _unique[n]
          res = _async: prid
        else
          _unique[@fn] = @rid if f._unique
          res = _async: @rid
          @waitUntil _as rt, f, arguments, @params.notify, n
      else
        res = await _as rt, f, arguments

    # _log - DISABLED all wrapped logging. Only requests onto the API routes get logged as of 11/10/2023
    #if f._log isnt false and not f._index and not lg.qry? and not n.includes '._'
    #  lg.took = Date.now() - started
    #  @log lg

    return res

P.svc = {}
P.src = {}


P.status = ->
  res = name: S.name, version: S.version, built: S.built
  try res.pmid = process.env.pm_id
  try res.pmname = process.env.name
  for k in ['rid', 'params', 'base', 'parts', 'opts', 'routes']
    try res[k] ?= @[k]
  if @S.bg is true
    try
      res.schedule = {}
      for ss of _schedule
        res.schedule[ss] = {}
        for k of _schedule[ss]
          res.schedule[ss][k] = _schedule[ss][k] if k not in ['fn']
  res.bg = true if @S.bg is true
  res.kv = if typeof @S.kv is 'string' and global[@S.kv] then @S.kv else if typeof @S.kv is 'string' then @S.kv else false
  try res.index = await @index.status()
  if S.dev
    res.bg = @S.bg
    if @S.bg isnt true
      try res.request = @request
    for k in ['headers', 'cookie', 'user', 'body']
      try res[k] ?= @[k]
  else
    try res.index = res.index.status
    res.kv = true if res.kv
    res.user = @user?.email
      
  return res
