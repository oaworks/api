
# global S and P are accessible anywhere, and all files are merged into one on build.
# NOTE it IS possible for scripts to persist between cloudflare worker requests, but also not guaranteed or intentional
# so can't rely on them being clean every time, nor rely on them for storing state. Hence every new fetch event builds its own @S and @P

try
  # from CF variable this will need parsed, so just default to passing them as strings and parsing them
  S = JSON.parse SECRETS_SETTINGS
try
  SS = JSON.parse SECRETS_SERVER # backend server can provide overrides in a server.json secrets file
  S[k] = SS[k] for k of SS
S ?= {} # and just in case it wasn't found
S.name ?= 'Paradigm' # this will also be used as the default name for the KV store
S.version ?= '5.5.0' # the construct script will use this to overwrite any version in the worker and server package.json files
# S.pass can be set to false if there is a bg URL but worker errors should NOT pass through on exception to it (otherwise they will by default)
S.pass = ['docs', 'client', '.well-known'] # if this is a list of strings, any route starting with these will throw error and pass back to bg (this would happen anyway with no function defined for them, but this avoids unnecessary processing)
S.dev ?= true
S.headers ?=
  'Access-Control-Allow-Methods': 'HEAD, GET, PUT, POST, DELETE, OPTIONS'
  'Access-Control-Allow-Origin': '*'
  'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control'
  'Permissions-Policy': 'interest-cohort=()'
S.formats ?= ['html', 'csv', 'json'] # allow formatted responses in this list
S.svc ?= {}
S.src ?= {}


# check _auth, refuse if not appropriate
# _auth - if true an authorised user is required. If a string or a list, an authorised user with that role is required. For empty list, cascade the url routes as groups. always try to find user even if auth is not required, so that user is optionally available
# _auths can be used instead to cascade the _auth setting to everything below it

# check cache unless _cache is false, set result from cache if matches
# _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache)
# _caches - can be used to cascade the cache setting to everything below it
# NOTE _auth and _cache are ALWAYS checked first at the incoming request level, and NOT checked for subsequent called functions (fetch can also use cache internally)

# _wrap - can be set to false so that a function that would otherwise be wrapped won't be

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
# if _history, and new data was sent, store the POST content rather than just whether or not there was any, so it can be recreated

# _diff can be true or a list of arguments for the function. It will check to see if a process gives the same result 
# (compared against a previously stored one). If it doesn't it should log something that then gets 
# picked up by the alert mechanism

# _format can be set to default the function format return type (html or csv so far)
# _hide can be set to hide a function that should otherwise show up on the routes list, 
# or _hides can be used to hide a function and anything under it
# e.g. one that doesn't start with _ but should be hidden for some reason anyway. NOTE this 
# doesn't stop it being ACCESSIBLE on the API, only hidden, whereas starting it with _ makes it inaccessible

# TODO limit, retry, cron/job/batch
# TODO add a way for a function to result in a file url on local disk or s3, or perhaps even a URL somewhere else, 
# and to serve the location redirect as the result. Could be a _file option

try
  addEventListener 'fetch', (event) ->
    event.passThroughOnException() if S.pass isnt false
    event.respondWith P.call event
try
  addEventListener 'scheduled', (event) ->
    # https://developers.cloudflare.com/workers/runtime-apis/scheduled-event
    # event.type will always be 'scheduled'. event.scheduledTime ms timestamp of the scheduled time. Can be parsed with new Date(event.scheduledTime)
    event.waitUntil P.call event, true # Fails will be recorded on Cron past events UI. Otherwise will record as success


