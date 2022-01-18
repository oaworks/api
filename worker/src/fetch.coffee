
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
        #console.log(url) if S?.bg is true # extra for finding out unexplained timeout issue
        buff = false
        if params.buffer
          buff = true
          delete params.buffer
        response = await fetch url, params
        console.log(response.status + ' ' + url) if (not url.includes('localhost') or response.status isnt 200) and S.dev and S.bg is true # status code can be found here
        # content type could be read from: response.headers.get('content-type')
        if buff
          r = await response.buffer()
        else
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
    catch err
      console.log(err, JSON.stringify(err), 'ERROR TRYING TO CALL FETCH') if S.dev and S.bg is true
      try @log err
      return

P.fetch._auth = 'system'
P.fetch._hide = true