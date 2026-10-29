
P.copy = (obj) ->
  try obj ?= @params
  return JSON.parse JSON.stringify obj

P.copy._log = false

P.dot = (o, k, v, d, ae) ->
  if typeof k is 'string'
    return P.dot o, k.split('.'), v, d, ae
  else if k.length is 0
    return o
  else if k.length is 1 and (v? or d?)
    if d?
      if o instanceof Array
        o.splice k[0], 1
      else
        delete o[k[0]]
      return true
    else
      if ae and Array.isArray(o) and typeof k[0] isnt 'number' and isNaN parseInt k[0]
        o = [{}] if not o.length
        o[o.length-1][k[0]] = v
      else
        o[k[0]] = v
      return true
  else
    if not o[k[0]]?
      if v?
        o[k[0]] = if typeof k[0] is 'number' or not isNaN(parseInt(k[0])) then [] else {}
        return P.dot o[k[0]], k.slice(1), v, d, ae
      else if ae and Array.isArray(o) and o.length and oo = o[o.length-1] and typeof oo is 'object' and oo[k[0]]?
        return P.dot oo[k[0]], k.slice(1), v, d, ae
      else if Array.isArray(o) and o.length and typeof o[0] is 'object'
        return P.dot o.flatMap((x) -> if x[k[0]]? then x[k[0]] else []), k.slice(1), v, d, ae
      else
        return undefined
    else
      if ae and Array.isArray(o) and typeof k[0] isnt 'number' and isNaN(parseInt(k[0])) and o.length and typeof o[o.length-1] is 'object'
        o[o.length-1][k[0]] ?= {} if v?
        return P.dot o[o.length-1][k[0]], k.slice(1), v, d, ae
      else
        return P.dot o[k[0]], k.slice(1), v, d, ae
P.dot._log = false

P.flatten = (obj, arrayed) ->
  arrayed ?= @params.arrayed ? false
  if not obj?
    obj = @params
    delete obj.arrayed
  res = {}
  _flatten = (obj, key) ->
    if typeof obj isnt 'object'
      res = obj
    else
      for k of obj
        isnum = false
        try isnum = not isNaN parseInt k
        pk = if isnum and not arrayed then key else if key then key + '.' + k else k
        v = obj[k]
        if typeof v isnt 'object'
          if res[pk]?
            res[pk] = [res[pk]] if not Array.isArray res[pk]
            res[pk].push v
          else
            res[pk] = v
        else if Array.isArray v
          if typeof v[0] is 'object'
            for n of v
              await _flatten v[n], pk + (if arrayed then '.' + n else '')
          else
            res[pk] ?= [] #''
            res[pk] = [res[pk]] if not Array.isArray res[pk]
            res[pk].push(av) for av in v
        else
          await _flatten v, pk
  if Array.isArray obj
    results = []
    for d in obj
      res = {}
      await _flatten d
      results.push res
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
