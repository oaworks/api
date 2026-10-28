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
