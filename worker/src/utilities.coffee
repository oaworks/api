
import { customAlphabet } from 'nanoid'

P.uid = (r) ->
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 100) IDs per second for 131000 years.
  nanoid = customAlphabet (@params.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz-'), @params.len ? @params.length ? @params.size ? @params.uid ? 21
  return nanoid()

P.uid._cache = false

P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

P.keys = (obj) ->
  try obj ?= @params
  keys = []
  for k of obj ? {}
    keys.push(k) if obj[k]? and k not in keys
  return keys

P.sleep = (ms) -> # await this when calling it to actually wait
  try ms ?= @params.ms
  return new Promise (resolve) => setTimeout resolve, ms ? 1000

P.hash = (msg) ->
  try msg ?= @params.hash ? @request.body ? @params.q ? @params
  msg = JSON.stringify(msg) if typeof msg isnt 'string'
  msg = new TextEncoder().encode msg
  buf = await crypto.subtle.digest "SHA-256", msg 
  arr = new Uint8Array buf
  parts = []
  for b in arr
    parts.push ('00' + b.toString(16)).slice(-2)
  return parts.join ''
# the above works on CF worker, but crypto.subtle probably needs to be replaced with standard crypto module on backend
# the below is a possible example, but note will need to use same params that generate the same result
'''P.hash = (str, lowercase=false, uri=true, encoding='utf8', digest) -> # alternatively base64, but can cause problems if later used in URLs
  str = str.toLowerCase() if lowercase is true
  str = encodeURIComponent(str) if uri is true
  hash = crypto.createHash('md5').update(str, encoding)
  return if digest is 'hex' then hash.digest('hex') else hash.digest('base64').replace(/\//g,'_').replace(/\+/g,'-')
'''

P.dot = (obj, key) ->
  # TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if typeof obj is 'string' and typeof key is 'object'
    st = obj
    obj = key
    key = st
  obj = @copy(obj) if obj?
  if not obj? and this?.params?.key?
    obj = @copy @params
    key = obj.key
    delete obj.key
  key = key.split('.') if typeof key is 'string'
  obj = obj[k] for k in key
  return obj


'''
P.retry = (fn, params=[], opts={}) ->
  # params should be a list of params for the fn
  params = [params] if not Array.isArray params
  opts.retry ?= 3
  opts.pause ?= 500
  opts.increment ?= true
  # can provide a function in opts.check to check the result each time, and an opts.timeout to timeout each loop

  while opts.retry > 0
    res = undefined
    _wrap = () ->
      try
        res = await fn.apply this, params
    if typeof opts.timeout is 'number'
      await Promise.race [_wrap.call(this), P.sleep(opts.timeout)]
    else
      _wrap.call this
    if typeof opts.check is 'function'
      retry = await opts.check res, retry
      if retry is true
        return res
      else if retry is false
        retry -= 1
      else if typeof retry isnt 'number'
        retry = 0
    else if res? and res isnt false
      return res
    else
      retry -= 1

    if typeof opts.pause is 'number' and opts.pause isnt 0
      await P.sleep opts.pause
      if opts.increment is true
        opts.pause = opts.pause * 2
      else if typeof opts.increment is 'number'
        opts.pause += opts.increment
    
  return undefined
'''


'''
# see https://github.com/arlac77/fetch-rate-limit-util/blob/master/src/rate-limit-util.mjs
MIN_WAIT_MSECS = 1000 # wait at least this long
MAX_RETRIES = 5 # only retry max this many times

/**
 * @param {Integer} millisecondsToWait
 * @param {Integer} rateLimitRemaining parsed from "x-ratelimit-remaining" header
 * @param {Integer} nthTry how often have we retried the request already
 * @param {Object} response as returned from fetch
 * @return {Integer} milliseconds to wait for next try or < 0 to deliver current response
 */
defaultWaitDecide = (millisecondsToWait, rateLimitRemaining, nthTry, response) ->
  return if nthTry > MAX_RETRIES then -1 else millisecondsToWait + MIN_WAIT_MSECS

rateLimitHandler = (fetcher, waitDecide = defaultWaitDecide) ->
  i = 0
  while true
    response = await fetcher()

    switch (response.status) ->
      default:
        return response

      case 403:
      case 429:
        # this differs by API we're hitting, example was for github. 
        # It's the timestamp of when the rate limit window would reset, generalise this
        rateLimitReset = parseInt response.headers.get "x-ratelimit-reset"

        millisecondsToWait = if isNaN(rateLimitReset) then 0 else new Date(rateLimitReset * 1000).getTime() - Date.now()

        millisecondsToWait = waitDecide(millisecondsToWait, parseInt(response.headers.get("x-ratelimit-remaining")), i, response)
        if millisecondsToWait <= 0
          return response
        else
          await new Promise resolve => setTimeout resolve, millisecondsToWait
    i++
'''



'''
P.decode = (content) ->
  _decode = (content) ->
    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g
    translate = {
      "nbsp":" ",
      "amp" : "&",
      "quot": "\"",
      "lt"  : "<",
      "gt"  : ">"
    }
    return content.replace(translator, ((match, entity) ->
      return translate[entity]
    )).replace(/&#(\d+);/gi, ((match, numStr) ->
      num = parseInt(numStr, 10)
      return String.fromCharCode(num)
    ))
  return _decode(content).replace(/\n/g,'')

P.str = (r) ->
  str = ''
  _str = (rp) ->
    if typeof rp is 'string'
      return rp
    else if rp is true
      return 'true'
    else if rp is false
      return 'false'
    else if typeof rp is 'function'
      return rp.toString()
    else if Array.isArray rp
      cr = []
      cr.push(_str a) for a in rp
      return JSON.stringify cr.sort()
    else if typeof rp is 'object'
      nob = ''
      keys = []
      keys.push(k) for k of rp
      for k in keys.sort()
        if nob.length is 0
          nob = '{'
        else
          nob += ','
        nob += '"' + o + '":"' + _str(rp[o]) + '"' for o of rp
      return nob + '}'
  str += _str r
  return str

P.flatten = (data) ->
  res = {}
  _flatten = (obj, key) ->
    for k of obj
      pk = if key then key + '.' + k else k
      v = obj[k]
      if typeof v is 'string'
        res[pk] = v
      else if Array.isArray v
        if typeof v[0] is 'object'
          for n of v
            _flatten v[n], pk + '.' + n
        else
          res[pk] = v.join(', ')
      else
        _flatten v, pk
  if Array.isArray data
    results = []
    for d in data
      res = {}
      results.push _flatten d
    return results
  else
    _flatten data
    return res

'''
