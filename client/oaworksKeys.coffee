
_OAcookie = (obj) ->
  if obj?
    domain = '.' + window.location.host
    domain = domain.replace('.bg.', '.') if domain.startsWith '.bg.'
    t = 'OAKeys='
    if obj
      t += encodeURIComponent JSON.stringify obj # so if values is false or '' this will effectively remove the cookie
      expires = 365
    else
      expires = -1
    d = new Date()
    d.setDate d.getDate() + expires
    t += '; expires=' + new Date(d).toUTCString()
    t += '; domain=' + domain + '; secure'
    document.cookie = t
    return t
  else
    for c in document.cookie.split ';'
      c = c.substring(1) while c.charAt(0) is ' '
      return JSON.parse(decodeURIComponent(c.substring(7, c.length))) if c.indexOf('OAKeys=') isnt -1
    return false

ck = _OAcookie()
window.OAKEYS = if typeof ck is 'object' then ck else {}

if window.location.search.includes 'orgkey='
  try o = window.location.search.split('org=')[1].split('&')[0]
  try o ?= window.location.href.split('//')[1].split('/')[1]
  if o
    window.OAKEYS[decodeURIComponent o] = window.location.search.split('orgkey=')[1].split('&')[0]
    _OAcookie window.OAKEYS
    try history.pushState null, null, window.location.href.split('?')[0]

if window.location.search.includes 'logout'
  window.OAKEYS = {} # or work out the org here and only logout of that org?
  _OAcookie false
  try history.pushState null, null, window.location.href.split('?')[0]
    
