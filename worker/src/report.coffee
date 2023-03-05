
try S.report = JSON.parse SECRETS_REPORT
S.report ?= {}

P.report = () -> return 'OA.Works report'

P.report.fixemails = () ->
  fixed = 0
  for await tr from @index._for (if @S.dev then 'paradigm_b_' else 'paradigm_') + 'report_works', 'email:* OR supplements.email:*', scroll: '30m'
    changed = false
    if typeof tr.email is 'string' and tr.email.includes '@'
      tr.email = await @encrypt tr.email
      changed = true
    for sp of tr.supplements
      if tr.supplements[sp].email?
        tr.supplements[sp].email = tr.supplements[sp].email[0] if Array.isArray tr.supplements[sp].email
        if typeof tr.supplements[sp].email is 'string' and tr.supplements[sp].email.includes '@'
          tr.supplements[sp].email = await @encrypt tr.supplements[sp].email
          changed = true
    if changed
      await @report.works tr
      fixed += 1
  return fixed
P.report.fixemails._auth = '@oa.works'

P.report.fixtypes = () ->
  checked = 0
  fixed = 0
  titled = 0
  for await tr from @index._for (if @S.dev then 'paradigm_b_' else 'paradigm_') + 'report_works', 'NOT title:*', scroll: '30m'
    if tr.DOI.startsWith '10.'
      titled += 1
      cr = await @src.crossref.works tr.DOI
      ol = await @src.openalex.works 'ids.doi.keyword:"https://doi.org/' + tr.DOI + '"', 1
      fr = await @report.works._process cr, ol
      await @report.works fr
    console.log 'fixing report works types titles', titled
  for await rr from @index._for (if @S.dev then 'paradigm_b_' else 'paradigm_') + 'report_works', '(NOT type.keyword:"journal-article" AND NOT type.keyword:"posted-content")', scroll: '30m'
    checked += 1
    if rr.DOI.startsWith '10.'
      cr = await @src.crossref.works rr.DOI
      if not cr?
        ol = await @src.openalex.works 'ids.doi.keyword:"https://doi.org/' + rr.DOI + '"', 1
      if (cr? or ol?) and (cr?.type isnt rr.type or ol?.type isnt rr.type)
        fixed += 1
        rr.type = cr?.type ? ol.type
        await @report.works rr
    console.log 'fixing report works types', checked, fixed
  @mail
    to: ['mark@oa.works']
    subject: 'OA report works types fixed ' + fixed
    text: checked + ' checked and fixed ' + fixed + ' and reprocessed ' + titled
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

P.report.oapolicy = _sheet: S.report.oapolicy_sheet, _format: (recs=[]) ->
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
      if rec[h]? and rec[h] isnt ''
        if h.includes '.'
          try @dot nr, h, rec[h]
        else
          nr[h] = rec[h]
    if JSON.stringify(nr) isnt '{}'
      #nr._id = nr.uid
      ready.push nr
  return if ready.length is 1 then ready[0] else ready

P.report.orgs = _sheet: S.report.orgs_sheet, _format: (recs=[]) ->
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
  return if ready.length is 1 then ready[0] else ready

