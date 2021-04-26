
@pradm ?= {}
pradm.api ?= '//' + window.location.host
pradm.gebi = (id) -> return document.getElementById id.replace('#','')
pradm.gebc = (cls) -> return document.getElementsByClassName cls.replace('.','')
pradm.gebn = (n) -> 
  r = document.getElementsByTagName n.replace('<','').replace('>','') # e.g. by the element name, like "div"
  return if r? then r else  document.getElementsByName n # otherwise by the "name" attribute matching n
pradm.each = (elems, key, val) ->
  if typeof elems is 'string'
    if elems.startsWith '#'
      elems = [pradm.gebi elems]
    else if elems.startsWith '.'
      elems = pradm.gebc elems
    else
      elems = pradm.gebn elems
  else if typeof elems is 'object'
    elems = [elems] if not Array.isArray elems
  if elems?
    for elem in elems
      if elem?
        if typeof key is 'function' then key(elem) else pradm.set elem key, val
pradm.listen = (action, els, fn) ->
  pradm.each els, (el) -> 
    if action is 'enter'
      action = 'keyup'
      wfn = (e) -> fn(e) if e.keyCode is 13
    else
      wfn = fn
    #el = pradm.clone el # gets rid of all listeners so we don't end up with dups - but note, gets rid of ALL. TODO use a wrapper to manage these independently
    if not pradm.has el, 'listen_'+action
      pradm.class el, 'listen_'+action
      el.addEventListener action, (e) -> wfn(e)
pradm.show = (els, html, append) ->
  pradm.each els, (el) -> 
    if typeof html is 'string'
      el.innerHTML = (if append then el.innerHTML else '') + html
    was = pradm.get el, 'pradm_display'
    was = 'block' if typeof was isnt 'string' or was is 'none' # TODO should be inline in which cases...
    el.style.display = was
pradm.hide = (els) ->
  pradm.each els, (el) -> 
    if el.style.display isnt 'none'
      pradm.set el, 'pradm_display', el.style.display
    el.style.display = 'none'
pradm.get = (el, attr) ->
  if not attr?
    try res = pradm.checked el
    try
      if not res? and el.getAttribute('type') not in ['radio', 'checkbox']
        res = el.value
    res = undefined if typeof res is 'string' and not res.length
  try res ?= el.getAttribute attr
  return res
pradm.set = (el, attr, val) -> try el.setAttribute attr, val
pradm.checked = (el) ->
  if el instanceof HTMLInputElement
    if el.getAttribute('type') is 'checkbox'
      return el.checked
    else if el.getAttribute('type') is 'radio'
      return if el.checked and el.value then el.value else undefined
  else
    return undefined
pradm.html = (els, html, append, show) ->
  rs = []
  pradm.each els, (el) -> 
    if typeof html is 'string'
      el.innerHTML = (if append then el.innerHTML else '') + html
    rs.push el.innerHTML
    pradm.show(el) if show
  return if rs.length is 1 then (rs[0] ? '') else if rs.length then rs else ''
pradm.append = (els, html) -> pradm.html els, html, true
pradm.remove = (els) -> pradm.each els, (el) -> el.parentNode.removeChild el
pradm.class = (el, cls, remove) -> 
  classes = el.getAttribute 'class'
  classes ?= ''
  if typeof cls is 'string'
    if remove is false
      classes = classes.replace(cls,'').trim().replace(/  /g,' ')
    else if classes.indexOf(cls) is -1
      classes += ' ' if classes.length
      classes += cls
    el.setAttribute 'class', classes
  return classes.split ' '
pradm.classes = (els) -> return pradm.class els
pradm.has = (el, cls) ->
  classes = pradm.classes el
  cls = cls.replace('.') if cls.startsWith '.'
  if cls in classes
    return true
  else
    return if el.getAttribute(cls) then true else false
pradm.css = (els, key, val) ->
  rs = []
  pradm.each els, (el) ->
    s = pradm.get el, 'style'
    s ?= ''
    style = {}
    for p in s.split ';'
      ps = p.split ':'
      style[ps[0].trim()] = ps[1].trim() if ps.length is 2
    if not key? or style[key]?
      rs.push if key? then style[key] else style
    style[key] = val if val?
    ss = ''
    for k of style
      ss += ';' if ss isnt ''
      ss += k + ':' + style[k]
    pradm.set el, 'style', ss
  if not val?
    return if rs.length is 1 then rs[0] else rs
pradm.clone = (el, children) ->
  if children
    n = el.cloneNode true
  else
    n = el.cloneNode false
    n.appendChild(el.firstChild) while el.hasChildNodes()
  el.parentNode.replaceChild n, el
  return n

pradm.dot = (obj, key, value, del) ->
  if typeof key is 'string'
    return pradm.dot obj, key.split('.'), value, del
  else if key.length is 1 and (value? or del?)
    if del is true or value is '$DELETE'
      if obj instanceof Array
        obj.splice key[0], 1
      else
        delete obj[key[0]]
      return true;
    else
      obj[key[0]] = value # TODO see below re. should this allow writing into multiple sub-objects of a list?
      return true
  else if key.length is 0
    return obj
  else
    if not obj[key[0]]?
      if false
        # check in case obj is a list of objects, and key[0] exists in those objects
        # if so, return a list of those values.
        # Keep order of the list? e.g for objects not containing the key, output undefined in the list space where value would have gone?
        # and can this recurse further? If the recovered items are lists or objecst themselves, go further into them?
        # if so, how would that be represented? and is it possible for this to work at all with value assignment?
      else if value?
        obj[key[0]] = if isNaN(parseInt(key[0])) then {} else []
        return pradm.dot obj[key[0]], key.slice(1), value, del
      else
        return undefined
    else
      return pradm.dot obj[key[0]], key.slice(1), value, del

pradm.ajax = (url, opts) ->
  console.log url
  if typeof url is 'object'
    opts = url
    url = undefined
  url ?= opts.url ? ''
  if url is '' or (url.startsWith '/' and not url.startsWith '//')
    url = pradm.api + url
  opts ?= {}
  opts.headers ?= {}
  if opts.data?
    opts.method = 'POST'
    if typeof opts.data is 'object' and typeof opts.data.append isnt 'function' # a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify opts.data
      opts.headers['Content-type'] ?= 'application/json'
    url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching
  xhr = new XMLHttpRequest()
  console.log url
  xhr.open (opts.method ? 'GET'), url
  xhr.setRequestHeader(h, opts.headers[h]) for h of opts.headers
  xhr.send opts.data
  xhr.onload = () ->
    try # worth checking xhr.status is 200?
      x = xhr.response
      try x = JSON.parse x
      opts.success x, xhr
    catch err
      try console.log err
      try opts.error xhr
  xhr.onerror = (err) -> try opts.error err
