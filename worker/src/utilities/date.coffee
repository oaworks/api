
P.dateparts = (d) ->
  o = {}
  d ?= @params.dateparts ? o.date
  try
    if typeof d is 'object'
      o[p] = d[p] for p of d
      d = o.date ? ''
    else if not d?
      o[p] ?= @params[p] for p of params
      d = o.date ? ''
    # at least year must be present. year can be first or last or singular but not middle. 
    # If only one part assume year. If only two assume month and year.

    if typeof d is 'number' or (typeof d is 'string' and not d.includes(' ') and not d.includes('/') and not d.includes('-') and d.length > 8 and not d.includes('T'))
      d = await @date d
    d = d.split('T')[0] if d.includes('T') and d.includes '-'
    d = d.trim().toLowerCase().replace(', ', ' ').replace(' of ', '').replace('st ', ' ').replace('nd ', ' ').replace('rd ', ' ').replace('th ', ' ')
    # NOTE august could now be augu but going to reduce to first three chars anyway
    d = d.replace(/-/g, ' ').replace /\//g, ' '
    if d.includes ' ' # assume some kind of 1 xxx... xxxx format
      for p of parts = d.split ' '
        part = parts[p]
        if part.length >= 3 # month or full year
          if isNaN parseInt part
            o.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf part.toLowerCase().substr 0, 3
            o.month = if typeof o.month is 'number' and o.month >= 0 then o.month + 1 else ''
          else
            o.year = part
        else if parseInt(part) < 13 and (parts.length is 2 or (parts.length is 3 and p is '1'))
          o.month = part
        else if parts.length is 1
          o.year = part
        else
          o.day = part

    o.day = (o.day ? '01').toString()
    o.day = '0' + o.day if o.day.length is 1
    if typeof o.month is 'string' and o.month.length and isNaN parseInt o.month
      o.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf o.month.toLowerCase().substr 0, 3
      o.month = if typeof o.month is 'number' and o.month >= 0 then o.month + 1 else ''
    o.month = (o.month ? '01').toString()
    o.month = '0' + o.month if o.month.length is 1
    o.year = o.year.toString()
    o.year = (if parseInt(o.year) < 30 then '20' else '19' + o.year) if o.year.length is 2
    o.day = '30' if o.day is '31' and o.month in ['04', '06', '09', '11'] # for example pubmed xml was seen to have dates of 31st April, etc
    o.day = '28' if o.month is '02' and (o.day in ['30', '31'] or (o.day is '29' and parseInt(o.year) % 4))
    o.date = o.year + '-' + o.month + '-' + o.day # allow for formatting option to be passed in?
    try o.timestamp = await @epoch o.date
  return o
P.dateparts._cache = false

P.date = (rt, timed, secs=true, ms=true) ->
  rt ?= @params.date ? Date.now()
  timed ?= @params.time
  if typeof rt is 'number' or (typeof rt is 'string' and not rt.includes(' ') and not rt.includes('/') and not rt.includes('-') and rt.length > 8 and not rt.includes('T'))
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
    rt = rt.split('T')[0] if rt.includes 'T'
    rt = rt.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace /-(\d)$/, "-0$1"
    rt += '-01-01' if not rt.includes '-'
    rt += '-01' if rt.split('-').length isnt 3
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
  if typeof epoch is 'string' and epoch.includes '/'
    eps = epoch.split '/'
    eps.reverse() if eps.length is 3 and eps[2].length is 4
    epoch = eps.join '-'
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
    epoch += 'T' if not epoch.includes 'T'
    epoch += '00:00' if not epoch.includes ':'
    epoch += ':00' if epoch.split(':').length < 3
    epoch += '.' if not epoch.includes '.'
    [start, end] = epoch.split('.')
    end = end.replace('Z','').replace('z','')
    end += '0' while end.length < 3
    end += 'Z' if not end.includes 'Z'
    return new Date(start + '.' + end).valueOf()
P.epoch._cache = false

