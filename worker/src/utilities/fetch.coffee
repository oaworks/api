
# https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

# NOTE TODO for getting certain file content, adding encoding: null to headers (or correct encoding required) can be helpful

# implement a rate limit option, where "rate" param can be passed. It should be a list [group,10,100000,86400] meaning group name to rate within, 10 requests per second, max 100k per 86400 seconds (1 day)
# if rate is true, the above will be the default. If rate is just a number it is assumed to be the r/s value.
# If no group name is provided it will be discerned from the url endpoint being called
# when rate is provided, check the system settings for a rate limit endpoint, and forward the requests to it (so that rates can be co-ordinated across a pool)
# if no system setting for where to call, then this is the master one, run it here - keep an in-memory track for each group
# make sure the "where to call" can be passed all the necessary params, and is accessible (e.g with system auth token)
_rates = {}

P.rate = (rate, blocked, ms) ->
  ms ?= @params.ms ? false
  s = 0
  if S.limiter and S.limiter.startsWith('http') and @params.rated isnt true and JSON.stringify(_rates) is '{}'
    headers = {}
    headers['x-' + S.name.toLowerCase() + '-system'] = S.system
    rs = S.limiter + '/rate?rated' + (if blocked then '&blocked' else '')
    if rate? and rate.length >= 2
      rs += '&group=' + encodeURIComponent rate[0]
      rs += '&rate=' + encodeURIComponent rate[1]
      rs += ('&max=' + encodeURIComponent rate[2]) if rate[2]
      rs += ('&per=' + encodeURIComponent rate[3]) if rate[3]
    if not res = await @fetch rs, headers:  headers # on first attempt this will call itself if it was already on the rate manager, but after that, it won't
      await @sleep 800 # in case of timeout on the rate limiter endpoint - send a warning here?
      res = await @fetch rs, headers:  headers
    return res
  else
    rate ?= [@params.group, @params.rate, @params.max, @params.per]
    blocked ?= @params.blocked ? false
    if blocked
      _rates.blocked ?= 0
      _rates.blocked += 1
    if rate[0]
      _rates[rate[0]] ?= started: Date.now(), last: undefined, rates: rate, count: 0, blocked: 0
      if blocked
        console.log('*** FETCH RATE BLOCKED ***', rate[0]) if S.dev and S.bg is true
        _rates[rate[0]].blocked += 1
        s = 30000 # see if there is a standard way (or few ways) to detect a specific blocking amount
      if rate[3]
        _rates[rate[0]].ends ?= _rates[rate[0]].started + (rate[3] * 1000)
        _rates[rate[0]].remaining = _rates[rate[0]].ends - Date.now()
        if _rates[rate[0]].ends < Date.now() # but should this be a rolling window? Can't know for sure how different remotes will implement it
          _rates[rate[0]].ends = _rates[rate[0]].started + (rate[3] * 1000)
          _rates[rate[0]].started = Date.now()
          _rates[rate[0]].count = 0
        if rate[2] and _rates[rate[0]].count >= rate[2] # would it be better to abort here, as the wait could be long?
          console.log('FETCH RATE MAXED', rate, _rates[rate[0]].remaining) if S.dev and S.bg is true
          s = _rates[rate[0]].remaining + 1
      if s is 0 and _rates[rate[0]].last and rate[1]
        console.log('FETCH RATE LIMITING', rate[0], 'max ' + rate[1] + 'r/s', 'avg ' + _rates[rate[0]].average + 'r/s', _rates[rate[0]].count) if S.dev and S.bg is true
        s = Math.round (1000 / rate[1]) - (Date.now() - _rates[rate[0]].last)
      _rates[rate[0]].last = Date.now() + s
      _rates[rate[0]].count += 1
      _rates[rate[0]].average = Math.round 1000 / ((_rates[rate[0]].last - _rates[rate[0]].started) / _rates[rate[0]].count)
  return if ms then s else Date.now() + s

P.rates = ->
  if S.limiter and S.limiter.startsWith('http') and @params.rated isnt true and JSON.stringify(_rates) is '{}'
    headers = {}
    headers['x-' + S.name.toLowerCase() + '-system'] = S.system
    rs = await @fetch S.limiter + '/rates?rated', headers:  headers # on first attempt this will call itself if it was already on the rate manager, but after that, it won't
    rs.master = false
    return rs
  else
    _rates.master = true
    return _rates
#P.rates._auth = 'system'

