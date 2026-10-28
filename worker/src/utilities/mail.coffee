
try
  S.mail = JSON.parse SECRETS_MAIL
catch
  S.mail = {}


P.mail = (opts) ->
  return {} if S.mail?.disabled

  opts = {text: opts} if typeof opts is 'string'
  opts ?= @copy(this?.params) ? {}

  if opts.template
    parts = await @template opts.template, opts.vars ? opts.params ? opts
    opts[p] = parts[p] for p of parts
    delete opts.template
    delete opts.vars
    delete opts.params

  if not opts.text and not opts.html
    opts.text = opts.content ? opts.msg ? opts.body ? @body ? ''
    if typeof opts.text is 'object'
      try
        opts.text = await @convert.json2html opts.text
      catch
        opts.text = JSON.stringify opts.text
  delete opts.content
  delete opts.body
  opts.html = opts.text if not opts.html and typeof opts.text is 'string' and opts.text.indexOf('<') isnt -1 and opts.text.indexOf('>') isnt -1

  # can also take opts.headers
  # also takes opts.attachment, but not required. Should be a list of objects

  ms = if (opts.svc or opts.service) and @S.svc[opts.svc ? opts.service]?.mail? then @S.svc[opts.svc ? opts.service].mail else (this?.S?.mail ? S.mail)
  opts.from ?= ms.from
  opts.to ?= ms.to
  delete opts.svc

  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages'
  opts.to = opts.to.join(',') if Array.isArray opts.to
  if opts.to
    f = this?.fetch ? P.fetch
    pl = method: 'POST', auth:'api:' + ms.apikey
    for fa in ['file', 'files', 'attachment', 'attachments']
      if opts[fa]?
        pl[fa] = opts[fa]
        delete opts[fa]
    pl.form = opts
    return await f url, pl
  else
    console.log opts
    console.log 'NO ADDRESS TO EMAIL TO'
    return {}

P.mail._auth = 'system'

