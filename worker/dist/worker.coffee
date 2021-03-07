
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
S.version ?= '5.2.5'
S.env ?= 'dev'
S.dev ?= S.env is 'dev'
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
  try console.log(S.version) if S.dev and S.bg isnt true # handy for CF edit UI debug to see if code has updated yet
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
  try
    @body = JSON.parse(@request.body) if @request.body.startsWith('{') or @request.body.startsWith('[')
    if typeof @body is 'object' and not Array.isArray @body
      @params[qp] ?= @body[qp] for qp of @body
  try @body ?= @request.body
  if @params.refresh
    @refresh = @params.refresh
    delete @params.refresh
  try
    @headers = {}
    @headers[hd[0]] = hd[1] for hd in [...@request.headers] # request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
  catch
    @headers = @request.headers # backend server passes a normal object
    if typeof @waitUntil isnt 'function'
      @waitUntil = (fn) -> 
        console.log 'waitUntil'
        return true
  try @rid = @headers['cf-ray'].slice(0, -4)
  # how / when to remove various auth headers before logging / matching cache?
  # e.g apikey, id, resume, token, access_token, email?
  try @id = @headers['x-id'] ? @headers.id ? @headers._id ? @params._id ? @params.id
  try @apikey = @headers['x-apikey'] ? @headers.apikey ? @params.apikey ? @params.apiKey
  delete @params.apikey if @params.apikey
  try @cookie = @headers.cookie
  if @request.url.indexOf('://') is -1
    @url = @request.url.split('?')[0].replace(/^\//,'').replace(/\/$/,'')
    @parts = if @url.length then @url.split('/') else []
    # there's no base to the URL passed on the server
  else
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
        if not indexed = await @index k.split('/')[0], (if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases})
          @log fn: r.split('/')[0].replace(/\_/g, '.'), msg: 'Could not save/create index', level: 'error'
        else
          @index k, r

  _return = (fn, n) =>
    # if fn._sheet is true, look for corresponding sheet value in setttings? Don't do it where fn._sheet is defined in case settings get overridden?
    fn._index ?= true if fn._sheet
    wp = fn._index or fn._kv or (fn._bg and @S.bg isnt true) # what about _async?
    if not wp and typeof fn is 'object' and not Array.isArray(fn) and typeof fn[@request.method] isnt 'function'
      return JSON.parse JSON.stringify fn
    else if not wp and not fn._kv and typeof fn isnt 'function'
      return fn
    else if not wp and not fn._kv and n.indexOf('.') is -1 or n.split('.').pop().indexOf('_') is 0 # don't wrap top-level or underscored methods
      return fn.bind @
    else
      _wrapped = () ->
        st = Date.now() # again, not necessarily going to be accurate in a workers environment
        rt = n.replace /\./g, '_'
        chd = false
        key = false
        bgd = false
        if (not fn._bg or @S.bg is true) and fn._index and ((@fn is n and @index._q @params) or (@fn isnt n and (arguments.length is 1 and @index._q(arguments[0]))) or (arguments.length is 2 and @index._q(arguments[1])))
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
        if not res? and (fn._bg or fn._sheet) and typeof @S.bg is 'string' and @S.bg.indexOf('http') is 0
          bu = @S.bg + '/' + n.replace(/\./g, '/') + if arguments.length and typeof arguments[0] is 'string' then arguments[0] else ''
          bup = if arguments.length and typeof arguments[0] is 'object' then {method: 'POST', body: arguments[0]} else if n is fn then {method: 'POST', body: @params} else {}
          if @S.name and @S.system
            bup.headers = {}
            bup.headers['x-' + S.name + '-system'] = @S.system
          try
            res = await @fetch bu, bup # does the worker timeout at 15s even if just waiting, not CPU time? test to find out. If so, race this and async it if necessary
            bgd = true
        if not res?
          # if it's an index function with a sheet setting, or a sheet param has been provided, what to do by default?
          if typeof fn is 'function' # it could also be an index or kv config object with no default function
            res = await (fn[@request.method] ? fn).apply @, arguments
          if not res? and fn._sheet # this should happen on background where possible, because above will have routed to bg if it was available
            res = await @src.google.sheets fn._sheet
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
        lg = fn: n, cached: (if chd then chd else undefined), bg: (if bg then bg else undefined), key: (if key then key else if chd and arguments.length then arguments[0].toLowerCase() else undefined)
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
    if @S.name and @S.system and @headers['x-' + S.name + '-system'] is @S.system
      authd = true # would this be sufficient or could original user be required too
    else
      authd = @auth() # check auth even if no function?
      @user = authd if typeof authd is 'object' and authd._id and authd.email
      if typeof fn._auth is 'function'
        authd = await fn._auth()
      else if fn._auth is true and @user? # just need a logged in user if true
        authd = true
      else if fn._auth # which should be a string... comma-separated, or a list
        # how to default to a list of the role groups corresponding to the URL route? empty list?
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
        resp = new Response res.body, res # no need to catch this for backend execution because cache functionwill never find anything on backend anyway
        resp.headers.append 'x-' + @S.name + '-cached', 'cache' # this would leave any prior "index" value, for example. Or use .set to overwrite
        resp.headers.delete 'x-' + @S.name + '-took'
        @log()
        return resp
      else if @S.bg is true # we're on the background server, no need to race a timeout
        res = await fn()
        @completed = true
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
      @_cache undefined, resp, fn._cache #.clone() # need to clone here? or is at cache enough? Has to be cached before being read and returned
    @log() # logging from the top level here should save the log to kv - don't log if unlog is present and its value matches a secret key?
  return resp

P._response = (res) ->
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
  
  if not @S.headers['Content-Type']?
    try res = JSON.stringify res, '', 2
    @S.headers['Content-Type'] = 'application/json; charset=UTF-8'
  try @S.headers['Content-Length'] ?= Buffer.byteLength res
  try @S.headers['x-' + @S.name + '-took'] = Date.now() - @started
  try @S.headers['x-' + @S.name + '-cached'] = @cached if @cached
  # TODO add formatting if the URL ended with .csv or something like that (or header requested particular format)
  try
    return new Response res, {status: status, headers: @S.headers}
  catch
    return status: status, headers: @S.headers, body: res

P.src = {}
P.svc = {}


# curl -X GET "https://api.lvatn.com/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
# curl -X GET "https://api.lvatn.com/auth?apikey=YOURAPIKEYHERE"

# store user record object in kv as user/:UID (value is stringified json object)
# store a map of email(s) to UID user/email/:EMAIL (or email hash) (value is a UID)
# and store a map of API keys as well, user/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
# store a login token at auth/token/:TOKEN (value is email, or maybe email hash) (autoexpire login tokens at 15mins 900s)
# and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about six months 15768000s, but rotate them on non-cookie use)

P.auth = (key, val) ->
  # TODO add a check for a system header that the workers can pass to indicate they're already authorised
  # should this be here and/or in roles, or in the main api file? and what does it return?
  try return true if @S.name and @S.system and @headers['x-' + S.name + '-system'] is @S.system
  
  #if key? and val?
  # if at least key provided directly, just look up the user
  # if params.auth, someone looking up the URL route for this acc. Who would have the right to see that?
  if typeof key is 'string'
    return await @kv 'user/' + key
  
  # TODO ensure this only does kv lookups (which cost money) when the necessary values are available
  # that way it can maybe just run on every request without impact if nothing provided
  if not @params.access_token? or not user = await @oauth()
    if @params.token and eml = await @kv 'auth/token/' + @params.token, '' # true causes delete after found
      if uid = await @kv 'user/email/' + eml
        user = await @kv 'user/' + uid # get the user record if it already exists
      user ?= await @auth._insert eml # create the user record if not existing, as this is the first token login attempt for this email address
    if not user and @apikey
      if uid = await @kv 'user/apikey/' + @apikey
        user = await @kv 'user/' + uid # no user creation if apikey doesn't match here - only create on login token above 
    if not user and (@params.resume? or @cookie) # accept resume on a header too?
      uid = @id
      if not uid and @params.email? # accept resume with email instead of id?
        uid = await @kv 'user/email/' + @params.email
      if not resume = @params.resume # login by resume token if provided in param or cookie
        try # check where is cookie?
          cookie = JSON.parse decodeURIComponent(@cookie).split((S.auth?.cookie?.name ? S.name ? 'n2') + "=")[1].split(';')[0]
          resume = cookie.resume
          uid = cookie.id
      if resume? and uid? and restok = await @kv 'auth/resume/' + uid + '/' + resume, (if @params.resume then '' else undefined) # delete if not a cookie resume
        user = await @kv 'user/' + uid

  if typeof user is 'object' and user._id
    # if 2fa is enabled, request a second form of ID (see below about implementing 2fa)

    # record the user login timestamp, and if login came from a service the user does not yet have a role in, add the service user role
    # who can add the service param?
    if @params.service and not user.roles?[@params.service]?
      upd = {}
      upd.roles = user.roles ? {}
      upd.roles[@params.service] = 'user'
      @kv 'user/' + user._id, upd, user # record the user login time?

    if @params.resume? or @params.token?
      # if a fresh login or resume token was used explicitly, provide a new resume token
      user.resume = @uid()
      @kv 'auth/resume/' + user._id + '/' + user.resume, Date.now(), 7890000 #15768000 # resume token lasts three months

    #if @auth.role 'root', @user
    #  lg = msg: 'Root login from ' + @request.headers['x-forwarded-for'] + ' ' + @request.headers['cf-connecting-ip'] + ' ' + @request.headers['x-real-ip']
    #  lg.notify = subject: lg.msg
    #  @log lg

  # if this is called with no variables, and no defaults, provide a count of users?
  # but then if logged in and on this route, what does it provide? the user account?
  return user


P.auth.token = (email, from, subject, text, html, template, url) ->
  email ?= @params.email ? ''
  from ?= S.auth?.from ? 'nobody@example.com'
  subject ?= S.auth?.subject ? 'Please complete your login'

  token = @uid 8
  url ?= (@params.url ? @request.url ? 'https://example.com').split('?')[0].replace('/token','') + '?token=' + token

  @kv 'auth/token/' + token, email, 900 # create a token that expires in 15 minutes
    
  if from and email
    # see old code for an attempt to add a gmail login button - if that has simplified since then, add it now
    sent = await @mail.send
      from: from
      to: email
      subject: subject
      text: text ? 'Your login code is:\r\n\r\n{{TOKEN}}\r\n\r\nor use this link:\r\n\r\n{{URL}}\r\n\r\nnote: this single-use code is only valid for 15 minutes.'
      html: html ? '<html><body><p>Your login code is:</p><p><b>{{TOKEN}}</b></p><p>or click on this link</p><p><a href=\"{{URL}}\">{{URL}}</a></p><p>note: this single-use code is only valid for 15 minutes.</p></body></html>'
      #template: template
      params: {token: token, url: url}
    return sent #sent?.data?.id ? sent?.id ? email
  else
    return token

# auth/role/:grl/:uid
# any logged in user can find out if any other user is in a role
P.auth.role = (grl, uid) ->
  grl ?= @params.role
  grl = @opts.auth if not grl? and typeof @opts?.auth is 'string'
  uid ?= @user
  if typeof grl is 'string' and grl.indexOf('/') isnt -1
    if not uid?
      uid = grl.split('/').pop()
      grl = grl.replace('/'+uid,'')
  user = if uid? and uid isnt @user?._id then @user(uid) else @user
  return false if not user?.roles?

  grl = [grl] if typeof grl is 'string'
  for g in grl
    g = g.replace('/','.')
    [group, role] = g.split '.'
    if not role?
      role = group
      group = '__global__'

    return 'owner' if group is user.id # user is owner on their own group
    return 'root' if 'root' in (user.roles.__global__ ? [])
    return role if role in (user.roles[group] ? [])

    if user.roles[group]?
      cascade = ['root', 'service', 'owner', 'super', 'admin', 'auth', 'bulk', 'delete', 'remove', 'create', 'insert', 'publish', 'put', 'draft', 'post', 'edit', 'update', 'user', 'get', 'read', 'info', 'public']
      if 0 < ri = cascade.indexOf role
        for rl in cascade.splice 0, ri
          return rl if rl in user.roles[group]

  return false


P.auth.roles = (user, grl, keep) ->
  user ?= @user ? @params.roles
  user = await @kv('user/' + user) if typeof user is 'string'

  # what about one logged in user acting on the roles route of another?
  [group, role] = grl.split '.'
  if not role?
    role = group
    group = '__global__'

  if role in user.roles?[group] ? []
    if keep?
      user.roles[group].splice user.roles[group].indexOf(role), 1
      @kv 'user/' + user._id, user
  else
    user.roles[group] ?= []
    user.roles.group.push role
    @kv 'user/' + user._id, user


P.auth.logout = (user) -> # how about triggering a logout on a different user account
  user ?= @user
  if user?
    @kv 'auth/resume/' + (if typeof user is 'string' then user else user._id), ''

# add a 2FA mechanism to auth (authenticator, sms...)
# https://stackoverflow.com/questions/8529265/google-authenticator-implementation-in-python/8549884#8549884
# https://github.com/google/google-authenticator
# http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/
#P.authenticator = () ->
# TODO if an authenticator app token is provided, check it within the 30s window
# delay responses to 1 per second to stop brute force attacks
# also need to provide the token/qr to initialise the authenticator app with the service
#  return false

# device fingerprinting was available in the old code but no explicit requirement for it so not added here yet
# old code also had xsrf tokens for FORM POSTs, add that back in if relevant




P.oauth = (token, cid) ->
  # https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  sets = {}
  token ?= @params.access_token
  if token
    try
      # we did also have facebook oauth in here, still in old code, but decided to drop it unless explicitly required again
      validate = await @http.post 'https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + token
      cid ?= S.svc[@params.service ? 'z']?.google?.oauth?.client?.id ? S.use?.google?.oauth?.client?.id
      if cid? and validate.data?.aud is cid
        ret = await @http.get 'https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + token
        if uid = await @kv 'user/email/' + ret.data.email
          if not user = await @kv 'user/' + uid
            user = await @auth._insert ret.data.email
        sets.google = {id:ret.data.id} if not user.google?
        if ret.data.name
          sets.name = ret.data.name if not user.name
        else if ret.data.given_name and not user.name
          sets.name = ret.data.given_name
          sets.name += ' ' + ret.data.family_name if ret.data.family_name
        sets.avatar = ret.data.picture if not user.avatar and ret.data.picture
  if user? and JSON.stringify(sets) isnt '{}'
    user = await @user.update user.id, sets
  return user
# the Oauth URL that would trigger something like this would be like:
# grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true'
# grl += '&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
# grl += '&state=' + state + '&redirect_uri=' + noddy.oauthRedirectUri + '&client_id=' + noddy.oauthGoogleClientId
# state would be something like Math.random().toString(36).substring(2,8) and would be sent and also kept for checking against the response
# the response from oauth login page would go back to current page and have a # with access_token= and state=
# NOTE as it is after a # these would only be available on a browser, as servers don't get the # part of a URL
# if the states match, send the access_token into the above method and if it validates then we can login the user


P.auth._insert = (key, val) ->
  if typeof key is 'string' and val?
    if val is ''
      key = key.replace('user/','') if key.startsWith 'user/'
      user = if @user?._id is key then @user else await @kv 'user/' + key
      try @auth.logout key
      try @kv('user/apikey/' + user.apikey, '-') if user.apikey?
      try @kv('user/email/' + user.email, '-') if user.email?
      @kv 'user/' + key, ''
    #else # update the user with the provided val
  else
    em = key if typeof key is 'string' and key.indexOf('@') isnt -1 and key.indexOf('.') isnt -1 # put this through a validator, either/both a regex and a service
    if not key? and this?.user?._id
      key = 'user/' + @user._id
    if key.indexOf('@') isnt -1
      key = await @kv 'user/email/' + key
    res = await @kv 'user/' + key
    if not res?
      if em
        u =
          email: em.trim() #store email here or not?
          apikey: @uid() # store the apikey here or not?
          profile: {}
        first = false # if no other user accounts yet
        u.roles = if first then {__global__: ['root']} else {}
        u.createdAt = Date.now()
        u._id = @uid()
        @kv 'user/apikey/' + apikey, u._id
        @kv 'user/email/' + email, u._id # or hash of email
        @kv 'user/' + u._id, u
        return u
      else
        return undefined
    else
      return undefined

P.auth._update = (r, user) ->
  user ?= r.auth # what about update a user other than the logged in one?
  if r.param and nu = @auth r.param
    a = '' # does the currently authorised user have permission to update the user being queried? if so, set user to nu
  if JSON.stringify(r.params) isnt '{}'
    user.profile ?= {}
    for p of r.params # normal user can update profile values
      user.profile[p] = pr[p]
    await @kv 'user/' + user.id, user
    return true # or return the updated user object?
  else
    return false



# https://developers.cloudflare.com/workers/runtime-apis/cache

# this is a cloudflare Cache implementation
# if an alternative has to be used, then write the alternative functions in a 
# different cache implementation, and add a method to swap P.cache to those functions
# yes, this could be done now, but if it never gets used then it's just premature optimisation
# if the cache isn't present this returns undefined and the main API code is written to continue 
# so it's an optional layer anyway
# top level API calls can cache, and any uses of fetch can cache directly too
# other methods can use this cache directly as well if they need to

# NOTE the cloudflare cache is only per region, not global. KV store is global (but only eventually consistent)

# https://community.cloudflare.com/t/how-long-does-the-basic-cloudflare-cdn-cache-things-for/85728
# https://support.cloudflare.com/hc/en-us/articles/218411427-What-does-edge-cache-expire-TTL-mean-#summary-of-page-rules-settings
# https://support.cloudflare.com/hc/en-us/articles/200168276

# https://developers.cloudflare.com/workers/examples/cache-api

P._cache = (request, response, age) ->
  if typeof age isnt 'number'
    age = if typeof @S.cache is 'number' then @S.cache else if @S.dev then 300 else 3600 # how long should default cache be?
  # age is max age in seconds until removal from cache (note this is not strict, CF could remove for other reasons)
  # request and response needs to be an actual Request and Response objects
  # returns promise wrapping the Response object
  if @S.cache is false or @S.bg is true # can change this if a backend cache mechanism is added later (prob not worthwhile)
    return undefined
  else
    try
      request ?= @request
      try
        url = request.url.toString()
        for h in ['refresh'] # should caches be keyed to apikey? what about headers? Do they affect caching?
          if url.indexOf(h + '=') isnt -1
            hp = new RegExp h + '=.*?&'
            url = url.replace hp, ''
          if url.indexOf('&' + h + '=') isnt -1
            url = url.split('&' + h + '=')[0] # it's the last param, remove from end
        cu = new URL url
    if request?
      try
        cu ?= new URL request.url
        # if request method is POST try changing to GET? and should any headers be removed?
        ck = new Request cu.toString(), request
        if not response? or response is ''
          rs = await caches.default.match ck
          if response is ''
            @waitUntil caches.default.delete ck
          return rs
        else
          # what about things like apikey, refresh and other params, headers not wanted in cache?
          # need to build a request object here, and include a Last-Modified header? or cacheTtl would just let it time out?
          # and what about overriding the method? Always do that here or allow it to be done before here?
          # it has to be a GET for it to be accepted by the CF cache
          # could use just the URL string as key (and then, which query params to consider, if any?)
          # but if using just the URL string how would the refresh timeout be checked?
          response = response.clone() # body of response can only be read once, so clone it
          rp = new Response response.body, response
          rp.headers.append "Cache-Control", "max-age=" + age
          @waitUntil caches.default.put ck, rp
      catch
        return undefined
    else
      return undefined


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



# write examples of how to do various things here

S.example ?= {}
S.example.example = 3
P.example = ->
  res = name: S.name, version: S.version, env: S.env, built: S.built
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  if S.dev
    try res.headers ?= @headers
    try res.request ?= @request
    try res.parts ?= @parts
    try res.params ?= @params
    try res.opts ?= @opts
  return res

P.example.restricted = () ->
  return hello: @user._id
P.example.restricted._auth = true

P.example.deep = ->
  res = {example: 'deep', request: @request, deeper: await @example.deep.deeper()}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  return res

P.example.deep.deeper = ->
  res = {hello: 'deeper'}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  try res.deepest = await @example.deep.deeper.deepest()
  return res

P.example.deep.deeper.deepest = ->
  res = {hello: 'deepest'}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  return res

# https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

P.fetch = (url, params) ->
  # TODO if asked to fetch a URL that is the same as the @url this worker served on, then needs to switch to a bg call if bg URL available
  if typeof url is 'object' and not params?
    params = url
    url = params.url
  try params ?= @copy @params
  params ?= {}
  if not url and params.url
    url = params.url
    delete params.url
  # if params is provided, and headers is in it, may want to merge with some default headers
  # see below for other things that can be set
  if params.username and params.password
    params.auth = params.username + ':' + params.password
    delete params.username
    delete params.password
  if url.split('//')[1].split('@')[0].indexOf(':') isnt -1
    params.auth = url.split('//')[1].split('@')[0]
    url = url.replace params.auth+'@', ''
  if params.auth
    params.headers ?= {}
    params.headers['Authorization'] = 'Basic ' + Buffer.from(params.auth).toString('base64') # should be fine on node
    delete params.auth
  for ct in ['data', 'content', 'json'] # where else might body content reasonably be?
    if params[ct]?
      params.body = params[ct]
      delete params[ct]
  if params.body?
    params.headers ?= {} # content-type is necessary for ES to accept, for example
    if not params.headers['Content-Type']? and not params.headers['content-type']?
      params.headers['Content-Type'] = if typeof params.body is 'object' then 'application/json' else 'text/plain'
    params.body = JSON.stringify(params.body) if typeof params.body in ['object', 'boolean', 'number'] # or just everything?
  console.log url
  if typeof url isnt 'string'
    return false
  else
    # if on the background server and not a worker, it will need node-fetch installed or an alternative to fetch must be used here
    _f = () =>
      if params.verbose
        verbose = true
        delete params.verbose
      else
        verbose = false
      try
        if url.indexOf('localhost') isnt -1
          # allow local https connections on backend server without check cert
          params.agent ?= new https.Agent rejectUnauthorized: false
      response = await fetch url, params
      console.log response.status # status code can be found here
      if verbose
        return response
      else
        # json() # what if there is no json or text? how to tell? what other types are there? will json also always be presented as text?
        # what if the method is a POST, or the response is a stream?
        # does it make any difference if it can all be found in text() and converted here anyway?
        ct = response.headers.get('content-type')
        if typeof ct is 'string' and ct.toLowerCase().indexOf('json') isnt -1
          r = await response.json()
        else
          r = await response.text()
        if response.status is 404
          return undefined
        else if response.status >= 400
          console.log r
          return status: response.status
        else
          return r
    '''if params.timeout
      params.retry ?= 1
      params.timeout = 30000 if params.timeout is true
    if params.retry
      params.retry = 3 if params.retry is true
      opts = retry: params.retry
      delete params.retry
      for rk in ['pause', 'increment', 'check', 'timeout']
        if params[rk]?
          opts[rk] = params[rk]
          delete params[rk]
      res = @retry.call this, _f, [url, params], opts
    else'''
    res = await _f()
    try
      res = res.trim()
      res = JSON.parse(res) if res.indexOf('[') is 0 or res.indexOf('{') is 0
    return res


