
P.permissions_new = (meta, ror, openalex) ->
  overall_policy_restriction = false
  haddoi = false
  
  _format = (rec) ->
    if haddoi and rec.embargo_months and (meta.published or meta.year)
      em = new Date Date.parse meta.published ? meta.year + '-01-01'
      em = new Date em.setMonth em.getMonth() + rec.embargo_months
      rec.embargo_end = em.toISOString().split('T')[0]
    delete rec.embargo_end if rec.embargo_end is ''
    rec.copyright_name = if rec.copyright_owner and rec.copyright_owner.toLowerCase() is 'publisher' then (if typeof rec.issuer.parent_policy is 'string' then rec.issuer.parent_policy else if typeof rec.issuer.id is 'string' then rec.issuer.id else rec.issuer.id[0]) else if rec.copyright_owner and rec.copyright_owner.toLowerCase() in ['journal','affiliation'] then (meta.journal ? '') else if (haddoi and rec.copyright_owner and rec.copyright_owner.toLowerCase().includes('author')) and meta.author? and meta.author.length and (meta.author[0].name or meta.author[0].family) then (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '') else ''
    #if rec.copyright_name.toLowerCase() in ['publisher','journal'] and (openalex or meta.doi or rec.provenance?.example)
    #  openalex ?= await @src.openalex.works.doi meta.doi ? rec.provenance.example
    #  crossref assertion of name 'copyright' used to give us a copyright_name value here, but openalex has no similar relevant field as far as I know
    rec.copyright_year = meta.year if haddoi and rec.copyright_year is '' and meta.year
    delete rec.copyright_year if rec.copyright_year is ''
    if haddoi and rec.deposit_statement? and rec.deposit_statement.includes '<<'
      fst = ''
      for pt in rec.deposit_statement.split '<<'
        if fst is '' and not pt.includes '>>'
          fst += pt
        else
          eph = pt.split '>>'
          ph = eph[0].toLowerCase()
          swaps = 
            'journal title': 'journal'
            'vol': 'volume'
            'date of publication': 'published'
            '(c)': 'year'
            'article title': 'title'
            'copyright name': 'copyright_name'
          ph = swaps[ph] if swaps[ph]?
          if ph is 'author'
            try fst += (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '')
          else
            fst += meta[ph] ? rec[ph] ? ''
          try fst += eph[1]
      rec.deposit_statement = fst
    if rec._id?
      rec.meta ?= {}
      rec.meta.source = 'https://' + (if S.dev then 'beta.oa.works/permissions/' else 'api.oa.works/permissions/') + (if rec.issuer.type then rec.issuer.type + '/' else '') + rec._id
    overall_policy_restriction = rec.issuer.has_policy if typeof rec.issuer?.has_policy is 'string' and rec.issuer.has_policy.toLowerCase().trim() in ['not publisher','takedown']
    delete rec[d] for d in ['_id', 'hide']
    return rec

  _score = (rec) =>
    score = (if rec.can_archive then 1000 else 0) + (if rec.provenance?.oa_evidence is 'In DOAJ' then 1000 else 0) + (if rec.licence then -5 else 0)
    score += if rec.requirements? then -10 else if rec.version is 'publishedVersion' then 200 else if rec.version is 'acceptedVersion' then 100 else 0
    score += if rec.issuer?.type.toLowerCase() is 'journal' then 5 else if rec.issuer?.type.toLowerCase() is 'publisher' then 4 else if rec.issuer?.type.toLowerCase() is 'university' then 3 else if rec.issuer?.type.toLowerCase() in ['article'] then 2 else 0
    score -= 25 if rec.embargo_months and rec.embargo_months >= 36 and (not rec.embargo_end or Date.parse(rec.embargo_end) < Date.now())
    return score

  meta = (if meta.startsWith('10.') then {doi: meta} else {issn: meta}) if typeof meta is 'string'
  meta ?= @copy @params
  try # TODO TEMP
    meta.permissions = meta.permissions_new
    delete meta.permissions_new
  delete meta.metadata if meta?.metadata is true # just a pass-through for us to show metadata for debug
  if meta?.permissions? and typeof meta.permissions is 'string'
    if meta.permissions.startsWith 'journal/'
      meta.issn = meta.permissions.replace 'journal/', ''
    else if meta.permissions.startsWith 'affiliation/'
      meta.ror = meta.permissions.replace 'affiliation/', ''
    else if meta.permissions.startsWith 'publisher/'
      meta.publisher = meta.permissions.replace 'publisher/', ''
    else if meta.permissions.startsWith('10.') and meta.permissions.includes '/'
      meta.doi = meta.permissions
    else if meta.permissions.includes('-') and meta.permissions.length < 10 and meta.permissions.length > 6
      meta.issn = meta.permissions
    else if not meta.permissions.includes(' ') and not meta.permissions.includes(',') and meta.permissions.replace(/[0-9]/g, '').length isnt meta.permissions.length
      meta.ror = meta.permissions
    else
      meta.publisher = meta.permissions # but could be a ROR?
    delete meta.permissions

  if meta.affiliation
    meta.ror = meta.affiliation
    delete meta.affiliation
  meta.ror ?= ror
  meta.ror = meta.ror.split(',') if typeof meta.ror is 'string' and meta.ror.includes ','

  if meta.journal and not meta.journal.includes(' ') and meta.journal.includes '-'
    meta.issn = meta.journal
    delete meta.journal
  meta.issn = meta.issn.split(',') if typeof meta.issn is 'string'

  return {body: 'No valid DOI, ISSN, or ROR provided', status: 404} if JSON.stringify(meta) is '{}' or (meta.issn and not JSON.stringify(meta.issn).includes('-')) or (meta.doi and (typeof meta.doi isnt 'string' or not meta.doi.startsWith('10.') or not meta.doi.includes '/'))
  
  haddoi = meta.doi
  try meta.doi ?= await @permissions_new.journals.example meta.issn
  if haddoi and (not meta.publisher or not meta.issn) and openalex ?= await @src.openalex.works haddoi # search works.doi to get remote if not local
    # we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article.
    # subject of any use? openalex does not have subject but does have keywords, topics, fields
    # using @citation for this may be suitable
    for a in openalex.authorships ? []
      au = {}
      au.name = a.author.display_name
      au.family = au.name.split(' ').pop()
      au.given = au.name.split(' ')[0] if au.name.split(' ').length > 1
      for aff in a.raw_affiliation_strings ? []
        au.affiliation ?= []
        au.affiliation.push name: aff
      meta.author ?= []
      meta.author.push au
    meta.type ?= openalex.type_crossref
    if openalex.primary_location?.source?.type is 'journal' # or others apart from journal?
      meta.publisher ?= openalex.primary_location.source.publisher ? openalex.primary_location.source.host_organization_name
      meta.journal ?= openalex.primary_location.source.display_name # is shortname and journal_short required for anything on the SYP / ILL widgets? If so copy here
      meta.issn ?= []
      meta.issn.push(oi) for oi in (openalex.primary_location.source.issn ? []) when oi not in meta.issn
    meta.published ?= openalex.publication_date # like 2009-01-01
    meta.year ?= openalex.publication_year
    meta.abstract = openalex.abstract
    meta[ok] ?= openalex[ok] for ok in ['title'] when openalex[ok]
    meta[bk] ?= openalex.biblio[bk] for bk in ['volume', 'issue'] when openalex.biblio?[bk]
    if openalex.biblio?.first_page or openalex.biblio?.last_page
      meta.pages = (openalex.biblio.first_page ? '') + (if openalex.biblio.first_page and openalex.biblio.last_page then ' to ' else '') + (openalex.biblio.last_page ? '')
  meta.year = meta.published.split('-')[0] if not meta.year and meta.published and meta.published.includes('-')
  meta.year += '' if typeof meta.year is 'number'
  meta.published = meta.year + '-01-01' if not meta.published and meta.year
  meta.issn = [meta.issn] if typeof meta.issn is 'string'
  meta.publisher = meta.publisher.substring(0, meta.publisher.lastIndexOf('(')).trim() if meta.publisher and meta.publisher.includes('(') and meta.publisher.lastIndexOf(')') > (meta.publisher.length*.7) # get rid of acronym at end like Public Library of Science (PLoS) because crossref etc don't usuallt include it
  
  return {body: 'DOI is not a journal article', status: 501} if haddoi and meta.type not in ['journal-article', 'article']
      
  try
    meta.citation = '[' + if meta.title then meta.title + '. ' else ''
    meta.citation += meta.journal + ' ' if meta.journal
    meta.citation += meta.volume + (if meta.issue then ', ' else ' ') if meta.volume
    meta.citation += meta.issue + ' ' if meta.issue
    meta.citation += 'p' + (meta.page ? meta.pages) if meta.page? or meta.pages?
    meta.citation += ' (' + (meta.year ? meta.published).split('-')[0] + ')' if meta.year or meta.published
    meta.citation = meta.citation.trim() + ']'

  perms = best_permission: undefined, all_permissions: []
  rors = []
  if meta.ror?
    meta.ror = [meta.ror] if typeof meta.ror is 'string'
    rs = await @permissions.affiliations 'issuer.id:"' + meta.ror.join('" OR issuer.id:"') + '"'
    if not rs?.hits?.total
      try rw = await @src.ror(if meta.ror.length is 1 then meta.ror[0] else 'id:"' + meta.ror.join(" OR id:") + '"')
      rw = rw.hits.hits[0]._source if rw?.hits?.total # look up the ROR, get the ISO 3166-1 alpha-2 code, search affiliations for that
      rs = await @permissions.affiliations('issuer.id:"' + rw.country.country_code + '"') if rw?.country?.country_code
    for rr in rs?.hits?.hits ? []
      tr = await _format rr._source
      tr.score = await _score tr
      rors.push tr

  indoaj = undefined
  if meta.issn
    for await rec from @index._for 'src_doaj_journals', 'bibjson.pissn:"' + meta.issn.join('" OR bibjson.pissn:"') + '" OR bibjson.eissn:"' + meta.issn.join('" OR bibjson.eissn:"') + '"'
      indoaj ?= rec
      meta.issn.push(rec.bibjson.pissn) if rec.bibjson.pissn not in meta.issn
      meta.issn.push(rec.bibjson.eissn) if rec.bibjson.eissn not in meta.issn
    ps = await @permissions.journals 'issuer.id:"' + meta.issn.join('" OR issuer.id:"') + '"'
    for p in ps?.hits?.hits ? []
      rp = await _format p._source
      rp.score = await _score rp
      perms.all_permissions.push rp
      
  if meta.publisher
    ps = await @permissions.publishers 'issuer.id:"' + meta.publisher + '"' # how exact/fuzzy can this be
    for p in ps?.hits?.hits ? []
      rp = await _format p._source
      rp.score = await _score rp
      perms.all_permissions.push rp

  altoa =
    can_archive: true
    version: 'publishedVersion'
    versions: ['publishedVersion']
    licence: undefined
    locations: ['institutional repository']
    embargo_months: undefined
    issuer:
      type: 'Journal'
      has_policy: 'yes'
    meta:
      creator: 'joe+doaj@oa.works'
      contributors: ['joe+doaj@oa.works']
      monitoring: 'Automatic'

  if indoaj
    for dl in (indoaj.bibjson?.license ? [])
      altoa.licence = dl.type if not altoa.licence or altoa.licence.length > dl.type
      altoa.licences ?= []
      altoa.licences.push type: dl.type
    # used to check src.crossref.journals here for journal licence if didn't get it from DOAJ - can this be checked in openalex instead if necessary?
    if typeof altoa.licence is 'string'
      altoa.licence = altoa.licence.toLowerCase().trim()
      if altoa.licence.startsWith 'cc'
        altoa.licence = altoa.licence.replace(/ /g, '-')
      else if altoa.licence.includes 'creative'
        altoa.licence = if altoa.licence.includes('0') or altoa.licence.includes('zero') then 'cc0' else if altoa.licence.includes('share') then 'ccbysa' else if altoa.licence.includes('derivative') then 'ccbynd' else 'ccby'
      else
        delete altoa.licence
    else
      delete altoa.licence
    altoa.issuer.id = if indoaj.bibjson.eissn and indoaj.bibjson.pissn then [indoaj.bibjson.pissn, indoaj.bibjson.eissn] else if indoaj.bibjson.pissn then [indoaj.bibjson.pissn] else [indoaj.bibjson.eissn]
    altoa.embargo_months = 0
    altoa.provenance = {oa_evidence: 'In DOAJ'}
    altoa.score = await _score altoa
    perms.all_permissions.push altoa
  
  else if meta.publisher and (await @permissions.publishers.oa meta.publisher).oa
    altoa.issuer.id = meta.publisher
    altoa.meta.creator = ['joe+oapublisher@oa.works']
    altoa.meta.contributors = ['joe+oapublisher@oa.works']
    altoa.provenance = {oa_evidence: 'OA publisher'} # does this mean embargo_months should be zero too?
    altoa.score = await _score altoa
    perms.all_permissions.push altoa

  if haddoi and (openalex ?= await @src.openalex.works(haddoi)) and (openalex?.best_oa_location?.license ? '').includes 'cc' # search works.doi to get remote if not local
    doa =
      can_archive: true
      version: openalex.best_oa_location.version
      versions: if openalex.best_oa_location.version in ['submittedVersion'] then ['submittedVersion'] else if openalex.best_oa_location.version in ['acceptedVersion'] then ['submittedVersion', 'acceptedVersion'] else if openalex.best_oa_location.version then ['submittedVersion', 'acceptedVersion', 'publishedVersion'] else []
      licence: openalex.best_oa_location.license
      locations: ['institutional repository']
      issuer:
        type: 'article'
        has_policy: 'yes'
        id: meta.doi
      meta:
        creator: 'support@unpaywall.org' # correct contact for openalex?
        contributors: ['support@unpaywall.org']
        monitoring: 'Automatic'
        updated: openalex.updated # oadoi.best_oa_location.updated was possibly more accurate but openalex only has the general record updated timestamp
      provenance:
        oa_evidence: 'Openalex' # this used to read from oadoi.best_oa_location.evidence but that is not in openalex
    doa.score = await _score doa
    perms.all_permissions.push doa

  # sort rors by score, and sort alts by score, then combine
  if perms.all_permissions.length
    perms.all_permissions.sort (a, b) => return if (a.score < b.score) then 1 else -1
    # note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for wp in perms.all_permissions
      if not wp.licences?
        wp.licences = []
        wp.licences.push(type: wp.licence) if wp.licence
      delete wp.issuer.journal_oa_type if haddoi and wp.issuer?.journal_oa_type_from and meta.published and Date.parse(meta.published) < Date.parse(wp.issuer.journal_oa_type_from)
      delete wp.issuer.journal_oa_type_from
      wp.issuer.journal_oa_type = await @permissions_new.journals.oa.type((meta.issn ? wp.issuer.id), indoaj, openalex) if (meta.issn or wp.issuer?.type is 'journal') and not wp.issuer.journal_oa_type
      perms.best_permission ?= wp if not wp.provenance?.enforcement_from or not meta.published or Date.parse(meta.published) > Date.parse wp.provenance.enforcement_from.split('/').reverse().join '-'
        
    for ro in (rors.sort (a, b) => return if (a.score < b.score) then 1 else -1)
      delete ro.issuer.journal_oa_type if haddoi and ro.issuer?.journal_oa_type_from and meta.published and Date.parse(meta.published) < Date.parse(ro.issuer.journal_oa_type_from)
      delete ro.issuer.journal_oa_type_from
      ro.issuer.journal_oa_type = await @permissions_new.journals.oa.type((meta.issn ? ro.issuer.id), indoaj, openalex) if (meta.issn or ro.issuer?.type is 'journal') and not ro.issuer.journal_oa_type
      perms.all_permissions.push ro
      pb = perms.best_permission
      if pb? and not pb.author_affiliation_requirement? and (not ro.provenance?.enforcement_from or not meta.published or Date.parse(meta.published) > Date.parse ro.provenance.enforcement_from.split('/').reverse().join '-')
        for key in ['versions', 'locations']
          pb[key].push(vl) for vl in ro[key] when vl not in pb[key]
        pb.version = if 'publishedVersion' in pb.versions then 'publishedVersion' else if 'acceptedVersion' in pb.versions then 'acceptedVersion' else 'submittedVersion'
        pb.embargo_end = ro.embargo_end if pb.embargo_end and ro.embargo_end and Date.parse(ro.embargo_end) < Date.parse pb.embargo_end
        pb.embargo_months = ro.embargo_months if pb.embargo_months and ro.embargo_months? and ro.embargo_months < pb.embargo_months
        pb.can_archive = true if ro.can_archive is true
        pb.requirements ?= {}
        pb.requirements.author_affiliation_requirement = if not meta.ror? then ro.issuer.id else if typeof meta.ror is 'string' then meta.ror else meta.ror[0]
        pb.issuer.affiliation = ro.issuer
        pb.meta ?= {}
        pb.meta.affiliation = ro.meta
        pb.provenance ?= {}
        pb.provenance.affiliation = ro.provenance
        pb.score = parseInt(pb.score) + parseInt(ro.score)
        perms.all_permissions.push pb

  if overall_policy_restriction
    return status: 501, body: if typeof overall_policy_restriction is 'string' and overall_policy_restriction.toLowerCase() is 'not publisher' then 'Please find another DOI for this article as this is provided as this does not allow us to find required information like who published it' else overall_policy_restriction
  else
    perms.metadata = meta if @params.metadata is true
    return perms
