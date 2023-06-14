

'''
P.report.articles = _index: true, _prefix: false
P.report.articles.process = (cr, openalex, refresh, everything, replaced) ->
  started = await @epoch()
  cr ?= @params.process
  refresh ?= @refresh
  everything ?= @params.everything # if so then runs epmc and permissions, which otherwise only run for records with orgs providing supplements
 
  if typeof openalex is 'string'
    openalex = openalex.split(if openalex.includes('doi.org') then 'doi.org/' else '/').pop()
    openalex = openalex.replace /\/$/, ''
    if openalex.startsWith '10.'
      openalex = openalex.toLowerCase()
      cr ?= openalex
    if openalex.startsWith('W') or openalex.startsWith '10.'
      if openalex.startsWith('10.') and refresh isnt true
        exists = await @report.articles _id: openalex
        exists = undefined if not exists?.updated or (refresh and exists and exists.updated < refresh)
      if openalex.startsWith('W') or not exists?.openalex
        ox = await @src.openalex.works _id: openalex
        openalex = ox if ox?.id
  openalex = undefined if typeof openalex is 'string' and not (openalex.startsWith('W') or openalex.startsWith('10.'))

  cr = openalex.ids.doi if not cr? and typeof openalex is 'object' and openalex?.ids?.doi
  cr = cr.split('doi.org/').pop() if typeof cr is 'string' and cr.includes 'doi.org/'
  cr = undefined if typeof cr is 'string' and not cr.startsWith '10.'
  cr = cr.toLowerCase() if typeof cr is 'string'
  cr = xref if not exists? and typeof cr is 'string' and xref = await @src.crossref.works _id: cr
  cr = undefined if typeof cr is 'object' and not cr.DOI

  if cr? and refresh isnt true
    exists ?= await @report.articles(if typeof cr is 'string' then cr else cr.DOI)
    exists = undefined if not exists?.updated or (refresh and exists and exists.updated < refresh)

  if cr? and not exists?.openalex
    openalex ?= await @src.openalex.works _id: if typeof cr is 'object' then cr.DOI else cr
  openalex = undefined if typeof openalex is 'string' or not openalex?.id

  if typeof cr is 'object' and cr.DOI
    rec = DOI: cr.DOI.toLowerCase(), subject: cr.subject, subtitle: cr.subtitle, volume: cr.volume, published_year: cr.year, issue: cr.issue, publisher: cr.publisher, published_date: cr.published, funder: cr.funder, issn: cr.ISSN, subtype: cr.subtype
    for ass in (cr.assertion ? [])
      assl = (ass.label ? '').toLowerCase()
      if assl.includes('accepted') and assl.split(' ').length < 3
        ad = await @dateparts ass.value
        rec.accepted_date ?= ad.date if ad?.date
      if assl.includes 'received'
        sd = await @dateparts ass.value
        rec.submitted_date ?= sd.date if sd?.date
    delete f['doi-asserted-by'] for f in rec.funder ? []
    rec.title = cr.title[0] if cr.title and cr.title.length
    rec.journal = cr['container-title'][0] if cr['container-title'] and cr['container-title'].length
    rec['reference-count'] = cr['reference-count'] if cr['reference-count']?
    for lc in cr.license ? []
      rec['crossref_license_url_' + lc['content-version']] = lc.URL if lc['content-version'] in ['am', 'vor', 'tdm', 'unspecified']
    rec.crossref_is_oa = if not cr.is_oa? then false else cr.is_oa

    brd = []
    newer = false
    _rsup = (sup, ud) =>
      sup.DOI = cr.DOI
      sup.replaced = ud
      await @report.orgs.supplements sup.osdid, ''
      sup._id = sup.osdid = sup.osdid.split('_10.') + '_' + sup.DOI.replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
      brd.push sup
    for ud in (cr['update-to'] ? [])
      if ud.DOI isnt cr.DOI and ud.type.toLowerCase() not in ['erratum', 'correction'] # some new version statements are for the same DOI, so no point changing anything
        rec.replaces = []
        rec.replaces.push DOI: ud.DOI, type: ud.type, updated: ud.updated?.timestamp
        await @report.articles(ud.DOI, '') if ude = await @report.articles ud.DOI
        _rsup(sup, ud.DOI) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + ud.DOI + '"'
    for rr in (cr.relation?['is-same-as'] ? [])
      if rr['id-type'] is 'doi' and rr.id isnt cr.DOI and newer = await @src.crossref.works rr.id
        _rsup(sup, rr.id) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + cr.DOI + '"'
    await @report.orgs.supplements(brd) if brd.length
    if newer isnt false
      return @report.articles.process newer, openalex, refresh, everything, cr.DOI
    if replaced # if this was passed in by a secondary call to process
      rec.replaces ?= []
      rec.replaces.push DOI: replaced, type: 'relation.is-same-as'

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
    rec.issn = openalex.host_venue.issn if openalex.host_venue?.issn and openalex.host_venue.issn.length
    rec.biblio = openalex.biblio if openalex.biblio
    rec['referenced_works'] = openalex['referenced_works'].length if openalex['referenced_works']
    for c in rec.concepts ? []
      delete c.wikidata
      try c.score = Math.floor(c.score * 100)
    for a in rec.authorships ? []
      delete i.type for i in a.institutions ? []

  rec ?= {}
  rec.DOI = cr.toLowerCase() if not rec.DOI and typeof cr is 'string'

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
      rec.issn = oadoi.journal_issns.split(',') if not rec.issn and typeof oadoi.journal_issns is 'string' and oadoi.journal_issns.length
      rec.journal ?= oadoi.journal_name
      rec.publisher ?= oadoi.publisher
      rec.published_date = oadoi.published_date if oadoi.published_date
      rec.published_year = oadoi.year if oadoi.year
      rec.oadoi_is_oa = oadoi.is_oa if oadoi.is_oa?

  rec.supplements = []
  rec.orgs = []
  if rec.DOI
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + rec.DOI + '"', sort: 'osdid.keyword': 'asc'
      rec.orgs.push(sup.org) if sup.org not in rec.orgs
      rec.paid = true if sup.paid
      rec.email = sup.email if not rec.email and sup.email
      rec.supplements.push sup

  if exists?
    rec.author_email_name = exists.author_email_name if exists.author_email_name and exists.email and rec.email and rec.email.toLowerCase() is exists.email.toLowerCase()
    rec[k] ?= exists[k] for k of exists

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
  
  everything = true if rec.orgs.length and (exists?.orgs ? []).length isnt rec.orgs.length # control whether to run time-expensive things on less important records

  #if (not exists? and rec.orgs.length) or (exists?.orgs ? []).length isnt rec.orgs.length or (rec.paid and rec.paid isnt exists?.paid) #or not exists.journal_oa_type
  if rec.DOI
    if not rec.PMCID or not rec.PMID
      if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else await @src.pubmed.doi rec.DOI) # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
        rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if not rec.PMCID and pubmed?.identifier?.pmc
        rec.PMID = pubmed.identifier.pubmed if not rec.PMID and pubmed?.identifier?.pubmed
        rec.pubtype = pubmed.type # this is a list

    if not rec.journal_oa_type # restrict permissions only to records with orgs supplements? for now no
      permissions = await @permissions (await @copy rec), undefined, undefined, oadoi, cr, started - 1209600000 # (if refresh then undefined else started - 1209600000) # use cached best permissions up to two weeks old
      rec.can_archive = permissions?.best_permission?.can_archive
      rec.can_archive = true if not rec.can_archive? and ((oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj)
      rec.version = permissions?.best_permission?.version
      rec.journal_oa_type = await @permissions.journals.oa.type rec.issn, undefined, oadoi, cr # calculate journal oa type separately because it can be different for a journal in general than for what permissions calculates in more specificity
      rec.journal_oa_type ?= 'unsuccessful'

    if everything
      if not rec.PMCID # only thing restricted to orgs supplements for now is remote epmc lookup and epmc licence calculation below
        if epmc = await @src.epmc.doi rec.DOI
          rec.PMCID = epmc.pmcid if epmc.pmcid
          for pt in (epmc.pubTypeList ? [])
            rec.pubtype = if Array.isArray(rec.pubtype) then rec.pubtype else if rec.pubtype then [rec.pubtype] else []
            rec.pubtype.push(pt.pubType) if pt.pubType not in rec.pubtype

  if everything
    if rec.PMCID and rec.repository_url_in_pmc and not rec.epmc_licence
      lic = await @src.epmc.licence rec.PMCID, epmc
      rec.epmc_licence = lic?.licence
    rec.pmc_has_data_availability_statement ?= rec.PMCID and await @src.pubmed.availability rec.PMCID
    if not rec.data_availability_statement and rec.PMCID #rec.pmc_has_data_availability_statement
      rec.data_availability_statement = await @src.epmc.statement rec.PMCID, epmc

  rec.is_oa = rec.oadoi_is_oa or rec.crossref_is_oa or rec.journal_oa_type in ['gold']
  rec._id ?= if rec.DOI then rec.DOI.toLowerCase().replace(/\//g, '_') else rec.openalex # and if no openalex it will get a default ID
  rec.supplemented = await @epoch()
  rec.updated ?= rec.supplemented
  rec.took = rec.supplemented - started
  if rec.DOI and @params.process is rec.DOI
    await @report.articles rec
  #console.log 'report articles processed', rec.DOI, rec.took
  return rec


P.report.articles.load = (timestamp, orgname, dois, year, refresh, supplements, everything) ->
  started = await @epoch()
  year ?= @params.load ? (await @date()).split('-')[0] # load could be supplements or everything but in that case year is not used anyway
  orgname ?= @params.org
  dois ?= @params.load
  dois = [dois] if typeof dois is 'string'
  refresh ?= @refresh
  everything ?= @params.load is 'everything'

  await @report.articles('') if refresh

  batch = []
  batchsize = 2000
  bt = 0
  total = 0
  crcount = 0
  olxcount = 0

  _batch = (cr, ol) =>
    bt += 1
    if typeof cr is 'string' and cr.startsWith('W') and not ol
      ol = cr
      cr = undefined
    prc = await @report.articles.process cr, ol, (timestamp ? refresh), everything
    if prc?
      batch.push prc
      total += 1
    console.log('report load building batch', batch.length) if batch.length % 200 is 0
    if batch.length is batchsize
      await @report.articles batch
      batch = []
      console.log 'report articles load', total, bt, (if dois then dois.length else undefined), await @epoch() - started

  if @params.load is 'supplements'
    dois ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', (if timestamp then 'updated:<' + timestamp else undefined), scroll: '5m', include: ['DOI']
      dois.push(sup.DOI) if sup.DOI not in dois
    console.log 'report articles supplements to load', dois.length
  else if everything
    dois ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_articles', 'NOT pmc_has_data_availability_statement:*', scroll: '5m', include: ['DOI', 'openalex']
      sd = sup.DOI ? sup.openalex
      dois.push(sd) if sd not in dois
    console.log 'report articles supplements to load everything for records that do not yet have everything', dois.length

  if Array.isArray dois
    await _batch(d) for d in dois
  else
    _crossref = (qry) =>
      qry ?= '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
      qry = '(' + qry + ') AND srcday:>' + timestamp if timestamp
      console.log 'report works load crossref by query', qry
      cc = []
      cc.push(cr.DOI) for await cr from @index._for 'src_crossref_works', qry, include: ['DOI'] #, scroll: '30m', include: ['DOI', 'subject', 'title', 'subtitle', 'volume', 'issue', 'year', 'publisher', 'published', 'funder', 'license', 'is_oa', 'ISSN', 'update-to', 'reference-count']
      crcount += cc.length
      console.log 'report works load crossref by query counted', cc.length
      await _batch(d) for d in cc

    _openalex = (qry) =>
      qry ?= 'authorships.institutions.display_name:* AND publication_year:' + year # NOT ids.doi:* AND 
      qry = '(' + qry + ') AND updated_date:>' + timestamp if timestamp
      console.log 'report works load openalex by query', qry
      oo = []
      oo.push(ol.id.split('/').pop()) for await ol from @index._for 'src_openalex_works', qry, include: ['id'] #, scroll: '30m'
      olxcount += oo
      console.log 'report works load openalex by query counted', oo.length
      await _batch(undefined, o) for o in oo
    
    await Promise.all [_crossref(), _openalex()]

    for await org from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', (if orgname then 'name:"' + orgname + '"' else 'paid:true'), scroll: '10m'
      # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      await _crossref(org.source.crossref) if org.source?.crossref
      await _openalex(org.source.openalex) if org.source?.openalex

    if timestamp
      for await crt from @index._for 'report_articles', 'orgs:* AND updated:<' + timestamp, scroll: '10m'
        await _batch(crt) if updated = await @src.crossref.works 'DOI:"' + crt.DOI + '" AND srcday:>' + timestamp
    

  await @report.articles(batch) if batch.length
  #@report.articles.load(undefined, undefined, undefined, undefined, undefined, undefined, true) if not dois

  took = await @epoch() - started
  text = 'Report articles loaded ' + total + '\n'
  text += 'All old articles were removed before loading began\n' if refresh
  text += dois.length + ' DOIs were provided to process\n' if dois and dois.length
  text += 'These were derived by searching for all articles that already have supplements attached\n' if @params.load is 'supplements'
  text += 'These were derived by searching for all articles that have not yet had everything fully processed\n' if everything
  text += 'These were provided by an orgs supplements refresh which took ' + Math.ceil(((await @epoch()) - supplements)/1000/60) + 'm\n' if supplements
  text += 'The load process was limited to ' + orgname + '\n' if orgname
  text += 'The load process was run for changes since ' + (await @datetime timestamp) + '\n' if timestamp
  text += 'The load process was run for year ' + year + '\n' if year and not (dois ? []).length
  text += 'Crossref queries counted ' + crcount + ' articles\n' if crcount
  text += 'Openalex queries counted ' + olxcount + ' articles\n' if olxcount
  text += 'Load processing took ' + Math.ceil(took/1000/60) + 'm\n'
  console.log 'Report articles loaded', total, took
  @mail to: ['mark@oa.works'], subject: 'OA report articles works loaded ' + total, text: text
  return total
P.report.articles.load._async = true
P.report.articles.load._auth = '@oa.works'
'''