'''
# https://stackoverflow.com/questions/46946380/fetch-api-request-timeout/46946573#46946573
timeout = (ms, promise) ->
  return new Promise (resolve, reject) =>
    timer = setTimeout () =>
      reject new Error 'TIMEOUT'
    , ms
    promise
      .then value =>
        clearTimeout timer
        resolve value
      .catch reason =>
        clearTimeout timer
        reject reason

timeout 1000, fetch '/hello'
  .then (response) ->
    r = response # do something with response
  .catch (error) ->
    e = error # do something with error
    

P.proxy = (url, params={}) ->
  if typeof url is 'object'
    params = url
    url = undefined
  params.proxy ?= S.proxy
  return P.fetch url, params


  response = await fetch(url, # how to set timeout on fetch
    method: method
    body: body
    #cf:
    #  mirage: true
    #  polish: "lossy"
    #  cacheTtl: ttl ?= 300
    #  cacheTtlByStatus:
    #    "200-299": ttl
    #    "300-399": 120
    #    "400-499": 60
    #    "500-599": 0
    headers:
      "Content-Type": type
      "User-Agent": "n2/4.0.1")

# Send a Http request and get a Buffer response.
export buffer = (url, {body, ttl, base64} = {}) ->
  base64 ?= true
  request(url,
    ttl: ttl,
    body: body
    parser: ((response) ->
      response = await response.arrayBuffer()
      if base64
        response = response.asBase64()
      response))
'''
S.log ?= {}

# it would also be good to log every fetch, and what was sent with it too, although if it was a big file or something like that, then not that
# what about a param to pass to avoid logging?

P.log = (msg) ->
  store = not msg? # an empty call to log stores everything in the _logs list

  if typeof msg is 'string'
    if msg.indexOf('/') isnt -1 and msg.indexOf(' ') is -1
      msg = fn: msg
    else
      msg = msg: msg
  else if Array.isArray msg
    @_logs.push(l) for l in msg
    msg = undefined

  if not msg?
    if @parts.length is 1 and @parts[0] is 'log' # should a remote log be allowed to send to a sub-route URL as an ID? maybe with particular auth?
      # receive a remote log
      msg = if typeof @body is 'object' then {logs: @body} else @params # bunch of logs sent in as POST body, or else just params
      msg.fn ?= @params.log # the fn, if any, would be in params.log (because @fn would just be log)
    msg ?= {}
    try
      msg.request =
        url: @request.url
        method: @request.method
        body: @request.bodyUsed
    try
      msg.request.cf =
        colo: @request.cf.colo
        country: @request.cf.country
    try
      msg.request.headers =
        ip: @headers['x-real-ip']
        'user-agent': @headers['user-agent']
        referer: @headers.referer
    try
      msg.fn ?= @fn
      msg.params = @params
      msg.refresh = @refresh
      msg.parts = @parts
      msg.completed = @completed
      msg.cached = @cached
    try msg.apikey = @headers.apikey? or @headers['x-apikey']? # only record if apikey was provided or not
    try msg.user = @user?._id

  if store
    msg.logs ?= []
    if Array.isArray(this?._logs) and @_logs.length
      for l in @_logs
        #msg.msg ?= l.msg
        msg.alert ?= l.alert
        msg.notify ?= l.notify
        msg.logs.push l
    msg.createdAt ?= Date.now()
    msg.name ?= S.name
    msg.version ?= S.version
    msg.env ?= S.env
    try
      msg.started = @started
      msg.took = Date.now() - @started
    msg._id = 'log/' + (@rid ? @uid())
    @kv msg
  else
    @_logs.push msg

  if S.log is false or S.bg is true # is this useful?
    console.log 'Server not logging:'
    console.log msg


P.log.schedule = () ->
  # this should become _schedule but for now is not so I can manually trigger it for testing
  # define what to do on a scheduled trigger
  # grab every log in the kv store and throw them to the index
  # but for now, just delete them
  @kv._each 'log', ''


'''
P.add 'mail/feedback/:token',
  get: () ->
    try
      from = this.queryParams.from ? P.settings.mail?.feedback?[this.urlParams.token]?.from ? "sysadmin@cottagelabs.com"
      to = P.settings.mail?.feedback?[this.urlParams.token]?.to
      service = P.settings.mail?.feedback?[this.urlParams.token]?.service
      subject = P.settings.mail?.feedback?[this.urlParams.token]?.subject ? "Feedback"
    if to?
      P.mail.send
        service: service
        from: from
        to: to
        subject: subject
        text: this.queryParams.content
    return {}


level/loglevel
group (default to whatever is after svc or src, or just part 0)
notify/alert

P.log = (opts, fn, lvl='debug') ->

    loglevels = ['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off']
    loglevel = P.settings.log?.level ? 'all'
    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level
      if opts.notify and P.settings.log?.notify
        try
          os = @copy opts
        catch
          os = opts
        Meteor.setTimeout (() -> P.notify os), 100

      for o of opts
        if not opts[o]?
          delete opts[o]
        else if typeof opts[o] isnt 'string' and not _.isArray opts[o]
          try
            opts[o] = JSON.stringify opts[o]
          catch
            try
              opts[o] = opts[o].toString()
            catch
              delete opts[o]

      if loglevels.indexOf(loglevel) <= loglevels.indexOf 'debug'
        console.log opts.msg if opts.msg

  if typeof notify is 'string'
    if note.indexOf '@' isnt -1
      note = to: note

  if typeof note is 'object'
    note.text ?= note.msg ? opts.msg
    note.subject ?= P.settings.name ? 'API log message'
    note.from ?= P.settings.log?.from ? 'alert@cottagelabs.com'
    note.to ?= P.settings.log?.to ? 'mark@cottagelabs.com'
    P.mail.send note




P.ping = (url,shortid) ->
  return false if not url?
  url = 'http://' + url if url.indexOf('http') isnt 0
  if (not shortid? or shortid is 'random') and spre = pings.find {url:url,redirect:true}
    return spre._id
  else
    obj = {url:url,redirect:true}
    if shortid? and shortid isnt 'random'
      while already = pings.get shortid
        shortid += Random.hexString(2)
      obj._id = shortid
    return pings.insert obj

# craft an img link and put it in an email, if the email is viewed as html it will load the URL of the img,
# which actually hits this route, and allows us to record stuff about the event

# so for example for oabutton where this was first created for, an image url like this could be created,
# with whatever params are required to be saved, in addition to the nonce.
# On receipt the pinger will grab IP and try to retrieve location data from that too:
# <img src="https://api.cottagelabs.com/ping/p.png?n=<CURRENTNONCE>service=oabutton&id=<USERID>">

P.ping.png = () ->
  if not P.settings.ping?.nonce? or this.queryParams.n is P.settings.ping.nonce
    data = this.queryParams
    delete data.n
    data.ip = this.request.headers['x-forwarded-for'] ? this.request.headers['cf-connecting-ip'] ? this.request.headers['x-real-ip']
    data.forwarded = this.request.headers['x-forwarded-for']
    try
      res = HTTP.call 'GET', 'http://ipinfo.io/' + data.ip + (if P.settings?.use?.ipinfo?.token? then '?token=' + P.settings.use.ipinfo.token else '')
      info = JSON.parse res.content
      data[k] = info[k] for k of info
      if data.loc
        try
          latlon = data.loc.split(',')
          data.lat = latlon[0]
          data.lon = latlon[1]
    pings.insert data
  img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8BQDwAEgAF/posBPQAAAABJRU5ErkJggg==', 'base64');
  if this.queryParams.red
    img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=', 'base64')
  this.response.writeHead 200,
    'Content-disposition': "inline; filename=ping.png"
    'Content-type': 'image/png'
    'Content-length': img.length
    'Access-Control-Allow-Origin': '*'

    this.response.end img

P.add 'ping/:shortid',
  get: () ->
    if this.urlParams.shortid is 'random' and this.queryParams.url
      # may want to disbale this eventually as it makes it easy to flood the server, if auth is added on other routes
      return P.ping this.queryParams.url, this.urlParams.shortid
    else if exists = pings.get(this.urlParams.shortid) and exists.url?
        count = exists.count ? 0
        count += 1
        pings.update exists._id, {count:count}
        return
          statusCode: 302
          headers:
            'Content-Type': 'text/plain'
            'Location': exists.url
          body: 'Location: ' + exists.url
    else return 404
  put:
    authRequired: true
    action: () ->
      # certain user groups can overwrite a shortlink
      # TODO: overwrite a short link ID that already exists, or error out
  post: () ->
    return P.ping (this.request.body.url ? this.queryParams.url), this.urlParams.shortid
  delete:
    #authRequired: true
    action: () ->
      if exists = pings.get this.urlParams.shortid
        pings.remove exists._id
        return true
      else
        return 404
'''

P.mail = (opts) ->
  return {} if S.mail?.disabled
  
  if not opts? and (this?.params? or this?.opts?)
    opts = this?.params ? {}
    opts[o] = @params[o] for o of @params
    
  if not opts.text and not opts.html
    opts.text = opts.content ? opts.body ? ""
  delete opts.content

  try
    for s in ['subject', 'text', 'html', 'template']
      if opts[s]?
        for p of opts.params
          opts[s] = opts[s].replace('{{' + p.toUpperCase() + '}}', opts.params[p])
      # this should be stand-alone called method somewhere...
      # should be case insensitive, and remove multiples, not just first occurrence
      # and do a delete of any template values that could not be replaced

  # can also take opts.headers

  # also takes opts.attachments, but not required. Should be a list of objects as per
  # how do attachments work if not on mail_url, can they be sent by API?
  # https://github.com/nodemailer/mailcomposer/blob/v4.0.1/README.md#attachments

  ms = if opts.svc? and S.svc?[opts.svc]?.mail? then S.svc[opts.svc].mail else S.mail
  opts.from ?= ms.from
  opts.to ?= ms.to
  delete opts.svc
  delete opts.template # what to actually do with this now...
  delete opts.params

  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages'
  opts.to = opts.to.join(',') if Array.isArray opts.to
  f = this?.fetch ? P.fetch
  return await f url, {method: 'POST', body: opts, headers: {auth:'api:'+ms.apikey}}

P.mail.validate = (e, apikey) ->
  apikey ?= S.mail?.pubkey
  e ?= this?.params?.email
  if typeof e is 'string' and typeof apikey is 'string'
    # also add a simple regex validator if mailgun validation is not available - and cache the validations
    f = this?.fetch ? P.fetch
    return await f 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e.params.email) + '&api_key=' + apikey





P.puppet = _bg: true

S.mail ?= {}
S.mail.from ?= "alert@cottagelabs.com"
S.mail.to ?= "mark@cottagelabs.com"

S.src.google ?= {}
try S.src.google.secrets = JSON.parse SECRETS_GOOGLE

# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

_xref_hdr = {'User-Agent': S.name + '; mailto:' + S.mail?.to}

P.src.crossref = {}

P.src.crossref.journals = (issn) ->
  # by being an index, should default to a search of the index, then run this query if not present, which should get saved to the index
  issn ?= this?.params?.journals ? this?.params?.issn
  #url = 'https://api.crossref.org/journals?query=' + issn
  url = 'https://dev.lvatn.com/use/crossref/journals/' + issn
  res = await @fetch url #, {headers: _xref_hdr} # TODO check how headers get sent by fetch
  #return if res?.message?['total-results']? and res.message['total-results'].length then res.message['total-results'][0] else undefined
  return if res?.ISSN? then res else undefined

P.src.crossref.journals._index = true
P.src.crossref.journals._key = 'ISSN'

P.src.crossref.works = (doi) ->
  if this?.params?.title or (typeof doi is 'object' and doi.title?) or (typeof doi is 'string' and doi.indexOf('10.') isnt 0)
    res = @src.crossref.works._title if this?.params?.title then @params.title else if typeof doi is 'object' then doi.title else doi
  else
    # a search of an index of works - and remainder of route is a DOI to return one record
    doi ?= this?.params?.works ? this?.params?.doi
    if typeof doi is 'string'
      doi = doi.split('://')[1] if doi.indexOf('http') is 0
      doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
  
      # for now just get from old system instead of crossref
      #url = 'https://api.crossref.org/works/' + doi
      url = 'https://dev.lvatn.com/use/crossref/works/' + doi
      res = await @fetch url #, {headers: _xref_hdr}

  if res?.DOI? #res?.message?.DOI?
    rec = res #res.data.message
    delete rec.relation
    delete rec.reference # is there anything worth doing with these? In some cases they are extremely long, enough to cause problems in the index
    delete rec.abstract
    #if typeof rec.abstract is 'string' and this?.convert?.html2txt?
    #  rec.abstract = @convert.html2txt rec.abstract
    return rec
  else
    return undefined

P.src.crossref.works._kv = false
P.src.crossref.works._index = settings: number_of_shards: 9
P.src.crossref.works._key = 'DOI'

P.src.crossref.works._title = (title) ->
  title ?= @params.title
  return undefined if typeof title isnt 'string'
  
  qr = 'title.exact:"' + title + '"'
  if title.indexOf(' ') isnt -1
    qr += ' OR ('
    f = true
    for t in title.split ' '
      if t.length > 2
        if f is true
          f = false
        else
          qr += ' AND '
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")'
    qr += ')'

  url = 'https://dev.lvatn.com/use/crossref/works?q=' + qr
  res = await @fetch url
  #res = @src.crossref.works qr

  possible = false
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
  for r in res?.hits?.hits ? []
    rec = r._source
    rt = (if typeof rec.title is 'string' then rec.title else rec.title[0]).toLowerCase()
    if rec.subtitle?
      st = (if typeof rec.subtitle is 'string' then rec.subtitle else rec.subtitle[0]).toLowerCase()
      rt += ' ' + st if typeof st is 'string' and st.length and st not in rt
    rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
    if (ltitle.indexOf(rt) isnt -1 or rt.indexOf(ltitle) isnt -1) and ltitle.length/rt.length > 0.7 and ltitle.length/rt.length < 1.3
      matches = true
      for k of metadata
        if k not in ['citation','title'] and typeof metadata[k] in ['string','number']
          matches = not fr[k]? or typeof fr[k] not in ['string','number'] or fr[k].toLowerCase() is metadata[k].toLowerCase()
      if matches
        if rec.type is 'journal-article'
          return if format then API.use.crossref.works.format(rec) else rec
        else if possible is false or possible.type isnt 'journal-article' and rec.type is 'journal-article'
          possible = rec

  return if possible is false then undefined else possible


# and need the code that builds the index and keeps it up to date
# and someting to trigger a load each day for example
# probably requires a cron schedule to read some kind of setting or KV of last-updated indexes, and their update schedule
# doing the regular index update will probably be a long-running job, so needs to be triggered but run on the backend machine


# Europe PMC client
# https://europepmc.org/RestfulWebService
# https://www.ebi.ac.uk/europepmc/webservices/rest/search/
# https://europepmc.org/Help#fieldsearch

# GET https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:10.1007/bf00197367&resulttype=core&format=json
# default page is 1 and default pageSize is 25
# resulttype lite is smaller, lacks so much metadata, no mesh, terms, etc
# open_access:y added to query will return only open access articles, and they will have fulltext xml available at a link like the following:
# https://www.ebi.ac.uk/europepmc/webservices/rest/PMC3257301/fullTextXML
# can also use HAS_PDF:y to get back ones where we should expect to be able to get a pdf, but it is not clear if those are OA and available via eupmc
# can ensure a DOI is available using HAS_DOI
# can search publication date via FIRST_PDATE:1995-02-01 or FIRST_PDATE:[2000-10-14 TO 2010-11-15] to get range

P.src.epmc = (qrystr, from, size) ->
  qrystr = 'DOI:' + qrystr if qrystr.indexOf('10.') is 0 and qrystr.indexOf(' ') is -1 and qrystr.split('/').length is 2 
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '%20sort_date:y&resulttype=core&format=json'
  url += '&pageSize=' + size if size? #can handle 1000, have not tried more, docs do not say
  url += '&cursorMark=' + from if from? # used to be a from pager, but now uses a cursor
  ret = {}
  res = await @fetch url
  ret.total = res.hitCount
  ret.data = res.resultList?.result ? []
  ret.cursor = res.nextCursorMark
  return ret

P.src.epmc.pmid = (ident) ->
  res = @src.epmc 'EXT_ID:' + ident + ' AND SRC:MED'
  return if res.total then res.data[0] else undefined

P.src.epmc.pmc = (ident) ->
  res = @src.epmc 'PMCID:PMC' + ident.toLowerCase().replace 'pmc', ''
  return if res.total then res.data[0] else undefined

P.src.epmc.title = (title) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  res = @src.epmc 'title:"' + title + '"'
  return if res.total then res.data[0] else undefined

P.src.epmc.licence = (pmcid, rec, fulltext) ->
  maybe_licence
  res = @src.epmc('PMC' + pmcid.toLowerCase().replace('pmc','')) if pmcid and not rec
  if res?.total > 0 or rec or fulltext
    rec ?= res.data[0]
    pmcid = rec.pmcid if not pmcid and rec
    if rec.license
      licinapi = {licence: rec.license,source:'epmc_api'}
      licinapi.licence = licinapi.licence.replace(/ /g,'-') if licinapi.licence.indexOf('cc') is 0
      return licinapi
      
    fulltext = @src.epmc.xml(pmcid) if not fulltext and pmcid
    if fulltext isnt 404 and typeof fulltext is 'string' and fulltext.indexOf('<') is 0 and @svc.lantern?
      licinperms = @svc.lantern.licence undefined,undefined,fulltext,'<permissions>','</permissions>'
      if licinperms.licence?
        licinperms.source = 'epmc_xml_permissions'
        return licinperms

      licanywhere = @svc.lantern.licence undefined,undefined,fulltext
      if licanywhere.licence?
        licanywhere.source = 'epmc_xml_outside_permissions'
        return licanywhere

      if fulltext.indexOf('<permissions>') isnt -1
        maybe_licence = {licence:'non-standard-licence',source:'epmc_xml_permissions'}

    if false #pmcid and not noui and @svc?.lantern?.licence?
      # TODO need a way to rate limit and run puppeteer
      url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
      pg = P.job.limit 3000, 'P.http.puppeteer', [url], "EPMCUI"
      if typeof pg is 'string'
        try licsplash = P.service.lantern.licence url, false, pg
        if licsplash?.licence?
          licsplash.source = 'epmc_html'
          return licsplash

    return maybe_licence ? false
  else
    return false

P.src.epmc.xml = (pmcid) ->
  pmcid = pmcid.toLowerCase().replace('pmc','') if pmcid
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/PMC' + pmcid + '/fullTextXML'
  r = await @fetch url
  return r.content

P.src.epmc.aam = (pmcid, rec, fulltext, noui) ->
  if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
    return {aam:true,info:'fulltext'}
  else
    # if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    #rec = @src.epmc.search('PMC' + pmcid.toLowerCase().replace('pmc',''))?.data?[0] if pmcid and not rec
    pmcid ?= rec?.pmcid
    if pmcid
      fulltext = @src.epmc.xml pmcid
      if typeof fulltext is 'string' and fulltext.indexOf('pub-id-type=\'manuscript\'') isnt -1 and fulltext.indexOf('pub-id-type="manuscript"') isnt -1
        resp = {aam:true,info:'fulltext'}
        return resp
      else if false #not noui
        url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc','')
        pg = P.job.limit 3000, 'P.http.puppeteer', [url], "EPMCUI"
        if pg is 404
          resp = {aam:false,info:'not in EPMC (404)'}
          return resp
        else if pg is 403
          return {info: 'EPMC blocking access, AAM status unknown'}
        else if typeof pg is 'string'
          s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal'
          s2 = 'Author manuscript; available in PMC'
          s3 = 'logo-nihpa.gif'
          s4 = 'logo-wtpa2.gif'
          if pg.indexOf(s1) isnt -1 or pg.indexOf(s2) isnt -1 or pg.indexOf(s3) isnt -1 or pg.indexOf(s4) isnt -1
            resp = {aam:true,info:'splashpage'}
            return resp
          else
            resp = {aam:false,info:'EPMC splashpage checked, no indicator found'}
            return resp
        else if pg?
          return {info: 'EPMC was accessed but aam could not be decided from what was returned'}
        else
          return {info: 'EPMC was accessed nothing was returned, so aam check could not be performed'}
  return {aam:false,info:''}


# https://developers.google.com/custom-search/json-api/v1/overview#Pricing
# note technically meant to be targeted to a site but can do full search on free tier
# free tier only up to 100 queries a day. After that, $5 per 1000, up to 10k
# has to come from registered IP address
P.src.google = (q, id, key) ->
	q ?= this?.params?.q ? this?.params?.google
	id ?= S.src.google?.secrets?.search?.id
	key ?= S.src.google?.secrets?.search?.key
	if q and id and key
		url = 'https://www.googleapis.com/customsearch/v1?key=' + key + '&cx=' + id + '&q=' + q
		return await @fetch url
	else
		return {}

