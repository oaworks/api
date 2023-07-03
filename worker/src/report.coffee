
try S.report = JSON.parse SECRETS_REPORT
S.report ?= {}

P.report = () -> return 'OA.Works report'

P.report.dev2live = (reverse) ->
  if not reverse
    f = 'paradigm_b_report_works'
    t = 'paradigm_report_works'
  else
    f = 'paradigm_report_works'
    t = 'paradigm_b_report_works'
  if @params.clear
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

P.report.cleandoi = (doi) ->
  doi ?= @params.cleandoi ? @params.doi
  try doi = '10.' + doi.split('/10.')[1] if doi.startsWith 'http'
  try doi = doi.toLowerCase().replace('doi ', '') if doi.startsWith 'doi '
  try doi = doi.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').replace(/^\//, '').split(' ')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim()
  if typeof doi is 'string' and doi.startsWith '10.'
    return doi
  else
    return ''



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

P.report.orgs.supplements = _index: true, _auth: '@oa.works'
P.report.orgs.supplements.load = (orgname, sheetname, clear) ->
  started = await @epoch()
  clear ?= @params.clear
  await @report.orgs.supplements('') if clear
  orgname ?= @params.org
  sheetname ?= @params.sheet
  recs = await @src.google.sheets S.report.orgs_sheet
  total = 0
  deletes = []
  dois = []
  replacements = {}
  sheets = []
  sheetnames = []
  if not clear
    replacements[sup.replaced] = sup.DOI for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'replaced:*'

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
          rc = 0
          osdids = []
          headers = []
          update = true
          sups = []
          await @sleep 1000
          try
            check = await @src.google.sheets sheetid: s.url, sheet: 'm_admin', headers: false
            await @sleep 1000 # more sleeps to avoid google 429 sadness
            if Array.isArray(check) and check.length and check[0][0].toLowerCase() is 'last updated' and last = check[0][1]
              [ld, lt] = last.split ' '
              ld = ld.split('/').reverse().join('-')
              last = await @epoch ld + 'T' + lt
              console.log org.name, s.name, 'last updated', last
              if typeof last is 'number' and last > 1672531200000 # start of 2023, just in case of a bad date
                latest = await @report.orgs.supplements 'sheets.keyword:"' + s.name + '"', size: 1, sort: updated: 'desc'
                latest = latest.hits.hits[0]._source if latest.hits?.hits?
                update = last if latest?.updated and last <= latest.updated
          if update isnt true
            console.log org.name, s.name, 'NOT loading because', last, 'is not after', latest?.updated
          else
            await @sleep 1000
            try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
            tries = 0
            while (not Array.isArray(rows) or not rows.length) and tries < 3 # https://github.com/oaworks/Gates/issues/375
              await @sleep 2000
              tries += 1
              try rows = await @src.google.sheets sheetid: s.url, sheet: 'Export', headers: false
            if Array.isArray(rows) and rows.length
              headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
              for row in rows
                rc += 1
                rr = org: org.name, sheets: s.name, ror: org.ror, paid: (if org.paid is true then org.paid else undefined) # check paid explicitly because some had an empty string instead of a bool
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
                if not rr.doi
                  rr.doi = (rr.DOI ? '') + ''
                else
                  rr.DOI ?= rr.doi + ''
                if rr.DOI = await @report.cleandoi rr.DOI
                  if not clear and replacements[rr.DOI]? #rep = await @report.orgs.supplements 'replaced.keyword:"' + rr.DOI + '"', 1
                    rr.replaced = rr.DOI
                    rr.DOI = replacements[rr.DOI] #rep.DOI
                  rr.email = await @encrypt(rr.email) if typeof rr.email is 'string' and rr.email.includes '@'
                  rr._id = rr.osdid = (org.name.replace(/[^a-zA-Z0-9-_ ]/g, '') + '_' + s.name + '_' + rr.DOI).replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
                  osdids.push rr.osdid
                  if rr.DOI not in dois
                    kc = false
                    if not clear
                      present = await @report.works 'supplements.osdid.keyword:"' + rr.osdid + '"', 1
                      present = present.hits.hits[0]._source if present?.hits?.hits? and present.hits.hits.length
                      try
                        for prs in present.supplements
                          if prs.osdid is rr.osdid
                            present = prs
                            break
                      if present?
                        kc = await @copy rr
                        delete kc.updated
                        for k of present
                          break if k not in ['updated'] and JSON.stringify(rr[k] ? '').toLowerCase() isnt JSON.stringify(present[k]).toLowerCase() # JSON string match on object isn't guaranteed but probably likely enough for the number of times we'll need it
                          delete kc[k]
                    dois.push(rr.DOI) if clear or JSON.stringify(kc) isnt '{}'
                  rr.updated = started
                  sups.push rr
                  total += 1
              console.log org.name, s.name, sups.length, dois.length
              await @report.orgs.supplements sups
            for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'org.keyword:"' + org.name + '" AND sheets.keyword:"' + s.name + '"', scroll: '5m', include: ['osdid']
              if sup.osdid not in osdids
                await @report.orgs.supplements sup.osdid, ''
                deletes.push sup.osdid
                dois.push(sup.DOI) if sup.DOI not in dois # need to rerun for ones where something has been deleted too so that deleted supplements get removed from the work
          sheets.push org: org.name, sheet: s.name, rows: rc, update: update, supplements: sups.length
          sheetnames.push s.name

  # check for sheets that have since been removed
  if not clear and not orgname and not sheetname
    for aps in await @report.works.suggest 'supplements.sheets', undefined, 5000
      if aps not in sheetnames
        for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'sheets.keyword:"' + aps + '"', scroll: '5m', include: ['osdid']
          await @report.orgs.supplements sup.osdid, ''
          deletes.push sup.osdid
        for await osw from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'supplements.sheets.keyword:"' + aps + '"', scroll: '5m', include: ['DOI']
          dois.push(osw.DOI) if osw.DOI and osw.DOI not in dois

  await @sleep 60000 # wait a while for the supplements index to finish building and then run the processing for DOIs
  #await @mail to: 'mark@oa.works', subject: 'OA report orgs supplements loaded ' + total, text: 'report orgs supplements load ' + total + '\ndois ' + dois.length + '\ndeletes ' + deletes.length + '\ntook ' + await @epoch() - started
  console.log 'report orgs supplements load', total, dois.length, deletes.length, await @epoch() - started
  if dois.length
    console.log 'reoprt orgs supplements load ready to call works load', dois.length
    await @report.works.load undefined, undefined, dois, undefined, undefined, started, undefined, sheets
  return total
