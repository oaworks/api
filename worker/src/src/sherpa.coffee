
try S.svc.sherpa = JSON.parse SECRETS_SHERPA

P.src.sherpa = {}

P.src.sherpa.opendoar = _index: true, _prefix: false

# https://v2.sherpa.ac.uk/api/object-retrieval.html
P.src.sherpa.opendoar.import = () ->
  @src.sherpa.opendoar ''
  recs = []
  counter = 0
  offset = 0
  while res = await @fetch 'https://v2.sherpa.ac.uk/cgi/retrieve?api-key=' + @S.svc.sherpa.apikey + '&item-type=repository&format=Json&offset=' + offset
    break if not res?.items? or not res.items.length
    console.log offset, counter, res.items.length
    offset += 100 # opendoar returns 100 at a time by default, and that is also the max
    for rec in res.items
      counter += 1
      recs.push rec
      if recs.length is 2000
        await @src.sherpa.opendoar recs
        recs = []
  if recs.length
    await @src.sherpa.opendoar recs
  return counter

P.src.sherpa.opendoar.import._hide = true