P.src.google.sheets = (opts) ->
	# expects a google sheet ID or a URL to a google sheets feed in json format
	# NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
	opts ?= this?.params ? {}
	opts = {sheetid: opts} if typeof opts is 'string'
	if (opts.sheets? or opts.sheet?) and not opts.sheetid?
		opts.sheetid = opts.sheet ? opts.sheets
		delete opts.sheet
		delete opts.sheets
	values = []
	if not opts.sheetid
		return values
	else if opts.sheetid.indexOf('http') is 0
		url = opts.sheetid
	else
		opts.sheetid = opts.sheetid.split('/spreadsheets/d/')[1].split('/')[0] if opts.sheetid.indexOf('/spreadsheets/d/') isnt -1
		opts.sheet ?= 'default' # or else a number, starting from 1, indicating which sheet in the overall sheet to access
		url = 'https://spreadsheets.google.com/feeds/list/' + opts.sheetid + '/' + opts.sheet + '/public/values?alt=json'

	g = await @fetch url
	for l of g.feed.entry
		val = {}
		for k of g.feed.entry[l]
			try val[k.replace('gsx$','')] = g.feed.entry[l][k].$t if k.indexOf('gsx$') is 0
		values.push val

	return values

P.src.google.sheets._bg = true


# https://developers.google.com/hangouts/chat
# NOTE this will need oauth configuration for a full bot. For now just a web hook
# https://developers.google.com/hangouts/chat/how-tos/webhooks	
# pradm dev "pradm alert" google chat webhook
P.src.google.chat = (params, url) ->
	params ?= @params
	headers = "Content-Type": 'application/json; charset=UTF-8' # any other possible headers?
	data = method: 'POST', headers: headers, body: text: decodeURIComponent params.text ? params.msg ? params.body ? ''
	url ?= @S.src.google?.secrets?.chat # should url be allowed on params? doesn't strictly need to be secret, the key and token it uses only work for the webhook
	if data.body.text and url?
		return @fetch url, data
	else
		return undefined


'''
# docs:
# https://developers.google.com/places/web-service/autocomplete
# example:
# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>


# TODO add old deprecated google finance API, if useful for anything. Runs 15 mins delay
# see http://finance.google.com/finance/info?client=ig&q=NASDAQ:AAPL
# which runs pages lik https://finance.yahoo.com/quote/AAPL/profile


# https://developers.google.com/knowledge-graph/
# https://developers.google.com/knowledge-graph/reference/rest/v1/
API.use.google.knowledge.retrieve = (mid,types) ->
	exists = API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve'
	return exists if exists
	u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=1&ids=' + mid
	if types
		types = types.join('&types=') if typeof types isnt 'string' # are multiple types done by comma separation or key repetition?
		u += '&types=' + types
	ret = {}
	try
		res = API.http.proxy 'GET', u, true
		ret = res.data.itemListElement[0].result
		ret.score = res.data.itemListElement[0].resultScore
	if not _.isEmpty ret
		API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve', ret
	return ret

API.use.google.knowledge.search = (qry,limit=10,refresh=604800000) -> # default 7 day cache
	u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=' + limit + '&query=' + encodeURIComponent qry
	API.log 'Searching google knowledge for ' + qry

	checksum = API.job.sign qry
	exists = API.http.cache checksum, 'google_knowledge_search', undefined, refresh
	return exists if exists

	res = API.http.proxy('GET',u,true).data
	try API.http.cache checksum, 'google_knowledge_search', res
	return res

API.use.google.knowledge.find = (qry) ->
	res = API.use.google.knowledge.search qry
	try
		return res.itemListElement[0].result #could add an if resultScore > ???
	catch
		return undefined

# https://cloud.google.com/natural-language/docs/getting-started
# https://cloud.google.com/natural-language/docs/basics
API.use.google.cloud.language = (content, actions=['entities','sentiment'], auth) ->
	actions = actions.split(',') if typeof actions is 'string'
	return {} if not content?
	checksum = API.job.sign content, actions
	exists = API.http.cache checksum, 'google_language'
	return exists if exists

	lurl = 'https://language.googleapis.com/v1/documents:analyzeEntities?key=' + API.settings.use.google.serverkey
	document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}
	result = {}
	if 'entities' in actions
		try result.entities = API.http.proxy('POST',lurl,{data:document,headers:{'Content-Type':'application/json'}},true).data.entities
	if 'sentiment' in actions
		try result.sentiment = API.http.proxy('POST',lurl.replace('analyzeEntities','analyzeSentiment'),{data:document,headers:{'Content-Type':'application/json'}},true).data
	API.http.cache(checksum, 'google_language', result) if not _.isEmpty result
	return result

# https://cloud.google.com/translate/docs/quickstart
API.use.google.cloud.translate = (q, source, target='en', format='text') ->
	# ISO source and target language codes
	# https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
	return {} if not q?
	checksum = API.job.sign q, {source: source, target: target, format: format}
	exists = API.http.cache checksum, 'google_translate'
	return exists if exists
	lurl = 'https://translation.googleapis.com/language/translate/v2?key=' + API.settings.use.google.serverkey
	result = API.http.proxy('POST', lurl, {data:{q:q, source:source, target:target, format:format}, headers:{'Content-Type':'application/json'}},true)
	if result?.data?.data?.translations
		res = result.data.data.translations[0].translatedText
		API.http.cache(checksum, 'google_language', res) if res.length
		return res
		#return result.data.data
	else
		return {}



API.use.google.places.autocomplete = (qry,location,radius) ->
	url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' + qry + '&key=' + API.settings.use.google.serverkey
	url += '&location=' + location + '&radius=' + (radius ? '10000') if location?
	try
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}

API.use.google.places.place = (id,qry,location,radius) ->
	if not id?
		try
			results = API.use.google.places.autocomplete qry,location,radius
			id = results.predictions[0].place_id
		catch err
			return {status:'error', error: err}
	url = 'https://maps.googleapis.com/maps/api/place/details/json?placeid=' + id + '&key=' + API.settings.use.google.serverkey
	try
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}

API.use.google.places.url = (qry) ->
	try
		results = API.use.google.places.place undefined,qry
		return {data: {url:results.result.website.replace('://','______').split('/')[0].replace('______','://')}}
	catch err
		return {status:'error', error: err}

API.use.google.places.nearby = (params={}) ->
	url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
	params.key ?= API.settings.use.google.serverkey
	url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
	try
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}

API.use.google.places.search = (params) ->
	url = 'https://maps.googleapis.com/maps/api/place/textsearch/json?'
	params.key ?= API.settings.use.google.serverkey
	url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
	try
		return API.http.proxy('GET',url,true).data
	catch err
		return {status:'error', error: err}



API.use.google.sheets.api = {}
# https://developers.google.com/sheets/api/reference/rest
API.use.google.sheets.api.get = (sheetid, opts={}) ->
	opts = {stale:opts} if typeof opts is 'number'
	opts.stale ?= 3600000
	opts.key ?= API.settings.use.google.serverkey
	try
		sheetid = sheetid.split('/spreadsheets/d/')[1].split('/')[0] if sheetid.indexOf('/spreadsheets/d/') isnt -1
		url = 'https://sheets.googleapis.com/v4/spreadsheets/' + sheetid
		url += '/values/' + opts.start + ':' + opts.end if opts.start and opts.end
		url += '?key=' + opts.key
		API.log 'Getting google sheet via API ' + url
		g = HTTP.call 'GET', url
		return g.data ? g
	catch err
		return err

# auth for sheets interactions that makes changes is complex, requiring oauth and an email account to be registered to the sheet, it seems
# https://developers.google.com/sheets/api/guides/authorizing
# https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/append
# https://developers.google.com/identity/protocols/oauth2
# https://developers.google.com/sheets/api/quickstart/nodejs#step_3_set_up_the_sample
# https://cloud.google.com/apigee/docs/api-platform/security/oauth/access-tokens
# https://docs.wso2.com/display/IntegrationCloud/Get+Credentials+for+Google+Spreadsheet
# https://help.gooddata.com/doc/en/building-on-gooddata-platform/data-preparation-and-distribution/additional-data-load-reference/data-load-tutorials/load-data-from-google-spreadsheets-via-google-api
# https://isd-soft.com/tech_blog/accessing-google-apis-using-service-account-node-js/
API.use.google.sheets.api.values = (sheetid, opts={}) ->
	opts.start ?= 'A1'
	if not opts.end?
		sheet = if typeof sheetid is 'object' then sheetid else API.use.google.sheets.api.get sheetid, opts
		opts.sheet ?= 0 # could also be the ID or title of a sheet in the sheet... if so iterate them to find the matching one
		rows = sheet.sheets[opts.sheet].properties.gridProperties.rowCount
		cols = sheet.sheets[opts.sheet].properties.gridProperties.columnCount
		opts.end = ''
		ls = Math.floor cols/26
		opts.end += (ls + 9).toString(36).toUpperCase() if ls isnt 0
		opts.end += (cols + 9-ls).toString(36).toUpperCase()
		opts.end += rows
	values = []
	try
		keys = false
		res = API.use.google.sheets.api.get sheetid, opts
		opts.keys ?= 0 # always assume keys? where to tell which row to get them from? 0-indexed or 1-indexed or named?
		keys = opts.keys if Array.isArray opts.keys
		for s in res.values
			if opts.keys? and keys is false
				keys = s
			else
				obj = {}
				for k of keys
					try
						obj[keys[k]] = s[k] if s[k] isnt ''
				values.push(obj) if not _.isEmpty obj
	return values
	
'''
S.src.microsoft ?= {}
try S.src.microsoft.secrets = JSON.parse SECRETS_MICROSOFT

P.src.microsoft = {}

# https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
# annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
# and it seems the bing UI is sometimes more accurate
P.src.microsoft.bing = (q, key) ->
  q ?= this?.params?.bing ? this?.params?.q ? this?.params?.query
  key ?= S.src.microsoft?.secrets?.bing?.key
  url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?mkt=en-GB&count=20&q=' + q
  res = await @fetch url, {headers: {'Ocp-Apim-Subscription-Key': key}} # TODO check how to pass the key header with fetch - and set a long cache time on it
  if res?.webPages?.value
    return {total: res.data.webPages.totalEstimatedMatches, data: res.data.webPages.value}
  else
    return {total: 0, data: []}


# https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
# We get files via MS Azure dump and run an import script. Fields we get are:
# 'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate'],
# 'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate'],
# 'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
# of about 49k journals about 9 are dups, 37k have ISSN. 32k were already known from other soruces. Of about 250m papers, about 99m have DOIs
P.src.microsoft.graph = (q) ->
  # NOTE: although there are about 250m papers only about 90m have JournalId - the rest could be books, etc. Import them all?
  _append = (rec) ->
    if rec.JournalId and j = @src.microsoft.graph.journal rec.JournalId
      rec.journal = j
    #if ma = @src.microsoft.graph.abstract rec.PaperId
    #  rec.abstract = ma
    #rec.relation = @src.microsoft.graph._relations rec.PaperId, false, false
    return rec

  q ?= @params.graph ? @params.doi ? @params.title ? @params
  q = q.toString() if typeof q is 'number' # an MS ID like 2517073914 may turn up as number, if so convert to string
  if typeof q is 'string' and q.indexOf('/') isnt -1 and q.indexOf('10.') is 0 and paper = @src.microsoft.graph.paper 'Doi.exact:"' + q + '"'
    return _append paper
  else if typeof q is 'string' and q.indexOf(' ') is -1 and q.length is 10 and paper = @src.microsoft.graph.paper q
    return _append paper
  else if typeof q is 'string' and q.indexOf(' ') isnt -1
    title = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim() # MAG PaperTitle is lowercased. OriginalTitle isnt
    if res = @src.microsoft.graph.paper 'PaperTitle:"' + title + '"'
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      if typeof this?.tdm?.levenshtein is 'function'
        lvs = @tdm.levenshtein title, rt, false
        longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
        if lvs.distance < 2 or longest/lvs.distance > 10
          #res.relation = await @src.microsoft.graph._relations res.PaperId
          return res
      else if title.length < (rt.length * 1.2) and (title.length > rt.length * .8)
        #res.relation = await @src.microsoft.graph._relations res.PaperId
        return res
    return undefined
  else
    return @src.microsoft.graph.paper q
  

P.src.microsoft.graph.paper = (q) ->
  try
    # for now just get from old index
    url = 'https://dev.lvatn.com/use/microsoft/graph/paper/?q=' + q
    res = await @fetch url
    return res.hits.hits[0]._source
  catch
    return undefined

P.src.microsoft.graph.journal = (q) ->
  try
    # for now just get from old index
    url = 'https://dev.lvatn.com/use/microsoft/graph/journal/' + q
    return await @fetch url
  catch
    return undefined


'''
P.src.microsoft.graph.paper = _index: true # TODO check how API init will pick up an index that has no main function
P.src.microsoft.graph.journal = _index: true
P.src.microsoft.graph.author = _index: true
P.src.microsoft.graph.affiliation = _index: true
P.src.microsoft.graph.abstract = _index: true
P.src.microsoft.graph.relation = _index: true
'''


'''
P.src.microsoft.graph._relations = (q, papers=true, authors=true, affiliations=true) ->
 # ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
 # context could be paper, author, affiliation
  results = []
  _append = (recs) ->
    res = []
    recs = [recs] if not Array.isArray recs
    for rec in recs
      rec.paper = await @src.microsoft.graph.paper(rec.PaperId) if rec.PaperId and papers
      rec.author = await @src.microsoft.graph.author(rec.AuthorId) if rec.AuthorId and authors
      rec.affiliation = await @src.microsoft.graph.affiliation(rec.AffiliationId ? rec.LastKnownAffiliationId) if (rec.AffiliationId or rec.LastKnownAffiliationId) and affiliations
      if rec.GridId or rec.affiliation?.GridId
        try rec.ror = await @src.wikidata.grid2ror rec.GridId ? rec.affiliation?.GridId
      res.push rec
      results.push rec
    return res

  if typeof q is 'string' and rel = await @src.microsoft.graph.relation q
    return _append rel
  
  count = 0
  if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'PaperId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('PaperId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'AuthorId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('AuthorId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'AffiliationId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('AffiliationId.exact:"' + q + '"')) if cn < 10

  return results
'''

P.src.oadoi = (doi) ->
  doi ?= this?.params?.oadoi ? this?.params?.doi
  if typeof doi is 'string' and doi.startsWith('10.')
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return undefined
    
P.src.oadoi._index = true
P.src.oadoi._kv = false
P.src.oadoi._key = 'doi'


P.status = ->
  res = name: S.name, version: S.version, env: S.env, built: S.built
  if S.dev
    for k in ['id', 'request', 'params', 'parts', 'opts', 'headers', 'cookie', 'user', 'fn', 'routes']
      if @S.bg isnt true or k isnt 'request'
        try res[k] ?= @[k]
  # add an uncached check that the backend is responding, and whether or not an index/kv is available, and whether on a worker or a backend
  # if index is available get some info about it - from index.status
  # if there are status endpoints further down the stack, call them all too if a certain param is passed
  # maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  # maybe some useful info from the recent logs too
  return res



try
  S.svc.oaworks = JSON.parse SECRETS_OAWORKS
catch
  S.svc.oaworks = {}
  
P.svc.oaworks = () ->
  return name: 'OA.works API'


# email templates - convert to a read from a sheet instead of currently in the repo
# oab status and stats
# make all request admin via sheet somehow


'''
P.svc.oaworks.bug = () ->
  if (@body?.contact? and @body.contact.length) or (@body?.email? and @svc.oaworks.validate(@body.email) isnt true)
    return ''
  else
    whoto = ['help@openaccessbutton.org']
    text = ''
    for k of @body
      text += k + ': ' + JSON.stringify(@body[k],undefined,2) + '\n\n'
    text = @tdm.clean text
    subject = '[OAB forms]'
    if @body?.form is 'uninstall' # wrong bug general other
      subject += ' Uninstall notice'
    else if @body?.form is 'wrong'
      subject += ' Wrong article'
    else if @body?.form is 'bug'
      subject += ' Bug'
    else if @body?.form is 'general'
      subject += ' General'
    else
      subject += ' Other'
    subject += ' ' + Date.now()
    try
      if @body?.form in ['wrong','uninstall']
        whoto.push 'natalia.norori@openaccessbutton.org'
    @mail {
      service: 'openaccessbutton',
      from: 'natalia.norori@openaccessbutton.org',
      to: whoto,
      subject: subject,
      text: text
    }
    return {
      status: 302,
      headers: {
        'Content-Type': 'text/plain',
        'Location': (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
      },
      body: 'Location: ' + (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
    }


P.svc.oaworks.blacklist = (url) ->
  url = url.toString() if typeof url is 'number'
  return false if url? and (url.length < 4 or url.indexOf('.') is -1)
  bl = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.blacklist, stale
  blacklist = []
  blacklist.push(i.url) for i in bl
  if url
    if url.indexOf('http') isnt 0 and url.indexOf(' ') isnt -1
      return false # sometimes article titles get sent here, no point checking them on the blacklist
    else
      for b in blacklist
        return true if url.indexOf(b) isnt -1
      return false
  else
    return blacklist


API.service.oab.validate = (email, domain, verify=true) ->
  bad = ['eric@talkwithcustomer.com']
  if typeof email isnt 'string' or email.indexOf(',') isnt -1 or email in bad
    return false
  else if email.indexOf('@openaccessbutton.org') isnt -1 or email.indexOf('@email.ghostinspector.com') isnt -1 #or email in []
    return true
  else
    v = @mail.validate email, @S.svc.oaworks.mail.pubkey
    if v.is_valid and (not verify or v.mailbox_verification in [true,'true'])
      return true
    else if v.did_you_mean
      return v.did_you_mean
    else
      return false


# LIVE: https://docs.google.com/spreadsheets/d/1Te9zcQtBLq2Vx81JUE9R42fjptFGXY6jybXBCt85dcs/edit#gid=0
# Develop: https://docs.google.com/spreadsheets/d/1AaY7hS0D9jtLgVsGO4cJuLn_-CzNQg0yCreC3PP3UU0/edit#gid=0
P.svc.oaworks.redirect = (url) ->
  return false if await @svc.oaworks.blacklist(url) is true # ignore anything on the usual URL blacklist
  list = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.redirect, 360000
  for listing in list
    if listing.redirect and url.replace('http://','').replace('https://','').split('#')[0] is listing.redirect.replace('http://','').replace('https://','').split('#')[0]
      # we have an exact alternative for this url
      return listing.redirect
    else if typeof url is 'string' and url.indexOf(listing.domain.replace('http://','').replace('https://','').split('/')[0]) isnt -1
      url = url.replace('http://','https://') if listing.domain.indexOf('https://') is 0
      listing.domain = listing.domain.replace('http://','https://') if url.indexOf('https://') is 0
      if (listing.fulltext and listing.splash and listing.identifier) or listing.element
        source = url
        if listing.fulltext
          # switch the url by comparing the fulltext and splash examples, and converting the url in the same way
          parts = listing.splash.split listing.identifier
          if url.indexOf(parts[0]) is 0 # can only successfully replace if the incoming url starts with the same as the start of the splash url
            diff = url.replace parts[0], ''
            diff = diff.replace(parts[1],'') if parts.length > 1
            url = listing.fulltext.replace listing.identifier, diff
        else if listing.element and url.indexOf('.pdf') is -1
          try
            content = await @fetch url # should really be a puppeteer render
            url = content.toLowerCase().split(listing.element.toLowerCase())[1].split('"')[0].split("'")[0].split('>')[0]
        return false if (not url? or url.length < 6 or url is source) and listing.blacklist is "yes"
      else if listing.loginwall and url.indexOf(listing.loginwall.replace('http://','').replace('https://','')) isnt -1
        # this url is on the login wall of the repo in question, so it is no use
        return false
      else if listing.blacklist is "yes"
        return false
  if typeof url is 'string'
    # some URLs can be confirmed as resolvable but we also hit a captcha response and end up serving that to the user
    # we introduced this because of issue https://github.com/OAButton/discussion/issues/1257
    # and for example https://www.tandfonline.com/doi/pdf/10.1080/17521740701702115?needAccess=true
    # ends up as https://www.tandfonline.com/action/captchaChallenge?redirectUri=%2Fdoi%2Fpdf%2F10.1080%2F17521740701702115%3FneedAccess%3Dtrue
    for avoid in ['captcha','challenge']
      return undefined if url.toLowerCase().indexOf(avoid) isnt -1
  return url
'''


# need listing of deposits and deposited for each user ID
# and/or given a uid, find the most recent URL that this users uid submitted a deposit for
# need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
# make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)