P = (scheduled) ->
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
  @params = {}
  if @request.url? and @request.url.indexOf('?') isnt -1
    pkp = ''
    for qp in @request.url.split('?')[1].split '&'
      kp = qp.split '='
      if kp[0].length # avoid &&
        if kp.length is 1 and pkp and (kp[0].startsWith(' ') or kp[0].includes('%'))
          @params[pkp] += '&' + decodeURIComponent kp[0] # try to catch things like q="smith & jones"
        else
          @params[kp[0]] = if kp.length is 1 then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'true' then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'false' then false else if qp.endsWith('=') then true else kp[1]
          if typeof @params[kp[0]] is 'string' and @params[kp[0]].replace(/[0-9]/g,'').length is 0 and not @params[kp[0]].startsWith('0')
            kpn = parseInt @params[kp[0]]
            @params[kp[0]] = kpn if not isNaN kpn
          if typeof @params[kp[0]] is 'string' and @params[kp[0]].indexOf('%') isnt -1
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

  ct = @headers['content-type'] ? ''
  if @S.bg is true
    @body = @request.body if @request.body?
  else if ct.includes '/json'
    @body = await @request.json()
  else if ct.includes 'form' # NOTE below, multipart may need to go to bg if receiving a file to save
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
  @rid = @headers['x-' + @S.name.toLowerCase() + '-async']
  try @rid ?= @headers['cf-ray'].slice 0, -4
  @rid ?= P.uid() # @uid is not defined yet
  # how / when to remove various auth headers before logging / matching cache?
  # e.g apikey, resume, token, access_token, email?
  try @apikey = @headers['x-apikey'] ? @headers.apikey ? @params.apikey
  for rk in ['x-apikey', 'apikey']
    delete @headers[rk] if @headers[rk]?
    delete @params[rk] if @params[rk]?
  if @params.refresh
    @refresh = @params.refresh
    delete @params.refresh # what to do about refresh getting into the cache key?

  # set the @url, the @base, the @route, and the url route parts in @parts
  if @request.url.indexOf('http://') isnt 0 and @request.url.indexOf('https://') isnt 0
    # in case there's a url param with them as well, check if they're at the start
    # there's no base to the URL passed on the backend server, so here the @base isn't shifted from the parts list
    @url = @request.url.split('?')[0].replace(/^\//,'').replace(/\/$/,'')
    try du = decodeURIComponent(@url) if @url.indexOf('%') isnt -1
    @parts = if @url.length then (du ? @url).split('/') else []
    try @base = @headers.host
  else
    @url = @request.url.split('?')[0].replace(/\/$/,'').split('://')[1]
    try du = decodeURIComponent(@url) if @url.indexOf('%') isnt -1
    @parts = (du ? @url).split '/'
    @base = @parts.shift()
  if typeof @headers.accept is 'string'
    @format = 'csv' if @headers.accept.indexOf('/csv') isnt -1 and 'csv' in @S.formats
  if @parts.length and @parts[@parts.length-1].indexOf('.') isnt -1 # format specified in url takes precedence over header
    pf = @parts[@parts.length-1].split('.').pop()
    if pf in @S.formats
      @format = pf
      @parts[@parts.length-1] = @parts[@parts.length-1].replace '.' + pf, ''
  if typeof @S.bg is 'string' and Array.isArray(@S.pass) and @parts.length and @parts[0] in @S.pass
    throw new Error() # send to backend to handle requests for anything that should be served from folders on disk
  for d of @S.domains ? {} # allows requests from specific domains to route directly to a subroute, or more usefully, a specific service
    @S.domains[d] = {parts: @S.domains[d], exclusive: false} if Array.isArray @S.domains[d]
    if @base.indexOf(d) isnt -1
      exclusive = @S.domains[d].exclusive # if exclusive, ONLY routes that match within the defined parts will be served
      if not exclusive # for non-exclusive, only restrict if there IS something to match at or after the defined parts
        pp = [...@S.domains[d].parts]
        tp = P
        while cp = pp.shift()
          try tp = tp[cp]
        exclusive = true if tp? and ((not @parts.length and typeof tp is 'function') or tp[@parts[0]]?)
      if exclusive
        @domain = d
        @parts = [...@S.domains[d].parts, ...@parts]
        break

  console.log(@request.method, @base, @domain, typeof @body) if @S.dev #and @S.bg is true

  @route = @parts.join '/'
  @routes = []
  @fn = '' # the function name that was mapped to by the URL routes in the request will be stored here
  @scheduled = true if scheduled or @route is '_schedule' # and restrict this to root, or disable URL route to it
  @_logs = [] # place for a running request to dump multiple logs, which will combine and save at the end of the overall request

  if @route is '' #don't bother doing anything, just serve a direct P._response with the API details
    return P._response.call @, if @request.method in ['HEAD', 'OPTIONS'] then '' else name: @S.name, version: @S.version, base: (if @S.dev then @base else undefined), built: (if @S.dev then @S.built else undefined)


  # TODO add a way to identify and iterate multiple functions either parallel or serial, adding to results
  # e.g. split url at // for multi functions. Params parallel gives on obj of named results
  # with merge for one result overwriting as they're received, or if only merge then merge in order
  # auth would need to be present for every stage

  # loop through everything defined on P, wrap and configure all functions, and set them onto @ so they can be called in relation to this fetch event
  # also pick up any URL params provided along the way - anything that doesn't map to a function or an object is considered some sort of param
  # params will be added to @params, keyed to whatever the most recent URL part that DID map to a function was
  # so for example /svc/oaworks/find maps to svc.oaworks.find, and /svc/oaworks/find/10.1234/567890 ALSO maps to it, 
  # and puts the remainder of the route (which is a DOI) into @params.find, so the find function can read it from there
  schedule = [] # if called by a task scheduler, every _schedule function will be put in here, and these get run instead of the fn
  fn = undefined # the actual function to run, once it's found (not just the name of it, which is put in @fn)
  prs = [...@parts]
  pk = undefined
  _lp = (p, a, n, hides, auths, wraps, caches) =>
    if pk and @fn.indexOf(n) is 0
      while prs.length and not p[prs[0]]?
        @params[pk] = (if @params[pk] then @params[pk] + '/' else '') + prs.shift()
    for k of p
      if typeof p[k] not in ['function', 'object']
        a[k] = p[k]
      else if p[k]?
        nd = n + (if n then '.' else '') + k
        if typeof p[k] is 'object' and not p[k]._index and not p[k]._indexed and not p[k]._kv and not p[k]._bg # index, kv, or bg could be objects that need wrapped
          a[k] = JSON.parse JSON.stringify p[k]
        else
          p[k]._hide ?= p[k]._hides ?= hides
          p[k]._auth ?= p[k]._auths ?= auths
          p[k]._auths = nd.split('.') if Array.isArray(p[k]._auths) and p[k]._auths.length is 0 # an empty auth array defaults to group names corresponding to the function subroutes
          p[k]._auth = nd.split('.') if Array.isArray(p[k]._auth) and p[k]._auth.length is 0 # an empty auth array defaults to group names corresponding to the function subroutes
          p[k]._wrap ?= p[k]._wraps ?= wraps
          p[k]._cache ?= p[k]._caches ?= caches
          p[k]._cache ?= false if nd.startsWith 'auth'
          p[k]._index ?= true if p[k]._sheet
          if p[k]._index # add index functions to index endpoints
            for ik in ['keys', 'terms', 'suggest', 'count', 'min', 'max', 'range', 'mapping', 'history', '_for'] #, '_each', '_bulk', '_refresh'] # of P.index
              p[k][ik] ?= {_indexed: ik, _auth: (if ik in [] then 'system' else p[k]._auth)}
          for sk of fs = P.dot @S, n
            p[k][sk] = fs[sk] if sk.startsWith '_' # try to find anything in settings and treat it as an override
          if typeof p[k] is 'function' and not p[k]._index and not p[k]._indexed and not p[k]._kv and not p[k]._bg and (nd.indexOf('.') is -1 or p[k]._wrap is false or nd.split('.').pop().indexOf('_') is 0)
            a[k] = p[k].bind @
          else
            a[k] = P._wrapper(p[k], nd).bind @
          a[k]._fn = nd
          for uk of p[k]
            a[k][uk] = p[k][uk] if uk.startsWith '_'
        schedule.push(a[k]) if @scheduled and a[k]._schedule
        if not k.startsWith '_' # underscored methods cannot be accessed from URLs
          if prs.length and prs[0] is k and @fn.indexOf(n) is 0
            pk = prs.shift()
            @fn += (if @fn is '' then '' else '.') + pk
            fn = a[k] if typeof a[k] is 'function' and n.indexOf('._') is -1 # URL routes can't call _abc functions or ones under them
          if typeof a[k] is 'function' and not a[k]._hide and nd.replace('svc.','').replace('src.','').split('.').length is 1 #and not nd.startsWith('scripts') and nd.indexOf('.scripts') is -1 and ((not nd.startsWith('svc') and not nd.startsWith('src')) or nd.split('.').length < 3)
            @routes.push (nd).replace(/\./g, '/') # TODO this could check the auth method, and only show things the current user can access, and also search for description / comment? NOTE this is just about visibility, they're still accessible if given right auth (if any)
        _lp(p[k], a[k], nd, (hides ? p[k]._hides), (auths ? p[k]._auths), (wraps ? p[k]._wraps), (caches ? p[k]._caches)) if not Array.isArray(p[k]) and (not k.startsWith('_') or typeof a[k] is 'function')
  _lp P, @, ''
  if pk and prs.length # catch any remaining url params beyond the max depth of P
    @params[pk] = if @params[pk] then @params[pk] + '/' + prs.join('/') else prs.join('/')
  # TODO should url params get some auto-processing like query params do above? Could be numbers, lists, bools...

  if @scheduled
    for fs in schedule
      console.log('scheduled', fs._fn) if @S.dev
      try
        if typeof fs._schedule is 'function'
          @waitUntil fs._schedule.apply @
        else # TODO add a timing method to this to only run at certain times, waiting until a kv record or similar indicating last run is not available
          @waitUntil fs.apply @

  else if typeof fn in ['object', 'function'] and fn._bg and typeof @S.bg is 'string' and @S.bg.startsWith 'http'
    throw new Error()
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

    # TODO check the blacklist
    if authd
      @format ?= fn._format if typeof fn._format is 'string' and fn._format in @S.formats
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
      # Random delay for https://en.wikipedia.org/wiki/Timing_attack
      @unauthorised = true
      await @sleep 200 * (1 + Math.random())
      res = status: 401 # not authorised
      if @format is 'html'
        res.body = await @auth undefined, (if @fn.startsWith('svc.') then @fn.replace('svc.', '').split('.')[0].toUpperCase() else '')

  res = '' if (not res? or (typeof res is 'object' and res.status is 404)) and @url.replace('.ico','').replace('.gif','').replace('.png','').endsWith 'favicon'
  resp = if typeof res is 'object' and not Array.isArray(res) and typeof res.headers?.append is 'function' then res else await @_response res, fn
  # what about if scheduled? log?
  if @parts.length and @parts[0] not in ['log','status'] and (not @system or @parts[0] not in ['kv', 'index']) and @request.method not in ['HEAD', 'OPTIONS'] and res? and res isnt ''
    if @completed and fn._cache isnt false and resp.status is 200 and (typeof res isnt 'object' or Array.isArray(res) or res.hits?.total isnt 0) and (typeof res isnt 'number' or not @refresh)
      si = fn._cache # fn._cache can be a number of seconds for cache to live, so pass it to cache to use if suitable
      si = 60 if not si? and typeof res is 'object' and not Array.isArray(res) and res.hits?.hits? # if this is a search result, cache only 1 minute max if nothing else was set for it
      @cache undefined, resp, si
    else if @refresh
      @cache undefined, ''
    @log() if typeof fn not in ['object', 'function'] or fn._log isnt false
  if not @completed and not @cached and not @unauthorised and not @scheduled and @S.pass isnt false and typeof @S.bg is 'string' and @request.method not in ['HEAD', 'OPTIONS']
    throw new Error() # TODO check for functions that often timeout and set them to _bg by default
  else
    return resp

P.src = {}
P.svc = {}
P.scripts = {}

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
    if @format and @format in ['html', 'csv']
      if typeof res isnt 'string'
        try
          res = await @convert['json2' + @format] res
      if typeof res is 'string' and @format is 'html' and not res.includes('<html') and not @params.partial
        ret = '<!DOCTYPE html><html dir="ltr" lang="en">\n<head>\n'
        ret += '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1.0">\n';
        if res.includes '<title'
          [pt, tt] = res.split '<title'
          [tt, at] = tt.split '</title>'
          ret += '<title' + tt + '</title>\n'
          res = pt + at
        else if res.includes 'id="title"'
          ret += '<title>' + res.split('id="title"')[1].split('>')[1].split('<')[0] + '</title>\n'
        ret += '<link href="//fonts.googleapis.com/css?family=Lustria|Noto+Sans|Roboto+Slab|Nixie+One" rel="stylesheet" type="text/css">\n'
        ret += '<link rel="stylesheet" href="/client/pradm.min.css?v=' + @S.version + '">\n'
        ret += '<script type="text/javascript" src="/client/pradm.min.js?v=' + @S.version + '"></script><script type="text/javascript" src="/client/pradmLogin.min.js?v=' + @S.version + '"></script>\n'
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
    return new Response res, {status: status, headers: @S.headers}
  catch
    return status: status, headers: @S.headers, body: res

