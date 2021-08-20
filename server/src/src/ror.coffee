
# https://ror.readme.io/docs/rest-api
# https://ror.readme.io/docs/data-dump

# data dump comes from:
# https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent
# and within the result object, filename is at hits.hits[0].files[0].links.self
# presumably always the first one?
# it's a zip, once unzipped is a JSON list, and the objects are NOT in jsonlines
# but they are pretty-printed, so risk identify start and end of objects by their whitespacing

P.src.ror.load = () ->
  batchsize = 20000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  infile = '/mnt/volume_nyc3_01/ror/2021-03-25-ror-data.json' # where the lines should be read from
  lastfile = '/mnt/volume_nyc3_01/ror/last' # where to record the ID of the last item read from the file
  try lastrecord = (await fs.readFile lastfile).toString() if not @refresh

  await @src.ror('') if not lastrecord

  total = 0
  batch = []

  startobj = false
  endobj = false
  lobj = ''
  for await line from readline.createInterface input: fs.createReadStream infile
    break if total is howmany
    try
      if not startobj and line.length is 5 and line.replace(/\s\s\s\s/,'') is '{'
        startobj = true
        lobj = '{'
      else if not endobj and line.replace(',', '').length is 5 and line.replace(/\s\s\s\s/,'').replace(',', '') is '}'
        endobj = true
        lobj += '}'
      else if line not in ['[', ']']
        lobj += line
      if startobj is true and endobj is true
        startobj = false
        endobj = false
        rec = await @src.ror._format JSON.parse lobj
        lobj = ''
        if not lastrecord or lastrecord is rec.id
          lastrecord = undefined
          total += 1
          batch.push rec
          if batch.length is batchsize
            console.log 'ROR bulk loading', batch.length, total
            await @src.ror batch
            batch = []
            await fs.writeFile lastfile, rec.id

  await @src.ror(batch) if batch.length
  console.log total
  return total

P.src.ror.load._async = true
P.src.ror.load._auth = 'root'