'''
P.svc.oaworks.deposit = (options={}, files) ->
  # so need some metadata in options.metadata

  d.deposit ?= []
  dep = {createdAt: Date.now(), zenodo: {}}
  dep.embedded = options.embedded if options.embedded
  dep.demo = options.demo if options.demo
  dep.pilot = options.pilot if options.pilot
  if typeof dep.pilot is 'boolean' or dep.pilot in ['true','false'] # catch possible old erros with live/pilot values
    dep.pilot = if dep.pilot is true or dep.pilot is 'true' then Date.now() else undefined
  dep.live = options.live if options.live
  if typeof dep.live is 'boolean' or dep.live in ['true','false']
    dep.live = if dep.live is true or dep.live is 'true' then Date.now() else undefined
  dep.name = (files[0].filename ? files[0].name) if files? and files.length
  dep.email = options.email if options.email
  dep.from = options.from if options.from and options.from isnt 'anonymous' # should it still be possible to deposit anonymously?
  dep.plugin = options.plugin if options.plugin
  dep.confirmed = decodeURIComponent(options.confirmed) if options.confirmed

  uc = options.config # should exist but may not

  perms = @svc.oaworks.permissions d, files, undefined, dep.confirmed # if confirmed is true the submitter has confirmed this is the right file. If confirmed is the checksum this is a resubmit by an admin
  if perms.file?.archivable and ((dep.confirmed? and dep.confirmed is perms.file.checksum) or not dep.confirmed) # if the depositor confirms we don't deposit, we manually review - only deposit on admin confirmation (but on dev allow it)
    zn = {}
    zn.content = files[0].data
    zn.name = perms.file.name
    zn.publish = @S.svc.oaworks?.deposit?.zenodo is true
    creators = []
    try
      for a in d.metadata.author
        if a.family?
          at = {name: a.family + (if a.given then ', ' + a.given else '')}
          try at.orcid = a.ORCID.split('/').pop() if a.ORCID
          try at.affiliation = a.affiliation.name if typeof a.affiliation is 'object' and a.affiliation.name?
          creators.push at 
    creators = [{name:'Unknown'}] if creators.length is 0
    description = if d.metadata.abstract then d.metadata.abstract + '<br><br>' else ''
    description += perms.best_permission?.deposit_statement ? (if d.metadata.doi? then 'The publisher\'s final version of this work can be found at https://doi.org/' + d.metadata.doi else '')
    description = description.trim()
    description += '.' if description.lastIndexOf('.') isnt description.length-1
    description += ' ' if description.length
    description += '<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.'
    meta =
      title: d.metadata.title ? 'Unknown',
      description: description.trim(),
      creators: creators,
      version: if perms.file.version is 'preprint' then 'Submitted Version' else if perms.file.version is 'postprint' then 'Accepted Version' else if perms.file.version is 'publisher pdf' then 'Published Version' else 'Accepted Version',
      journal_title: d.metadata.journal
      journal_volume: d.metadata.volume
      journal_issue: d.metadata.issue
      journal_pages: d.metadata.page
    meta.keywords = d.metadata.keyword if _.isArray(d.metadata.keyword) and d.metadata.keyword.length and typeof d.metadata.keyword[0] is 'string'
    if d.metadata.doi?
      in_zenodo = @src.zenodo.records.doi d.metadata.doi
      if in_zenodo and dep.confirmed isnt perms.file.checksum and not @S.dev
        dep.zenodo.already = in_zenodo.id # we don't put it in again although we could with doi as related field - but leave for review for now
      else if in_zenodo
        meta['related_identifiers'] = [{relation: (if meta.version is 'postprint' or meta.version is 'AAM' or meta.version is 'preprint' then 'isPreviousVersionOf' else 'isIdenticalTo'), identifier: d.metadata.doi}]
      else
        meta.doi = d.metadata.doi
    else if @S.svc.oaworks.zenodo?.prereserve_doi
      meta.prereserve_doi = true
    meta['access_right'] = 'open'
    meta.license = perms.best_permission?.licence ? 'cc-by' # zenodo also accepts other-closed and other-nc, possibly more
    meta.license = 'other-closed' if meta.license.indexOf('other') isnt -1 and meta.license.indexOf('closed') isnt -1
    meta.license = 'other-nc' if meta.license.indexOf('other') isnt -1 and meta.license.indexOf('non') isnt -1 and meta.license.indexOf('commercial') isnt -1
    meta.license += '-4.0' if meta.license.toLowerCase().indexOf('cc') is 0 and isNaN(parseInt(meta.license.substring(meta.license.length-1)))
    try
      if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,'YYYY-MM-DD').valueOf() > Date.now()
        meta['access_right'] = 'embargoed'
        meta['embargo_date'] = perms.best_permission.embargo_end # check date format required by zenodo
    try meta['publication_date'] = d.metadata.published if d.metadata.published? and typeof d.metadata.published is 'string'
    if uc
      uc.community = uc.community_ID if uc.community_ID? and not uc.community?
      if uc.community
        uc.communities ?= []
        uc.communities.push({identifier: ccm}) for ccm in (if typeof uc.community is 'string' then uc.community.split(',') else uc.community)
      if uc.community? or uc.communities?
        uc.communities ?= uc.community
        uc.communities = [uc.communities] if not Array.isArray uc.communities
        meta['communities'] = []
        meta.communities.push(if typeof com is 'string' then {identifier: com} else com) for com in uc.communities
    tk = if @S.dev or dep.demo then @S.svc.oaworks?.zenodo?.sandbox else @S.svc.oaworks?.zenodo?.token
    if tk
      if not dep.zenodo.already
        z = @src.zenodo.deposition.create meta, zn, tk
        if z.id
          dep.zenodo.id = z.id
          dep.zenodo.url = 'https://' + (if @S.dev or dep.demo then 'sandbox.' else '') + 'zenodo.org/record/' + z.id
          dep.zenodo.doi = z.metadata.prereserve_doi.doi if z.metadata?.prereserve_doi?.doi?
          dep.zenodo.file = z.uploaded?.links?.download ? z.uploaded?.links?.download
        else
          dep.error = 'Deposit to Zenodo failed'
          try dep.error += ': ' + JSON.stringify z
    else
      dep.error = 'No Zenodo credentials available'
  dep.version = perms.file.version if perms.file?.version?
  if dep.zenodo.id
    if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,'YYYY-MM-DD').valueOf() > Date.now()
      dep.embargo = perms.best_permission.embargo_end
    dep.type = 'zenodo'
  else if dep.error? and dep.error.toLowerCase().indexOf('zenodo') isnt -1
    dep.type = 'review'
  else if options.from and (not dep.embedded or (dep.embedded.indexOf('openaccessbutton.org') is -1 and dep.embedded.indexOf('shareyourpaper.org') is -1))
    dep.type = if options.redeposit then 'redeposit' else if files? and files.length then 'forward' else 'dark'
  else
    dep.type = 'review'
  # save the deposit record somewhere for later review

  bcc = ['joe@righttoresearch.org','natalia.norori@openaccessbutton.org']
  tos = []
  if typeof uc?.owner is 'string' and uc.owner.indexOf('@') isnt -1
    tos.push uc.owner
  else if dep.from and iacc = API.accounts.retrieve dep.from
    try tos.push iacc.email ? iacc.emails[0].address # the institutional user may set a config value to use as the contact email address but for now it is the account address
  if tos.length is 0
    tos = _.clone bcc
    bcc = []

  dep.permissions = perms
  dep.url = if typeof options.redeposit is 'string' then options.redeposit else if d.url then d.url else undefined

  ed = @copy dep
  if ed.metadata?.author?
    as = []
    for author in ed.metadata.author
      if author.family
        as.push (if author.given then author.given + ' ' else '') + author.family
    ed.metadata.author = as
  ed.adminlink = (if ed.embedded then ed.embedded else 'https://shareyourpaper.org' + (if ed.metadata?.doi? then '/' + ed.metadata.doi else ''))
  ed.adminlink += if ed.adminlink.indexOf('?') is -1 then '?' else '&'
  if perms?.file?.checksum?
    ed.confirmed = encodeURIComponent perms.file.checksum
    ed.adminlink += 'confirmed=' + ed.confirmed + '&'
  ed.adminlink += 'email=' + ed.email
  tmpl = API.mail.template dep.type + '_deposit.html'
  sub = API.service.oab.substitute tmpl.content, ed
  if perms.file?.archivable isnt false # so when true or when undefined if no file is given
    ml =
      from: 'deposits@openaccessbutton.org'
      to: tos
      subject: (sub.subject ? dep.type + ' deposit')
      html: sub.content
    ml.bcc = bcc if bcc.length # passing undefined to mail seems to cause errors, so only set if definitely exists
    ml.attachments = [{filename: (files[0].filename ? files[0].name), content: files[0].data}] if _.isArray(files) and files.length
    @mail ml

  dep.z = z if @S.dev and dep.zenodo.id? and dep.zenodo.id isnt 'EXAMPLE'
  
  if dep.embargo
    try dep.embargo_UI = moment(dep.embargo).format "Do MMMM YYYY"
  return dep

'''

P.svc.oaworks.metadata = () ->
  res = await @svc.oaworks.find()
  return res.metadata


P.svc.oaworks.find = (options, metadata={}, content) ->
  res = {}

  _metadata = (input) =>
    for k of ct = await @svc.oaworks.citation input
      if k in ['url', 'paywall']
        res[k] ?= ct[k]
      else
        metadata[k] ?= ct[k]

  try options ?= @copy @params
  options ?= {}
  options.doi ?= options.find
  content ?= options.dom ? @request.body

  options.url = (options.q ? options.id) if options.q or options.id
  if options.url
    options.url = options.url.toString() if typeof options.url is 'number'
    if options.url.indexOf('/10.') isnt -1
      # we don't use a regex to try to pattern match a DOI because people often make mistakes typing them, so instead try to find one
      # in ways that may still match even with different expressions (as long as the DOI portion itself is still correct after extraction we can match it)
      dd = '10.' + options.url.split('/10.')[1].split('&')[0].split('#')[0]
      if dd.indexOf('/') isnt -1 and dd.split('/')[0].length > 6 and dd.length > 8
        dps = dd.split('/')
        dd = dps.join('/') if dps.length > 2
        metadata.doi ?= dd
    if options.url.replace('doi:','').replace('doi.org/','').trim().indexOf('10.') is 0
      metadata.doi ?= options.url.replace('doi:','').replace('doi.org/','').trim()
      options.url = 'https://doi.org/' + metadata.doi
    else if options.url.toLowerCase().indexOf('pmc') is 0
      metadata.pmcid ?= options.url.toLowerCase().replace('pmcid','').replace('pmc','')
      options.url = 'http://europepmc.org/articles/PMC' + metadata.pmcid
    else if options.url.replace(/pmid/i,'').replace(':','').length < 10 and options.url.indexOf('.') is -1 and not isNaN(parseInt(options.url.replace(/pmid/i,'').replace(':','').trim()))
      metadata.pmid ?= options.url.replace(/pmid/i,'').replace(':','').trim()
      options.url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + metadata.pmid
    else if not metadata.title? and options.url.indexOf('http') isnt 0
      if options.url.indexOf('{') isnt -1 or (options.url.replace('...','').match(/\./gi) ? []).length > 3 or (options.url.match(/\(/gi) ? []).length > 2
        options.citation = options.url
      else
        metadata.title = options.url
    delete options.url if options.url.indexOf('http') isnt 0 or options.url.indexOf('.') is -1
  if options.title and (options.title.indexOf('{') isnt -1 or (options.title.replace('...','').match(/\./gi) ? []).length > 3 or (options.title.match(/\(/gi) ? []).length > 2)
    options.citation = options.title # titles that look like citations
    delete options.title

  metadata.doi ?= options.doi
  metadata.title ?= options.title
  metadata.pmid ?= options.pmid
  metadata.pmcid ?= options.pmcid ? options.pmc
  await _metadata(options.citation) if options.citation
  try metadata.title = metadata.title.replace(/(<([^>]+)>)/g,'').replace(/\+/g,' ').trim()
  try metadata.doi = metadata.doi.split(' ')[0].replace('http://','').replace('https://','').replace('doi.org/','').replace('doi:','').trim()
  delete metadata.doi if typeof metadata.doi isnt 'string' or metadata.doi.indexOf('10.') isnt 0

  # switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if not metadata.title and content and typeof options.url is 'string' and (options.url.indexOf('alma.exlibrisgroup.com') isnt -1 or options.url.indexOf('/exlibristest') isnt -1)
    delete options.url

  _searches = () =>
    if (content? or options.url?) and not (metadata.doi or metadata.pmid? or metadata.pmcid? or metadata.title?)
      await _metadata await @svc.oaworks.scrape content ? options.url

    if not metadata.doi
      if metadata.pmid or metadata.pmcid
        epmc = await @src.epmc[if metadata.pmcid then 'pmc' else 'pmid'] (metadata.pmcid ? metadata.pmid)
        await _metadata epmc
      if metadata.title and not metadata.doi
        _crt = () =>
          await _metadata(await @src.crossref.works metadata.title) if not metadata.doi
          return true
        _mst = () =>
          await _metadata(await @src.microsoft.graph metadata.title) if not metadata.doi
          return true
        _pmt = () =>
          await _metadata(await @src.epmc.title metadata.title) if not epmc? and not metadata.doi
          return true
        await Promise.all [_crt(), _mst(), _pmt()]
  
    if metadata.doi
      _oad = () =>
        oad = await @src.oadoi metadata.doi
        await _metadata(oad) if oad?.doi is metadata.doi
        return true
      _crd = () =>
        cr = await @src.crossref.works metadata.doi
        if not cr?.type
          res.doi_not_in_crossref = metadata.doi
          delete options.url if typeof options.url is 'string' and options.url.indexOf('doi.org/' + metadata.doi) isnt -1
          delete metadata.doi
        else
          await _metadata cr
        return true
      await Promise.all [_oad(), _crd()]
    
    return true

  await _searches()

  # if nothing useful can be found and still only have title try using bing - or drop this ability?
  # TODO what to do if this finds anything? re-call the whole find?
  if metadata.title and not metadata.doi and not content and not options.url and not epmc?
    try
      mct = unidecode(metadata.title.toLowerCase()).replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
      bong = await @src.microsoft.bing.search mct
      if bong?.data? and bong.data.length
        bct = unidecode(bong.data[0].name.toLowerCase()).replace('(pdf)','').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
        if mct.replace(/ /g,'').indexOf(bct.replace(/ /g,'')) is 0 and not await @svc.oaworks.blacklist bong.data[0].url
          # if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
          options.url = bong.data[0].url.replace /"/g, ''
          metadata.pmid = options.url.replace(/\/$/,'').split('/').pop() if typeof options.url is 'string' and options.url.indexOf('pubmed.ncbi') isnt -1
          metadata.doi ?= '10.' + options.url.split('/10.')[1] if typeof options.url is 'string' and options.url.indexOf('/10.') isnt -1
      if metadata.doi or metadata.pmid or options.url
        await _searches() # run again if anything more useful found

  _ill = () =>
    if (metadata.doi or metadata.title) and (options.from? or options.config?) and (options.plugin is 'instantill' or options.ill is true)
      res.ill ?= {} # terms and openurl can be done client-side by new embed but old embed can't so keep these a while longer
      try res.ill.terms = options.config?.terms ? await @svc.oaworks.ill.terms options.from
      try res.ill.openurl = await @svc.oaworks.ill.openurl (options.config ? options.from), metadata
      try res.ill.subscription = await @svc.oaworks.ill.subscription (options.config ? options.from), metadata, res.refresh
    return true
  _permissions = () =>
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper') # don't get permissions by default now that the permissions check could take longer
      res.permissions ?= await @svc.oaworks.permissions metadata, (options.config ? options.from)
    return true
  await Promise.all [_ill(), _permissions()]

  # certain user-provided search values are allowed to override any that we could find ourselves, and we note that we got these from the user
  # is it worth keeping this in the backend or just have the embed handle it now that embed handles redirects to ill requests?
  # is this ONLY relevant to ILL? or anything else?
  for uo in ['title','journal','year','doi']
    metadata[uo] = options[uo] if options[uo] and options[uo] isnt metadata[uo]

  res.metadata = metadata
  return res


# Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
# Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.svc.oaworks.citation = (citation) ->
  res = {}
  
  try citation ?= @params.citation ? @params
  if typeof citation is 'string' and (citation.indexOf('{') is 0 or citation.indexOf('[') is 0)
    try citation = JSON.parse options.citation

  if typeof citation is 'object'
    res.doi ?= citation.DOI ? citation.doi
    try res.type ?= citation.type ? citation.genre
    res.issn ?= citation.ISSN ? citation.issn ? citation.journalInfo?.journal?.issn ? citation.journal?.issn
    res.issn ?= citation.journal_issns.split(',') if citation.journal_issns
    try res.title ?= citation.title[0] if Array.isArray citation.title
    try
      if citation.subtitle? and citation.subtitle.length and citation.subtitle[0].length
        res.title += ': ' + citation.subtitle[0]
    res.title ?= citation.dctitle ? citation.bibjson?.title
    res.title ?= citation.title if citation.title not in [404,'404']
    res.title = res.title.replace(/\s\s+/g,' ').trim() if res.title
    try res.journal ?= citation['container-title'][0]
    try res.shortname = citation['short-container-title'][0]
    res.journal ?= citation.journal_name ? citation.journalInfo?.journal?.title ? citation.journal?.title
    res.journal = citation.journal.split('(')[0].trim() if citation.journal
    res.publisher ?= citation.publisher
    try res.issue ?= citation.issue if citation.issue?
    try res.volume ?= citation.volume if citation.volume?
    try res.page ?= citation.page.toString() if citation.page?
    for key in ['title','journal']
      if not res[key] and typeof citation[key] is 'string' and (citation[key].charAt(0).toUpperCase() isnt citation[key].charAt(0) or citation[key].toUpperCase() is citation.key or citation[key].toLowerCase() is citation.key)
        res[key] = citation[key].charAt(0).toUpperCase() + citation[key].slice(1)
    if not res.year? and (citation.year? or citation.published? or citation.published_date?)
      try
        for ms in (citation.year ? citation.published ? citation.published_date).split(if (citation.year ? citation.published ? citation.published_date).indexOf('/') isnt -1 then '/' else '-')
          res.year ?= ms if ms.length is 4
      try
        delete res.year if typeof res.year isnt 'number' and (res.year.length isnt 4 or res.year.replace(/[0-9]/gi,'').length isnt 0)
      res.year = res.year.toString() if typeof res.year is 'number'
    if not res.year? and not res.published?
      for p in ['published-print','journal-issue.published-print','issued','published-online','created','deposited','indexed']
        try
          if rt = citation[p] ? citation['journal-issue']?[p.replace('journal-issue.','')]
            if typeof rt['date-time'] is 'string' and rt['date-time'].indexOf('T') isnt -1 and rt['date-time'].split('T')[0].split('-').length is 3
              res.published ?= rt['date-time'].split('T')[0]
              res.year ?= res.published.split('-')[0]
              break
            else if rt['date-parts']? and rt['date-parts'].length and Array.isArray(rt['date-parts'][0]) and rt['date-parts'][0].length
              rp = rt['date-parts'][0]
              pbl = rp[0].toString()
              if pbl.length > 2 # needs to be a year
                res.year ?= pbl
                if rp.length is 1
                  pbl += '-01-01'
                else
                  m = false
                  d = false
                  if not isNaN(parseInt(rp[1])) and parseInt(rp[1]) > 12
                    d = rp[1].toString()
                  else
                    m = rp[1].toString()
                  if rp.length is 2
                    if d isnt false
                      m = rp[2].toString()
                    else
                      d = rp[2].toString()
                  m = if m is false then '01' else if m.length is 1 then '0' + m else m
                  d = if d is false then '01' else if d.length is 1 then '0' + d else d
                  pbl += '-' + m + '-' + d
                res.published ?= pbl
                break
    try
      if not res.author? and (citation.author? or citation.z_authors?)
        res.author ?= []
        # what formats do we want for authors? how much metadata about them?
        for a in citation.author ? citation.z_authors
          if typeof a is 'string'
            res.author.push {name: a}
          else
            if a.affiliation?
              a.affiliation = a.affiliation[0] if Array.isArray a.affiliation
              a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
            res.author.push a
    #for i of citation # should we grab everything else too? probably not
    #  res[i] ?= citation[i] if typeof citation[i] is 'string' or Array.isArray citation[i]
    try res.licence ?= citation.best_oa_location.license if citation.best_oa_location?.license and citation.best_oa_location?.license isnt null
    if Array.isArray citation.assertion
      for a in citation.assertion
        if a.label is 'OPEN ACCESS' and a.URL and a.URL.indexOf('creativecommons') isnt -1
          res.licence ?= a.URL # and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
    if Array.isArray citation.license
      for l in citation.license ? []
        if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not rec.licence or rec.licence.indexOf('creativecommons') is -1)
          res.licence ?= l.URL
    if typeof citation.license is 'string'
      res.licence ?= citation.license
    if typeof res.licence is 'string' and res.licence.indexOf('/licenses/') isnt -1
      res.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-')
    # if there is a URL to use but not open, store it as res.paywall
    res.url ?= citation.best_oa_location?.url_for_pdf ? citation.best_oa_location?.url ? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?

  else if typeof citation is 'string'
    try
      citation = citation.replace(/citation\:/gi,'').trim()
      citation = citation.split('title')[1].trim() if citation.indexOf('title') isnt -1
      citation = citation.replace(/^"/,'').replace(/^'/,'').replace(/"$/,'').replace(/'$/,'')
      res.doi = citation.split('doi:')[1].split(',')[0].split(' ')[0].trim() if citation.indexOf('doi:') isnt -1
      res.doi = citation.split('doi.org/')[1].split(',')[0].split(' ')[0].trim() if citation.indexOf('doi.org/') isnt -1
      if not res.doi and citation.indexOf('http') isnt -1
        res.url = 'http' + citation.split('http')[1].split(' ')[0].trim()
      try
        if citation.indexOf('|') isnt -1 or citation.indexOf('}') isnt -1
          res.title = citation.split('|')[0].split('}')[0].trim()
        if citation.split('"').length > 2
          res.title = citation.split('"')[1].trim()
        else if citation.split("'").length > 2
          res.title ?= citation.split("'")[1].trim()
      try
        pts = citation.replace(/,\./g,' ').split ' '
        for pt in pts
          if not res.year
            pt = pt.replace /[^0-9]/g,''
            if pt.length is 4
              sy = parseInt pt
              res.year = sy if typeof sy is 'number' and not isNaN sy
      try
        if not res.title and res.year and citation.indexOf(res.year) < (citation.length/4)
          res.title = citation.split(res.year)[1].trim()
          res.title = res.title.replace(')','') if res.title.indexOf('(') is -1 or res.title.indexOf(')') < res.title.indexOf('(')
          res.title = res.title.replace('.','') if res.title.indexOf('.') < 3
          res.title = res.title.replace(',','') if res.title.indexOf(',') < 3
          res.title = res.title.trim()
          if res.title.indexOf('.') isnt -1
            res.title = res.title.split('.')[0]
          else if res.title.indexOf(',') isnt -1
            res.title = res.title.split(',')[0]
      if res.title
        try
          bt = citation.split(res.title)[0]
          bt = bt.split(res.year)[0] if res.year and bt.indexOf(res.year) isnt -1
          bt = bt.split(res.url)[0] if res.url and bt.indexOf(res.url) > 0
          bt = bt.replace(res.url) if res.url and bt.indexOf(res.url) is 0
          bt = bt.replace(res.doi) if res.doi and bt.indexOf(res.doi) is 0
          bt = bt.replace('.','') if bt.indexOf('.') < 3
          bt = bt.replace(',','') if bt.indexOf(',') < 3
          bt = bt.substring(0,bt.lastIndexOf('(')) if bt.lastIndexOf('(') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(')')) if bt.lastIndexOf(')') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(',')) if bt.lastIndexOf(',') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf('.')) if bt.lastIndexOf('.') > (bt.length-3)
          bt = bt.trim()
          if bt.length > 6
            if bt.indexOf(',') isnt -1
              res.author = []
              res.author.push({name: ak}) for ak in bt.split(',')
            else
              res.author = [{name: bt}]
        try
          rmn = citation.split(res.title)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.indexOf(res.url) isnt -1
          rmn = rmn.replace(res.doi) if res.doi and rmn.indexOf(res.doi) isnt -1
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 6
            res.journal = rmn
            res.journal = res.journal.split(',')[0].replace(/in /gi,'').trim() if rmn.indexOf(',') isnt -1
            res.journal = res.journal.replace('.','') if res.journal.indexOf('.') < 3
            res.journal = res.journal.replace(',','') if res.journal.indexOf(',') < 3
            res.journal = res.journal.trim()
      try
        if res.journal
          rmn = citation.split(res.journal)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.indexOf(res.url) isnt -1
          rmn = rmn.replace(res.doi) if res.doi and rmn.indexOf(res.doi) isnt -1
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 4
            rmn = rmn.split('retrieved')[0] if rmn.indexOf('retrieved') isnt -1
            rmn = rmn.split('Retrieved')[0] if rmn.indexOf('Retrieved') isnt -1
            res.volume = rmn
            if res.volume.indexOf('(') isnt -1
              res.volume = res.volume.split('(')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split('(')[1].split(')')[0]
                res.issue = res.issue.trim()
            if res.volume.indexOf(',') isnt -1
              res.volume = res.volume.split(',')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split(',')[1]
                res.issue = res.issue.trim()
            if res.volume
              try
                delete res.volume if isNaN parseInt res.volume
            if res.issue
              if res.issue.indexOf(',') isnt -1
                res.issue = res.issue.split(',')[0].trim()
              try
                delete res.issue if isNaN parseInt res.issue
            if res.volume and res.issue
              try
                rmn = citation.split(res.journal)[1]
                rmn = rmn.split('retriev')[0] if rmn.indexOf('retriev') isnt -1
                rmn = rmn.split('Retriev')[0] if rmn.indexOf('Retriev') isnt -1
                rmn = rmn.split(res.url)[0] if res.url and rmn.indexOf(res.url) isnt -1
                rmn = rmn.split(res.doi)[0] if res.doi and rmn.indexOf(res.doi) isnt -1
                rmn = rmn.substring(rmn.indexOf(res.volume)+(res.volume+'').length)
                rmn = rmn.substring(rmn.indexOf(res.issue)+(res.issue+'').length)
                rmn = rmn.replace('.','') if rmn.indexOf('.') < 2
                rmn = rmn.replace(',','') if rmn.indexOf(',') < 2
                rmn = rmn.replace(')','') if rmn.indexOf(')') < 2
                rmn = rmn.trim()
                if not isNaN parseInt rmn.substring(0,1)
                  res.pages = rmn.split(' ')[0].split('.')[0].trim()
                  res.pages = res.pages.split(', ')[0] if res.pages.length > 5
      if not res.author and citation.indexOf('et al') isnt -1
        cn = citation.split('et al')[0].trim()
        if citation.indexOf(cn) is 0
          res.author = [{name: cn + 'et al'}]
      if res.title and not res.volume
        try
          clc = citation.split(res.title)[1].toLowerCase().replace('volume','vol').replace('vol.','vol').replace('issue','iss').replace('iss.','iss').replace('pages','page').replace('pp','page')
          if clc.indexOf('vol') isnt -1
            res.volume = clc.split('vol')[1].split(',')[0].split('(')[0].split('.')[0].split(' ')[0].trim()
          if not res.issue and clc.indexOf('iss') isnt -1
            res.issue = clc.split('iss')[1].split(',')[0].split('.')[0].split(' ')[0].trim()
          if not res.pages and clc.indexOf('page') isnt -1
            res.pages = clc.split('page')[1].split('.')[0].split(', ')[0].split(' ')[0].trim()

  return res




