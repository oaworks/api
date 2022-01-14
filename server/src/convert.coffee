
P.convert ?= {}

# apt-get install pdftk poppler-utils antiword unoconv #ghostscript tesseract-ocr

P.convert._content2file = (content) ->
  if not content? and (@params.url or @params.content)
    pc = @params.url ? @params.content
    if pc.startsWith('http://') or (not pc.startsWith('/') and not pc.includes '../')
      content = pc
  if typeof content is 'string' and content.startsWith 'http'
    content = await @fetch content, buffer: true
  if not content and @request.files
    file = @request.files[0]
    file = file[0] if Array.isArray file
    content = file.data
  if typeof content isnt 'string' or not content.startsWith '/'
    fuid = '/tmp/' + await @uid()
    await fs.appendFile fuid, content
  return fuid ? content
  
P.convert.doc2txt = (content) ->
  cn = await @convert._content2file content
  txt = await @_child 'antiword', cn
  await fs.unlink(cn) if typeof cn is 'string' and cn.startsWith '/tmp/'
  return txt

P.convert.docx2txt = (content) ->
  cn = await @convert._content2file content
  await @_child 'unoconv', ['-f', 'doc', cn] # unoconv also has a convenience command set up called doc2pdf
  await fs.unlink(cn) if cn.startsWith '/tmp/'
  cn = cn.replace('.docx', '') + '.doc'
  txt = await @convert.doc2txt cn
  try await fs.unlink(cn) if typeof cn is 'string' and cn.startsWith '/tmp/'
  return txt

P.convert.pdf2txt = (content) ->
  cn = await @convert._content2file content
  txt = await @_child 'pdftotext', [cn, '-']
  await fs.unlink(cn) if typeof cn is 'string' and cn.startsWith '/tmp/'
  return txt

'''
P.convert.html2txt = (content, opts) ->
  opts ?= @copy @params
  opts.mime ?= 'text/html'
  return @convert.doc2txt content, opts

P.convert.xml2txt = (content, opts) ->
  opts ?= @copy @params
  opts.mime ?= 'application/xml'
  return @convert.doc2txt content, opts
'''

# TODO add svg2png (avoiding the canvas and canvg problem on newer ubuntu where libgif4 won't run - and has to be backend)
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

'''