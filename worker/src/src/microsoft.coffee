
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
    return {total: res.webPages.totalEstimatedMatches, data: res.webPages.value}
  else
    return {total: 0, data: []}



P.src.microsoft.graph = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.journal = _prefix: false, _index: true
P.src.microsoft.graph.author = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.affiliation = _prefix: false, _index: true
P.src.microsoft.graph.urls = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.abstract = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.relation = _prefix: false, _index: settings: number_of_shards: 12

P.src.microsoft.graph.paper = (q) -> # can be a search or a record to get urls and relations for
  url_source_types = # defined by MAG
    '1': 'html'
    '2': 'text'
    '3': 'pdf'
    '4': 'doc'
    '5': 'ppt'
    '6': 'xls'
    '8': 'rtf'
    '12': 'xml'
    '13': 'rss'
    '20': 'swf'
    '27': 'ics'
    '31': 'pub'
    '33': 'ods'
    '34': 'odp'
    '35': 'odt'
    '36': 'zip'
    '40': 'mp3'

  if @params.title and not q
    return @src.microsoft.graph.paper.title()

  q = @params.q ? @params.paper ? @params
  res = if typeof q is 'object' and q.PaperId and q.Rank then q else await @src.microsoft.graph q
  for r in (res?.hits?.hits ? (if res then [res] else []))
    #if ma = await @src.microsoft.graph.abstract r._source.PaperId, 1
    #  r._source.abstract = ma
    try
      urlres = await @src.microsoft.graph.urls 'PaperId:"' + r._source.PaperId + '"' # don't bother for-looping these because result size should be low, and saves on creating and deleting a scrol context for every one
      for ur in urlres.hits.hits
        r._source.url ?= []
        puo = url: ur._source.SourceUrl, language: ur._source.LanguageCode
        try puo.type = url_source_types[ur._source.SourceType.toString()]
        r._source.url.push puo
    try
      rres = await @src.microsoft.graph.relation 'PaperId:"' + r._source.PaperId + '"', 100 # 100 authors should be enough...
      for rr in rres.hits.hits
        if rr._source.AuthorId # which it seems they all do, along with OriginalAuthor and OriginalAffiliation
          r._source.author ?= []
          r._source.author.push name: rr._source.OriginalAuthor, sequence: rr._source.AuthorSequenceNumber, id: rr._source.AuthorId, affiliation: {name: rr._source.OriginalAffiliation, id: rr._source.AffiliationId}
    
  return res
  

P.src.microsoft.graph.title = (q) ->
  q ?= @params.title ? @params.q
  if typeof q is 'string'
    title = q.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim() # MAG PaperTitle is lowercased. OriginalTitle isnt
    res = await @src.microsoft.graph 'PaperTitle:"' + title + '"', 1
    res = res.hits.hits[0]?._source if res?.hits?.hits
    if res?.PaperTitle
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      if typeof this?.tdm?.levenshtein is 'function'
        lvs = await @tdm.levenshtein title, rt, false
        longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
        if lvs.distance < 2 or longest/lvs.distance > 10
          return @src.microsoft.graph.paper res
      else if title.length < (rt.length * 1.2) and (title.length > rt.length * .8)
        return @src.microsoft.graph.paper res
  return
