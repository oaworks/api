
#P.convert ?= {}

# svg2png (avoiding the canvas and canvg problem on newer ubuntu where libgif4 won't run - and has to be backend)
# pdf2txt in a way that doesn't suck

'''
# xlsx has lots more useful options that could be used to get particular parts of sheets. See:
# https://www.npmjs.com/package/xlsx
P.convert._excel2 = (what='csv', workbook, opts={}) ->
  try
    res = xlsx.utils['sheet_to_' + what] workbook # this works if just one simple sheet
  catch
    sheets = workbook.SheetNames # this works if it is a sheet with names
    opts.sheet ?= sheets[0]
    res = xlsx.utils['sheet_to_' + what] workbook.Sheets[opts.sheet]
  res = res.split('<body>')[1].split('</body>')[0] if what is 'html'
  return res
P.convert.excel2csv = (workbook, opts) ->
  return P.convert._excel2 'csv', workbook, opts

P.convert.file2txt = (content, opts={}) ->
  # NOTE for this to work, see textract on npm - requires other things (antiword for word docs) installed. May not be useful.
  opts.from = undefined if typeof opts.from is 'string' and opts.from.indexOf('/') is -1 # need a proper mime type here
  from = opts.from
  delete opts.from
  named = opts.name ? false
  delete opts.name
  if named and not from
    mime = P.convert.mime named
    if mime
      from = mime
      named = false
  from ?= 'application/msword'
  try
    if typeof content is 'string' and content.indexOf('http') is 0
      textract.fromUrl content, opts, ( err, result ) ->
        return result
    else if named
      if typeof content is 'string'
        content = new Buffer content
      textract.fromBufferWithName named, content, opts, ( err, result ) ->
        return result
    else
      if typeof content is 'string'
        content = new Buffer content
      textract.fromBufferWithMime from, content, opts, ( err, result ) ->
        return result
  catch
    return ''

'''