P.report.orgs.supplement = (sheetname, orgname, max, changed, reload, reprocess, xref, olx) ->
  sheetname ?= @params.sheet
  orgname ?= @params.org
  max ?= @params.max
  reload ?= @params.reload
  reprocess ?= @params.reprocess
  repmc = @params.repmc ? false # trigger an epmc lookup again, even if not setting reload to true
  
  if typeof changed is 'string'
    changed = await @report.works changed
    changed ?= await @src.crossref.works changed

  paramdoi = false
  if not changed? and @params.supplement and @params.supplement.startsWith '10.'
    paramdoi = @params.supplement.toLowerCase()
    changed = await @src.crossref.works paramdoi

  '''_sortsupps = (sups) ->
    try # sort supplements by sheet name, which are expected to be unique
      bysn = {}
      bysnks = []
      for s in sups
        s.sheets.sort()
        bysn[s.sheets[0]] = s
        bysnks.push s.sheets[0]
      res = []
      res.push(bysn[sk]) for sk in bysnks.sort()
      return res
    catch
      return sups'''

  tried = []
  failed = []
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
            tried.push org.name + ' ' + s.name + ' ' + url
            headers = []
            rows = []
            tries = 0
            await @sleep 2000 # https://github.com/oaworks/Gates/issues/375
            try
              rows = await @src.google.sheets sheetid: url, sheet: 'Export', headers: false # just get rows because headers are in different places, and want to simplify them as well
            catch
              failed.push org.name + ' ' + s.name + ' ' + url
            while (not Array.isArray(rows) or not rows.length) and tries < 3 # https://github.com/oaworks/Gates/issues/375
              await @sleep 5000
              tries += 1
              try rows = await @src.google.sheets sheetid: url, sheet: 'Export', headers: false
            if Array.isArray(rows) and rows.length
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
                else if h.includes '.'
                  await @dot rr.supplements[0], h, if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if h.toLowerCase() in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else if typeof row[hp] is 'string' and row[hp].includes(';') then row[hp].split(';') else row[hp]
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
                #rr.supplements = await _sortsupps rr.supplements
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
          #addedsup = false
          for sp in wrr.supplements
          #  if (not orgname or orgname not in sp.orgs) and (not sheetname or sheetname not in sp.sheets)
          #    addedsup = true
          #    rr.supplements.push sp
          #if addedsup
          #  rr.supplements = await _sortsupps rr.supplements
            rr.supplements.push(sp) if (not orgname or orgname not in sp.orgs) and (not sheetname or sheetname not in sp.sheets)
        if wrr.paid and (orgname or sheetname)
          rr.paid.push(pp) for pp in wrr.paid when typeof pp is 'string' and pp not in rr.paid 
        if wrr.orgs and (orgname or sheetname)
          rr.orgs.push(og) for og in wrr.orgs when typeof og is 'string' and og not in rr.orgs 

    if not wrr?.title or not wrr?.authorships? or xref? or olx? or reprocess is true #xref and olx are passed from the changes check for paid records
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
        rr.email ?= an_email
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
      for sp of rr.supplements
        if rr.supplements[sp].email?
          rr.supplements[sp].email = rr.supplements[sp].email[0] if Array.isArray rr.supplements[sp].email
          if typeof rr.supplements[sp].email is 'string' and rr.supplements[sp].email.includes '@'
            rr.supplements[sp].email = await @encrypt rr.supplements[sp].email
          rr.email ?= rr.supplements[sp].email
      if typeof rr.email is 'string' and rr.email.includes '@'
        rr.email = await @encrypt rr.email
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
    text += 'Sheets tried:\n\n'
    text += st + '\n' for st in tried
    text += 'None\n' if not tried.length
    text += '\n\nSheets failed:\n\n'
    text += sf + '\n' for sf in failed
    text += 'None\n' if not failed.length
    text += '\n\nSheet counts:\n\n'
    for os of orgsheets
      text += os + '\n'
      for ss of orgsheets[os]
        text += ss + ' ' + orgsheets[os][ss] + ' DOIs\n'
    text += '\n\n' + doid + ' DOIs were found in the sheets\n\n'

    @mail
      to: ['mark@oa.works','joe@oa.works']
      subject: 'OA report supplements loaded ' + loaded
      text: text
  
  return loaded
P.report.orgs.supplement._async = true

P.report.orgs.orgkeys = _index: true, _auth: '@oa.works'
P.report.orgs.key = (org) ->
  org ?= @params.org
  return undefined if not org?
  org = org.toLowerCase()
  rec = await @report.orgs.orgkeys 'org.keyword:"' + org + '"', 1
  if not rec? or @refresh
    if rec?
      rec.lastRefreshedAt = await @epoch()
      try rec.lastRefreshedBy = @user.email
    else
      rec = org: org, createdAt: await @epoch()
      try rec.createdBy = @user.email
    key = await @uid()
    rec.key = await @encrypt key
    await @report.orgs.orgkeys rec
    return key
  else
    rec.lastRetrievedAt = await @epoch()
    try rec.lastRetrievedBy = @user.email
    await @report.orgs.orgkeys rec
    return @decrypt rec.key
P.report.orgs.key._auth = '@oa.works'

P.report.emails = _sheet: S.report.emails_sheet, _key: 'doi', _auth: '@oa.works'

