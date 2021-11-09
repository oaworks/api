
P.svc.oaworks.metadata = (doi) ->
  res = await @svc.oaworks.find doi # may not be a DOI, but most likely thing
  return res?.metadata


P.svc.oaworks.find = (options, metadata={}, content) ->
  res = {}

  _metadata = (input) =>
    ct = await @svc.oaworks.citation input
    for k of ct
      if k in ['url', 'paywall']
        res[k] ?= ct[k]
      else
        metadata[k] ?= ct[k]
    return true

  options = {doi: options} if typeof options is 'string'
  try options ?= @copy @params
  options ?= {}
  content ?= options.dom ? (if typeof @body is 'string' then @body else undefined)
  
  options.find = options.metadata if options.metadata
  if options.find
    if options.find.indexOf('10.') is 0 and options.find.indexOf('/') isnt -1
      options.doi = options.find
    else
      options.url = options.find
    delete options.find
  options.url ?= options.q ? options.id
  if options.url
    options.url = options.url.toString() if typeof options.url is 'number'
    if options.url.indexOf('/10.') isnt -1
      # we don't use a regex to try to pattern match a DOI because people often make mistakes typing them, so instead try to find one
      # in ways that may still match even with different expressions (as long as the DOI portion itself is still correct after extraction we can match it)
      dd = '10.' + options.url.split('/10.')[1].split('&')[0].split('#')[0]
      if dd.indexOf('/') isnt -1 and dd.split('/')[0].length > 6 and dd.length > 8
        dps = dd.split('/')
        dd = dps.join('/') if dps.length > 2
        metadata.doi ?= dd
    if options.url.replace('doi:','').replace('doi.org/','').trim().indexOf('10.') is 0
      metadata.doi ?= options.url.replace('doi:','').replace('doi.org/','').trim()
      options.url = 'https://doi.org/' + metadata.doi
    else if options.url.toLowerCase().indexOf('pmc') is 0
      metadata.pmcid ?= options.url.toLowerCase().replace('pmcid','').replace('pmc','')
      options.url = 'http://europepmc.org/articles/PMC' + metadata.pmcid
    else if options.url.replace(/pmid/i,'').replace(':','').length < 10 and options.url.indexOf('.') is -1 and not isNaN(parseInt(options.url.replace(/pmid/i,'').replace(':','').trim()))
      metadata.pmid ?= options.url.replace(/pmid/i,'').replace(':','').trim()
      options.url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + metadata.pmid
    else if not metadata.title? and options.url.indexOf('http') isnt 0
      if options.url.indexOf('{') isnt -1 or (options.url.replace('...','').match(/\./gi) ? []).length > 3 or (options.url.match(/\(/gi) ? []).length > 2
        options.citation = options.url
      else
        metadata.title = options.url
    delete options.url if options.url.indexOf('http') isnt 0 or options.url.indexOf('.') is -1
  if typeof options.title is 'string' and (options.title.indexOf('{') isnt -1 or (options.title.replace('...','').match(/\./gi) ? []).length > 3 or (options.title.match(/\(/gi) ? []).length > 2)
    options.citation = options.title # titles that look like citations
    delete options.title

  metadata.doi ?= options.doi
  metadata.title ?= options.title
  metadata.pmid ?= options.pmid
  metadata.pmcid ?= options.pmcid ? options.pmc
  await _metadata(options.citation) if options.citation
  try metadata.title = metadata.title.replace(/(<([^>]+)>)/g,'').replace(/\+/g,' ').trim()
  try metadata.title = await @decode metadata.title
  try metadata.doi = metadata.doi.split(' ')[0].replace('http://','').replace('https://','').replace('doi.org/','').replace('doi:','').trim()
  delete metadata.doi if typeof metadata.doi isnt 'string' or metadata.doi.indexOf('10.') isnt 0

  # switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if not metadata.title and content and typeof options.url is 'string' and (options.url.indexOf('alma.exlibrisgroup.com') isnt -1 or options.url.indexOf('/exlibristest') isnt -1)
    delete options.url

  # set a demo tag in certain cases
  # e.g. for instantill/shareyourpaper/other demos - dev and live demo accounts
  res.demo = options.demo if options.demo?
  res.demo ?= true if (metadata.doi is '10.1234/567890' or (metadata.doi? and metadata.doi.indexOf('10.1234/oab-syp-') is 0)) or metadata.title is 'Engineering a Powerfully Simple Interlibrary Loan Experience with InstantILL' or options.from in ['qZooaHWRz9NLFNcgR','eZwJ83xp3oZDaec86']
  res.test ?= true if res.demo # don't save things coming from the demo accounts into the catalogue later

  _searches = () =>
    if (content? or options.url?) and not (metadata.doi or metadata.pmid? or metadata.pmcid? or metadata.title?)
      scraped = await @svc.oaworks.scrape content ? options.url
      await _metadata scraped

    if not metadata.doi
      if metadata.pmid or metadata.pmcid
        epmc = await @src.epmc[if metadata.pmcid then 'pmc' else 'pmid'] (metadata.pmcid ? metadata.pmid)
        await _metadata epmc
      if not metadata.doi and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
        metadata.title = metadata.title.replace /\+/g, ' ' # some+titles+come+in+like+this
        cr = await @src.crossref.works.title metadata.title
        if cr?.type and cr?.DOI
          await _metadata cr
        if not metadata.doi
          mag = await @src.microsoft.graph metadata.title
          if mag?.PaperTitle
            await _metadata mag
        if not metadata.doi and not epmc? # run this only if we don't find in our own stores
          epmc = await @src.epmc.title metadata.title
          await _metadata epmc

    if metadata.doi
      _fatcat = () =>
        fat = await @src.fatcat metadata.doi
        if fat?.files?
          for f in fat.files
            # there are also hashes and revision IDs, but without knowing details about which is most recent just grab the first
            # looks like the URLs are timestamped, and looks like first is most recent, so let's just assume that.
            if f.mimetype.toLowerCase().indexOf('pdf') isnt -1 and f.state is 'active' # presumably worth knowing...
              for fu in f.urls
                if fu.url and fu.rel is 'webarchive' # would we want the web or the webarchive version?
                  res.url = fu.url
                  break
        return true
      _oad = () =>
        oad = await @src.oadoi metadata.doi
        res.doi_not_in_oadoi = metadata.doi if not oad?
        await _metadata(oad) if oad?.doi and metadata?.doi and oad.doi.toLowerCase() is metadata.doi.toLowerCase() # check again for doi in case removed by failed crossref lookup
        return true
      _crd = () =>
        cr = await @src.crossref.works metadata.doi
        if not cr?.type
          res.doi_not_in_crossref = metadata.doi
        else
          # temporary fix of date info until crossref index reloaded
          try
            cr.published = await @src.crossref.works.published cr
            try cr.year = cr.published.split('-')[0]
            try cr.year = parseInt cr.year
            try cr.publishedAt = await @epoch cr.published
          await _metadata cr
        return true
      await Promise.all [_oad(), _crd()] # _fatcat(), 

    return true

  await _searches()


  # if nothing useful can be found and still only have title try using bing - or drop this ability?
  # TODO what to do if this finds anything? re-call the whole find?
  if not metadata.doi and not content and not options.url and not epmc? and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
    try
      mct = unidecode(metadata.title.toLowerCase()).replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
      bong = await @src.microsoft.bing.search mct
      if bong?.data
        bct = unidecode(bong.data[0].name.toLowerCase()).replace('(pdf)','').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
        if mct.replace(/ /g,'').indexOf(bct.replace(/ /g,'')) is 0 #and not await @svc.oaworks.blacklist bong.data[0].url
          # if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
          options.url = bong.data[0].url.replace /"/g, ''
          metadata.pmid = options.url.replace(/\/$/,'').split('/').pop() if typeof options.url is 'string' and options.url.indexOf('pubmed.ncbi') isnt -1
          metadata.doi ?= '10.' + options.url.split('/10.')[1] if typeof options.url is 'string' and options.url.indexOf('/10.') isnt -1
      if metadata.doi or metadata.pmid or options.url
        await _searches() # run again if anything more useful found

  _ill = () =>
    if (metadata.doi or (metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1)) and (options.from or options.config?) and (options.plugin is 'instantill' or options.ill is true)
      try res.ill ?= subscription: await @svc.oaworks.ill.subscription (options.config ? options.from), metadata
    return true
  _permissions = () =>
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper')
      res.permissions ?= await @svc.oaworks.permissions metadata, options.config?.ror, false
    return true
  await Promise.all [_ill(), _permissions()]

  # certain user-provided search values are allowed to override any that we could find ourselves
  # TODO is this ONLY relevant to ILL? or anything else?
  for uo in ['title','journal','year','doi']
    metadata[uo] = options[uo] if options[uo] and options[uo] isnt metadata[uo]

  res.metadata = metadata # if JSON.stringify(metadata) isnt '{}'
  return res


# Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
# Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.svc.oaworks.citation = (citation) ->
  res = {}
  
  try citation ?= @params.citation ? @params
  if typeof citation is 'string' and (citation.indexOf('{') is 0 or citation.indexOf('[') is 0)
    try citation = JSON.parse citation

  if typeof citation is 'object'
    res.doi = citation.DOI ? citation.doi
    res.pmid = citation.pmid if citation.pmid
    res.pmcid = citation.pmcid if citation.pmcid
    try res.type = citation.type ? citation.genre
    res.issn ?= citation.ISSN ? citation.issn ? citation.journalInfo?.journal?.issn ? citation.journal?.issn
    if citation.journalInfo?.journal?.eissn?
      res.issn ?= []
      res.issn = [res.issn] if typeof res.issn is 'string'
      res.issn.push citation.journalInfo.journal.eissn
    res.issn ?= citation.journal_issns.split(',') if citation.journal_issns
    try res.title ?= citation.title[0] if Array.isArray citation.title
    try
      if citation.subtitle? and citation.subtitle.length and citation.subtitle[0].length
        res.title += ': ' + citation.subtitle[0]
    res.title ?= citation.dctitle ? citation.bibjson?.title
    res.title ?= citation.title if citation.title not in [404,'404']
    res.title = res.title.replace(/\s\s+/g,' ').trim() if typeof res.title is 'string'
    try res.journal ?= citation['container-title'][0]
    try res.shortname = citation['short-container-title'][0]
    try res.shortname = citation.journalInfo.journal.isoabbreviation ? citation.journalInfo.journal.medlineAbbreviation
    res.journal ?= citation.journal_name ? citation.journalInfo?.journal?.title ? citation.journal?.title
    res.journal = citation.journal.split('(')[0].trim() if citation.journal
    try res[key] = res[key].charAt(0).toUpperCase() + res[key].slice(1) for key in ['title','journal']
    res.publisher ?= citation.publisher
    res.publisher = res.publisher.trim() if res.publisher
    try res.issue ?= citation.issue if citation.issue?
    try res.issue ?= citation.journalInfo.issue if citation.journalInfo?.issue
    try res.volume ?= citation.volume if citation.volume?
    try res.volume ?= citation.journalInfo.volume if citation.journalInfo?.volume
    try res.page ?= citation.page.toString() if citation.page?
    res.page = citation.pageInfo.toString() if citation.pageInfo
    res.abstract = citation.abstract ? citation.abstractText if citation.abstract or citation.abstractText
    try res.abstract = @convert.html2txt(res.abstract).replace(/\n/g,' ').replace('Abstract ','') if res.abstract

    for p in ['published-print', 'journal-issue.published-print', 'journalInfo.printPublicationDate', 'firstPublicationDate', 'journalInfo.electronicPublicationDate', 'published', 'published_date', 'issued', 'published-online', 'created', 'deposited']
      if typeof res.published isnt 'string'
        if rt = citation[p] ? citation['journal-issue']?[p.replace('journal-issue.','')] ? citation['journalInfo']?[p.replace('journalInfo.','')]
          rt = rt.toString() if typeof rt is 'number'
          try rt = rt['date-time'].toString() if typeof rt isnt 'string'
          if typeof rt isnt 'string'
            try
              for k of rt['date-parts'][0]
                rt['date-parts'][0][k] = '01' if typeof rt['date-parts'][0][k] not in ['number', 'string']
              rt = rt['date-parts'][0].join '-'
          if typeof rt is 'string'
            res.published = if rt.indexOf('T') isnt -1 then rt.split('T')[0] else rt
            res.published = res.published.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace /-(\d)$/, "-0$1"
            res.published += '-01' if res.published.indexOf('-') is -1
            res.published += '-01' if res.published.split('-').length isnt 3
            res.year ?= res.published.split('-')[0]
            delete res.published if res.published.split('-').length isnt 3
            delete res.year if res.year.toString().length isnt 4
        break if res.published
    res.year ?= citation.year if citation.year
    try res.year ?= citation.journalInfo.yearOfPublication.trim()

    if not res.author? and (citation.author? or citation.z_authors? or citation.authorList?.author)
      res.author ?= []
      try
        for a in citation.author ? citation.z_authors ? citation.authorList.author
          if typeof a is 'string'
            res.author.push name: a
          else
            au = {}
            au.given = a.given ? a.firstName
            au.family = a.family ? a.lastName
            au.name = (if au.given then au.given + ' ' else '') + (au.family ? '')
            if a.affiliation?
              try
                for aff in (if au.affiliation then (if Array.isArray(a.affiliation) then a.affiliation else [a.affiliation]) else au.authorAffiliationDetailsList.authorAffiliation)
                  if typeof aff is 'string'
                    au.affiliation ?= []
                    au.affiliation.push name: aff.replace(/\s\s+/g,' ').trim()
                  else if typeof aff is 'object' and (aff.name or aff.affiliation)
                    au.affiliation ?= []
                    au.affiliation.push name: (aff.name ? aff.affiliation).replace(/\s\s+/g,' ').trim()
            res.author.push au

    try res.subject = citation.subject if citation.subject? and citation.subject.length and typeof citation.subject[0] is 'string'
    try res.keyword = citation.keywordList.keyword if citation.keywordList?.keyword? and citation.keywordList.keyword.length and typeof citation.keywordList.keyword[0] is 'string'
    try
      for m in [...(citation.meshHeadingList?.meshHeading ? []), ...(citation.chemicalList?.chemical ? [])]
        res.keyword ?= []
        mn = if typeof m is 'string' then m else m.name ? m.descriptorName
        res.keyword.push mn if typeof mn is 'string' and mn and mn not in res.keyword

    res.licence = citation.license.trim().replace(/ /g,'-') if typeof citation.license is 'string'
    res.licence = citation.licence.trim().replace(/ /g,'-') if typeof citation.licence is 'string'
    try res.licence ?= citation.best_oa_location.license if citation.best_oa_location?.license and citation.best_oa_location?.license isnt null
    if not res.licence
      if Array.isArray citation.assertion
        for a in citation.assertion
          if a.label is 'OPEN ACCESS' and a.URL and a.URL.indexOf('creativecommons') isnt -1
            res.licence ?= a.URL # and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
      if Array.isArray citation.license
        for l in citation.license ? []
          if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not res.licence or res.licence.indexOf('creativecommons') is -1)
            res.licence ?= l.URL
    if typeof res.licence is 'string' and res.licence.indexOf('/licenses/') isnt -1
      res.licence = 'cc-' + res.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-').replace(/-$/, '')

    # if there is a URL to use but not open, store it as res.paywall
    res.url ?= citation.best_oa_location?.url_for_pdf ? citation.best_oa_location?.url #? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?
    if not res.url and citation.fullTextUrlList?.fullTextUrl? # epmc fulltexts
      for cf in citation.fullTextUrlList.fullTextUrl
        if cf.availabilityCode.toLowerCase() in ['oa','f'] and (not res.url or (cf.documentStyle is 'pdf' and res.url.indexOf('pdf') is -1))
          res.url = cf.url

  else if typeof citation is 'string'
    try
      citation = citation.replace(/citation\:/gi,'').trim()
      citation = citation.split('title')[1].trim() if citation.indexOf('title') isnt -1
      citation = citation.replace(/^"/,'').replace(/^'/,'').replace(/"$/,'').replace(/'$/,'')
      res.doi = citation.split('doi:')[1].split(',')[0].split(' ')[0].trim() if citation.indexOf('doi:') isnt -1
      res.doi = citation.split('doi.org/')[1].split(',')[0].split(' ')[0].trim() if citation.indexOf('doi.org/') isnt -1
      if not res.doi and citation.indexOf('http') isnt -1
        res.url = 'http' + citation.split('http')[1].split(' ')[0].trim()
      try
        if citation.indexOf('|') isnt -1 or citation.indexOf('}') isnt -1
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
          res.title = res.title.replace(')','') if res.title.indexOf('(') is -1 or res.title.indexOf(')') < res.title.indexOf('(')
          res.title = res.title.replace('.','') if res.title.indexOf('.') < 3
          res.title = res.title.replace(',','') if res.title.indexOf(',') < 3
          res.title = res.title.trim()
          if res.title.indexOf('.') isnt -1
            res.title = res.title.split('.')[0]
          else if res.title.indexOf(',') isnt -1
            res.title = res.title.split(',')[0]
      if res.title
        try
          bt = citation.split(res.title)[0]
          bt = bt.split(res.year)[0] if res.year and bt.indexOf(res.year) isnt -1
          bt = bt.split(res.url)[0] if res.url and bt.indexOf(res.url) > 0
          bt = bt.replace(res.url) if res.url and bt.indexOf(res.url) is 0
          bt = bt.replace(res.doi) if res.doi and bt.indexOf(res.doi) is 0
          bt = bt.replace('.','') if bt.indexOf('.') < 3
          bt = bt.replace(',','') if bt.indexOf(',') < 3
          bt = bt.substring(0,bt.lastIndexOf('(')) if bt.lastIndexOf('(') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(')')) if bt.lastIndexOf(')') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf(',')) if bt.lastIndexOf(',') > (bt.length-3)
          bt = bt.substring(0,bt.lastIndexOf('.')) if bt.lastIndexOf('.') > (bt.length-3)
          bt = bt.trim()
          if bt.length > 6
            if bt.indexOf(',') isnt -1
              res.author = []
              res.author.push({name: ak}) for ak in bt.split(',')
            else
              res.author = [{name: bt}]
        try
          rmn = citation.split(res.title)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.indexOf(res.url) isnt -1
          rmn = rmn.replace(res.doi) if res.doi and rmn.indexOf(res.doi) isnt -1
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 6
            res.journal = rmn
            res.journal = res.journal.split(',')[0].replace(/in /gi,'').trim() if rmn.indexOf(',') isnt -1
            res.journal = res.journal.replace('.','') if res.journal.indexOf('.') < 3
            res.journal = res.journal.replace(',','') if res.journal.indexOf(',') < 3
            res.journal = res.journal.trim()
      try
        if res.journal
          rmn = citation.split(res.journal)[1]
          rmn = rmn.replace(res.url) if res.url and rmn.indexOf(res.url) isnt -1
          rmn = rmn.replace(res.doi) if res.doi and rmn.indexOf(res.doi) isnt -1
          rmn = rmn.replace('.','') if rmn.indexOf('.') < 3
          rmn = rmn.replace(',','') if rmn.indexOf(',') < 3
          rmn = rmn.trim()
          if rmn.length > 4
            rmn = rmn.split('retrieved')[0] if rmn.indexOf('retrieved') isnt -1
            rmn = rmn.split('Retrieved')[0] if rmn.indexOf('Retrieved') isnt -1
            res.volume = rmn
            if res.volume.indexOf('(') isnt -1
              res.volume = res.volume.split('(')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split('(')[1].split(')')[0]
                res.issue = res.issue.trim()
            if res.volume.indexOf(',') isnt -1
              res.volume = res.volume.split(',')[0]
              res.volume = res.volume.trim()
              try
                res.issue = rmn.split(',')[1]
                res.issue = res.issue.trim()
            if res.volume
              try
                delete res.volume if isNaN parseInt res.volume
            if res.issue
              if res.issue.indexOf(',') isnt -1
                res.issue = res.issue.split(',')[0].trim()
              try
                delete res.issue if isNaN parseInt res.issue
            if res.volume and res.issue
              try
                rmn = citation.split(res.journal)[1]
                rmn = rmn.split('retriev')[0] if rmn.indexOf('retriev') isnt -1
                rmn = rmn.split('Retriev')[0] if rmn.indexOf('Retriev') isnt -1
                rmn = rmn.split(res.url)[0] if res.url and rmn.indexOf(res.url) isnt -1
                rmn = rmn.split(res.doi)[0] if res.doi and rmn.indexOf(res.doi) isnt -1
                rmn = rmn.substring(rmn.indexOf(res.volume)+(res.volume+'').length)
                rmn = rmn.substring(rmn.indexOf(res.issue)+(res.issue+'').length)
                rmn = rmn.replace('.','') if rmn.indexOf('.') < 2
                rmn = rmn.replace(',','') if rmn.indexOf(',') < 2
                rmn = rmn.replace(')','') if rmn.indexOf(')') < 2
                rmn = rmn.trim()
                if not isNaN parseInt rmn.substring(0,1)
                  res.pages = rmn.split(' ')[0].split('.')[0].trim()
                  res.pages = res.pages.split(', ')[0] if res.pages.length > 5
      if not res.author and citation.indexOf('et al') isnt -1
        cn = citation.split('et al')[0].trim()
        if citation.indexOf(cn) is 0
          res.author = [{name: cn + 'et al'}]
      if res.title and not res.volume
        try
          clc = citation.split(res.title)[1].toLowerCase().replace('volume','vol').replace('vol.','vol').replace('issue','iss').replace('iss.','iss').replace('pages','page').replace('pp','page')
          if clc.indexOf('vol') isnt -1
            res.volume = clc.split('vol')[1].split(',')[0].split('(')[0].split('.')[0].split(' ')[0].trim()
          if not res.issue and clc.indexOf('iss') isnt -1
            res.issue = clc.split('iss')[1].split(',')[0].split('.')[0].split(' ')[0].trim()
          if not res.pages and clc.indexOf('page') isnt -1
            res.pages = clc.split('page')[1].split('.')[0].split(', ')[0].split(' ')[0].trim()

  res.year = res.year.toString() if typeof res.year is 'number'
  return res