P.report.orgs.supplements.load._async = true
P.report.orgs.supplements.load._auth = '@oa.works'



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



P.report.works = _index: true
P.report.works.process = (cr, openalex, refresh, everything, replaced) ->
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
        exists = await @report.works _id: openalex
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
    exists ?= await @report.works(if typeof cr is 'string' then cr else cr.DOI)
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
    _rsup = (sup, ud) =>
      sup.DOI = cr.DOI
      sup.replaced = ud
      await @report.orgs.supplements sup.osdid, ''
      sup._id = sup.osdid = sup.osdid.split('_10.')[0] + '_' + sup.DOI.replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_')
      brd.push sup
    for ud in (cr['update-to'] ? [])
      if ud.DOI isnt cr.DOI and ud.type.toLowerCase() not in ['erratum', 'correction'] # some new version statements are for the same DOI, so no point changing anything
        rec.replaces = []
        rec.replaces.push DOI: ud.DOI, type: ud.type, updated: ud.updated?.timestamp
        await @report.works(ud.DOI, '') if ude = await @report.works ud.DOI
        _rsup(sup, ud.DOI) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + ud.DOI + '"'
    for rr in (cr.relation?['is-same-as'] ? [])
      if rr['id-type'] is 'doi' and rr.id isnt cr.DOI and rr.id isnt replaced and newer = await @src.crossref.works rr.id # crossref is capable of saying a DOI is the same as another DOI that does not exist in crossref
        _rsup(sup, rr.id) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + cr.DOI + '"'
    await @report.orgs.supplements(brd) if brd.length
    if newer?
      return @report.works.process newer, openalex, refresh, everything, cr.DOI
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

  if rec.is_paratext or rec.is_retracted
    if rec.DOI
      try
        pfn = (if rec.is_paratext then 'paratext' else 'retracted') + (if @S.dev then '_dev' else '')
        prds = []
        try prds = JSON.parse (await fs.readFile @S.static.folder + pfn + '.json').toString()
        prds.push(rec.DOI) if rec.DOI not in prds
        await fs.writeFile @S.static.folder + pfn + '.json', JSON.stringify prds, '', 2
    return 

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
      rec.author_email_name = sup.author_email_name_ic if sup.author_email_name_ic
      rec.supplements.push sup

  if exists?
    rec.author_email_name = exists.author_email_name if not rec.author_email_name and exists.author_email_name and exists.email and rec.email and rec.email.toLowerCase() is exists.email.toLowerCase()
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
    if not rec.PMCID or not rec.PMID or not rec.pubtype or not rec.submitted_date or not rec.accepted_date
      if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else await @src.pubmed.doi rec.DOI) # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
        rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if not rec.PMCID and pubmed?.identifier?.pmc
        rec.PMID = pubmed.identifier.pubmed if not rec.PMID and pubmed?.identifier?.pubmed
        rec.pubtype = pubmed.type # this is a list
        rec.submitted_date ?= pubmed.dates?.PubMedPubDate_received?.date
        rec.accepted_date ?= pubmed.dates?.PubMedPubDate_accepted?.date

    if not rec.journal_oa_type # restrict permissions only to records with orgs supplements? for now no
      permissions = await @permissions (await @copy rec), undefined, undefined, oadoi, cr, started - 1209600000 # (if refresh then undefined else started - 1209600000) # use cached best permissions up to two weeks old
      rec.can_archive = permissions?.best_permission?.can_archive
      rec.can_archive = true if not rec.can_archive? and ((oadoi?.best_oa_location?.license ? '').includes('cc') or oadoi?.journal_is_in_doaj)
      rec.version = permissions?.best_permission?.version
      rec.journal_oa_type = await @permissions.journals.oa.type rec.issn, undefined, oadoi, cr # calculate journal oa type separately because it can be different for a journal in general than for what permissions calculates in more specificity
      rec.journal_oa_type ?= 'unsuccessful'

    if everything
      if not rec.PMCID or not rec.pubtype or not rec.submitted_date or not rec.accepted_date # only thing restricted to orgs supplements for now is remote epmc lookup and epmc licence calculation below
        if epmc = await @src.epmc.doi rec.DOI
          rec.PMCID = epmc.pmcid if epmc.pmcid
          rec.submitted_date ?= epmc.firstIndexDate
          rec.accepted_date ?= epmc.firstPublicationDate
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
  if rec.DOI and @params.process is rec.DOI and @params.save isnt false
    await @report.works rec
  #console.log 'report works processed', rec.DOI, rec.took
  return rec


