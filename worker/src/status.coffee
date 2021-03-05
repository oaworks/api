
P.status = ->
  res = name: S.name, version: S.version, env: S.env, built: S.built
  if S.dev
    for k in ['id', 'request', 'params', 'parts', 'opts', 'headers', 'cookie', 'user', 'fn', 'routes']
      try res[k] ?= @[k]
  # add an uncached check that the backend is responding, and whether or not an index/kv is available, and whether on a worker or a backend
  # if index is available get some info about it - from index.status
  # if there are status endpoints further down the stack, call them all too if a certain param is passed
  # maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  # maybe some useful info from the recent logs too
  return res


