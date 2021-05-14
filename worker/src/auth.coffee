
# curl -X GET "https://api.lvatn.com/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
# curl -X GET "https://api.lvatn.com/auth?apikey=YOURAPIKEYHERE"

# NOTE all emails will be lowercased
# store user record object in kv as user/:UID (value is stringified json object)
# and store a map of API keys as well, user/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
# store a login token at auth/token/:TOKEN (value is email) (autoexpire login tokens at 10mins 600s)
# and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about three months 7890000s, but rotate them on non-cookie use)

# TODO check how system header auth should affect checks on auth and group/role activities further down the stack
# ideally should be ok to run anything after system hand-off that already got auth'd at top level, but check

P.auth = (key) ->
  try return true if @S.name and @S.system and @headers['x-' + S.name + '-system'] is @S.system
  # if params.auth, someone looking up the URL route for this acc. Who would have the right to see that?
  if typeof key is 'string'
    return await @kv 'user/' + (if key.includes('@') then @hashhex(key) else key)

  if (@params.access_token and oauth = await @oauth @params.access_token) or ((@params.token or @params.auth) and email = await @kv 'auth/token/' + (@params.token ? @params.auth), '') # true causes delete after found
    if not user = await @kv 'user/' + @hashhex(oauth?.email ? email) # get the user record if it already exists
      user = await @auth._insert oauth ? email # create the user record if not existing, as this is the first token login attempt for this email address
  if not user and @apikey and uid = await @kv 'user/apikey/' + @apikey
      user = await @kv 'user/' + uid # no user creation if apikey doesn't match here - only create on login token above 
  if not user and (@params.resume or @cookie) # accept resume on a header too?
    if not resume = @params.resume # login by resume token if provided in param or cookie
      try
        cookie = JSON.parse decodeURIComponent(@cookie).split((S.auth?.cookie?.name ? 'pradm') + "=")[1].split(';')[0]
        resume = cookie.resume
        uid = cookie._id
    uid ?= @id # if picked up from incoming params
    if @params.email and not uid
      uid = @hashhex @params.email # accept resume with email instead of id?
    if resume and uid and restok = await @kv 'auth/resume/' + uid + '/' + resume, (if @params.resume then '' else undefined) # delete if not a cookie resume
      user = await @kv 'user/' + uid
      user.resume = resume

  if typeof user is 'object' and user._id
    # if 2fa is enabled, request a second form of ID (see below about implementing 2fa)

    # record the user login timestamp, and if login came from a service the user does not yet have a role in, add the service user role
    # who can add the service param?
    if @params.service and not user.roles?[@params.service]?
      upd = {}
      upd.roles = user.roles ? {}
      upd.roles[@params.service] = 'user'
      @kv 'user/' + user._id, upd, user # record the user login time?

    if @params.resume or @params.token or @params.auth
      # if a fresh login or resume token was used explicitly, provide a new resume token
      user.resume = @uid()
      @kv 'auth/resume/' + user._id + '/' + user.resume, Date.now(), 7890000 # resume token lasts three months (could make six at 15768000)

    #if @auth.role 'root', @user
    #  lg = msg: 'Root login from ' + @request.headers['x-forwarded-for'] + ' ' + @request.headers['cf-connecting-ip'] + ' ' + @request.headers['x-real-ip']
    #  lg.notify = subject: lg.msg
    #  @log lg

  # if this is called with no variables, and no defaults, provide a count of users?
  # but then if logged in and on this route, what does it provide? the user account?
  if not key? and not user? and @format is 'html'
    ret = '<input id="pradmEmail" class="pradmEmail" style="min-width:250px;" type="text" name="email" placeholder="Enter your email address to sign in"><input id="pradmToken" class="pradmToken" style="display:none;min-width:250px;" type="text" name="token" placeholder="Enter the login token once you receive it">'
    ret += '<script type="text/javascript" src="/client/pradm.js"></script><script type="text/javascript" src="/client/pradmLogin.js"></script>'
    ret += '<script>pradm.next = true;</script>'
    return ret
  else
    return user


P.auth.token = (email, from, subject, text, html, template, url) ->
  email ?= @params.email
  if email
    email = email.trim().toLowerCase()
    from ?= S.auth?.from ? 'login@example.com'
    subject ?= S.auth?.subject ? 'Please complete your login'
    token = @uid 8
    console.log(email, token) if @S.dev and @S.bg is true
    url ?= @params.url
    if url
      url += '#' + token
    else
      url = @base + '/' + @route.replace '/token', '/' + token
    @kv 'auth/token/' + token, email, 600 # create a token that expires in 10 minutes
    @waitUntil @mail
      from: from
      to: email
      subject: subject
      text: text ? 'Your login code is:\r\n\r\n' + token + '\r\n\r\nor use this link:\r\n\r\n' + url + '\r\n\r\nnote: this single-use code is only valid for 10 minutes.'
      html: html ? '<html><body><p>Your login code is:</p><p><b>' + token + '</b></p><p>or click on this link</p><p><a href=\"' + url + '\">' + url + '</a></p><p>note: this single-use code is only valid for 10 minutes.</p></body></html>'
      #template: template
      params: {token: token, url: url}
    return email: email
  else
    return @uid 8 # is there a case where this would somehow be useful? It's not getting saved anywhere for later confirmation...

