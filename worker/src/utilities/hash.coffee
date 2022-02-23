
P.hash = (content) ->
  content ?= @params.hash ? @params.content ? @params.q ? @params ? @body
  try
    content = await @fetch(@params.url) if @params.url
  content = JSON.stringify(content) if typeof content isnt 'string'
  try
    content = new TextEncoder().encode content
    buf = await crypto.subtle.digest "SHA-256", content
    arr = new Uint8Array buf
    parts = []
    for b in arr
      parts.push ('00' + b.toString(16)).slice(-2)
    return parts.join ''
  catch
    # the above works on CF worker, but crypto.subtle needs to be replaced with standard crypto module on backend
    # crypto is imported by the server-side main api file
    return crypto.createHash('sha256').update(content, 'utf8').digest 'hex' # md5 would be preferable but web crypto /subtle doesn't support md5

P.hashcode = (content) -> # java hash code style
  content ?= @params.hashcode ? @params.content ? @params.q ? @params ? @body
  content = JSON.stringify(content) if typeof content isnt 'string'
  hash = 0
  i = 0
  while i < content.length
    hash = ((hash<<5)-hash) + content.charCodeAt i
    hash &= hash
    i++
  return hash

P.hashhex = (content) ->
  content ?= @params.hashhex
  n = @hashcode content
  n = 0xFFFFFFFF + n + 1 if n < 0
  return n.toString 16

P.shorthash = (content, alphabet) -> # as learnt from something I once googled, but can't remember what
  content ?= @params.shorthash ? @params.content ? @params.q ? @params ? @body
  content = JSON.stringify(content) if typeof content isnt 'string'
  hash = @hashcode content
  if not alphabet
    alphabet = '0123456789abcdefghijklmnoqrstuvwxyz' # keep one char from the usable range to replace negative signs on hashcodes
    spare = 'p'
  else
    spare = alphabet.substring 0, 1
    alphabet = alphabet.replace spare, ''
  al = alphabet.length
  result = if hash < 0 then spare else ''
  hash = Math.abs hash
  while hash >= al
    result += alphabet[hash % al]
    hash = Math.floor hash / al
  return result + (if hash > 0 then alphabet[hash] else '')
