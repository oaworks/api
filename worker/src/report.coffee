
P.report = () -> return 'OA.Works report'

P.report.fixtypes = () ->
  checked = 0
  fixed = 0
  for await rr from @index._for (if @S.dev then 'paradigm_b_' else 'paradigm_') + 'report_works', 'NOT type.keyword:"journal-article" AND NOT type.keyword:"posted-content"', scroll: '30m', include: ['DOI', 'type']
    checked += 1
    if cr = await @src.crossref.works cr.DOI
      if cr.type isnt rr.type
        fixed += 1
        rr.type = cr.type
        await @report.works rr
    console.log 'fixing report works types', checked, fixed
  @mail
    to: ['mark@oa.works']
    subject: 'OA report works types fixed ' + fixed
    text: checked + ' checked and fixed ' + fixed
  return fixed
P.report.fixtypes._async = true
P.report.fixtypes._bg = true
P.report.fixtypes._auth = 'root'

P.report.dev2live = (reverse) ->
  if not reverse
    f = 'paradigm_b_report_works'
    t = 'paradigm_report_works'
  else
    f = 'paradigm_report_works'
    t = 'paradigm_b_report_works'
  await @index._send t, '', undefined, false
  counter = 0
  batch = []
  for await rm from @index._for f
    counter += 1
    batch.push(rm) if rm.DOI and not rm.DOI.includes(' pmcid:') and not rm.DOI.includes('\n') and not rm.DOI.includes '?ref'
    if batch.length is 30000
      console.log 'report works', (if reverse then 'live2dev' else 'dev2live'), f, t, counter
      await @index._bulk t, batch, undefined, undefined, false
      batch = []

  if batch.length
    await @index._bulk t, batch, undefined, undefined, false
    batch = []

  return counter

P.report.dev2live._async = true
P.report.dev2live._bg = true
P.report.dev2live._auth = 'root'

P.report.live2dev = () ->
  return @report.dev2live true
P.report.live2dev._async = true
P.report.live2dev._bg = true
P.report.live2dev._auth = 'root'

P.report.orgs = _sheet: '1d_RxBLU2yNzfSNomPbWQQr3CS0f7BhMqp6r069E8LR4/dev' , _format: (recs=[]) ->
  ready = []
  bs = 0
  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    nr = {}
    for h of rec
      if typeof rec[h] is 'string'
        rec[h] = rec[h].trim()
        if rec[h].toLowerCase() is 'true'
          rec[h] = true
        else if rec[h].toLowerCase() is 'false'
          rec[h] = false
        else if ((rec[h].startsWith('[') and rec[h].endsWith(']')) or (rec[h].startsWith('{') and rec[h].endsWith('}')))
          try
            rec[h] = JSON.parse rec[h]
          catch err
            console.log 'cant parse ' + h, rec[h], err
            bs += 1
        else if rec[h].includes ';'
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split ';'
      if h.includes '.'
        try @dot nr, h, rec[h]
      else
        nr[h] = rec[h]
    if Array.isArray nr.sheets
      for s in nr.sheets
        s.url = await @encrypt s.url
    else
      delete nr.sheets
    ready.push(nr) if JSON.stringify(nr) isnt '{}'
  console.log 'report orgs refresh finished'
  console.log bs + ' bad sheets strings found in completed report orgs refresh'
  return if ready.length is 1 then ready[0] else ready