'''
there would be an index called svc_oaworks_find (possibly namespaced to service name and env, or global)
may also want to allow explicit naming of the index, not the same as the route
so the usual index operations have to be available under P.svc.oaworks.find
at /find we should serve the index of find results

when .find is called, we need to know whether it is:
  an attempt to get back one specific find (e.g. it was already previously run so the result exists)
    so url params could do this - e.g. pass /find/10.1234/567890 or /find/id/1234 or /find/title/blah blah
    and may want to check kv as well if set for this endpoint
    check kv would entail:
      look up the full url (with params?)
      or look up a provided ID
      
  an attempt to run find
    which could run if the above lookup returns nothing (or more than one?)
    or if refresh is true, always run
    so find needs a .run to fall back to (and if doesn't have one, nothing populates the index on a fail to find)
    after .run:
      save to index 
      index should also save a history if configured to do so
      and save to kv if set to do so
        would it be possible to also set multiple routes to point to one kv result?
        like if a find on /find/10.1234/567890 should also be findable by /find/pmid/12345678
      
  an attempt to search finds
    when there is no provided url params, and no query params that could be used to get back one specific one
    or when there is a definitive search param provided, such as q or query or source?
    
{
  env: may want to specify the env we are in (defaults to infer from Settings). Or false to be global to any env
  index: false 'optional_index_name' # optional, otherwise inferred from the url route - or could be false while kv is true
  history: false # if true, on every edit, save a copy of the previous state of the record (requires index)
  kv: false # whether or not to also store in the kv layer (default false). prob not worth using kv AND cache
  cache: false # cache the results of the fetch requests to the index. could be true or false or a number for how long to cache
  # also need a way to record the user ID of whoever caused a historic change, if available
}

what goes into the log as the recorded response for this sort of route?
'''


# this should default to a search of ILLs as well... with a restrict
# restrict = @auth.role('openaccessbutton.admin', @user) and this.queryParams.all then [] else [{term:{from:@user?._id}}]
P.svc.oaworks.ill = () -> # only worked on POST with optional auth
  opts = @params
  if @user
    opts.from ?= @user._id
    opts.api = true
  opts = await @tdm.clean opts
  # opts should include a key called metadata at this point containing all metadata known about the object
  # but if not, and if needed for the below stages, it is looked up again
  opts.metadata ?= {}
  meta = @svc.oaworks.metadata opts
  for m of meta
    opts.metadata[m] ?= meta[m]
  opts.pilot = Date.now() if opts.pilot is true
  opts.live = Date.now() if opts.live is true

  if opts.library is 'imperial'
    # TODO for now we are just going to send an email when a user creates an ILL
    # until we have a script endpoint at the library to hit
    # library POST URL: https://www.imperial.ac.uk/library/dynamic/oabutton/oabutton3.php
    if not opts.forwarded and not opts.resolved
      @mail
        service: 'openaccessbutton',
        from: 'natalia.norori@openaccessbutton.org',
        to: ['joe@righttoresearch.org','s.barron@imperial.ac.uk'],
        subject: 'EXAMPLE ILL TRIGGER',
        text: JSON.stringify(opts,undefined,2)
      #@mail {template:{filename:'imperial_confirmation_example.txt'}, to:opts.id}
      @waitUntil @fetch 'https://www.imperial.ac.uk/library/dynamic/oabutton/oabutton3.php', body: opts, method: 'POST'
    return opts #oab_ill.insert opts # TODO this needs to save into an ill index somewhere. will _index: true be enough for this?

  else if opts.from? or opts.config?
    user = @auth(opts.from) if opts.from isnt 'anonymous'
    if user? or opts.config?
      config = opts.config #? get the old user config from old system data
      if config.requests
        config.requests_off ?= config.requests
      delete opts.config if opts.config?
      vars = {}
      vars.name = user?.profile?.firstname ? 'librarian'
      vars.details = ''
      ordered = ['title','author','volume','issue','date','pages']
      for o of opts
        if o is 'metadata'
          for m of opts[o]
            if m isnt 'email'
              opts[m] = opts[o][m]
              ordered.push(m) if m not in ordered
          delete opts.metadata
        else
          ordered.push(o) if o not in ordered
      for r in ordered
        if opts[r]
          vars[r] = opts[r]
          if r is 'author'
            authors = '<p>Authors:<br>'
            first = true
            ats = []
            for a in opts[r]
              if a.family
                if first
                  first = false
                else
                  authors += ', '
                atidy = a.family + (if a.given then ' ' + a.given else '')
                authors += atidy
                ats.push atidy
            vars.details += authors + '</p>'
            vars[r] = ats
          else if ['started','ended','took'].indexOf(r) is -1
            vars.details += '<p>' + r + ':<br>' + opts[r] + '</p>'
        #vars.details += '<p>' + o + ':<br>' + opts[o] + '</p>'
      opts.requests_off = true if config.requests_off
      delete opts.author if opts.author? # remove author metadata due to messy provisions causing save issues
      delete opts.metadata.author if opts.metadata?.author?
      #vars.illid = oab_ill.insert opts # TODO need to save an ILL record here
      vars.details += '<p>Open access button ILL ID:<br>' + vars.illid + '</p>';
      eml = if config.email and config.email.length then config.email else if user?.email then user?.email else false

      # such as https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=in%3A&si0qs=0021-9231&si1in=au%3A&si1op=AND&si2in=kw%3A&si2op=AND&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch
      # could be provided as: (unless other params are mandatory) 
      # https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?si0qs=0021-9231
      if config.search and config.search.length and (opts.issn or opts.journal)
        if config.search.indexOf('worldcat') isnt -1
          su = config.search.split('?')[0] + '?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in='
          su += if opts.issn? then 'in%3A' else 'ti%3A'
          su += '&si0qs=' + (opts.issn ? opts.journal)
          su += '&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch'
        else
          su = config.search
          su += if opts.issn then opts.issn else opts.journal
        vars.details += '<p>Search URL:<br><a href="' + su + '">' + su + '</a></p>'
        vars.worldcatsearchurl = su

      if not opts.forwarded and not opts.resolved and eml
        @svc.oaworks.mail {vars: vars, template: {filename:'instantill_create.html'}, to: eml, from: "InstantILL <InstantILL@openaccessbutton.org>", subject: "ILL request " + vars.illid}
      # send msg to mark and joe for testing (can be removed later)
      txt = vars.details
      delete vars.details
      txt += '<br><br>' + JSON.stringify(vars,undefined,2)
      @mail
        service: 'openaccessbutton',
        from: 'InstantILL <InstantILL@openaccessbutton.org>',
        to: ['mark@cottagelabs.com','joe@righttoresearch.org'],
        subject: 'ILL CREATED',
        html: txt,
        text: txt

      return vars.illid
    else
      return status: 401
  else
    return status: 404


P.svc.oaworks.ill.collect = () ->
  sid = @params.collect # end of the url is an SID
  # example AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6
  url = 'https://script.google.com/macros/s/' + sid + '/exec?'
  for q of @params
    if q isnt 'collect'
      url += q + '=' + @params[q] + '&'
  url += 'uuid=' + @uid()
  @waitUntil @fetch url
  return true


P.svc.oaworks.ill.openurl = () ->
  # Will eventually redirect after reading openurl params passed here, somehow. 
  # For now a POST of metadata here by a user with an open url registered will build their openurl
  opts = @params
  if opts.config?
    opts.uid ?= opts.config
    delete opts.config
  if opts.metadata?
    for m of opts.metadata
      opts[m] ?= opts.metadata[m]
    delete opts.metadata
  if not opts.uid and not @user?
    return status: 404
  else
    opts = await @tdm.clean opts
    uid = opts.uid ? @user._id
    config = if typeof uid is 'object' then uid else undefined
    config ?= {}
    if config.ill_redirect_base_url
      config.ill_form ?= config.ill_redirect_base_url
    if config.ill_redirect_params
      config.ill_added_params ?= config.ill_redirect_params
    return '' if withoutbase isnt true and not config.ill_form # support redirect base url for legacy config
    # add iupui / openURL defaults to config
    defaults =
      sid: 'sid'
      title: 'atitle' # this is what iupui needs (title is also acceptable, but would clash with using title for journal title, which we set below, as iupui do that
      doi: 'rft_id' # don't know yet what this should be
      #pmid: 'pmid' # same as iupui ill url format
      pmcid: 'pmcid' # don't know yet what this should be
      #aufirst: 'aufirst' # this is what iupui needs
      #aulast: 'aulast' # this is what iupui needs
      author: 'aulast' # author should actually be au, but aulast works even if contains the whole author, using aufirst just concatenates
      journal: 'title' # this is what iupui needs
      #issn: 'issn' # same as iupui ill url format
      #volume: 'volume' # same as iupui ill url format
      #issue: 'issue' # same as iupui ill url format
      #spage: 'spage' # this is what iupui needs
      #epage: 'epage' # this is what iupui needs
      page: 'pages' # iupui uses the spage and epage for start and end pages, but pages is allowed in openurl, check if this will work for iupui
      published: 'date' # this is what iupui needs, but in format 1991-07-01 - date format may be a problem
      year: 'rft.year' # this is what IUPUI uses
      # IUPUI also has a month field, but there is nothing to match to that
    for d of defaults
      config[d] = defaults[d] if not config[d]
  
    url = if config.ill_form then config.ill_form else ''
    url += if url.indexOf('?') is -1 then '?' else '&'
    url += config.ill_added_params.replace('?','') + '&' if config.ill_added_params
    url += config.sid + '=InstantILL&'
    for k of meta
      v = false
      if k is 'author'
        # need to check if config has aufirst and aulast or something similar, then need to use those instead, 
        # if we have author name parts
        try
          if typeof meta.author is 'string'
            v = meta.author
          else if Array.isArray meta.author
            v = ''
            for author in meta.author
              v += ', ' if v.length
              if typeof author is 'string'
                v += author
              else if author.family
                v += author.family + if author.given then ', ' + author.given else ''
          else
            if meta.author.family
              v = meta.author.family + if meta.author.given then ', ' + meta.author.given else ''
            else
              v = JSON.stringify meta.author
      else if k in ['doi','pmid','pmc','pmcid','url','journal','title','year','issn','volume','issue','page','crossref_type','publisher','published','notes']
        v = meta[k]
      if v
        url += (if config[k] then config[k] else k) + '=' + encodeURIComponent(v) + '&'
    if meta.usermetadata
      nfield = if config.notes then config.notes else 'notes'
      url = url.replace('usermetadata=true','')
      if url.indexOf(nfield+'=') is -1
        url += '&' + nfield + '=The user provided some metadata.'
      else
        url = url.replace(nfield+'=',nfield+'=The user provided some metadata. ')
    return url.replace('/&&/g','&')


P.svc.oaworks.ill.subscription = (uid, meta) ->
  uid ?= @user ? @params.uid
  if not meta?
    meta = JSON.parse JSON.stringify @params
    delete meta.uid
  do_serialssolutions_xml = true
  do_sfx_xml = true
  res = {findings:{}, lookups:[], error:[], contents: []}
  if typeof uid is 'string'
    res.uid = uid 
    user = @auth uid
    config = user?.service?.openaccessbutton?.ill?.config
  else
    config = uid
  if config?.subscription?
    if config.ill_redirect_params
      config.ill_added_params ?= config.ill_redirect_params
    # need to get their subscriptions link from their config - and need to know how to build the query string for it
    openurl = @svc.oaworks.ill.openurl config, meta, true
    openurl = openurl.replace(config.ill_added_params.replace('?',''),'') if config.ill_added_params
    openurl = openurl.split('?')[1] if openurl.indexOf('?') isnt -1
    if typeof config.subscription is 'string'
      config.subscription = config.subscription.split(',')
    if typeof config.subscription_type is 'string'
      config.subscription_type = config.subscription_type.split(',')
    config.subscription_type ?= []
    for s of config.subscription
      sub = config.subscription[s]
      if typeof sub is 'object'
        subtype = sub.type
        sub = sub.url
      else
        subtype = config.subscription_type[s] ? 'unknown'
      sub = sub.trim()
      if sub
        if (subtype is 'serialssolutions' or sub.indexOf('serialssolutions') isnt -1) and sub.indexOf('.xml.') is -1 and do_serialssolutions_xml is true
          tid = sub.split('.search')[0]
          tid = tid.split('//')[1] if tid.indexOf('//') isnt -1
          #bs = if sub.indexOf('://') isnt -1 then sub.split('://')[0] else 'http' # always use htto because https on the xml endpoint fails
          sub = 'http://' + tid + '.openurl.xml.serialssolutions.com/openurlxml?version=1.0&genre=article&'
        else if (subtype is 'sfx' or sub.indexOf('sfx.') isnt -1) and sub.indexOf('sfx.response_type=simplexml') is -1 and do_sfx_xml is true
          sub += (if sub.indexOf('?') is -1 then '?' else '&') + 'sfx.response_type=simplexml'
        url = sub + (if sub.indexOf('?') is -1 then '?' else '&') + openurl
        url = url.split('snc.idm.oclc.org/login?url=')[1] if url.indexOf('snc.idm.oclc.org/login?url=') isnt -1
        url = url.replace('cache=true','')
        if subtype is 'sfx' or sub.indexOf('sfx.') isnt -1 and url.indexOf('=10.') isnt -1
          url = url.replace('=10.','=doi:10.')
        # need to use the proxy as some subscriptions endpoints need a registered IP address, and ours is registered for some of them already
        # but having a problem passing proxy details through, so ignore for now
        # BUT AGAIN eds definitely does NOT work without puppeteer so going to have to use that again for now and figure out the proxy problem later
        #pg = API.http.puppeteer url #, undefined, API.settings.proxy
        # then get that link
        # then in that link find various content, depending on what kind of service it is
        
        # try doing without puppeteer and see how that goes
        pg = ''
        spg = ''
        error = false
        res.lookups.push url
        try
          #pg = HTTP.call('GET', url, {timeout:15000, npmRequestOptions:{proxy:API.settings.proxy}}).content
          pg = if url.indexOf('.xml.serialssolutions') isnt -1 or url.indexOf('sfx.response_type=simplexml') isnt -1 then await @fetch(url) else await @puppet url #, undefined, API.settings.proxy
          spg = if pg.indexOf('<body') isnt -1 then pg.toLowerCase().split('<body')[1].split('</body')[0] else pg
          res.contents.push spg
        catch err
          error = true
        #res.u ?= []
        #res.u.push url
        #res.pg = pg

        # sfx 
        # with access:
        # https://cricksfx.hosted.exlibrisgroup.com/crick?sid=Elsevier:Scopus&_service_type=getFullTxt&issn=00225193&isbn=&volume=467&issue=&spage=7&epage=14&pages=7-14&artnum=&date=2019&id=doi:10.1016%2fj.jtbi.2019.01.031&title=Journal+of+Theoretical+Biology&atitle=Potential+relations+between+post-spliced+introns+and+mature+mRNAs+in+the+Caenorhabditis+elegans+genome&aufirst=S.&auinit=S.&auinit1=S&aulast=Bo
        # which will contain a link like:
        # <A title="Navigate to target in new window" HREF="javascript:openSFXMenuLink(this, 'basic1', undefined, '_blank');">Go to Journal website at</A>
        # but the content can be different on different sfx language pages, so need to find this link via the tag attributes, then trigger it, then get the page it opens
        # can test this with 10.1016/j.jtbi.2019.01.031 on instantill page
        # note there is also now an sfx xml endpoint that we have found to check
        if subtype is 'sfx' or url.indexOf('sfx.') isnt -1
          res.error.push 'sfx' if error
          if do_sfx_xml
            if spg.indexOf('getFullTxt') isnt -1 and spg.indexOf('<target_url>') isnt -1
              try
                # this will get the first target that has a getFullTxt type and has a target_url element with a value in it, or will error
                res.url = spg.split('getFullTxt')[1].split('</target>')[0].split('<target_url>')[1].split('</target_url>')[0].trim()
                res.findings.sfx = res.url
                if res.url?
                  if res.url.indexOf('getitnow') is -1
                    res.found = 'sfx'
                    return res
                  else
                    res.url = undefined
                    res.findings.sfx = undefined
          else
            if spg.indexOf('<a title="navigate to target in new window') isnt -1 and spg.split('<a title="navigate to target in new window')[1].split('">')[0].indexOf('basic1') isnt -1
              # tried to get the next link after the click through, but was not worth putting more time into it. For now, seems like this will have to do
              res.url = url
              res.findings.sfx = res.url
              if res.url?
                if res.url.indexOf('getitnow') is -1
                  res.found = 'sfx'
                  return res
                else
                  res.url = undefined
                  res.findings.sfx = undefined

        # eds
        # note eds does need a login, but IP address range is supposed to get round that
        # our IP is supposed to be registered with the library as being one of their internal ones so should not need login
        # however a curl from our IP to it still does not seem to work - will try with puppeteer to see if it is blocking in other ways
        # not sure why the links here are via an oclc login - tested, and we will use without it
        # with access:
        # https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=RE&aulast=Marx&atitle=Platelet-rich+plasma:+growth+factor+enhancement+for+bone+grafts&id=doi:10.1016/S1079-2104(98)90029-4&title=Oral+Surgery,+Oral+Medicine,+Oral+Pathology,+Oral+Radiology,+and+Endodontology&volume=85&issue=6&date=1998&spage=638&issn=1079-2104
        # can be tested on instantill page with 10.1016/S1079-2104(98)90029-4
        # without:
        # https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=MP&aulast=Newton&atitle=Librarian+roles+in+institutional+repository+data+set+collecting:+outcomes+of+a+research+library+task+force&id=doi:10.1080/01462679.2011.530546
        else if subtype is 'eds' or url.indexOf('ebscohost.') isnt -1
          res.error.push 'eds' if error
          if spg.indexOf('view this ') isnt -1 and pg.indexOf('<a data-auto="menu-link" href="') isnt -1
            res.url = url.replace('://','______').split('/')[0].replace('______','://') + pg.split('<a data-auto="menu-link" href="')[1].split('" title="')[0]
            res.findings.eds = res.url
            if res.url?
              if res.url.indexOf('getitnow') is -1
                res.found = 'eds'
                return res
              else
                res.url = undefined

        # serials solutions
        # the HTML source code for the No Results page includes a span element with the class SS_NoResults. This class is only found on the No Results page (confirmed by serialssolutions)
        # does not appear to need proxy or password
        # with:
        # https://rx8kl6yf4x.search.serialssolutions.com/?genre=article&issn=14085348&title=Annales%3A%20Series%20Historia%20et%20Sociologia&volume=28&issue=1&date=20180101&atitle=HOW%20TO%20UNDERSTAND%20THE%20WAR%20IN%20SYRIA.&spage=13&PAGES=13-28&AUTHOR=%C5%A0TERBENC%2C%20Primo%C5%BE&&aufirst=&aulast=&sid=EBSCO:aph&pid=
        # can test this on instantill page with How to understand the war in Syria - Annales Series Historia et Sociologia 2018
        # but the with link has a suppressed link that has to be clicked to get the actual page with the content on it
        # <a href="?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick">Click here</a>
        # which is the only link with the showsuppressedlinks param and the clickhere content
        # then the page with the content link is like:
        # https://rx8kl6yf4x.search.serialssolutions.com/?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick
        # and the content is found in a link like this:
        # <div id="ArticleCL" class="cl">
        #   <a target="_blank" href="./log?L=RX8KL6YF4X&amp;D=EAP&amp;J=TC0000940997&amp;P=Link&amp;PT=EZProxy&amp;A=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&amp;H=c7306f7121&amp;U=http%3A%2F%2Fwww.ulib.iupui.edu%2Fcgi-bin%2Fproxy.pl%3Furl%3Dhttp%3A%2F%2Fopenurl.ebscohost.com%2Flinksvc%2Flinking.aspx%3Fgenre%3Darticle%26issn%3D1408-5348%26title%3DAnnales%2BSeries%2Bhistoria%2Bet%2Bsociologia%26date%3D2018%26volume%3D28%26issue%3D1%26spage%3D13%26atitle%3DHOW%2BTO%2BUNDERSTAND%2BTHE%2BWAR%2BIN%2BSYRIA.%26aulast%3D%25C5%25A0TERBENC%26aufirst%3DPrimo%C5%BE">Article</a>
        # </div>
        # without:
        # https://rx8kl6yf4x.search.serialssolutions.com/directLink?&atitle=Writing+at+the+Speed+of+Sound%3A+Music+Stenography+and+Recording+beyond+the+Phonograph&author=Pierce%2C+J+Mackenzie&issn=01482076&title=Nineteenth+Century+Music&volume=41&issue=2&date=2017-10-01&spage=121&id=doi:&sid=ProQ_ss&genre=article
        
        # we also have an xml alternative for serials solutions
        # see https://journal.code4lib.org/articles/108
        else if subtype is 'serialssolutions' or url.indexOf('serialssolutions.') isnt -1
          res.error.push 'serialssolutions' if error
          if do_serialssolutions_xml is true
            if spg.indexOf('<ssopenurl:url type="article">') isnt -1
              fnd = spg.split('<ssopenurl:url type="article">')[1].split('</ssopenurl:url>')[0].trim() # this gets us something that has an empty accountid param - do we need that for it to work?
              if fnd.length
                res.url = fnd
                res.findings.serials = res.url
                if res.url?
                  if res.url.indexOf('getitnow') is -1
                    res.found = 'serials'
                    return res
                  else
                    res.url = undefined
                    res.findings.serials = undefined
            # disable journal matching for now until we have time to get it more accurate - some things get journal links but are not subscribed
            #else if spg.indexOf('<ssopenurl:result format="journal">') isnt -1
            #  # we assume if there is a journal result but not a URL that it means the institution has a journal subscription but we don't have a link
            #  res.journal = true
            #  res.found = 'serials'
            #  API.http.cache(sig, 'oab_ill_subs', res)
            #  return res
          else
            if spg.indexOf('ss_noresults') is -1
              try
                surl = url.split('?')[0] + '?ShowSupressedLinks' + pg.split('?ShowSupressedLinks')[1].split('">')[0]
                #npg = API.http.puppeteer surl #, undefined, API.settings.proxy
                npg = @fetch surl, {timeout: 15000, npmRequestOptions:{proxy:S.proxy}}
                if npg.indexOf('ArticleCL') isnt -1 and npg.split('DatabaseCL')[0].indexOf('href="./log') isnt -1
                  res.url = surl.split('?')[0] + npg.split('ArticleCL')[1].split('DatabaseCL')[0].split('href="')[1].split('">')[0]
                  res.findings.serials = res.url
                  if res.url?
                    if res.url.indexOf('getitnow') is -1
                      res.found = 'serials'
                      return res
                    else
                      res.url = undefined
                      res.findings.serials = undefined
              catch
                res.error.push 'serialssolutions' if error
  return res




