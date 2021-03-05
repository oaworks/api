
P.mail = (opts) ->
  return {} if S.mail?.disabled
  
  if not opts? and (this?.params? or this?.opts?)
    opts = this?.params ? {}
    opts[o] = @params[o] for o of @params
    
  if not opts.text and not opts.html
    opts.text = opts.content ? opts.body ? ""
  delete opts.content

  try
    for s in ['subject', 'text', 'html', 'template']
      if opts[s]?
        for p of opts.params
          opts[s] = opts[s].replace('{{' + p.toUpperCase() + '}}', opts.params[p])
      # this should be stand-alone called method somewhere...
      # should be case insensitive, and remove multiples, not just first occurrence
      # and do a delete of any template values that could not be replaced

  # can also take opts.headers

  # also takes opts.attachments, but not required. Should be a list of objects as per
  # how do attachments work if not on mail_url, can they be sent by API?
  # https://github.com/nodemailer/mailcomposer/blob/v4.0.1/README.md#attachments

  ms = if opts.svc? and S.svc?[opts.svc]?.mail? then S.svc[opts.svc].mail else S.mail
  opts.from ?= ms.from
  opts.to ?= ms.to
  delete opts.svc
  delete opts.template # what to actually do with this now...
  delete opts.params

  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages'
  opts.to = opts.to.join(',') if Array.isArray opts.to
  f = this?.fetch ? P.fetch
  return await f url, {method: 'POST', body: opts, headers: {auth:'api:'+ms.apikey}}

P.mail.validate = (e, apikey) ->
  apikey ?= S.mail?.pubkey
  e ?= this?.params?.email
  if typeof e is 'string' and typeof apikey is 'string'
    # also add a simple regex validator if mailgun validation is not available - and cache the validations
    f = this?.fetch ? P.fetch
    return await f 'https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e.params.email) + '&api_key=' + apikey




