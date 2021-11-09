
P.service ?= undefined # optionally set the name of the service using the login
P.oauthRedirectUri = undefined # this can be set, but if not, current page will be used (whatever is used has to be authorised as a redirect URI with the oauth provider)
P.oauthGoogleClientId = undefined # this must be provided for oauth to work
P.account = undefined # set to the account object once retrieved

P.token = (e) ->
  try e.preventDefault()
  P.cookie false
  # TODO add a validation of the email val if email not already set?
  if not email = P.val '#PEmail'
    P.css '#PEmail', 'border-color', '#f04717'
    P.focus '#PEmail'
    return
  P.hide '.PEmail'
  P.show '.PLoading'
  P.show '.PToken'
  opts =
    success: (data) ->
      P.hide '.PLoading'
      P.focus '#PToken'
      P._loggingin = setInterval () ->
        P.loginSuccess() if P.loggedin()
      , 2000
    data:
      email: email
      url: window.location.protocol + '//' + window.location.host + window.location.pathname
      service: P.service
  P.ajax '/auth/token', opts

P.loginSuccess = (data) ->
  if P._loggingin
    clearInterval P._loggingin
    delete P._loggingin
  P.hide '.PLogin'
  P.hide '.PLoading'
  P.hide '.PToken'
  if typeof data is 'object'
    P.account = data
    P.cookie data
  if P.account?.email and P '.PWelcome'
    ph = P.html '.PWelcome'
    ph = if ph.length then ph + ' ' + P.account.email.split('@')[0] else P.account.email
    P.html '.PWelcome', ph
    P.show '.PWelcome'
  if not P.loginNext and window.location.search.indexOf('next=') isnt -1
    P.loginNext = decodeURIComponent window.location.search.split('next=')[1].split('&')[0]
  else if not P.loginNext and window.location.search.startsWith '?next'
    P.loginNext = true
  if P.loginNext
    if P.loginNext is true
      location.reload()
    else
      window.location = P.loginNext
  else
    try
      P.show '.PLogout'
      P.on 'click', '#PLogout', P.logout
    try
      P.afterLogin() if typeof P.afterLogin is 'function'

P.loginError = (err, xhr) ->
  console.log 'Login error'
  console.log err # and log an error to backend somewhere...
  console.log xhr # paradigm API may have xhr.response with a follow-up option such as a way to request access or permission
  if P._loggingin
    clearInterval P._loggingin
    delete P._loggingin
  P.cookie false
  P.account = undefined
  P.hide '.PLoading'
  P.hide '.PToken'
  P.set '#PEmail', ''
  P.set '#PEmail', 'placeholder', 'error, enter your email to try again'
  P.show '.PEmail'
  P.show '.PLogin'
  
P.login = (e) ->
  try e.preventDefault()
  opts =
    success: P.loginSuccess
    error: P.loginError
    data: service: P.service

  pt = P.val '#PToken'
  if window.location.hash.indexOf('access_token=') isnt -1
    opts.data.oauth = {}
    for p of pts = window.location.hash.replace('#','').split '&'
      [k, v] = pts[p].split '='
      opts.data.oauth[k] = v
    oauthcookie = P.cookie 'poauth'
    P.cookie 'poauth', false
  else if window.location.hash.replace('#','').length is 8
    opts.data.token = window.location.hash.replace '#', ''
    try window.history.pushState "", "", window.location.pathname
  else if typeof pt is 'string' and pt.length is 8
    opts.data.token = pt
  else if account = P.loggedin()
    opts.data.email = account.email
    opts.data.resume = account.resume

  if (opts.data.email and opts.data.resume) or opts.data.hash or opts.data.token or opts.data.oauth?.state is oauthcookie?.state
    P.hide '.PEmail'
    P.hide '.PToken'
    P.show '.PLoading'
    P.ajax '/auth', opts

P.loggedin = () ->
  if p = P.cookie()
    P.account = p if typeof p is 'object' and JSON.stringify(p) isnt '{}'
  return P.account

P.logout = (e) ->
  try e.preventDefault()
  P.show '.PLoading'
  if account = P.loggedin()
    P.ajax '/auth/logout?apikey=' + account.apikey, success: () ->
      P.account = undefined
      P.cookie false
      P.hide '.PLoading' # just in case anything made this visible
      if P.loginNext is true
        location.reload()
      else if P.loginNext
        window.location = P.loginNext
      else if typeof P.afterLogout is 'function'
        try P.afterLogout()

P.requestPermission = () ->
  P.hide '.PRequestPermission'
  P.show '.PRequestedPermission'
  P.ajax '/auth/request'

P.ready () ->
  try P.on 'enter', '#PEmail', P.token
  try P.on 'keyup', '#PToken', (e) -> P.login() if P.val('#PToken').length is 8
  try P.on 'click', '#PRequestPermission', P.requestPermission
  try
    if P.val('#POauthGoogle').length and P.oauthGoogleClientId
      state = Math.random().toString(36).substring(2,8)
      grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
      grl += '&state=' + state + '&redirect_uri=' + (P.oauthRedirectUri ? window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + P.oauthGoogleClientId
      P.set '#POauthGoogle', 'href', grl
      P.on 'click', '#POauthGoogle', () -> P.cookie 'poauth', {state:state}, {expires:1}
  
  loggedin = P.loggedin()
  if loggedin or (typeof window.location.hash is 'string' and window.location.hash and window.location.hash.replace('#', '').length is 8)
    P.loginNext = undefined if loggedin # don't go to next if already logged in
    P.login() # will it be worth doing this on every page load, or only those with a login token hash?