P.permissions_new._log = false


'''

P.permissions.journals = _sheet: '1ZTcYJUzhNJYIuxsjKzdVFCbOhJsviVik-8K1DpU7-eE/Main', _prefix: false, _format: (recs=[]) ->
  ready = []
  for rec in (if typeof recs is 'object' and not Array.isArray(recs) then [recs] else recs)
    nr = # a controlled structure for JSON output, can't be guaranteed as not JSON spec, but Joe likes it for visual review
      can_archive: undefined
      version: undefined
      versions: []
      licence: undefined
      locations: undefined
      embargo_months: undefined
      embargo_end: undefined
      deposit_statement: undefined
      copyright_owner: ''
      copyright_name: ''
      copyright_year: ''
      issuer: {}
      meta: {}
      provenance: {}
      requirements: {}

    for k of rec
      rec[k] = rec[k].trim() if typeof rec[k] is 'string'
      if k is 'id'
        nr.issuer.id = if typeof rec.id is 'string' and rec.id.includes(',') then rec.id.split(',') else rec.id
        if typeof nr.issuer.id is 'string' and nr.issuer.id.startsWith('10.') and nr.issuer.id.includes('/') and not nr.issuer.id.includes ' '
          nr.DOI = nr.issuer.id
        else
          cids = []
          for nid in (if typeof nr.issuer.id is 'string' then [nr.issuer.id] else nr.issuer.id)
            nid = nid.trim()
            if nr.issuer.type is 'journal' and nid.includes('-') and not nid.includes ' '
              nid = nid.toUpperCase()
              if af = await @src.openalex.sources 'issn:"' + nid + '"', 1
                for an in af.issn
                  cids.push(an) if an not in cids
            cids.push(nid) if nid not in cids
          nr.issuer.id = cids
      else if k is 'embargo_months'
        kn = if typeof rec[k] is 'number' then rec[k] else if typeof rec[k] is 'string' then parseInt(rec[k].trim()) else undefined
        if kn and typeof kn is 'number'
          nr.embargo_months = kn
          nr.embargo_end = '' # just to allow neat output later - can't be calculated until compared to a particular article
      else if k and rec[k]? and rec[k] not in ['', 'none', 'unclear']
        if k is 'versions' and rec.versions.length
          nr.can_archive = true
          nr.version = if rec.versions.includes('ublish') then 'publishedVersion' else if rec.versions.includes('ccept') then 'acceptedVersion' else 'submittedVersion'
        if k in ['versions', 'locations', 'meta.contributors', 'meta.creator', 'meta.reviewer', 'provenance.archiving_policy', 'requirements.funder', 'journal']
          rec[k] = rec[k].trim().replace(/\, /, ',').replace(/ \,/, ',').split ','
        await @dot nr, (if k is 'license' then 'licence' else k), rec[k]

    nr.copyright_owner = nr.issuer.type if (not nr.copyright_owner or nr.copyright_owner.toLowerCase() is 'journal') and nr.issuer.type
    delete nr.requirements if JSON.stringify(nr.requirements) is '{}'
    ready.push nr

  return if ready.length is 1 then ready[0] else ready

P.permissions.publishers = _sheet: '11rsHmef1j9Q9Xb0WtQ_BklQceaSkkFEIm7tJ4qz0fJk/Main', _prefix: false, _format: P.permissions.journals._format
P.permissions.affiliations = _sheet: '15fa1DADj6y_3aZQcP9-zBalhaThxzZw9dyEbxMBBb5Y/Main', _prefix: false, _format: P.permissions.journals._format
'''


