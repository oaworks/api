P.bug = () ->
  if @params.contact # verify humanity
    return ''
  else
    whoto = ['help@oa.works']
    text = ''
    for k of @params
      text += k + ': ' + JSON.stringify(@params[k], undefined, 2) + '\n\n'
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
      whoto.push 'help@openaccessbutton.org'
    @waitUntil @mail
      service: 'openaccessbutton'
      from: 'help@openaccessbutton.org'
      to: whoto
      subject: subject
      text: text
    lc = (if @S.dev then 'https://dev.openaccessbutton.org' else 'https://openaccessbutton.org') + '/feedback#defaultthanks'
    return
      status: 302
      headers: 'Content-Type': 'text/plain', 'Location': lc
      body: lc
