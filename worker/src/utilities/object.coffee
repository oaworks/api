
P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

'''P.dot = (obj, key) ->
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
    return'''

P.dot = (o, k, v, d) ->
  if typeof k is 'string'
    return P.dot o, k.split('.'), v, d
  else if k.length is 1 and (v? or d?)
    if d?
      if o instanceof Array
        o.splice k[0], 1
      else
        delete o[k[0]]
      return true
    else
      o[k[0]] = v
      return true
  else if k.length is 0
    return o
  else
    if not o[k[0]]?
      if v?
        o[k[0]] = if typeof k[0] is 'number' or not isNaN(parseInt(k[0])) then [] else {}
        return P.dot o[k[0]], k.slice(1), v, d
      else
        return undefined
    else
      return P.dot o[k[0]], k.slice(1), v, d


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

P.keys = (obj) ->
  try obj ?= @params
  keys = []
  for k of obj ? {}
    keys.push(k) if obj[k]? and k not in keys
  return keys
