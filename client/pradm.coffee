
# n should be element ID or class name or tag name.
# Prefix IDs with # and class names with .
# Scope them to within a specific element by providing that element ID first 
# (preceded with #), then a space, then the element(s) class name / tag name
# (ID requests can't be scoped this way because IDs have to be unique within a page anyway)
# or an element to scope on can be directly provided as third param
P = (n, fn, sc) ->
  if typeof fn is 'function'
    P.each n, fn
  else if n
    [sc, n] = n.split(' ') if not sc?
    if not n?
      n = sc
      sc = document
    d = P[if n.startsWith('#') then 'gebi' else if n.startsWith('.') then 'gebc' else 'gebn'] n, sc
    return if d? and (n.startsWith('#') or d.length isnt 0) then d else undefined

P.api ?= @api ? '//' + window.location.host

P.gebi = (id) -> return document.getElementById id.split('#').pop().split(' ')[0]
P.gebc = (n, sc) ->
  sc = P.list(P sc ? n)[0] if typeof sc is 'string' or n.includes ' '
  d = (sc ? document).getElementsByClassName n.replace '.', ''
  return if d? and d.length is 1 then d[0] else d
P.gebn = (n, sc) ->
  n = n.replace /[<>]/g, ''
  if n.includes ','
    return P.gebns n, sc
  else
    sc = P.list(P sc ? n)[0] if typeof sc is 'string' or n.includes ' '
    d = (sc ? document).getElementsByTagName n # e.g. by the element name, like "div"
    d = (sc ? document).getElementsByName(n) if not d? or d.length is 0 # otherwise by the "name" attribute matching n
    return if d? and d.length is 1 then d[0] else d
P.gebns = (ns, sc) -> # ns could be like "h1, h2, h3, p"
  d = []
  sc = P.list(P sc ? ns)[0] if typeof sc is 'string' or ns.includes ' '
  for tag in ns.replace(/, /g, ',').split ','
    d.push(t) for t in (sc ? document).getElementsByTagName tag
  d.sort (a,b) -> return if a.sourceIndex then a.sourceIndex - b.sourceIndex else 3 - (a.compareDocumentPosition(b) & 6)
  return if d.length is 1 then d[0] else d

P.list = (els) ->
  els = P(els) if typeof els is 'string'
  els = [els] if els? and not Array.isArray(els) and not HTMLCollection.prototype.isPrototypeOf(els) and not NodeList.prototype.isPrototypeOf els
  return els ? []
P.each = (els, k, v, sc) ->
  els = P(els, undefined, sc) if typeof els is 'string'
  for el in P.list els
    if typeof k is 'function'
      k el
    else
      P.set(el, k, v) if el? and k?

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
P.toggle = (els) ->
  P.each els, (el) ->
    P[if el.style.display is 'none' then 'show' else 'hide'] el
P.focus = (els) -> P.each els, (el) -> el.focus()
P.blur = (els) -> P.each els, (el) -> el.blur()
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
P.val = P.get
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
P.attr = (els, a, v) -> return P[if v? then 'set' else 'get'] els, a, v
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
P.prepend = (els, h) -> P.html els, h, false
P.append = (els, h) -> P.html els, h, true
P.remove = (els) -> P.each els, (el) -> el.parentNode.removeChild el

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
      r.push(cc) if c not in r
  return r
P.class = P.classes
P.has = (els, cls) ->
  r = false
  P.each els, (el) ->
    r = true if cls.replace(/^\./, '') in P.classes(el) or (not cls.startsWith('.') and el.getAttribute cls)
  return r

P.css = (els, k, v) ->
  r = undefined
  P.each els, (el) ->
    style = {}
    for p in (P.get(el, 'style') ? '').split ';'
      [pk, pv] = p.split ':'
      style[pk] = if pk is k and v? then v else pv
    r ?= if k? then style[k] else style
    if v?
      ss = ''
      for sk of style
        ss += (if ss isnt '' then ';' else '') + sk + ':' + style[sk] if style[sk]?
      P.set el, 'style', ss
  return r

P.clone = (el, c) ->
  el = P(el) if typeof el is 'string'
  el = P.list(el)[0]
  if c
    n = el.cloneNode true
  else
    n = el.cloneNode false
    n.appendChild(el.firstChild) while el.hasChildNodes()
  el.parentNode.replaceChild n, el
  return n

P.siblings = (els) ->
  r = []
  P.each (els), (el) ->
    s = el.parentNode.firstChild
    while s
      r.push(s) if s.nodeType is 1 and s isnt el
      s = s.nextSibling
  return r
  
# end of functions that act on elements

P.on = (a, id, fn, l, sc) ->
  if a is 'enter'
    a = 'keyup'
    wfn = (e) -> fn(e) if e.keyCode is 13
  else
    wfn = fn
  l ?= 300 if a is 'scroll'
  l = 300 if l is true
  wfn = P.limit(wfn) if l
  P._ons ?= {}
  if not P._ons[a]?
    P._ons[a] = {}
    [sc, id] = id.split(' ') if id.includes ' '
    sc = P.list(P sc)[0] if sc? and typeof sc is 'string'
    (sc ? document).addEventListener a, (e) ->
      ids = P.classes e.target
      ids[i] = '.' + ids[i] for i of ids
      ids.push('#' + e.target.id) if e.target.id
      try ids.push e.target.tagName.toLowerCase()
      for s in ids
        if P._ons[a][s]?
          P._ons[a][s][f](e) for f of P._ons[a][s]
          break
  P._ons[a][id] ?= {}
  P._ons[a][id][fn.toString().toLowerCase().replace('function', '').replace /[^a-z0-9]/g, ''] ?= wfn

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
        o[k[0]] = if isNaN(parseInt(k[0])) then {} else []
        return P.dot o[k[0]], k.slice(1), v, d
      else
        return undefined
    else
      return P.dot o[k[0]], k.slice(1), v, d

P.keys = (o) ->
  r = []
  r.push(k) for k of o
  return r
  
P.params = (p) ->
  r = {}
  for kv in window.location.href.slice(window.location.href.indexOf('?') + 1).split '&'
    [k, v] = kv.split '='
    if k
      if typeof v is 'string'
        try v = decodeURIComponent v
        v = unescape v.replace /%22/gi, '"' # just in case of weird old encoders that sent odd params
        try v = JSON.parse v
      r[k] = v ? true
  return if p then r[p] else r

P.ajax = (url, opts) ->
  if typeof url is 'object'
    opts = url
    url = undefined
  url ?= opts.url ? ''
  if url is '' or (url.startsWith('/') and not url.startsWith '//')
    url = P.api + url

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

P.limit = (fn, w) ->
  w ?= 300
  p = 0
  t = null

  lim = () ->
    n = Date.now()
    r = w - (n - p)
    args = arguments
    if r <= 0 or r > w
      if t
        clearTimeout t
        t = null
      p = n
      res = fn.apply this, args
    else
      t ?= setTimeout () =>
        p = Date.now()
        res = fn.apply this, args
      , r
    return res

  lim.stop = () -> clearTimeout t
  return lim

P.ready = (fn) -> document.addEventListener 'DOMContentLoaded', fn

P.scroll = (fn) ->
  fn = P.limit fn
  window.addEventListener 'scroll', (e) -> fn(e)
P.scroll() if P '.Pscroll' # a convenience for nice UI visuals
