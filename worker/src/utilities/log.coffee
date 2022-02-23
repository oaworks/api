
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

P.logs = _index: true, _auth: 'system'

