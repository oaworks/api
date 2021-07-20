
# curl -X GET "https://api.oa.works/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
# curl -X GET "https://api.oa.works/auth?apikey=YOURAPIKEYHERE"

# store user record object in kv as users/:UID (value is stringified json object)
# and store a map of API keys as well, auth/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
# store a login token at auth/token/:TOKEN (value is email) (autoexpire login tokens at 20mins 1200s)
# and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about three months 7890000s, but rotate them on non-cookie use)
# and store users to the index as well if available

P.auth = (key) ->
  shn = 'x-' + @S.name.toLowerCase() + '-system'
  if @S.name and @S.system and @headers[shn] is @S.system
    delete @headers[shn]
    @system = true
  return true if @system

  # if params.auth, someone looking up the URL route for this acc. Who would have the right to see that?
  if typeof key is 'string'
    return @users._get key

  if not key? and @user? and @fn is 'auth'
    user = @user
  else
    if (@params.access_token and oauth = await @oauth @params.access_token) or ((@params.token or @params.auth) and email = await @kv 'auth/token/' + (@params.token ? @params.auth), '') # true causes delete after found
      if not user = await @users._get(oauth?.email ? email) # get the user record if it already exists
        user = await @users._create oauth ? email # create the user record if not existing, as this is the first token login attempt for this email address
    if not user and @apikey and uid = await @kv 'auth/apikey/' + @apikey
        user = await @users._get uid # no user creation if apikey doesn't match here - only create on login token above 
    if not user and (@params.resume or @cookie) # accept resume on a header too?
      if not resume = @params.resume # login by resume token if provided in param or cookie
        try
          cookie = JSON.parse decodeURIComponent(@cookie).split((S.auth?.cookie?.name ? 'pradm') + "=")[1].split(';')[0]
          resume = cookie.resume
          uid = cookie._id
      uid ?= @headers['x-id']
      if @params.email and not uid
        uid = @hashhex @params.email.trim().toLowerCase() # accept resume with email instead of id?
      if resume and uid and restok = await @kv 'auth/resume/' + uid + '/' + resume
        user = await @users._get uid
        user.resume = resume

  if typeof user is 'object' and user._id
    # if 2fa is enabled, request a second form of ID (see below about implementing 2fa)

    # record the user login timestamp, and if login came from a service the user does not yet have a role in, add the service user role
    # who can add the service param?
    if @params.service and not user.roles?[@params.service]?
      user.roles ?= {}
      user.roles[@params.service] = 'user'
      @users._update user

    if not user.resume? and not @apikey
      user.resume = @uid()
      @kv 'auth/resume/' + user._id + '/' + user.resume, Date.now(), 7890000 # resume token lasts three months (could make six at 15768000)

    if await @auth.role 'root', @user
      @log msg: 'root login' #, notify: true

  # if this is called with no variables, and no defaults, provide a count of users?
  # but then if logged in and on this route, what does it provide? the user account?
  
  if not key? and @fn is 'auth' and not @format and @headers['user-agent'] and @headers['user-agent'].toLowerCase().includes('mozilla') and @headers.accept and @headers.accept.toLowerCase().includes 'html'
    @format = 'html'

  if not key? and @format is 'html'
    ret = if @fn is 'auth' then '<body class="black">' else '<body>'
    ret += '<div class="flex" style="margin-top: 10%;"><div class="c6 off3"><h1 id="title" class="centre statement" style="font-size:40px;">' + (if @base then @base.replace('bg.', '(bg) ') else @S.name) + '</h1></div></div>'
    ret += '<div class="flex" style="margin-top: 5%;"><div class="c6 off3">'
    if not user?
      ret += '<input autofocus id="PEmail" class="PEmail big shadow" type="text" name="email" placeholder="email">'
      ret += '<input id="PToken" class="PToken big shadow" style="display:none;" type="text" name="token" placeholder="token (check your email)">'
      ret += '<p class="PWelcome" style="display:none;">Welcome back</p>'
      ret += '<p class="PLogout" style="display:none;"><a id="PLogout" class="button action" href="#">logout</a></p>'
    else
      ret += '<p>' + user.email + '</p><p><a id="PLogout" class="button action" href="#">logout</a></p>'
    ret += '<div class="PLoading" style="display:none;"><div class="loading big"></div></div>'
    ret += '</div></div></body>'
    ret += '<script>'
    ret += 'P.afterLogout = function() { location.reload(); }; ' if @fn is 'auth'
    ret += 'P.loginNext = true;'  if @fn isnt 'auth' or user?
    ret += '</script>'
    return ret
  else
    return user