P.report.works.load = (timestamp, org, dois, year, refresh, supplements, everything, info) ->
  started = await @epoch()
  year ?= @params.load ? (await @date()).split('-')[0] # load could be supplements or everything but in that case year is not used anyway
  org ?= @params.org ? @params.orgs ? @params.load is 'orgs'
  dois = @params.load if not dois? and @params.load? and @params.load.startsWith '10.'
  dois = [dois] if typeof dois is 'string'
  refresh ?= @refresh
  everything ?= @params.load is 'everything'

  await @report.works('') if refresh

  batch = []
  batchsize = 2000
  bt = 0
  total = 0
  cc = []
  oo = []

  _batch = (cr, ol) =>
    bt += 1
    console.log bt, cr, ol
    if typeof cr is 'string' and cr.startsWith('W') and not ol
      ol = cr
      cr = undefined
    if cr? or ol?
      prc = await @report.works.process cr, ol, (timestamp ? refresh), everything
      if prc?._id?
        batch.push prc
        total += 1
      else
        console.log 'report works load finding empty works', cr, ol, prc
      console.log('report load building batch', batch.length) if batch.length % 200 is 0
      if batch.length is batchsize
        await @report.works batch
        batch = []
        console.log 'report works load', total, bt, (if dois then dois.length else undefined), await @epoch() - started

  if @params.load is 'supplements'
    dois ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', (if timestamp then 'updated:<' + timestamp else undefined), scroll: '5m', include: ['DOI']
      dois.push(sup.DOI) if sup.DOI not in dois
    console.log 'report works supplements to load', dois.length
  else if everything
    dois ?= []
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'NOT pmc_has_data_availability_statement:*', scroll: '5m', include: ['DOI', 'openalex']
      sd = sup.DOI ? sup.openalex
      dois.push(sd) if sd not in dois
    console.log 'report works supplements to load everything for records that do not yet have everything', dois.length

  if Array.isArray dois
    await _batch(d) for d in dois
  else
    _crossref = (cq) =>
      processed = cc.length
      cq ?= '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
      cq = '(' + cq + ') AND srcday:>' + timestamp if timestamp
      console.log 'report works load crossref by query', cq
      cc = []
      cc.push(cr.DOI) for await cr from @index._for 'src_crossref_works', cq, include: ['DOI'], scroll: '30m' #, include: ['DOI', 'subject', 'title', 'subtitle', 'volume', 'issue', 'year', 'publisher', 'published', 'funder', 'license', 'is_oa', 'ISSN', 'update-to', 'reference-count']
      console.log 'report works load crossref by query counted', cc.length
      await @mail to: ['mark@oa.works'], subject: 'report works load crossref by query counted ' + cc.length, text: cc.length + '\n\n' + cq
      await _batch(d) for d in cc.slice processed
      await @mail to: ['mark@oa.works'], subject: 'report works load crossref done ' + bt, text: bt + ''

    await _crossref() if org isnt true

    _openalex = (oq) =>
      processed = oo.length
      oq ?= 'authorships.institutions.display_name:* AND publication_year:' + year # NOT ids.doi:* AND 
      oq = '(' + oq + ') AND updated_date:>' + timestamp if timestamp
      console.log 'report works load openalex by query', oq
      for await ol from @index._for 'src_openalex_works', oq, include: ['id', 'ids'], scroll: '30m'
        oodoi = if ol.ids?.doi then '10.' + ol.ids.doi.split('/10.')[1] else undefined
        if ol.id and ol.id.includes('/') and (not oodoi or (oodoi not in oo and oodoi not in cc))
          oo.push ol.id.split('/').pop()
      console.log 'report works load openalex by query counted', oo.length
      await @mail to: ['mark@oa.works'], subject: 'report works load crossref by query counted ' + cc.length, text: oo.length + '\n\n' + oq
      await _batch(undefined, o) for o in oo.slice processed
      await @mail to: ['mark@oa.works'], subject: 'report works load openalex done ' + bt, text: bt + ''
    
    await _openalex() if org isnt true

    for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs', (if typeof org is 'string' then 'name:"' + org + '"' else 'paid:true'), scroll: '10m'
      # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      try await _crossref(o.source.crossref) if o.source?.crossref
      try await _openalex(o.source.openalex) if o.source?.openalex

    if timestamp
      for await crt from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'orgs:* AND updated:<' + timestamp, scroll: '10m'
        await _batch(crt) if updated = await @src.crossref.works 'DOI:"' + crt.DOI + '" AND srcday:>' + timestamp
    

  await @report.works(batch) if batch.length
  #await @report.works.load(undefined, undefined, undefined, undefined, undefined, undefined, true) if not dois

  took = await @epoch() - started
  text = 'Report works loaded ' + total + (if @S.dev then ' (dev)' else '') + '\n'
  text += 'All old works were removed before loading began\n' if refresh
  text += dois.length + ' DOIs were provided to process\n' if dois and dois.length
  text += 'These were derived by searching for all works that already have supplements attached\n' if @params.load is 'supplements'
  text += 'These were derived by searching for all works that have not yet had everything fully processed\n' if everything
  text += 'These were provided by an orgs supplements refresh which took ' + Math.ceil((started - supplements)/1000/60) + 'm\n' if supplements
  text += 'The load process was limited to ' + org + '\n' if typeof org is 'string'
  text += 'The load process was run for changes since ' + (await @datetime timestamp) + '\n' if timestamp
  text += 'The load process was run for year ' + year + '\n' if year and not (dois ? []).length
  text += 'Crossref queries counted ' + cc.length + ' works\n' if cc.length
  text += 'Openalex queries counted ' + oo.length + ' works\n' if oo.length
  text += 'Load processing took ' + Math.ceil(took/1000/60) + 'm\n'
  text += '\n' + JSON.stringify(i) + '\n' for i in (info ? [])
  console.log 'Report works loaded', total, took
  await @mail to: ['mark@oa.works', 'joe@oa.works'], subject: 'OA report works works loaded ' + total, text: text
  return total