P.svc.oaworks.permissions = (meta, roruid, getmeta) ->
  overall_policy_restriction = false
  cr = false
  haddoi = false
  
  meta ?= @copy @params
  if meta?.permissions?
    if meta.permissions.startsWith 'journal/'
      meta.issn = meta.permissions.replace 'journal/', ''
    else if meta.permissions.startsWith 'affiliation/'
      meta.ror = meta.permissions.replace 'affiliation/', ''
    else if meta.permissions.startsWith 'publisher/'
      meta.publisher = meta.permissions.replace 'publisher/', ''
    else if meta.permissions.indexOf('10.') is 0 and meta.permissions.indexOf('/') isnt -1
      meta.doi = meta.permissions
    else if meta.permissions.indexOf('-') isnt 0 and meta.permissions.length < 10 and meta.permissions.length > 6
      meta.issn = meta.permissions
    else
      meta.publisher = meta.permissions # but could be a ROR?
    delete meta.permissions
  
  _prep = (rec) ->
    if haddoi and rec.embargo_months and (meta.published or meta.year)
      em = moment meta.published ? meta.year + '-01-01'
      em = em.add rec.embargo_months, 'months'
      rec.embargo_end = em.format "YYYY-MM-DD"
    delete rec.embargo_end if rec.embargo_end is ''
    rec.copyright_name = if rec.copyright_owner is 'publisher' then (if typeof rec.issuer.parent_policy is 'string' then rec.issuer.parent_policy else if typeof rec.issuer.id is 'string' then rec.issuer.id else rec.issuer.id[0]) else if rec.copyright_owner in ['journal','affiliation'] then (meta.journal ? '') else if (rec.copyright_owner and rec.copyright_owner.toLowerCase().indexOf('author') isnt -1) and meta.author? and meta.author.length and (meta.author[0].name or meta.author[0].family) then (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '') else ''
    if rec.copyright_name in ['publisher','journal'] and (cr or meta.doi or rec.provenance?.example)
      if cr is false
        cr = await @src.crossref.works meta.doi ? rec.provenance.example
      if cr?.assertion? and cr.assertion.length
        for a in cr.assertion
          if a.name.toLowerCase() is 'copyright'
            try rec.copyright_name = a.value
            try rec.copyright_name = a.value.replace('\u00a9 ','').replace(/[0-9]/g,'').trim()
    rec.copyright_year = meta.year if haddoi and rec.copyright_year is '' and meta.year
    delete rec.copyright_year if rec.copyright_year is ''
    if haddoi and rec.deposit_statement? and rec.deposit_statement.indexOf('<<') isnt -1
      fst = ''
      for pt in rec.deposit_statement.split '<<'
        if fst is '' and pt.indexOf('>>') is -1
          fst += pt
        else
          eph = pt.split '>>'
          ph = eph[0].toLowerCase()
          swaps = 
            'journal title': 'journal'
            'vol': 'volume'
            'date of publication': 'published'
            '(c)': 'year'
            'article title': 'title'
            'copyright name': 'copyright_name'
          ph = swaps[ph] if swaps[ph]?
          if ph is 'author'
            try fst += (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '')
          else
            fst += meta[ph] ? rec[ph] ? ''
          try fst += eph[1]
      rec.deposit_statement = fst
    if rec._id?
      rec.meta ?= {}
      rec.meta.source = 'https://' + (if S.dev then 'dev.api.cottagelabs.com/svc/oaworks/permissions/' else 'api.openaccessbutton.org/permissions/') + (if rec.issuer.type then rec.issuer.type + '/' else '') + rec._id
    if typeof rec.issuer?.has_policy is 'string' and rec.issuer.has_policy.toLowerCase().trim() in ['not publisher','takedown']
      # find out if this should be enacted if it is the case for any permission, or only the best permission
      overall_policy_restriction = rec.issuer.has_policy
    delete rec[d] for d in ['_id','permission_required','createdAt','updatedAt','created_date','updated_date']
    try delete rec.issuer.updatedAt
    return rec

  _score = (rec) =>
    score = if rec.can_archive then 1000 else 0
    score += 1000 if rec.provenance?.oa_evidence is 'In DOAJ'
    if rec.requirements?
      # TODO what about cases where the requirement is met?
      # and HOW is requirement met? we search ROR against issuer, but how does that match with author affiliation?
      # should we even be searching for permissions by ROR, or only using it to calculate the ones we find by some other means?
      # and if it is not met then is can_archive worth anything?
      score -= 10
    else
      score += if rec.version is 'publishedVersion' then 200 else if rec.version is 'acceptedVersion' then 100 else 0
    score -= 5 if rec.licences? and rec.licences.length
    score += if rec.issuer?.type is 'journal' then 5 else if rec.issuer?.type is 'publisher' then 4 else if rec.issuer?.type is 'university' then 3 else if rec.issuer?.type in 'article' then 2 else 0
    score -= 25 if rec.embargo_months and rec.embargo_months >= 36 and (not rec.embargo_end or moment(rec.embargo_end,"YYYY-MM-DD").isBefore(moment()))
    return score


  inp = {}
  if typeof meta is 'string'
    meta = if meta.indexOf('10.') is 0 then {doi: meta} else {issn: meta}
  delete meta.meta if meta.meta? # just used to pass in a false to getmeta
  if meta.metadata? # if passed a catalogue object
    inp = meta
    meta = meta.metadata
    
  if meta.affiliation
    meta.ror = meta.affiliation
    delete meta.affiliation
  if meta.journal and meta.journal.indexOf(' ') is -1
    meta.issn = meta.journal
    delete meta.journal
  if meta.publisher and meta.publisher.indexOf(' ') is -1 and meta.publisher.indexOf(',') is -1 and not oab_permissions.find 'issuer.type.exact:"publisher" AND issuer.id:"' + meta.publisher + '"'
    # it is possible this may actually be a ror, so switch to ror just in case - if it still matches nothing, no loss
    meta.ror = meta.publisher
    delete meta.publisher

  issns = if Array.isArray(meta.issn) then meta.issn else [] # only if directly passed a list of ISSNs for the same article, accept them as the ISSNs list to use
  meta.issn = meta.issn.split(',') if typeof meta.issn is 'string' and meta.issn.indexOf(',') isnt -1
  meta.ror = meta.ror.split(',') if typeof meta.ror is 'string' and meta.ror.indexOf(',') isnt -1
  
  if not meta.ror
    uc = if typeof roruid is 'object' then roruid else if typeof roruid is 'string' then @svc.oaworks.deposit.config(roruid) else undefined
    if (typeof uc is 'object' and uc.ror?) or typeof roruid is 'string'
      meta.ror = uc?.ror ? roruid

  if JSON.stringify(meta) is '{}' or (meta.issn and JSON.stringify(meta.issn).indexOf('-') is -1) or (meta.doi and (typeof meta.doi isnt 'string' or meta.doi.indexOf('10.') isnt 0 or meta.doi.indexOf('/') is -1))
    return body: 'No valid DOI, ISSN, or ROR provided', statusCode: 404
    
  # NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  # we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = () =>
    psm = @copy meta
    delete psm.ror
    if JSON.stringify(psm) isnt '{}'
      rsm = @svc.oaworks.metadata {metadata: ['crossref_type','issn','publisher','published','year','author','ror']}, psm
      for mk of rsm
        meta[mk] ?= rsm[mk]
  await _getmeta() if getmeta isnt false and meta.doi and (not meta.publisher or not meta.issn)
  meta.published = meta.year + '-01-01' if not meta.published and meta.year
  haddoi = meta.doi?
  af = false
  if meta.issn
    meta.issn = [meta.issn] if typeof meta.issn is 'string'
    if not issns.length # they're already meta.issn in this case anyway
      for inisn in meta.issn
        issns.push(inisn) if inisn not in issns # check just in case
    if not issns.length or not meta.publisher or not meta.doi
      if af = academic_journal.find 'issn.exact:"' + issns.join('" OR issn.exact:"') + '"'
        meta.publisher ?= af.publisher
        for an in (if typeof af.issn is 'string' then [af.issn] else af.issn)
          issns.push(an) if an not in issns # check again
        meta.doi ?= af.doi
    try
      meta.doi ?= await @src.crossref.journals.doi issns
    catch # temporary until wider crossref update completed
      meta.doi ?= await @src.crossref.journals.dois.example issns
    await _getmeta() if not haddoi and meta.doi
  if haddoi and meta.crossref_type not in ['journal-article']
    return
      body: 'DOI is not a journal article'
      status: 501

  if meta.publisher and meta.publisher.indexOf('(') isnt -1 and meta.publisher.lastIndexOf(')') > (meta.publisher.length*.7)
    # could be a publisher name with the acronym at the end, like Public Library of Science (PLoS)
    # so get rid of the acronym because that is not included in the publisher name in crossref and other sources
    meta.publisher = meta.publisher.substring(0, meta.publisher.lastIndexOf('(')).trim()

  try
    meta.citation = '['
    meta.citation += meta.title + '. ' if meta.title
    meta.citation += meta.journal + ' ' if meta.journal
    meta.citation += meta.volume + (if meta.issue then ', ' else ' ') if meta.volume
    meta.citation += meta.issue + ' ' if meta.issue
    meta.citation += 'p' + (meta.page ? meta.pages) if meta.page? or meta.pages?
    if meta.year or meta.published
      meta.citation += ' (' + (meta.year ? meta.published).split('-')[0] + ')'
    meta.citation = meta.citation.trim()
    meta.citation += ']'

  perms = best_permission: undefined, all_permissions: []
  rors = []
  if meta.ror?
    meta.ror = [meta.ror] if typeof meta.ror is 'string'
    rs = oab_permissions.search 'issuer.id.exact:"' + meta.ror.join('" OR issuer.id.exact:"') + '"'
    if not rs?.hits?.total
      # look up the ROR in wikidata - if found, get the qid from the P17 country snak, look up that country qid
      # get the P297 ISO 3166-1 alpha-2 code, search affiliations for that
      if rwd = wikidata_record.find 'snaks.property.exact:"P6782" AND snaks.property.exact:"P17" AND (snaks.value.exact:"' + meta.ror.join(" OR snaks.value.exact:") + '")'
        snkd = false
        for snak in rwd.snaks
          if snkd
            break
          else if snak.property is 'P17'
            if cwd = wikidata_record.get snak.qid
              for sn in cwd.snaks
                if sn.property is 'P297'
                  snkd = true
                  rs = oab_permissions.search 'issuer.id.exact:"' + sn.value + '"'
                  break
    for rr in rs?.hits?.hits ? []
      tr = _prep rr._source
      tr.score = _score tr
      rors.push tr

  if issns.length or meta.publisher
    qr = if issns.length then 'issuer.id.exact:"' + issns.join('" OR issuer.id.exact:"') + '"' else ''
    if meta.publisher
      qr += ' OR ' if qr isnt ''
      qr += 'issuer.id:"' + meta.publisher + '"' # how exact/fuzzy can this be
    ps = oab_permissions.search qr
    if ps?.hits?.hits? and ps.hits.hits.length
      for p in ps.hits.hits
        rp = _prep p._source
        rp.score = _score rp
        perms.all_permissions.push rp

  if perms.all_permissions.length is 0 and meta.publisher and not meta.doi and not issns.length
    af = academic_journal.find 'publisher:"' + meta.publisher + '"'
    if not af?
      fz = academic_journal.find 'publisher:"' + meta.publisher.split(' ').join(' AND publisher:"') + '"'
      if fz.publisher is meta.publisher
        af = fz
      else
        lvs = @tdm.levenshtein fz.publisher, meta.publisher, true
        longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
        af = fz if lvs.distance < 5 or longest/lvs.distance > 10
    if typeof af is 'object' and af.is_oa
      pisoa = academic_journal.count('publisher:"' + af.publisher + '"') is academic_journal.count('publisher:"' + af.publisher + '" AND is_oa:true')
    af = false if not af.is_oa or not pisoa

  if typeof af is 'object' and af.is_oa isnt false
    af.is_oa = true if not af.is_oa? and ('doaj' in af.src or af.wikidata_in_doaj)
    if af.is_oa
      altoa =
        can_archive: true
        version: 'publishedVersion'
        versions: ['publishedVersion']
        licence: undefined
        licence_terms: ""
        licences: []
        locations: ['institutional repository']
        embargo_months: undefined
        issuer:
          type: 'journal'
          has_policy: 'yes'
          id: af.issn
        meta:
          creator: ['joe+doaj@openaccessbutton.org']
          contributors: ['joe+doaj@openaccessbutton.org']
          monitoring: 'Automatic'

      try altoa.licence = af.license[0].type # could have doaj licence info
      altoa.licence ?= af.licence # wikidata licence
      if 'doaj' in af.src or af.wikidata_in_doaj
        altoa.embargo_months = 0
        altoa.provenance = {oa_evidence: 'In DOAJ'}
      if typeof altoa.licence is 'string'
        altoa.licence = altoa.licence.toLowerCase().trim()
        if altoa.licence.indexOf('cc') is 0
          altoa.licence = altoa.licence.replace(/ /g, '-')
        else if altoa.licence.indexOf('creative') isnt -1
          altoa.licence = if altoa.licence.indexOf('0') isnt -1 or altoa.licence.indexOf('zero') isnt -1 then 'cc0' else if altoa.licence.indexOf('share') isnt -1 then 'ccbysa' else if altoa.licence.indexOf('derivative') isnt -1 then 'ccbynd' else 'ccby'
        else
          delete altoa.licence
      else
        delete altoa.licence
      if altoa.licence
        altoa.licences = [{type: altoa.licence, terms: ""}]
      altoa.score = _score altoa
      perms.all_permissions.push altoa

  if haddoi and meta.doi and oadoi = await @src.oadoi meta.doi
    # use oadoi for specific doi
    if oadoi?.best_oa_location?.license and oadoi.best_oa_location.license.indexOf('cc') isnt -1
      doa =
        can_archive: true
        version: oadoi.best_oa_location.version
        versions: []
        licence: oadoi.best_oa_location.license
        licence_terms: ""
        licences: []
        locations: ['institutional repository']
        issuer:
          type: 'article'
          has_policy: 'yes'
          id: meta.doi
        meta:
          creator: ['support@unpaywall.org']
          contributors: ['support@unpaywall.org']
          monitoring: 'Automatic'
          updated: oadoi.best_oa_location.updated
        provenance:
          oa_evidence: oadoi.best_oa_location.evidence

      if typeof doa.licence is 'string'
        doa.licences = [{type: doa.licence, terms: ""}]
      if doa.version
        doa.versions = if doa.version in ['submittedVersion','preprint'] then ['submittedVersion'] else if doa.version in ['acceptedVersion','postprint'] then ['submittedVersion', 'acceptedVersion'] else  ['submittedVersion', 'acceptedVersion', 'publishedVersion']
      doa.score = _score doa
      perms.all_permissions.push doa

  # sort rors by score, and sort alts by score, then combine
  if perms.all_permissions.length
    perms.all_permissions.sort (a, b) => return if (a.score > b.score) then 1 else -1
    # note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for wp in perms.all_permissions
      if not wp.provenance?.enforcement_from
        perms.best_permission = @copy wp
        break
      else if not meta.published or moment(meta.published,'YYYY-MM-DD').isAfter(moment(wp.provenance.enforcement_from,'DD/MM/YYYY'))
        perms.best_permission = @copy wp
        break
    if rors.length
      rors.sort (a, b) => return if (a.score > b.score) then 1 else -1
      for ro in rors # check this gives the order in the direction we want, else reverse it
        perms.all_permissions.push ro
        if not perms.best_permission?.author_affiliation_requirement?
          if perms.best_permission?
            if not ro.provenance?.enforcement_from or not meta.published or moment(meta.published,'YYYY-MM-DD').isAfter(moment(ro.provenance.enforcement_from,'DD/MM/YYYY'))
              pb = @copy perms.best_permission
              for key in ['licences', 'versions', 'locations']
                for vl in ro[key]
                  pb[key] ?= []
                  pb[key].push(vl) if vl not in pb[key]
              for l in pb.licences ? []
                pb.licence = l.type if not pb.licence? or l.type.length < pb.licence.length
              pb.version = if 'publishedVersion' in pb.versions or 'publisher pdf' in pb.versions then 'publishedVersion' else if 'acceptedVersion' in pb.versions or 'postprint' in pb.versions then 'acceptedVersion' else 'submittedVersion'
              if pb.embargo_end
                if ro.embargo_end
                  if moment(ro.embargo_end,"YYYY-MM-DD").isBefore(moment(pb.embargo_end,"YYYY-MM-DD"))
                    pb.embargo_end = ro.embargo_end
              if pb.embargo_months and ro.embargo_months? and ro.embargo_months < pb.embargo_months
                pb.embargo_months = ro.embargo_months
              pb.can_archive = true if ro.can_archive is true
              pb.requirements ?= {}
              pb.requirements.author_affiliation_requirement = if not meta.ror? then ro.issuer.id else if typeof meta.ror is 'string' then meta.ror else meta.ror[0]
              pb.issuer.affiliation = ro.issuer
              pb.meta ?= {}
              pb.meta.affiliation = ro.meta
              pb.provenance ?= {}
              pb.provenance.affiliation = ro.provenance
              pb.score = parseInt(pb.score) + parseInt(ro.score)
              perms.best_permission = pb
              perms.all_permissions.push pb

  if overall_policy_restriction
    msgs = 
      'not publisher': 'Please find another DOI for this article as this is provided as this doesn’t allow us to find required information like who published it'
    return
      body: if typeof overall_policy_restriction isnt 'string' then overall_policy_restriction else msgs[overall_policy_restriction.toLowerCase()] ? overall_policy_restriction
      status: 501
  else
    return perms



