
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
S.version ?= '5.3.1' # the construct script will use this to overwrite any version in the worker and server package.json files
S.dev ?= true
S.pass ?= true if typeof S.bg is 'string' # if there is a bg to pass through to on errors/timeouts, then go to it by default
S.docs ?= 'https://leviathanindustries.com/paradigm'
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

# check cache unless _cache is false, set res from cache if matches
# _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache)
# NOTE _auth and _cache are ALWAYS checked first at the incoming request level, and NOT checked for subsequent called functions (fetch can also use cache internally)

# if an _async param was provided, check the async index for a completed result
# if found, delete it and save it to wherever it should be (if anywhere), just as if a normal result had been processed
# return the result to the user (via usual caching, logging etc if appropriate)

# otherwise check for args and/or params
# if args has length, args have priority
# otherwise go with params (or just pass through?)

# then check storage layers if configured to do so
# _kv - if true store the result in CF workers KV, and check for it on new requests - like a cache, but global, with 1s eventual consistency whereas cache is regional
# _index - if true send the result to an index. Or can be an object of index initialisation settings, mappings, aliases
# _key - optional which key, if not default _id, to use from a result object to save it as - along with the function route which will be derived if not provided
# _search - if false, the wrapper won't run a search on incoming potential queries before calling the function. If a string, will be used as the key to search within, unless the incoming content is obviously already a complex query
# _qopts - an optional object defining query options, see P.index.translate and elasticsearch docs to learn more about what can be provided
# _prefix - if false, the index is not prefixed with the app/index name, so can be accessed by any running version. Otherwise, an index is only accessible to the app version with the matching prefix. TODO this may be updated with abilityt o list prefix names to match multiple app versions but not all
# _sheet - if true get a sheet ID from settings for the given endpoint, if string then it is the sheet ID. If present it implies _index:true if _index is not set

# _kv gets checked prior to _index UNLESS there are args that appear to be a query
# for _kv, args[0] has to be a string for a key, with no args[1] - otherwise pass through
# for _index args[0] has to be string for key, or query str or query obj, args[1] empty or query params
# if it was a call to /index directly, and if those get wrapped, then args[0] may also be index name, with a query obj in args[1]
# if _index and no index present, create it - or only on provision of data or query?
# if _sheet, and no index present, or @params.sheet, load it too
# _sheet loads should be _bg even if main function isn't
# if _sheet, block anything appearing to be a write?

# _async - if true, don't wait for the result, just return _async:@rid. If bg is configured and _bg isn't false on the function, send to bg. Otherwise just continue it locally.
# _bg - if true pass request to backend server e.g for things that are known will be long running
# this can happen at the top level route or if it calls any function that falls back to bg, the whole query falls back

# by this point, with nothing else available, run the process (by now either on bg or worker, whichever was appropriate)

# if the response indicates an error, e.g. it is an object with a status: 404 or similar, return to the response
# also do not save if a Response object is directly passed as result from the function (and don't send to _response either, just return it)

# if a valid result is available, and wasn't already a record in from kv or index, write the result to kv/index if configured to do so
# NOTE index actually writes to kv unless _kv is explicitly false, for later scheduled pickup and bulk index
# otherwise result needs to have a _key or _id
# cache the result unless _cache is false or it was an index creation or sheet load

# log the request, and whether or not data was sent, and if a result was achieved, and other useful info
# if _history, and new data was sent, store the POST content rather than just whether or not there was any, so it can be recreated

# _diff can be true or a list of arguments for the function. It will check to see if a process gives the same result 
# (compared against a previously stored one). If it doesn't it should log something that then gets 
# picked up by the alert mechanism

# _format can be set to default the function format return type (html or csv so far)
# _hidden can be set to hide a function that should otherwise show up on the routes list, 
# e.g. one that doesn't start with _ but should be hidden for some reason anyway. NOTE this 
# doesn't stop it being ACCESSIBLE on the API, only hidden, whereas starting it with _ makes it inaccessible

# TODO limit, retry, cron/job/batch (note workers now has a schedule ability too. explore that but consider vendor lock-in)
# TODO add a way for a function to result in a file url on local disk or s3, or perhaps even a URL somewhere else, 
# and to serve the location redirect as the result. Could be a _file option