# temporary legacy wrapper for old site front page availability check
# that page should be moved to use the new embed, like shareyourpaper
P.svc.oaworks.availability = (params, v2) ->
  params ?= @copy @params
  delete @params.dom
  if params.availability
    if params.availability.startsWith('10.') and params.availability.indexOf('/') isnt -1
      params.doi = params.availability
    else if params.availability.indexOf(' ') isnt -1
      params.title = params.availability
    else
      params.id = params.availability
    delete params.availability
  params.url = params.url[0] if Array.isArray params.url
  if not params.test and params.url and false #await @svc.oaworks.blacklist params.url
    params.dom = 'redacted' if params.dom
    return status: 400
  else
    afnd = {data: {availability: [], requests: [], accepts: [], meta: {article: {}, data: {}}}}
    if params?
      afnd.data.match = params.doi ? params.pmid ? params.pmc ? params.pmcid ? params.title ? params.url ? params.id ? params.citation ? params.q
    afnd.v2 = v2 if typeof v2 is 'object' and JSON.stringify(v2) isnt '{}' and v2.metadata?
    afnd.v2 ?= await @svc.oaworks.find params
    if afnd.v2?
      afnd.data.match ?= afnd.v2.input ? afnd.v2.metadata?.doi ? afnd.v2.metadata?.title ? afnd.v2.metadata?.pmid ? afnd.v2.metadata?.pmc ? afnd.v2.metadata?.pmcid ? afnd.v2.metadata?.url
      afnd.data.match = afnd.data.match[0] if Array.isArray afnd.data.match
      try
        afnd.data.ill = afnd.v2.ill
        afnd.data.meta.article = JSON.parse(JSON.stringify(afnd.v2.metadata)) if afnd.v2.metadata?
        afnd.data.meta.article.url = afnd.data.meta.article.url[0] if Array.isArray afnd.data.meta.article.url
        if afnd.v2.url? and not afnd.data.meta.article.source?
          afnd.data.meta.article.source = 'oaworks' # source doesn't play significant role any more, could prob just remove this if not used anywhere
        if afnd.v2.url
          afnd.data.availability.push type: 'article', url: (if Array.isArray(afnd.v2.url) then afnd.v2.url[0] else afnd.v2.url)
      try
        if afnd.data.availability.length is 0 and (afnd.v2.metadata.doi or afnd.v2.metadata.title or afnd.v2.meadata.url)
          if afnd.v2.metadata.doi
            qry = 'doi.exact:"' + afnd.v2.metadata.doi + '"'
          else if afnd.v2.metadata.title
            qry = 'title.exact:"' + afnd.v2.metadata.title + '"'
          else
            qry = 'url.exact:"' + (if Array.isArray(afnd.v2.metadata.url) then afnd.v2.metadata.url[0] else afnd.v2.metadata.url) + '"'
          if qry # ' + (if @S.dev then 'dev.' else '') + '
            resp = await @fetch 'https://api.cottagelabs.com/service/oab/requests?q=' + qry + ' AND type:article&sort=createdAt:desc'
            if resp?.hits?.total
              request = resp.hits.hits[0]._source
              rq = type: 'article', _id: request._id
              rq.ucreated = if params.uid and request.user?.id is params.uid then true else false
              afnd.data.requests.push rq
    afnd.data.accepts.push({type:'article'}) if afnd.data.availability.length is 0 and afnd.data.requests.length is 0
    return afnd

P.svc.oaworks.availability._hide = true