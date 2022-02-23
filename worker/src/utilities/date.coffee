
P.date = (rt, timed, secs=true, ms=true) ->
  rt ?= @params.date ? Date.now()
  timed ?= @params.time
  if typeof rt is 'number' or (typeof rt is 'string' and rt.indexOf(' ') is -1 and rt.indexOf('/') is -1 and rt.indexOf('-') is -1 and rt.length > 8 and rt.indexOf('T') is -1)
    try
      ret = new Date parseInt rt
      ret = ret.toISOString()
      if timed
        if not secs
          ret = ret.split(':').slice(0,-1).join(':').replace('T', ' ')
        else if not ms
          ret = ret.split('.')[0].replace('T', ' ')
      else
        ret = ret.split('T')[0]
      return ret
  try
    rt = rt.toString() if typeof rt is 'number'
    rt = rt[0] if Array.isArray(rt) and rt.length is 1 and Array.isArray rt[0]
    if typeof rt isnt 'string'
      try
        for k of rt
          rt[k] = '01' if typeof rt[k] not in ['number', 'string']
        rt = rt.join '-'
    rt = decodeURIComponent rt
    rt = rt.split('T')[0] if rt.indexOf('T') isnt -1
    rt = rt.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace /-(\d)$/, "-0$1"
    rt += '-01' if rt.indexOf('-') is -1
    pts = rt.split '-'
    if pts.length isnt 3
      rt += '-01' 
      pts = rt.split '-'
    rt = undefined if pts.length isnt 3
    rt = pts.reverse().join('-') if pts[0].length < pts[2].length
    return rt
  catch
    return
P.date._cache = false

P.datetime = (secs, ms) -> return @date @params.datetime, (@params.time ? true), (secs ? @params.secs ? @params.s), (ms ? @params.ms)
P.datetime._cache = false
P.epoch = (epoch) ->
  epoch ?= @params.epoch
  epoch = epoch.toString() if typeof epoch is 'number'
  if not epoch
    return Date.now()
  else if epoch.startsWith('+') or epoch.startsWith('-') or (epoch.split('+').length is 2 and epoch.split('+')[0].length > 4) or (epoch.split('-').length is 2 and epoch.split('-')[0].length > 4)
    epoch = Date.now() + epoch if epoch.startsWith('+') or epoch.startsWith '-'
    if epoch.includes '+'
      [epoch, add] = epoch.replace('/', '').split '+'
      return (parseInt(epoch) + parseInt add).toString()
    else if epoch.includes '-'
      [epoch, subtract] = epoch.replace('/', '').split '-'
      return (parseInt(epoch) - parseInt subtract).toString()
  else if epoch.length > 8 and not epoch.includes('-') and not isNaN parseInt epoch
    return @date epoch, @params.time ? true
  else
    epoch += '-01' if epoch.length is 4
    epoch += '-01' if epoch.split('-').length < 3
    epoch += 'T' if epoch.indexOf('T') is -1
    epoch += '00:00' if epoch.indexOf(':') is -1
    epoch += ':00' if epoch.split(':').length < 3
    epoch += '.' if epoch.indexOf('.') is -1
    [start, end] = epoch.split('.')
    end = end.replace('Z','').replace('z','')
    end += '0' while end.length < 3
    end += 'Z' if end.indexOf('Z') is -1
    return new Date(start + '.' + end).valueOf()
P.epoch._cache = false