# auth/role/:grl/:uid
# any logged in user can find out if any other user is in a role
P.auth.role = (grl, uid) ->
  grl ?= @params.role
  grl = @params.auth if not grl? and typeof @params?.auth is 'string'
  if typeof grl is 'string' and grl.indexOf('/') isnt -1
    if not uid?
      uid = grl.split('/').pop()
      grl = grl.replace '/' + uid, ''
  user = if typeof uid is 'object' then uid else if typeof uid is 'string' then await @kv(if uid.includes('@') then @hashhex(uid) else uid) else @user
  return false if not user?.roles?

  grl = [grl] if typeof grl is 'string'
  for g in grl
    g = g.replace('/','.')
    [group, role] = g.split '.'
    if not role?
      role = group
      group = '__global__'

    return 'owner' if group is user.id # user is owner on their own group
    return 'root' if 'root' in (user.roles.__global__ ? [])
    return role if role in (user.roles[group] ? [])

    if user.roles[group]?
      cascade = ['root', 'service', 'owner', 'super', 'admin', 'auth', 'bulk', 'delete', 'remove', 'create', 'insert', 'publish', 'put', 'draft', 'post', 'edit', 'update', 'user', 'get', 'read', 'info', 'public']
      if 0 < ri = cascade.indexOf role
        for rl in cascade.splice 0, ri
          return rl if rl in user.roles[group]

  return false


P.auth.roles = (user, grl, keep) ->
  user ?= @user ? @params.roles
  user = await @kv('user/' + (if user.includes('@') then @hashhex(user) else user)) if typeof user is 'string'

  # what about one logged in user acting on the roles route of another?
  [group, role] = grl.split '.'
  if not role?
    role = group
    group = '__global__'

  if role in user.roles?[group] ? []
    if keep?
      user.roles[group].splice user.roles[group].indexOf(role), 1
      @kv 'user/' + user._id, user
  else
    user.roles[group] ?= []
    user.roles.group.push role
    @kv 'user/' + user._id, user


P.auth.logout = (user) -> # how about triggering a logout on a different user account
  user ?= @user
  if user
    @kv 'auth/resume/' + (if typeof user is 'string' then (if user.includes('@') then @hashhex(user) else user) else user._id), ''
  if @format is 'html'
    ret = '<p id="logout">Logging out...</p>'
    ret += '<script type="text/javascript" src="/client/pradm.js"></script><script type="text/javascript" src="/client/pradmLogin.js"></script>'
    ret += '''<script>
setTimeout(function() {
  pradm.logout();
  pradm.html('#logout', "You're logged out");
}, 2000);
</script>'''
    return ret

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
# grl += '&state=' + state + '&redirect_uri=' + pradm.oauthRedirectUri + '&client_id=' + pradm.oauthGoogleClientId
# state would be something like Math.random().toString(36).substring(2,8) and would be sent and also kept for checking against the response
# the response from oauth login page would go back to current page and have a # with access_token= and state=
# NOTE as it is after a # these would only be available on a browser, as servers don't get the # part of a URL
# if the states match, send the access_token into the above method and if it validates then we can login the user


P.auth._insert = (obj) ->
  if typeof obj is 'string'
    obj = email: obj
  return false if typeof obj.email isnt 'string' or not obj.email.includes '@'
  u =
    _id: @hashhex obj.email.trim().toLowerCase()
    email: obj.email #store email here or not?
    apikey: @uid() # store the apikey here or not?
  delete obj.email
  u.profile = obj # could use obj as profile input data? better for services to store this where necessary though
  first = false # if no other user accounts yet
  u.roles = if first then {__global__: ['root']} else {}
  u.createdAt = new Date()
  @kv 'user/apikey/' + u.apikey, u._id
  @kv 'user/' + u._id, u
  return u

P.auth._update = (r, user) ->
  user ?= r.auth # what about update a user other than the logged in one?
  if r.param and nu = @auth r.param
    a = '' # does the currently authorised user have permission to update the user being queried? if so, set user to nu
  if JSON.stringify(r.params) isnt '{}'
    user.profile ?= {}
    for p of r.params # normal user can update profile values
      user.profile[p] = pr[p]
    await @kv 'user/' + user.id, user
    return true # or return the updated user object?
  else
    return false

P.auth._remove = (key) ->
  key = key.replace('user/','') if key.startsWith 'user/'
  key = @hashhex(key) if key.includes '@'
  user = if @user?._id is key then @user else await @kv 'user/' + key
  try @auth.logout key
  try @kv 'user/apikey/' + user.apikey, ''
  try @kv 'user/' + key, ''