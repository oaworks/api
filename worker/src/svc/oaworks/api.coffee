
try
  S.svc.oaworks = JSON.parse SECRETS_OAWORKS
catch
  S.svc.oaworks = {}
  
P.svc.oaworks = () ->
  if JSON.stringify(@params) isnt '{}'
    return status: 404
  else
    rts = await @subroutes 'svc.oaworks'
    rts.splice(rts.indexOf(hd), 1) for hd in ['bug', 'blacklist', 'deposits', 'journal', 'journal/load']
    return
      name: 'OA.Works Paradigm API'
      version: @S.version
      base: if @S.dev then @base else undefined
      built: if @S.dev then @S.built else undefined
      user: if @user?.email then @user.email else undefined
      routes: rts

P.svc.oaworks.templates = _key: 'name', _sheet: '16Qm8n3Rmx3QyttFpSGj81_7T6ehfLAtYRSvmDf3pAzg/1', _hide: true

P.svc.oaworks.bug = () ->
  if @params.contact # verify humanity
    return ''
  else
    whoto = ['help@oa.works']
    text = ''
    for k of @params
      text += k + ': ' + JSON.stringify(@params[k], undefined, 2) + '\n\n'
    text = await @tdm.clean text
    subject = '[OAB forms]'
    if @params?.form is 'uninstall' # wrong bug general other
      subject += ' Uninstall notice'
    else if @params?.form is 'wrong'
      subject += ' Wrong article'
    else if @params?.form is 'bug'
      subject += ' Bug'
    else if @params?.form is 'general'
      subject += ' General'
    else
      subject += ' Other'
    subject += ' ' + Date.now()
    if @params?.form in ['wrong','uninstall']
      whoto.push 'natalia@oa.works'
    @waitUntil @mail
      service: 'openaccessbutton'
      from: 'help@oa.works'
      to: whoto
      subject: subject
      text: text
    lc = (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
    return
      status: 302
      headers: 'Content-Type': 'text/plain', 'Location': lc
      body: lc

P.svc.oaworks.blacklist = (url) ->
  url ?= @params.url
  url = url.toString() if typeof url is 'number'
  return false if url? and (url.length < 4 or url.indexOf('.') is -1)
  blacklist = []
  blacklist.push(i.url.toLowerCase()) for i in await @src.google.sheets @S.svc.oaworks?.google?.sheets?.blacklist
  if url
    if not url.startsWith('http') and url.includes ' '
      return false # sometimes things like article titles get sent here, no point checking them on the blacklist
    else
      for b in blacklist
        return true if url.includes b.toLowerCase()
      return false
  else
    return blacklist
