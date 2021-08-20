
P.src.crossref ?= {}

P.src.crossref.load = () ->
  batchsize = 20000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  # https://www.crossref.org/blog/new-public-data-file-120-million-metadata-records/
  # https://academictorrents.com/details/e4287cb7619999709f6e9db5c359dda17e93d515
  # this requires getting the crossref data dump from a torrent, which is a hassle on some commercial cloud providers
  # but once the file is on disk, extract it and this process will be able to go from there
  # there are torrent libs for node that could be used here, but given the infrequency and size of what we want 
  # to torrent, it's safer to do that step separately. Here's some simple instructions for the Jan 2021 crossref release:
  # sudo apt-get install aria2
  # aria2c https://academictorrents.com/download/e4287cb7619999709f6e9db5c359dda17e93d515.torrent
  infolder = '/mnt/volume_nyc3_01/crossref/crossref_public_data_file_2021_01/'
  lastfile = '/mnt/volume_nyc3_01/crossref/last' # where to record the ID of the last file processed
  
  files = -1 # max number of files to process. set to -1 to keep going
  filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
  try filenumber = parseInt((await fs.readFile lastfile).toString()) if not @refresh

  await @src.crossref.works('') if filenumber is 0

  total = 0
  batch = [] # batch of json records to upload

  while filenumber >= 0 and filenumber isnt files
    break if total is howmany
    try
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
    catch
      filenumber = -1

  await @src.crossref.works(batch) if batch.length

  console.log total
  return total

P.src.crossref.load._async = true
P.src.crossref.load._auth = 'root'
