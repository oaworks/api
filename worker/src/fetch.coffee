
# https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

# NOTE TODO for getting certain file content, adding encoding: null to headers (or correct encoding required) can be helpful

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
  if url.split('//')[1].split('@')[0].indexOf(':') isnt -1
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
  if params.body?
    params.headers ?= {} # content-type is necessary for ES to accept, for example
    if not params.headers['Content-Type']? and not params.headers['content-type']?
      params.headers['Content-Type'] = if typeof params.body is 'object' then 'application/json' else 'text/plain'
    params.body = JSON.stringify(params.body) if typeof params.body in ['object', 'boolean', 'number'] # or just everything?
    params.method ?= 'POST'
  if params.form?
    # note, to send form and more data, form-data would be needed
    params.headers ?= {}
    if not params.headers['Content-Type']? and not params.headers['content-type']?
      params.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    if typeof params.form is 'object'
      try params.form = await @form params.form
    params.body = params.form
    delete params.form
    params.method ?= 'POST'

  if typeof url isnt 'string'
    return
  else
    if url.includes 'localhost' # allow local https connections on backend server without check cert
      try params.agent ?= new https.Agent rejectUnauthorized: false
    if url.includes '?'
      pts = url.split '?'
      nu = pts.shift() + '?'
      for qp in pts.join('?').split '&'
        nu += '&' if not nu.endsWith '?'
        [k,v] = qp.split '='
        v ?= ''
        nu += encodeURIComponent(k) + (if v then '=' + (if v.indexOf('%') isnt -1 then v else encodeURIComponent v) else '') if k
      url = nu
    if params.params and JSON.stringify(params.params) isnt '{}'
      url += '?' if url.indexOf('?') is -1
      for k, v of params.params
        url += '&' if not url.endsWith('&') and not url.endsWith '?'
        url += encodeURIComponent(k) + '=' + encodeURIComponent(if typeof v is 'object' then JSON.stringify(v) else v) if k
      delete params.params
    if S.system and ((typeof S.bg is 'string' and url.startsWith S.bg) or (typeof S.kv is 'string' and S.kv.startsWith('http') and url.startsWith S.kv))
      params.headers ?= {} # add the system auth code and any user creds when passing anything back to bg, or when bg passing to worker to reach kv
      params.headers['x-' + S.name.toLowerCase() + '-system'] ?= S.system
      params.headers['x-apikey'] = @user.apikey if not params.headers.Authorization and not params.headers.authorization and not params.headers['x-apikey'] and @user

    _f = () =>
      if params.stream
        delete params.stream
        # return full response with status, ok, redirected, bodyUsed, size, timeout url, statusText, clone, body, arrayBuffer, blob, json, text, buffer, textConverted 
        return fetch url, params # (and response body can be used as stream if desired, or can await text() or json() etc
      else
        console.log(url) if S?.bg is true # extra for finding out unexplained timeout issue
        response = await fetch url, params
        console.log(response.status + ' ' + url) if (not url.includes('localhost') or response.status isnt 200) and S.dev and S.bg is true # status code can be found here
        # content type could be read from: response.headers.get('content-type')
        r = await response.text() # await response.json() can get json direct, but it will error if the wrong sort of data is provided, so just try it here
        try r = JSON.parse(r) if typeof r is 'string' and (r.indexOf('{') is 0 or r.indexOf('[') is 0)
        if response.status is 404
          return
        else if response.status >= 400
          console.log(params, JSON.stringify(r), 'FETCH ERROR', response.status) if S.dev and S.bg is true
          return status: response.status
        else
          return r

    try
      if params.timeout and this?._timeout? # should timeout be here at all or could/should @retry be used to handle that?
        pt = if params.timeout is true then 30000 else params.timeout
        delete params.timeout
        res = await @_timeout pt, _f()
      else
        res = await _f()
      try
        res = res.trim()
        res = JSON.parse(res) if res.indexOf('[') is 0 or res.indexOf('{') is 0
      return res
    catch err
      console.log(err, JSON.stringify(err), 'ERROR TRYING TO CALL FETCH') if S.dev and S.bg is true
      try @log err
      return


'''
limiting = (fetcher, retries=1) ->
  # notice if someone else is limiting us, and how long to wait for
  while retries
    retries--
    response = await fetcher()
    switch (response.status) ->
      default:
        return response
      case 403:
      case 429:
        # header names differ by API we're hitting, these examples are for github. 
        # It's the timestamp of when the rate limit window would reset, generalise this
        # e.g. look for any header containing ratelimit? or rate? then see if it's a big
        # number which would be a timestamp (and check if need *1000 for unix to ms version) 
        # or a small number which is probably ms to wait
        resets = parseInt response.headers.get "x-ratelimit-reset"
        ms = if isNaN(resets) then 0 else new Date(resets * 1000).getTime() - Date.now()
        if ms is 0
          # this one is like a count of ms to wait?
          remaining = parseInt response.headers.get "x-ratelimit-remaining"
          ms = remaining if not isNaN remaining

        if ms <= 0
          return response
        else
          await new Promise resolve => setTimeout resolve, ms
'''

P.fetch._auth = 'system'
P.fetch._hide = true