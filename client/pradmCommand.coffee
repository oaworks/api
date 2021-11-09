
P.command = (opts) ->
  opts ?= {}
  opts.api ?= ''
  
  commands = []
  P.ajax opts.api + '/subroutes', success: (res) -> commands = res

  ui = '<div id="results"></div>'
  ui += '<textarea style="border: none; resize: none;" id="command" placeholder=">"></textarea>'
  ui += '<div id="suggestions"></div>'
  P.css 'body', 'height', '100%'
  P.append 'body', ui
  P.focus '#command'
  
  idx = -1
  history = []

  P.on 'keyup', '#command', (e) ->
    P.html '#suggestions', ''
    if e.keyCode in [38, 40]
      idx += if e.keyCode is 38 and idx > 0 then -1 else if e.keyCode is 40 and idx < history.length then 1 else 0
      P.set '#command', history[idx] ? ''
    else
      command = P.val('#command').replace '\n', ''
      if command.includes ' = /'
        [key, command] = command.split ' = /'
        command = '/' + command
      if e.keyCode is 13
        history.push(command) if history[history.length-1] isnt command
        idx = history.length
        P.set '#command', ''
        success = (res) ->
          window[key] = res if key and res?
          P.append '#results', '<pre style="color: black; background: transparent; border: none; border-bottom: 1px dotted #ccc;  margin: 0px; padding: 4px;">' + JSON.stringify(res, '', 2) + '</pre>'
          window.scrollTo 0, document.body.scrollHeight
        if command is 'clear'
          P.html '#results', ''
        else if command.startsWith '/'
          P.ajax opts.api + command, success: success
        else
          success Function('return (' + command + ')')()
      else if command and command.startsWith '/'
        command = command.replace '/', ''
        for c in commands
          P.append('#suggestions', c + '<br>') if c.startsWith command

P.afterLogin = () ->
  P.attr '#command', 'placeholder', P.account.email.split('@')[0].split('.')[0] + ' >'