# https://docs.google.com/spreadsheets/d/1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A/edit
P.svc.oaworks.permission = (recs=[]) ->
  keys = 
    versionsarchivable: 'versions'
    permissionsrequestcontactemail: 'permissions_contact'
    archivinglocationsallowed: 'locations'
    license: 'licence'
    licencesallowed: 'licences'
    'post-printembargo': 'embargo_months'
    depositstatementrequired: 'deposit_statement'
    copyrightowner: 'copyright_owner' # can be journal, publisher, affiliation or author
    publicnotes: 'notes'
    authoraffiliationrolerequirement: 'requirements.role'
    authoraffiliationrequirement: 'requirements.affiliation'
    authoraffiliationdepartmentrequirement: 'requirements.departmental_affiliation'
    iffundedby: 'requirements.funder'
    fundingproportionrequired: 'requirements.funding_proportion'
    subjectcoverage: 'requirements.subject'
    has_policy: 'issuer.has_policy'
    permissiontype: 'issuer.type'
    parentpolicy: 'issuer.parent_policy'
    contributedby: 'meta.contributors'
    recordlastupdated: 'meta.updated'
    reviewers: 'meta.reviewer'
    addedby: 'meta.creator'
    monitoringtype: 'meta.monitoring'
    policyfulltext: 'provenance.archiving_policy'
    policylandingpage: 'provenance.archiving_policy_splash'
    publishingagreement: 'provenance.sample_publishing_agreement'
    publishingagreementsplash: 'provenance.sample_publishing_splash'
    rights: 'provenance.author_rights'
    embargolist: 'provenance.embargo_list'
    policyfaq: 'provenance.faq'
    miscsource: 'provenance.misc_source'
    enforcementdate: 'provenance.enforcement_from'
    example: 'provenance.example'

  ready = []
  for rec in recs
    nr = 
      can_archive: false
      version: undefined
      versions: undefined
      licence: undefined
      licence_terms: undefined
      licences: undefined
      locations: undefined
      embargo_months: undefined
      embargo_end: undefined
      deposit_statement: undefined
      permission_required: undefined
      permissions_contact: undefined
      copyright_owner: undefined
      copyright_name: undefined
      copyright_year: undefined
      notes: undefined
      requirements: undefined
      issuer: {}
      meta: {}
      provenance: undefined

    try
      rec.recordlastupdated = rec.recordlastupdated.trim()
      if rec.recordlastupdated.indexOf(',') isnt -1
        nd = false
        for dt in rec.recordlastupdated.split ','
          nd = dt.trim() if nd is false or moment(dt.trim(),'DD/MM/YYYY').isAfter(moment(nd,'DD/MM/YYYY'))
        rec.recordlastupdated = nd if nd isnt false
      nr.meta.updated = rec.recordlastupdated
    nr.meta.updatedAt = moment(nr.meta.updated, 'DD/MM/YYYY').valueOf() if nr.meta.updated?

    # the google feed import will lowercase these key names and remove whitespace, question marks, brackets too, but not dashes
    nr.issuer.id = if rec.id.indexOf(',') isnt -1 then rec.id.split(',') else rec.id
    if typeof nr.issuer.id isnt 'string'
      cids = []
      inaj = false
      for nid in nr.issuer.id
        nid = nid.trim()
        if nr.issuer.type is 'journal' and nid.indexOf('-') isnt -1 and nid.indexOf(' ') is -1
          nid = nid.toUpperCase()
          if af = academic_journal.find 'issn.exact:"' + nid + '"'
            inaj = true
            for an in af.issn
              cids.push(an) if an not in cids
        cids.push(nid) if nid not in cids
      nr.issuer.id = cids
    nr.permission_required = rec.has_policy? and rec.has_policy.toLowerCase().indexOf('permission required') isnt -1

    for k of rec
      if keys[k] and rec[k]? and rec[k].length isnt 0
        nk = keys[k]
        nv = undefined
        if k is 'post-printembargo' # Post-Print Embargo - empty or number of months like 0, 12, 24
          try
            kn = parseInt rec[k].trim()
            nv = kn if typeof kn is 'number' and not isNaN kn and kn isnt 0
            nr.embargo_end = '' if nv? # just to allow neat output later - can't be calculated until compared to a particular article
        else if k in ['journal', 'versionsarchivable', 'archivinglocationsallowed', 'licencesallowed', 'policyfulltext', 'contributedby', 'addedby', 'reviewers', 'iffundedby']
          nv = []
          for s in rcs = rec[k].trim().split ','
            st = s.trim()
            if k is 'licencesallowed'
              if st.toLowerCase() isnt 'unclear'
                lc = type: st.toLowerCase()
                try lc.terms = rec.licenceterms.split(',')[rcs.indexOf(s)].trim() # these don't seem to exist any more...
                nv.push lc
            else
              if k is 'versionsarchivable'
                st = st.toLowerCase()
                st = 'submittedVersion' if st is 'preprint'
                st = 'acceptedVersion' if st is 'postprint'
                st = 'publishedVersion' if st is 'publisher pdf'
              nv.push(if k in ['archivinglocationsallowed'] then st.toLowerCase() else st) if st.length and st not in nv
        else if k not in ['recordlastupdated']
          nv = rec[k].trim()
        nv = nv.toLowerCase() if typeof nv is 'string' and (nv.toLowerCase() in ['yes','no'] or k in ['haspolicy','permissiontype','copyrightowner'])
        nv = '' if k in ['copyrightowner','license'] and nv is 'unclear'
        if nv?
          if nk.indexOf('.') isnt -1
            nps = nk.split '.'
            nr[nps[0]] ?= {}
            nr[nps[0]][[nps[1]]] = nv
          else
            nr[nk] = nv

    # Archived Full Text Link - a URL to a web archive link of the full text policy link (ever multiple?)
    # Record First Added - date like 12/07/2017
    # Post-publication Pre-print Update Allowed - string like No, Yes, could be empty (turn these to booleans?)
    # Can Authors Opt Out - seems to be all empty, could presumably be Yes or No

    nr.licences ?= []
    if not nr.licence
      for l in nr.licences
        if not nr.licence? or l.type.length < nr.licence.length
          nr.licence = l.type
          nr.licence_terms = l.terms
    nr.versions ?= []
    if nr.versions.length
      nr.can_archive = true
      nr.version = if 'acceptedVersion' in nr.versions or 'postprint' in nr.versions then 'acceptedVersion' else if 'publishedVersion' in nr.versions or 'publisher pdf' in nr.versions then 'publishedVersion' else 'submittedVersion'
    nr.copyright_owner ?= nr.issuer?.type ? ''
    nr.copyright_name ?= ''
    nr.copyright_year ?= '' # the year of publication, to be added at result stage
    ready.push(nr) if not JSON.stringify(nr) isnt '{}'

    # TODO if there is a provenance.example DOI look up the metadata for it and find the journal ISSN. 
    # then have a search for ISSN be able to find that. Otherwise, we have coverage by publisher that 
    # contains no journal info, so no way to go from ISSN to the stored record

  if ready.length
    oab_permissions.remove '*'
    oab_permissions.insert ready
  return ready.length

P.svc.oaworks.permission._sheet = '1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A'



'''
API.add 'service/oab/request/:rid',
  post:
    roleRequired:'openaccessbutton.user',
    action: () ->
      if r = oab_request.get this.urlParams.rid
        n = {}
        if not r.user? and not r.story? and this.request.body.story
          n.story = this.request.body.story
          n.user = id: this.user._id, email: this.user.emails[0].address, username: (this.user.profile?.firstname ? this.user.username ? this.user.emails[0].address)
          n.user.firstname = this.user.profile?.firstname
          n.user.lastname = this.user.profile?.lastname
          n.user.affiliation = this.user.service?.openaccessbutton?.profile?.affiliation
          n.user.profession = this.user.service?.openaccessbutton?.profile?.profession
          n.count = 1 if not r.count? or r.count is 0
        if API.accounts.auth 'openaccessbutton.admin', this.user
          n.test ?= this.request.body.test if this.request.body.test? and this.request.body.test isnt r.test
          n.status ?= this.request.body.status if this.request.body.status? and this.request.body.status isnt r.status
          n.rating ?= this.request.body.rating if this.request.body.rating? and this.request.body.rating isnt r.rating
          n.name ?= this.request.body.name if this.request.body.name? and this.request.body.name isnt r.name
          n.email ?= this.request.body.email if this.request.body.email? and this.request.body.email isnt r.email
          n.author_affiliation ?= this.request.body.author_affiliation if this.request.body.author_affiliation? and this.request.body.author_affiliation isnt r.author_affiliation
          n.story ?= this.request.body.story if this.request.body.story? and this.request.body.story isnt r.story
          n.journal ?= this.request.body.journal if this.request.body.journal? and this.request.body.journal isnt r.journal
          n.notes = this.request.body.notes if this.request.body.notes? and this.request.body.notes isnt r.notes
          n.access_right = this.request.body.access_right if this.request.body.access_right? and this.request.body.access_right isnt r.access_right
          n.embargo_date = this.request.body.embargo_date if this.request.body.embargo_date? and this.request.body.embargo_date isnt r.embargo_date
          n.access_conditions = this.request.body.access_conditions if this.request.body.access_conditions? and this.request.body.access_conditions isnt r.access_conditions
          n.license = this.request.body.license if this.request.body.license? and this.request.body.license isnt r.license
          if this.request.body.received?.description? and (not r.received? or this.request.body.received.description isnt r.received.description)
            n.received = if r.received? then r.received else {}
            n.received.description = this.request.body.received.description
        n.email = this.request.body.email if this.request.body.email? and ( API.accounts.auth('openaccessbutton.admin',this.user) || not r.status? || r.status is 'help' || r.status is 'moderate' || r.status is 'refused' )
        n.story = this.request.body.story if r.user? and this.userId is r.user.id and this.request.body.story? and this.request.body.story isnt r.story
        n.url ?= this.request.body.url if this.request.body.url? and this.request.body.url isnt r.url
        n.title ?= this.request.body.title if this.request.body.title? and this.request.body.title isnt r.title
        n.doi ?= this.request.body.doi if this.request.body.doi? and this.request.body.doi isnt r.doi
        if n.story
          res = oab_request.search 'rating:1 AND story.exact:"' + n.story + '"'
          if res.hits.total
            nres = oab_request.search 'rating:0 AND story.exact:"' + n.story + '"'
            n.rating = 1 if nres.hits.total is 0
        if not n.status?
          if (not r.title and not n.title) || (not r.email and not n.email) || (not r.story and not n.story)
            n.status = 'help' if r.status isnt 'help'
          else if r.status is 'help' and ( (r.title or n.title) and (r.email or n.email) and (r.story or n.story) )
            n.status = 'moderate'
        if n.title? and typeof n.title is 'string'
          try n.title = n.title.charAt(0).toUpperCase() + n.title.slice(1)
        if n.journal? and typeof n.journal is 'string'
          try n.journal = n.journal.charAt(0).toUpperCase() + n.journal.slice(1)
        if not n.doi? and not r.doi? and r.url? and r.url.indexOf('10.') isnt -1 and r.url.split('10.')[1].indexOf('/') isnt -1
          n.doi = '10.' + r.url.split('10.')[1]
          r.doi = n.doi
        if (r.doi or r.url) and not r.title and not n.title
          try
            cr = if r.doi then API.service.oab.metadata(undefined, {doi: r.doi}) else API.service.oab.metadata {url: r.url}
            for c of cr
              n[c] ?= cr[c] if not r[c]?
        r.author_affiliation = n.author_affiliation if n.author_affiliation?
        if n.crossref_type? and n.crossref_type isnt 'journal-article'
          n.status = 'closed'
          n.closed_on_update = true
          n.closed_on_update_reason = 'notarticle'
        if (not r.email and not n.email) and r.author and r.author.length and (r.author[0].affiliation? or r.author_affiliation)
          try
            email = API.use.hunter.email {company: (r.author_affiliation ? r.author[0].affiliation[0].name), first_name: r.author[0].family, last_name: r.author[0].given}, API.settings.service.openaccessbutton.hunter.api_key
            if email?.email?
              n.email = email.email
        oab_request.update(r._id,n) if JSON.stringify(n) isnt '{}'
        if (r.user?.email? or n.user?.email?) and (not r.user or (not r.story? and n.story))
          try
            tmpl = API.mail.template 'initiator_confirmation.html'
            sub = API.service.oab.substitute tmpl.content, {_id: r._id, url: (r.url ? n.url), title:(r.title ? n.title ? r.url) }
            API.mail.send
              service: 'openaccessbutton',
              from: sub.from ? API.settings.service.openaccessbutton.mail.from
              to: n.user?.email ? r.user.email
              subject: sub.subject ? 'New request created ' + r._id
              html: sub.content
        return oab_request.get r._id
      else
        return 404
  delete:
    roleRequired:'openaccessbutton.user'
    action: () ->
      r = oab_request.get this.urlParams.rid
      oab_request.remove(this.urlParams.rid) if API.accounts.auth('openaccessbutton.admin',this.user) or this.userId is r.user.id
      return {}
'''


###
to create a request the url and type are required, What about story?
{
  url: "url of item request is about",
  story: "the story of why this request / support, if supplied",
  email: "email address of person to contact to request",
  count: "the count of how many people support this request",
  createdAt: "date request was created",
  status: "help OR moderate OR progress OR hold OR refused OR received OR closed",
  receiver: "unique ID that the receive endpoint will use to accept one-time submission of content",
  title: "article title",
  doi: "article doi",
  user: {
    id: "user ID of user who created request",
    username: "username of user who created request",
    email: "email of user who created request"
  }
}
###
'''
P.svc.oaworks.request = (req, uacc, fast, notify=true) ->
  dom
  if req.dom
    dom = req.dom
    delete req.dom
  return false if JSON.stringify(req).indexOf('<script') isnt -1
  req = @tdm.clean req
  req.type ?= 'article'
  req.url = req.url[0] if _.isArray req.url
  req.doi = req.url if not req.doi? and req.url? and req.url.indexOf('10.') isnt -1 and req.url.split('10.')[1].indexOf('/') isnt -1
  req.doi = '10.' + req.doi.split('10.')[1].split('?')[0].split('#')[0] if req.doi? and req.doi.indexOf('10.') isnt 0
  req.doi = decodeURIComponent(req.doi) if req.doi
  if req.url? and req.url.indexOf('eu.alma.exlibrisgroup.com') isnt -1
    req.url += (if req.url.indexOf('?') is -1 then '?' else '&') + 'oabLibris=' + Random.id()
    if req.title? and typeof req.title is 'string' and req.title.length > 0 and texist = oab_request.find {title:req.title,type:req.type}
      texist.cache = true
      return texist
  else if req.doi or req.title or req.url
    eq = {type: req.type}
    if req.doi
      eq.doi = req.doi
    else if req.title
      eq.title = req.title
    else
      eq.url = req.url
    if exists = oab_request.find eq
      exists.cache = true
      return exists
  return false if not req.test and @svc.oaworks.blacklist req.url

  rid = if req._id and oab_request.get(req._id) then req._id else oab_request.insert {url:req.url,type:req.type,_id:req._id}
  user = if uacc then (if typeof uacc is 'string' then API.accounts.retrieve(uacc) else uacc) else undefined
  send_confirmation = false
  if not req.user? and user and req.story
    send_confirmation = true
    un = user.profile?.firstname ? user.username ? user.emails[0].address
    req.user =
      id: user._id
      username: un
      email: user.emails[0].address
      firstname: user.profile?.firstname
      lastname: user.profile?.lastname
      affiliation: user.service?.openaccessbutton?.profile?.affiliation
      profession: user.service?.openaccessbutton?.profile?.profession
  req.count ?= if req.story then 1 else 0

  if not req.doi or not req.title or not req.email
    try
      cr = @svc.oaworks.metadata {url: req.url}, {doi: req.doi}
      for c of cr
        if c is 'email'
          for e in cr.email
            isauthor = false
            if cr?.author?
              for a in cr.author
                isauthor = a.family and e.toLowerCase().indexOf(a.family.toLowerCase()) isnt -1
            if isauthor and @mail.validate(e, @S.svc.oaworks.mail?.pubkey).is_valid
              req.email = e
              break
        else
          req[c] ?= cr[c]
  if _.isArray(req.author) and not req.author_affiliation
    for author in req.author
      try
        if req.email.toLowerCase().indexOf(author.family) isnt -1
          req.author_affiliation = author.affiliation[0].name
          break
  req.keywords ?= []
  req.title ?= ''
  req.doi ?= ''
  req.author = []
  req.journal = ''
  req.issn = ''
  req.publisher = ''
  if not req.email and req.author_affiliation
    try
      for author in req.author
        if author.affiliation[0].name is req.author_affiliation
          # it would be possible to lookup ORCID here if the author has one in the crossref data, but that would only get us an email for people who make it public
          # previous analysis showed that this is rare. So not doing it yet
          email = @src.hunter.email {company: req.author_affiliation, first_name: author.family, last_name: author.given}, @S.svc.oaworks.hunter.api_key
          if email?.email?
            req.email = email.email
            break

  if req.story
    res = oab_request.search 'rating:1 AND story.exact:"' + req.story + '"'
    if res.hits.total
      nres = oab_request.search 'rating:0 AND story.exact:"' + req.story + '"'
      req.rating = 1 if nres.hits.total is 0

  req.status ?= if not req.story or not req.title or not req.email or not req.user? then "help" else "moderate"
  if req.year
    try
      req.year = parseInt(req.year) if typeof req.year is 'string'
      if req.year < 2000
        req.status = 'closed'
        req.closed_on_create = true
        req.closed_on_create_reason = 'pre2000'
    try
      if fast and (new Date()).getFullYear() - req.year > 5 # only doing these on fast means only doing them via UI for now
        req.status = 'closed'
        req.closed_on_create = true
        req.closed_on_create_reason = 'gt5'
  if fast and not req.doi? and req.status isnt 'closed'
    req.status = 'closed'
    req.closed_on_create = true
    req.closed_on_create_reason = 'nodoi'
  if fast and req.crossref_type? and req.crossref_type isnt 'journal-article' and req.status isnt 'closed'
    req.status = 'closed'
    req.closed_on_create = true
    req.closed_on_create_reason = 'notarticle'

  req.receiver = @uid()
  req._id = rid
  if req.title? and typeof req.title is 'string'
    try req.title = req.title.charAt(0).toUpperCase() + req.title.slice(1)
  if req.journal? and typeof req.journal is 'string'
    try req.journal = req.journal.charAt(0).toUpperCase() + req.journal.slice(1)
  oab_request.update rid, req
  if (fast and req.user?.email?) or send_confirmation
    try
      tmpl = API.mail.template 'initiator_confirmation.html'
      sub = API.service.oab.substitute tmpl.content, {_id: req._id, url: req.url, title:(req.title ? req.url) }
      @mail
        service: 'openaccessbutton',
        from: sub.from ? @S.svc.oaworks.mail.from
        to: req.user.email
        subject: sub.subject ? 'New request created ' + req._id
        html: sub.content
  if req.story # and notify
    # for now still send if not notify, but remove Natalia (Joe requested it this way, so he still gets them on bulk creates, but Natalia does not)
    addrs = @S.svc.oaworks.notify.request
    if not notify and typeof addrs isnt 'string' and 'natalia.norori@openaccessbutton.org' in addrs
      addrs.splice(addrs.indexOf('natalia.norori@openaccessbutton.org'),1)
    @mail
      service: 'openaccessbutton'
      from: 'natalia.norori@openaccessbutton.org'
      to: addrs
      subject: 'New request created ' + req._id
      text: (if @S.dev then 'https://dev.openaccessbutton.org/request/' else 'https://openaccessbutton.org/request/') + req._id
  return req
'''


