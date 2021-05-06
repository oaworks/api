
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
  #apikey ?= @S.mail?.pubkey
  e ?= this?.params?.email
  if typeof e is 'string' and e.length and (e.indexOf(' ') is -1 or (e.startsWith('"') and e.split('"@').length is 2))
    try
      if typeof apikey is 'string'
        v = await @fetch 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e) + '&api_key=' + apikey
        return v.did_you_mean ? v.is_valid

    #(?:[a-z0-9!#$%&amp;'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&amp;'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])
    ns = e.split '@'
    if ns.length is 2 and ns[0].length and ns[0].length < 65 and ((ns[0].startsWith('"') and ns[0].endsWith('"')) or (ns[0].indexOf(' ') is -1 and ns[0].indexOf(',') is -1 and ns[0].indexOf(':') is -1 and ns[0].indexOf(';') is -1))
      if ns[1].length and ns[1].indexOf(',') is -1 and ns[1].indexOf(' ') is -1
        nsp = ns[1].split '.'
        if nsp.length > 1 and (nsp.length isnt 2 or nsp[0] isnt 'example')
          return true

  return false