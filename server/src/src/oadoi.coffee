
P.src.oadoi.load = () ->
  await @src.oadoi('') if @params._delete

  batchsize = @params.batchsize ? @params.batch ? 20000 # how many records to batch upload at a time
  howmany = @params.howmany ? @params.size ? -1 # max number of lines to process. set to -1 to keep going

  infile = '/mnt/volume_nyc3_01/oadoi/18022021.jsonl' # where the lines should be read from
  lastfile = '/mnt/volume_nyc3_01/oadoi/last' # where to record the ID of the last item read from the file
  if not @refresh
    try lastrecord = (await fs.readFile lastfile).toString()

  total = 0
  batch = []

  _lines = (path) =>
    readline.createInterface 
      input: fs.createReadStream(path) #.pipe zlib.createGunzip()
      crlfDelay: Infinity

  for await line from _lines infile
    line = line.trim()
    if line.startsWith '{'
      line = line.replace(/\,$/, '') if line.endsWith ','
      rec = false
      try rec = JSON.parse line
      if typeof rec is 'object' and (not lastrecord? or lastrecord is rec.id) # is there an ID for oadoi dumps? maybe just DOI?
        lastrecord = undefined
        if total is howmany
          console.log 'reached limit', howmany
          break
          
        batch.push await rec
        if batch.length > batchsize
          console.log 'bulk loading', batch.length, total
          await @src.oadoi batch
          batch = []
          await fs.writeFile lastfile, rec.id

        total += 1

  if batch.length
    await @src.oadoi batch
    batch = []
    
  return total

P.src.oadoi.load._async = true
P.src.oadoi.load._auth = 'root'
