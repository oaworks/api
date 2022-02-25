
# n should be element ID or class name or tag name.
# Prefix IDs with # and class names with .
# Scope them to within a specific element by providing that element ID first 
# (preceded with #), then a space, then the element(s) class name / tag name
# (ID requests can't be scoped this way because IDs have to be unique within a page anyway)
# or an element to scope on can be directly provided as third param
P = (n, fn, sc) ->
  if typeof fn is 'function'
    P.each n, fn, undefined, sc
  else if n
    if n.startsWith('#') and n.includes ' '
      sc = n.split(' ')[0]
      n = n.replace sc + ' ', ''
      sc = P.gebi sc
    d = P[if n.startsWith('#') then 'gebi' else if n.startsWith('.') then 'gebc' else 'gebn'] n, sc
    return if d? and (n.startsWith('#') or d.length isnt 0) then d else undefined

P.gebi = (id) -> return document.getElementById id.split('#').pop().split(' ')[0]
P.gebc = (n, sc) ->
  sc ?= P.list(P sc ? n)[0] if typeof sc is 'string' or (n.startsWith('#') and n.includes ' ')
  d = (sc ? document).getElementsByClassName n.replace(/^\./, '').replace(/\s\./g, ' ').trim()
  return if d? and d.length is 1 then d[0] else d
P.gebn = (n, sc) ->
  n = n.replace /[<>]/g, ''
  if n.includes ','
    return P.gebns n, sc
  else
    sc ?= P.list(P sc ? n)[0] if typeof sc is 'string' or (n.startsWith('#') and n.includes ' ')
    d = (sc ? document).getElementsByTagName n # e.g. by the element name, like "div"
    d = (sc ? document).getElementsByName(n) if not d? or d.length is 0 # otherwise by the "name" attribute matching n
    return if d? and d.length is 1 then d[0] else d
P.gebns = (ns, sc) -> # ns could be like "h1, h2, h3, p"
  d = []
  sc ?= P.list(P sc ? ns)[0] if typeof sc is 'string' or (ns.startsWith('#') and ns.includes ' ')
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
      r.push(cc) if cc not in r
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
      style[k] = v
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

P.mobile = () -> # try to tell if on a mobile device
  if /(android|bb\d+|meego).+mobile|avantgo|bada\/|blackberry|blazer|compal|elaine|fennec|hiptop|iemobile|ip(hone|od)|ipad|iris|kindle|Android|Silk|lge |maemo|midp|mmp|netfront|opera m(ob|in)i|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|series(4|6)0|symbian|treo|up\.(browser|link)|vodafone|wap|windows (ce|phone)|xda|xiino/i.test(navigator.userAgent) or /1207|6310|6590|3gso|4thp|50[1-6]i|770s|802s|a wa|abac|ac(er|oo|s\-)|ai(ko|rn)|al(av|ca|co)|amoi|an(ex|ny|yw)|aptu|ar(ch|go)|as(te|us)|attw|au(di|\-m|r |s )|avan|be(ck|ll|nq)|bi(lb|rd)|bl(ac|az)|br(e|v)w|bumb|bw\-(n|u)|c55\/|capi|ccwa|cdm\-|cell|chtm|cldc|cmd\-|co(mp|nd)|craw|da(it|ll|ng)|dbte|dc\-s|devi|dica|dmob|do(c|p)o|ds(12|\-d)|el(49|ai)|em(l2|ul)|er(ic|k0)|esl8|ez([4-7]0|os|wa|ze)|fetc|fly(\-|_)|g1 u|g560|gene|gf\-5|g\-mo|go(\.w|od)|gr(ad|un)|haie|hcit|hd\-(m|p|t)|hei\-|hi(pt|ta)|hp( i|ip)|hs\-c|ht(c(\-| |_|a|g|p|s|t)|tp)|hu(aw|tc)|i\-(20|go|ma)|i230|iac( |\-|\/)|ibro|idea|ig01|ikom|im1k|inno|ipaq|iris|ja(t|v)a|jbro|jemu|jigs|kddi|keji|kgt( |\/)|klon|kpt |kwc\-|kyo(c|k)|le(no|xi)|lg( g|\/(k|l|u)|50|54|\-[a-w])|libw|lynx|m1\-w|m3ga|m50\/|ma(te|ui|xo)|mc(01|21|ca)|m\-cr|me(rc|ri)|mi(o8|oa|ts)|mmef|mo(01|02|bi|de|do|t(\-| |o|v)|zz)|mt(50|p1|v )|mwbp|mywa|n10[0-2]|n20[2-3]|n30(0|2)|n50(0|2|5)|n7(0(0|1)|10)|ne((c|m)\-|on|tf|wf|wg|wt)|nok(6|i)|nzph|o2im|op(ti|wv)|oran|owg1|p800|pan(a|d|t)|pdxg|pg(13|\-([1-8]|c))|phil|pire|pl(ay|uc)|pn\-2|po(ck|rt|se)|prox|psio|pt\-g|qa\-a|qc(07|12|21|32|60|\-[2-7]|i\-)|qtek|r380|r600|raks|rim9|ro(ve|zo)|s55\/|sa(ge|ma|mm|ms|ny|va)|sc(01|h\-|oo|p\-)|sdk\/|se(c(\-|0|1)|47|mc|nd|ri)|sgh\-|shar|sie(\-|m)|sk\-0|sl(45|id)|sm(al|ar|b3|it|t5)|so(ft|ny)|sp(01|h\-|v\-|v )|sy(01|mb)|t2(18|50)|t6(00|10|18)|ta(gt|lk)|tcl\-|tdg\-|tel(i|m)|tim\-|t\-mo|to(pl|sh)|ts(70|m\-|m3|m5)|tx\-9|up(\.b|g1|si)|utst|v400|v750|veri|vi(rg|te)|vk(40|5[0-3]|\-v)|vm40|voda|vulc|vx(52|53|60|61|70|80|81|83|85|98)|w3c(\-| )|webc|whit|wi(g |nc|nw)|wmlb|wonu|x700|yas\-|your|zeto|zte\-/i.test(navigator.userAgent.substr(0,4))
    return true
  else
    return false

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

P.on = (a, id, fn, l, sc) ->
  if typeof fn is 'number' and typeof l is 'function'
    nl = fn
    fn = l
    l = nl
  if a is 'enter'
    a = 'keyup'
    wfn = (e) -> fn(e) if e.keyCode is 13
  else
    wfn = fn
  l ?= 300 if a in ['scroll', 'keyup']
  l = 300 if l is true
  wfn = P.limit(wfn, l) if l
  
  if id.startsWith('#') and id.includes ' '
    sc = id.split(' ')[0].replace '#', ''
    id = id.split ' '
    id.shift()
    id = id.join ' '
  else
    sc = '_doc'

  P._ons ?= {}
  P._ons[sc] ?= {}
  if not P._ons[sc][a]?
    P._ons[sc][a] = {}
    (if sc is '_doc' then document else P.list(P '#' + sc)[0]).addEventListener a, (e) ->
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
        if P._ons[sc][a][s]?
          P._ons[sc][a][s][f](e) for f of P._ons[sc][a][s]
          break
  P._ons[sc][a][id] ?= {}
  P._ons[sc][a][id][fn.toString().toLowerCase().replace('function', '').replace /[^a-z0-9]/g, ''] ?= wfn

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
