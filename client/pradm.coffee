
P = (n) ->
  d = P[if n.startsWith('#') then 'gebi' else if n.startsWith('.') then 'gebc' else 'gebn'] n
  return if d? and (n.startsWith('#') or d.length isnt 0) then d else undefined

P.list = (els) ->
  els = P(els) if typeof els is 'string'
  els = [els] if els? and not Array.isArray(els) and not HTMLCollection.prototype.isPrototypeOf(els) and not NodeList.prototype.isPrototypeOf els
  return els ? []
P.each = (els, k) ->
  els = P(els) if typeof els is 'string'
  k(el) for el in P.list els

P.show = (els, h, a) ->
  P.each els, (el) -> 
    el.innerHTML = (if a then el.innerHTML else '') + h + (if a is false then el.innerHTML else '') if h
    w = P.get el, 'Pdisplay'
    w = 'block' if typeof w isnt 'string' or w is 'none' # TODO should be inline in which cases...
    el.style.display = w
P.hide = (els) ->
  P.each els, (el) -> 
    if el.style.display isnt 'none'
      P.set el, 'Pdisplay', el.style.display
    el.style.display = 'none'
P.focus = (els) -> P.each els, (el) -> el.focus()
P.get = (els, a) ->
  r = undefined
  P.each els, (el) ->
    if not r?
      if a?
        try r = el.getAttribute a
      else
        if el.getAttribute('type') in ['radio', 'checkbox']
          try r = P.checked el
        if not r? and el.getAttribute('type') not in ['radio', 'checkbox']
          try r = el.value
        r = undefined if typeof r is 'string' and not r.length
  return r
P.set = (els, a, v) -> 
  P.each els, (el) -> 
    if v?
      el.setAttribute a, v
    else if a is true
      P.check el
    else if a is false
      P.uncheck el
    else
      el.value = a
P.checked = (els) ->
  r = undefined
  P.each els, (el) ->
    if not r?
      if el instanceof HTMLInputElement
        if el.getAttribute('type') is 'checkbox'
          r = el.checked
        else if el.getAttribute('type') is 'radio'
          r = if el.checked then (el.value ? true) else false
      else
        r = false
  return r
P.check = (els) -> P.each els, (el) -> try el.checked = true # will work for radio buttons as well
P.uncheck = (els) -> P.each els, (el) -> try el.checked = false

P.html = (els, h, a, s) ->
  r = ''
  P.each els, (el) -> 
    if typeof h is 'string'
      el.innerHTML = (if a then el.innerHTML else '') + h + (if a is false then el.innerHTML else '')
    r += el.innerHTML
    P.show(el) if s
  return r

P.classes = (els, cls, d) -> 
  r = []
  cls = cls.replace(/^\./, '') if cls
  P.each els, (el) -> 
    c = el.getAttribute('class') ? ''
    if cls
      if d?
        c = c.replace(cls, '').trim().replace /\s\s/g, ' '
      else if c.indexOf(cls) is -1
        c += (if c.length then ' ' else '') + cls
      el.setAttribute 'class', c
    for cc in c.split ' '
      r.push(cc) if cc not in r
  return r





