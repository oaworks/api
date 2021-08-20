
S.src.microsoft ?= {}
try S.src.microsoft.secrets = JSON.parse SECRETS_MICROSOFT

P.src.microsoft = {}

# https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
# annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
# and it seems the bing UI is sometimes more accurate
P.src.microsoft.bing = (q, key) ->
  q ?= this?.params?.bing ? this?.params?.q ? this?.params?.query
  key ?= S.src.microsoft?.secrets?.bing?.key
  url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?mkt=en-GB&count=20&q=' + q
  res = await @fetch url, {headers: {'Ocp-Apim-Subscription-Key': key}, cache: 259200} # cache for 3 days
  if res?.webPages?.value
    return {total: res.data.webPages.totalEstimatedMatches, data: res.data.webPages.value}
  else
    return {total: 0, data: []}


P.src.microsoft.graph = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.journal = _prefix: false, _index: true
P.src.microsoft.graph.author = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.affiliation = _prefix: false, _index: true
P.src.microsoft.graph.urls = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.abstract = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.relation = _prefix: false, _index: settings: number_of_shards: 12


'''
P.src.microsoft.graph = (q) ->
  # NOTE: although there are about 250m papers only about 90m have JournalId - the rest could be books, etc. Import them all?
  _append = (rec) ->
    if rec.JournalId
      j = await @src.microsoft.graph.journal rec.JournalId
      if j
        rec.journal = j
    #if ma = await @src.microsoft.graph.abstract rec.PaperId
    #  rec.abstract = ma
    #rec.relation = await @src.microsoft.graph._relations rec.PaperId, false, false
    return rec

  q ?= @params.graph ? @params.doi ? @params.title ? @params
  q = q.toString() if typeof q is 'number' # an MS ID like 2517073914 may turn up as number, if so convert to string
  if typeof q is 'string' and q.indexOf('/') isnt -1 and q.indexOf('10.') is 0 and paper = await @src.microsoft.graph.paper 'Doi.exact:"' + q + '"'
    return await _append paper
  else if typeof q is 'string' and q.indexOf(' ') is -1 and q.length is 10 and paper = await @src.microsoft.graph.paper q
    return await _append paper
  else if typeof q is 'string' and q.indexOf(' ') isnt -1
    title = q.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim() # MAG PaperTitle is lowercased. OriginalTitle isnt
    res = await @src.microsoft.graph.paper 'PaperTitle:"' + title + '"'
    if res?.PaperTitle
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      if typeof this?.tdm?.levenshtein is 'function'
        lvs = await @tdm.levenshtein title, rt, false
        longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
        if lvs.distance < 2 or longest/lvs.distance > 10
          #res.relation = await @src.microsoft.graph._relations res.PaperId
          return res
        else
          return
      else if title.length < (rt.length * 1.2) and (title.length > rt.length * .8)
        #res.relation = await @src.microsoft.graph._relations res.PaperId
        return res
    return
  else
    return await @src.microsoft.graph.paper q
  
P.src.microsoft.graph.paper = (q) ->
  # for now just get from old index
  url = 'https://dev.api.cottagelabs.com/use/microsoft/graph/paper/?q=' + q
  res = await @fetch url
  return if res?.hits?.total then res.hits.hits[0]._source else undefined
'''