# https://jcheminf.springeropen.com/articles/10.1186/1758-2946-3-47
P.svc.oaworks.scrape = (content, doi) ->
  meta = {doi:doi}
  if typeof content is 'string' and content.startsWith 'http'
    if not meta.doi # quick check to get a DOI if at the end of a URL, as they often are
      mr = new RegExp /\/(10\.[^ &#]+\/[^ &#]+)$/
      ud = mr.exec decodeURIComponent content
      meta.doi = ud[1] if ud and ud.length > 1 and 9 < ud[1].length and ud[1].length < 45 and ud[1].indexOf('/') isnt -1 and ud[1].indexOf('10.') is 0
    #if content.indexOf('.pdf') isnt -1
    #  try content = await @convert.pdf2txt url
    #try content ?= await @puppet url
    content ?= await @fetch url

  return {} if typeof content isnt 'string'

  if content.indexOf('<') isnt 0 and content.length > 6000
    content = content.substring(0,6000)  # we only check the first three or so pages of content (3000 chars per page estimates 500 words per page)
  else if content.length > 50000
    content = content.substring(0,50000) # but for apparently html or xml sorts of content, take more to get through all metadata
    
  if not meta.doi
    try
      cl = content.toLowerCase()
      if cl.indexOf('dc.identifier') isnt -1
        cl = cl.split('dc.identifier')[1].split('content')[1]
        cl = cl.split('"')[1] if cl.indexOf('"') isnt -1
        cl = cl.split("'")[1] if cl.indexOf("'") isnt -1
        meta.doi = cl if cl.indexOf('10.') is 0 and cl.indexOf('/') isnt -1

  if not meta.doi
    try
      cl ?= content.toLowerCase()
      if cl.indexOf('citation_doi') isnt -1
        cl = cl.split('citation_doi')[1].split('content')[1]
        cl = cl.split('"')[1] if cl.indexOf('"') isnt -1
        cl = cl.split("'")[1] if cl.indexOf("'") isnt -1
        meta.doi = cl if cl.indexOf('10.') is 0 and cl.indexOf('/') isnt -1

  if not meta.doi # look for a doi in the first 600 words
    cnts = 0
    for str in content.split(' ')
      cnts += 1
      if cnts < 600
        str = str.replace(/ /g,'').replace('doi:','')
        str = str.split('doi.org')[1] if str.indexOf('doi.org') isnt -1
        str = str.replace('/','') if str.indexOf('/') is 0
        str = str.trim()
        if str.indexOf('10.') is 0 and str.indexOf('/') isnt -1 # don't use a regex
          meta.doi = str
          break
      
  if not meta.doi
    try
      d = @tdm.extract
        content:content
        matchers:['/doi[^>;]*?(?:=|:)[^>;]*?(10[.].*?\/.*?)("|\')/gi','/doi[.]org/(10[.].*?/.*?)("| \')/gi']
      for n in d.matches
        if not meta.doi and 9 < d.matches[n].result[1].length and d.matches[n].result[1].length < 45
          meta.doi = d.matches[n].result[1]
          meta.doi = meta.doi.substring(0,meta.doi.length-1) if meta.doi.endsWith('.')

  meta.doi = meta.doi.split(' ')[0] if meta.doi # catch some spacing issues that sometimes come through
    
  if not meta.title
    cl = content.toLowerCase()
    if cl.indexOf('requestdisplaytitle') isnt -1
      meta.title = cl.split('requestdisplaytitle').pop().split('>')[1].split('<')[0].trim().replace(/"/g,'')
    else if cl.indexOf('dc.title') isnt -1
      meta.title = cl.split('dc.title')[1].replace(/'/g,'"').split('content=')[1].split('"')[1].trim().replace(/"/g,'')
    else if cl.indexOf('eprints.title') isnt -1
      meta.title = cl.split('eprints.title')[1].replace(/'/g,'"').split('content=')[1].split('"')[1].trim().replace(/"/g,'')
    else if cl.indexOf('og:title') isnt -1
      meta.title = cl.split('og:title')[1].split('content')[1].split('=')[1].replace('/>','>').split('>')[0].trim().replace(/"/g,'')
      meta.title = meta.title.substring(1,meta.title.length-1) if meta.title.startsWith("'")
    else if cl.indexOf('"citation_title" ') isnt -1
      meta.title = cl.split('"citation_title" ')[1].replace(/ = /,'=').split('content="')[1].split('"')[0].trim().replace(/"/g,'')
    else if cl.indexOf('<title') isnt -1
      meta.title = cl.split('<title')[1].split('>')[1].split('</title')[0].trim().replace(/"/g,'')
  meta.title = meta.title.split('|')[0].trim() if meta.title and meta.title.indexOf('|') isnt -1

  if not meta.year
    try
      k = @tdm.extract({
        content:content,
        matchers:[
          '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')citation_date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi',
          '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')dc.date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi',
          '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')prism.publicationDate(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi'
        ],
        start:'<head',
        end:'</head'
      })
      mk = k.matches[0].result[1]
      mkp = mk.split('-')
      if mkp.length is 1
        meta.year = mkp[0]
      else
        for my in mkp
          if my.length > 2
            meta.year = my
    
  if not meta.keywords
    try
      k = @tdm.extract
        content:content
        matchers:['/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')keywords(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi']
        start:'<head'
        end:'</head'
      kk = k.matches[0].result[1]
      if kk.indexOf(';') isnt -1
        kk = kk.replace(/; /g,';').replace(/ ;/g,';')
        meta.keywords = kk.split(';')
      else
        kk = kk.replace(/, /g,',').replace(/ ,/g,',')
        meta.keywords = kk.split(',')

  if not meta.email
    mls = []
    try
      m = @tdm.extract
        content:content
        matchers:['/mailto:([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi','/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
      for i in m.matches
        mm = i.result[1].replace('mailto:','')
        mm = mm.substring(0,mm.length-1) if mm.endsWith('.')
        mls.push(mm) if mls.indexOf(mm) is -1
    mls.sort ((a, b) -> return b.length - a.length)
    mstr = ''
    meta.email = []
    for me in mls
      meta.email.push(me) if mstr.indexOf(me) is -1
      mstr += me

  return meta


P.tdm = {}

P.tdm.clean = (text) ->
	text ?= this?.params?.clean ? this?.params?.text ? this?.params?.q
	_bad_chars = [
		{bad: '‘', good: "'"},
		{bad: '’', good: "'"},
		{bad: '´', good: "'"},
		{bad: '“', good: '"'},
		{bad: '”', good: '"'},
		{bad: '–', good: '-'},
		{bad: '-', good: '-'}
	]
	for c in _bad_chars
		re = new RegExp c.bad, 'g'
		text = text.replace re, c.good
	return text

P.tdm.occurrence = (content, sub, overlap) ->
	content ?= this?.params?.content ? this?.params?.url
	content = @fetch(content) if content.indexOf('http') is 0
	sub ?= this?.params?.sub ? this?.params?.q
	overlap ?= this?.params?.overlap
	content += ""
	sub += ""
	return (content.length + 1) if sub.length <= 0
	n = 0
	pos = 0
	step = if overlap then 1 else sub.length
	while true
		pos = content.indexOf sub, pos
		if pos >= 0
			++n
			pos += step
		else break
	return n

P.tdm.levenshtein = (a, b, lowercase) ->
	a ?= this?.params?.a
	b ?= this?.params?.b
	lowercase ?= this?.params?.lowercase ? true
	if lowercase
		a = a.toLowerCase()
		b = b.toLowerCase()
	minimator = (x, y, z) ->
		return x if x <= y and x <= z
		return y if y <= x and y <= z
		return z

	m = a.length
	n = b.length

	if m < n
		c = a
		a = b
		b = c
		o = m
		m = n
		n = o

	r = [[]]
	c = 0
	while c < n + 1
		r[0][c] = c
		c++

	i = 1
	while i < m + 1
		r[i] = [i]
		j = 1
		while j < n + 1
			cost = if a.charAt( i - 1 ) is b.charAt( j - 1 ) then 0 else 1
			r[i][j] = minimator( r[i-1][j] + 1, r[i][j-1] + 1, r[i-1][j-1] + cost )
			j++
		i++

	return distance: r[ r.length - 1 ][ r[ r.length - 1 ].length - 1 ], length: {a:m, b:n} #, detail: r

# https://en.wikipedia.org/wiki/Hamming_distance#Algorithm_example
# this is faster than levenshtein but not always so useful
# this works slightly better with perceptual hashes, or anything where just need to know how many changes to make to become the same
# for example the levenshtein difference between 1234567890 and 0123456789 is 2
# whereas the hamming distance is 10
P.tdm.hamming = (a, b, lowercase) ->
	a ?= this?.params?.a
	b ?= this?.params?.b
	lowercase ?= this?.params?.lowercase ? true
	if lowercase
		a = a.toLowerCase()
		b = b.toLowerCase()
	if a.length < b.length
		short = a
		long = b
	else
		short = b
		long = a
	pos = long.indexOf short
	ss = short.split('')
	sl = long.split('')
	if sl.length > ss.length
		diff = sl.length - ss.length
		if 0 < pos
			pc = 0
			while pc < pos
				ss.unshift ''
				pc++
				diff--
		c = 0
		while c < diff
			ss.push ''
			c++
	moves = 0
	for k of sl
		moves++ if ss[k] isnt sl[k]
	return moves

P.tdm.extract = (opts) ->
	# opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
	if opts.url and not opts.content
		if opts.url.indexOf('.pdf') isnt -1 or opts.url.indexOf('/pdf') isnt -1
			opts.convert ?= 'pdf'
		else
			opts.content = P.http.puppeteer opts.url, true
	try
		text = if opts.convert then P.convert.run(opts.url ? opts.content, opts.convert, 'txt') else opts.content
	catch
		text = opts.content

	opts.matchers ?= [opts.match]
	if opts.start?
		parts = text.split opts.start
		text = if parts.length > 1 then parts[1] else parts[0]
	text = text.split(opts.end)[0] if opts.end?
	text = text.toLowerCase() if opts.lowercase
	text = text.replace(/[^a-z0-9]/g,'') if opts.ascii
	text = text.replace(/ /g,'') if opts.spaces is false

	res = {length:text.length, matched:0, matches:[], matchers:opts.matchers, text: text}

	if text and typeof text isnt 'number'
		for match in opts.matchers
			mopts = 'g'
			mopts += 'i' if opts.lowercase
			if match.indexOf('/') is 0
				lastslash = match.lastIndexOf '/'
				if lastslash+1 isnt match.length
					mopts = match.substring lastslash+1
					match = match.substring 1,lastslash
			else
				match = match.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&")
			m
			mr = new RegExp match,mopts
			while m = mr.exec(text)
				res.matched += 1
				res.matches.push {matched:match,result:m}

	return res

P.tdm.emails = (opts={}) ->
	opts.matchers = ['/([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi','/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
	emails = []
	checked = []
	ex = P.tdm.extract opts
	for pm in ex.matches
		for pmr in pm.result
			if pmr not in checked
				emails.push(pmr) if typeof P.mail?.validate? isnt 'function' or P.mail.validate(pmr, P.settings.service?.openaccessbutton?.mail?.pubkey).is_valid
			checked.push pmr
	return emails

P.tdm.stopwords = (stops, more, gramstops=true) -> 
	# removed wordpos option from this
	stops ?= ['purl','w3','http','https','ref','html','www','ref','cite','url','title','date','nbsp','doi','fig','figure','supplemental',
		'year','time','january','february','march','april','may','june','july','august','september','october','november','december',
		'jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec','keywords','revised','accepted','file','attribution',
		'org','com','id','wp','main','website','blogs','media','people','years','made','location','its','asterisk','called','xp','er'
		'image','jpeg','jpg','png','php','object','false','true','article','chapter','book','caps','isbn','scale','axis','accessed','email','e-mail',
		'story','first1','first2','last1','last2','general','list','accessdate','view_news','d0','dq','sfnref','onepage','sfn','authorlink']
	gramstops = ["apos", "as", "able", "about", "above", "according", "accordingly", "across", "actually", "after", "afterwards", 
		"again", "against", "aint", "all", "allow", "allows", "almost", "alone", "along", "already", "also", "although", "always", "am", 
		"among", "amongst", "an", "and", "another", "any", "anybody", "anyhow", "anyone", "anything", "anyway", "anyways", "anywhere", 
		"apart", "appear", "appreciate", "appropriate", "are", "arent", "around", "as", "aside", "ask", "asking", "associated", "at", 
		"available", "away", "awfully", "be", "became", "because", "become", "becomes", "becoming", "been", "before", "beforehand", 
		"behind", "being", "believe", "below", "beside", "besides", "best", "better", "between", "beyond", "both", "brief", "but", "by", 
		"cmon", "cs", "came", "can", "cant", "cannot", "cant", "cause", "causes", "certain", "certainly", "changes", "clearly", "co", 
		"com", "come", "comes", "concerning", "consequently", "consider", "considering", "contain", "containing", "contains", "corresponding", 
		"could", "couldnt", "course", "currently", "definitely", "described", "despite", "did", "didnt", "different", "do", "does", "doesnt", 
		"doing", "dont", "done", "down", "downwards", "during", "each", "edu", "eg", "eight", "either", "else", "elsewhere", "enough", "entirely", 
		"especially", "et", "etc", "even", "ever", "every", "everybody", "everyone", "everything", "everywhere", "ex", "exactly", "example", "except", 
		"far", "few", "fifth", "first", "five", "followed", "following", "follows", "for", "former", "formerly", "forth", "four", "from", "further", 
		"furthermore", "get", "gets", "getting", "given", "gives", "go", "goes", "going", "gone", "got", "gotten", "greetings", "had", "hadnt", 
		"happens", "hardly", "has", "hasnt", "have", "havent", "having", "he", "hes", "hello", "help", "hence", "her", "here", "heres", "hereafter", 
		"hereby", "herein", "hereupon", "hers", "herself", "hi", "him", "himself", "his", "hither", "hopefully", "how", "howbeit", "however", "i", "I", 
		"id", "ill", "im", "ive", "ie", "if", "ignored", "immediate", "in", "inasmuch", "inc", "indeed", "indicate", "indicated", "indicates", "
		inner", "insofar", "instead", "into", "inward", "is", "isnt", "it", "itd", "itll", "its", "itself", "just", "keep", "keeps", "kept", 
		"know", "knows", "known", "last", "lately", "later", "latter", "latterly", "least", "less", "lest", "let", "lets", "like", "liked", "likely", 
		"little", "look", "looking", "looks", "ltd", "mainly", "many", "may", "maybe", "me", "mean", "meanwhile", "merely", "might", "more", "moreover", 
		"most", "mostly", "much", "must", "my", "myself", "name", "namely", "nd", "near", "nearly", "necessary", "need", "needs", "neither", "never", 
		"nevertheless", "new", "next", "nine", "no", "nobody", "non", "none", "noone", "nor", "normally", "not", "nothing", "now", "nowhere", 
		"obviously", "of", "off", "often", "oh", "ok", "okay", "old", "on", "once", "one", "ones", "only", "onto", "or", "other", "others", "otherwise", 
		"ought", "our", "ours", "ourselves", "out", "outside", "over", "overall", "own", "particular", "particularly", "per", "perhaps", "placed", 
		"please", "plus", "possible", "presumably", "probably", "provides", "que", "quite", "qv", "rather", "rd", "re", "really", "reasonably", 
		"regarding", "regardless", "regards", "relatively", "respectively", "right", "said", "same", "saw", "say", "saying", "says", "second", 
		"secondly", "see", "seeing", "seem", "seemed", "seeming", "seems", "seen", "self", "selves", "sensible", "sent", "serious", "seriously", 
		"seven", "several", "shall", "she", "should", "shouldnt", "since", "six", "so", "some", "somebody", "somehow", "someone", "something", 
		"sometime", "sometimes", "somewhat", "somewhere", "soon", "sorry", "specified", "specify", "specifying", "still", "sub", "such", "sup", "sure", 
		"ts", "take", "taken", "tell", "tends", "th", "than", "thank", "thanks", "thanx", "that", "thats", "thats", "the", "their", "theirs", "them", 
		"themselves", "then", "thence", "there", "theres", "thereafter", "thereby", "therefore", "therein", "theres", "thereupon", "these", "they", 
		"theyd", "theyll", "theyre", "theyve", "think", "third", "this", "thorough", "thoroughly", "those", "though", "three", "through", 
		"throughout", "thru", "thus", "to", "together", "too", "took", "toward", "towards", "tried", "tries", "truly", "try", "trying", "twice", 
		"two", "un", "under", "unfortunately", "unless", "unlikely", "until", "unto", "up", "upon", "us", "use", "used", "useful", "uses", "using", 
		"usually", "value", "various", "very", "via", "viz", "vs", "want", "wants", "was", "wasnt", "way", "we", "wed", "well", "weve", 
		"welcome", "well", "went", "were", "werent", "what", "whats", "whatever", "when", "whence", "whenever", "where", "wheres", "whereafter", 
		"whereas", "whereby", "wherein", "whereupon", "wherever", "whether", "which", "while", "whither", "who", "whos", "whoever", "whole", "whom", 
		"whose", "why", "will", "willing", "wish", "with", "within", "without", "wont", "wonder", "would", "would", "wouldnt", "yes", "yet", "you", 
		"youd", "youll", "youre", "youve", "your", "yours", "yourself", "yourselves", "zero"]
	if gramstops
		for g in gramstops
			stops.push(g) if g not in stops
	if more
		more = more.split(',') if typeof more is 'string'
		for m in more
			stops.push(m) if m not in stops
	return stops


import { customAlphabet } from 'nanoid'

P.uid = (r) ->
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 100) IDs per second for 131000 years.
  nanoid = customAlphabet (@params.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz-'), @params.len ? @params.length ? @params.size ? @params.uid ? 21
  return nanoid()

P.uid._cache = false

P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

P.keys = (obj) ->
  try obj ?= @params
  keys = []
  for k of obj ? {}
    keys.push(k) if obj[k]? and k not in keys
  return keys

P.sleep = (ms) -> # await this when calling it to actually wait
  try ms ?= @params.ms
  return new Promise (resolve) => setTimeout resolve, ms ? 1000

P.hash = (msg) ->
  try msg ?= @params.hash ? @request.body ? @params.q ? @params
  msg = JSON.stringify(msg) if typeof msg isnt 'string'
  msg = new TextEncoder().encode msg
  buf = await crypto.subtle.digest "SHA-256", msg 
  arr = new Uint8Array buf
  parts = []
  for b in arr
    parts.push ('00' + b.toString(16)).slice(-2)
  return parts.join ''
# the above works on CF worker, but crypto.subtle probably needs to be replaced with standard crypto module on backend
# the below is a possible example, but note will need to use same params that generate the same result
'''P.hash = (str, lowercase=false, uri=true, encoding='utf8', digest) -> # alternatively base64, but can cause problems if later used in URLs
  str = str.toLowerCase() if lowercase is true
  str = encodeURIComponent(str) if uri is true
  hash = crypto.createHash('md5').update(str, encoding)
  return if digest is 'hex' then hash.digest('hex') else hash.digest('base64').replace(/\//g,'_').replace(/\+/g,'-')
'''

P.dot = (obj, key) ->
  # TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if typeof obj is 'string' and typeof key is 'object'
    st = obj
    obj = key
    key = st
  obj = @copy(obj) if obj?
  if not obj? and this?.params?.key?
    obj = @copy @params
    key = obj.key
    delete obj.key
  key = key.split('.') if typeof key is 'string'
  obj = obj[k] for k in key
  return obj


'''
P.retry = (fn, params=[], opts={}) ->
  # params should be a list of params for the fn
  params = [params] if not Array.isArray params
  opts.retry ?= 3
  opts.pause ?= 500
  opts.increment ?= true
  # can provide a function in opts.check to check the result each time, and an opts.timeout to timeout each loop

  while opts.retry > 0
    res = undefined
    _wrap = () ->
      try
        res = await fn.apply this, params
    if typeof opts.timeout is 'number'
      await Promise.race [_wrap.call(this), P.sleep(opts.timeout)]
    else
      _wrap.call this
    if typeof opts.check is 'function'
      retry = await opts.check res, retry
      if retry is true
        return res
      else if retry is false
        retry -= 1
      else if typeof retry isnt 'number'
        retry = 0
    else if res? and res isnt false
      return res
    else
      retry -= 1

    if typeof opts.pause is 'number' and opts.pause isnt 0
      await P.sleep opts.pause
      if opts.increment is true
        opts.pause = opts.pause * 2
      else if typeof opts.increment is 'number'
        opts.pause += opts.increment
    
  return undefined
'''


'''
# see https://github.com/arlac77/fetch-rate-limit-util/blob/master/src/rate-limit-util.mjs
MIN_WAIT_MSECS = 1000 # wait at least this long
MAX_RETRIES = 5 # only retry max this many times

/**
 * @param {Integer} millisecondsToWait
 * @param {Integer} rateLimitRemaining parsed from "x-ratelimit-remaining" header
 * @param {Integer} nthTry how often have we retried the request already
 * @param {Object} response as returned from fetch
 * @return {Integer} milliseconds to wait for next try or < 0 to deliver current response
 */
defaultWaitDecide = (millisecondsToWait, rateLimitRemaining, nthTry, response) ->
  return if nthTry > MAX_RETRIES then -1 else millisecondsToWait + MIN_WAIT_MSECS

rateLimitHandler = (fetcher, waitDecide = defaultWaitDecide) ->
  i = 0
  while true
    response = await fetcher()

    switch (response.status) ->
      default:
        return response

      case 403:
      case 429:
        # this differs by API we're hitting, example was for github. 
        # It's the timestamp of when the rate limit window would reset, generalise this
        rateLimitReset = parseInt response.headers.get "x-ratelimit-reset"

        millisecondsToWait = if isNaN(rateLimitReset) then 0 else new Date(rateLimitReset * 1000).getTime() - Date.now()

        millisecondsToWait = waitDecide(millisecondsToWait, parseInt(response.headers.get("x-ratelimit-remaining")), i, response)
        if millisecondsToWait <= 0
          return response
        else
          await new Promise resolve => setTimeout resolve, millisecondsToWait
    i++
'''



'''
P.decode = (content) ->
  _decode = (content) ->
    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g
    translate = {
      "nbsp":" ",
      "amp" : "&",
      "quot": "\"",
      "lt"  : "<",
      "gt"  : ">"
    }
    return content.replace(translator, ((match, entity) ->
      return translate[entity]
    )).replace(/&#(\d+);/gi, ((match, numStr) ->
      num = parseInt(numStr, 10)
      return String.fromCharCode(num)
    ))
  return _decode(content).replace(/\n/g,'')

P.str = (r) ->
  str = ''
  _str = (rp) ->
    if typeof rp is 'string'
      return rp
    else if rp is true
      return 'true'
    else if rp is false
      return 'false'
    else if typeof rp is 'function'
      return rp.toString()
    else if Array.isArray rp
      cr = []
      cr.push(_str a) for a in rp
      return JSON.stringify cr.sort()
    else if typeof rp is 'object'
      nob = ''
      keys = []
      keys.push(k) for k of rp
      for k in keys.sort()
        if nob.length is 0
          nob = '{'
        else
          nob += ','
        nob += '"' + o + '":"' + _str(rp[o]) + '"' for o of rp
      return nob + '}'
  str += _str r
  return str

P.flatten = (data) ->
  res = {}
  _flatten = (obj, key) ->
    for k of obj
      pk = if key then key + '.' + k else k
      v = obj[k]
      if typeof v is 'string'
        res[pk] = v
      else if Array.isArray v
        if typeof v[0] is 'object'
          for n of v
            _flatten v[n], pk + '.' + n
        else
          res[pk] = v.join(', ')
      else
        _flatten v, pk
  if Array.isArray data
    results = []
    for d in data
      res = {}
      results.push _flatten d
    return results
  else
    _flatten data
    return res

'''


S.built = "Sun Mar 7 03:36:22 GMT 2021"
