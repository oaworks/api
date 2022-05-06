
_OALogin = (n) ->
  if n.startsWith '#'
    d = document.getElementById n
  else
    d = document.getElementsByClassName n.replace(/^\./, '').replace(/\s\./g, ' ').trim()
    d = d[0] if d? and d.length is 1
  return if d? and (n.startsWith('#') or d.length isnt 0) then d else undefined
  
_OALogin.each = (els, k) ->
  els = _OALogin(els) if typeof els is 'string'
  els = [els] if els? and not Array.isArray(els) and not HTMLCollection.prototype.isPrototypeOf(els) and not NodeList.prototype.isPrototypeOf els
  k(el) for el in (els ? [])
_OALogin.show = (els, h, a) ->
  _OALogin.each els, (el) -> 
    el.innerHTML = (if a then el.innerHTML else '') + h + (if a is false then el.innerHTML else '') if h
    w = el.getAttribute 'OALoginDisplay'
    w = 'block' if typeof w isnt 'string' or w is 'none' # TODO should be inline in which cases...
    el.style.display = w
_OALogin.hide = (els) ->
  _OALogin.each els, (el) -> 
    if el.style.display isnt 'none'
      el.setAttribute 'OALoginDisplay', el.style.display
    el.style.display = 'none'

_OALogin.ajax = (url, opts) ->
  if typeof url is 'object'
    opts = url
    url = undefined
  url ?= opts.url ? ''
  if url is '' or (url.startsWith('/') and not url.startsWith '//')
    url = '//' + window.location.host + url

  opts ?= {}
  opts.headers ?= {}
  opts.method = opts.method.toUpperCase() if typeof opts.method is 'string'
  if opts.data?
    opts.method = 'POST'
    if typeof opts.data is 'object' and typeof opts.data.append isnt 'function' # a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify opts.data
      opts.headers['Content-type'] ?= 'application/json'
    #url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching?

  try
    if not opts.headers.Authorization and not opts.headers.authorization and not opts.headers.apikey and not opts.headers['x-apikey']
      if opts.username and opts.password
        opts.headers.Authorization ?= "Basic " + btoa(opts.username + ":" + opts.password)
      else if opts.apikey or opts['x-apikey']
        opts.headers.apikey = opts.apikey ? opts['x-apikey']

  xhr = new XMLHttpRequest()
  xhr.open (opts.method ? 'GET'), url
  xhr.setRequestHeader(h, opts.headers[h]) for h of opts.headers

  loaded = false
  xhr.onload = () ->
    loaded = true
    try
      if xhr.status > 199 and xhr.status < 400
        x = xhr.response
        try x = JSON.parse x
        try opts.success x, xhr
      else
        try opts.error xhr
    catch err
      try console.log err
      try opts.error xhr
  xhr.onerror = (err) -> try opts.error err, xhr
  xhr.onloadend = () -> try opts.error(xhr) if xhr.status in [404] and not loaded

  try xhr.send opts.data

_OALogin.cookie = (n, vs, opts) ->
  if n is '' or n is false or typeof n is 'object'
    vs = n
    n = undefined
  n ?= 'oaworksLogin'
  if vs? # even if values is false or '', so can remove this way
    opts ?= {}
    if opts.domain
      domained = true
    else
      domained = false
      opts.domain = '.' + window.location.host
      opts.domain = opts.domain.replace('.bg.', '.') if opts.domain.startsWith '.bg.'
    t = n + '='
    if vs
      t += encodeURIComponent JSON.stringify vs # so if values is false or '' this will effectively remove the cookie
    else
      opts.expires = -1
    d = opts.expires ? 180
    if typeof d is 'number'
      d = new Date()
      d.setDate d.getDate() + opts.expires
    t += '; expires=' + new Date(d).toUTCString() if d instanceof Date
    t += '; domain=' + opts.domain if typeof opts.domain is 'string' and opts.domain isnt ''
    t += '; path=' + if typeof opts.path is 'string' and opts.path isnt '' then opts.path else '/'
    t += '; secure' if opts.secure isnt false # default to secure
    t += '; HttpOnly' if opts.httponly
    document.cookie = t
    if opts.expires is -1 and opts.domain and not domained
      dt = t.split('; domain=')[0] # clear the cookie without domain specified too, just to make sure
      document.cookie = dt
    return t
  else
    for c in document.cookie.split ';'
      c = c.substring(1) while c.charAt(0) is ' '
      return JSON.parse(decodeURIComponent(c.substring(n.length + 1, c.length))) if c.indexOf(n + '=') isnt -1
    return false

_OALogin.account = undefined # set to the account object once retrieved

