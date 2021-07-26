
# write examples of how to do various things here

S.example ?= {}
S.example.example = 3
P.example = ->
  res = name: S.name, version: S.version, built: S.built
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  if S.dev
    try res.headers ?= @headers
    try res.parts ?= @parts
    try res.params ?= @params
    try res.opts ?= @opts
  return res
P.example._hides = true

P.example.idx = _index: true

P.example.restricted = () ->
  return hello: @user._id
P.example.restricted._auth = true

P.example.deep = ->
  res = {example: 'deep', deeper: await @example.deep.deeper()}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  return res

P.example.deep.deeper = ->
  res = {hello: 'deeper'}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  try res.deepest = await @example.deep.deeper.deepest()
  return res

P.example.deep.deeper.deepest = ->
  res = {hello: 'deepest'}
  try res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0] #.split(" ")[5].replace('FetchEvent.e','').replace(/\./,'')
  try res.fn = @fn
  return res

P.example.inbetween = ->
  # call a url like example/thing/inbetween and this should give you thing
  console.log typeof @params.example
  return @params