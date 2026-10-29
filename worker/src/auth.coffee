
# curl -X GET "https://api.oa.works/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
# curl -X GET "https://api.oa.works/auth?apikey=YOURAPIKEYHERE"

# store user record object in kv as users/:UID (value is stringified json object)
# and store a map of API keys as well, auth/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
# store a login token at auth/token/:TOKEN (value is email) (autoexpire login tokens at 20mins 1200s)
# and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about three months 7890000s, but rotate them on non-cookie use)
# and store users to the index as well if available

P.auth = (key) ->
  if typeof key is 'string' # or key can be false, to pass through to unauthorised / login / request page
    return @users._get key

  if not key and @user? and (@fn is 'auth' or key is false)
    user = @user
  else if key isnt false
    if (@params.token or @params.auth) and email = await @kv 'auth/token/' + (@params.token ? @params.auth), '' # true causes delete after found
      if not user = await @users._get email # get the user record if it already exists
        user = await @users._create email # create the user record if not existing, as this is the first token login attempt for this email address
    if not user and @apikey
      if @S.bg is true
        user = await @users._get undefined, @apikey
      if not user and uid = await @kv 'auth/apikey/' + @apikey
        user = await @users._get uid # no user creation if apikey doesn't match here - only create on login token above 
    if not user and (@params.resume or @cookie)
      if not resume = @params.resume # login by resume token if provided in param or cookie
        try
          cookie = JSON.parse decodeURIComponent(@cookie).split((S.auth?.cookie?.name ? 'oaworksLogin') + "=")[1].split(';')[0]
          resume = cookie.resume
          uid = cookie._id
      uid ?= @headers['x-id']
      if @params.email and not uid
        uid = @hashhex @params.email.trim().toLowerCase()
      if resume and uid and restok = await @kv 'auth/resume/' + uid + '/' + resume
        user = await @users._get uid
        user.resume = resume if user?

  if typeof user is 'object' and user._id

    if not user.resume? and not @apikey
      user.resume = @uid()
      @kv 'auth/resume/' + user._id + '/' + user.resume, {createdAt: Date.now()}, 7890000 # resume token lasts three months (could make six at 15768000)

    if await @auth.role 'root', @user
      @log msg: 'root login'
  
  if not @format and (@fn is 'auth' or @unauthorised) and @headers['user-agent'] and @headers['user-agent'].toLowerCase().includes('mozilla') and @headers.accept and @headers.accept.includes('/html') and not @headers.accept.includes '/json'
    @format = 'html'
  if not key and @format is 'html'
    ret = '<body>'
    ret += '<script type="text/javascript" src="/client/oaworksLogin.min.js?v=' + @S.version + '"></script>\n'
    ret += '<h1>' + (if @base then @base.replace('bg.', '(bg) ') else @S.name) + '</h1>'
    if not @user?
      ret += '<input autofocus id="OALoginEmail" class="OALoginEmail" type="text" name="email" placeholder="email">'
      ret += '<input id="OALoginToken" class="OALoginToken" style="display:none;" type="text" name="token" placeholder="token (check your email)">'
      ret += '<p class="OALoginWelcome" style="display:none;">Welcome back</p>'
      ret += '<p class="OALoginLogout" style="display:none;"><a id="OALoginLogout" href="#">logout</a></p>'
    else
      ret += '<p>' + user.email + '</p><p><a id="PLogout" href="#">logout</a></p>'
    return ret + '</body>'
  else
    return user


P.auth.token = (email, from, subject, text, html, template, url) ->
  email ?= @params.email
  if email
    email = email.trim().toLowerCase()
    from ?= S.auth?.from ? 'login@oa.works'
    token = @uid 8
    console.log(email, token) if @S.dev and @S.bg is true
    url ?= @params.url
    if url
      url += '#' + token
      subject ?= 'Complete your login to ' + (if url.includes('//') then url.split('//')[1] else url).split('/')[0]
    else
      url = @base + '/' + @route.replace '/token', '/' + token
      subject ?= 'Complete your login to ' + (if @base then @base.replace('bg.', '(bg) ') else @S.name)
    @kv 'auth/token/' + token, email, 1200 # create a token that expires in 20 minutes
    @waitUntil @mail
      from: from
      to: email
      subject: subject
      text: text ? 'Your login code is:\r\n\r\n' + token + '\r\n\r\nor use this link:\r\n\r\n' + url + '\r\n\r\nnote: this single-use code is only valid for 20 minutes.'
      html: html ? '<html><body><p>Your login code is:</p><p><b>' + token + '</b></p><p>or click on this link</p><p><a href=\"' + url + '\">' + url + '</a></p><p>note: this single-use code is only valid for 10 minutes.</p></body></html>'
      params: {token: token, url: url}
    return email: email
  else
    return

P.auth.role = (grl, user) ->
  grl ?= @params.role
  user = if typeof user is 'object' then user else if user or @params.auth then await @users._get(user ? @params.auth) else @user

  return 'system' if grl is 'system' and @system
  return 'root' if user?.email and user.email in (if typeof @S.root is 'string' then [@S.root] else if Array.isArray(@S.root) then @S.root else [])
  return grl if grl.startsWith('@') and user?.email? and user.email.endsWith grl # a user can be allowed if the required auth is the @domain.com of their email address
    
  return false


P.auth.logout = (user) ->
  user ?= @user
  if user
    await @kv._each 'auth/resume/' + (if typeof user is 'string' then (if user.includes('@') then @hashhex(user.trim().toLowerCase()) else user) else user._id), ''
    return true
  else
    return false
    


P.users = _index: true, _auth: 'system'

P.users._get = (uid, apikey) ->
  if apikey
    us = await @index 'users', 'apikey:"' + apikey + '"'
    if us?.hits?.total is 1
      user = us.hits.hits[0]._source 
      user._id ?= us.hits.hits[0]._id
  else if typeof uid is 'string'
    uid = uid.replace('users/','') if uid.startsWith 'users/'
    uid = @hashhex(uid.trim().toLowerCase()) if uid.includes '@'
    if @S.bg isnt true
      try user = await @kv 'users/' + uid
    if not user?
      try user = await @index 'users/' + uid
      if user? and @S.bg isnt true # may have found a user from the index who isn't in the local kv yet, so put it in
        try await @kv 'users/' + uid, user
        try await @kv 'auth/apikey/' + user.apikey, uid
  return user

P.users._create = (user) ->
  user = {email: user} if typeof user is 'string'
  return false if typeof user.email isnt 'string' or not user.email.includes '@'
  u =
    _id: @hashhex user.email.trim().toLowerCase()
    email: user.email
    apikey: @uid()
  delete user.email
  try u.profile = user
  try u.creation = @base + '/' + @route # which domain the user was created from
  u.createdAt = new Date()
  try await @kv 'users/' + u._id, u
  try await @kv 'auth/apikey/' + u.apikey, u._id
  try @waitUntil @index 'users/' + u._id, u
  return u