P.permissions_new.journals = example: (issn) ->
  issn ?= @params.doi ? @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  try
    res = await @src.openalex.works 'ids.doi:* AND locations.source.issn:"' + issn.join('" OR locations.source.issn:"') + '"', 1
    return res.doi
  return
P.permissions_new.journals.example._log = false

'''
P.permissions.journals.transformative = _index: true, _prefix: false
P.permissions.journals.transformative.load = () ->
  batch = []
  tfs = await @fetch 'https://api.journalcheckertool.org/journal?q=tj:true&include=issn&size=10000'
  batch.push(rec._source) for rec in tfs.hits.hits
  if batch.length
    await @permissions.journals.transformative ''
    await @permissions.journals.transformative batch
  return batch.length
P.permissions.journals.transformative.load._bg = true
P.permissions.journals.transformative.load._async = true
P.permissions.journals.transformative.load._auth = 'root'

P.permissions.journals.oa = (issn, oadoi) ->
  # NOTE it is still to be decided what licence is acceptable to be counted as OA on the crossref index. For now it's anything CC, including NC
  try issn ?= @params.journals ? @params.journal ? @params.issn ? @params.oa
  ret = {}
  if issn
    ret.articles = await @src.crossref.works.count 'type:"journal-article" AND ISSN:"' + issn + '"'
    ret.open = await @src.crossref.works.count 'type:"journal-article" AND ISSN:"' + issn + '" AND is_oa:true' # could add AND NOT licence:nc
    if ret.articles is ret.open
      ret.oa = true
    if jr = await @src.doaj.journals 'bibjson.pissn:"' + issn + '" OR bibjson.eissn:"' + issn + '"', 1
      ret.open = ret.articles
      ret.doaj = true
      ret.oa = true
    if ex = await @permissions.journals.example issn
      oadoi ?= await @src.oadoi ex, 1
      if oadoi?
        delete ret.oa
        ret.open = ret.articles
        ret.oadoi = true
        ret.oa = oadoi?.best_oa_location?.license and oadoi.best_oa_location.license.includes 'cc' # oadoi.journal_is_oa
      else
        ret.oa = false
  return ret
P.permissions.journals.oa._log = false
'''

