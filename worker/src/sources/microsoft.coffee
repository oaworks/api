
S.src.microsoft ?= {}
try S.src.microsoft = JSON.parse SECRETS_MICROSOFT

P.src.microsoft = {}

# https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
# annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
# and it seems the bing UI is sometimes more accurate
P.src.microsoft.bing = (q, key, market, count, cache) ->
  q ?= this?.params?.bing ? this?.params?.q ? this?.params?.query
  key ?= this?.params?.key ? S.src.microsoft.bing?.key
  market ?= this?.params?.market ? 'en-GB'
  count ?= this?.params?.count ? 20
  cache ?= this?.params?.cache ? 259200 # cache for 3 days
  if q? and key?
    url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?'
    url += 'mkt=' + market + '&' if market
    url += 'count=' + count + '&' if count 
    url += 'q=' + q
    res = await @fetch url, {headers: {'Ocp-Apim-Subscription-Key': key}, cache: cache}
    if res?.webPages?.value
      return {total: res.webPages.totalEstimatedMatches, data: res.webPages.value}
  return {total: 0, data: []}
P.src.microsoft.bing._auth = 'root'


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
      lvs = await @levenshtein title, rt, false
      longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
      if lvs.distance < 2 or longest/lvs.distance > 10
        return @src.microsoft.graph.paper res
  return




# https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
# We used to get files via MS Azure dump and run an import script. Have to manually go to 
# Azure, use storage explorer to find the most recent blob container, select the file(s)
# to download, right click and select shared access signature, create it, copy it, and download that.
# THEN DELETE THE BLOB BECAUSE THEY CHARGE US FOR EVERY CREATION, EVERY DOWNLOAD, AND STORAGE TIME FOR AS LONG AS IT EXISTS
# but now the service has been discontinued. Maybe there will be a replacement in future

P.src.microsoft.load = (kinds) ->
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going...

  keys =
    #journal: ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    #affiliation: ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate']
    #author: ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    #relation: ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
    #abstract: ['PaperId', 'Abstract']
    #urls: ['PaperId', 'SourceType', 'SourceUrl', 'LanguageCode']
    paper: ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate']

  kinds ?= if @params.load then @params.load.split(',') else if @params.kinds then @params.kinds.split(',') else @keys keys

  # totals: 49027 journals, 26997 affiliations, 269880467 authors, 699632917 relations, 429637001 urls, 145551658 abstracts (in 2 files), 259102074 papers
  # paper URLs PaperId is supposedly a Primary Key but there are clearly many more of them than Papers...
  # of other files not listed here yet: 1726140322 paper references
  # of about 49k journals about 9 are dups, 37k have ISSN. 32k were already known from other soruces. Of about 250m papers, about 99m have DOIs
  infolder = @S.directory + '/mag/2021-04-26/' # where the lines should be read from
  lastfile = @S.directory + '/mag/last' # prefix of where to record the ID of the last item read from the kind of file
  
  total = 0
  blanks = 0
  done = not @params.parallel
  ds = {}
  
  paper_journal_count = 0
  paper_journal_lookups = {} # store these in memory when loading papers as they're looked up because there aren't many and it will work out faster than searching every time
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

  _loadkind = (kind) =>
    console.log 'MAG loading', kind
    batchsize = if kind in ['abstract'] then 20000 else if kind in ['relation'] then 75000 else if kind in ['urls'] then 100000 else 50000 # how many records to batch upload at a time
    batch = []
    kindlastfile = lastfile + '_' + kind
    kindtotal = 0
    try lastrecord = parseInt((await fs.readFile kindlastfile).toString().split(' ')[0]) if not @refresh

    if lastrecord isnt 'DONE'
      if not lastrecord
        if kind is 'paper'
          await @src.microsoft.graph ''
        else
          await @src.microsoft.graph[kind] ''
      
      infile = (if kind in ['urls'] then infolder.replace('2021-04-26/', '') else infolder) + (if kind is 'relation' then 'PaperAuthorAffiliations.txt' else (if kind in ['urls'] then 'Paper' else '') + kind.substr(0,1).toUpperCase() + kind.substr(1) + (if kind in ['urls'] then '' else 's') + '.txt')

      for await line from readline.createInterface input: fs.createReadStream infile
        kindtotal += 1
        break if total is howmany
        vals = line.split '\t'
        try console.log(kind, 'waiting', kindtotal, lastrecord) if lastrecord and not (kindtotal/100000).toString().includes '.'
        if not lastrecord or kindtotal is lastrecord or parseInt(vals[0]) is lastrecord
          lastrecord = undefined
          total += 1
          kc = 0
          obj = {}
          if kind not in ['relation', 'urls']
            obj._id = vals[0]
            try obj._id = obj._id.trim()
            delete obj._id if not obj._id # there appear to be some blank lines so skip those
          if obj._id or kind in ['relation', 'urls']
            if kind is 'abstract'
              try
                obj.PaperId = parseInt vals[0]
                ind = JSON.parse vals[1]
                al = []
                al.push('') while al.length < ind.IndexLength
                for k in ind.InvertedIndex
                  for p in ind.InvertedIndex[k]
                    al[p] = k
                obj.Abstract = al.join(' ').replace /\n/g, ' '
            else
              for key in keys[kind]
                vs = vals[kc]
                try vs.trim()
                obj[key] = vs if vs and key not in ['NormalizedName']
                if key in ['Rank', 'AuthorSequenceNumber', 'Year', 'EstimatedCitation', 'FamilyRank', 'SourceType'] or key.endsWith('Count') or key.endsWith 'Id'
                  try
                    psd = parseInt obj[key]
                    obj[key] = psd if not isNaN psd
                kc += 1
            if kind is 'paper'
              if obj.JournalId
                try
                  js = obj.JournalId.toString()
                  if jrnl = paper_journal_lookups[js]
                    obj.journal = title: jrnl.DisplayName, ISSN: jrnl.Issn.split(','), url: jrnl.Webpage, id: obj.JournalId
                  else if jrnl = await @src.microsoft.graph.journal js
                    paper_journal_lookups[js] = jrnl
                    paper_journal_count += 1
                    console.log paper_journal_count
                    obj.journal = title: jrnl.DisplayName, ISSN: jrnl.Issn.split(','), url: jrnl.Webpage

          if JSON.stringify(obj) isnt '{}' # readline MAG author dump somehow managed to cause blank rows even though they couldn't be found in the file, so skip empty records
            batch.push obj
          else
            blanks += 1
  
        if batch.length is batchsize
          console.log kind, total, kindtotal, blanks
          if kind is 'paper'
            await @src.microsoft.graph batch
          else
            batched = await @src.microsoft.graph[kind] batch
            console.log 'batch returned', batched # should be the count of how many were successfully saved
          await fs.writeFile kindlastfile, kindtotal + ' ' + vals[0]
          batch = []
  
      if batch.length
        if kind is 'paper'
          await @src.microsoft.graph batch 
        else
          await @src.microsoft.graph[kind] batch
      await fs.writeFile kindlastfile, 'DONE'
    ds[k] = true

  for k in kinds
    if @params.parallel
      if k isnt 'paper'
        ds[k] = false
        _loadkind k
    else
      await _loadkind k

  while not done
    done = true
    for d of ds
      done = false if ds[d] is false
    if done and 'paper' in kinds
      await _loadkind 'paper'
    await @sleep 1000

  console.log total, blanks
  return total

P.src.microsoft.load._bg = true
P.src.microsoft.load._async = true
P.src.microsoft.load._auth = 'root'

