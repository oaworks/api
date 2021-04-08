
import { customAlphabet } from 'nanoid'

P.uid = (r) ->
  r ?= if @fn is 'uid' then (this?.params?.len ? this?.params?.length ? this?.params?.size ? this?.params?.uid ? 21) else 21
  if typeof r is 'string'
    rs = parseInt r
    r = if isNaN(rs) then undefined else rs
  # have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  # are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  # will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  # without uppercases it's only a 1% chance if generating 100) IDs per second for 131000 years.
  nanoid = customAlphabet (this?.params?.alphabet ? '0123456789abcdefghijklmnopqrstuvwxyz'), r
  return nanoid()
P.uid._cache = false

P.hash = (content) ->
  try content ?= @params.hash ? @params.content ? @body ? @params.q ? @params
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

P.sleep = (ms) -> # await this when calling it to actually wait
  try ms ?= @params.ms
  return new Promise (resolve) => setTimeout resolve, ms ? 1000

P._timeout = (ms, fn) -> # where fn is a promise-able function that has been called
  # so call this like res = await @_timeout 5000, @fetch url
  return new Promise (resolve, reject) =>
    timer = setTimeout () =>
      reject new Error 'TIMEOUT' # should this error or just return undefined?
    , ms
    promise
      .then value =>
        clearTimeout timer
        resolve value
      .catch reason =>
        clearTimeout timer
        reject reason

P.form = (params) ->
  # return params object x-www-form-urlencoded
  params ?= @params
  po = ''
  for p of params
    po += '&' if po isnt ''
    for ppt in (if Array.isArray(params[p]) then params[p] else [params[p]])
      if ppt?
        po += '&' if not po.endsWith '&'
        po += p + '=' + encodeURIComponent (if typeof ppt is 'object' then JSON.stringify(ppt) else ppt)
  return po

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
  text = await _decode(content).replace(/\n/g,'')
  for c in [{bad: '‘', good: "'"}, {bad: '’', good: "'"}, {bad: '´', good: "'"}, {bad: '“', good: '"'}, {bad: '”', good: '"'}, {bad: '–', good: '-'}, {bad: '-', good: '-'}]
    re = new RegExp c.bad, 'g'
    text = text.replace re, c.good
  return text

P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

P.keys = (obj) ->
  try obj ?= @params
  keys = []
  for k of obj ? {}
    keys.push(k) if obj[k]? and k not in keys
  return keys

P.dot = (obj, key) ->
  # TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if typeof obj is 'string' and typeof key is 'object'
    st = obj
    obj = key
    key = st
  if not obj? and this?.params?.key?
    obj = @copy @params
    key = obj.key
  key = key.split('.') if typeof key is 'string'
  try
    res = obj
    res = res[k] for k in key
    return res
  catch
    return undefined

P.flatten = (obj) ->
  obj ?= @params
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
            await _flatten v[n], pk + '.' + n
        else
          res[pk] = v.join(', ')
      else
        await _flatten v, pk
  if Array.isArray obj
    results = []
    for d in data
      res = {}
      results.push await _flatten d
    return results
  else
    await _flatten obj
    return res

P.template = (content, vars) ->
  content ?= @params.content ? @params.template ? @body
  vars ?= @params
  if @params.url or content.startsWith 'http'
    content = await @fetch @params.url ? content
  if content.indexOf(' ') is -1 and content.indexOf('.') isnt -1 and content.length < 100
    try
      cs = await @_templates content
      content = cs.content
  ret = {}
  _rv = (obj, pre='') ->
    for o of obj
      ov = if pre then pre + '.' + o else o
      if typeof obj[o] is 'object' and not Array.isArray obj[o]
        _rv obj[o], pre + (if pre is '' then '' else '.') + o
      else if content.toLowerCase().indexOf('{{'+ov+'}}') isnt -1
        rg = new RegExp '{{'+ov+'}}', 'gi'
        content = content.replace rg, (if Array.isArray(obj[o]) then obj[o].join(', ') else (if typeof obj[o] is 'string' then obj[o] else (if obj[o] is true then 'Yes' else (if obj[o] is false then 'No' else ''))))
  _rv vars # replace all vars that are in the content
  kg = new RegExp '{{.*?}}', 'gi'
  if content.indexOf('{{') isnt -1 # retrieve any vars provided IN the content (e.g. a content template can specify a subject for an email to use)
    vs = ['subject','from','to','cc','bcc']
    # the could be vars in content that themselves contain vars, e.g {{subject I am the subject about {{id}} yes I am}}
    # and some of those vars may fail to get filled in. So define the list of possible vars names THEN go through the content with them
    for cp in content.toLowerCase().split '{{'
      pcp = cp.split('{{')[0].split('}}')[0].split(' ')[0]
      vs.push(pcp) if pcp not in vs
    for k in vs
      key = if content.toLowerCase().indexOf('{{'+k) isnt -1 then k else undefined
      if key
        keyu = if content.indexOf('{{'+key.toUpperCase()) isnt -1 then key.toUpperCase() else key
        val = content.split('{{'+keyu)[1]
        val = val.replace(kg,'') if val.split('}}')[0].indexOf('{{') # remove any vars present inside this one that were not able to have their values replaced
        val = val.split('}}')[0].trim()
        ret[key] = val if val
        kkg = new RegExp('{{'+keyu+'.*?}}','gi')
        content = content.replace(kkg,'')
  content = content.replace(kg, '') if content.indexOf('{{') isnt -1 # remove any outstanding vars in content that could not be replaced by provided vars
  ret.content = content
  # TODO consider if worth putting markdown formatting back in here, and how big a markdown parser is
  return ret # an obj of the content plus any vars found within the template

P._templates = _index: true # an index to store templates in - although generally should be handled at the individual function/service level



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