P.permissions_new.journals.oa = type: (issns, doajrnl, openalex, crossref) ->
  issns ?= @params.journals ? @params.journal ? @params.type ? @params.issn ? @params.issns ? []
  is_in_doaj = doajrnl?
  if typeof issns is 'string'
    issns = issns.split('doi.org/')[1] if issns.includes 'doi.org/'
    if not openalex? and issns.startsWith '10.' # search works.doi to get remote if not local
      openalex = await @src.openalex.works.doi issns
      crossref = await @src.crossref.works.doi(issns) if not crossref? and not openalex?
      issns = []
  issns = issns.split(',') if typeof issns is 'string'

  js = 'unknown'
  # TODO this may be better if checking openalex.type even if type_crossref exists, such as 10.1056/nejmx220005 where type is erratum, so n/a would be correct. 
  # But to maintain old behaviour, fow now we let it through if any of them are good enough.
  if (openalex?.type_crossref and openalex.type_crossref isnt 'journal-article') or (not openalex?.type_crossref and openalex?.type and openalex.type isnt 'article') or (crossref?.type and crossref.type isnt 'journal-article')
    js = 'not applicable'
  else if (not openalex?.type_crossref or openalex.type_crossref is 'journal-article') and (openalex?.type_crossref is 'journal-article' or crossref?.type is 'journal-article' or (not openalex?.type or openalex.type is 'article')) and (not crossref?.type or crossref.type is 'journal-article')
    if openalex?
      #for oi in openalex.best_oa_location?.source?.issn ? openalex.primary_location?.source?.issn ? []
      #  issns.push(oi) if oi and oi not in issns
      # openalex has issn_l as well, but is included in issn which is a list
      # openalex can lack ISSN for records that do have them, if it only shows a record for example in pubmed when it is also in a journal with an ISSN. This can sometimes be seen by it also having APC data from doaj. See 10.11606/s1518-8787.2023057004376
      # relying on apc provenance is definitively NOT an indicator of being in DOAJ, as openalex has articles with apc data from DOAJ but showing locations as not in DOAJ, e.g 10.1016/j.ijpara.2022.07.006 (and manual ISSN search on doaj.org confirms it is not in DOAJ)
      # APC data is NOT reliable indicator of doaj or gold/diamond, plenty openalex articles have that but are closed etc e.g see https://bg.beta.oa.works/src/openalex/works/terms/open_access.oa_status.keyword?q=apc_paid.value:0%20AND%20apc_paid.provenance:doaj
      # openalex indicates works as hybrid even when it knows they are in DOAJ - likely because another location it lists has an apc or similar, but the DOAJ one does not
      # see https://bg.beta.oa.works/src/openalex/works?q=open_access.oa_status:hybrid%20AND%20locations.source.is_in_doaj:true
      for ll in openalex.locations ? [] # it IS possible for openalex to have a DOAJ location but not list that as primary or best oa location (cos it prefers pubmed for both those, for example)
        is_in_doaj = true if ll.source?.is_in_doaj # rely on presence of apc_paid provenance too?
        issns.push(oi) for oi in (ll.source?.issn ? []) when oi and oi not in issns
      js = if openalex.open_access?.oa_status is 'hybrid' and not is_in_doaj then 'hybrid' else if is_in_doaj or openalex.open_access?.oa_status is 'gold' then 'gold' else 'closed'
    if js is 'unknown' and not issns and not is_in_doaj and (crossref? or (openalex?.ids?.doi and crossref = await @src.crossref.works openalex.ids.doi.split('doi.org/').pop()))
      issns = crossref.ISSN if crossref.ISSN
    if issns or doajrnl?
      doajrnl ?= await @src.doaj.journals 'bibjson.eissn.keyword:"' + issns.join('" OR bibjson.eissn.keyword:"') + '" OR bibjson.pissn.keyword:"' + issns.join('" OR bibjson.pissn.keyword:"') + '"', 1
      if doajrnl?
        js = if doajrnl.bibjson?.apc?.has_apc is false then 'diamond' else 'gold'
      else if issns
        if await @permissions.journals.transformative.count 'issn:"' + issns.join('" OR issn:"') + '"'
          js = 'transformative'
        else if js is 'closed'
          if await @src.openalex.hybrid issns
            js = 'hybrid'
          else if openalex?.open_access?.oa_status not in ['closed', 'bronze', 'green']
            calc = await @src.openalex.oa.type issns
            js = calc.calculated if calc.calculated and calc.calculated not in ['closed', 'bronze', 'green']

  return js