P.report.works.load._async = true
P.report.works.load._auth = '@oa.works'

P.report.works.changes = (timestamp, org) ->
  # do not reload orgs first before running changes, Joe wants that to remain a manual process
  timestamp ?= @params.changes ? @params.timestamp ? Date.now() - 90000000
  org ?= @params.org
  @report.works.load timestamp, org # start from timestamp a little more than a day ago, by default
  return true
P.report.works.changes._bg = true
#P.report.works.changes._async = true
P.report.works.changes._auth = '@oa.works'

'''P.report.works.check = (year) ->
  year ?= @params.check ? @params.year ? '2023'
  res = year: year, crossref: 0, openalex: 0, crossref_in_works: 0, crossref_in_works_had_openalex: 0, crossref_not_in_works_in_openalex: 0, openalex_in_works: 0, openalex_in_works_by_id: 0, openalex_with_doi_but_not_seen: 0, openalex_not_in_works: 0, duplicates: 0
  cq = '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year
  seen = []
  not_in_works = []
  for await cr from @index._for 'src_crossref_works', cq, include: ['DOI'] #, scroll: '30m'
    console.log 'crossref', res.crossref
    if cr.DOI not in seen
      seen.push cr.DOI
    else
      res.duplicates += 1
    res.crossref += 1
    res.crossref_in_works += 1 if worked = await @report.works cr.DOI
    not_in_works.push(cr.DOI) if not worked and cr.DOI not in not_in_works
    if worked?.openalex
      res.crossref_in_works_had_openalex += 1
    else if olx = await @src.openalex.works 'ids.doi:"' + cr.DOI + '"'
      res.crossref_not_in_works_in_openalex += 1

  oq = 'authorships.institutions.display_name:* AND publication_year:' + year
  for await ol from @index._for 'src_openalex_works', oq, include: ['id', 'ids'] #, scroll: '30m'
    console.log 'openalex', res.openalex
    res.openalex += 1
    oodoi = if ol.ids?.doi then '10.' + ol.ids.doi.split('/10.')[1] else undefined
    if oodoi
      if oodoi not in seen
        res.openalex_with_doi_but_not_seen += 1 if oodoi
        seen.push oodoi
      else
        res.duplicates += 1
    if oodoi and worked = await @report.works oodoi
      res.openalex_in_works += 1
    else if worked = await @report.works 'openalex.keyword:"' + ol.id + '"', 1
      res.openalex_in_works += 1
      res.openalex_in_works_by_id += 1
    else
      res.openalex_not_in_works += 1
    not_in_works.push(oodoi ? ol.id) if not worked and (oodoi ? ol.id) not in not_in_works

  res.seen = seen.length
  res.not_in_works = not_in_works.length
  try await fs.writeFile @S.static.folder + 'report_check_' + year + '.json', JSON.stringify res, '', 2
  try await fs.writeFile @S.static.folder + 'report_check_seen_' + year + '.json', JSON.stringify seen, '', 2
  try await fs.writeFile @S.static.folder + 'report_check_missing_' + year + '.json', JSON.stringify not_in_works, '', 2
  return res
P.report.works.check._async = true

P.report.test = _index: true, _alias: 'altest2'

P.report.test.add = ->
  l = await @dot P, 'report.test._alias'
  await @report.test hello: 'world', alias: l ? 'none'
  await @sleep 2000
  res = count: await @report.test.count(), ford: 0, records: []
  for await i from @index._for 'report_test', '*'
    res.ford += 1
    res.records.push i
  return res
'''