P.ajax = (url, opts) ->
  if typeof url is 'object'
    opts = url
    url = undefined
  url ?= opts.url ? ''
  if url is '' or (url.startsWith('/') and not url.startsWith '//')
    url = '//' + window.location.host + url

  opts ?= {}
  opts.headers ?= {}
  opts.method = opts.method.toUpperCase() if typeof opts.method is 'string'
  if opts.data?
    opts.method = 'POST'
    if typeof opts.data is 'object' and typeof opts.data.append isnt 'function' # a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify opts.data
      opts.headers['Content-type'] ?= 'application/json'
    #url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching?

  try
    if not opts.headers.Authorization and not opts.headers.authorization and not opts.headers.apikey and not opts.headers['x-apikey']
      if opts.username and opts.password
        opts.headers.Authorization ?= "Basic " + btoa(opts.username + ":" + opts.password)
      else if opts.apikey or opts['x-apikey']
        opts.headers.apikey = opts.apikey ? opts['x-apikey']
      #else if P.account?.resume # if paradigm creds are available, but not sending to a paradigm URL (which would include cookies if available) try the resume key
 
  xhr = new XMLHttpRequest()
  xhr.open (opts.method ? 'GET'), url
  xhr.setRequestHeader(h, opts.headers[h]) for h of opts.headers

  loaded = false
  xhr.onload = () ->
    loaded = true
    try
      if xhr.status > 199 and xhr.status < 400
        x = xhr.response
        try x = JSON.parse x
        try opts.success x, xhr
      else
        try opts.error xhr
    catch err
      try console.log err
      try opts.error xhr
  xhr.onerror = (err) -> try opts.error err, xhr
  xhr.onloadend = () -> try opts.error(xhr) if xhr.status in [404] and not loaded

  try xhr.send opts.data

P.cookie = (n, vs, opts) ->
  if n is '' or n is false or typeof n is 'object'
    vs = n
    n = undefined
  n ?= 'pradm'
  if vs? # even if values is false or '', so can remove this way
    opts ?= {}
    if opts.domain
      domained = true
    else
      domained = false
      opts.domain = '.' + window.location.host
      opts.domain = opts.domain.replace('.bg.', '.') if opts.domain.startsWith '.bg.' # a convenience for Paradigm bg servers
    t = n + '='
    if vs
      t += encodeURIComponent JSON.stringify vs # so if values is false or '' this will effectively remove the cookie
    else
      opts.expires = -1
    d = opts.expires ? 180
    if typeof d is 'number'
      d = new Date()
      d.setDate d.getDate() + opts.expires
    t += '; expires=' + new Date(d).toUTCString() if d instanceof Date
    t += '; domain=' + opts.domain if typeof opts.domain is 'string' and opts.domain isnt ''
    t += '; path=' + if typeof opts.path is 'string' and opts.path isnt '' then opts.path else '/'
    t += '; secure' if opts.secure isnt false # default to secure
    t += '; HttpOnly' if opts.httponly
    document.cookie = t
    if opts.expires is -1 and opts.domain and not domained
      dt = t.split('; domain=')[0] # clear the cookie without domain specified too, just to make sure
      document.cookie = dt
    return t
  else
    for c in document.cookie.split ';'
      c = c.substring(1) while c.charAt(0) is ' '
      return JSON.parse(decodeURIComponent(c.substring(n.length + 1, c.length))) if c.indexOf(n + '=') isnt -1
    return false

P.on = (a, id, fn) ->
  if a is 'enter'
    a = 'keyup'
    wfn = (e) -> fn(e) if e.keyCode is 13
  else
    wfn = fn

  P._ons ?= {}
  if not P._ons[a]?
    P._ons[a] = {}
    document.addEventListener a, (e) ->
      ids = []
      _bids = (et) ->
        for pc in P.classes et
          ids.push('.' + pc) if '.' + pc not in ids
        ids.push('#' + et.id) if et.id and '#' + et.id not in ids
        try
          etnl = et.tagName.toLowerCase()
          ids.push(etnl) if etnl not in ids
      _bids e.target
      if a in ['click'] # catch bubbling from clicks on child elements for example - are there other actions this is worth doing for?
        pn = e.target.parentNode
        while pn
          if document.body is pn
            pn = undefined
          else
            _bids pn
            pn = pn.parentNode
      for s in ids
        if P._ons[a][s]?
          P._ons[a][s][f](e) for f of P._ons[a][s]
          break
  P._ons[a][id] ?= {}
  P._ons[a][id][fn.toString().toLowerCase().replace('function', '').replace /[^a-z0-9]/g, ''] ?= wfn

