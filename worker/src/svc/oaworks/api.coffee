
try
  S.svc.oaworks = JSON.parse SECRETS_OAWORKS
catch
  S.svc.oaworks = {}
  
P.svc.oaworks = () ->
  return name: 'OA.works API'


# email templates - convert to a read from a sheet instead of currently in the repo
# oab status and stats
# make all request admin via sheet somehow


'''
P.svc.oaworks.bug = () ->
  if (@body?.contact? and @body.contact.length) or (@body?.email? and @svc.oaworks.validate(@body.email) isnt true)
    return ''
  else
    whoto = ['help@openaccessbutton.org']
    text = ''
    for k of @body
      text += k + ': ' + JSON.stringify(@body[k],undefined,2) + '\n\n'
    text = @tdm.clean text
    subject = '[OAB forms]'
    if @body?.form is 'uninstall' # wrong bug general other
      subject += ' Uninstall notice'
    else if @body?.form is 'wrong'
      subject += ' Wrong article'
    else if @body?.form is 'bug'
      subject += ' Bug'
    else if @body?.form is 'general'
      subject += ' General'
    else
      subject += ' Other'
    subject += ' ' + Date.now()
    try
      if @body?.form in ['wrong','uninstall']
        whoto.push 'natalia.norori@openaccessbutton.org'
    @mail {
      service: 'openaccessbutton',
      from: 'natalia.norori@openaccessbutton.org',
      to: whoto,
      subject: subject,
      text: text
    }
    return {
      status: 302,
      headers: {
        'Content-Type': 'text/plain',
        'Location': (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
      },
      body: 'Location: ' + (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
    }


P.svc.oaworks.blacklist = (url) ->
  url = url.toString() if typeof url is 'number'
  return false if url? and (url.length < 4 or url.indexOf('.') is -1)
  bl = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.blacklist, stale
  blacklist = []
  blacklist.push(i.url) for i in bl
  if url
    if url.indexOf('http') isnt 0 and url.indexOf(' ') isnt -1
      return false # sometimes article titles get sent here, no point checking them on the blacklist
    else
      for b in blacklist
        return true if url.indexOf(b) isnt -1
      return false
  else
    return blacklist


API.service.oab.validate = (email, domain, verify=true) ->
  bad = ['eric@talkwithcustomer.com']
  if typeof email isnt 'string' or email.indexOf(',') isnt -1 or email in bad
    return false
  else if email.indexOf('@openaccessbutton.org') isnt -1 or email.indexOf('@email.ghostinspector.com') isnt -1 #or email in []
    return true
  else
    v = @mail.validate email, @S.svc.oaworks.mail.pubkey
    if v.is_valid and (not verify or v.mailbox_verification in [true,'true'])
      return true
    else if v.did_you_mean
      return v.did_you_mean
    else
      return false


# LIVE: https://docs.google.com/spreadsheets/d/1Te9zcQtBLq2Vx81JUE9R42fjptFGXY6jybXBCt85dcs/edit#gid=0
# Develop: https://docs.google.com/spreadsheets/d/1AaY7hS0D9jtLgVsGO4cJuLn_-CzNQg0yCreC3PP3UU0/edit#gid=0
P.svc.oaworks.redirect = (url) ->
  return false if await @svc.oaworks.blacklist(url) is true # ignore anything on the usual URL blacklist
  list = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.redirect, 360000
  for listing in list
    if listing.redirect and url.replace('http://','').replace('https://','').split('#')[0] is listing.redirect.replace('http://','').replace('https://','').split('#')[0]
      # we have an exact alternative for this url
      return listing.redirect
    else if typeof url is 'string' and url.indexOf(listing.domain.replace('http://','').replace('https://','').split('/')[0]) isnt -1
      url = url.replace('http://','https://') if listing.domain.indexOf('https://') is 0
      listing.domain = listing.domain.replace('http://','https://') if url.indexOf('https://') is 0
      if (listing.fulltext and listing.splash and listing.identifier) or listing.element
        source = url
        if listing.fulltext
          # switch the url by comparing the fulltext and splash examples, and converting the url in the same way
          parts = listing.splash.split listing.identifier
          if url.indexOf(parts[0]) is 0 # can only successfully replace if the incoming url starts with the same as the start of the splash url
            diff = url.replace parts[0], ''
            diff = diff.replace(parts[1],'') if parts.length > 1
            url = listing.fulltext.replace listing.identifier, diff
        else if listing.element and url.indexOf('.pdf') is -1
          try
            content = await @fetch url # should really be a puppeteer render
            url = content.toLowerCase().split(listing.element.toLowerCase())[1].split('"')[0].split("'")[0].split('>')[0]
        return false if (not url? or url.length < 6 or url is source) and listing.blacklist is "yes"
      else if listing.loginwall and url.indexOf(listing.loginwall.replace('http://','').replace('https://','')) isnt -1
        # this url is on the login wall of the repo in question, so it is no use
        return false
      else if listing.blacklist is "yes"
        return false
  if typeof url is 'string'
    # some URLs can be confirmed as resolvable but we also hit a captcha response and end up serving that to the user
    # we introduced this because of issue https://github.com/OAButton/discussion/issues/1257
    # and for example https://www.tandfonline.com/doi/pdf/10.1080/17521740701702115?needAccess=true
    # ends up as https://www.tandfonline.com/action/captchaChallenge?redirectUri=%2Fdoi%2Fpdf%2F10.1080%2F17521740701702115%3FneedAccess%3Dtrue
    for avoid in ['captcha','challenge']
      return undefined if url.toLowerCase().indexOf(avoid) isnt -1
  return url
'''
