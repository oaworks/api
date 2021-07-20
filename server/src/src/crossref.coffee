
P.src.crossref ?= {}

P.src.crossref._load = () ->
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

  filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
  files = -1 # max number of files to process. set to -1 to keep going
  howmany = -1 # max number of records to process. set to -1 to keep going
  batchsize = 15000 # how many records to batch upload at a time

  batch = [] # batch of json records to upload
  done = 0

  try filenumber = parseInt (await fs.readFile lastfile).toString()

  console.log 'Starting at file number ' + filenumber
  
  while filenumber isnt -1 and (files is -1 or filenumber <= files)
    try
      content = await @convert._gz2txt infolder + filenumber + '.json.gz'
      console.log 'File number ' + filenumber + ', done ' + done + ', batch size ' + batch.length + ', content length ' + content.length
      recs = JSON.parse content
      lp = 0
      for rec in recs.items
        if howmany is -1 or done < howmany
          done += 1
          lp += 1
          rec = await @src.crossref.works._prep rec
          rec['srcfile'] = filenumber
          rec['srcidx'] = lp
          batch.push rec
          if batch.length >= batchsize
            await @src.crossref.works batch
            await fs.writeFile lastfile, filenumber
            batch = []
      filenumber += 1
    catch
      filenumber = -1

  if batch.length
    @src.crossref.works batch
    batch = []

