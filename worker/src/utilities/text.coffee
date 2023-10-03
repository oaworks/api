P.levenshtein = (a, b, lowercase) ->
  a ?= this?.params?.a
  b ?= this?.params?.b
  lowercase ?= this?.params?.lowercase ? true
  if lowercase
    a = a.toLowerCase()
    b = b.toLowerCase()
  minimator = (x, y, z) ->
    return x if x <= y and x <= z
    return y if y <= x and y <= z
    return z

  m = a.length
  n = b.length

  if m < n
    c = a
    a = b
    b = c
    o = m
    m = n
    n = o

  r = [[]]
  c = 0
  while c < n + 1
    r[0][c] = c
    c++

  i = 1
  while i < m + 1
    r[i] = [i]
    j = 1
    while j < n + 1
      cost = if a.charAt( i - 1 ) is b.charAt( j - 1 ) then 0 else 1
      r[i][j] = minimator( r[i-1][j] + 1, r[i][j-1] + 1, r[i-1][j-1] + cost )
      j++
    i++

  return distance: r[ r.length - 1 ][ r[ r.length - 1 ].length - 1 ], length: {a:m, b:n} #, detail: r

P.extract = (opts) ->
  # opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
  opts ?= @copy @params
  if opts.url and not opts.content
    if opts.url.indexOf('.pdf') isnt -1 or opts.url.indexOf('/pdf') isnt -1
      opts.convert ?= 'pdf'
    else
      #opts.content = await @puppet opts.url
      opts.content = await @fetch opts.url
  if opts.convert
    try text = await @convert[opts.convert + '2txt'] opts.url ? opts.content
  text ?= opts.content

  opts.matchers ?= [opts.match]
  if opts.start?
    parts = text.split opts.start
    text = if parts.length > 1 then parts[1] else parts[0]
  text = text.split(opts.end)[0] if opts.end?
  text = text.toLowerCase() if opts.lowercase
  text = text.replace(/[^a-z0-9]/g,'') if opts.ascii
  text = text.replace(/ /g,'') if opts.spaces is false

  res = {length: text.length, matched: 0, matches: [], matchers: opts.matchers, text: text}

  if text and typeof text isnt 'number'
    for match in (if typeof opts.matchers is 'string' then opts.matchers.split(',') else opts.matchers)
      if typeof match is 'string'
        mopts = ''
        if match.indexOf('/') is 0
          lastslash = match.lastIndexOf '/'
          if lastslash+1 isnt match.length
            mopts = match.substring lastslash+1
            match = match.substring 1,lastslash
        else
          match = match.replace /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&"
      else
        mopts = ''
      mopts += 'i' if opts.lowercase
      try
        mr = new RegExp match, mopts
        if m = mr.exec text
          res.matched += 1
          res.matches.push {matched: match.toString(), result: m}

  return res

P.decode = (content) ->
  content ?= this?.params?.decode ? this?.params?.content ? this?.params?.text ? this?.body
  _decode = (content) ->
    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g
    translate = "nbsp":" ", "amp" : "&", "quot": "\"", "lt"  : "<", "gt"  : ">"
    return content.replace(translator, ((match, entity) ->
      return translate[entity]
    )).replace(/&#(x?[0-9A-Fa-f]+);/gi, ((match, numStr) ->
      if numStr.startsWith 'x'
        num = parseInt numStr.replace('x', ''), 16
      else
        num = parseInt numStr, 10
      return String.fromCharCode num
    ))
  text = await _decode content
  text = text.replace /\n/g, ' '
  for c in [{bad: '‘', good: "'"}, {bad: '’', good: "'"}, {bad: '´', good: "'"}, {bad: '“', good: '"'}, {bad: '”', good: '"'}, {bad: '–', good: '-'}, {bad: '-', good: '-'}]
    re = new RegExp c.bad, 'g'
    text = text.replace re, c.good
  try text = decodeURIComponent(text) if text.indexOf('%2') isnt -1
  try text = decodeURIComponent(text) if text.indexOf('%2') isnt -1 # some of the data we handle was double encoded, so like %2520, so need two decodes
  return text
