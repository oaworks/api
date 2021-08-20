
# can build a local wikidata from dumps
# https://dumps.wikimedia.org/wikidatawiki/entities/latest-all.json.gz
# https://www.mediawiki.org/wiki/Wikibase/DataModel/JSON
# it is about 80gb compressed. Each line is a json object so can uncompress and read line by line then load into an index
# then make available all the usual search operations on that index
# then could try to make a way to find all mentions of an item in any block of text
# and make wikidata searches much faster
# downloading to index machine which has biggest disk takes about 5 hours
# there is also a recent changes API where could get last 30 days changes to items to keep things in sync once first load is done
# to bulk load 5000 every 10s would take about 48 hours

# may also be able to get properties by query
# https://www.wikidata.org/w/api.php?action=wbsearchentities&search=doctoral%20advisor&language=en&type=property&format=json
# gets property ID for string, just need to reverse. (Already have a dump accessible below, but for keeping up to date...)


P.src.wikidata.load = () ->
  batchsize = 20000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  # get latest dump from: https://dumps.wikimedia.org/wikidatawiki/entities/
  # e.g. the latest-all.json.gz at about 95gb. Content is a json array, objects each on a new line 
  # read the compressed file line by line and ensure the line is an object, then use it
  infile = '/mnt/volume_nyc3_01/wikidata/latest-all.json.gz' # where the lines should be read from
  lastfile = '/mnt/volume_nyc3_01/wikidata/last' # where to record the ID of the last item read from the file
  try lastrecord = (await fs.readFile lastfile).toString() if not @refresh

  await @src.wikidata('') if not lastrecord

  total = 0
  batch = []

  for await line from readline.createInterface input: fs.createReadStream(infile).pipe zlib.createGunzip()
    break if total is howmany
    try
      rec = JSON.parse line.trim().replace /\,$/, ''
      if not lastrecord or lastrecord is rec.id
        lastrecord = undefined
        total += 1
        batch.push await @src.wikidata._format rec
        if batch.length is batchsize
          console.log 'bulk loading', batch.length, total
          await @src.wikidata batch
          batch = []
          await fs.writeFile lastfile, rec.id

  await @src.wikidata(batch) if batch.length
  return total

P.src.wikidata.load._async = true
P.src.wikidata.load._auth = 'root'


