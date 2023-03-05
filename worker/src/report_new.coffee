
P.report.orgs.supplements = _index: true, _auth: '@oa.works'

#P.report.orgs = _sheet: S.report.orgs_sheet, _format: (recs=[]) ->
P.report.orgs.supplements.load = (orgname, sheetname, clear) ->
  clear ?= @params.clear
  await @report.orgs.supplements('') if clear
  orgname ?= @params.org
  sheetname ?= @params.sheet
  recs = await @src.google.sheets S.report.orgs_sheet
  ready = []
  total = 0
  deletes = []
  dois = []
  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    org = {}
    for h of rec
      if typeof rec[h] is 'string'
        rec[h] = rec[h].trim()
        if rec[h].toLowerCase() is 'true'
          rec[h] = true
        else if rec[h].toLowerCase() is 'false'
          rec[h] = false
        else if ((rec[h].startsWith('[') and rec[h].endsWith(']')) or (rec[h].startsWith('{') and rec[h].endsWith('}')))
          try rec[h] = JSON.parse rec[h]
        else if rec[h].includes ';'
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split ';'
      if h.includes '.'
        try @dot org, h, rec[h]
      else
        org[h] = rec[h]
    if Array.isArray org.sheets
      for s in org.sheets
        if (not orgname or org.name is orgname) and (not sheetname or s.name is sheetname)
          console.log org.name, s.name, s.url
          osdids = []
          headers = []
          try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
          tries = 0
          while (not Array.isArray(rows) or not rows.length) and tries < 3 # https://github.com/oaworks/Gates/issues/375
            await @sleep 2000
            tries += 1
            try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
          if Array.isArray(rows) and rows.length
            sups = []
            headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
            org.supplements = 0
            for row in rows
              rr = org: org.name, sheet: s.name, ror: org.ror, paid: org.paid
              for hp of headers
                h = headers[hp]
                if h in ['doi', 'DOI']
                  rr[h] = row[hp]
                else if h is 'apc_cost'
                  try rr.apc_cost = parseInt row[hp]
                else if h.includes '.'
                  await @dot rr, h, if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if h.toLowerCase() in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else if typeof row[hp] is 'string' and row[hp].includes(';') then row[hp].split(';') else row[hp]
                else
                  rr[h] = if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if h.toLowerCase() in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else row[hp]
                  rr[h] = rr[h].split(';') if typeof rr[h] is 'string' and rr[h].includes ';'
              rr.DOI ?= rr.doi
              try rr.DOI = '10.' + rr.DOI.split('/10.')[1] if rr.DOI and rr.DOI.startsWith 'http'
              try rr.DOI = rr.DOI.toLowerCase().replace('doi ', '') if rr.DOI.startsWith 'doi '
              rr.DOI = rr.DOI.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/ /g, '').replace(/^\//, '').split('?')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '') if rr.DOI # catch dirty DOIs like 10.1021/acscentsci.0c00732?ref=pdf
              if rr.DOI and rr.DOI.startsWith '10.'
                rr.email = await @encrypt(rr.email) if typeof rr.email is 'string' and rr.email.includes '@'
                rr._id = rr.osdid = (org.name.replace(/[^a-zA-Z0-9-_ ]/g, '') + '_' + s.name + '_' + rr.DOI).replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
                osdids.push rr.osdid
                if rr.DOI not in dois
                  present = if clear then undefined else await @report.orgs.supplements _id: rr.osdid
                  differs = not present?
                  if not differs
                    kc = await @copy rr
                    for k of present
                      differs = true if (Array.isArray(rr[k]) and (not Array.isArray(present[k]) or rr[k].length isnt present[k].length)) or (typeof rr[k] is 'object' and (typeof present[k] isnt 'object' or JSON.stringify(rr[k]) isnt JSON.stringify(present[k]))) or rr[k] isnt present[k] # JSON string match on object isn't guaranteed but probably likely enough for the number of times we'll need it
                      break if differs
                      delete kc[k]
                  dois.push(rr.DOI) if differs or JSON.stringify(kc) isnt '{}'
                sups.push rr
                org.supplements += 1
                total += 1
            console.log org.name, s.name, sups.length
            await @report.orgs.supplements sups
          for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'org.keyword:"' + org.name + '" AND sheet.keyword:"' + s.name + '"', scroll: '5m', include: ['osdid', 'DOI'], sort: 'osdid.keyword': 'asc'
            if sup.osdid not in osdids
              await @report.orgs.supplements sup.osdid, ''
              deletes.push sup.osdid
              dois.push(sup.DOI) if sup.DOI not in dois # need to rerun for ones where something has been deleted too so that deleted supplemen ts get removed from the work
        s.url = await @encrypt s.url
    else
      delete org.sheets
    ready.push(org) if JSON.stringify(org) isnt '{}'

  await @sleep 60000 # wait a while for the supplements index to finish building and then run the processing for DOIs
  #@report.articles.load undefined, undefined, dois
  console.log 'report orgs supplements load', total, dois.length, deletes.length
  return total #if ready.length is 1 then ready[0] else ready
#P.report.orgs.supplements.load._async = true
P.report.orgs.supplements.load._auth = '@oa.works'

P.report.articles = _index: true, _prefix: false

P.report.articles.process = (cr, openalex, refresh) ->
  started = await @epoch()
  refresh ?= @refresh
  if cr? and refresh isnt true
    exists = await @report.articles if typeof cr is 'string' then cr else cr.DOI
    exists = undefined if not exists?.updated or (refresh and exists and exists.updated < refresh)
  cr ?= @params.process # if called with DOI directly on URL do a complete process, not just a rerun from any current indexed record

  cr = xref if not exists? and typeof cr is 'string' and cr.startsWith('10.') and xref = await @src.crossref.works _id: cr
  cr = undefined if typeof cr is 'object' and not cr.DOI
  if cr? and not exists?.openalex
    openalex ?= await @src.openalex.works _id: if typeof cr is 'object' then cr.DOI else cr
    openalex = undefined if not openalex?.id

  if typeof cr is 'object' and cr.DOI
    rec = DOI: cr.DOI.toLowerCase(), subject: cr.subject, subtitle: cr.subtitle, volume: cr.volume, published_year: cr.year, issue: cr.issue, publisher: cr.publisher, published_date: cr.published, funder: cr.funder, issn: cr.ISSN
    for ass in (cr.assertion ? [])
      assl = (ass.label ? '').toLowerCase()
      rec.accepted_date ?= cr.assertion.value if assl.includes('accepted') and not assl.split(' ').length > 2
      rec.submitted_date ?= cr.assertion.value if assl.includes 'received'
    delete f['doi-asserted-by'] for f in rec.funder ? []
    rec.title = cr.title[0] if cr.title and cr.title.length
    rec.journal = cr['container-title'][0] if cr['container-title'] and cr['container-title'].length
    for lc in cr.license ? []
      rec['crossref_license_url_' + lc['content-version']] = lc.URL if lc['content-version'] in ['am', 'vor', 'tdm', 'unspecified']
    rec.crossref_is_oa = if not cr.is_oa? then false else cr.is_oa

  if openalex?
    rec ?= {}
    rec.openalex = openalex.id.split('/').pop() if openalex.id
    rec.DOI = openalex.ids.doi.split('doi.org/').pop().toLowerCase() if not rec.DOI and openalex.ids?.doi?
    rec.PMID = openalex.ids.pmid.split('/').pop() if openalex.ids?.pmid
    rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if not rec.PMCID and openalex.ids?.pmcid
    rec.title = openalex.title if openalex.title
    rec[ok] = openalex[ok] for ok in ['authorships', 'concepts', 'cited_by_count', 'type', 'is_paratext', 'is_retracted']
    rec.published_date = openalex.publication_date if openalex.publication_date
    rec.published_year = openalex.publication_year if openalex.publication_year
    rec.issn = openalex.host_venue.issn if openalex.host_venue?.issn
    for c in rec.concepts ? []
      delete c.wikidata
      try c.score = Math.floor(c.score * 100)
    for a in rec.authorships ? []
      delete i.type for i in a.institutions ? []

  if not rec?
    rec = {}
    rec.DOI = cr.toLowerCase() if typeof cr is 'string'
    if exists?
      rec[k] = exists[k] for k of exists

  return if rec.is_paratext or rec.is_retracted

  delete rec.is_paratext
  delete rec.is_retracted

  if not exists?.oadoi and rec.DOI
    rec.oadoi = true
    oadoi = await @src.oadoi rec.DOI
    for loc in oadoi?.oa_locations ? []
      if loc.host_type is 'publisher'
        rec.publisher_license ?= loc.license
        rec.publisher_url_for_pdf ?= loc.url_for_pdf
        rec.publisher_version ?= loc.version
      if loc.host_type is 'repository'
        if loc.url and loc.url.toLowerCase().includes 'pmc'
          if not rec.PMCID
            pp = loc.url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0]
            rec.PMCID = 'PMC' + pp if pp.length and pp.replace(/[^0-9]/g, '').length is pp.length and not isNaN parseInt pp
          if loc.license and not rec.epmc_licence
            rec.epmc_licence = loc.license
        if not rec.repository_url or not rec.repository_url.includes 'pmc'
          for ok in ['license', 'url_for_pdf', 'url', 'version']
            rec['repository_' + ok] = loc[ok] if loc[ok]
    if rec.repository_url and rec.repository_url.toLowerCase().includes 'pmc'
      rec.PMCID ?= 'PMC' + rec.repository_url.toLowerCase().split('pmc').pop().split('/')[0].split('#')[0].split('?')[0]
      rec.repository_url_in_pmc = true
    if oadoi?
      rec.best_oa_location_url = oadoi.best_oa_location?.url
      rec.best_oa_location_url_for_pdf = oadoi.best_oa_location?.url_for_pdf
      rec.oa_status = oadoi.oa_status
      rec.has_repository_copy = oadoi.has_repository_copy
      rec.has_oa_locations_embargoed = if oadoi.oa_locations_embargoed? and oadoi.oa_locations_embargoed.length then true else false
      rec.title = oadoi.title
      rec.issn = oadoi.journal_issns.split(',') if not rec.issn and typeof oadoi.journal_issns is 'string'
      rec.journal ?= oadoi.journal_name
      rec.publisher ?= oadoi.publisher
      rec.published_date = oadoi.published_date if oadoi.published_date
      rec.published_year = oadoi.year if oadoi.year
      rec.oadoi_is_oa = oadoi.is_oa if oadoi.is_oa?

  rec.supplements = []
  rec.orgs = []
  for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + rec.DOI + '"', sort: 'osdid.keyword': 'asc'
    rec.orgs.push(sup.org) if sup.org not in rec.orgs
    rec.paid = true if sup.paid
    rec.email = sup.email if not rec.email and sup.email
    rec.supplements.push sup

  if rec.authorships? and rec.email and not rec.author_email_name and (not exists?.authorships? or not exists?.email)
    email = if rec.email.includes('@') then rec.email else await @decrypt rec.email
    if rec.authorships.length is 1
      rec.author_email_name = 'Dr. ' + rec.authorships[0].author?.display_name
    else
      ren = email.split('@')[0].toLowerCase().replace /[^a-z]/g, ''
      best_initial = ''
      best_name = ''
      best_score = 1000000
      for rn in rec.authorships
        if ran = rn.author?.display_name
          lvs = await @levenshtein ren, ran.toLowerCase().replace /[^a-z]/g, ''
          score = lvs.distance / ran.length
          if score < best_score
            best_score = score
            best_name = ran
          if best_score > .2 and (ren.endsWith(ran.split(' ').pop().toLowerCase()) or (ran.split(' ')[0].length > 4 and ren.includes ran.split(' ')[0].toLowerCase()))
            best_score = .1
            best_name = ran
          if not best_initial and ren.startsWith (ran.split(' ')[0].slice(0,1) + ran.split(' ').pop().slice(0,1)).toLowerCase()
            best_initial = ran
      if best_name and best_score < .7
        rec.author_email_name = 'Dr. ' + best_name.split(' ').pop()
      if not rec.author_email_name and best_initial
        rec.author_email_name = 'Dr. ' + best_initial

  rec.email = await @encrypt(rec.email) if typeof rec.email is 'string' and rec.email.includes '@'
  
  if not exists? or (exists.orgs ? []).length isnt rec.orgs.length or rec.paid isnt exists.paid or not exists.journal_oa_type
    if rec.orgs.length and (rec.DOI or (rec.issn ? []).length)
      permissions = await @permissions (await @copy rec), undefined, undefined, oadoi, cr, started - 1209600000 # (if refresh then undefined else started - 1209600000) # use cached best permissions up to two weeks old
      rec.can_archive = permissions?.best_permission?.can_archive
      rec.can_archive = true if not rec.can_archive? and ((oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj)
      rec.version = permissions?.best_permission?.version
      rec.journal_oa_type = await @permissions.journals.oa.type undefined, undefined, oadoi, cr # calculate journal oa type separately because it can be different for a journal in general than for what permissions calculates in more specificity

    if rec.DOI and (not rec.PMCID or not rec.PMID)
      if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else await @src.pubmed.doi rec.DOI) # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
        rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if pubmed?.identifier?.pmc
        rec.PMID = pubmed.identifier.pubmed if not rec.PMID and pubmed?.identifier?.pubmed
    if rec.DOI and not rec.PMCID
      if epmc = await @src.epmc.doi rec.DOI
        rec.PMCID = epmc.pmcid if epmc.pmcid
    if rec.orgs.length and rec.PMCID and rec.repository_url_in_pmc and not rec.epmc_licence
      lic = await @src.epmc.licence rec.PMCID, epmc
      rec.epmc_licence = lic?.licence
    rec.pmc_has_data_availability_statement = rec.PMCID and await @src.pubmed.availability rec.PMCID

  rec.is_oa = rec.oadoi_is_oa or rec.crossref_is_oa or rec.journal_oa_type in ['gold']
  rec._id ?= if rec.DOI then rec.DOI.toLowerCase().replace(/\//g, '_') else rec.openalex # and if no openalex it will get a default ID
  rec.supplemented = await @epoch()
  rec.updated ?= rec.supplemented
  rec.took = rec.supplemented - started
  if @params.process is rec.DOI
    await @report.articles rec
    console.log rec
  #console.log 'report articles processed', rec.DOI, rec.took
  return rec


P.report.articles.load = (timestamp, orgname, dois, year, refresh) ->
  started = await @epoch()
  year ?= @params.load ? (await @date()).split('-')[0] # load could be supplements but in that case year is not used anyway
  orgname ?= @params.org
  dois ?= @params.load
  dois = [dois] if typeof dois is 'string'
  refresh ?= @refresh

  await @report.articles('') if refresh

  batch = []
  batchsize = 2000
  bt = 0
  total = 0

  _batch = (cr, ol) =>
    bt += 1
    prc = await @report.articles.process cr, ol, timestamp ? refresh
    if prc?
      batch.push prc
      total += 1
    console.log('report load building batch', batch.length) if batch.length % 200 is 0
    if batch.length is batchsize
      await @report.articles batch
      batch = []
      console.log 'report articles load', total, bt, await @epoch() - started

  if @params.load is 'supplements'
    dois ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', (if timestamp then 'updated:<' + timestamp else undefined), scroll: '5m', include: ['DOI']
      dois.push(sup.DOI) if sup.DOI not in dois
    console.log 'report articles supplements to load', dois.length

  if Array.isArray dois
    await _batch(d) for d in dois
  else
    _crossref = (qry) =>
      qry ?= '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
      qry = '(' + qry + ') AND srcday:>' + timestamp if timestamp
      console.log 'report works load crossref by query', qry
      await _batch(cr) for await cr from @index._for 'src_crossref_works', qry, scroll: '10m', include: ['DOI', 'subject', 'title', 'subtitle', 'volume', 'issue', 'year', 'publisher', 'published', 'funder', 'license', 'is_oa', 'ISSN']

    _openalex = (qry) =>
      qry ?= 'NOT ol.ids.doi:* AND authorships.institutions.display_name:* AND publication_year:' + year
      qry = '(' + qry + ') AND updated_date:>' + timestamp if timestamp
      console.log 'report works load openalex by query', qry
      await _batch(undefined, ol) for await ol from @index._for 'src_openalex_works', qry, scroll: '10m'

    await Promise.all [_crossref(), _openalex()]

    for await org from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', (if orgname then 'name:"' + orgname + '"' else 'paid:true'), scroll: '10m'
      # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      _crossref(org.source.crossref) if org.source?.crossref
      _openalex(org.source.openalex) if org.source?.openalex

    if timestamp
      for await crt from @index._for 'report_articles', 'orgs:* AND updated:<' + timestamp, scroll: '10m'
        await _batch(crt) if updated = await @src.crossref.works 'DOI:"' + crt.DOI + '" AND srcday:>' + timestamp

  await @report.articles(batch) if batch.length
  console.log 'report articles loaded', total, await @epoch() - started
  return total
P.report.articles.load._async = true

P.report.articles.compare = () ->
  missing = processed: 0, counts: {}, article: [], cleaned: [], supplements: [], duplicates: []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'orgs:* AND DOI:*', scroll: '10m', include: ['DOI']
    missing.processed += 1
    console.log('report articles comparing', missing.processed) if missing.processed % 200 is 0
    if not exists = await @report.articles rec.DOI
      if rec.DOI in missing.article
        missing.duplicates.push rec.DOI
      else
        cd = rec.DOI.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/ /g, '').replace(/^\//, '').split('?')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '')
        if typeof cd is 'string' and cd.length and cleaned = await @report.articles cd
          missing.cleaned.push rec.DOI
        else if not sup = await @report.orgs.supplements.count 'DOI:"' + rec.DOI + '"'
          missing.supplements.push rec.DOI
        else
          missing.article.push rec.DOI
  missing.counts = article: missing.article.length, cleaned: missing.cleaned.length, supplements: missing.supplements.length, duplicates: missing.duplicates.length
  out = @S.static.folder + '/report_articles_works_compare.json'
  await fs.writeFile out, JSON.stringify missing, "", 2
  @mail to: 'mark@oa.works', subject: 'OA report articles works compared ', text: out
  return missing