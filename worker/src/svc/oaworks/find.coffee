
P.svc.oaworks.metadata = () ->
  res = await @svc.oaworks.find()
  return res.metadata


P.svc.oaworks.find = (options, metadata={}, content) ->
  res = {}

  _metadata = (input) =>
    for k of ct = await @svc.oaworks.citation input
      if k in ['url', 'paywall']
        res[k] ?= ct[k]
      else
        metadata[k] ?= ct[k]

  try options ?= @copy @params
  options ?= {}
  options.doi ?= options.find
  content ?= options.dom ? @request.body

  options.url = (options.q ? options.id) if options.q or options.id
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
  if options.title and (options.title.indexOf('{') isnt -1 or (options.title.replace('...','').match(/\./gi) ? []).length > 3 or (options.title.match(/\(/gi) ? []).length > 2)
    options.citation = options.title # titles that look like citations
    delete options.title

  metadata.doi ?= options.doi
  metadata.title ?= options.title
  metadata.pmid ?= options.pmid
  metadata.pmcid ?= options.pmcid ? options.pmc
  await _metadata(options.citation) if options.citation
  try metadata.title = metadata.title.replace(/(<([^>]+)>)/g,'').replace(/\+/g,' ').trim()
  try metadata.doi = metadata.doi.split(' ')[0].replace('http://','').replace('https://','').replace('doi.org/','').replace('doi:','').trim()
  delete metadata.doi if typeof metadata.doi isnt 'string' or metadata.doi.indexOf('10.') isnt 0

  # switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if not metadata.title and content and typeof options.url is 'string' and (options.url.indexOf('alma.exlibrisgroup.com') isnt -1 or options.url.indexOf('/exlibristest') isnt -1)
    delete options.url

  _searches = () =>
    if (content? or options.url?) and not (metadata.doi or metadata.pmid? or metadata.pmcid? or metadata.title?)
      await _metadata await @svc.oaworks.scrape content ? options.url

    if not metadata.doi
      if metadata.pmid or metadata.pmcid
        epmc = await @src.epmc[if metadata.pmcid then 'pmc' else 'pmid'] (metadata.pmcid ? metadata.pmid)
        await _metadata epmc
      if metadata.title and not metadata.doi
        _crt = () =>
          await _metadata(await @src.crossref.works metadata.title) if not metadata.doi
          return true
        _mst = () =>
          await _metadata(await @src.microsoft.graph metadata.title) if not metadata.doi
          return true
        _pmt = () =>
          await _metadata(await @src.epmc.title metadata.title) if not epmc? and not metadata.doi
          return true
        await Promise.all [_crt(), _mst(), _pmt()]
  
    if metadata.doi
      _oad = () =>
        oad = await @src.oadoi metadata.doi
        await _metadata(oad) if oad?.doi is metadata.doi
        return true
      _crd = () =>
        cr = await @src.crossref.works metadata.doi
        if not cr?.type
          res.doi_not_in_crossref = metadata.doi
          delete options.url if typeof options.url is 'string' and options.url.indexOf('doi.org/' + metadata.doi) isnt -1
          delete metadata.doi
        else
          await _metadata cr
        return true
      await Promise.all [_oad(), _crd()]
    
    return true

  await _searches()

  # if nothing useful can be found and still only have title try using bing - or drop this ability?
  # TODO what to do if this finds anything? re-call the whole find?
  if metadata.title and not metadata.doi and not content and not options.url and not epmc?
    try
      mct = unidecode(metadata.title.toLowerCase()).replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
      bong = await @src.microsoft.bing.search mct
      if bong?.data? and bong.data.length
        bct = unidecode(bong.data[0].name.toLowerCase()).replace('(pdf)','').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
        if mct.replace(/ /g,'').indexOf(bct.replace(/ /g,'')) is 0 and not await @svc.oaworks.blacklist bong.data[0].url
          # if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
          options.url = bong.data[0].url.replace /"/g, ''
          metadata.pmid = options.url.replace(/\/$/,'').split('/').pop() if typeof options.url is 'string' and options.url.indexOf('pubmed.ncbi') isnt -1
          metadata.doi ?= '10.' + options.url.split('/10.')[1] if typeof options.url is 'string' and options.url.indexOf('/10.') isnt -1
      if metadata.doi or metadata.pmid or options.url
        await _searches() # run again if anything more useful found

  _ill = () =>
    if (metadata.doi or metadata.title) and (options.from? or options.config?) and (options.plugin is 'instantill' or options.ill is true)
      res.ill ?= {} # terms and openurl can be done client-side by new embed but old embed can't so keep these a while longer
      try res.ill.terms = options.config?.terms ? await @svc.oaworks.ill.terms options.from
      try res.ill.openurl = await @svc.oaworks.ill.openurl (options.config ? options.from), metadata
      try res.ill.subscription = await @svc.oaworks.ill.subscription (options.config ? options.from), metadata, res.refresh
    return true
  _permissions = () =>
    if metadata.doi and (options.permissions or options.plugin is 'shareyourpaper') # don't get permissions by default now that the permissions check could take longer
      res.permissions ?= await @svc.oaworks.permissions metadata, (options.config ? options.from)
    return true
  await Promise.all [_ill(), _permissions()]

  # certain user-provided search values are allowed to override any that we could find ourselves, and we note that we got these from the user
  # is it worth keeping this in the backend or just have the embed handle it now that embed handles redirects to ill requests?
  # is this ONLY relevant to ILL? or anything else?
  for uo in ['title','journal','year','doi']
    metadata[uo] = options[uo] if options[uo] and options[uo] isnt metadata[uo]

  res.metadata = metadata
  return res


# Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
# Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.svc.oaworks.citation = (citation) ->
  res = {}
  
  try citation ?= @params.citation ? @params
  if typeof citation is 'string' and (citation.indexOf('{') is 0 or citation.indexOf('[') is 0)
    try citation = JSON.parse options.citation

  if typeof citation is 'object'
    res.doi ?= citation.DOI ? citation.doi
    try res.type ?= citation.type ? citation.genre
    res.issn ?= citation.ISSN ? citation.issn ? citation.journalInfo?.journal?.issn ? citation.journal?.issn
    res.issn ?= citation.journal_issns.split(',') if citation.journal_issns
    try res.title ?= citation.title[0] if Array.isArray citation.title
    try
      if citation.subtitle? and citation.subtitle.length and citation.subtitle[0].length
        res.title += ': ' + citation.subtitle[0]
    res.title ?= citation.dctitle ? citation.bibjson?.title
    res.title ?= citation.title if citation.title not in [404,'404']
    res.title = res.title.replace(/\s\s+/g,' ').trim() if res.title
    try res.journal ?= citation['container-title'][0]
    try res.shortname = citation['short-container-title'][0]
    res.journal ?= citation.journal_name ? citation.journalInfo?.journal?.title ? citation.journal?.title
    res.journal = citation.journal.split('(')[0].trim() if citation.journal
    res.publisher ?= citation.publisher
    try res.issue ?= citation.issue if citation.issue?
    try res.volume ?= citation.volume if citation.volume?
    try res.page ?= citation.page.toString() if citation.page?
    for key in ['title','journal']
      if not res[key] and typeof citation[key] is 'string' and (citation[key].charAt(0).toUpperCase() isnt citation[key].charAt(0) or citation[key].toUpperCase() is citation.key or citation[key].toLowerCase() is citation.key)
        res[key] = citation[key].charAt(0).toUpperCase() + citation[key].slice(1)
    if not res.year? and (citation.year? or citation.published? or citation.published_date?)
      try
        for ms in (citation.year ? citation.published ? citation.published_date).split(if (citation.year ? citation.published ? citation.published_date).indexOf('/') isnt -1 then '/' else '-')
          res.year ?= ms if ms.length is 4
      try
        delete res.year if typeof res.year isnt 'number' and (res.year.length isnt 4 or res.year.replace(/[0-9]/gi,'').length isnt 0)
      res.year = res.year.toString() if typeof res.year is 'number'
    if not res.year? and not res.published?
      for p in ['published-print','journal-issue.published-print','issued','published-online','created','deposited','indexed']
        try
          if rt = citation[p] ? citation['journal-issue']?[p.replace('journal-issue.','')]
            if typeof rt['date-time'] is 'string' and rt['date-time'].indexOf('T') isnt -1 and rt['date-time'].split('T')[0].split('-').length is 3
              res.published ?= rt['date-time'].split('T')[0]
              res.year ?= res.published.split('-')[0]
              break
            else if rt['date-parts']? and rt['date-parts'].length and Array.isArray(rt['date-parts'][0]) and rt['date-parts'][0].length
              rp = rt['date-parts'][0]
              pbl = rp[0].toString()
              if pbl.length > 2 # needs to be a year
                res.year ?= pbl
                if rp.length is 1
                  pbl += '-01-01'
                else
                  m = false
                  d = false
                  if not isNaN(parseInt(rp[1])) and parseInt(rp[1]) > 12
                    d = rp[1].toString()
                  else
                    m = rp[1].toString()
                  if rp.length is 2
                    if d isnt false
                      m = rp[2].toString()
                    else
                      d = rp[2].toString()
                  m = if m is false then '01' else if m.length is 1 then '0' + m else m
                  d = if d is false then '01' else if d.length is 1 then '0' + d else d
                  pbl += '-' + m + '-' + d
                res.published ?= pbl
                break
    try
      if not res.author? and (citation.author? or citation.z_authors?)
        res.author ?= []
        # what formats do we want for authors? how much metadata about them?
        for a in citation.author ? citation.z_authors
          if typeof a is 'string'
            res.author.push {name: a}
          else
            if a.affiliation?
              a.affiliation = a.affiliation[0] if Array.isArray a.affiliation
              a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
            res.author.push a
    #for i of citation # should we grab everything else too? probably not
    #  res[i] ?= citation[i] if typeof citation[i] is 'string' or Array.isArray citation[i]
    try res.licence ?= citation.best_oa_location.license if citation.best_oa_location?.license and citation.best_oa_location?.license isnt null
    if Array.isArray citation.assertion
      for a in citation.assertion
        if a.label is 'OPEN ACCESS' and a.URL and a.URL.indexOf('creativecommons') isnt -1
          res.licence ?= a.URL # and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
    if Array.isArray citation.license
      for l in citation.license ? []
        if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not rec.licence or rec.licence.indexOf('creativecommons') is -1)
          res.licence ?= l.URL
    if typeof citation.license is 'string'
      res.licence ?= citation.license
    if typeof res.licence is 'string' and res.licence.indexOf('/licenses/') isnt -1
      res.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/$\//,'').replace(/\//g, '-')
    # if there is a URL to use but not open, store it as res.paywall
    res.url ?= citation.best_oa_location?.url_for_pdf ? citation.best_oa_location?.url ? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?

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

  return res