P.rates.check = (url, group, rate, max, per, amount) ->
  started = Date.now()
  url ?= @params.url
  headers = {}
  if not url?
    url = 'https://bg.beta.oa.works/rates'
    headers['x-' + S.name.toLowerCase() + '-system'] = S.system
  group ?= @params.group ? 'check'
  rate ?= @params.rate ? 2
  max ?= @params.max ? 5
  per ?= @params.per ? 10
  amount ?= @params.amount ? 16
  times = []
  waits = []
  ret = []
  for r in [0..amount]
    times.push Date.now()
    ret.push await @fetch url, rate: [group, rate, max, per], headers: headers # 2r/s, max 5 per 10s
    if times.length > 1
      waits.push times[times.length - 1] - times[times.length - 2]
  ended = Date.now()
  return started: started, ended: ended, took: (ended-started), local: (JSON.stringify(_rates) isnt '{}'), url: url, group: group, rate: rate + 'r/s', max: (if max then (max + (if per then ' per ' + per + 's' else '')) else undefined), amount: amount, times: times, waits: waits, results: ret
P.rates.check._auth = 'root'

P.fetch = (url, params) ->
  if not url? and not params?
    try params = @copy @params
  if typeof url is 'object' and not params?
    params = url
    url = params.url
  params ?= {}
  if typeof params is 'number'
    params = cache: params
  if typeof params.cache is 'number' # https://developers.cloudflare.com/workers/examples/cache-using-fetch
    params.cf ?= cacheEverything: true
    params.cf.cacheTtl = params.cache
    delete params.cache
  if not url and params.url
    url = params.url
    delete params.url
  if params.bg is true and typeof S.bg is 'string'
    params.url = url # send to bg (e.g. for proxying)
    url = S.bg + '/fetch'
    delete params.bg
  if params.username and params.password
    params.auth = params.username + ':' + params.password
    delete params.username
    delete params.password
  if url.split('?')[0].includes('@') and url.includes(':') and url.split('//')[1].split('?')[0].split('@')[0].includes ':'
    params.auth = url.split('//')[1].split('@')[0]
    url = url.replace params.auth + '@', ''
  if params.auth
    params.headers ?= {}
    params.headers.Authorization = 'Basic ' + Buffer.from(params.auth).toString('base64')
    delete params.auth
  for ct in ['data', 'content', 'json']
    if params[ct]?
      params.body = params[ct]
      delete params[ct]
  params.attachment ?= params.attachments
  params.file ?= params.attachment
  if params.file?
    params.headers ?= {}
    #params.headers['Content-Type'] = 'multipart/form-data'
    params.form = params.body if params.body? and not params.form?
    params.body = new FormData()
    if not Array.isArray params.file
      if typeof params.file is 'object' and params.file.file?
        fll = [{file: params.file.file, filename: params.file.filename ? params.file.name ? params.filename}]
      else
        fll = [{file: params.file, filename: params.filename}]
      params.file = fll
    for flo in params.file
      if flo?.file? or flo?.data?
        params.body.append (if params.attachment? then 'attachment' else 'file'), (flo.file ? flo.data), (flo.filename ? flo.name ? params.filename ? 'file')
    delete params.filename
    params.method ?= 'POST'
  else if params.body?
    params.headers ?= {} # content-type is necessary for ES to accept, for example
    if not params.headers['Content-Type']? and not params.headers['content-type']?
      params.headers['Content-Type'] = if typeof params.body is 'object' then 'application/json' else 'text/plain'
    params.body = JSON.stringify(params.body) if typeof params.body in ['object', 'boolean', 'number'] # or just everything?
    params.method ?= 'POST'
  if params.form?
    if params.file?
      if typeof params.form is 'object'
        for fk of params.form
          for av in (if Array.isArray(params.form[fk]) then params.form[fk] else [params.form[fk]])
            params.body.append fk, if typeof av is 'object' then JSON.stringify(av) else av
    else
      params.headers ?= {}
      if not params.headers['Content-Type']? and not params.headers['content-type']?
        params.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      if typeof params.form is 'object'
        po = '' # params object to string x-www-form-urlencoded
        for p of params.form
          po += '&' if po isnt ''
          for ppt in (if Array.isArray(params.form[p]) then params.form[p] else [params.form[p]])
            if ppt?
              po += '&' if not po.endsWith '&'
              po += p + '=' + encodeURIComponent (if typeof ppt is 'object' then JSON.stringify(ppt) else ppt)
        params.form = po
      params.body = params.form
    delete params.form
    params.method ?= 'POST'
  delete params.file
  delete params.attachment
  delete params.attachments

  if typeof url isnt 'string'
    return
  else
    if not url.startsWith('http:') and url.includes 'localhost' # allow local https connections on backend server without check cert
      try params.agent ?= new https.Agent rejectUnauthorized: false
    if url.includes '?'
      pts = url.split '?'
      nu = pts.shift() + '?'
      for qp in pts.join('?').split '&'
        nu += '&' if not nu.endsWith '?'
        [k,v] = qp.split '='
        v ?= ''
        nu += encodeURIComponent(k) + (if v then '=' + (if v.includes('%') then v else encodeURIComponent v) else '') if k
      url = nu
    if params.params and JSON.stringify(params.params) isnt '{}'
      url += '?' if not url.includes '?'
      for k, v of params.params
        url += '&' if not url.endsWith('&') and not url.endsWith '?'
        url += encodeURIComponent(k) + '=' + encodeURIComponent(if typeof v is 'object' then JSON.stringify(v) else v) if k
      delete params.params
    if S.system and ((typeof S.bg is 'string' and url.startsWith S.bg) or (typeof S.async is 'string' and url.startsWith S.async) or (typeof S.kv is 'string' and S.kv.startsWith('http') and url.startsWith S.kv))
      params.headers ?= {} # add the system auth code and any user creds when passing anything back to bg, or when bg passing to worker to reach kv
      params.headers['x-' + S.name.toLowerCase() + '-system'] ?= S.system
      params.headers['x-apikey'] = @user.apikey if not params.headers.Authorization and not params.headers.authorization and not params.headers['x-apikey'] and @user

    _f = () =>
      if params.stream
        delete params.stream
        # return full response with status, ok, redirected, bodyUsed, size, timeout url, statusText, clone, body, arrayBuffer, blob, json, text, buffer, textConverted 
        return fetch url, params # (and response body can be used as stream if desired, or can await text() or json() etc
      else
        #console.log(url) if S?.bg is true # extra for finding out unexplained timeout issue
        buff = false
        if params.buffer
          buff = true
          delete params.buffer
        response = await fetch url, params
        try
          console.log(response.status + ' ' + url) if (not url.includes('localhost') or response.status not in [200, 404]) and S.dev and S.bg is true # status code can be found here
          # content type could be read from: response.headers.get('content-type')
          if params.verbose
            console.log(response.body) if response.status > 300
            console.log response.status + ' ' + url
        catch
          console.log 'Error logging to console for fetch'
          console.log response
        if buff
          r = await response.buffer()
        else if params.method in ['HEAD']
          r = status: response.status
          r[hd[0]] = hd[1] for hd in [...response.headers]
        else
          try r = await response.text() # await response.json() can get json direct, but it will error if the wrong sort of data is provided, so just try it here
          try r = JSON.parse(r) if typeof r is 'string' and (r.startsWith('{') or r.startsWith('['))
        if response.status is 404
          return
        else if response.status >= 400
          console.log(params, JSON.stringify(r), 'FETCH ERROR', response.method, response.status, url) if S.dev and S.bg is true
          return status: response.status, body: r
        else
          return r

    try
      _rate = false
      if params.rate?
        _rate = true
        params.rate = [undefined, params.rate] if typeof params.rate is 'number'
        params.rate.unshift(undefined) if typeof params.rate[0] isnt 'string'
        params.rate[0] ?= url.split('/')[2] # use the domain as the default group name
        if waitto = await @rate params.rate
          await @sleep waitto - Date.now()
        delete params.rate
      if params.timeout and this?._timeout?
        pt = if params.timeout is true then 30000 else params.timeout
        delete params.timeout
        res = await @_timeout pt, _f()
      else
        res = await _f()
      try
        res = res.trim()
        res = JSON.parse(res) if res.startsWith('[') or res.startsWith('{')
      try
        if response.status is 429 and _rate
          @rate params.rate, true
      return res
    catch err
      console.log('ERROR TRYING TO CALL FETCH', url, err, JSON.stringify(err)) if S.dev and S.bg is true
      try @log err
      return

P.fetch._auth = 'system'



P._timeout = (ms, fn) -> # where fn is a promise-able function that has been called
  # so call this like res = await @_timeout 5000, @fetch url
  return new Promise (resolve, reject) =>
    timer = setTimeout () =>
      reject new Error 'TIMEOUT' # should this error or just return?
    , ms
    promise
      .then value =>
        clearTimeout timer
        resolve value
      .catch reason =>
        clearTimeout timer
        reject reason
