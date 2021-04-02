
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
  # also takes opts.attachments, but not required. Should be a list of objects
  # how do attachments work if not on mail_url, can they be sent by API?
  # https://github.com/nodemailer/mailcomposer/blob/v4.0.1/README.md#attachments
  # could use mailgun-js, but prefer to just send direct to API

  ms = if (opts.svc or opts.service) and @S.svc[opts.svc ? opts.service]?.mail? then @S.svc[opts.svc ? opts.service].mail else (this?.S?.mail ? S.mail)
  opts.from ?= ms.from
  opts.to ?= ms.to
  delete opts.svc

  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages'
  opts.to = opts.to.join(',') if Array.isArray opts.to
  f = this?.fetch ? P.fetch
  fo = await @form opts
  return await f url, {method: 'POST', form: fo, auth:'api:'+ms.apikey}

P.mail.validate = (e, apikey) ->
  apikey ?= S.mail?.pubkey
  e ?= this?.params?.email
  if typeof e is 'string' and typeof apikey is 'string'
    # also add a simple regex validator if mailgun validation is not available - and cache the validations
    f = this?.fetch ? P.fetch
    return await f 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e) + '&api_key=' + apikey


