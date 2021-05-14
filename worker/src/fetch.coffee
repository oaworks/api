
# https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

# NOTE TODO for getting certain file content, adding encoding: null to headers (or correct encoding required) is helpful

P.fetch = (url, params) ->
  # TODO if asked to fetch a URL that is the same as the @url this worker served on, then needs to switch to a bg call if bg URL available
  if not url? and not params?
    try params = @copy @params
  if typeof url is 'object' and not params?
    params = url
    url = params.url
  params ?= {}
  if not url and params.url
    url = params.url
    delete params.url
  if params.bg is true and typeof S.bg is 'string'
    params.url = url # send to bg (e.g. for proxying)
    url = S.bg + '/fetch'
    delete params.bg
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
    params.method ?= 'POST'
  if params.form?
    # note, to send form and more data, form-data would be needed
    params.headers ?= {}
    if not params.headers['Content-Type']? and not params.headers['content-type']?
      params.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    if typeof params.form is 'string'
      params.body = params.form
    else
      try params.form = await @params params.form
    delete params.form
    params.method ?= 'POST'
  if typeof url isnt 'string'
    return false
  else
    try
      if url.indexOf('?') isnt -1
        nu = url.split('?')[0] + '?'
        for qp in url.split('?')[1].split '&'
          nu += '&' if not nu.endsWith '?'
          [k,v] = qp.split '='
          v ?= ''
          nu += k + '=' + if v.indexOf('%') isnt -1 then v else encodeURIComponent v
        url = nu
    if S.system and ((typeof S.bg is 'string' and url.startsWith S.bg) or (typeof S.kv is 'string' and S.kv.startsWith('http') and url.startsWith S.kv))
      params.headers ?= {} # add the system auth code when passing anything back to bg, or when bg passing to worker to reach kv
      params.headers['x-' + S.name + '-system'] ?= S.system
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
      console.log(response.status + ' ' + url) if S.dev #and S.bg is true # status code can be found here
      # content type could be read from: response.headers.get('content-type')
      # and await response.json() can get json direct, but it will error if the wrong sort of data is provided.
      # So just do it manually from text here if appropriate
      # TODO what if the response is a stream (buffer)?
      r = await response.text()
      try r = JSON.parse(r) if typeof r is 'string' and (r.indexOf('{') is 0 or r.indexOf('[') is 0)
      resp = {}
      if response.status is 404
        resp = undefined
      else if response.status >= 400
        if S.dev
          console.log JSON.stringify r
          console.log 'ERROR ' + response.status
        resp.status = response.status
      else if verbose
        if typeof r is 'object'
          resp.json = r
        else
          resp.text = r
      else
        resp = r
      if verbose and typeof resp is 'object'
        resp.headers = {}
        resp.headers[hd[0]] = hd[1] for hd in [...response.headers]
        resp[rk] = response[rk] for rk in ['status', 'ok', 'redirected', 'bodyUsed'] # size, timeout url, statusText, clone, body, arrayBuffer, blob, json, text, buffer, textConverted
      if verbose and resp? and this?.fn? and @fn is 'fetch' and @parts.length is 1 and @parts[0] is 'fetch'
        return status: 200, body: resp
      else
        return resp
    '''
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
    if params.timeout and this?._timeout?
      pt = if params.timeout is true then 30000 else params.timeout
      delete params.timeout
      res = await @_timeout pt, _f()
    else
      res = await _f()
    try
      res = res.trim()
      res = JSON.parse(res) if res.indexOf('[') is 0 or res.indexOf('{') is 0
    return res

