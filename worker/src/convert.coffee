
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
        idlink = true
        if not params.keys or '_id' in params.keys
          rc._id = '<a onclick="this.setAttribute(\'href\', window.location.href.split(\'.html\')[0].split(\'/\').pop() + \'/\' + this.getAttribute(\'href\') )" href="' + rec._id + '.html">' + rec._id + '</a>'
          idlink = false
        for nk of rs # could add controls to alter the order here, or customise key names
          rc[nk] ?= rs[nk]
          if idlink and nk is params.keys[0]
            try rc[nk] = '<a onclick="this.setAttribute(\'href\', window.location.href.split(\'.html\')[0].split(\'/\').pop() + \'/\' + this.getAttribute(\'href\') )" href="' + rec._id + '.html">' + rs[nk] + '</a>'
            idlink = false
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
          try rec[h] = rec[h].join(', ') if Array.isArray(rec[h]) and rec[h].length and typeof rec[h][0] is 'string'
          try rec[h] = JSON.stringify(rec[h]) if typeof rec[h] is 'object'
          try rec[h] = rec[h].replace /"/g, quote + quote
          try rec[h] = rec[h].replace /,,/g, separator # TODO change this for a regex of the separator
          try rec[h] = rec[h].replace /\n/g, ' '
          try rec[h] = rec[h].replace /\s\s/g, ' '
          try records += rec[h]
        records += quote
    return quote + headers.join(quote + separator + quote) + quote + '\n' + records

P.convert.csv2json = (csv, params) ->
  csv ?= @body ? @params.csv
  if @params.url
    csv = await @fetch url
  params ?= @params
  quote = params.quote ? '"'
  separator = params.separator ? ','
  newline = params.newline ? '\n'
  csv = csv.replace /""/g, 'XXX_QUOTER_GOES_HERE_XXX' # TODO change this for a regex of whatever the quote char is
  res = []
  if typeof csv is 'string' and csv.length
    lines = csv.split newline
    if lines.length
      headers = lines.shift().split quote + separator
      # TODO add handling for flattened object headers eg metadata.author.0.name
      # should do this by making an unflatten utility that goes through the object and rebuilds
      for header in headers
        header = header.replace(quote, '') if header.indexOf(quote) is 0
      for line in lines
        row = {}
        vals = line.split quote + separator
        for h in headers
          if vals.length
            row[h] = vals.shift()
            if row[h]
              row[h] = row[h].replace(/^"/, '').replace(/"$/, '').replace /XXX_QUOTER_GOES_HERE_XXX/g, quote
              try row[h] = JSON.parse row[h]
        res.push row
  return res

P.convert.csv2html = (csv) ->
  csv ?= @body ? @params.csv
  if @params.url
    csv = await @fetch url
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
  if Array.isArray(recs) or (recs?.hits?.hits and params.es isnt false)
    params.subset = parts.join('.') if parts?
    tbl = await @convert.csv2html await @convert.json2csv recs, params
    return tbl
  else
    res = '<div>'
    if params.edit # extras only for rscvd for now but should be any management fields to add and not yet present
      res += '<div style="clear:both; margin:-1px 0px;"><div style="float:left;width: 150px; overflow: scroll;"><b><p>status</p></b></div>'
      res += '<div style="float:left;"><select class="pradmForm" id="status" style="margin-top:15px;margin-bottom:0px;min-width:180px;">'
      for st in ['', 'Verified', 'Denied', 'Progressing', 'Overdue', 'Provided', 'Cancelled', 'Done']
        res += '<option' + (if recs.status is st then ' selected="selected"' else '') + '>' + st + '</option>'
      delete recs.status
      res += '</select></div>'
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
          res += if params.edit then '<textarea class="pradmForm" id="' + k + '" style="min-height:80px;width:100%;margin-bottom:5px;">' else ''
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
    if params.edit
      res = '<script type="text/javascript" src="/client/pradm.js"></script><script type="text/javascript" src="/client/pradmEdit.js"></script>' + res
      res += '<script type="text/javascript">pradm.edit()</script>'
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


'''
P.convert.table2csv = (content) ->
  d = P.convert.table2json content, opts
  return P.convert.json2csv d

P.convert.table2json = () ->
  return @convert.json2csv await @convert.table2csv

P.convert.html2txt = (content) -> # or xml2txt
  text = html2txt.fromString(content, {wordwrap: 130})
  return text
P.convert.xml2txt = (content) ->
  return @convert.html2txt content

P.convert.xml2json = (content) ->
  # TODO needs to handle attributes etc
  return ''
'''

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
    ret += P.convert.hex2bin buf[c]
    c++
  return ret

