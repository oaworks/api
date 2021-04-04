
P.convert = {}

P.convert.json2csv = (recs) ->
  recs ?= @body ? @params
  if @params.url
    recs = await @fetch url
  es = false
  try
    if recs?.hits?.hits?
      es = true
      recs = recs.hits.hits
  recs = [recs] if not Array.isArray recs
  quote = '"'
  separator = ','
  newline = '\n'
  if not recs.length
    return ''
  else
    headers = [] # is it useful to allow provision of default headers/fields?
    records = ''
    for rec in recs
      if es is true and (rec._source or rec.fields)
        rec = rec._source ? rec.fields
      if @params.subset
        rec = rec[@params.subset]
      if @params.flatten
        rec = await @flatten rec
      for k of rec
        headers.push(k) if rec[k]? and k not in headers
      for h in headers
        records += separator if records.endsWith quote
        records += quote
        try
          for val in (if Array.isArray(rec[h]) then rec[h] else [rec[h]])
            if val? and val isnt ''
              records += ', ' if not records.endsWith quote
              try
                val = JSON.stringify(val).replace(/^"/, '').replace(/"$/, '')
              # TODO escape any instances of quote in v with a regex replace
              val = val.replace /"/g, '\\"'
              records += val
        records += quote
      records += newline if records.length
    return quote + headers.join(quote + separator + quote) + quote + '\n' + records

P.convert.csv2json = (csv) ->
  csv ?= @body ? @params.csv
  if @params.url
    csv = await @fetch url
  quote = '"'
  separator = ','
  newline = '\n'
  csv = csv.replace /\\"/g, 'XXX_QUOTER_GOES_HERE_XXX'
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
        res.push row
  return res

P.convert.csv2html = (csv) ->
  csv ?= @body ? @params.csv
  if @params.url
    csv = await @fetch url
  quote = '"'
  separator = ','
  newline = '\n'
  csv = csv.replace /\\"/g, 'XXX_QUOTER_GOES_HERE_XXX'
  res = '<table style="border:1px solid #ccc; border-collapse: collapse;">'
  if typeof csv is 'string' and csv.length
    lines = csv.split newline
    if lines.length
      res += '<thead><tr>'
      headers = lines.shift()
      for header in headers.split quote + separator
        header = header.replace(quote, '') if header.indexOf(quote) is 0
        res += '<th style="padding:2px; border:1px solid #ccc;">' + header + '</th>'
      res += '</tr></thead><tbody>'
      for line in lines
        res += '<tr>'
        for v in line.split quote + separator
          res += '<td style="padding:2px; border:1px solid #ccc;">'
          if v
            v = v.replace(/^"/, '').replace(/"$/, '')
            res += v.replace(/\</g, '&lt;').replace(/\>/g, '&gt;')
          res += '</td>' # add a regex replace of the separator, avoiding escaped instances
        res += '</tr>'
      res += '</tbody>'
  res = res.replace /XXX_QUOTER_GOES_HERE_XXX/g, quote
  return res + '</table>'

P.convert.json2html = (recs) ->
  recs ?= @body ? @params
  if @params.url
    recs = await @fetch url
  if Array.isArray recs
    return @convert.csv2html await @convert.json2csv recs
  else
    res = '<div>'
    if @params.subset
      recs = recs[@params.subset]
      res += '<h3>' + @params.subset + ':</h3>'
      res += '<input type="hidden" id="options_subset" value="' + @params.subset + '">'
    if @params.flatten
      recs = await @flatten recs
      res += '<input type="hidden" id="options_flatten" value="true">'
    _draw = (rec) =>
      for k of rec
        if rec[k]? and rec[k] isnt '' and (not Array.isArray(rec[k]) or rec[k].length)
          res += '<div style="clear:both; border:1px solid #ccc; margin:-1px 0px;"><div style="float:left;width: 150px; overflow: scroll;"><b><p>' + k + '</p></b></div>'
          res += '<div style="float:left;">'
          res += if @params.edit then '<textarea id="' + k + '" style="min-height:100px;width:100%;">' else ''
          if Array.isArray rec[k]
            if typeof rec[k][0] is 'object'
              for ok in rec[k]
                _draw ok
            else if typeof rec[k][0] is 'string'
              res += (if @params.edit then '' else '<p>') + rec[k].join(', ') + (if @params.edit then '' else '</p>')
            else
              res += (if @params.edit then '' else '<p>') + JSON.stringify(rec[k]) + (if @params.edit then '' else '</p>')
          else if typeof rec[k] is 'object'
            _draw rec[k]
          else if typeof rec[k] is 'string'
            res += (if @params.edit then '' else '<p>') + rec[k] + (if @params.edit then '' else '</p>')
          else
            res += (if @params.edit then '' else '<p>') + JSON.stringify(rec[k]) + (if @params.edit then '' else '</p>')
          res += if @params.edit then '</textarea>' else ''
          res += '</div></div>'
    _draw recs
    if @params.edit
      res += '' # TODO add a save button, or notify that login is required - and some js to POST the altered data
    return res + '</div>'

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

