
S.log ?= {}

# it would also be good to log every fetch, and what was sent with it too, although if it was a big file or something like that, then not that
# what about a param to pass to avoid logging?

P.log = (msg) ->
  if @S.log isnt false
    store = not msg? # an empty call to log stores everything in the _logs list
    
    if typeof msg is 'string'
      if msg.indexOf('/') isnt -1 and msg.indexOf(' ') is -1
        msg = fn: msg
      else
        msg = msg: msg
    else if Array.isArray msg
      @_logs.push(l) for l in msg
      msg = undefined
  
    if not msg?
      if @parts.length is 1 and @parts[0] is 'log' # should a remote log be allowed to send to a sub-route URL as an ID? maybe with particular auth?
        # receive a remote log
        msg = if typeof @body is 'object' then {logs: @body} else @params # bunch of logs sent in as POST body, or else just params
        msg.fn ?= @params.log # the fn, if any, would be in params.log (because @fn would just be log)
      msg ?= {}
      try
        msg.request =
          url: @request.url
          method: @request.method
      try msg.request.body = @body?
      try
        msg.request.cf =
          colo: @request.cf.colo
          country: @request.cf.country
      try
        msg.request.headers =
          ip: @headers['x-real-ip']
          'user-agent': @headers['user-agent']
          referer: @headers.referer
      try
        msg.fn ?= @fn
        msg.refresh = @refresh
        msg.parts = @parts
        msg.completed = @completed
        msg.cached = @cached
      try
        # don't stringify the whole obj, allow individual keys, but make them all strings to avoid mapping clashes
        msg.params = {}
        for p of @params
          msg.params[p] = if typeof @params[p] is 'string' then @params[p] else JSON.stringify @params[p]
      try msg.apikey = @headers.apikey? or @headers['x-apikey']? # only record if apikey was provided or not
      try msg.user = @user?._id
      msg.unauthorised = true if @unauthorised
    else if typeof msg is 'object' and msg.res and msg.args # this indicates the fn had _diff true
      try # find a previous log for the same thing and if it's different add a diff: true to the log of this one. Or diff: false if same, to track that it was diffed
        prev = await @index 'log', 'args:"' + msg.args # TODO what if it was a diff on a main log event though? do all log events have child log events now? check. and check what args/params should be compared for diff
        msg.diff = prev.hits.hits[0]._source.res isnt msg.res
        # if msg.diff, send an email alert? Or have schedule pick up on those later?

    if store
      msg.logs ?= []
      if Array.isArray(this?._logs) and @_logs.length
        for l in @_logs
          #msg.msg ?= l.msg
          msg.alert ?= l.alert
          msg.notify ?= l.notify
          msg.logs.push l
      msg._createdAt ?= Date.now()
      msg.name ?= S.name
      msg.version ?= S.version
      msg.base = @base
      msg.bg = true if @S.bg is true
      msg.system = true if @system is true
      msg.scheduled = true if @scheduled is true
      try
        msg.started = @started
        msg.took = Date.now() - @started
      mid = 'log/' + (@rid ? await @uid())
      if @S.bg is true or @S.kv is false
        if not indexed = await @index mid, msg
          await @index 'log', {}
          @index mid, msg
      else
        @kv mid, msg
    else
      @_logs.push msg
  else if @S.dev and @S.bg is true
    console.log msg

P.log._schedule = 'log'

P.log.schedule = () ->
  # this should become _schedule but for now is not so I can manually trigger it for testing
  # define what to do on a scheduled trigger
  # grab every log in the kv store and throw them to the index
  # but for now, just delete them
  @kv._each 'log', ''