P.report.orgs.supplement = (sheetname, orgname, max, changed, reload, xref, olx) ->
  sheetname ?= @params.sheet
  orgname ?= @params.org
  max ?= @params.max
  reload ?= @params.reload
  repmc = @params.repmc ? false # trigger an epmc lookup again, even if not setting reload to true
  
  if typeof changed is 'string'
    changed = await @report.works changed
    changed ?= await @src.crossref.works changed

  paramdoi = false
  if not changed? and @params.supplement and @params.supplement.startsWith '10.'
    paramdoi = @params.supplement.toLowerCase()
    changed = await @src.crossref.works paramdoi

  loaded = 0
  doid = 0
  dois = {}
  counts = {}
  orgsheets = {}

  if not changed? or paramdoi
    for await org from @index._for 'report_orgs', 'sheets.url:*'
      if not orgname or org.name is orgname
        orgsheets[org.name] ?= {}
        console.log 'supplementing for', org.name
        for s in org.sheets
          orgsheets[org.name][s.name] ?= 0
          if not sheetname or s.name is sheetname
            console.log 'supplementing from sheet', s.name
            url = await @decrypt s.url
            headers = []
            rows = await @src.google.sheets sheetid: url, sheet: 'Export', headers: false # just get rows because headers are in different places, and want to simplify them as well
            if rows
              headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
            else
              rows = []
            console.log rows.length, 'rows from sheet with headers', JSON.stringify headers
            mx = 0
            rc = 0
            for row in rows
              orgsheets[org.name][s.name] += 1
              rc += 1
              console.log 'processing row', rc, 'for', org.name, s.name
              mx += 1
              if mx is max
                console.log 'stopping supplementing for', s.name, 'due to max limit'
                break 
              rr = supplements: [{orgs: [org.name], sheets: [s.name], ror: org.ror, paid: org.paid}], orgs: [org.name], paid: if org.paid then [org.name] else []
              for hp of headers
                h = headers[hp]
                if h in ['doi', 'DOI']
                  rr[h] = row[hp]
                else if h is 'apc_cost'
                  try rr.supplements[0].apc_cost = parseInt row[hp]
                else
                  rr.supplements[0][h] = if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if h.toLowerCase() in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else row[hp]
                  rr.supplements[0][h] = rr.supplements[0][h].split(';') if typeof rr.supplements[0][h] is 'string' and rr.supplements[0][h].includes ';'
              rr.DOI ?= rr.doi
              if rr.DOI and rr.DOI.startsWith 'http'
                try rr.DOI = '10.' + rr.DOI.split('/10.')[1] # avoid dirty inputs that are full URLs
              rr.DOI = rr.DOI.toLowerCase().split('\\')[0].trim().replace(/^\//, '').split('?')[0].split(' pmcid')[0].split('\n')[0] if rr.DOI # also catch problems like 10.1021/acscentsci.0c00732?ref=pdf
              if rr.DOI and (not paramdoi or paramdoi is rr.DOI)
                doid += 1
                if dois[rr.DOI]?
                  rr[k] ?= dois[rr.DOI][k] for k of dois[rr.DOI]
                  rr.supplements.push(sp) for sp in dois[rr.DOI].supplements when (not orgname or orgname not in sp.orgs) and (not sheetname or sheetname not in sp.sheets)
                  rr.paid.push(pp) for pp in dois[rr.DOI].paid when pp not in rr.paid
                  rr.orgs.push(og) for og in dois[rr.DOI].orgs when og not in rr.orgs
                dois[rr.DOI] = rr
                counts[rr.DOI] ?= 0
                counts[rr.DOI] += 1
  else
    dois[changed.DOI] = changed

  batch = []
  for d of dois
    loaded += 1
    console.log loaded
    rr = dois[d]
    if reload isnt true and (not changed? or paramdoi) and wrr = await @report.works rr.DOI
      if wrr.hits?.hits? # catch problems caused by bad input DOIs
        if wrr.hits.hits.length is 1
          wrr = wrr.hits.hits[0]._source
        else
          wrr = undefined
      if wrr?
        rr[k] ?= wrr[k] for k of wrr when k not in ['hits', '_shards', 'took', 'timed_out', 'q', 'is_paratext', 'is_retracted'] 
        if wrr.supplements and (orgname or sheetname)
          for sp in wrr.supplements
            rr.supplements.push(sp) if (not orgname or orgname not in sp.orgs) and (not sheetname or sheetname not in sp.sheets)
        if wrr.paid and orgname
          rr.paid.push(pp) for pp in wrr.paid when typeof pp is 'string' and pp not in rr.paid 
        if wrr.orgs and orgname
          rr.orgs.push(og) for og in wrr.orgs when typeof og is 'string' and og not in rr.orgs 

    if not wrr?.title or not wrr?.authorships? or xref? or olx? #xref and olx are passed from the changes check for paid records
      cr = xref ? await @src.crossref.works rr.DOI # ? await @src.crossref.works.doi rr.DOI
      ol = olx ? await @src.openalex.works 'ids.doi:"https://doi.org/' + rr.DOI + '"', 1
      ol ?= await @src.openalex.works.doi rr.DOI
      if (cr? or ol?) and processed = await @report.works._process cr, ol
        if processed.is_paratext or processed.is_retracted
          rr = undefined
        else
          rr[k] ?= processed[k] for k of processed when k not in ['is_paratext', 'is_retracted']
    
    if rr?.authorships? and not rr.author_email_name
      an_email = rr.email
      an_email = sup.email for sup in rr.supplements when sup.email and not an_email
      if an_email
        an_email = an_email[0] if typeof an_email isnt 'string'
        if rr.authorships.length is 1
          rr.author_email_name = 'Dr. ' + rr.authorships[0].author?.display_name
        else
          ren = an_email.split('@')[0].toLowerCase().replace(/[^a-z]/g, '')
          best_initial = ''
          best_name = ''
          best_score = 1000000
          for rn in rr.authorships
            if ran = rn.author?.display_name
              lvs = await @levenshtein ren, ran.toLowerCase().replace(/[^a-z]/g, '')
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
            rr.author_email_name = 'Dr. ' + best_name.split(' ').pop()
          if not rr.author_email_name and best_initial
            rr.author_email_name = 'Dr. ' + best_initial

    if rr?.paid? and rr.paid.length and @params.pmc isnt false and (not rr.pmc_checked or reload is true or repmc is true)
      console.log('checking for pmc', rr.PMCID, rr.DOI) if paramdoi
      rr.pmc_checked = true
      if not rr.PMCID and pubmed = await @src.pubmed.doi rr.DOI # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
        rr.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if pubmed?.identifier?.pmc
      epmc = undefined
      if not rr.PMCID and epmc = await @src.epmc.doi rr.DOI
        rr.PMCID = epmc.pmcid if epmc.pmcid
      if rr.PMCID and rr.repository_url_in_pmc and not rr.epmc_licence
        lic = await @src.epmc.licence rr.PMCID, epmc
        rr.epmc_licence = lic?.licence
      rr.pmc_has_data_availability_statement = rr.PMCID and await @src.pubmed.availability rr.PMCID

    if rr?
      rr.updated = await @epoch()
      batch.push rr

    if batch.length is 10000
      await @report.works batch
      console.log 'report orgs supplemented', loaded
      batch = []

  if batch.length
    await @report.works batch
    batch = []

  if not changed?
    text = 'https://bg.' + (if @S.dev then 'beta' else 'api') + '.oa.works/report/works?q=supplements.orgs:*\n\n'
    for os of orgsheets
      text += os + '\n'
      for ss of orgsheets[os]
        text += ss + orgsheets[os][ss] + ' DOIs\n'
    text += '\n\n' + doid + ' DOIs were found in the sheets\n\n'

    @mail
      to: ['mark@oa.works', 'joe@oa.works']
      subject: 'OA report supplements loaded ' + loaded
      text: text
  
  return loaded
P.report.orgs.supplement._async = true

P.report.emails = _sheet: '1U3YXF1DLhGvP4PgqxNQuHOSR99RWuwVeMmdTAmSM45U/Export', _key: 'DOI'

P.report.works = _index: true, _key: 'DOI'

P.report.works._process = (cr, openalex) ->
  if cr?.DOI?
    rec = DOI: cr.DOI.toLowerCase(), subject: cr.subject, subtitle: cr.subtitle, volume: cr.volume, published_year: cr.year, issue: cr.issue, publisher: cr.publisher, published_date: cr.published, funder: cr.funder
    for f in rec.funder ? []
      delete f['doi-asserted-by']
    rec.title = cr.title[0] if cr.title and cr.title.length
    rec.journal = cr['container-title'][0] if cr['container-title'] and cr['container-title'].length
    for lc in cr.license ? []
      if lc['content-version'] in ['am', 'vor', 'tdm', 'unspecified']
        rec['crossref_license_url_' + lc['content-version']] = lc.URL
    rec.crossref_is_oa = if not cr.is_oa? then false else cr.is_oa
  else if openalex?
    rec = openalex: openalex.id.split('/').pop(), title: openalex.title
    rec.DOI = openalex.ids.doi.split('doi.org/').pop().toLowerCase() if openalex.ids?.doi?
  else
    return
    
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
    rec.journal ?= oadoi.journal_name
    rec.publisher ?= oadoi.publisher
    rec.published_date = oadoi.published_date if oadoi.published_date
    rec.published_year = oadoi.year if oadoi.year
    #rec.updated = oadoi.updated # removed in favour of adding our own as instructed by JM

  prc = await @copy rec
  permissions = await @permissions prc, undefined, undefined, oadoi, cr
  rec.can_archive = permissions?.best_permission?.can_archive
  rec.version = permissions?.best_permission?.version
  rec.journal_oa_type = await @permissions.journals.oa.type undefined, undefined, oadoi, cr # this does this again, separately, because Joe asked for it

  if not rec.can_archive? and ((oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj)
    rec.can_archive = true

  rec.oadoi_is_oa = oadoi?.is_oa
  rec.is_oa = rec.oadoi_is_oa or rec.crossref_is_oa or rec.journal_oa_type in ['gold'] # what about transformative or diamond? or any others?

  if rec.DOI
    hasml = await @report.emails rec.DOI
    rec.email = hasml?.Email

  openalex ?= await @src.openalex.works 'ids.doi:"https://doi.org/' + rec.DOI + '"', 1
  if openalex?
    rec[ok] = openalex[ok] for ok in ['authorships', 'concepts', 'cited_by_count', 'type', 'is_paratext', 'is_retracted']
    rec.title = openalex.title if openalex.title 
    rec.published_date = openalex.publication_date if openalex.publication_date and not oadoi?.published_date
    rec.published_year = openalex.publication_year if openalex.publication_year and not oadoi?.year
    rec.issn = openalex.host_venue?.issn
    for c in rec.concepts ? []
      delete c.wikidata
    for a in rec.authorships ? []
      for i in a.institutions ? []
        delete i.country_code
        delete i.type
    rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if not rec.PMCID and openalex.ids?.pmcid

  rec.updated = await @epoch()
  return rec

P.report.works.load = (timestamp, crossref, openalex, supplement, qry, oaqry, notify) ->
  started = await @epoch()

  timestamp ?= @params.load ? @params.timestamp
  crossref ?= @params.crossref
  openalex ?= @params.openalex
  supplement ?= false #@params.supplement
  overwrite = @params.overwrite ? true

  if @params.clear
    await @report.works ''

  batch = []

  if @params.year
    year = @params.year
    year = '(' + year.replace(/ /g, '').split(',').join(' OR ') + ')' if typeof year is 'string' and year.includes ','
  else
    year = '2022'
    #await @report.works('') if not timestamp

  total = batch.length
  if batch.length
    await @report.works batch
    batch = []
  
  qry ?= '(type.keyword:"journal-article" OR type.keyword:"posted-content") AND (funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
  qry = '(' + qry + ') AND year.keyword:' + year if year and not qry.includes ':' + year
  qry = '(' + qry + ') AND srcday:>' + timestamp if timestamp and not qry.includes ':>' + timestamp
  console.log qry
  crcount = await @src.crossref.works.count qry
  console.log crcount, 'records available for update from crossref'
  if crossref isnt false
    console.log 'Starting OA report works loading from crossref'
    for await cr from @index._for 'src_crossref_works', qry, scroll: '30m', max: @params.max, include: ['DOI', 'subject', 'title', 'subtitle', 'volume', 'issue', 'year', 'publisher', 'published', 'funder', 'license', 'is_oa']
      if overwrite is true or not await @report.works cr.DOI
        total += 1
        console.log('report works load xref', total) if not timestamp and total % 20 is 0
        prc = await @report.works._process cr
        if prc? and not prc.is_retracted and not prc.is_paratext
          delete prc.is_retracted
          delete prc.is_paratext
          dt = await @date()
          if dt.includes(year) and timestamp
            exists = await @report.works cr.DOI
            if exists?.supplements?
              prc[e] ?= exists[e] for e in ['supplements', 'orgs', 'author_email_name', 'pmc_checked', 'paid', 'PMCID', 'epmc_licence', 'pmc_has_data_availability_statement']
          batch.push prc
        if batch.length is 10000
          await @report.works batch
          console.log 'OA report works loading', total, Math.ceil ((await @epoch()) - started)/60000
          batch = []

  oaqry ?= 'authorships.institutions.display_name:* AND publication_year:' + year
  oaqry = '(' + oaqry + ') AND publication_year:' + year if year and not oaqry.includes ':' + year
  oaqry = '(' + oaqry + ') AND updated_date:>' + timestamp if timestamp and not oaqry.includes ':>' + timestamp
  console.log oaqry
  alexcount = await @src.openalex.works.count oaqry
  console.log alexcount, 'records available for update from openalex'
  if openalex isnt false
    console.log 'Starting OA report works loading from openalex'
    for await ol from @index._for 'src_openalex_works', oaqry, scroll: '30m', max: @params.max
      if not ol.ids?.doi
        #exists = await @report.works ol.ids.doi.split('doi.org/')[1].toLowerCase()
        if true #(overwrite is true or not exists?) and not exists?.authorships?
          total += 1
          console.log('report works load oalx', total) if not timestamp and total % 20 is 0
          prc = await @report.works._process undefined, ol
          if prc? and not prc.is_retracted and not prc.is_paratext
            delete prc.is_retracted
            delete prc.is_paratext
            batch.push prc
          if batch.length is 10000
            await @report.works batch
            console.log 'OA report works loading from openalex', total, Math.ceil ((await @epoch()) - started)/60000
            batch = []

  if batch.length
    await @report.works batch

  @report.orgs.supplement() if supplement isnt false # this will run async and should be run because the above may have written over records that had supplements in them

  took = Math.ceil ((await @epoch()) - started)/60000
  console.log 'OA report done loading after ' + took + ' minutes'
  if notify isnt false
    @mail
      to: ['mark@oa.works', 'joe@oa.works']
      subject: 'OA report works loaded ' + total + ' in ' + took + ' minutes' + (if timestamp then ' for ' + (await @date timestamp) else '') + ', ' + crcount + ' crosref, ' + alexcount + ' openalex'
      text: 'https://bg.' + (if @S.dev then 'beta' else 'api') + '.oa.works/report/works'
  return total

P.report.works.load._bg = true
P.report.works.load._async = true
P.report.works.load._auth = '@oa.works'

P.report.works.changes = (timestamp, orgname) ->
  timestamp ?= @params.changes ? @params.timestamp ? Date.now() - 90000000
  orgname ?= @params.org
  if @params.paid isnt false
    for await org from @index._for 'report_orgs', 'paid:true AND (source.crossref:* OR source.openalex:*)'
      xcnts = 0
      ocnts = 0
      # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      if not orgname or orgname is org.name
        await @report.works.load timestamp, (if org.source.crossref then undefined else false), (if org.source.openalex then undefined else false), undefined, (if org.source.crossref then decodeURIComponent(decodeURIComponent(org.source.crossref)) else undefined), (if org.source.openalex then decodeURIComponent(decodeURIComponent(org.source.openalex)) else undefined) #, false
        if org.source.supplements
          for await rec from @index._for 'report_works', decodeURIComponent(decodeURIComponent(org.source.supplements)) #'paid:"' + org.name + '" AND DOI:*'
            if rec.DOI and not rec.DOI.includes(' pmcid:') and not rec.DOI.includes('\n') and not rec.DOI.includes '?ref'
              supd = await @src.crossref.works 'DOI:"' + rec.DOI + '" AND srcday:>' + timestamp
              if supd?.hits?.total is 1
                xcnts += 1
                console.log 'xref', org.name, xcnts
                await @report.orgs.supplement undefined, undefined, undefined, rec, undefined, supd.hits.hits[0]._source
              oupd = await @src.openalex.works 'ids.doi:"https://doi.org/' + rec.DOI + '" AND updated_date:>' + timestamp
              if oupd?.hits?.total is 1
                ocnts += 1
                console.log 'oalx', org.name, ocnts
                await @report.orgs.supplement undefined, undefined, undefined, rec, undefined, undefined, oupd.hits.hits[0]._source
  else
    @report.works.load timestamp # start from timestamp a little more than a day ago, by default
  return true
P.report.works.changes._bg = true
P.report.works.changes._async = true
P.report.works.changes._auth = '@oa.works'
  


P.report.supplements = _index: true, _prefix: false, _key: 'DOI'
P.report.check = (ror, reload) ->
  reload ?= @params.check ? @params.reload ? @params.sheet
  
  started = await @epoch()
  ts = await @datetime(false).replace /[-T\: ]/g, '_'
  console.log 'OA check running', ts, reload

  if not reload
    await @report.supplements ''

  _from_crossref = (cr) =>
    cr.published = await @src.crossref.works.published cr
    try cr.year = cr.published.split('-')[0]
    try cr.year = parseInt cr.year
    try
      crf = DOI: cr.DOI.toLowerCase(), title: cr.title?[0], journal: cr['container-title']?[0], ISSN: cr.ISSN, publisher: cr.publisher, crossref_published: cr.published, crossref_year: cr.year, citations: cr['reference-count'], crossref_is_oa: cr.is_oa, crossref_subject: cr.subject
      try crf.title = crf.title.replace(/\n/g, '').replace(/\s\s+/g, ' ')
      crf.funder_grant_ids = []
      crf.funder_name = []
      for f in cr.funder ? []
        if f.DOI is '10.13039/100000865' or (f.name and f.name.toLowerCase().includes 'gates')
          f.name = 'Bill and Melinda Gates Foundation' if f.name.toLowerCase() is 'bank of canada'
          crf.funder_name.push(f.name) if f.name not in crf.funder_name
          for fid in f.award ? []
            for fidc in fid.split ','
              fidc = fidc.trim()
              crf.funder_grant_ids.push(fidc) if fidc not in crf.funder_grant_ids
      crf.author_names = []
      crf.author_affiliation = []
      for a in cr.author ? []
        an = a.name ? (if a.given then a.given + ' ' else '') + (a.family ? '')
        crf.author_names.push(an) if an
        for aff in a.affiliation ? []
          if aff.name and aff.name.toLowerCase().includes('gates') and aff.name not in crf.author_affiliation
            crf.author_affiliation.push aff.name
      try
        for lc in cr.license
          if lc['content-version'] in ['am', 'vor', 'tdm', 'unspecified']
            crf['crossref_license_url_' + lc['content-version']] ?= []
            crf['crossref_license_url_' + lc['content-version']].push lc.URL
      crf.crossref = cr
      delete crf.crossref[x] for x in ['assertion', 'reference', 'relation']
      return crf
    catch
      console.log 'from crossref parse error', JSON.stringify cr
      return

  recs = {}

  if not reload
    out = '/home/cloo/static/report/OAreport_' + ts  + '.csv'

    q = 'funder.award:OPP* OR funder.award:INV*' # query and matchers should be read from a config somewhere depending on ror
    q = 'type:"journal-article" AND (' + q + ')' if not q.includes 'journal-article'
    matchers = [
      /Melinda\sGates\sFoundation/g, # about 100
      /BMGF/g,
      /Gates\sCambridge\sTrust/g, # about 20
      #/investment\s?id\s?\d{5}/gi, # didn't match anything
      /IID\s?\d{5}/gi,
      /OPPG[HD]\s?\d{4}/g, # about 20
      /OPP\s?1\s?\d{6}/g, # matches the most at about ~1100
      /OPP\s?[45]\s?\d{4}/g, # about 30
      /INV\‐\d{6}/g # 1
    ]
  
    for await rec from @index._for 'src_crossref_works', q
      rec.DOI = rec.DOI.toLowerCase()
      ex = await @extract content: JSON.stringify(rec), matchers: matchers
      if ex.matched
        recs[rec.DOI] = await _from_crossref rec
        recs[rec.DOI].matches = []
        for mt in ex.matches
          recs[rec.DOI].matches.push({matcher: mt.matched, matched: mt.result.join(',')}) if mt.matched or mt.result
  
    # NOTE funders in crossref can be assigned a "DOI" as an ID, so get the crossref funders data too and use that to search for them as well. 
    # There ARE examples of funders in works listed with or without DOI, or listed with DOI and no funder.name. There are even some with funder.DOI
    # and a WRONG funder.name, but evidence of being correct such as a Gates one having Gates DOI but wrong name but a Gates-formatted grant ID e.g 10.1002/uog.18811
    fq = '"10.13039/100000865" OR "gates foundation" OR "gates cambridge trust"'
    fields = ['funder.DOI', 'funder.name', 'author.affiliation.name']
    # the RORs for gates and gates cambridge trust are 0456r8d26 and 033sn5p83 but neither appear anywhere in crossref
    for await rec from @index._for 'src_crossref_works', fq, {fields: fields}
      if rec.type is 'journal-article'
        matches = []
        js = JSON.stringify rec
        matches.push({field: 'funder.DOI', matched: '10.13039/100000865'}) if js.includes '10.13039/100000865'
        matches.push({field: 'funder.name', matched: 'gates foundation'}) if js.includes 'gates foundation'
        matches.push({field: 'funder.name', matched: 'gates cambridge trust'}) if js.includes 'gates cambridge trust'
        rec.DOI = rec.DOI.toLowerCase()
        if recs[rec.DOI]
          recs[rec.DOI].matches.push(mf) for mf in matches
          recs[rec.DOI].duplicate ?= 0
          recs[rec.DOI].duplicate += 1
        else
          recs[rec.DOI] = await _from_crossref rec
          recs[rec.DOI].matches = matches

  sheets = # https://docs.google.com/spreadsheets/d/.../edit
    finance: '1nhykkqxYQ4DNPAj-WnXHcYnSd4dmt_Hf0xEVDZxaPLY'
    oasupport: '180562eXtmMANfIlioclUrQDaUSWkTOz7igOymfnv2pg'
    staff: '1EZI0iNAXnJ-qbIJFGmtplHWP03NVT7hhf0ICazI0YXw'
    grants: '1lDNHAwH-8x89fgLK-JLs9bBv2cdHsJRnb1Pj86QYWZI'
    names: '1ZowZub-nwOHJrzP7IbhbdoydOAmBRxLysejw38Xt32Y'
    emails: '1U3YXF1DLhGvP4PgqxNQuHOSR99RWuwVeMmdTAmSM45U'
    lens: '1XulUi2Bk3QNsJLekx0PpNb6REhrwQi6Q9M1x_KIUH_0'
    chronos: '1SxIFu4SoROqinOXAZMepOE0d1oxAZgC8LR_nTRi4vpU'
    oacheck: '1hRZGE-LfHdloHOEVVbt_ULjvwU76gECfa8MrthF9EV8'
    asap: '14Cs80bpyKym6R1kKqIrI1R5MMELms7ArPQzF67YOOgM'
    gates_funded_pmc: '1tE6it4EcW83-ZUCotdFMnj6LsyKfQCPdkBcrr36PkVM'
    oaworks_das: '1GoZ2s0x6VEqsiTnL4BOhVFEz1wKjGn7n-_dDVZWbvMI'

  if reload
    if sr = sheets[reload]
      sheets = {}
      sheets[reload] = sr
    else
      for sr of sheets
        if sheets[sr] is reload
          sheets = {}
          sheets[sr] = reload
          break
  for s of sheets
    rows = await @src.google.sheets sheetid: sheets[s], sheet: 'Export', headers: false # just get rows because headers are in different places, and want to simplify them as well
    #if s is 'finance'
    #  rows.shift()
    #  rows.shift() # get rid of junk rows at top
    headers = []
    if rows? # catch google lookup fails
      headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift() # get headers
    else
      rows = []
    for row in rows
      rec = {}
      for h of headers
        rec[headers[h].toLowerCase()] = if not row[h] then undefined else if row[h].trim().toLowerCase() in ['true', 'yes'] then true else if row[h].trim().toLowerCase() in ['false', 'no'] then false else if headers[h].toLowerCase() in ['grant_id', 'ror'] then row[h].replace(/\//g, ',').replace(/ /g, '').split(',') else row[h]
      if rec.doi and typeof rec.doi is 'string'
        rd = rec.doi.split(',')[0].toLowerCase().replace(/\.$/, '').replace(/\s/, '').split(' ')[0].split('?')[0].trim() # some appeared to be lists of DOIs which is no use e.g. 10.1128/msphere.01330-20, 10.1128/msphere.00490-21
        if rd.startsWith('10.') and rd.includes('/') and rd.length > 6
          if reload
            recs[rd] = await @report.supplements rd
            if not recs[rd]?
              recs[rd] ?= await @src.crossref.works rd
              recs[rd] ?= await @src.crossref.works.doi rd
              if recs[rd]?
                recs[rd] = await _from_crossref recs[rd]
              else
                recs[rd] = {}
            recs[rd][k] = rec[k] for k of rec
          else if recs[rd]?
            recs[rd].duplicate ?= 0
            recs[rd].duplicate += 1
          else if cr = await @src.crossref.works rd
            recs[rd] = await _from_crossref cr
          else if cr = await @src.crossref.works.doi rd
            recs[rd] = await _from_crossref cr
          else
            recs[rd] = DOI: rd, in_crossref: false
            #recs[rd].doi_resolves = false if not await @fetch 'https://doi.org/' + rd
          try
            recs[rd].sheets ?= []
            recs[rd].sheets.push(s) if s not in recs[rd].sheets
            recs[rd].ror ?= []
            for rr in rec.ror ? ['0456r8d26']
              recs[rd].ror.push(rr) if rr not in recs[rd].ror
            for r of rec
              if r is 'apc_cost'
                try
                  ra = parseInt rec[r]
                catch
                  ra = 0
                recs[rd][r] ?= 0
                recs[rd][r] += ra
              else if recs[rd][r]?
                if recs[rd][r]
                  recs[rd][r] = [recs[rd][r]] if not Array.isArray recs[rd][r]
                else
                  recs[rd][r] = [] # catch blanks
                recs[rd][r].push(rec[r]) if rec[r]? and (typeof rec[r] isnt 'string' or rec[r].trim().length) and rec[r] not in recs[rd][r]
              else if rec[r]? and rec[r] isnt ''
                recs[rd][r] = rec[r]
          catch # just skip ones that error out, such as bad DOIs
            console.log 'sheet fields merge error', rd
        else
          console.log 'bad doi', rd

  dois = await @keys(recs).length
  console.log dois

  if not reload
    alternates = # {}
      title: 'Paper title'
      journal: 'Journal Title'
      publisher: 'Publisher name'
      published: 'Published date'
      year: 'Published year'
    keys = if @params.keys then @params.keys.split(',') else [
      "DOI", "PMCID", "in_oadoi", "in_crossref", "doi_resolves", "compliant", "can_archive", "journal_oa_type", "crossref_is_oa", "oadoi_is_oa", "is_oa", 
      "oadoi_oa_status", "best_oa_location_url", "best_oa_location_url_for_pdf", "has_repository_copy", "repository_license", 
      "repository_url_for_pdf", "repository_url", "repository_url_in_pmc", "repository_version", "publisher_license", "publisher_url_for_pdf", "publisher_version", 
      "has_oa_locations_embargoed", "epmc_licence", "epmc_licence_source", "pmc_has_data_availability_statement",
      "title", "journal", "ISSN", "publisher", "published", "crossref_published", "oadoi_published", "year", "crossref_year", "oadoi_year", "author_affiliation", "funder_name", "funder_grant_ids", 
      "crossref_license_url_am", "crossref_license_url_vor", "crossref_license_url_tdm", "crossref_license_url_unspecified", "crossref_subject",
      # keys examples from OAreport Gates live: https://docs.google.com/spreadsheets/d/1Ufh_xs3NQjzbPRgwlFnHxK5nY2cjn4SsnCqvVnY4Nk8/edit#gid=1145124691
      "grant_id", "invoice_date", "invoice_number",
      # and others suggested by Joe, to be sourced from sheets inputs if not already known:
      "mturk_has_data_availability_statement", "mturk_data_availability_statement",
      "tdm_is_oa", "mturk_is_oa", "staff_is_oa",
      "apc_cost", "oawork_finance_internal_id", "type", "to", "status", "sent", "last_contact", "last_heard_from",
      "completed", "follow_up_due", "follow_ups_sent", "clicked", "author_name", "email",
      "author_email_name", "citations", "sheets", "matches_targets", "matches_found"]
    for key in keys
      await fs.appendFile out, (if key isnt 'DOI' then ',"' else '"') + (alternates[key] ? key) + '"'

  batch = []
  counter = 0
  max = @params.max ? 0
  for d of recs
    break if max and counter > max
    counter += 1
    res = recs[d]
    if not res? # check cos there was one from chronos that ended up with no record e.g. 10.1016/j.vaccine.2017.05.087pmcid:
      console.log d
    else
      if oadoi = await @src.oadoi res.DOI
        res.oadoi = oadoi
        res.journal_oa_type = await @permissions.journals.oa.type undefined, undefined, oadoi, res.crossref

        for loc in oadoi.oa_locations ? []
          if loc.host_type is 'publisher'
            res.publisher_license ?= loc.license
            res.publisher_url_for_pdf ?= loc.url_for_pdf
            res.publisher_version ?= loc.version
          if loc.host_type is 'repository'
            if loc.url and loc.url.toLowerCase().includes 'pmc'
              if not res.PMCID and not res.pmcid
                try
                  pp = loc.url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0]
                  if pp.length and pp.replace(/[^0-9]/g, '').length is pp.length and not isNaN parseInt pp
                    res.PMCID = 'PMC' + pp
              if loc.license and not res.epmc_licence
                res.epmc_licence = loc.license
                res.epmc_licence_source = 'oadoi EPMC repository oa_location'
            if not res.repository_url or not res.repository_url.includes 'pmc'
              for ok in ['license', 'url_for_pdf', 'url', 'version']
                res['repository_' + ok] = loc[ok] if loc[ok]
        res.repository_url_in_pmc = true if res.repository_url and res.repository_url.toLowerCase().includes 'pmc'
        res.best_oa_location_url = oadoi.best_oa_location?.url
        res.best_oa_location_url_for_pdf = oadoi.best_oa_location?.url_for_pdf
        res.oadoi_is_oa = oadoi.is_oa
        res.is_oa = res.oadoi_is_oa or res.crossref_is_oa
        res.oadoi_oa_status = oadoi.oa_status
        res.has_repository_copy = oadoi.has_repository_copy
        res.has_oa_locations_embargoed = if oadoi.oa_locations_embargoed? and oadoi.oa_locations_embargoed.length then true else false
  
        res.title ?= oadoi.title
        res.journal ?= oadoi.journal_name
        res.ISSN ?= oadoi.journal_issns.split(',') if oadoi.journal_issns
        res.publisher ?= oadoi.publisher
        res.oadoi_published = oadoi.published_date
        res.oadoi_year = oadoi.year
  
      else
        res.in_oadoi = false

      res.year ?= res.oadoi_year ? res.crossref_year
      res.published ?= res.oadoi_published ? res.crossref_published

      if (oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj
        res.can_archive = true
      else
        rcc = @copy (res.crossref ? {})
        rcc.doi = rcc.DOI
        res.permissions = await @permissions rcc, undefined, undefined, oadoi, (if JSON.stringify(rcc) is '{}' then undefined else rcc)
        res.can_archive = res.permissions?.best_permission?.can_archive

      res.compliant = await @report.compliant res
      
      epmc = undefined
      pubmed = undefined
      if not res.PMCID
        if res.pmcid and (not Array.isArray(res.pmcid) or res.pmcid.length) # may be present from sheets?
          res.PMCID = 'PMC' + res.pmcid.toString().toLowerCase().replace('pmc', '')
          res.PMCID = res.PMCID[0] if Array.isArray res.PMCID
        else
          pubmed = await @src.pubmed.doi res.DOI # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
          if pubmed?.identifier?.pmc
            res.PMCID = pubmed.identifier.pmc
            res.PMCID = 'PMC' + res.PMCID.toLowerCase().replace('pmc', '')
          if (not res.PMCID or res.repository_url_in_pmc) and epmc = await @src.epmc.doi res.DOI
            res.PMCID = epmc.pmcid
      if res.PMCID and res.repository_url_in_pmc and not res.epmc_licence
        lic = await @src.epmc.licence res.PMCID, epmc
        res.epmc_licence = lic?.licence
        res.epmc_licence_source = lic?.source
      res.pmc_has_data_availability_statement = res.PMCID and await @src.pubmed.availability res.PMCID
  
      if res.author_names and res.email
        if res.author_names.length is 1
          res.author_email_name = 'Dr. ' + res.author_names[0].split(' ').pop()
        else
          ren = (if typeof res.email is 'string' then res.email else res.email[0]).split('@')[0].toLowerCase().replace(/[^a-z]/g, '')
          best_initial = ''
          best_name = ''
          best_score = 1000000
          for ran in res.author_names
            lvs = await @levenshtein ren, ran.toLowerCase().replace(/[^a-z]/g, '')
            score = lvs.distance / ran.length
            if score < best_score
              best_score = score
              best_name = ran
            if best_score > .2 and (ren.endsWith(ran.split(' ').pop().toLowerCase()) or (ran.split(' ')[0].length > 4 and ren.includes ran.split(' ')[0].toLowerCase()))
              best_score = .1
              best_name = ran
            if not best_initial and ren.startsWith (ran.split(' ')[0].slice(0,1) + ran.split(' ').pop().slice(0,1)).toLowerCase()
              best_initial = ran
          if best_score < .7
            res.author_email_name = 'Dr. ' + best_name.split(' ').pop()
          if not res.author_email_name and best_initial
            res.author_email_name = 'Dr. ' + best_initial

      batch.push res
      if not reload
        await fs.appendFile out, '\n'
        for k in keys
          val = if not res[k]? then '' else if Array.isArray(res[k]) then res[k].join(',') else if typeof res[k] is 'object' then JSON.stringify(res[k]) else res[k]
          if k is 'matches_targets'
            for m in res.matches ? []
              val += (if val then ',' else '') + (m.field ? m.matcher) if m.field or m.matcher 
          else if k is 'matches_found'
            val += (if val then ',' else '') + m.matched for m in res.matches ? []
          await fs.appendFile out, (if k isnt 'DOI' then ',"' else '"') + val.toString().replace(/"/g, '').replace(/\n/g, '').replace(/\s\s+/g, ' ') + '"'
  
      console.log('Gates OA checking', counter, dois) if counter % 100 is 0
      if batch.length is 5000
        await @report.supplements batch
        batch = []
  
  if batch.length
    await @report.supplements batch
    batch = []

  took = Math.ceil ((await @epoch()) - started)/60000
  console.log 'OA check done after ' + took + ' minutes', reload
  if not reload
    @mail
      to: ['joe@oa.works', 'sarah@oa.works']
      subject: 'Gates OA check done ' + counter + ' in ' + took + ' minutes'
      text: 'https://static.oa.works/report/' + (out ? '').split('/report/').pop()
  return counter

P.report.check._bg = true
P.report.check._async = true
P.report.check._notify = false

P.report.compliant = (rec, ror) ->
  # compare with https://docs.google.com/spreadsheets/d/1oanKC96Jbel7S8Hhy0muMHzRvOIUzer1dZu7FlXhqaE/edit#gid=1000508628
  # and https://docs.google.com/spreadsheets/d/1-7bVmmpVfaa8biZO2GdVsjOJTPGEpjL4h9oAXjJonVw/edit#gid=1048310661
  # source for TJs from JCT sheet is https://docs.google.com/spreadsheets/d/e/2PACX-1vT2SPOjVU4CKhP7FHOgaf0aRsjSOt-ApwLOy44swojTDFsWlZAIZViC0gdbmxJaEWxdJSnUmNoAnoo9/pub?gid=0&single=true&output=csv
  # there are 2281. But it's not clear how we used that data for anything other than display in the sheet
  robl = (rec.oadoi?.best_oa_location?.license ? '').toLowerCase().replace(/-/g, '')
  if rec.publisher in ['Cold Spring Harbor Laboratory', 'Research Square'] or rec.journal in ['Data in Brief'] or rec.DOI.startsWith('10.2139/ssrn') or rec.DOI.startsWith('10.21203/rs') or rec.DOI.startsWith('10.31234/osf.io/')
    return 'n/a' # not peer reviewed, so compliant is not applicable
  else if rec.journal_oa_type and rec.journal_oa_type not in ['closed', 'green'] and (robl.includes('ccby') or robl.includes('cc0') or robl.includes('pd') or (robl.includes('public') and robl.includes('domain')))
    if not rec.repository_url_in_pmc # what repos count as approved?
      return 'expected'
    else
      return 'yes'
  else if not rec.journal_oa_type? or not robl or not rec.oadoi?.best_oa_location?.url
    return 'unknown'
  else
    return 'no'

'''
P.report.compliance = (ror) ->
  ror ?= @params.report ? @params.compliance ? @params.ror
  papers = await @report.supplements.count()
  compliant = await @report.supplements.count 'compliant:yes'
  pc = Math.ceil((compliant/papers) * 1000)/10
  return if pc > 100 then 100 else pc

P.report.rating = (ror) ->
  ror ?= @params.report ? @params.rating ? @params.ror
  if ror
    ror = await @src.ror(ror) if typeof ror isnt 'object'
    filter = 'type:"journal-article" AND ("' + ror.name + '" OR "' + ror._id + '")'
    papers = await @src.crossref.works.count filter
    opens = await @src.crossref.works.count filter + ' AND is_oa:true'
  else
    papers = await @report.supplements.count()
    opens = await @report.supplements.count 'is_oa:true'
  pc = Math.ceil((opens/papers) * 1000)/10
  return if pc > 100 then 100 else pc

P.report.citations = (filter) ->
  counts = papers: 0, citations: 0, oa: {papers: 0, citations: 0}, closed: {papers: 0, citations: 0}
  filter = filter._id if typeof filter is 'object'
  ror = @params.report ? @params.citations
  ror = filter if typeof filter is 'string' and filter.length < 10 and not filter.includes ' '
  if ror
    filter = 'type:"journal-article"' + if ror then ' AND ("' + ror.name + '" OR "' + ror._id + '")' else ''

  if ror is '0456r8d26'
    for await rec from @index._for 'svc_oaworks_report_supplements', 'citations:*', {include: ['citations', 'is_oa']}
      counts.papers += 1
      counts.citations += rec.citations
      counts[if rec.is_oa then 'oa' else 'closed'].papers += 1
      counts[if rec.is_oa then 'oa' else 'closed'].citations += rec.citations
  else if filter
    for await rec from @index._for 'src_crossref_works', filter + ' AND reference-count:*', {include: ['reference-count', 'is_oa']}
      counts.papers += 1
      counts.citations += rec['reference-count']
      counts[if rec.is_oa then 'oa' else 'closed'].papers += 1
      counts[if rec.is_oa then 'oa' else 'closed'].citations += rec['reference-count']

  counts.oa.average = Math.ceil counts.oa.citations / counts.oa.papers
  counts.closed.average = Math.ceil counts.closed.citations / counts.closed.papers
  if counts.oa.average > counts.closed.average
    counts.oa_extra_percent = Math.ceil ((counts.oa.average - counts.closed.average) / counts.closed.average) * 100 
  return counts

P.report.estimate = () ->
  orgs = 0
  dups = 0
  articles = 0
  articledups = 0
  zeros = 0
  seen = []
  dois = []
  qrys = []
  for await rec from @index._for 'src_ror', 'types:(nonprofit OR education OR government)', include: ['acronyms', 'name', 'aliases', 'id', 'external_ids']
    skip = false
    rec.name = rec.name.trim().replace /"/g, ''
    qry = '"' + rec.id.split('/').pop() + '" OR funder.name.keyword:"' + rec.name + '" OR author.affiliation.name.keyword:"' + rec.name + '"'
    if rec.name.length > 4
      if rec.name in seen
        skip = true
      else
        seen.push rec.name
    for k in ['acronyms', 'aliases']
      for c in (rec[k] ? [])
        c = c.trim().replace /"/g, ''
        if c.length > 4
          qry += ' OR funder.name.keyword:"' + c + '" OR author.affiliation.name.keyword:"' + c + '"'
          if c in seen
            skip = true
          else
            seen.push c
    if rec.external_ids?.GRID?.preferred? or rec.external_ids?.GRID?.all?
      grid = rec.external_ids.GRID.preferred ? (if Array.isArray(rec.external_ids.GRID.all) then rec.external_ids.GRID.all[0] else rec.external_ids.GRID.all.split(',')[0])
      if grid.length > 5
        qry += ' OR "' + grid + '"'
        if grid in seen
          skip = true
        else
          seen.push grid
    if not skip and qry.length > 4
      qry = '(' + qry + ') AND (type.keyword:"journal-article" OR type.keyword:"posted-content") AND (year.keyword:"2022")'
      qrys.push qry
    else
      dups += 1

  ql = qrys.length
  console.log 'running ' + ql + ' queries'
  counter = 0
  while q = qrys.pop()
    counter += 1
    console.log counter + ' of ' + ql
    orgs += 1
    #oars = await @index.count 'src_crossref_works', qry
    oars = 0
    for await cr from @index._for 'src_crossref_works', q, include: ['DOI']
      dl = cr.DOI.toLowerCase()
      if dl not in dois
        #dois.push dl
        oars += 1
      else
        articledups += 1
    zeros += 1 if oars is 0
    articles += oars
    console.log q, oars, orgs, dups, articles, articledups, zeros

  await @mail to: 'mark@oa.works', text: 'orgs: ' + orgs + ', duplicates: ' + dups + ', articles: ' + articles + ', articledups: ' + articledups + ', zeros: ' + zeros
  return true
P.report.estimate._async = true
'''

