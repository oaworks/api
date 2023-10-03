
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
  # otherwise search entrez with DOI?
  return

P.src.pubmed.pmc = (pmc) ->
  pmc ?= @params.pmc
  if pmc and found = await @src.pubmed 'identifier.pmc:"PMC' + pmc.toString().toLowerCase().replace('pmc','') + '"', 1
    return found
  # otherwise try calling entrez?
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
    md = await @convert.xml2json await @fetch url
    recs = []
    md.eSummaryResult.DocSum = [md.eSummaryResult.DocSum] if not Array.isArray md.eSummaryResult.DocSum
    for rec in md.eSummaryResult.DocSum
      frec = id: rec.Id
      for ii in rec.Item
        if ii._.Type is 'List'
          frec[ii._.Name] = []
          if ii.Item?
            for si in ii.Item
              sio = {}
              sio[si._.Name] = si.$
              frec[ii._.Name].push sio
        else
          frec[ii._.Name] = ii.$
      recs.push frec
      return recs[0] if not id? or not id.includes ','
    return recs
  catch
    return

P.src.pubmed.entrez.pmid = (pmid) ->
  pmid ?= @params.pmid
  # can prob switch this direct for an efetch
  # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=35717313
  # also could do for pmc and others
  # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?db=pubmed&id=' + pmid
  try
    res = await @fetch url
    result = await @convert.xml2json res
    return @src.pubmed.entrez.summary result.ePostResult.QueryKey, result.ePostResult.WebEnv
    # switch this to use the code in pubmed.load as a formatter for records? Or have load call format
  catch
    return

P.src.pubmed.search = (str, full, size=10, ids=false) ->
  str ?= @params.search ? @params.q
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
        pg = await @src.pubmed.pmid uid # should rate limit this to 300ms?
        res.data.push pg
        break if res.data.length is size
    else
      for rec in await @src.pubmed.entrez.summary undefined, undefined, ids
        res.data.push rec
        break if res.data.length is size
    return res
  catch
    return

P.src.pubmed.pmid = (pmid) ->
  pmid ?= @params.pmid
  # check local index first, if not present then try to retrieve from entrez
  try
    return @src.pubmed.entrez.pmid pmid # save if it was not present?
  return

P.src.pubmed.aheadofprint = (pmid) ->
  pmid ?= @params.pmid
  try
    # should switch this for an efetch
    # https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=35717313
    res = await @fetch 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'
    return res.includes 'PublicationStatus&gt;aheadofprint&lt;/PublicationStatus' # would these be url encoded or proper characters?
  catch
    return

P.src.pubmed.availabilities = _sheet: '1ZQa6tOqFsm_nF3XUk9-FhDk5gmVtXeRC4I3uldDl-gM/Export', _prefix: false, _key: 'PMC'
P.src.pubmed.availability = (pmcid) ->
  # availabilities for now are loaded from a sheet. However they could be done by xml lookup. see below
  pmcid ?= @params.pubmed ? @params.availability ? @params.pmc ? @params.pmcid ? @params.PMC ? @params.PMCID
  pmcid = 'pmc' + (pmcid + '').toLowerCase().replace('pmc', '')
  if exists = await @src.pubmed.availabilities pmcid
    return true
  else
    return false

P.src.pubmed.availability.statement = (pmcid, rec) ->
  return P.src.epmc.statement pmcid, rec

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

# elements the files should contain:
# https://www.nlm.nih.gov/bsd/licensee/elements_alphabetical.html
# and descriptions:
# https://www.nlm.nih.gov/bsd/licensee/elements_descriptions.html#history

# TODO consider using ncbi to get all pmc files:
# https://www.ncbi.nlm.nih.gov/pmc/tools/pmcaws/

