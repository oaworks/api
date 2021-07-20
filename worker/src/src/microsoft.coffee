
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


# https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
# We get files via MS Azure dump and run an import script. Have to manually go to 
# Azure, use storage explorer to find the most recent blob container, select the file(s)
# to download, right click and select shared access signature, create it, copy it, and download that.
# THEN DELETE THE BLOB BECAUSE THEY CHARGE US FOR EVERY CREATION, EVERY DOWNLOAD, AND STORAGE TIME FOR AS LONG AS IT EXISTS
# Fields we get are:
# 'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
# 'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate'],
# 'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate'],
# 'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
# of about 49k journals about 9 are dups, 37k have ISSN. 32k were already known from other soruces. Of about 250m papers, about 99m have DOIs
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
          return undefined
      else if title.length < (rt.length * 1.2) and (title.length > rt.length * .8)
        #res.relation = await @src.microsoft.graph._relations res.PaperId
        return res
    return undefined
  else
    return await @src.microsoft.graph.paper q
  

P.src.microsoft.graph.paper = (q) ->
  # for now just get from old index
  url = 'https://dev.api.cottagelabs.com/use/microsoft/graph/paper/?q=' + q
  res = await @fetch url
  return if res?.hits?.total then res.hits.hits[0]._source else undefined

P.src.microsoft.graph.journal = (q) ->
  # for now just get from old index
  url = 'https://dev.api.cottagelabs.com/use/microsoft/graph/journal/' + q
  res = await @fetch url
  return res


'''
P.src.microsoft.graph.paper = _index: true
P.src.microsoft.graph.journal = _index: true
P.src.microsoft.graph.author = _index: true
P.src.microsoft.graph.affiliation = _index: true
P.src.microsoft.graph.abstract = _index: true
P.src.microsoft.graph.relation = _index: true
'''


'''
P.src.microsoft.graph._relations = (q, papers=true, authors=true, affiliations=true) ->
 # ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
 # context could be paper, author, affiliation
  results = []
  _append = (recs) ->
    res = []
    recs = [recs] if not Array.isArray recs
    for rec in recs
      rec.paper = await @src.microsoft.graph.paper(rec.PaperId) if rec.PaperId and papers
      rec.author = await @src.microsoft.graph.author(rec.AuthorId) if rec.AuthorId and authors
      rec.affiliation = await @src.microsoft.graph.affiliation(rec.AffiliationId ? rec.LastKnownAffiliationId) if (rec.AffiliationId or rec.LastKnownAffiliationId) and affiliations
      if rec.GridId or rec.affiliation?.GridId
        try rec.ror = await @src.wikidata.grid2ror rec.GridId ? rec.affiliation?.GridId
      res.push rec
      results.push rec
    return res

  if typeof q is 'string' and rel = await @src.microsoft.graph.relation q
    return _append rel
  
  count = 0
  if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'PaperId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('PaperId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'AuthorId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('AuthorId.exact:"' + q + '"')) if cn < 10
  else if typeof q is 'string' and cn = @src.microsoft.graph.relation.count 'AffiliationId.exact:"' + q + '"'
    count += cn
    _append(@src.microsoft.graph.relation.fetch('AffiliationId.exact:"' + q + '"')) if cn < 10

  return results
'''
