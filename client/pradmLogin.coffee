
@pradm ?= {}
pradm.service ?= undefined # optionally set the name of the service using the login
pradm.api ?= window.location.host # set this elsewhere if not on the current host
pradm.oauthRedirectUri = undefined # this can be set, but if not, current page will be used (whatever is used has to be authorised as a redirect URI with the oauth provider)
pradm.oauthGoogleClientId = undefined # this must be provided for oauth to work
pradm.account = undefined # set to the account object once retrieved

pradm.getCookie = (name) ->
  name ?= 'pradm'
  for c in document.cookie.split ';'
    c = c.substring(1) while c.charAt(0) is ' '
    return JSON.parse(decodeURIComponent(c.substring(name.length + 1, c.length))) if c.indexOf(name + '=') isnt -1
  return false
pradm.setCookie = (name, values, options) ->
  name ?= 'pradm'
  text = name + '='
  text += encodeURIComponent(JSON.stringify(values)) if values
  options ?= {}
  date = options.expires ? 180
  if typeof date is 'number'
    date = new Date()
    date.setDate date.getDate() + options.expires
  text += '; expires=' + new Date(date).toUTCString() if date instanceof Date
  text += '; domain=' + options.domain if typeof options.domain is 'string' and options.domain isnt ''
  text += '; path=' + if typeof options.path is 'string' and options.path isnt '' then options.path else '/'
  text += '; secure' if options.secure isnt false # default to secure
  text += '; HttpOnly' if options.httponly
  document.cookie = text
  return text
pradm.removeCookie = (name, domain) -> pradm.setCookie name, undefined, {domain: domain, expires:-1}

pradm.token = (e) ->
  try e.preventDefault()
  pradm.removeCookie()
  # TODO add a validation of the email val if email not already set?
  if not email = pradm.get '#pradmEmail'
    pradm.css '#pradmEmail', 'border-color', '#f04717'
    pradm.focus '#pradmEmail'
    return
  pradm.hide '.pradmEmail'
  pradm.show '.pradmLoading'
  pradm.show '.pradmToken'
  opts =
    success: (data) ->
      pradm.hide '.pradmLoading'
      pradm.focus '#pradmToken'
    data:
      email: email
      url: window.location.protocol + '//' + window.location.host + window.location.pathname
      service: pradm.service
  pradm.ajax '/auth/token', opts

pradm.loginSuccess = (data) ->
  pradm.hide '.pradmLogin'
  pradm.hide '.pradmLoading'
  pradm.hide '.pradmToken'
  if data?
    pradm.account = data
    pradm.setCookie undefined, data
  if pradm.next or window.location.href.indexOf('next=') isnt -1
    if pradm.next is true
      location.reload()
    else
      window.location = pradm.next ? decodeURIComponent(window.location.href.split('next=')[1].split('&')[0])
  else
    try
      pradm.show '.pradmLogout'
      pradm.listen 'click', '#pradmLogout', pradm.logout

pradm.loginError = (err) ->
  console.log err # and log an error to backend somewhere...
  pradm.removeCookie()
  pradm.account = undefined
  pradm.hide '.pradmLoading'
  pradm.hide '.pradmToken'
  pradm.set '#pradmEmail', 'placeholder', 'Login error, please try your email address again'
  pradm.show '.pradmEmail'
  pradm.show '.pradmLogin'
  
pradm.login = (e) ->
  try e.preventDefault()
  opts =
    success: pradm.loginSuccess
    error: pradm.loginError
    data: service: pradm.service

  pt = pradm.get '#pradmToken'
  if window.location.hash.indexOf('access_token=') isnt -1
    opts.data.oauth = {}
    for p of pts = window.location.hash.replace('#','').split '&'
      [k, v] = pts[p].split '='
      opts.data.oauth[k] = v
    oauthcookie = pradm.getCookie 'poauth'
    pradm.removeCookie 'poauth'
  else if window.location.hash.replace('#','').length is 8
    opts.data.token = window.location.hash.replace '#', ''
    try window.history.pushState "", "", window.location.pathname
  else if typeof pt is 'string' and pt.length is 8
    opts.data.token = pt
  else if account = pradm.loggedin()
    opts.data.email = account.email
    opts.data.resume = account.resume

  if (opts.data.email and opts.data.resume) or opts.data.hash or opts.data.token or opts.data.oauth.state is oauthcookie?.state
    pradm.hide '.pradmEmail'
    pradm.hide '.pradmToken'
    pradm.show '.pradmLoading'
    pradm.ajax '/auth', opts

pradm.loggedin = () ->
  pradm.account ?= pradm.getCookie()
  return pradm.account
pradm.logout = (e) ->
  try e.preventDefault()
  if account = pradm.loggedin()
    pradm.ajax '/auth/logout' + if pradm.api.indexOf(window.location.host) is -1 then '?apikey=' + account.apikey else ''
  pradm.account = undefined
  pradm.removeCookie()
  if pradm.next
    if pradm.next is true
      location.reload()
    else
      window.location = pradm.next

pradm.listen 'enter', '#pradmEmail', pradm.token
try pradm.listen 'keyup', '#pradmToken', (e) -> pradm.login() if pradm.get('#pradmToken').length is 8
try
  if pradm.get('#pradmOauthGoogle').length and pradm.oauthGoogleClientId
    state = Math.random().toString(36).substring(2,8)
    grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
    grl += '&state=' + state + '&redirect_uri=' + (pradm.oauthRedirectUri ? window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + pradm.oauthGoogleClientId
    pradm.set '#pradmOauthGoogle', 'href', grl
    pradm.listen 'click', '#pradmOauthGoogle', () -> pradm.setCookie 'poauth', {state:state}, {expires:1}

pradm.login() if pradm.loggedin() or (typeof window.location.hash is 'string' and window.location.hash and window.location.hash.replace('#', '').length is 8)