P.report.email = (doi) ->
  return undefined if not doi and not @params.orgkey
  doi ?= @params.email ? @params.doi
  return undefined if not doi?
  rec = await @report.works doi
  if rec?.email
    return rec.email if rec.email.includes '@'
    rpke = await @encrypt @params.orgkey
    ok = await @report.orgs.orgkeys 'key.keyword:"' + rpke + '"', 1
    if typeof ok?.org is 'string' and ok.org.length
      rol = []
      rol.push(rou.toLowerCase()) for rou in rec.orgs
      if ok.org in rol
        return @decrypt rec.email
  return

P.report.works = _index: true, _key: 'DOI'

P.report.works._process = (cr, openalex) ->
  if cr?.DOI?
    rec = DOI: cr.DOI.toLowerCase(), subject: cr.subject, subtitle: cr.subtitle, volume: cr.volume, published_year: cr.year, issue: cr.issue, publisher: cr.publisher, published_date: cr.published, funder: cr.funder
    for ass in (cr.assertion ? [])
      assl = (ass.label ? '').toLowerCase()
      rec.accepted_date ?= cr.assertion.value if assl.includes('accepted') and not assl.split(' ').length > 2
      rec.submitted_date ?= cr.assertion.value if assl.includes 'received'
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
    rec.pmid = openalex.ids.pmid.split('/').pop() if openalex.ids?.pmid?
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
    rec.email = hasml.Email if hasml?.Email?
    rec.email_cw_batch_count = hasml.email_cw_batch_count if hasml?.email_cw_batch_count?
    if typeof rec.email is 'string' and rec.email.includes '@'
      rec.email = await @encrypt rec.email

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
        delete i.type
    rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if not rec.PMCID and openalex.ids?.pmcid

  rec.updated = await @epoch()
  return rec

P.report.works.load = (timestamp, crossref, openalex, supplement, qry, oaqry, notify, after) ->
  started = await @epoch()

  timestamp ?= @params.load ? @params.timestamp
  crossref ?= @params.crossref
  openalex ?= @params.openalex
  supplement ?= false #@params.supplement
  after ?= @params.after
  after = ((await @epoch()) - 604800000) if after is true
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
  
  qry ?= '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
  qry = '(' + qry + ') AND year.keyword:' + year if year and not qry.includes ':' + year
  qry = '(' + qry + ') AND srcday:>' + timestamp if timestamp and not qry.includes ':>' + timestamp
  console.log qry
  crcount = await @src.crossref.works.count qry
  console.log crcount, 'records available for update from crossref'
  looped = 0
  if crossref isnt false
    console.log 'Starting OA report works loading from crossref'
    for await cr from @index._for 'src_crossref_works', qry, scroll: '30m', max: @params.max, include: ['DOI', 'subject', 'title', 'subtitle', 'volume', 'issue', 'year', 'publisher', 'published', 'funder', 'license', 'is_oa']
      looped += 1
      if (overwrite is true and not after) or not await @report.works (if after then 'DOI.keyword:"' + cr.DOI + '" AND updated:<' + after else cr.DOI)
        total += 1
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
      console.log('report works load xref', total, looped) if not timestamp and ((total and total % 20 is 0) or (looped and looped % 20 is 0))

  if notify isnt false and crossref isnt false and not timestamp
    @mail
      to: ['mark@oa.works', 'joe@oa.works']
      subject: 'OA report works finished crossref load ' + total + ' in ' + took + ' minutes' + (if timestamp then ' for ' + (await @date timestamp) else '') + ', ' + crcount + ' crosref, '
      text: 'https://bg.' + (if @S.dev then 'beta' else 'api') + '.oa.works/report/works'

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
                await @report.orgs.supplement undefined, undefined, undefined, rec, undefined, undefined, supd.hits.hits[0]._source
              oupd = await @src.openalex.works 'ids.doi:"https://doi.org/' + rec.DOI + '" AND updated_date:>' + timestamp
              if oupd?.hits?.total is 1
                ocnts += 1
                console.log 'oalx', org.name, ocnts
                await @report.orgs.supplement undefined, undefined, undefined, rec, undefined, undefined, undefined, oupd.hits.hits[0]._source
  else
    @report.works.load timestamp # start from timestamp a little more than a day ago, by default
  return true
P.report.works.changes._bg = true
P.report.works.changes._async = true
P.report.works.changes._auth = '@oa.works'
  
