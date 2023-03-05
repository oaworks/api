
P.convert ?= {}

P.convert.json2csv = (recs, params) ->
  recs ?= @body ? @params
  params ?= @params
  if params.url
    recs = await @fetch params.url
  if params.es or recs?.hits?.hits?
    try
      recs = recs.hits.hits
      params.es = true
  recs = [recs] if not Array.isArray recs
  quote = params.quote ? '"'
  separator = params.separator ? ','
  newline = params.newline ? '\n'
  if not recs.length
    return ''
  else
    headers = params.keys ? []
    records = ''
    for rec in recs
      records += newline if records.length
      if params.es isnt false and (rec._source or rec.fields)
        rs = rec._source ? rec.fields
        rc = {}
        for nk of rs # could add controls to alter the order here, or customise key names
          rc[nk] ?= rs[nk]
        rec = rc
      if params.flatten
        rec = await @flatten rec
      if params.subset
        rec = await @dot rec, params.subset
      if not params.keys
        for k of rec
          headers.push(k) if rec[k]? and k not in headers
      for h in headers
        records += separator if records.length and not records.endsWith newline
        records += quote
        if rec[h]?
          try rec[h] = rec[h][0] if Array.isArray(rec[h]) and rec[h].length is 1 and Array.isArray rec[h][0]
          try rec[h] = rec[h].join(',') if Array.isArray(rec[h]) and rec[h].length and typeof rec[h][0] isnt 'object'
          try rec[h] = JSON.stringify(rec[h]) if typeof rec[h] is 'object'
          try rec[h] = rec[h].replace(/"/g, quote + quote) if quote is '"' and rec[h].indexOf(quote) isnt -1 # escape quotes with another quote
          #try rec[h] = rec[h].replace /,,/g, separator # TODO change this for a regex of the separator
          try rec[h] = rec[h].replace /\n/g, ' '
          try rec[h] = rec[h].replace /\s\s/g, ' '
          try records += rec[h]
        records += quote
    return quote + headers.join(quote + separator + quote) + quote + '\n' + records

P.convert.csv2json = (csv, params) ->
  params ?= @params
  csv ?= @body ? @params.csv
  if params.url or (typeof csv is 'string' and csv.startsWith 'http')
    csv = await @fetch params.url ? csv
  res = []
  if typeof csv is 'string' and csv.length
    quote = params.quote ? '"'
    separator = params.separator ? ','
    newline = params.newline ? '\n'
    lines = csv.split newline
    if lines.length
      headers = lines.shift().split quote + separator
      # TODO add handling for flattened object headers eg metadata.author.0.name via a utility for it
      pl = ''
      for line in lines
        pl += (if pl then newline else '') + line
        vals = pl.split quote + separator
        if vals.length is headers.length and (not quote or line.endsWith quote)
          pl = ''
          row = {}
          for h in headers
            h = h.replace(quote, '') if h.startsWith quote
            h = h.substring(0, h.length-1) if h.endsWith quote
            if vals.length
              row[h] = vals.shift()
              if row[h]
                row[h] = row[h].replace(quote, '') if row[h].startsWith quote
                row[h] = row[h].substring(0, row[h].length-1) if not vals.length and row[h].endsWith quote # strip the end quote from the last one
                try row[h] = JSON.parse row[h]
          res.push row
  return res

P.convert.csv2html = (csv, params) ->
  csv ?= @body ? @params.csv
  params ?= @params
  if params.url or (typeof csv is 'string' and csv.startsWith 'http')
    csv = await @fetch params.url ? csv
  quote = '"'
  separator = ','
  newline = '\n'
  csv = csv.replace /,,/g, separator + quote + quote + separator # TODO change this for a regex of the separator
  res = '<style>table.paradigm tr:nth-child(even) {background: #eee}\
table.paradigm tr:nth-child(odd) {background: #fff}</style>\n'
  res += '<table class="paradigm" style="border-collapse: collapse;">\n'
  if typeof csv is 'string' and csv.length
    lines = csv.split newline
    if lines.length
      res += '<thead><tr>'
      headers = lines.shift()
      ln = 0
      for header in headers.split quote + separator + quote
        res += '<th style="padding:2px; border:1px solid #ccc;">' + header.replace(/"/g, '') + '</th>'
        ln += 1
      res += '</tr></thead>\n<tbody>\n'
      for line in lines
        res += '<tr>'
        line = line.replace(',"",', ',"XXX_EMPTY_XXX",') while line.indexOf(',"",') isnt -1
        line = line.replace('"",','"XXX_EMPTY_XXX",') while line.startsWith '"",'
        line = line.slice(0,line.length-3) while line.endsWith ',""'
        line = line.replace /""/g, 'XXX_QUOTER_GOES_HERE_XXX' # TODO change this for a regex of whatever the quote char is
        vn = 0
        for v in line.split quote + separator + quote
          vn += 1
          res += '<td style="padding:2px; border:1px solid #ccc;vertical-align:text-top;">'
          v = v.replace(/^"/, '').replace(/"$/, '')
          if v isnt 'XXX_EMPTY_XXX'
            if v.indexOf('{') is 0 or v.indexOf('[') is 0
              res += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;">...</a><div style="display:none;">'
              res += await @convert.json2html JSON.parse v.replace /XXX_QUOTER_GOES_HERE_XXX/g, quote
              res += '</div>'
            else
              res += v.replace /XXX_QUOTER_GOES_HERE_XXX/g, quote # .replace(/\</g, '&lt;').replace(/\>/g, '&gt;')
          res += '</td>' # add a regex replace of the separator, avoiding escaped instances
        while vn < ln
          res += '<td style="padding:2px; border:1px solid #ccc;vertical-align:text-top;"></td>'
          vn += 1
        res += '</tr>\n'
      res += '</tbody>\n'
  return res + '</table>'

P.convert.json2html = (recs, params) ->
  recs ?= @body ? @params
  params ?= @params
  if params.url
    recs = await @fetch url
  if params.new
    params.edit ?= true
    recs = {}
    for key in await @index.keys @route.replace /\//g, '_'
      recs[key] = '' # could also get mapping types from here, and need to handle nesting eventually
  if params.subset and not Array.isArray recs
    parts = params.subset.split '.'
    while part = parts.shift()
      if typeof recs is 'object' and not Array.isArray(recs) and recs[part]?
        recs = recs[part]
      else
        break
  if Array.isArray(recs) or (recs?.hits?.hits? and params.es isnt false)
    params.subset = parts.join('.') if parts?
    return @convert.csv2html await @convert.json2csv recs, params
  else
    res = '<div>'
    if params.flatten
      recs = await @flatten recs
      res += '<input type="hidden" id="options_flatten" value="true">'
    if params.subset
      if parts.length
        recs = recs[pt] for pt in parts
      res += '<h3>' + params.subset + ':</h3>'
      res += '<input type="hidden" id="options_subset" value="' + params.subset + '">'
    _draw = (rec) =>
      if params.edit # just for rscvd demo for now
        rec.comments ?= ''
      if params.keys
        rec[pk] ?= '' for pk in params.keys
      for k of rec
        # for example crossref date-parts are an array in an array, pretty useless, so dump the external array
        try rec[k] = rec[k][0] if Array.isArray(rec[k]) and rec[k].length is 1 and Array.isArray rec[k][0]
        if rec[k]? and (not Array.isArray(rec[k]) or rec[k].length) and (not params.keys or k in params.keys)
          res += '<div style="clear:both; ' + (if not params.edit then 'border:1px solid #ccc; ' else '') + 'margin:-1px 0px;"><div style="float:left;width: 150px; overflow: scroll;"><b><p>' + k + '</p></b></div>'
          res += '<div style="float:left;">'
          res += if params.edit then '<textarea class="PForm" id="' + k + '" style="min-height:80px;width:100%;margin-bottom:5px;">' else ''
          if Array.isArray rec[k]
            if typeof rec[k][0] is 'object'
              for ok in rec[k]
                _draw ok
            else
              try
                rks = rec[k].join ', '
              catch
                try
                  rks = JSON.stringify rec[k]
                catch
                  rks = rec[k]
              try res += (if params.edit then '' else '<p>') + rks + (if params.edit then '' else '</p>')
          else if typeof rec[k] is 'object'
            _draw rec[k]
          else
            res += (if params.edit then '' else '<p>') + rec[k] + (if params.edit then '' else '</p>')
          res += if params.edit then '</textarea>' else ''
          res += '</div></div>'
    _draw recs
    res += '</div>'
    return res

P.convert.json2txt = (content) ->
  content ?= @body ? @params
  content = await @fetch(@params.url) if @params.url
  strings = []
  _extract = (content) ->
    if Array.isArray content
      await _extract(c) for c in content
    else if typeof content is 'object'
      await _extract(content[c]) for c of content
    else if content
      strings.push content
  await _extract content
  return strings.join ' '

P.convert._hexMatch = 
  '0': '0000'
  '1': '0001'
  '2': '0010'
  '3': '0011'
  '4': '0100'
  '5': '0101'
  '6': '0110'
  '7': '0111'
  '8': '1000'
  '9': '1001'
  'a': '1010'
  'b': '1011'
  'c': '1100'
  'd': '1101'
  'e': '1110'
  'f': '1111'

P.convert.hex2bin = (ls) ->
  res = []
  for l in (if not Array.isArray(ls) then [ls] else ls)
    res.push P.convert._hexMatch[l.toLowerCase()]
  return res.join ''

P.convert.bin2hex = (ls) ->
  # this needs work...
  if not Array.isArray ls
    els = []
    sls = ls.split('')
    pr = ''
    while sls.length
      pr += sls.shift()
      if pr.length is 4
        els.push pr
        pr = ''
    ls = els
  res = []
  hm = {}
  for k of P.convert._hexMatch
    hm[P.convert._hexMatch[k]] = k
  for l in ls
    res.push '0x' + hm[l]
  return new Buffer(res).toString()
  
P.convert.buf2bin = (buf) ->
  buf = buf.toString('hex') if Buffer.isBuffer buf
  buf = buf.replace /^0x/, ''
  ret = ''
  c = 0
  while c < buf.length
    ret += await P.convert.hex2bin buf[c]
    c++
  return ret

P.convert.stream2txt = (stream) ->
  chunks = []
  return new Promise (resolve, reject) =>
    stream.on 'data', (chunk) => chunks.push Buffer.from chunk
    stream.on 'error', (err) => reject err
    stream.on 'end', () => resolve Buffer.concat(chunks).toString 'utf8'

P.convert.xml2json = (x) ->
  # TODO parse from buffer (file on disk or stream from url)
  # allow CDATA e.g <![CDATA[<p>your html here</p>]]>
  # track embedded and unescaped html tags e.g https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
  x ?= @params.xml2json ? @params.url
  res = {}
  if typeof x is 'string'
    x = await @fetch(x) if x.startsWith 'http'
    elem = ''
    pointer = ''
    starting = false
    ending = false
    while c = x[0]
      x = x.slice 1
      if c not in ['\uFEFF', '\t', '\r', '\n'] and (c isnt ' ' or (elem.length and not elem.endsWith '>'))
        starting = true if elem is '<' and c not in ['/', '?', '!'] # ignore xml and doctype statements - can add later if any use for them is found
        elem += c
        ending = true if (elem.endsWith('</') and elem.split('</').length-1 is elem.split('>').length) or (elem.endsWith('/>') and not elem.split('/>')[0].includes '>')
        if c is '>'
          console.log pointer
          if ending
            ending = false
            elem = elem.split('</')[0]
            if elem isnt ''
              if pv = await @dot res, pointer, undefined, undefined, true
                if Array.isArray pv
                  pv = [{}] if not pv.length
                  if pv[pv.length-1].$?
                    pv[pv.length-1].$ = [pv[pv.length-1].$] if not Array.isArray pv[pv.length-1].$
                    pv[pv.length-1].$.push elem
                  else
                    pv[pv.length-1].$ = elem
                else
                  pv.$ = elem
                elem = pv
              else
                elem = $: elem
                try elem._ = prv[pointer.split('.').pop()]._ if prv = await @dot res, pointer.slice(0, pointer.lastIndexOf('.')), undefined, undefined, true
              elem = elem.$ if typeof elem is 'object' and not elem._? and elem.$?
              await @dot res, pointer, elem, undefined, true
            pointer = if pointer.includes('.') then pointer.slice(0, pointer.lastIndexOf('.')) else ''
          else if starting
            starting = false
            meta = {}
            for p in elem.replace('<', '').replace('>', '').split ' '
              if not p.includes '='
                pointer += (if pointer and not pointer.endsWith('.') then '.' else '') + p
              else if p.length
                [k, v] = p.split '='
                meta[k.trim().replace(/"/g, '')] = v.trim().replace /"/g, ''
            if pv = await @dot res, pointer, undefined, undefined, true
              pv = [pv] if not Array.isArray pv
              pv.push if JSON.stringify(meta) isnt '{}' then {_: meta} else {}
              await @dot res, pointer, pv, undefined, true
            else if JSON.stringify(meta) isnt '{}'
              await @dot res, pointer + '._', meta, undefined, true
          elem = ''
  return res

