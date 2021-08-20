
S.log ?= {}

_bg_log_batch = []
_bg_log_batch_timeout = false
_bg_last_log_batch = false

P.log = (msg, store) ->

  _save_batch = () =>
    # TODO may be worth generalising this into index functionality and having an option to bulk any index
    # then index calls that are writing data should route to the bg /index functions instead of 
    # direct to the index, so that they can be temporarily stored and handled in bulk (only suitable for when they can be lost too)
    clearTimeout(_bg_log_batch_timeout) if _bg_log_batch_timeout isnt false
    _bg_log_batch_timeout = setTimeout _save_batch, 30000
    _bg_last_log_batch = Date.now()
    _last = (new Date(_bg_last_log_batch)).toISOString().replace('T',' ').split('.')[0]
    _batch = []
    while _batch.length < 400 and _bg_log_batch.length
      _batch.push _bg_log_batch.shift()
    if _batch.length
      console.log('Writing ' + _batch.length + ' logs to index', _batch[0]._id, _batch[_batch.length-1]._id, _last) if @S.bg is true
      if not indexed = await @index 'logs', _batch
        await @index 'logs', {}
        await @index 'logs', _batch
      _batch = []
    else if @S.bg is true
      console.log 'Checked log batch but none to save', _last

  if @S.log isnt false and @nolog isnt true
    store = not msg? if store isnt true # an empty call to log stores everything in the _logs list
    
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
        if @system
          _bg_log_batch.push @body
          _save_batch() if _bg_log_batch_timeout is false
          return true # end here, just saving a log received from remote with system credential
        else
          # receive a remote log - what permissions should be required?
          msg = if typeof @body is 'object' then @body else @params # bunch of logs sent in as POST body, or else just params
          msg = {logs: msg} if Array.isArray msg
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
        msg.request.headers = @headers # just get all headers to see what's useful?
        if msg.request.headers.cookie
          msg.cookie = true
          delete msg.request.headers.cookie
      #catch
      #try
      #  msg.request.headers = {}
      #  msg.headers.ip = (@headers['x-forwarded-for'] ? @headers['x-real-ip']) if @headers['x-real-ip'] or @headers['x-forwarded-for']
      #  msg.headers['user-agent'] = @headers['user-agent'] if @headers['user-agent']
      #  msg.headers.referer = @headers.referer if @headers.referer
      try
        msg.fn = @fn if not msg.fn? and @fn?
        msg.refresh = @refresh if @refresh
        msg.parts = @parts
        msg.completed = @completed if @completed
        msg.cached = @cached if @cached
      try
        # don't stringify the whole obj, allow individual keys, but make them all strings to avoid mapping clashes
        msg.params = {}
        for p of @params
          msg.params[p] = if typeof @params[p] is 'string' then @params[p] else JSON.stringify @params[p]
      try msg.apikey = @apikey? # only record if apikey was provided or not
      try msg.user = @user._id if @user?._id?
      msg.unauthorised = true if @unauthorised

    else if typeof msg is 'object' and msg.res and msg.args # this indicates the fn had _diff true
      try # find a previous log for the same thing and if it's different add a diff: true to the log of this one. Or diff: false if same, to track that it was diffed
        prevs = await @index 'logs', 'args:"' + msg.args + '"' # TODO what if it was a diff on a main log event though? do all log events have child log events now? check. and check what args/params should be compared for diff
        prev = prevs.hits.hits[0]._source
        msg.diff = if msg.checksum and prev.checksum then (msg.checksum isnt prev.checksum) else (msg.res isnt prev.res)
        # if msg.diff, send an email alert? Or have schedule pick up on those later?

    if store
      if not msg.logs
        msg.logs = []
        if Array.isArray(this?._logs) and @_logs.length
          for l in @_logs
            #msg.msg ?= l.msg
            msg.alert ?= l.alert if l.alert
            msg.notify ?= l.notify if l.notify
            msg.logs.push l
      msg.createdAt = new Date() #Date.now()
      msg.name ?= S.name
      msg.version ?= S.version
      msg.base = @base
      msg.domain = @domain if @domain
      msg.bg = true if @S.bg is true
      msg.system = true if @system is true
      msg.scheduled = true if @scheduled is true
      try
        msg.started = @started
        msg.took = Date.now() - @started
      msg._id = @rid
      if @S.index?.url?
        if @S.bg is true
          _bg_log_batch.push msg
          if (typeof @S.log is 'object' and @S.log.batch is false) or _bg_log_batch.length > 300 or _bg_last_log_batch is false or Date.now() > (_bg_last_log_batch + 30000)
            _save_batch()
        else if typeof @S.bg isnt 'string' or (typeof @S.log is 'object' and @S.log.batch is false)
          _bg_log_batch.push msg
          @waitUntil _save_batch()
        else
          @waitUntil @fetch @S.bg + '/log', body: msg
      else
        try
          @kv 'logs/' + msg._id, msg
        catch
          console.log 'Logging unable to save to kv or index'
          consolg.log msg
    else
      @_logs.push msg
  else if @S.dev and @S.bg is true
    console.log 'NOT logging', msg

  return true

P.log._hide = true

P.logs = _index: true, _hide: true, _auth: 'system'


# a user should be able to set a list of endpoints they want to receive notifications for
# could also wildcard* match
# note if there are lots of notifications, may need to group them
# user won't need auth for the endpoint because it won't give any info about the result - just that it happened?
# or if results are wanted, auth for the endpoint would be necessary
# notifications from this will go to a google chat bot webhook
# notifications will be triggered by log analysis, a scheduled job will need to check through them

'''
P.log.monitor = (opts) ->
  opts ?= @params
  if (opts.email or opts.chat) and opts.q
    opts.q = JSON.stringify(opts.q) if typeof opts.q isnt 'string'
    opts.frequency ?= 60
    # also can provide an opts.name as a nice name for the monitor instead if just the query
    return opts
  return
P.log.monitor = _index: true
P.log.monitor._schedule = () ->
  notify = {}
  chat = []
  counter = 0
  await @index.each 'log_monitor', '*', (rec) ->
    if not rec.notified or rec.notified + (rec.frequency * 60000) < @started
      rec.notified = @started
      @waitUntil @index 'log_monitor/' + rec._id, @copy rec
      q = if typeof rec.q is 'string' and rec.q.startsWith('{') then JSON.parse(rec.q) else rec.q
      q = await @index.translate q, { newest: true, restrict: [{query_string: {query: 'createdAt:>' + (@started - (rec.frequency * 60000))}}]}
      count = await @index.count 'logs', undefined, q
      if count
        counter += count
        rec.dq = q
        rec.count = count
        if rec.email
          notify.email ?= []
          notify.email.push rec
        if rec.chat
          chat.push rec

  for e of notify
    txt = ''
    for n in notify[e]
      txt += 'https://bg' + (if @S.dev then 'b' else '') + '.lvatn.com/log?q=' + JSON.stringify(n.dq) + '\n\n'
    @waitUntil @mail.send
      to: notify[e].email
      subject: notify[e].length + ' of your monitors have ' + rec.count + ' new alerts'
      text: txt
  
  if chat.length
    txt = chat.length + ' monitor notifications:'
    for c in chat
      txt += '\nhttps://bg' + (if @S.dev then 'b' else '') + '.lvatn.com/log?q=' + JSON.stringify(c.dq)
    @waitUntil @src.google.chat txt
  
  return counter
'''

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