P.auth.token = (email, from, subject, text, html, template, url) ->
  email ?= @params.email
  if email
    email = email.trim().toLowerCase()
    from ?= S.auth?.from ? 'login@example.com'
    subject ?= S.auth?.subject ? 'Complete your login to ' + (if @base then @base.replace('bg.', '(bg) ') else @S.name)
    token = @uid 8
    console.log(email, token) if @S.dev and @S.bg is true
    url ?= @params.url
    if url
      url += '#' + token
    else
      url = @base + '/' + @route.replace '/token', '/' + token
    @kv 'auth/token/' + token, email, 1200 # create a token that expires in 20 minutes
    @waitUntil @mail
      from: from
      to: email
      subject: subject
      text: text ? 'Your login code is:\r\n\r\n' + token + '\r\n\r\nor use this link:\r\n\r\n' + url + '\r\n\r\nnote: this single-use code is only valid for 20 minutes.'
      html: html ? '<html><body><p>Your login code is:</p><p><b>' + token + '</b></p><p>or click on this link</p><p><a href=\"' + url + '\">' + url + '</a></p><p>note: this single-use code is only valid for 10 minutes.</p></body></html>'
      #template: template
      params: {token: token, url: url}
    return email: email
  else
    return @uid 8 # is there a case where this would somehow be useful? It's not getting saved anywhere for later confirmation...

# auth/:uid/role/:grl
# check if a user has a role or one of a list of roles
P.auth.role = (grl, user) ->
  grl ?= @params.role
  user = if typeof user is 'object' then user else if user or @params.auth then await @users._get(user ? @params.auth) else @user

  return 'system' if grl is 'system' and @system
  return 'root' if user?.email and user.email in (if typeof @S.root is 'string' then [@S.root] else if Array.isArray(@S.root) then @S.root else [])

  if user?.roles?
    for g in (if typeof grl is 'string' then grl.split(',') else grl)
      [group, role] = g.replace('/', '.').split '.'

      return 'owner' if group is user._id # user is owner on their own group
      if role
        if role in (user.roles[group] ? [])
          return role
        else if user.roles[group]?
          cascade = ['service', 'owner', 'super', 'admin', 'auth', 'bulk', 'delete', 'remove', 'create', 'insert', 'publish', 'put', 'draft', 'post', 'edit', 'update', 'user', 'get', 'read', 'info', 'public']
          if -1 < ri = cascade.indexOf role
            for rl in cascade.splice 0, ri
              return rl if rl in user.roles[group]

  return false


# /auth/:uid/roles/:grl
# add a user to a role, or remove, or deny
# deny meaning automatically not allowed any other role on the group
# whereas otherwise a user (or system on behalf of) should be able to request a role (TODO)
P.auth.add = (grl, user, remove, deny) ->
  grl ?= @params.add
  [group, role] = grl.replace('/', '.').split '.'

  user = if typeof user is 'object' then user else if user or @params.auth then await @users._get(user ? @params.auth) else @user
  if @user._id isnt user._id
    # TODO what about one logged in user acting on the roles route of another? - which groups could a user add another user to?
    return false if not await @auth.role 'system'

  remove ?= (@request.method is 'DELETE' or @params._delete is true) and @fn is 'auth.roles'

  if group is 'root' or role is 'root' # root only allowed by config. can't be set via API.
    return false
  else if deny
    user.roles[group] = ['deny'] # no other roles can be kept
    @users._update user
  else if not role
    if user.roles[group]?
      if remove?
        delete user.roles[group]
        @users._update user
    else
      user.roles[group] = ['user']
      @users._update user
  else if user.roles?[group] and role in user.roles[group]
    if remove?
      user.roles[group].splice user.roles[group].indexOf(role), 1
      delete user.roles[group] if not user.roles[group].length
      @users._update user
  else
    user.roles[group] ?= []
    user.roles.group.push role
    @users._update user

  return user

