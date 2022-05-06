
import { customAlphabet } from 'nanoid'

P.uid = (length) ->
  length ?= if @fn is 'uid' then (this?.params?.len ? this?.params?.length ? this?.params?.size ? this?.params?.uid ? 21) else 21
  if typeof length is 'string'
    rs = parseInt length
    length = if isNaN(rs) then undefined else rs
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 1000 IDs per second for 131000 years.
  nanoid = customAlphabet (this?.params?.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz'), length
  return nanoid()
P.uid._cache = false

P.encrypt = (content) ->
  content ?= @params.encrypt ? @params.content ? @params.q ? @params ? @body
  try
    content = await @fetch(@params.url) if @params.url
  content = JSON.stringify(content) if typeof content isnt 'string'
  cipher = crypto.createCipheriv 'aes-256-ctr', @S.encrypt.salt, @params.iv ? @S.encrypt.iv
  encrypted = Buffer.concat [cipher.update(content), cipher.final()]
  return encrypted.toString 'hex'
P.encrypt._cache = false
P.encrypt._bg = true # need to check but presumably createCipheriv and createDecipheriv won't be available on CF worker with crypto.subtle

P.decrypt = (content) ->
  content ?= @params.decrypt ? @params.content ? @params.q ? @params ? @body
  try
    content = await @fetch(@params.url) if @params.url
  if typeof content is 'object'
    iv = content.iv
    content = content.content
  else
    iv = @params.iv ? @S.encrypt.iv
  content = JSON.stringify(content) if typeof content isnt 'string'
  #decipher = crypto.createDecipheriv 'aes-256-ctr', @S.encrypt.salt, iv
  #decrypted = Buffer.concat [decipher.update(content), decipher.final()]
  decipher = crypto.createDecipheriv 'aes-256-ctr', @S.encrypt.salt, iv
  decrypted = Buffer.concat [decipher.update(Buffer.from(content, 'hex')), decipher.final()]
  return decrypted.toString()
P.decrypt._cache = false
P.decrypt._bg = true
P.decrypt._auth = '@oa.works'

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