'''
there would be an index called svc_oaworks_find (possibly namespaced to service name and env, or global)
may also want to allow explicit naming of the index, not the same as the route
so the usual index operations have to be available under P.svc.oaworks.find
at /find we should serve the index of find results

when .find is called, we need to know whether it is:
  an attempt to get back one specific find (e.g. it was already previously run so the result exists)
    so url params could do this - e.g. pass /find/10.1234/567890 or /find/id/1234 or /find/title/blah blah
    and may want to check kv as well if set for this endpoint
    check kv would entail:
      look up the full url (with params?)
      or look up a provided ID
      
  an attempt to run find
    which could run if the above lookup returns nothing (or more than one?)
    or if refresh is true, always run
    so find needs a .run to fall back to (and if doesn't have one, nothing populates the index on a fail to find)
    after .run:
      save to index 
      index should also save a history if configured to do so
      and save to kv if set to do so
        would it be possible to also set multiple routes to point to one kv result?
        like if a find on /find/10.1234/567890 should also be findable by /find/pmid/12345678
      
  an attempt to search finds
    when there is no provided url params, and no query params that could be used to get back one specific one
    or when there is a definitive search param provided, such as q or query or source?
    
{
  env: may want to specify the env we are in (defaults to infer from Settings). Or false to be global to any env
  index: false 'optional_index_name' # optional, otherwise inferred from the url route - or could be false while kv is true
  history: false # if true, on every edit, save a copy of the previous state of the record (requires index)
  kv: false # whether or not to also store in the kv layer (default false). prob not worth using kv AND cache
  cache: false # cache the results of the fetch requests to the index. could be true or false or a number for how long to cache
  # also need a way to record the user ID of whoever caused a historic change, if available
}

what goes into the log as the recorded response for this sort of route?
'''