P.src.pubmed.load = (changes) ->
  # there are 30k or less records per pubmed file so tried batching by file, but streaming more than one file at a time caused OOM
  # so reduce batch size if necessary. default node heap size is 1400M I think, so increased to 3072M and try again
  # check if increasing heap that machine running it has enough - AND note that on production if using PM2 to run as cluster, then 
  # need enough memory for each process to max out. Running 3 with 15k batch size was stable but reaching almost 3000M at times and 
  # didn't seem much faster, so now set to do whole files as batches with two streamers at a time, see how that goes
  changes = true if not changes? and @params.load is 'changes'
  batchsize = -1 # how many records to batch upload at a time
  streamers = @params.streamers ? 3 # how many files to stream at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going...

  await @src.pubmed('') if @refresh and not changes

  addr = if changes then 'https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/' else 'https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/'
  fls = []
  fnumber = if typeof @params.load is 'number' then @params.load else if typeof @params.changes is 'number' then @params.changes else undefined
  listing = await @fetch addr
  for a in listing.split 'href="'
    f = a.split('"')[0]
    if (f.endsWith('.gz') and f.includes(fnumber + '.xml')) or (not fnumber and f.startsWith('pubmed') and f.endsWith('.gz') and (@params.load in ['baseline'] or (@refresh and not changes) or not exists = await @src.pubmed.count 'srcfile:"' + addr + f + '"'))
      fls.push addr + f
    else if not f.endsWith '.md5'
      console.log 'pubmed load skipping file', addr + f

  running = 0
  total = 0

  _loop = (fn) =>
    console.log 'Pubmed loading' + (if changes then ' changes' else ''), fn, fls.length, running

    # stream them, unzip, and parse line by line, processing each record once a full record has been parsed out
    # the first 2020 gz file for example is 19M, uncompressed it is 182M. 30k records or so per file
    batch = []
    rec = {}
    current = ''
    try
      for await line from readline.createInterface input: (await fetch fn).body.pipe zlib.createGunzip() # this still fails on error because the try doesn't catch
        if batchsize > 0 and batch.length >= batchsize
          await @src.pubmed batch
          batch = []
          console.log fn, total

        line = line.trim().replace('&amp;', '&')
        if line is '</PubmedArticle>' # <PubmedArticle>...</PubmedArticle> is a total article record
          total += 1
          #if published isnt false and published.year
          #  rec.published = await @dateparts published
          rec.srcfile = fn
          rec._id = rec.PMID
          batch.push rec
          rec = {}
          break if total is howmany
        else if not line.startsWith('<?') and not line.includes('?xml') and not line.includes('!DOCTYPE') and not line.includes('/>') and not line.includes('PubmedArticle') and not line.includes('PubmedData') and not line.includes('History') and not line.includes('ArticleIdList') and not line.includes('List>')
          current = line.split('>')[0].split(' ')[0].replace('<', '') # track current line any use? check for </ ?
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
            if line.includes(k) or line.includes k.replace '>', ' '
              rec[km[k]] ?= line.split('>')[1].split('</')[0]

          if line.includes '<MedlinePgn>' # vals like 1345-56 makes ES interpret a date, then others that don't will fail
            rec.pages = line.split('>')[1].split('</')[0].replace(' - ',' to ').replace('-', ' to ')          
          else if line.includes '<ISSN'
            rec.ISSN ?= []
            v = line.split('>')[1].split('</')[0]
            rec.ISSN.push(v) if v not in rec.ISSN
          else if line.includes '<Keyword>'
            rec.keyword ?= []
            v = line.split('>')[1].split('</')[0]
            rec.keyword.push(v) if v not in rec.keyword
          else if line.includes '<GeneSymbol>'
            rec.gene ?= []
            v = line.split('>')[1].split('</')[0]
            rec.gene.push(v) if v not in rec.gene
          else if line.includes('<PublicationType>') or line.includes '<PublicationType '
            rec.type ?= []
            v = line.split('>')[1].split('</')[0]
            rec.type.push(v) if v not in rec.type
          else if line.includes '<Chemical>'
            rec.chemical ?= []
            rec.chemical.push {}
          else if line.includes('<NameOfSubstance>') or line.includes '<NameOfSubstance '
            rec.chemical ?= [{}]
            rec.chemical[rec.chemical.length - 1].name = line.split('>')[1].split('</')[0]
            rec.chemical[rec.chemical.length - 1].nameID = line.split('UI="')[1].split('"')[0]
          else if line.includes '<RegistryNumber>'
            rec.chemical ?= [{}]
            rec.chemical[rec.chemical.length - 1].registry = line.split('>')[1].split('</')[0]
          else if line.includes('<DataBank>') or line.includes '<DataBank '
            rec.databank ?= []
            rec.databank.push {}
          else if line.includes '<DataBankName>'
            rec.databank ?= [{}]
            rec.databank[rec.databank.length - 1].name = line.split('>')[1].split('</')[0]
          else if line.includes '<AccessionNumber>'
            rec.databank ?= [{}]
            rec.databank[rec.databank.length - 1].accession ?= []
            rec.databank[rec.databank.length - 1].accession.push line.split('>')[1].split('</')[0]
          else if line.includes('<Grant>') or line.includes '<Grant '
            rec.grant ?= []
            rec.grant.push {}
          else if line.includes '<GrantID>'
            rec.grant ?= [{}]
            rec.grant[rec.grant.length - 1].id = line.split('>')[1].split('</')[0]
          else if line.includes '<Acronym>'
            rec.grant ?= [{}]
            rec.grant[rec.grant.length - 1].acronym = line.split('>')[1].split('</')[0]
          else if line.includes '<Agency>'
            rec.grant ?= [{}]
            rec.grant[rec.grant.length - 1].agency = line.split('>')[1].split('</')[0]
          else if line.includes '<Country>'
            if (not rec.grant or rec.grant[rec.grant.length - 1].country) and not rec.country
              rec.country = line.split('>')[1].split('</')[0]
            else if rec.grant and rec.grant.length
              rec.grant[rec.grant.length - 1].country = line.split('>')[1].split('</')[0]
          else if line.includes('<MeshHeading>') or line.includes '<MeshHeading '
            rec.mesh ?= []
            rec.mesh.push {}
          else if line.includes('<DescriptorName>') or line.includes('<DescriptorName ')
            rec.mesh ?= [{}]
            rec.mesh[rec.mesh.length - 1].description = line.split('>')[1].split('</')[0]
            rec.mesh[rec.mesh.length - 1].descriptionID = line.split('UI="')[1].split('"')[0]
          else if line.includes('<QualifierName>') or line.includes('<QualifierName ')
            rec.mesh ?= [{}]
            rec.mesh[rec.mesh.length - 1].qualifier ?= []
            rec.mesh[rec.mesh.length - 1].qualifier.push name: line.split('>')[1].split('</')[0], id: line.split('UI="')[1].split('"')[0]
          # where are author Identifiers going? Don't seem to have picked any up
          else if line.includes('<Author>') or line.includes('<Author ') or line.includes('<Investigator>') or line.includes('<Investigator ')
            rec.author ?= []
            rec.author.push if line.includes('<Investigator') then {investigator: true} else {}
          else if line.includes '<LastName>' # some fields called PersonalNameSubjectList can cause a problem but don't know what they are so not including them
            rec.author ?= [{}]
            rec.author[rec.author.length - 1].lastname = line.split('>')[1].split('</')[0]
          else if line.includes '<ForeName>' # skip <Initials>
            rec.author ?= [{}]
            rec.author[rec.author.length - 1].firstname = line.split('>')[1].split('</')[0]
          else if line.includes '<Affiliation>'
            rec.author ?= [{}]
            rec.author[rec.author.length - 1].affiliation = line.split('>')[1].split('</')[0]
          else if line.includes '<Identifier>'
            rec.author ?= [{}]
            rec.author[rec.author.length - 1].identifier = line.split('>')[1].split('</')[0]
          else if line.includes('<Note>') or line.includes('<Note ') or line.includes('<GeneralNote>') or line.includes '<GeneralNote '
            rec.notes ?= []
            rec.notes.push line.split('>')[1].split('</')[0]
          else if line.includes('<DeleteCitation>') or line.includes '<DeleteCitation '
            rec.deletedFromMedline = true # this indicates Medline deleted the record, we should prob just remove all these too, but let's see how many there are
          else if line.includes('<ArticleId>') or line.includes '<ArticleId '
            rec.identifier ?= {}
            try
              idt = line.split('IdType="')[1].split('"')[0]
              rec.identifier[idt] ?= line.split('>')[1].split('</')[0]
          # check how History dates are being handled, where is the attribute that indicates what sort of date they are?
          else if not line.includes('</') and (line.includes('Date>') or line.includes('<Date') or line.includes('<PubMedPubDate') or line.includes('<ArticleDate>') or line.includes('ArticleDate ') or line.includes('<PubDate>') or line.includes '<PubDate ')
            somedate = line.split('>')[0].split(' ')[0].replace('<', '')
            try
              ll = line.toLowerCase()
              somedatestatus = ll.split('>')[0].split('pubstatus')[1] if ll.includes 'pubstatus'
              somedatestatus = somedatestatus.split('"')[1] if somedatestatus.includes '"'
          else if somedate and (line.includes('<Year>') or line.includes('<Month>') or line.includes('<Day>'))
            rec.dates ?= {}
            sds = somedate + (if somedatestatus then '_' + somedatestatus else '')
            rec.dates[sds] ?= {}
            rec.dates[sds][line.split('>')[0].replace('<', '').toLowerCase()] = line.split('>')[1].split('</')[0]
            delete rec.dates[sds].date
            delete rec.dates[sds].timestamp
            try rec.dates[sds] = await @dateparts rec.dates[sds]
            try rec.dates[sds].pubstatus = somedatestatus if somedatestatus
          else if somedate and line.includes('</' + somedate)
            somedate = ''
            somedatestatus = ''
          # handle the contents of ReferenceList and be aware it uses self closing xml as well e.g. <ReferenceList/> (as may other tags)
          else if line.includes('<Reference>') or line.includes '<Reference '
            rec.references ?= []
          else if line.includes '<Citation'
            rec.references ?= []
            rf = author: []
            try rf.author.push({name: an}) for an in line.split('. ')[0].split(', ')
            try rf.title = line.split('. ')[1].split('?')[0].trim()
            try rf.journal = line.replace(/\?/g,'.').split('. ')[2].trim()
            try rf.doi = line.split('doi.org/')[1].split(' ')[0].trim() if line.includes 'doi.org/'
            try rf.url = 'http' + rc.split('http')[1].split(' ')[0]
            rec.references.push(rf) if JSON.stringify(rf) isnt '{}'

      if batch.length
        await @src.pubmed batch
        console.log fn, total

    running -= 1

  while fls.length
    break if howmany > 0 and total >= howmany
    await @sleep 1000
    if running < streamers
      running += 1
      nf = fls.shift()
      _loop nf

  console.log total, fls.length

  return if @params.howmany then batch else total

P.src.pubmed.load._bg = true
P.src.pubmed.load._async = true
#P.src.pubmed.load._auth = 'root'


P.src.pubmed.changes = () ->
  return @src.pubmed.load true

P.src.pubmed.changes._bg = true
P.src.pubmed.changes._async = true
P#.src.pubmed.changes._auth = 'root'
P.src.pubmed.changes._notify = false