P.permissions_new.journals.oa.type._log = false


'''
P.permissions.publishers.oa = (publisher) ->
  ret = publisher: (publisher ? @params.publisher ? @params.oa).replace /&/g, ''
  if not await @src.crossref.journals 'publisher:"' + ret.publisher + '"', 1
    if fz = await @src.crossref.journals 'publisher:"' + ret.publisher.split(' ').join('" AND publisher:"') + '"', 1
      if fz.publisher.toLowerCase() isnt ret.publisher.toLowerCase()
        lvs = await @levenshtein fz.publisher, ret.publisher
        ret.publisher = fz.publisher if lvs.distance < 5 or (if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b)/lvs.distance > 10
    else
      ret.journals = 0
  ret.journals ?= await @src.crossref.journals.count 'publisher:"' + ret.publisher + '" AND NOT discontinued:true'
  ret.open = await @src.doaj.journals.count 'publisher:"' + ret.publisher + '" AND NOT bibjson.discontinued_date:* AND NOT bibjson.is_replaced_by:*'
  ret.percent = if ret.journals then Math.ceil((ret.open / ret.journals) * 100) else if ret.open then 100 else 0
  ret.oa = (not ret.journals and ret.open) or (ret.journals and ret.journals is ret.open)
  return ret
P.permissions.publishers.oa._log = false
'''
