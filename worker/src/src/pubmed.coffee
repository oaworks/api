
# there are pubmed data loaders on the server side, they build an index that can 
# be queried directly. However some of the below functions may still be useful 
# for lookups to the pubmed API at other times

# pubmed API http://www.ncbi.nlm.nih.gov/books/NBK25497/
# examples http://www.ncbi.nlm.nih.gov/books/NBK25498/#chapter3.ESearch__ESummaryEFetch
# get a pmid - need first to issue a query to get some IDs...
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?id=21999661&db=pubmed
# then scrape the QueryKey and WebEnv values from it and use like so:
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=1&WebEnv=NCID_1_54953983_165.112.9.28_9001_1461227951_1012752855_0MetA0_S_MegaStore_F_1

P.src.pubmed = _key: 'PMID', _prefix: false, _index: settings: number_of_shards: 6

P.src.pubmed.entrez = {}
P.src.pubmed.entrez.summary = (qk, webenv, id) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed'
  if id?
    id = id.join(',') if Array.isArray id
    url += '&id=' + id # can be a comma separated list as well
  else
    url += '&query_key=' + qk + '&WebEnv=' + webenv
  try
    res = await @fetch url
    md = await @convert.xml2json res
    recs = []
    for rec in md.eSummaryResult.DocSum
      frec = {id:rec.Id[0]}
      for ii in rec.Item
        if ii.$.Type is 'List'
          frec[ii.$.Name] = []
          if ii.Item?
            for si in ii.Item
              sio = {}
              sio[si.$.Name] = si._
              frec[ii.$.Name].push sio
        else
          frec[ii.$.Name] = ii._
      recs.push frec
      if not id? or id.indexOf(',') is -1
        return recs[0]
        break
    return recs
  catch
    return

P.src.pubmed.entrez.pmid = (pmid) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?db=pubmed&id=' + pmid
  try
    res = await @fetch url
    result = await @convert.xml2json res
    return @src.pubmed.entrez.summary result.ePostResult.QueryKey[0], result.ePostResult.WebEnv[0]
  catch
    return

P.src.pubmed.search = (str, full, size=10, ids=false) ->
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmax=' + size + '&sort=pub date&term=' + str
  try
    ids = ids.split(',') if typeof ids is 'string'
    if Array.isArray ids
      res = {total: ids.length, data: []}
    else
      res = await @fetch url
      result = await @convert.xml2json res
      res = {total: result.eSearchResult.Count[0], data: []}
      if ids is true
        res.data = result.eSearchResult.IdList[0].Id
        return res
      else
        ids = result.eSearchResult.IdList[0].Id
    if full # may need a rate limiter on this
      for uid in ids
        pg = await @src.pubmed.pmid uid # should rate limit this to 300ms
        res.data.push pg
        break if res.data.length is size
    else
      urlids = []
      for id in ids
        break if res.data.length is size
        urlids.push id
        if urlids.length is 40
          for rec in await @src.pubmed.entrez.summary undefined, undefined, urlids
            res.data.push await @src.pubmed.format rec
            break if res.data.length is size
          urlids = []
      if urlids.length
        for rec in await @src.pubmed.entrez.summary undefined, undefined, urlids
          res.data.push await @src.pubmed.format rec
          break if res.data.length is size
    return res
  catch
    return

P.src.pubmed.pmid = (pmid) ->
  try
    url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
    res = await @fetch url
    if res.indexOf('<') is 0
      return @src.pubmed.format await @decode res.split('<pre>')[1].split('</pre>')[0].replace('\n','')
  try
    return @src.pubmed.format await @src.pubmed.entrez.pmid pmid
  return

P.src.pubmed.aheadofprint = (pmid) ->
  try
    res = await @fetch 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
    return res.indexOf('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus') isnt -1
  catch
    return