P.auth.remove = (grl, user) ->
  grl ?= @params.remove
  return @auth.permit grl, user, true

P.auth.deny = (grl, user) ->
  grl ?= @params.deny
  return @auth.permit grl, user, undefined, true
  

P.auth.logout = (user) -> # how about triggering a logout on a different user account
  user ?= @user
  if user
    await @kv._each 'auth/resume/' + (if typeof user is 'string' then (if user.includes('@') then @hashhex(user.trim().toLowerCase()) else user) else user._id), ''
    return true
  else
    return false
    

# add a 2FA mechanism to auth (authenticator, sms...)
# https://stackoverflow.com/questions/8529265/google-authenticator-implementation-in-python/8549884#8549884
# https://github.com/google/google-authenticator
# http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/
#P.authenticator = () ->
# TODO if an authenticator app token is provided, check it within the 30s window
# delay responses to 1 per second to stop brute force attacks
# also need to provide the token/qr to initialise the authenticator app with the service
#  return false

# device fingerprinting was available in the old code but no explicit requirement for it so not added here yet
# old code also had xsrf tokens for FORM POSTs, add that back in if relevant

P._oauth = (token, cid) ->
  # https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  sets = {}
  if token #?= @params.access_token
    try
      # we did also have facebook oauth in here, still in old code, but decided to drop it unless explicitly required again
      validate = await @fetch 'https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + token, method: 'POST' # has to be a POST even though it sends nothing
      cid ?= @S.svc[@params.service ? 'z']?.google?.oauth?.client?.id ? S.use?.google?.oauth?.client?.id
      if cid? and validate.data?.aud is cid
        ret = await @fetch 'https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + token
        return
          email: ret.data.email.toLowerCase()
          google: {id: ret.data.id}
          name: ret.data.name ? (ret.data.given_name + (if ret.data.family_name then ' ' + ret.data.family_name else ''))
          avatar: ret.data.picture
  return undefined
# an oauth client-side would require the google oauth client token. It's not a secret, but must be got in advance from google account provider
# ours is '360291218230-r9lteuqaah0veseihnk7nc6obialug84.apps.googleusercontent.com' - but that's no use to anyone else, unless wanting to login with us
# the Oauth URL that would trigger something like this would be like:
# grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true'
# grl += '&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
# grl += '&state=' + state + '&redirect_uri=' + P.oauthRedirectUri + '&client_id=' + P.oauthGoogleClientId
# state would be something like Math.random().toString(36).substring(2,8) and would be sent and also kept for checking against the response
# the response from oauth login page would go back to current page and have a # with access_token= and state=
# NOTE as it is after a # these would only be available on a browser, as servers don't get the # part of a URL
# if the states match, send the access_token into the above method and if it validates then we can login the user


P.users = _index: true, _hide: true, _auth: 'system'

P.users._get = (uid) ->
  if typeof uid is 'string'
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
  u.profile = user # could use other input as profile input data? better for services to store this where necessary though
  u.roles = {}
  u.createdAt = new Date()
  try await @kv 'users/' + u._id, u
  try await @kv 'auth/apikey/' + u.apikey, u._id
  try @waitUntil @index 'users/' + u._id, u
  return u

P.users._update = (uid, user) ->
  # TODO how to decide who can update users, remotely or locally, and is it always a total update or could be a partial?
  if typeof uid is 'object' and user._id and not user?
    user = uid
    uid = user._id
  if typeof uid is 'string' and typeof user is 'object' and JSON.stringify(user) isnt '{}'
    uid = uid.replace('users/','') if uid.startsWith 'users/'
    uid = @hashhex(uid.trim().toLowerCase()) if uid.includes '@'
    user.updatedAt = new Date()
    try await @kv 'users/' + uid, user
    try @waitUntil @index 'users/' + uid, user
    return true
  else
    return false

P.users._delete = (uid) ->
  if user = (if typeof uid is 'object' then uid else if @user?._id is uid then @user else await @users._get uid)
    try await @kv._each 'auth/resume/' + user._id, ''
    try await @kv 'auth/apikey/' + user.apikey, ''
    try await @kv 'users/' + user._id, ''
    try await @index 'users/' + user._id, ''

