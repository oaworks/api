
# the only things find does that could be required separately is it provides a URL to the article, which is actually extracted in @citation
# so if dropping find altogether, just use @citation to get the URL e.g. in calls to permissions that may also need it such as for shareyourpaper
# find will also operate without a DOI whereas shareyourpaper and permissions didn't - they could be changed to allow that, or just restrict some of what find used to do
# find will also give info of any open ILLs

P.metadata = (doi) ->
  res = await @find doi # may not be a DOI, but most likely thing
  return res?.metadata
P.metadata._log = false

P.find = (options, metadata={}, content) ->
  res = {}

  _metadata = (input) =>
    ct = await @citation input
    for k of ct
      if k in ['url', 'paywall']
        res[k] ?= ct[k]
      else
        metadata[k] ?= ct[k]

  if typeof options is 'string'
    options = if options.split('doi.org/').pop().startsWith('10.') then {doi: options} else {title: options}
  try options ?= @copy @params
  options ?= {}
  content ?= options.dom ? (if typeof @body is 'string' then @body else undefined)
  
  options.find = options.metadata if options.metadata
  if options.find
    if options.find.startsWith('10.') and options.find.includes '/'
      options.doi = options.find
    else
      options.url = options.find
    delete options.find
  options.url ?= options.q ? options.id
  if options.url
    options.url = options.url.toString() if typeof options.url is 'number'
    if options.url.startsWith '/10.'
      # we don't use a regex to try to pattern match a DOI because people often make mistakes typing them, so instead try to find one
      # in ways that may still match even with different expressions (as long as the DOI portion itself is still correct after extraction we can match it)
      dd = '10.' + options.url.split('/10.')[1].split('&')[0].split('#')[0]
      if dd.includes('/') and dd.split('/')[0].length > 6 and dd.length > 8
        dps = dd.split('/')
        dd = dps.join('/') if dps.length > 2
        metadata.doi ?= dd
    if options.url.replace('doi:','').replace('doi.org/','').trim().startsWith '10.'
      metadata.doi ?= options.url.replace('doi:','').replace('doi.org/','').trim()
      options.url = 'https://doi.org/' + metadata.doi
    else if options.url.toLowerCase().startsWith 'pmc'
      metadata.pmcid ?= options.url.toLowerCase().replace('pmcid','').replace('pmc','')
      options.url = 'http://europepmc.org/articles/PMC' + metadata.pmcid
    else if options.url.replace(/pmid/i,'').replace(':','').length < 10 and options.url.includes('.') and not isNaN(parseInt(options.url.replace(/pmid/i,'').replace(':','').trim()))
      metadata.pmid ?= options.url.replace(/pmid/i,'').replace(':','').trim()
      options.url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + metadata.pmid
    else if not metadata.title? and not options.url.startsWith 'http'
      if options.url.includes('{') or (options.url.replace('...','').match(/\./gi) ? []).length > 3 or (options.url.match(/\(/gi) ? []).length > 2
        options.citation = options.url
      else
        metadata.title = options.url
    delete options.url if not options.url.startsWith('http') or not options.url.includes '.'
  if typeof options.title is 'string' and (options.title.includes('{') or (options.title.replace('...','').match(/\./gi) ? []).length > 3 or (options.title.match(/\(/gi) ? []).length > 2)
    options.citation = options.title # titles that look like citations
    try options.doi = '10.' + options.title.split('10.')[1].split(' ')[0].trim() if options.title.includes('10.') and options.title.includes '/'
    delete options.doi if options.doi.length < 8 or not options.doi.includes '/'
    delete options.title

  options.doi = await @decode(options.doi) if options.doi
  metadata.doi ?= options.doi
  metadata.title ?= options.title
  metadata.pmid ?= options.pmid
  metadata.pmcid ?= options.pmcid ? options.pmc
  await _metadata(options.citation) if options.citation
  try metadata.title = metadata.title.replace(/(<([^>]+)>)/g,'').replace(/\+/g,' ').trim()
  try metadata.title = await @decode metadata.title
  try metadata.doi = metadata.doi.split(' ')[0].replace('http://','').replace('https://','').replace('doi.org/','').replace('doi:','').trim()
  delete metadata.doi if typeof metadata.doi isnt 'string' or not metadata.doi.startsWith '10.'

  # switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  delete options.url if not metadata.title and content and typeof options.url is 'string' and (options.url.includes('alma.exlibrisgroup.com') or options.url.includes '/exlibristest')

  # set a demo tag in certain cases e.g. for instantill/shareyourpaper/other demos - dev and live demo accounts
  res.demo = options.demo if options.demo?
  res.demo ?= true if (metadata.doi is '10.1234/567890' or (metadata.doi? and metadata.doi.startsWith '10.1234/oab-syp-')) or metadata.title is 'Engineering a Powerfully Simple Interlibrary Loan Experience with InstantILL' or options.from in ['qZooaHWRz9NLFNcgR','eZwJ83xp3oZDaec86']
  res.test ?= true if res.demo # don't save things coming from the demo accounts into the catalogue later

  epmc = false
  if (content? or options.url?) and not (metadata.doi or metadata.pmid? or metadata.pmcid? or metadata.title?)
    await _metadata await @scrape content ? options.url

  if not metadata.doi
    if metadata.pmid or metadata.pmcid
      epmc = await @src.epmc[if metadata.pmcid then 'pmc' else 'pmid'] (metadata.pmcid ? metadata.pmid)
      await _metadata epmc
    if not metadata.doi and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
      metadata.title = metadata.title.replace /\+/g, ' ' # some+titles+come+in+like+this
      openalex = await @src.openalex.works.title metadata.title
      await _metadata(openalex) if openalex?.type and openalex?.doi
      if not metadata.doi and not epmc
        epmc = await @src.epmc.title metadata.title
        await _metadata(epmc) if epmc isnt false

  await _metadata(openalex) if metadata.doi and openalex = await @src.openalex.works.doi metadata.doi # run this even if ran openalex title search above, because may since have gotten DOI and could get better
  res.doi_not_in_openalex = true if metadata.doi and not openalex?.type_crossref

  # temporary until publishers in permissions are re-keyed to match openalex publisher names (which differ from crossref which is what we originally keyed them to)
  # https://github.com/oaworks/discussion/issues/3192#issuecomment-2314515904
  if metadata.doi and cr = await @src.crossref.works.doi metadata.doi # metadata.publisher and 
    metadata.publisher = cr.publisher if cr.publisher

  _ill = () =>
    if (metadata.doi or (metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1)) and (options.from or options.config?) and (options.plugin is 'instantill' or options.ill is true)
      try res.ill ?= subscription: await @ill.subscription (options.config ? options.from), metadata
    return true
  _permissions = () =>
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper')
      res.permissions ?= await @permissions metadata, options.config?.ror, false
    return true
  await Promise.all [_ill(), _permissions()]

  # temporary 
  try
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper') and not res.permissions?.all_permissions and metadata.publisher_lineage.length > 1
      pi = 0
      while pi < metadata.publisher_lineage.length
        if metadata.publisher_lineage[pi] isnt metadata.publisher
          metadata.publisher = metadata.publisher_lineage[pi]
          res.permissions = await @permissions metadata, options.config?.ror, false
          break if res.permissions.all_permissions
        pi++

  # certain user-provided search values are allowed to override any that we could find ourselves. TODO is this ONLY relevant to ILL? or anything else?
  metadata[uo] = options[uo] for uo in ['title', 'journal', 'year', 'doi'] when options[uo] and options[uo] isnt metadata[uo]

  res.metadata = metadata # if JSON.stringify(metadata) isnt '{}'
  return res



# Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
# Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.citation = (citation) ->  
  try citation ?= @params.citation ? @params
  if typeof citation is 'string'
    try citation = JSON.parse(citation) if citation.startsWith('{') or citation.startsWith '['
    citation = await @src.openalex.works.doi(citation) if citation.startsWith '10.'

  res = {}
  if typeof citation is 'object' # can be crossref, oadoi, openalex, epmc format
    for id in ['doi', 'pmid', 'pmcid']
      res[id] = citation[id] ? citation[id.toUpperCase()] ? citation.ids?[id]
      res[id] = res[id].toString() if typeof res[id] is 'number'
      res[id] = res[id].split('/').pop() if id in ['pmid', 'pmcid'] and res[id] and res[id].includes '/'
      res[id] = res[id].split('.org/').pop() if id in ['doi'] and res[id] and res[id].includes '.org/'
      res[id] = 'PMC' + res[id] if res[id] and id is 'pmcid' and not res[id].startsWith 'PMC'
    res.DOI = res.doi if res.doi and not res.DOI
    try res.type = citation.type_crossref ? citation.type ? citation.genre
    res.issn = citation.ISSN ? citation.issn ? citation.journalInfo?.journal?.issn ? citation.journal?.issn ? citation.primary_location?.source?.issn ? []
    res.issn.push(citation.journalInfo.journal.eissn) if citation.journalInfo?.journal?.eissn? and citation.journalInfo.journal.eissn not in res.issn
    res.issn = citation.journal_issns.split(',') if not res.issn and citation.journal_issns
    res.title = citation.title
    res.title = res.title[0] if Array.isArray res.title
    res.title += ': ' + citation.subtitle[0] if res.title and citation.subtitle? and citation.subtitle.length and citation.subtitle[0].length
    res.title ?= citation.dctitle ? citation.bibjson?.title
    delete res.title if res.title in [404, '404']
    res.title = res.title.replace(/\s\s+/g,' ').trim() if typeof res.title is 'string'
    res.journal = if citation['container-title'] then citation['container-title'][0] else citation.primary_location?.source?.display_name
    try res.shortname = citation['short-container-title'][0]
    try res.shortname = citation.journalInfo.journal.isoabbreviation ? citation.journalInfo.journal.medlineAbbreviation
    res.journal ?= citation.journal_name ? citation.journalInfo?.journal?.title ? citation.journal?.title
    res.journal = citation.journal.split('(')[0].trim() if citation.journal
    res.shortname ?= res.journal # fix for old embed that still expects something here
    res.journal_short = res.shortname if res.shortname and not res.journal_short # fix for change to old metadata field name
    try res[key] ?= res[key].charAt(0).toUpperCase() + res[key].slice(1) for key in ['title','journal']
    res.publisher = citation.publisher ? citation.primary_location?.source?.publisher ? citation.primary_location?.source?['host_organization_name']
    res.publisher = res.publisher.trim() if res.publisher
    try res.publisher_lineage = citation.primary_location.source.host_organization_lineage_names # temporary re. https://github.com/oaworks/discussion/issues/3227
    res.published = citation.publication_date # like 2009-01-01
    res.issue = citation.issue ? citation.journalInfo?.issue ? citation.biblio?.issue
    res.volume = citation.volume ? citation.journalInfo?.volume ? citation.biblio?.volume
    res.pages = (citation.page ? citation.pages ? citation.pageInfo).toString() if citation.page or citation.pages or citation.pageInfo
    if citation.biblio?.first_page or citation.biblio?.last_page
      res.pages = if citation.biblio.first_page is citation.biblio.last_page then citation.biblio.first_page else (citation.biblio.first_page ? '') + (if citation.biblio.first_page and citation.biblio.last_page then '-' else '') + (citation.biblio.last_page ? '')
    res.abstract = citation.abstract ? citation.abstractText

    for p in ['published-print', 'journal-issue.published-print', 'journalInfo.printPublicationDate', 'firstPublicationDate', 'journalInfo.electronicPublicationDate', 'published', 'published_date', 'issued', 'published-online', 'created', 'deposited']
      if typeof res.published isnt 'string' # this may already be set above from openalex for example
        if rt = citation[p] ? citation['journal-issue']?[p.replace('journal-issue.','')] ? citation['journalInfo']?[p.replace('journalInfo.','')]
          rt = rt.toString() if typeof rt is 'number'
          try rt = rt['date-time'].toString() if typeof rt isnt 'string'
          if typeof rt isnt 'string'
            try
              rt['date-parts'][0][k] = '01' for k of rt['date-parts'][0] when typeof rt['date-parts'][0][k] not in ['number', 'string']
              rt = rt['date-parts'][0].join '-'
          if typeof rt is 'string'
            res.published = if rt.includes('T') then rt.split('T')[0] else rt
            res.published = res.published.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace /-(\d)$/, "-0$1"
            res.published += '-01' if not res.published.includes '-'
            res.published += '-01' if res.published.split('-').length isnt 3
            res.year ?= res.published.split('-')[0]
            delete res.published if res.published.split('-').length isnt 3
            delete res.year if res.year.toString().length isnt 4
        break if res.published
    res.year ?= citation.year if citation.year
    try res.year ?= citation.journalInfo.yearOfPublication.trim()
    res.year = res.published.split('-')[0] if not res.year and res.published and res.published.includes '-'

    if not res.author? and (authors = citation.author ? citation.z_authors ? citation.authorList?.author ? citation.authorships)
      res.author ?= []
      try
        for a in authors
          if typeof a is 'string'
            res.author.push name: a
          else
            au = {}
            if typeof a.author is 'object'
              au.given = a.author.display_name.split(' ')[0] if a.author.display_name.split(' ').length > 1
              au.family = a.author.display_name.split(' ').pop()
              try au.given = a.author.display_name.replace(' ' + au.family, '') if a.author.display_name.split(' ').length > 2
              au.name = a.author.display_name
              for aff in a.raw_affiliation_strings ? []
                au.affiliation ?= []
                au.affiliation.push name: aff
            else
              au.given = a.given ? a.firstName
              au.family = a.family ? a.lastName
              au.name = (if au.given then au.given + ' ' else '') + (au.family ? '')
              for aff in (if a.affiliation then (if Array.isArray(a.affiliation) then a.affiliation else [a.affiliation]) else (a.authorAffiliationDetailsList.authorAffiliation ? []))
                if typeof aff is 'string'
                  au.affiliation ?= []
                  au.affiliation.push name: aff.replace(/\s\s+/g,' ').trim()
                else if typeof aff is 'object' and (aff.name or aff.affiliation)
                  au.affiliation ?= []
                  au.affiliation.push name: (aff.name ? aff.affiliation).replace(/\s\s+/g,' ').trim()
            try au.affiliation = au.affiliation.sort (a,b) -> a.name.localeCompare(b.name)
            res.author.push au

    try res.subject = citation.subject if citation.subject? and citation.subject.length and typeof citation.subject[0] is 'string'
    try res.keyword = citation.keywordList.keyword if citation.keywordList?.keyword? and citation.keywordList.keyword.length and typeof citation.keywordList.keyword[0] is 'string'
    if not res.keyword and citation.keywords # openalex also has topics and fields / subfields, use those here?
      res.keyword = []
      res.keyword.push(kw.keyword ? kw.display_name) for kw in citation.keywords when kw.keyword or kw.display_name
    try
      for m in [...(citation.meshHeadingList?.meshHeading ? []), ...(citation.chemicalList?.chemical ? [])]
        res.keyword ?= []
        mn = if typeof m is 'string' then m else m.name ? m.descriptorName
        res.keyword.push(mn) if typeof mn is 'string' and mn and mn not in res.keyword

    res.licence = citation.license.trim().replace(/ /g,'-') if typeof citation.license is 'string'
    res.licence = citation.licence.trim().replace(/ /g,'-') if typeof citation.licence is 'string'
    try res.licence ?= citation.best_oa_location.license if citation.best_oa_location?.license
    try res.licence ?= citation.primary_location.license if citation.primary_location?.license
    if not res.licence
      for a in citation.assertion ? []
        if a.label is 'OPEN ACCESS' and a.URL and a.URL.includes 'creativecommons'
          res.licence ?= a.URL # and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
      for l in citation.license ? []
        if l.URL and l.URL.includes('creativecommons') and (not res.licence or not res.licence.includes 'creativecommons')
          res.licence ?= l.URL
    if typeof res.licence is 'string' and res.licence.includes '/licenses/'
      res.licence = 'cc-' + res.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-').replace(/-$/, '')

    # if there is a URL to use but not open, store it as res.paywall?
    res.url ?= citation.best_oa_location?.pdf_url ? citation.best_oa_location?.url_for_pdf ? citation.best_oa_location?.url ? citation.best_oa_location?.landing_page_url #? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?
    if not res.url and citation.fullTextUrlList?.fullTextUrl? # epmc fulltexts
      for cf in citation.fullTextUrlList.fullTextUrl
        res.url = cf.url if cf.availabilityCode.toLowerCase() in ['oa','f'] and (not res.url or (cf.documentStyle is 'pdf' and not res.url.includes 'pdf'))

  else if typeof citation is 'string' # worth keeping citiation string extraction? Don't think it's used anywhere any more
    try
      citation = citation.replace(/citation\:/gi,'').trim()
      citation = citation.split('title')[1].trim() if citation.includes 'title'
      citation = citation.replace(/^"/,'').replace(/^'/,'').replace(/"$/,'').replace(/'$/,'')
      res.doi = citation.split('doi:')[1].split(',')[0].split(' ')[0].trim() if citation.includes 'doi:'
      res.doi = citation.split('doi.org/')[1].split(',')[0].split(' ')[0].trim() if citation.includes  'doi.org/'
      if not res.doi and citation.includes 'http'
        res.url = 'http' + citation.split('http')[1].split(' ')[0].trim()
      try
        if citation.includes('|') or citation.includes '}'
          res.title = citation.split('|')[0].split('}')[0].trim()
        if citation.split('"').length > 2
          res.title = citation.split('"')[1].trim()
        else if citation.split("'").length > 2
          res.title ?= citation.split("'")[1].trim()
      try
        pts = citation.replace(/,\./g,' ').split ' '
        for pt in pts
          if not res.year
            pt = pt.replace /[^0-9]/g,''
            if pt.length is 4
              sy = parseInt pt
              res.year = sy if typeof sy is 'number' and not isNaN sy
      try
        if not res.title and res.year and citation.indexOf(res.year) < (citation.length/4)
          res.title = citation.split(res.year)[1].trim()
          res.title = res.title.replace(')','') if not res.title.includes('(') or res.title.indexOf(')') < res.title.indexOf('(')
          res.title = res.title.replace('.','') if res.title.indexOf('.') < 3
          res.title = res.title.replace(',','') if res.title.indexOf(',') < 3
          res.title = res.title.trim()
          if res.title.includes '.'
            res.title = res.title.split('.')[0]
          else if res.title.includes ','
            res.title = res.title.split(',')[0]
      if res.title
        try
          bt = citation.split(res.title)[0]
          bt = bt.split(res.year)[0] if res.year and bt.includes res.year
          bt = bt.split(res.url)[0] if res.url and bt.indexOf(res.url) > 0
          bt = bt.replace(res.url) if res.url and bt.startsWith res.url
          bt = bt.replace(res.doi) if res.doi and bt.startsWith res.doi
          bt = bt.replace('.','') if bt.indexOf('.') < 3
          bt = bt.replace(',','') if bt.indexOf(',') < 3
          bt = bt.substring(0,bt.lastIndexOf('(')) if bt.lastIndexOf('(') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(')')) if bt.lastIndexOf(')') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(',')) if bt.lastIndexOf(',') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf('.')) if bt.lastIndexOf('.') > (bt.length-3)
          bt = bt.trim()
          if bt.length > 6
            if bt.includes ','
              res.author = []
              res.author.push({name: ak}) for ak in bt.split(',')
            else
              res.author = [{name: bt}]
        try
          rmn = citation.split(res.title)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.includes res.url
          rmn = rmn.replace(res.doi) if res.doi and rmn.includes res.doi
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 6
            res.journal = rmn
            res.journal = res.journal.split(',')[0].replace(/in /gi,'').trim() if rmn.includes ','
            res.journal = res.journal.replace('.','') if res.journal.indexOf('.') < 3
            res.journal = res.journal.replace(',','') if res.journal.indexOf(',') < 3
            res.journal = res.journal.trim()
      try
        if res.journal
          rmn = citation.split(res.journal)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.includes res.url
          rmn = rmn.replace(res.doi) if res.doi and rmn.includes res.doi
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 4
            rmn = rmn.split('retrieved')[0] if rmn.includes 'retrieved'
            rmn = rmn.split('Retrieved')[0] if rmn.includes 'Retrieved'
            res.volume = rmn
            if res.volume.includes '('
              res.volume = res.volume.split('(')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split('(')[1].split(')')[0]
                res.issue = res.issue.trim()
            if res.volume.includes ','
              res.volume = res.volume.split(',')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split(',')[1]
                res.issue = res.issue.trim()
            if res.volume
              try
                delete res.volume if isNaN parseInt res.volume
            if res.issue
              if res.issue.includes ','
                res.issue = res.issue.split(',')[0].trim()
              try
                delete res.issue if isNaN parseInt res.issue
            if res.volume and res.issue
              try
                rmn = citation.split(res.journal)[1]
                rmn = rmn.split('retriev')[0] if rmn.includes 'retriev'
                rmn = rmn.split('Retriev')[0] if rmn.includes 'Retriev'
                rmn = rmn.split(res.url)[0] if res.url and rmn.includes res.url
                rmn = rmn.split(res.doi)[0] if res.doi and rmn.includes res.doi
                rmn = rmn.substring(rmn.indexOf(res.volume)+(res.volume+'').length)
                rmn = rmn.substring(rmn.indexOf(res.issue)+(res.issue+'').length)
                rmn = rmn.replace('.','') if rmn.indexOf('.') < 2
                rmn = rmn.replace(',','') if rmn.indexOf(',') < 2
                rmn = rmn.replace(')','') if rmn.indexOf(')') < 2
                rmn = rmn.trim()
                if not isNaN parseInt rmn.substring(0,1)
                  res.pages = rmn.split(' ')[0].split('.')[0].trim()
                  res.pages = res.pages.split(', ')[0] if res.pages.length > 5
      if not res.author and citation.includes 'et al'
        cn = citation.split('et al')[0].trim()
        if citation.startsWith cn
          res.author = [{name: cn + 'et al'}]
      if res.title and not res.volume
        try
          clc = citation.split(res.title)[1].toLowerCase().replace('volume','vol').replace('vol.','vol').replace('issue','iss').replace('iss.','iss').replace('pages','page').replace('pp','page')
          if clc.includes 'vol'
            res.volume = clc.split('vol')[1].split(',')[0].split('(')[0].split('.')[0].split(' ')[0].trim()
          if not res.issue and clc.includes 'iss'
            res.issue = clc.split('iss')[1].split(',')[0].split('.')[0].split(' ')[0].trim()
          if not res.pages and clc.includes 'page'
            res.pages = clc.split('page')[1].split('.')[0].split(', ')[0].split(' ')[0].trim()

  res.year = res.year.toString() if typeof res.year is 'number'
  return res