'''
P.add 'mail/feedback/:token',
  get: () ->
    try
      from = this.queryParams.from ? P.settings.mail?.feedback?[this.urlParams.token]?.from ? "sysadmin@cottagelabs.com"
      to = P.settings.mail?.feedback?[this.urlParams.token]?.to
      service = P.settings.mail?.feedback?[this.urlParams.token]?.service
      subject = P.settings.mail?.feedback?[this.urlParams.token]?.subject ? "Feedback"
    if to?
      P.mail.send
        service: service
        from: from
        to: to
        subject: subject
        text: this.queryParams.content
    return {}


level/loglevel
group (default to whatever is after svc or src, or just part 0)
notify/alert

P.log = (opts, fn, lvl='debug') ->

    loglevels = ['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off']
    loglevel = P.settings.log?.level ? 'all'
    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level
      if opts.notify and P.settings.log?.notify
        try
          os = @copy opts
        catch
          os = opts
        Meteor.setTimeout (() -> P.notify os), 100

      for o of opts
        if not opts[o]?
          delete opts[o]
        else if typeof opts[o] isnt 'string' and not _.isArray opts[o]
          try
            opts[o] = JSON.stringify opts[o]
          catch
            try
              opts[o] = opts[o].toString()
            catch
              delete opts[o]

      if loglevels.indexOf(loglevel) <= loglevels.indexOf 'debug'
        console.log opts.msg if opts.msg

  if typeof notify is 'string'
    if note.indexOf '@' isnt -1
      note = to: note

  if typeof note is 'object'
    note.text ?= note.msg ? opts.msg
    note.subject ?= P.settings.name ? 'API log message'
    note.from ?= P.settings.log?.from ? 'alert@cottagelabs.com'
    note.to ?= P.settings.log?.to ? 'mark@cottagelabs.com'
    P.mail.send note




P.ping = (url,shortid) ->
  return false if not url?
  url = 'http://' + url if url.indexOf('http') isnt 0
  if (not shortid? or shortid is 'random') and spre = pings.find {url:url,redirect:true}
    return spre._id
  else
    obj = {url:url,redirect:true}
    if shortid? and shortid isnt 'random'
      while already = pings.get shortid
        shortid += Random.hexString(2)
      obj._id = shortid
    return pings.insert obj

# craft an img link and put it in an email, if the email is viewed as html it will load the URL of the img,
# which actually hits this route, and allows us to record stuff about the event

# so for example for oabutton where this was first created for, an image url like this could be created,
# with whatever params are required to be saved, in addition to the nonce.
# On receipt the pinger will grab IP and try to retrieve location data from that too:
# <img src="https://api.cottagelabs.com/ping/p.png?n=<CURRENTNONCE>service=oabutton&id=<USERID>">

P.ping.png = () ->
  if not P.settings.ping?.nonce? or this.queryParams.n is P.settings.ping.nonce
    data = this.queryParams
    delete data.n
    data.ip = this.request.headers['x-forwarded-for'] ? this.request.headers['cf-connecting-ip'] ? this.request.headers['x-real-ip']
    data.forwarded = this.request.headers['x-forwarded-for']
    try
      res = HTTP.call 'GET', 'http://ipinfo.io/' + data.ip + (if P.settings?.use?.ipinfo?.token? then '?token=' + P.settings.use.ipinfo.token else '')
      info = JSON.parse res.content
      data[k] = info[k] for k of info
      if data.loc
        try
          latlon = data.loc.split(',')
          data.lat = latlon[0]
          data.lon = latlon[1]
    pings.insert data
  img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8BQDwAEgAF/posBPQAAAABJRU5ErkJggg==', 'base64');
  if this.queryParams.red
    img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=', 'base64')
  this.response.writeHead 200,
    'Content-disposition': "inline; filename=ping.png"
    'Content-type': 'image/png'
    'Content-length': img.length
    'Access-Control-Allow-Origin': '*'

    this.response.end img

P.add 'ping/:shortid',
  get: () ->
    if this.urlParams.shortid is 'random' and this.queryParams.url
      # may want to disbale this eventually as it makes it easy to flood the server, if auth is added on other routes
      return P.ping this.queryParams.url, this.urlParams.shortid
    else if exists = pings.get(this.urlParams.shortid) and exists.url?
        count = exists.count ? 0
        count += 1
        pings.update exists._id, {count:count}
        return
          statusCode: 302
          headers:
            'Content-Type': 'text/plain'
            'Location': exists.url
          body: 'Location: ' + exists.url
    else return 404
  put:
    authRequired: true
    action: () ->
      # certain user groups can overwrite a shortlink
      # TODO: overwrite a short link ID that already exists, or error out
  post: () ->
    return P.ping (this.request.body.url ? this.queryParams.url), this.urlParams.shortid
  delete:
    #authRequired: true
    action: () ->
      if exists = pings.get this.urlParams.shortid
        pings.remove exists._id
        return true
      else
        return 404
'''