P.convert._mimes = {
  '.aac': 'audio/aac', # AAC audio	
  '.abw': 'application/x-abiword', # AbiWord document
  '.arc': 'application/x-freearc', # Archive document (multiple files embedded)
  '.avi': 'video/x-msvideo', # AVI: Audio Video Interleave
  '.azw': 'application/vnd.amazon.ebook', # Amazon Kindle eBook format
  '.bin': 'application/octet-stream', # Any kind of binary data
  '.bmp': 'image/bmp', # Windows OS/2 Bitmap Graphics
  '.bz': 'application/x-bzip', # BZip archive
  '.bz2': 'application/x-bzip2', # BZip2 archive
  '.csh': 'application/x-csh', # C-Shell script
  '.css': 'text/css', # Cascading Style Sheets (CSS)
  '.csv': 'text/csv', # Comma-separated values (CSV)
  '.doc': 'application/msword', # Microsoft Word
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', # Microsoft Word (OpenXML)
  '.eot': 'application/vnd.ms-fontobject', # MS Embedded OpenType fonts
  '.epub': 'application/epub+zip', # Electronic publication (EPUB)
  '.gz': 'application/gzip', # GZip Compressed Archive
  '.gif': 'image/gif', # Graphics Interchange Format (GIF)
  '.htm': 'text/html', # HyperText Markup Language (HTML)
  '.ico': 'image/vnd.microsoft.icon', # Icon format
  '.ics': 'text/calendar', # iCalendar format
  '.jar': 'application/java-archive', # Java Archive (JAR)
  '.jpg': 'image/jpeg', # JPEG images
  '.js': 'text/javascript', # JavaScript
  '.json': 'application/json', # JSON format
  '.jsonld': 'application/ld+json', # JSON-LD format
  '.mid': 'audio/midi', # Musical Instrument Digital Interface (MIDI) audio/x-midi
  '.mjs': 'text/javascript', # JavaScript module
  '.mp3': 'audio/mpeg', # MP3 audio
  '.mpeg': 'video/mpeg', # MPEG Video
  '.mpkg': 'application/vnd.apple.installer+xml', # Apple Installer Package
  '.odp': 'application/vnd.oasis.opendocument.presentation', # OpenDocument presentation document
  '.ods': 'application/vnd.oasis.opendocument.spreadsheet', # OpenDocument spreadsheet document
  '.odt': 'application/vnd.oasis.opendocument.text', # OpenDocument text document
  '.oga': 'audio/ogg', # OGG audio
  '.ogv': 'video/ogg', # OGG video
  '.ogx': 'application/ogg', # OGG
  '.opus': 'audio/opus', # Opus audio
  '.otf': 'font/otf', # OpenType font
  '.png': 'image/png', # Portable Network Graphics
  '.pdf': 'application/pdf', # Adobe Portable Document Format (PDF)
  '.php': 'application/php', # Hypertext Preprocessor (Personal Home Page)
  '.ppt': 'application/vnd.ms-powerpoint', # Microsoft PowerPoint
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation', # Microsoft PowerPoint (OpenXML)
  '.py': 'text/plain',
  '.rar': 'application/vnd.rar', # RAR archive
  '.rb': 'text/plain',
  '.rtf': 'application/rtf', # Rich Text Format (RTF)
  '.sh': 'application/x-sh', # Bourne shell script
  '.svg': 'image/svg+xml', # Scalable Vector Graphics (SVG)
  '.swf': 'application/x-shockwave-flash', # Small web format (SWF) or Adobe Flash document
  '.tar': 'application/x-tar', # Tape Archive (TAR)
  '.tif': 'image/tiff', # Tagged Image File Format (TIFF)
  '.ts': 'video/mp2t', # MPEG transport stream
  '.ttf': 'font/ttf', # TrueType Font
  '.txt': 'text/plain', # Text, (generally ASCII or ISO 8859-n)
  '.vsd': 'application/vnd.visio', # Microsoft Visio
  '.wav': 'audio/wav', # Waveform Audio Format
  '.weba': 'audio/webm', # WEBM audio
  '.webm': 'video/webm', # WEBM video
  '.webp': 'image/webp', # WEBP image
  '.woff': 'font/woff', # Web Open Font Format (WOFF)
  '.woff2': 'font/woff2', # Web Open Font Format (WOFF)
  '.xhtml': 'application/xhtml+xml', # XHTML
  '.xls': 'application/vnd.ms-excel', # Microsoft Excel
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', # Microsoft Excel (OpenXML)
  '.xml': 'application/xml', # XML
  '.xul': 'application/vnd.mozilla.xul+xml', # XUL
  '.zip': 'application/zip', # ZIP archive
  '.3gp': 'video/3gpp', # 3GPP audio/video container audio/3gpp if it doesn't contain video
  '.3g2': 'video/3gpp2', # 3GPP2 audio/video container audio/3gpp2 if it doesn't contain video
  '.7z': 'application/x-7z-compressed' # 7-zip archive
}

P.convert.mime = (fn) ->
  fn ?= @params.fn ? @params.mime ? @params.filename ? @params.file
  # plus some programming languages with text/plain, useful for filtering on filenames
  tp = (if fn.indexOf('.') is -1 then fn else fn.substr(fn.lastIndexOf('.')+1)).toLowerCase()
  tp = 'htm' if tp is 'html'
  tp = 'jpg' if tp is 'jpeg'
  tp = 'tif' if tp is 'tiff'
  tp = 'mid' if tp is 'midi'
  mime = P.convert._mimes['.'+tp]
  return if typeof mime is 'string' then mime else false

P.convert.stream2txt = (stream) ->
  chunks = []
  return new Promise (resolve, reject) =>
    stream.on 'data', (chunk) => chunks.push Buffer.from chunk
    stream.on 'error', (err) => reject err
    stream.on 'end', () => resolve Buffer.concat(chunks).toString 'utf8'
