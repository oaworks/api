
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


P.src.wikidata.load = (batchsize, howmany, del) ->
  await @src.wikidata('') if del or @params._delete

  batchsize ?= @params.batchsize ? @params.batch ? 20000 # how many records to batch upload at a time
  howmany ?= @params.howmany ? @params.size ? -1 # max number of lines to process. set to -1 to keep going

  # get latest dump from: https://dumps.wikimedia.org/wikidatawiki/entities/
  # e.g. the latst-all.json.gz at about 95gb. Content is a json array, objects each on a new line 
  # read the compressed file line by line and ensure the line is an object, then use it
  infile = '/mnt/volume_nyc3_01/wikidata/latest-all.json.gz' # where the lines should be read from
  lastfile = '/mnt/volume_nyc3_01/wikidata/last' # where to record the ID of the last item read from the file
  if not @refresh
    try lastrecord = (await fs.readFile lastfile).toString()

  total = 0
  batch = []

  _lines = (path) =>
    readline.createInterface 
      input: fs.createReadStream(path).pipe zlib.createGunzip()
      crlfDelay: Infinity

  for await line from _lines infile
    line = line.trim()
    if line.startsWith '{'
      line = line.replace(/\,$/, '') if line.endsWith ','
      rec = false
      try rec = JSON.parse line
      if typeof rec is 'object' and (not lastrecord? or lastrecord is rec.id)
        lastrecord = undefined
        if total is howmany
          console.log 'reached limit', howmany
          break
          
        batch.push await @src.wikidata._format rec
        if batch.length > batchsize
          console.log 'bulk loading', batch.length, total
          await @src.wikidata batch
          batch = []
          await fs.writeFile lastfile, rec.id

        total += 1

  if batch.length
    await @src.wikidata batch
    batch = []
    
  return total

P.src.wikidata.load._async = true
P.src.wikidata.load._auth = 'root'