_OALogin.token = (e) ->
  try e.preventDefault()
  _OALogin.cookie false
  # TODO add a validation of the email val if email not already set?
  if not email = document.getElementById('OALoginEmail').value
    document.getElementById('OALoginEmail').focus()
    return
  _OALogin.hide '.OALoginEmail'
  _OALogin.show '.OALoading'
  _OALogin.show '.OALoginToken'
  opts =
    success: (data) ->
      _OALogin.hide '.OALoading'
      document.getElementById('OALoginToken').focus()
      _OALogin._loggingin = setInterval () ->
        _OALogin.loginSuccess() if _OALogin.loggedin()
      , 2000
    data:
      email: email
      url: window.location.protocol + '//' + window.location.host + window.location.pathname
  _OALogin.ajax '/auth/token', opts

_OALogin.loginSuccess = (data) ->
  if _OALogin._loggingin
    clearInterval _OALogin._loggingin
    delete _OALogin._loggingin
  _OALogin.hide '.OALogin'
  _OALogin.hide '.OALoading'
  _OALogin.hide '.OALoginToken'
  if typeof data is 'object'
    _OALogin.account = data
    _OALogin.cookie data
  if not _OALogin.loginNext and window.location.search.indexOf('next=') isnt -1
    _OALogin.loginNext = decodeURIComponent window.location.search.split('next=')[1].split('&')[0]
  else if not _OALogin.loginNext and window.location.search.startsWith '?next'
    _OALogin.loginNext = true
  if _OALogin.loginNext
    if _OALogin.loginNext is true
      location.reload()
    else
      window.location = _OALogin.loginNext
  else
    try
      _OALogin.show '.OALoginLogout'
      document.getElementById('OALoginLogout').addEventListener 'click', _OALogin.logout
    try
      _OALogin.afterLogin() if typeof _OALogin.afterLogin is 'function'

_OALogin.loginError = (err, xhr) ->
  console.log 'Login error'
  console.log err # and log an error to backend somewhere...
  console.log xhr
  if _OALogin._loggingin
    clearInterval _OALogin._loggingin
    delete _OALogin._loggingin
  _OALogin.cookie false
  _OALogin.account = undefined
  _OALogin.hide '.OALoading'
  _OALogin.hide '.OALoginToken'
  document.getElementById('OALoginEmail').value = ''
  document.getElementById('OALoginEmail').setAttribute 'placeholder', 'error, enter your email to try again'
  _OALogin.show '.OALoginEmail'
  _OALogin.show '.OALogin'
  
_OALogin.login = (e) ->
  try e.preventDefault()
  opts =
    success: _OALogin.loginSuccess
    error: _OALogin.loginError
    data: {}

  pt = document.getElementById('OALoginToken').value
  if window.location.hash.replace('#','').length is 8
    opts.data.token = window.location.hash.replace '#', ''
    try window.history.pushState "", "", window.location.pathname
  else if typeof pt is 'string' and pt.length is 8
    opts.data.token = pt
  else if account = _OALogin.loggedin()
    opts.data.email = account.email
    opts.data.resume = account.resume

  if (opts.data.email and opts.data.resume) or opts.data.hash or opts.data.token
    _OALogin.hide '.OALoginEmail'
    _OALogin.hide '.OALoginToken'
    _OALogin.show '.OALoading'
    _OALogin.ajax '/auth', opts

_OALogin.loggedin = () ->
  if p = _OALogin.cookie()
    _OALogin.account = p if typeof p is 'object' and JSON.stringify(p) isnt '{}'
  return _OALogin.account

_OALogin.logout = (e) ->
  try e.preventDefault()
  _OALogin.show '.OALoading'
  if account = _OALogin.loggedin()
    _OALogin.ajax '/auth/logout?apikey=' + account.apikey, success: () ->
      _OALogin.account = undefined
      _OALogin.cookie false
      _OALogin.hide '.OALoading' # just in case anything made this visible
      if _OALogin.loginNext is true
        location.reload()
      else if _OALogin.loginNext
        window.location = _OALogin.loginNext
      else if typeof _OALogin.afterLogout is 'function'
        try _OALogin.afterLogout()


document.addEventListener 'DOMContentLoaded', () ->
  try document.getElementById('OALoginEmail').addEventListener 'keyup', (e) -> _OALogin.token(e) if e.keyCode is 13
  try document.getElementById('OALoginToken').addEventListener 'keyup', (e) -> _OALogin.login() if document.getElementById('OALoginToken').value.length is 8
  loggedin = _OALogin.loggedin()
  if loggedin or (typeof window.location.hash is 'string' and window.location.hash and window.location.hash.replace('#', '').length is 8)
    _OALogin.loginNext = undefined if loggedin # don't go to next if already logged in
    _OALogin.login() # will it be worth doing this on every page load, or only those with a login token hash?