try
  addEventListener 'fetch', (event) ->
    event.passThroughOnException() if S.pass
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
  try S.headers['X-' + S.name] ?= (if S.version then 'v' + S.version else '') + (if S.built then ' built ' + S.built  else '')
  @S = JSON.parse JSON.stringify S
  
  # make @params @body, @headers, @cookie
  @params = {} # TODO add a general cleaner of incoming params? but allow override if necessary for certain endpoints?
  # note may need to remove apikey param - but if removing, how does that affect the fact that request is an actual immutable Request object?
  # it probably would appear to change, but may still be in there, then may get saved in cache etc which prob isn't wanted
  # unless results SHOULD differ by apikey? Probably on any route where that is the case, caching should be disabled
  if @request.url? and @request.url.indexOf('?') isnt -1
    for qp in @request.url.split('?')[1].split '&'
      kp = qp.split '='
      @params[kp[0]] = if kp.length is 1 then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'true' then true else if typeof kp[1] is 'string' and kp[1].toLowerCase() is 'false' then false else if qp.endsWith('=') then true else kp[1]
      if typeof @params[kp[0]] is 'string' and @params[kp[0]].replace(/[0-9]/g,'').length is 0 and not @params[kp[0]].startsWith('0')
        kpn = parseInt @params[kp[0]]
        @params[kp[0]] = kpn if not isNaN kpn
      if typeof @params[kp[0]] is 'string' and (@params[kp[0]].startsWith('[') or @params[kp[0]].startsWith('{'))
        try @params[kp[0]] = JSON.parse @params[kp[0]]
      else if typeof @params[kp[0]] is 'string' and @params[kp[0]].indexOf('%') isnt -1
        try @params[kp[0]] = decodeURIComponent @params[kp[0]]
  @headers = {}
  try
    @headers[hd[0].toLowerCase()] = hd[1] for hd in [...@request.headers] # request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
  catch
    try
      @headers[hk.toLowerCase()] = @request.headers[hk] for hk of @request.headers # backend server passes a normal object, so just use that if not set above

  try
    ct = @headers['content-type']
    ct ?= ''
    if ct.includes '/json'
      @body = await @request.json()
    else if ct.includes 'form'
      fd = await @request.formData()
      for entry of fd.entries()
        if @body[entry[0]]?
          @body[entry[0]] = [@body[entry[0]]] if not Array.isArray @body[entry[0]]
          @body[entry[0]].push entry[1]
        else
          @body[entry[0]] = entry[1]
    else
      @body = await @request.text()
    # and what if blob? Accept blobs or not?
    # @body = URL.createObjectURL await request.blob()
  try @body ?= @request.body # if nothing else, just get the body which may be directly provided by the server
  try @body = JSON.parse(@body) if @body.startsWith('{') or @body.startsWith('[')
  try
    if typeof @body is 'object' and not Array.isArray @body
      @params[qp] ?= @body[qp] for qp of @body

  if typeof @waitUntil isnt 'function' # it will be on worker, but not on backend
    @S.bg = true if not @S.bg? or typeof @S.bg is 'string' # or could there be other places there is no waitUntil, but we want to deploy there without it being in bg mode?
    @S.cache ?= false
    @waitUntil = (fn) -> return true # just let it run
  else if not @S.kv # try setting a default key-value store reference on the worker
    # where will backend overwrite this to true? can this be set on the global S, and overwritten on backend?
    @S.kv = @S.name.replace /\s/g, ''
    delete @S.kv if not global[@S.kv]
  try @cookie = @headers.Cookie ? @headers.cookie
  
  # set some request and user IDs / keys in @rid, @id, @apikey, and @refresh
  try @rid = @headers['cf-ray'].slice 0, -4
  try @rid ?= @headers['x-' + @S.name + '-async']
  # how / when to remove various auth headers before logging / matching cache?
  # e.g apikey, id, resume, token, access_token, email?
  try @uid = @headers['x-uid'] ? @headers.uid ? @params.uid
  try @apikey = @headers['x-apikey'] ? @headers.apikey ? @params.apikey
  delete @headers['x-apikey'] if @headers['x-apikey']
  delete @headers.apikey if @headers.apikey
  delete @params.apikey if @params.apikey
  delete @params.uid if @params.uid
  if @params.refresh
    @refresh = @params.refresh
    delete @params.refresh # what to do about refresh getting into the cache key?

  # set the @url, the @base, the @route, and the url route parts in @parts
  if @request.url.indexOf('http://') isnt 0 and @request.url.indexOf('https://') isnt 0
    # in case there's a url param with them as well, check if they're at the start
    # there's no base to the URL passed on the backend server, so here the @base isn't shifted from the parts list
    @url = @request.url.split('?')[0].replace(/^\//,'').replace(/\/$/,'')
    @parts = if @url.length then @url.split('/') else []
    try @base = @headers.host
  else
    @url = @request.url.split('?')[0].replace(/\/$/,'').split('://')[1]
    @parts = @url.split '/'
    @base = @parts.shift()
  if typeof @headers.accept is 'string'
    @format = 'csv' if @headers.accept.indexOf('/csv') isnt -1 and 'csv' in @S.formats
  if @parts.length and @parts[@parts.length-1].indexOf('.') isnt -1 # format specified in url takes precedence over header
    pf = @parts[@parts.length-1].split('.').pop()
    if pf in @S.formats
      @format = pf
      @parts[@parts.length-1] = @parts[@parts.length-1].replace '.' + pf, ''
  if @parts.length is 1 and @parts[0] in ['docs', 'client'] and typeof @S.bg is 'string' and @S.pass
    throw new Error() # send to backend to handle requests for anything that should be served from folders on disk
  for d of @S.domains ? {} # allows requests from specific domains to route directly to a subroute, or more usefully, a specific service
    if @base.indexOf(d) isnt -1
      @domain = d
      @parts = [...@S.domains[d], ...@parts]
      break
  
  console.log(@base, @domain) if @S.dev and @S.bg is true

  @route = @parts.join '/'
  @routes = []
  @fn = '' # the function name that was mapped to by the URL routes in the request will be stored here
  @scheduled = true if scheduled or @route is '_schedule' # and restrict this to root, or disable URL route to it
  #@nolog = true if ... # don't log if nolog is present and its value matches a secret key? Or if @S.log is false?
  @_logs = [] # place for a running request to dump multiple logs, which will combine and save at the end of the overall request

  if @route is '' #don't bother doing anything, just serve a direct P._response with the API details
    return P._response.call @, if @request.method in ['HEAD', 'OPTIONS'] then '' else name: @S.name, version: @S.version, base: (if @S.dev then @base else undefined), built: (if @S.dev then @S.built else undefined)

  # a save method called by the following _return when necessary
  _save = (k, r, f) =>
    if r? and (typeof r isnt 'object' or Array.isArray(r) or (r.headers?.append isnt 'function' and (typeof r.status isnt 'number' or r.status < 200 or r.status > 600)))
      # if the function returned a Response object, or something with an error status, don't save it
      if f._key and Array.isArray(r) and r.length and not r[0]._id? and r[0][f._key]?
        c._id = (if Array.isArray(c[f._key]) then c[f._key][0] else c[f._key]) for c in r
      id = if Array.isArray(r) then '' else '/' + (if f._key and r[f._key] then r[f._key] else (r._id ? @uid())).replace(/\//g, '_').replace(k + '_', '').toLowerCase()
      @kv(k + id, r, f._kv) if f._kv and not Array.isArray(r) #_kv should be set for things that MUST be in the kv - they won't be removed, but will be copied to index if _index is also true
      if f._index and (f._kv is false or not @S.kv or @S.bg)  # all indexing is bulked through kv unless _kv is false or overall kv is disabled in settings, or immediate indexing is true
        if not exists = await @index k.split('/')[0] # create the index if it doesn't exist yet
          await @index k.split('/')[0], (if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases})
        @index k + id, r
      if f._async
        @kv 'async/' + @rid, if f._index or f._kv then k + id else r

  # wraps every function on P, apart from top level functions and ones that start with _
  # and controls how it should return, depending on wrapper settings declared on each P object
  # _auth and _cache are handled before _return is used to wrap, because they only operate on the function defined by the URL route
  # whereas any other functon called later also gets wrapped and handled here
  _return = (f, n) =>
    try
      fs = P.dot @S, n
      for uf of fs
        f[uf] = fs[uf] if uf.startsWith '_' # try to find anything in settings and treat it as an override
    f._auth = n.split('.') if Array.isArray(f._auth) and f._auth.length is 0 # an empty auth array defaults to group names corresponding to the function subroutes
    f._index ?= true if f._sheet
    f._cache ?= false if n.startsWith 'auth'
    if f._index and f._kv isnt false
      f._schedule ?= (if f._sheet then '0001' else true) # reload sheets at 0600 every day by default?
    if typeof f is 'function' and (n.indexOf('.') is -1 or n.split('.').pop().indexOf('_') is 0)
      return f.bind @ # don't wrap top-level or underscored methods
    else if typeof f is 'object' and not f._index and not f._kv and not f._bg and typeof f[@request.method] isnt 'function'
      f._fn = n
      return JSON.parse JSON.stringify f
    else
      _wrapped = () ->
        st = Date.now() # again, not necessarily going to be accurate in a workers environment
        rt = n.replace /\./g, '_'
        lg = fn: n, key: rt

        if f._async and @params.async and not arguments.length and @fn is n
          # check for an _async param request and look to see if it is in the async temp store (if it's finished)
          if adone = await @kv 'async/' + @params.async, ''
            if typeof adone is 'string' and adone.indexOf('/') isnt -1 and adone.split('/').length is 2
              if f._kv # retrieve the full result from kv or index (the async just stored the identifier for it)
                res = await @kv adone
              else if f._index
                res = await @index adone
            else
              try
                res = if typeof adone is 'string' then JSON.parse(adone) else adone
              catch
                res = adone
          else
            res = _async: @params.async # user should keep waiting
        else if f._index or f._kv
          if arguments.length is 1
            if f._index and await @index._q arguments[0]
              lg.qry = arguments[0]
            else if typeof arguments[0] is 'string'
              if arguments[0].length
                #lg.key = rt + '/' + arguments[0].replace(/\//g, '_').replace rt + '_', ''
                lg.key = arguments[0]
              else
                rec = ''
            else if typeof arguments[0] is 'object'
              rec = arguments[0]
              lg.key = if f._key then rec[f._key] else if rec._id then rec._id else rt 
          else if arguments.length is 2
            if f._index and arguments[0]? and isq = await @index._q arguments[0]
              lg.qry = arguments[0]
              qopts = arguments[1]
            else if f._index and typeof arguments[0] is 'string' and arguments[0].indexOf('/') is -1 and isq = await @index._q arguments[1]
              lg.key = arguments[0]
              lg.qry = arguments[1]
            else if typeof arguments[0] is 'string'
              lg.key = arguments[0]
              rec = arguments[1]
              if lg.key.indexOf('/') is -1
                lg.key = if f._key and rec[f._key] then rec[f._key] else if rec._id then rec._id else rt 
          else if @fn is n # try from params and parts - it's only a rec if the parts indicate an ID as well as route
            if @request.method is 'PUT' or (@request.method is 'POST' and not isq = await @index._q @params)
              rec = @body
            else if @request.method is 'DELETE'
              rec = ''
            else if isq = await @index._q @params
              lg.qry = @params
            else if @parts.indexOf('create') is @parts.length - 1 or @parts.indexOf('save') is @parts.length - 1
              rec = @copy @params
              delete rec[c] for c in @parts
              rec = undefined if JSON.stringify(rec) is '{}'
            lg.key = @route
            
        if f._sheet and @parts.indexOf('sheet') is @parts.length-1
          # serve the sheet url. TODO could make this a redirect too - als make it handle sheet and sheet ID in cases where both are provided
          res = status: 302
          if @format is 'json'
            res.body = 'https://spreadsheets.google.com/feeds/list/' + f._sheet + '/' + 'default' + '/public/values?alt=json'
          else
            res.body = 'https://docs.google.com/spreadsheets/d/' + f._sheet
          res.headers = Location: res.body

        lg.key = rt + '/' + lg.key.replace(/\//g, '_').replace(rt, '').replace(/^_/, '') if lg.key
        if not res? and (f._index or f._kv) and (not @refresh or (f._sheet and @fn isnt n and not @scheduled) or (@fn is n and rec)) # and not rec? and not fn.qry))
          if f._kv and lg.key.indexOf('/') isnt -1 and not lg.qry # check kv first if there is an ID present
            res = await @kv lg.key, rec
            lg.cached = 'kv' if res? and not rec?
          if not res? and f._index and (rec? or f._search isnt false) # otherwise try the index
            # TODO if lg.qry is a string like a title, with no other search qualifiers in it, and f._search is a string, treat f._search as the key name to search in
            # BUT if there are no spaces in lg.qry, it's probably supposed to be part of the key - that should be handled above anyway
            if rec?
              if typeof rec is 'object' and not Array.isArray(rec) and not rec._id and JSON.stringify(rec) not in ['{}', '[]']
                rec._id = @uid()
              res = await @index lg.key, rec
            else
              if not lg.key.includes '/'
                qopts = f['_' + @format]?._qopts ? f._json?._qopts ? f._qopts
                lg.qry = '*' if not lg.qry? and qopts?
              res = await @index lg.key, (if lg.qry then await @index.translate(lg.qry, qopts) else undefined)
            if @fn isnt n and typeof lg.qry is 'string' and lg.qry.indexOf(' ') is -1 and not rec and res?.hits?.total is 1 and lg.qry.indexOf(res.hits.hits[0]._id) isnt -1
              try res = res.hits.hits[0]._source
            lg.cached = 'index' if res? and not rec?
        @cached = lg.cached if lg.cached and @fn.startsWith n # record whether or not the main function result was cached in index or kv
        
        if not res? and (f._bg or f._sheet) and typeof @S.bg is 'string' and @S.bg.indexOf('http') is 0
          # if nothing yet and requires bg or sheet, pass to bg if available and not yet there
          # TODO would it be better to just throw error here and divert the entire request to backend?
          bup = headers: {}, body: rec ? (if arguments.length then arguments[0] else @params)
          bup.headers['x-' + @S.name + '-async'] = @rid
          try
            # TODO could @_timeout this and if it runs out, throw new Error() to go to bg machine
            # TODO this replace of _ with / affects function names with underscores in them - if there are any, need a neater way to handle switching back to url form
            res = await @fetch @S.bg + '/' + lg.key.replace(/_/g, '/') + (if @refresh then '?refresh=true' else ''), bup # if this takes too long the whole route function will timeout and cascade to bg
            lg.bg = true
        # if it's an index function with a sheet setting, or a sheet param has been provided, what to do by default?
        if not res? and f._sheet and (@refresh or not exists = await @index rt) # this will happen on background where possible, because above will have routed to bg if it was available
          res = await @src.google.sheets f._sheet
          if typeof f is 'function' # process the sheet with the parent if it is a function
            res = await f.apply @, [res]
          await @index(rt, '') if Array.isArray(res) and res.length
          @waitUntil _save rt, @copy(res), f
          res = res.length
        if not res?
          if typeof (f[@request.method] ? f) is 'function' # it could also be an index or kv config object with no default function
            if f._async
              lg.async = true
              res = _async: @rid
              _async = (rt, f) =>
                if ares = await (f[@request.method] ? f).apply @, arguments
                  _save rt, @copy(ares), f
              @waitUntil _async rt, f
            else
              res = await (f[@request.method] ? f).apply @, arguments
              if res? and (f._kv or f._index)
                @waitUntil _save rt, @copy(res), f
          else if f._index and not lg.qry and not rec and rt.indexOf('/') is -1 and not exists = await @index rt # create the index
            res = await @index rt, (if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases})

        if f._diff and @request.method is 'GET' and res? and not lg.cached and not lg.async
          try
            lg.args = JSON.stringify arguments
            if Array.isArray(f._diff) and typeof f._diff[0] is 'string'
              if f._diff[0].startsWith '-' # it's a list of keys to ignore
                dr = @copy res
                delete dr[d.replace('-','')] for d in f._diff
              else # it's a list of keys to include
                dr = {}
                dr[di] = res[di] for di in f._diff
              lg.res = JSON.stringify dr
            else
              lg.res = JSON.stringify res # what if this is huge? just checksum it?

        if f._history and (f._index or f._kv) and rec? and not Array.isArray rec
          try lg.rec = JSON.stringify rec # record the incoming rec to record a history of changes to the record
        lg.qry = JSON.stringify(lg.qry) if lg.qry
        try lg.took = Date.now() - st
        @log lg
        return res
      wb = _wrapped.bind @
      for uk of f
        if uk.startsWith '_'
          wb._fn ?= n # set the function name if there are other underscored wraper settings to work with
          wb[uk] = f[uk] 
      return wb

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
  _lp = (p, a, n) =>
    # TODO consider if it would be useful to have the construct script build a default of this
    # NOTE that may reduce the configurability of it per call, or at least may require some additional config at call time anyway, 
    # which may limit the value of having it pre-configured in the first place
    #if p._index # add default additional index functions
    #  p[ik] ?= P.index[ik] for ik of P.index #['keys', 'terms', 'suggest', 'count', 'min', 'max', 'range']
    if pk and @fn.indexOf(n) is 0
      while prs.length and not p[prs[0]]?
        @params[pk] = (if @params[pk] then @params[pk] + '/' else '') + prs.shift()
    for k of p
      if typeof p[k] not in ['function', 'object']
        try
          a[k] = JSON.parse JSON.stringify p[k] # is it worth copying this?
        catch
          a[k] = p[k]
      else
        nd = n + (if n then '.' else '') + k
        a[k] = _return p[k], nd
        schedule.push(a[k]) if @scheduled and a[k]._schedule
        if not k.startsWith '_' # underscored methods cannot be accessed from URLs, and are never wrapped
          if prs.length and prs[0] is k and @fn.indexOf(n) is 0
            pk = prs.shift()
            @fn += (if @fn is '' then '' else '.') + pk
            fn = a[k] if typeof a[k] is 'function' and n.indexOf('._') is -1 # URL routes can't call _abc functions or ones under them
          if typeof a[k] is 'function' and not a[k]._hidden and not nd.startsWith('scripts') and nd.indexOf('.scripts') is -1 and not nd.startsWith('kv') and not nd.startsWith('index') and ((not nd.startsWith('svc') and not nd.startsWith('src')) or nd.split('.').length < 3)
            @routes.push (nd).replace(/\./g, '/') # TODO this could check the auth method, and only show things the current user can access, and also search for description / comment? NOTE this is just about visibility, they're still accessible if given right auth (if any)
        _lp(p[k], a[k], nd) if not Array.isArray(p[k]) and (not k.startsWith('_') or typeof a[k] is 'function')
  _lp P, @, ''
  if pk and prs.length # catch any remaining url params beyond the max depth of P
    @params[pk] = if @params[pk] then @params[pk] + '/' + prs.join('/') else prs.join('/')
  # TODO should url params get some auto-processing like query params do above? Could be numbers, lists, bools...

  if @scheduled
    res = {}
    klogs = [] # move any logs first so that schedule can be aware of any recently run scheduled events
    await @kv._each 'log', (lk) ->
      if lk.indexOf('/') isnt -1 and lk isnt 'log'
        l = await @kv lk, ''
        l._id ?= lk.split('/').pop()
        klogs.push l
    res.log = klogs.length
    if klogs.length
      @waitUntil @index 'log', klogs

    requested_refresh = true if @refresh is true # track if the main request included a refresh from the start, to force all scheduled events to happen regardless of timing (mainly for dev/test)
    for fs in schedule
      if fs._fn #and fs._fn in ['svc.oaworks.permissions.journals']
        console.log('scheduled', fs._fn) if @S.dev #and @S.bg is true
        if typeof fs._schedule is 'function'
          res[fs._fn] = true
          @waitUntil fs._schedule()
        else
          fun = fs._fn.replace /\./g, '_'
          recs = []
          hhmm = true
          if typeof fs._schedule is 'number' or (typeof fs._schedule is 'string' and fs._schedule.length is 4 and fs._schedule.replace(/[0-9]/g, '').length is 0)
            # TODO consider changing this to accept cron style strings of space-separated numbers. For now can be time like "0900" or number of minutes like 240
            if requested_refresh
              last = false
            else
              lasts = await @index 'log', 'logs.fn:"' + fs._fn + '" AND scheduled:true', true
              last = if lasts?.hits?.hits? and lasts.hits.hits.length then lasts.hits.hits[0]._source else false
            if typeof last is 'object' and ((typeof fs._schedule is 'number' and last.started and (last.started + (fs._schedule*60000)) > @started) or (last.createdAt and (last.createdAt.split('T')[0].split('-').pop().replace(/^0/, '') is (new Date()).getDate().toString() or @started < (new Date()).setHours(parseInt(fs._schedule.substring(0,2)), parseInt(fs._schedule.substring(2)), 0, 0))))
              hhmm = false
              res[fs._fn] = false
            else
              hhmm = fs._schedule
          if hhmm isnt false
            res[fs._fn] = true
            if fs._sheet
              if typeof fs is 'function'
                @refresh ?= true
                await fs() # await this one so that the kv import runs after
              else # will it ever not be a (wrapped) function?
                recs = await @src.google.sheets fs._sheet
                await @index(fun, '') if Array.isArray(recs) and recs.length
            else if typeof fs is 'function' and hhmm isnt true
              @waitUntil fs()
          await @kv._each fun, (kn) ->
            if kn.indexOf('/') isnt -1 and kn isnt fun
              # this could also be used as a way to replicate changes back into a sheet after reload, if there was a unique identifier for records
              rec = await @kv kn, if fs._kv then undefined else '' # if kv not explicitly set, delete when moving to index
              rec._id ?= kn.split('/').pop()
              recs.push rec
          recs = [recs] if typeof recs is 'object' and JSON.stringify(recs) isnt '{}' and not Array.isArray recs
          if Array.isArray(recs) and recs.length
            res[fs._fn] = recs.length
            @waitUntil @index fun, recs

  else if typeof fn is 'function'
    if @S.name and @S.system and @headers['x-' + @S.name + '-system'] is @S.system
      @system = true
      authd = true # would this be sufficient or could original user be required too
    else
      authd = await @auth()
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
      else if fn._cache isnt false and not @refresh and (@request.method is 'GET' or (@request.method is 'POST' and @index._q @params)) and res = await @_cache() # this will return empty if nothing relevant was ever put in there anyway
        # how about caching of responses to logged in users, by param or header?
        @cached = 'cache'
        res = new Response res.body, res # no need to catch this for backend execution because cache function will never find anything on backend anyway
        res.headers.append 'x-' + @S.name + '-cached', 'cache' # this would leave any prior "index" value, for example. Or use .set to overwrite
        res.headers.delete 'x-' + @S.name + '-took'
      else
        res = await fn()
        @completed = true

    else
      # Random delay for https://en.wikipedia.org/wiki/Timing_attack https://www.owasp.org/index.php/Blocking_Brute_Force_Attacks#Finding_Other_Countermeasures
      @unauthorised = true
      await @sleep 200 * (1 + Math.random())
      res = status: 401 # not authorised
      @format = 'html' if @fn is 'svc.rscvd.supply' # quick workaround for demo
      if @format is 'html'
        res.body = await @auth()

  res = '' if (not res? or (typeof res is 'object' and res.status is 404)) and @url.replace('.ico','').replace('.gif','').replace('.png','').endsWith 'favicon'
  resp = if typeof res is 'object' and not Array.isArray(res) and typeof res.headers?.append is 'function' then res else await @_response res, fn
  if @scheduled or (@parts.length and @parts[0] not in ['log','status'] and @request.method not in ['HEAD', 'OPTIONS'] and res? and res isnt '')
    if @completed and fn._cache isnt false and resp.status is 200 and (typeof res isnt 'object' or Array.isArray(res) or res.hits?.total isnt 0) and (not fn._sheet or typeof res isnt 'number' or not @refresh)
      @_cache undefined, resp, fn._cache # fn._cache can be a number of seconds for cache to live, so pass it to cache to use if suitable
    @log()
  if not @completed and not @cached and not @unauthorised and not @scheduled and @S.pass and typeof @S.bg is 'string' and @request.method not in ['HEAD', 'OPTIONS']
    # TODO add a regular schedule to check logs for things that didn't complete, and set them to _bg by default so they don't keep timing out
    throw new Error()
  else
    return resp

P._response = (res, fn) -> # this provides a Response object. It's outside the main P.call so that it can be used elsewhere if convenient
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
          res = await @convert['json2' + @format] res, keys: fn?['_' + @format]?._qopts?.include ? fn?._qopts?.include
      @S.headers['Content-Type'] = if @format is 'html' then 'text/html; charset=UTF-8' else 'text/csv; charset=UTF-8'
    if typeof res isnt 'string'
      try res = JSON.stringify res, '', 2
    @S.headers['Content-Type'] ?= 'application/json; charset=UTF-8'
  try @S.headers['Content-Length'] ?= Buffer.byteLength res
  try @S.headers['x-' + @S.name + '-took'] = Date.now() - @started
  try @S.headers['x-' + @S.name + '-cached'] = @cached if @cached
  try
    return new Response res, {status: status, headers: @S.headers}
  catch
    return status: status, headers: @S.headers, body: res

P.src = {}
P.svc = {}
P.scripts = {}
