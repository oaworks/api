
# there are pubmed data loaders on the server side, they build an index that can 
# be queried directly. However some of the below functions may still be useful 
# for lookups to the pubmed API at other times

# pubmed API http://www.ncbi.nlm.nih.gov/books/NBK25497/
# examples http://www.ncbi.nlm.nih.gov/books/NBK25498/#chapter3.ESearch__ESummaryEFetch
# get a pmid - need first to issue a query to get some IDs...
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?id=21999661&db=pubmed
# then scrape the QueryKey and WebEnv values from it and use like so:
# http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=1&WebEnv=NCID_1_54953983_165.112.9.28_9001_1461227951_1012752855_0MetA0_S_MegaStore_F_1

# NOTE: interestingly there are things in pubmed with PMC IDs that are NOT in EPMC, they return 
# nothing in the epmc website or API. For example PMID 33685375 has PMC7987225 and DOI 10.2989/16085906.2021.1872664
# (the crossref record has no PMID or PMC in it, but the pubmed record has all)

# NOTE also there are items in pubmed with identifier.pmc which seem fine but some have
# identifier.pmcid which may NOT be fine. e.g. PMID 31520348 shows a pmc ID of 6156939
# but in PMC that is a DIFFERENT article. The DOI provided in pubmed matches the correct 
# article in EPMC, which is not an article in PMC.
P.src.pubmed = _key: 'PMID', _prefix: false, _index: settings: number_of_shards: 6

P.src.pubmed.doi = (doi) ->
  doi ?= @params.doi
  if doi and found = await @src.pubmed 'identifier.doi:"' + doi + '"', 1
    return found
  return

P.src.pubmed.pmc = (pmc) ->
  pmc ?= @params.pmc
  if pmc and found = await @src.pubmed 'identifier.pmc:"PMC' + pmc.toString().toLowerCase().replace('pmc','') + '"', 1
    return found
  return

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

P.src.pubmed.availabilities = _sheet: '1ZQa6tOqFsm_nF3XUk9-FhDk5gmVtXeRC4I3uldDl-gM/Export', _prefix: false, _key: 'PMC'
P.src.pubmed.availability = (pmcid) ->
  pmcid ?= @params.pubmed ? @params.availability ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  pmcid = 'pmc' + (pmcid + '').toLowerCase().replace('pmc', '')
  if exists = await @src.pubmed.availabilities pmcid
    return true
  else
    return false

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




# https://www.nlm.nih.gov/databases/download/pubmed_medline.html
# https://www.nlm.nih.gov/bsd/licensee/2021_stats/2021_LO.html

# in case the medline data does not include all PMCs or PMIDs, there is a converter API
# and/or PMC sources that could be used to map things (with just over 6 million PMC IDs in the pubmed 
# data, looks like probably all PMC articles were in the data dump anyway)
# https://www.ncbi.nlm.nih.gov/pmc/tools/id-converter-api/
# https://www.ncbi.nlm.nih.gov/pmc/tools/ftp/

# annual files published each December, listed at: https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/
# lists files such as https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/pubmed21n0001.xml.gz
# up to 1062 for 2020. Contains other files including .md5 files for each gz file
# Managed to load 31847922
# PMID 30036026 failed with a “published” value of 1-01-01

# daily update files listed at https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/
# such as https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/pubmed21n1063.xml.gz
# can contain one or more files for each day since the last annual file dump

