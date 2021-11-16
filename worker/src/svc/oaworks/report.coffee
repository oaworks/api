
P.svc.oaworks.report = () ->
  @format = 'html'
  return '<script src="/client/svc/oaworks/report.min.js"></script>'

P.svc.oaworks.report.supplements = _index: true, _prefix: false, _key: 'DOI'
P.svc.oaworks.report.check = (ror, reload) ->
  reload ?= @params.check ? @params.reload ? @params.sheet
  
  started = await @epoch()
  ts = await @datetime(false).replace /[-T\: ]/g, '_'
  console.log 'OA check running', ts, reload

  _from_crossref = (cr) =>
    cr.published = await @src.crossref.works.published cr
    try cr.year = cr.published.split('-')[0]
    try cr.year = parseInt cr.year
    try
      crf = DOI: cr.DOI.toLowerCase(), title: cr.title?[0], journal: cr['container-title']?[0], ISSN: cr.ISSN, publisher: cr.publisher, crossref_published: cr.published, crossref_year: cr.year, citations: cr['reference-count'], crossref_is_oa: cr.is_oa
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
      ex = await @tdm.extract content: JSON.stringify(rec), matchers: matchers
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
    finance: '1xD-5e8TTEpgRL1iCJVOEnSYiddC-K0npkCWCaqx2--4'
    oasupport: '180562eXtmMANfIlioclUrQDaUSWkTOz7igOymfnv2pg'
    staff: '1EZI0iNAXnJ-qbIJFGmtplHWP03NVT7hhf0ICazI0YXw'
    grants: '1lDNHAwH-8x89fgLK-JLs9bBv2cdHsJRnb1Pj86QYWZI'
    names: '1ZowZub-nwOHJrzP7IbhbdoydOAmBRxLysejw38Xt32Y'
    emails: '1U3YXF1DLhGvP4PgqxNQuHOSR99RWuwVeMmdTAmSM45U'
    lens: '1XulUi2Bk3QNsJLekx0PpNb6REhrwQi6Q9M1x_KIUH_0'
    chronos: '1SxIFu4SoROqinOXAZMepOE0d1oxAZgC8LR_nTRi4vpU'
    
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
    headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift() # get headers
    for row in rows
      rec = {}
      for h of headers
        rec[headers[h].toLowerCase()] = if not row[h] then undefined else if row[h].trim().toLowerCase() in ['true', 'yes'] then true else if row[h].trim().toLowerCase() in ['false', 'no'] then false else if headers[h].toLowerCase() in ['grant_id', 'ror'] then row[h].replace(/\//g, ',').replace(/ /g, '').split(',') else row[h]
      if rec.doi and typeof rec.doi is 'string'
        rd = rec.doi.split(',')[0].toLowerCase().replace(/\.$/, '').replace(/\s/, '').split(' ')[0].split('?')[0].trim() # some appeared to be lists of DOIs which is no use e.g. 10.1128/msphere.01330-20, 10.1128/msphere.00490-21
        if rd.startsWith('10.') and rd.includes('/') and rd.length > 6
          if reload
            recs[rd] = await @svc.oaworks.report.supplements rd
            if not recs[rd]?
              recs[rd] ?= await @src.crossref.works rd
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
          else
            recs[rd] = DOI: rd, in_crossref: false
            recs[rd].doi_resolves = false if not await @fetch 'https://doi.org/' + rd
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
      "epmc_licence", "epmc_licence_source", 
      "title", "journal", "ISSN", "publisher", "published", "crossref_published", "oadoi_published", "year", "crossref_year", "oadoi_year", "author_names", "author_affiliation", "funder_name", "funder_grant_ids", 
      # keys examples from OAreport Gates live: https://docs.google.com/spreadsheets/d/1Ufh_xs3NQjzbPRgwlFnHxK5nY2cjn4SsnCqvVnY4Nk8/edit#gid=1145124691
      "grant_id", "invoice_date", "invoice_number",
      # and others suggested by Joe, to be sourced from sheets inputs if not already known:
      "apc_cost", "oawork_finance_internal_id", "type", "to", "status", "sent", "last_contact", "last_heard_from",
      "completed", "follow_up_due", "follow_ups_sent", "author_name", "email",
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
        res.journal_oa_type = await @svc.oaworks.permissions.journals.oa.type undefined, undefined, oadoi, res.crossref

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
        res.permissions = await @svc.oaworks.permissions rcc, undefined, undefined, oadoi, (if JSON.stringify(rcc) is '{}' then undefined else rcc)
        res.can_archive = res.permissions?.best_permission?.can_archive

      res.compliant = await @svc.oaworks.report.compliant res
      
      epmc = undefined
      pubmed = undefined
      if not res.PMCID
        if res.pmcid and (not Array.isArray(res.pmcid) or res.pmcid.length) # may be present from sheets?
          res.PMCID = 'PMC' + res.pmcid.toString().toLowerCase().replace('pmc', '')
          res.PMCID = res.PMCID[0] if Array.isArray res.PMCID
        else if pubmed = await @src.pubmed.doi res.DOI
          if pubmed.identifier?.pmc
            res.PMCID = pubmed.identifier.pmc
            res.PMCID = 'PMC' + res.PMCID.toLowerCase().replace('pmc', '')
        else if res.repository_url_in_pmc and epmc = await @src.epmc.doi res.DOI
          res.PMCID = epmc.pmcid
      if res.PMCID and res.repository_url_in_pmc and not res.epmc_licence
        lic = await @src.epmc.licence res.PMCID, epmc
        res.epmc_licence = lic?.licence
        res.epmc_licence_source = lic?.source
  
      if res.author_names and res.email
        if res.author_names.length is 1
          res.author_email_name = 'Dr. ' + res.author_names[0].split(' ').pop()
        else
          ren = (if typeof res.email is 'string' then res.email else res.email[0]).split('@')[0].toLowerCase().replace(/[^a-z]/g, '')
          best_initial = ''
          best_name = ''
          best_score = 1000000
          for ran in res.author_names
            lvs = await @tdm.levenshtein ren, ran.toLowerCase().replace(/[^a-z]/g, '')
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
            res.author_email_name = best_initial

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
  
      console.log('Gates OA checking', batch.length, dois) if batch.length % 100 is 0

  if not reload
    await @svc.oaworks.report.supplements '' # change this to a delete of only those that are relevant to the source files of the org being checked
  await @svc.oaworks.report.supplements batch

  took = Math.ceil ((await @epoch()) - started)/60000
  console.log 'OA check done after ' + took + ' minutes', reload
  if not reload
    @mail
      to: 'mark@oa.works'
      subject: 'Gates OA check done ' + batch.length + ' in ' + took + ' minutes'
      text: 'https://static.oa.works/report/' + ts
  return batch.length

P.svc.oaworks.report._hides = true
P.svc.oaworks.report.check._bg = true
P.svc.oaworks.report.check._async = true
P.svc.oaworks.report.check._notify = false



P.svc.oaworks.report.compliant = (rec, ror) ->
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

P.svc.oaworks.report.compliance = (ror) ->
  ror ?= @params.report ? @params.compliance ? @params.ror
  papers = await @svc.oaworks.report.supplements.count()
  compliant = await @svc.oaworks.report.supplements.count 'compliant:yes'
  pc = Math.ceil((compliant/papers) * 1000)/10
  return if pc > 100 then 100 else pc

P.svc.oaworks.report.rating = (ror) ->
  ror ?= @params.report ? @params.rating ? @params.ror
  if ror
    ror = await @src.ror(ror) if typeof ror isnt 'object'
    filter = 'type:"journal-article" AND ("' + ror.name + '" OR "' + ror._id + '")'
    papers = await @src.crossref.works.count filter
    opens = await @src.crossref.works.count filter + ' AND is_oa:true'
  else
    papers = await @svc.oaworks.report.supplements.count()
    opens = await @svc.oaworks.report.supplements.count 'is_oa:true'
  pc = Math.ceil((opens/papers) * 1000)/10
  return if pc > 100 then 100 else pc

P.svc.oaworks.report.citations = (filter) ->
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



P.svc.oaworks.report.publishers = (filter) ->
  if filter or not publist = P.svc.oaworks.report._publishers # allow to cache the result for a while...
    pubs = {}
    for pub in await @src.crossref.works.terms 'publisher', filter, 200
      pubs[pub.term] = {papers: pub.count}
    
    filter ?= ''
    filter = '(' + filter + ')' if filter.includes(' OR ') and not filter.includes ')'
    filteroa = (if filter then filter + ' AND ' else '') + 'is_oa:true'
  
    for opub in await @src.crossref.works.terms 'publisher', filteroa, 200
      pubs[opub.term] ?= {}
      pubs[opub.term].open = opub.count
    
    publist = []
    for p of pubs
      pubs[p].name = p
      if pubs[p].open? and not pubs[p].papers?
        pubs[p].papers = await @src.crossref.works.count filter + (if filter then ' AND ' else '') + ' publisher.keyword:"' + p + '"'
      if pubs[p].papers and not pubs[p].open?
        pubs[p].open = await @src.crossref.works.count filteroa + ' AND publisher.keyword:"' + p + '"'
      pubs[p].rating = if pubs[p].open and pubs[p].papers then pubs[p].open / pubs[p].papers else 0
      pubs[p].percent = Math.ceil(pubs[p].rating * 1000)/10
      pubs[p].percent = 100 if pubs[p].percent > 100
      if pubs[p].papers and pubs[p].rating
        publist.push pubs[p]
    
    #publist.sort (a, b) => return b.rating - a.rating
    publist.sort (a, b) => return b.rating - a.rating or b.open - a.open
    
    P.svc.oaworks.report._publishers = publist

  return publist

P.svc.oaworks.report.journals = () ->
  if not jrnlist = P.svc.oaworks.report._journals
    jrnls = {}
    for jrnl in await @src.crossref.works.terms 'container-title', undefined, 200
      jrnls[jrnl.term] = {papers: jrnl.count}
    
    for oj in await @src.crossref.works.terms 'container-title', 'is_oa:true', 200
      jrnls[oj.term] ?= {}
      jrnls[oj.term].open = oj.count
    
    jrnlist = []
    for j of jrnls
      jrnls[j].name = j
      if jrnls[j].open? and not jrnls[j].papers?
        jrnls[j].papers = await @src.crossref.works.count 'container-title.keyword:"' + j + '"'
      if jrnls[j].papers and not jrnls[j].open?
        jrnls[j].open = await @src.crossref.works.count 'is_oa:true AND container-title.keyword:"' + j + '"'
      jrnls[j].rating = if jrnls[j].open and jrnls[j].papers then jrnls[j].open / jrnls[j].papers else 0
      jrnls[j].percent = Math.ceil(jrnls[j].rating * 1000)/10
      jrnls[j].percent = 100 if jrnls[j].percent > 100
      if jrnls[j].papers and jrnls[j].rating
        jrnlist.push jrnls[j]
    
    #jrnlist.sort (a, b) => return b.rating - a.rating
    jrnlist.sort (a, b) => return b.rating - a.rating or b.open - a.open
  
    P.svc.oaworks.report._journals = jrnlist
  
  return jrnlist



P.svc.oaworks.report.compare = () ->
  res = 
    crossref: await @src.crossref.works.count '(funder.DOI:"10.13039/100000865" OR funder.name:"gates foundation" OR funder.name:"gates cambridge trust" OR author.affiliation.name:"melinda gates" OR author.affiliation.name:"gates cambridge trust")'
    pubmed: await @src.pubmed.count 'grant.agency:"melinda gates" OR grant.agency:"gates cambridge trust" OR author.affiliation:"melinda gates" OR author.affiliation:"gates cambridge trust"' # what about gates international research scholar? Or things like "gates institute for..." Also just the phrase in any field matches another ~204 mostly in abstract or title, but not necessarily Gates-funded articles, just ABOUT gates work
    pubmednodoi: 0
    pubmednotcrossref: 0
    pubmednotepmc: 0
    mag: 0
    magnodoi: 0
    magnodoimatchedtitle: 0
    magnotcrossref: 0
    magnotcrossrefviatitle: 0
    magnotcrossrefnotpubmed: 0
  pubmednotcrossref = []
  for await rec from @index._for 'src_pubmed', 'grant.agency:"melinda gates" OR grant.agency:"gates cambridge trust" OR author.affiliation:"melinda gates" OR author.affiliation:"gates cambridge trust"'
    if not rec.identifier?.pmc
      res.pubmednotepmc += 1
    if rec.identifier?.doi
      if cr = await @src.crossref.works rec.identifier.doi
        crs = JSON.stringify(cr).toLowerCase()
        if not crs.includes('10.13039/100000865') and not crs.includes('gates foundation') and not crs.includes('gates cambridge trust')
          res.pubmednotcrossref += 1
          pubmednotcrossref.push rec.identifier.doi
      else
        res.pubmednotcrossref += 1
        pubmednotcrossref.push rec.identifier.doi
    else
      res.pubmednodoi += 1
  seen = []
  for await rec from @index._for 'src_microsoft_graph_relation', 'OriginalAffiliation:"melinda gates"'
    if rec.PaperId not in seen
      seen.push rec.PaperId
      res.mag += 1
      paper = await @src.microsoft.graph rec.PaperId
      if paper.Doi
        if cr = await @src.crossref.works paper.Doi
          crs = JSON.stringify(cr).toLowerCase()
          if not crs.includes('10.13039/100000865') and not crs.includes('gates foundation') and not crs.includes('gates cambridge trust')
            res.magnotcrossref += 1
            res.magnotcrossrefnotpubmed += 1 if paper.Doi not in pubmednotcrossref
        else
          res.magnotcrossref += 1
          res.magnotcrossrefnotpubmed += 1 if paper.Doi not in pubmednotcrossref
      else
        res.magnodoi += 1
        if paper.PaperTitle and cr = await @src.crossref.works 'title:"' + paper.PaperTitle + '"'
          if cr?.hits?.total isnt 0
            res.magnodoimatchedtitle += 1
            cr = cr.hits.hits[0]._source
            crs = JSON.stringify(cr).toLowerCase()
            if not crs.includes('10.13039/100000865') and not crs.includes('gates foundation') and not crs.includes('gates cambridge trust')
              res.magnotcrossref += 1
              res.magnotcrossrefviatitle += 1
          else
            res.magnotcrossrefnotpubmed += 1
  return res

