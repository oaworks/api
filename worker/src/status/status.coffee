
P.status = ->
  res = name: S.name, version: S.version, built: S.built
  for k in ['uid', 'rid', 'params', 'base', 'parts', 'opts', 'routes']
    try res[k] ?= @[k]
  res.bg = true if @S.bg is true
  res.kv = if typeof @S.kv is 'string' and global[@S.kv] then @S.kv else if typeof @S.kv is 'string' then @S.kv else false
  res.index = true if await @index ''
  if S.dev
    if @S.bg isnt true
      try res.request = @request
    for k in ['headers', 'cookie', 'user']
      try res[k] ?= @[k]
      
  # TODO if there are status endpoints further down the stack, call them all too if a certain param is passed
  # maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  # maybe some useful info from the recent logs too
  return res


