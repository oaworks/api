
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