P.src.pubmed.load = (changes) ->
  # there are 30k or less records per pubmed file so tried batching by file, but streaming more than one file at a time caused OOM
  # so reduce batch size if necessary. default node heap size is 1400M I think, so increased to 3072M and try again
  # check if increasing heap that machine running it has enough - AND note that on production if using PM2 to run as cluster, then 
  # need enough memory for each process to max out. Running 3 with 15k batch size was stable but reaching almost 3000M at times and 
  # didn't seem much faster, so now set to do whole files as batches with two streamers at a time, see how that goes
  batchsize = -1 # how many records to batch upload at a time
  streamers = 1 # how many files to stream at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going...

  await @src.pubmed('') if @refresh and not changes

  addr = if changes then 'https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/' else 'https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/'
  files = []
  listing = await @fetch addr
  for a in listing.split 'href="'
    f = a.split('"')[0]
    if f.startsWith('pubmed') and f.endsWith('.gz') and ((@refresh and not changes) or not exists = await @src.pubmed.count 'srcfile:"' + addr + f + '"')
      files.push addr + f

  running = 0
  total = 0

  _loop = (fn) =>
    console.log 'Pubmed loading' + (if changes then ' changes' else ''), fn, files.length, running

    # stream them, unzip, and parse line by line, processing each record once a full record has been parsed out
    # the first 2020 gz file for example is 19M, uncompressed it is 182M. 30k records or so per file
    batch = []
    rec = {}
    published = false
    ininv = false
    for await line from readline.createInterface input: (await fetch fn).body.pipe zlib.createGunzip()
      if batchsize > 0 and batch.length >= batchsize
        await @src.pubmed batch
        batch = []
        console.log fn, total

      line = line.trim().replace('&amp;', '&')
      if line is '</PubmedArticle>' # <PubmedArticle>...</PubmedArticle> is a total article record
        total += 1
        if published isnt false and published.year
          rec.year = parseInt published.year
          if published.month and published.month.length > 2
            published.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf published.month.toLowerCase().substr(0, 3)
          published.month = published.month.toString() if typeof published.month is 'number'
          published.month = '0' + published.month if published.month and published.month.length is 1
          published.day = published.day.toString() if typeof published.day is 'number'
          published.day = '0' + published.day if published.day and published.day.length is 1
          rec.published = published.year + '-' + (published.month ? '01') + '-' + (published.day ? '01')
          rec.publishedAt = await @epoch rec.published
        rec.srcfile = fn
        rec._id = rec.PMID
        batch.push rec
        rec = {}
        published = false
        ininv = false
        break if total is howmany
      else
        km = 
          '<ArticleTitle>': 'title'
          '<AbstractText>': 'abstract'
          '<ISOAbbreviation>': 'iso'
          '<Issue>': 'issue' 
          '<Title>': 'journal'
          '<Language>': 'language'
          '<NlmUniqueID>': 'NLMID'
          '<PMID>': 'PMID'
          '<Volume>': 'volume'
          '<CopyrightInformation>': 'copyright'
          '<NumberOfReferences>': 'references_count'
          '<PublicationStatus>': 'status'
          '<SpaceFlightMission>': 'spaceflightmission'
        for k of km
          rec[km[k]] ?= line.split('>')[1].split('</')[0] if line.includes(k) or line.includes k.replace '>', ' '

        if line.includes '<MedlinePgn>'
          # do this because something like 1345-56 makes ES attempt to interpret a date, then others that don't look like a date will fail
          rec.pages = line.split('>')[1].split('</')[0].replace(' - ',' to ').replace('-', ' to ')
        
        if line.includes('<ISSN>') or line.includes('<ISSN ') or line.includes '<ISSNLinking>'
          rec.ISSN ?= []
          v = line.split('>')[1].split('</')[0]
          rec.ISSN.push(v) if v not in rec.ISSN
        if line.includes '<Keyword>'
          rec.keyword ?= []
          v = line.split('>')[1].split('</')[0]
          rec.keyword.push(v) if v not in rec.keyword
        if line.includes '<GeneSymbol>'
          rec.gene ?= []
          v = line.split('>')[1].split('</')[0]
          rec.gene.push(v) if v not in rec.gene
        if line.includes('<PublicationType>') or line.includes '<PublicationType '
          rec.type ?= []
          v = line.split('>')[1].split('</')[0]
          rec.type.push(v) if v not in rec.type

        if line.includes '<Chemical>'
          rec.chemical ?= []
          rec.chemical.push {}
        if line.includes('<NameOfSubstance>') or line.includes '<NameOfSubstance '
          rec.chemical[rec.chemical.length - 1].name = line.split('>')[1].split('</')[0]
          rec.chemical[rec.chemical.length - 1].nameID = line.split('UI="')[1].split('"')[0]
        if line.includes '<RegistryNumber>'
          rec.chemical[rec.chemical.length - 1].registry = line.split('>')[1].split('</')[0]

        if line.includes('<DataBank>') or line.includes '<DataBank '
          rec.databank ?= []
          rec.databank.push {}
        if line.includes '<DataBankName>'
          rec.databank[rec.databank.length - 1].name = line.split('>')[1].split('</')[0]
        if line.includes '<AccessionNumber>'
          rec.databank[rec.databank.length - 1].accession ?= []
          rec.databank[rec.databank.length - 1].accession.push line.split('>')[1].split('</')[0]

        if line.includes('<Grant>') or line.includes '<Grant '
          rec.grant ?= []
          rec.grant.push {}
        if line.includes '<GrantID>'
          rec.grant[rec.grant.length - 1].id = line.split('>')[1].split('</')[0]
        if line.includes '<Acronym>'
          rec.grant[rec.grant.length - 1].acronym = line.split('>')[1].split('</')[0]
        if line.includes '<Agency>'
          rec.grant[rec.grant.length - 1].agency = line.split('>')[1].split('</')[0]
        if line.includes '<Country>'
          if (not rec.grant or rec.grant[rec.grant.length - 1].country) and not rec.country
            rec.country = line.split('>')[1].split('</')[0]
          else
            rec.grant[rec.grant.length - 1].country = line.split('>')[1].split('</')[0]

        if line.includes('<MeshHeading>') or line.includes '<MeshHeading '
          rec.mesh ?= []
          rec.mesh.push {}
        if line.includes('<DescriptorName>') or line.includes('<DescriptorName ')
          rec.mesh[rec.mesh.length - 1].description = line.split('>')[1].split('</')[0]
          rec.mesh[rec.mesh.length - 1].descriptionID = line.split('UI="')[1].split('"')[0]
        if line.includes('<QualifierName>') or line.includes('<QualifierName ')
          rec.mesh[rec.mesh.length - 1].qualifier ?= []
          rec.mesh[rec.mesh.length - 1].qualifier.push name: line.split('>')[1].split('</')[0], id: line.split('UI="')[1].split('"')[0]

        if line.includes('<Investigator>') or line.includes '<Investigator '
          rec.author ?= []
          rec.author.push {}
          ininv = true
        if line.includes('<Author>') or line.includes '<Author '
          rec.author ?= []
          rec.author.push {}
          ininv = false
        try # some fields called PersonalNameSubjectList can cause a problem but don't know what they are so not including them
          if line.includes '<LastName>'
            rec.author[rec.author.length - 1].lastname = line.split('>')[1].split('</')[0]
            rec.author[rec.author.length - 1].investigator = true if ininv
          if line.includes '<ForeName>' # skip <Initials>
            rec.author[rec.author.length - 1].firstname = line.split('>')[1].split('</')[0]
          if line.includes '<Affiliation>'
            rec.author[rec.author.length - 1].affiliation = line.split('>')[1].split('</')[0]
          if line.includes '<Identifier>'
            rec.author[rec.author.length - 1].identifier = line.split('>')[1].split('</')[0]
            
        if line.includes('<Note>') or line.includes('<Note ') or line.includes('<GeneralNote>') or line.includes '<GeneralNote '
          try
            rec.notes ?= []
            rec.notes.push line.split('>')[1].split('</')[0]
            
        if line.includes('<DeleteCitation>') or line.includes '<DeleteCitation '
          rec.deletedFromMedline = true # this indicates Medline deleted the record, we should prob just remove all these too, but let's see how many there are

        if line.includes('<ArticleId>') or line.includes '<ArticleId '
          rec.identifier ?= {}
          idt = line.split('IdType="')[1].split('"')[0]
          rec.identifier[idt] ?= line.split('>')[1].split('</')[0]
          
        if line.includes('<ArticleDate>') or line.includes('ArticleDate ') or line.includes('<PubDate>') or line.includes '<PubDate '
          published = {}
        if published isnt false and (line.includes('<Year>') or line.includes('<Month>') or line.includes('<Day>'))
          published[line.split('>')[0].replace('<', '').toLowerCase()] = line.split('>')[1].split('</')[0]

    if batch.length
      await @src.pubmed batch
      batch = []
      console.log fn, total
    running -= 1

  while files.length
    break if howmany > 0 and total >= howmany
    await @sleep 1000
    if running < streamers
      running += 1
      _loop files.shift()

  console.log total
  #if not changes
  #  total += await @src.pubmed.changes true
  #  console.log total

  return total

P.src.pubmed.load._bg = true
P.src.pubmed.load._async = true
P.src.pubmed.load._auth = 'root'


P.src.pubmed.changes = () ->
  return @src.pubmed.load true

P.src.pubmed.changes._bg = true
P.src.pubmed.changes._async = true
P.src.pubmed.changes._auth = 'root'
P.src.pubmed.changes._notify = false

