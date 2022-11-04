
P.metadata = (doi) ->
  res = await @find doi # may not be a DOI, but most likely thing
  return res?.metadata


P.find = (options, metadata={}, content) ->
  res = {}

  _metadata = (input) =>
    ct = await @citation input
    for k of ct
      if k in ['url', 'paywall']
        res[k] ?= ct[k]
      else
        metadata[k] ?= ct[k]
    return true

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
  if not metadata.title and content and typeof options.url is 'string' and (options.url.includes('alma.exlibrisgroup.com') or options.url.includes '/exlibristest')
    delete options.url

  # set a demo tag in certain cases
  # e.g. for instantill/shareyourpaper/other demos - dev and live demo accounts
  res.demo = options.demo if options.demo?
  res.demo ?= true if (metadata.doi is '10.1234/567890' or (metadata.doi? and metadata.doi.startsWith '10.1234/oab-syp-')) or metadata.title is 'Engineering a Powerfully Simple Interlibrary Loan Experience with InstantILL' or options.from in ['qZooaHWRz9NLFNcgR','eZwJ83xp3oZDaec86']
  res.test ?= true if res.demo # don't save things coming from the demo accounts into the catalogue later

  epmc = false
  mag = false
  _searches = () =>
    if (content? or options.url?) and not (metadata.doi or metadata.pmid? or metadata.pmcid? or metadata.title?)
      scraped = await @scrape content ? options.url
      await _metadata scraped

    if not metadata.doi
      if metadata.pmid or metadata.pmcid
        epmc = await @src.epmc[if metadata.pmcid then 'pmc' else 'pmid'] (metadata.pmcid ? metadata.pmid)
        await _metadata epmc
      if not metadata.doi and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
        metadata.title = metadata.title.replace /\+/g, ' ' # some+titles+come+in+like+this
        cr = await @src.crossref.works.title metadata.title
        await _metadata(cr) if cr?.type and cr?.DOI
        if not metadata.doi
          mag = await @src.microsoft.graph metadata.title
          await _metadata(mag) if mag isnt false and mag?.PaperTitle
        if not metadata.doi and not epmc
          epmc = await @src.epmc.title metadata.title
          await _metadata(epmc) if epmc isnt false

    if metadata.doi
      _oad = () =>
        oad = await @src.oadoi metadata.doi
        res.doi_not_in_oadoi = metadata.doi if not oad?
        await _metadata(oad) if oad?.doi and metadata?.doi and oad.doi.toLowerCase() is metadata.doi.toLowerCase() # check again for doi in case removed by failed crossref lookup
        return true
      _crd = () =>
        cr = await @src.crossref.works metadata.doi
        cr ?= await @src.crossref.works.doi metadata.doi
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
      await Promise.all [_oad(), _crd()]

    return true

  await _searches()

  # if nothing useful can be found and still only have title try using bing - or drop this ability?
#  if mag isnt false and not metadata.doi and not content and not options.url and not epmc and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
#    mct = metadata.title.toLowerCase().replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ') # this previously had a unidecode on it...
#    bong = await @src.microsoft.bing mct
#    if bong?.data and bong.data.length
#      bct = bong.data[0].name.toLowerCase().replace('(pdf)', '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s\s+/g, ' ') # this had unidecode to match to above...
#      if mct.replace(/ /g, '').startsWith bct.replace(/ /g, '') #and not await @blacklist bong.data[0].url
#        # if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
#        options.url = bong.data[0].url.replace /"/g, ''
#        metadata.pmid = options.url.replace(/\/$/,'').split('/').pop() if typeof options.url is 'string' and options.url.includes 'pubmed.ncbi'
#        metadata.doi ?= '10.' + options.url.split('/10.')[1] if typeof options.url is 'string' and options.url.includes '/10.'
#    if metadata.doi or metadata.pmid or options.url
#      await _searches() # run again if anything more useful found

  _ill = () =>
    if (metadata.doi or (metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1)) and (options.from or options.config?) and (options.plugin is 'instantill' or options.ill is true)
      try res.ill ?= subscription: await @ill.subscription (options.config ? options.from), metadata
    return true
  _permissions = () =>
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper')
      res.permissions ?= await @permissions metadata, options.config?.ror, false
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
P.citation = (citation) ->
  res = {}
  
  try citation ?= @params.citation ? @params
  if typeof citation is 'string' and (citation.startsWith('{') or citation.startsWith '[')
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
    res.journal_short = res.shortname if res.shortname and not res.journal_short # temporary fix for change to metadata field name
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
          if a.label is 'OPEN ACCESS' and a.URL and a.URL.includes 'creativecommons'
            res.licence ?= a.URL # and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
      if Array.isArray citation.license
        for l in citation.license ? []
          if l.URL and l.URL.includes('creativecommons') and (not res.licence or not res.licence.includes 'creativecommons')
            res.licence ?= l.URL
    if typeof res.licence is 'string' and res.licence.includes '/licenses/'
      res.licence = 'cc-' + res.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-').replace(/-$/, '')

    # if there is a URL to use but not open, store it as res.paywall
    res.url ?= citation.best_oa_location?.url_for_pdf ? citation.best_oa_location?.url #? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?
    if not res.url and citation.fullTextUrlList?.fullTextUrl? # epmc fulltexts
      for cf in citation.fullTextUrlList.fullTextUrl
        if cf.availabilityCode.toLowerCase() in ['oa','f'] and (not res.url or (cf.documentStyle is 'pdf' and not res.url.includes 'pdf'))
          res.url = cf.url

  else if typeof citation is 'string'
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


# temporary legacy wrapper for old site front page availability check
# that page should be moved to use the new embed, like shareyourpaper
P.availability = (params, v2) ->
  params ?= @copy @params
  delete @params.dom
  if params.availability
    if params.availability.startsWith('10.') and params.availability.includes '/'
      params.doi = params.availability
    else if params.availability.includes ' '
      params.title = params.availability
    else
      params.id = params.availability
    delete params.availability
  params.url = params.url[0] if Array.isArray params.url
  if not params.test and params.url and false #await @blacklist params.url
    params.dom = 'redacted' if params.dom
    return status: 400
  else
    afnd = {data: {availability: [], requests: [], accepts: [], meta: {article: {}, data: {}}}}
    if params?
      afnd.data.match = params.doi ? params.pmid ? params.pmc ? params.pmcid ? params.title ? params.url ? params.id ? params.citation ? params.q
    afnd.v2 = v2 if typeof v2 is 'object' and JSON.stringify(v2) isnt '{}' and v2.metadata?
    afnd.v2 ?= await @find params
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