P.src.pubmed.format = (rec, metadata={}) ->
  if typeof rec is 'string' and rec.indexOf('<') is 0
    rec = await @convert.xml2json rec
  if rec.eSummaryResult?.DocSum? or rec.ArticleIds
    frec = {}
    if rec.eSummaryResult?.DocSum?
      rec = md.eSummaryResult.DocSum[0]
      for ii in rec.Item
        if ii.$.Type is 'List'
          frec[ii.$.Name] = []
          if ii.Item?
            for si in ii.Item
              sio = {}
              sio[si.$.Name] = si._
              frec[ii.$.Name].push sio
        else
          frec[ii.$.Name] = ii._
    else
      frec = rec
    try metadata.pmid ?= rec.Id[0]
    try metadata.pmid ?= rec.id
    try metadata.title ?= frec.Title
    try metadata.issn ?= frec.ISSN
    try metadata.essn ?= frec.ESSN
    try metadata.doi ?= frec.DOI
    try metadata.journal ?= frec.FullJournalName
    try metadata.journal_short ?= frec.Source
    try metadata.volume ?= frec.Volume
    try metadata.issue ?= frec.Issue
    try metadata.page ?= frec.Pages #like 13-29 how to handle this
    try metadata.year ?= frec[if frec.PubDate then 'PubDate' else 'EPubDate'].split(' ')[0]
    try
      p = frec[if frec.PubDate then 'PubDate' else 'EPubDate'].split ' '
      metadata.published ?= p[0] + '-' + (['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(p[1].toLowerCase()) + 1) + '-' + (if p.length is 3 then p[2] else '01')
    if frec.AuthorList?
      metadata.author ?= []
      for a in frec.AuthorList
        try
          a.family = a.Author.split(' ')[0]
          a.given = a.Author.replace(a.family + ' ','')
          a.name = a.given + ' ' + a.family
          metadata.author.push a
    if frec.ArticleIds? and not metadata.pmcid?
      for ai in frec.ArticleIds
        if ai.pmc # pmcid or pmc? replace PMC in the value? it will be present
          metadata.pmcid ?= ai.pmc
          break
  else if rec.PubmedArticle?
    rec = rec.PubmedArticle
    mc = rec.MedlineCitation[0]
    try metadata.pmid ?= mc.PMID[0]._
    try metadata.title ?= mc.Article[0].ArticleTitle[0]
    try metadata.issn ?= mc.Article[0].Journal[0].ISSN[0]._
    try metadata.journal ?= mc.Article[0].Journal[0].Title[0]
    try metadata.journal_short ?= mc.Article[0].Journal[0].ISOAbbreviation[0]
    try
      pd = mc.Article[0].Journal[0].JournalIssue[0].PubDate[0]
      try metadata.year ?= pd.Year[0]
      try metadata.published ?= pd.Year[0] + '-' + (if pd.Month then (['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(pd.Month[0].toLowerCase()) + 1) else '01') + '-' + (if pd.Day then pd.Day[0] else '01')
    try
      metadata.author ?= []
      for ar in mc.Article[0].AuthorList[0].Author
        a = {}
        a.family = ar.LastName[0]
        a.given = ar.ForeName[0]
        a.name = (if a.given then a.given + ' ' else '') + (a.family ? '')
        try a.affiliation = ar.AffiliationInfo[0].Affiliation[0]
        if a.affiliation?
          a.affiliation = a.affiliation[0] if Array.isArray a.affiliation
          a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
        metadata.author.push a
    try
      for pid in rec.PubmedData[0].ArticleIdList[0].ArticleId
        if pid.$.IdType is 'doi'
          metadata.doi ?= pid._
          break
    try
      metadata.reference ?= []
      for ref in rec.PubmedData[0].ReferenceList[0].Reference
        rc = ref.Citation[0]
        rf = {}
        rf.doi = rc.split('doi.org/')[1].trim() if rc.indexOf('doi.org/') isnt -1
        try
          rf.author = []
          rf.author.push({name: an}) for an in rc.split('. ')[0].split(', ')
        try rf.title = rc.split('. ')[1].split('?')[0].trim()
        try rf.journal = rc.replace(/\?/g,'.').split('. ')[2].trim()
        try
          rf.url = 'http' + rc.split('http')[1].split(' ')[0]
          delete rf.url if rf.url.indexOf('doi.org') isnt -1 
        metadata.reference.push(rf) if JSON.stringify(rf) isnt '{}'
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  return metadata


