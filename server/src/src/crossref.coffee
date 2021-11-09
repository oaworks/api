
P.src.crossref ?= {}

P.src.crossref.load = () ->
  batchsize = 30000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  # https://www.crossref.org/blog/new-public-data-file-120-million-metadata-records/
  # https://academictorrents.com/details/e4287cb7619999709f6e9db5c359dda17e93d515
  # this requires getting the crossref data dump from a torrent, which is a hassle on some commercial cloud providers
  # but once the file is on disk, extract it and this process will be able to go from there
  # there are torrent libs for node that could be used here, but given the infrequency and size of what we want 
  # to torrent, it's safer to do that step separately. Here's some simple instructions for the Jan 2021 crossref release:
  # sudo apt-get install aria2
  # aria2c https://academictorrents.com/download/e4287cb7619999709f6e9db5c359dda17e93d515.torrent
  infolder = @S.directory + '/crossref/crossref_public_data_file_2021_01/'
  lastfile = @S.directory + '/crossref/last' # where to record the ID of the last file processed
  
  files = -1 # max number of files to process. set to -1 to keep going
  filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
  try filenumber = parseInt((await fs.readFile lastfile).toString()) if not @refresh

  #await @src.crossref.works('') if filenumber is 0

  total = 0
  batch = [] # batch of json records to upload

  while filenumber >= 0 and filenumber isnt files and filenumber < 40229 # there are 40228 in the 2020 data dump,  but oddly 9999 is missing in our set
    if filenumber not in [9999] # should make this a file exists check probably
      break if total is howmany
      console.log 'Crossref load starting file', filenumber
      lines = ''
      for await line from readline.createInterface input: fs.createReadStream(infolder + filenumber + '.json.gz').pipe zlib.createGunzip()
        lines += line
      
      for rec in JSON.parse(lines).items
        break if total is howmany
        total += 1
        rec = await @src.crossref.works._format rec
        rec['srcfile'] = filenumber
        batch.push rec
        
        if batch.length is batchsize
          console.log 'Crossref load ' + filenumber, total
          await @src.crossref.works batch
          await fs.writeFile lastfile, filenumber
          batch = []
    filenumber += 1

  await @src.crossref.works(batch) if batch.length

  console.log total
  return total

P.src.crossref.load._async = true
P.src.crossref.load._auth = 'root'



P.src.crossref.changes = (startday) ->
  batchsize = 20000
  startday ?= @params.changes
  if not startday
    try
      last = await @src.crossref.works 'srcday:*', size: 1, sort: srcday: 'desc'
      startday = last.srcday
  startday ?= 1607126400000 # the timestamp of when changes appeared to start after the last data dump, around 12/12/2020
  dn = Date.now()
  loaded = 0
  days = 0
  batch = []
  while startday < dn
    console.log 'Crossref changes', startday, days
    cursor = '*' # set a new cursor on each index day query
    days += 1
    totalthisday = false
    fromthisday = 0
    while totalthisday is false or fromthisday < totalthisday
      await @sleep 500
      thisdays = await @src.crossref.works.search undefined, cursor, 1000, undefined, startday, startday # using same day for crossref API gets that whole day
      if not thisdays?.data
        console.log 'crossref error'
        await @sleep 2000 # wait on crossref downtime
      else
        for rec in thisdays.data
          fr = await @src.crossref.works._format rec
          fr.srcday = startday
          batch.push fr
          loaded += 1
        if batch.length >= batchsize
          console.log 'Crossref bulk load', startday, days, totalthisday, fromthisday, loaded
          await @src.crossref.works batch
          batch = []
        if totalthisday is false
          totalthisday = thisdays.total ? 0
          console.log startday, totalthisday
        fromthisday += 1000
        cursor = thisdays.cursor
    startday += 86400000

  await @src.crossref.works(batch) if batch.length
  
  console.log loaded, days
  return loaded

P.src.crossref.changes._async = true
P.src.crossref.changes._auth = 'root'
P.src.crossref.changes._notify = false
