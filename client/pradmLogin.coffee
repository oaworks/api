
@pradm ?= {}
pradm.service ?= undefined # optionally set the name of the service using the login
pradm.api ?= window.location.host # set this elsewhere if not on the current host
pradm.oauthRedirectUri = undefined # this can be set, but if not, current page will be used (whatever is used has to be authorised as a redirect URI with the oauth provider)
pradm.oauthGoogleClientId = undefined # this must be provided for oauth to work
pradm.account = undefined # set to the account object once retrieved

pradm.getCookie = (cname) ->
  cname ?= 'pradm'
  for c in document.cookie.split ';'
    c = c.substring(1) while c.charAt(0) is ' '
    return JSON.parse(decodeURIComponent(c.substring(cname.length + 1, c.length))) if c.indexOf(cname + '=') isnt -1
  return false
pradm.setCookie = (name, values, options) ->
  text = name + '='
  text += encodeURIComponent(JSON.stringify(values)) if values
  options ?= {}
  date = options.expires
  if typeof date is 'number'
    date = new Date()
    date.setDate date.getDate() + options.expires
  text += '; expires=' + date.toUTCString() if date instanceof Date
  text += '; domain=' + options.domain if typeof options.domain is 'string' and options.domain isnt ''
  text += '; path=' + if typeof options.path is 'string' and options.path isnt '' then options.path else '/'
  text += '; secure' if options.secure isnt false # default to secure
  text += '; HttpOnly' if options.httponly
  document.cookie = text
  return text
pradm.removeCookie = (name, domain) -> pradm.setCookie name, undefined, {domain: domain, expires:-1}

pradm.ajax = (url, opts) ->
  if typeof url is 'object'
    opts = url
    url = undefined
  url ?= opts.url ? ''
  if url is '' or url.startsWith '/'
    url = pradm.api + url
  opts ?= {}
  opts.headers ?= {}
  if opts.data?
    opts.method = 'POST'
    if typeof opts.data is 'object' and typeof opts.data.append isnt 'function' # a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify opts.data
      opts.headers['Content-type'] ?= 'application/json'
    url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching
  xhr = new XMLHttpRequest()
  xhr.open (opts.method ? 'GET'), url
  xhr.setRequestHeader(h, headers[h]) for h of opts.headers
  xhr.send opts.data
  xhr.onload = () ->
    try # worth checking xhr.status is 200?
      opts.success JSON.parse(xhr.response), xhr
    catch err
      try console.log err
      try opts.error xhr
  xhr.onerror = (err) -> try opts.error err

pradm.token = (e) ->
  try e.preventDefault()
  pradm.removeCookie()
  # TODO add a validation of the email val if email not already set?
  if not email = $('#pradmEmail').val()
    $('#pradmEmail').css('border-color','#f04717').focus()
    return
  $('.pradmLogin').hide()
  $('.pradmLoading').show()
  $('.pradmToken').show()
  opts =
    success: (data) ->
      $('.pradmLoading').hide()
      $('#pradmToken').focus()
    data:
      email: email
      service: pradm.service
  pradm.ajax '/auth/token', opts

pradm.loginSuccess = (data) ->
  $('.pradmLoading').hide()
  $('.pradmLogin').hide()
  $('.pradmToken').hide()
  if data?
    pradm.account = data.account # prob needs apikey, account, email
    pradm.setCookie undefined, data.account, data.settings
  if window.location.href.indexOf('next=') isnt -1
    window.location = decodeURIComponent(window.location.href.split('next=')[1].split('&')[0])
  else
    try
      $('.pradmLogout').show()
      $('#pradmLogout').unbind('click').bind 'click', pradm.logout

pradm.loginError = (err) ->
  console.log err # and log an error to backend somewhere...
  pradm.removeCookie()
  pradm.account = undefined
  $('.pradmLoading').hide()
  $('.pradmToken').hide()
  $('#pradmEmail').attr 'placeholder', 'Login error, please try your email address again'
  $('#pradmEmail').show()
  $('.pradmLogin').show()
  
pradm.login = (e) ->
  try e.preventDefault()
  opts =
    success: pradm.loginSuccess
    error: pradm.loginError
    data: service: pradm.service

  if window.location.hash.indexOf('access_token=') isnt -1
    opts.data.oauth = {}
    for p of pts = window.location.hash.replace('#','').split '&'
      [k, v] = pts[p].split '='
      opts.data.oauth[k] = v
    oauthcookie = pradm.getCookie 'poauth'
    pradm.removeCookie 'poauth'
  else if window.location.hash.replace('#','').length is 21
    opts.data.hash = window.location.hash.replace '#', ''
  else if $('#pradmToken').val().length is 7
    opts.data.token = $('#pradmToken').val()
  else if account = pradm.loggedin()
    opts.data.email = account.email
    opts.data.resume = account.resume

  if (opts.data.email and opts.data.resume) or opts.data.hash or opts.data.token or opts.data.oauth.state is oauthcookie?.state
    $('.pradmEmail').hide()
    $('.pradmToken').hide()
    $('.pradmLoading').show()
    pradm.ajax '/auth/login', opts

pradm.loggedin = () ->
  pradm.account ?= pradm.getCookie()
  return pradm.account
pradm.logout = (e) ->
  try e.preventDefault()
  if account = pradm.loggedin()
    pradm.ajax '/auth/logout' + if pradm.api.indexOf(window.location.host) is -1 then '?apikey=' + account.apikey else ''
  pradm.account = undefined
  pradm.removeCookie()

$('#pradmEmail').unbind('keyup').bind 'keyup', (e) -> pradm.token() if e.keyCode is 13
try $('#pradmToken').unbind('keyup').bind 'keyup', (e) -> pradm.login() if $('#pradmToken').val().length is 7
if $('#pradmOauthGoogle').length and pradm.oauthGoogleClientId
  state = Math.random().toString(36).substring(2,8)
  grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
  grl += '&state=' + state + '&redirect_uri=' + (pradm.oauthRedirectUri ? window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + pradm.oauthGoogleClientId
  $('#pradmOauthGoogle').attr('href',grl).unbind('click').bind 'click', () -> pradm.setCookie 'poauth', {state:state}, {expires:1}

pradm.login() if pradm.loggedin()
