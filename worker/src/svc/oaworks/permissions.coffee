

P.svc.oaworks.permissions = (meta, ror, getmeta, oadoi, crossref) -> # oadoi and crossref are just ways for other functions to pass in oadoi or crossref record objects to save looking them up again
  overall_policy_restriction = false
  haddoi = false
  
  _format = (rec) ->
    if haddoi and rec.embargo_months and (meta.published or meta.year)
      em = new Date Date.parse meta.published ? meta.year + '-01-01'
      em = new Date em.setMonth em.getMonth() + rec.embargo_months
      rec.embargo_end = em.toISOString().split('T')[0]
    delete rec.embargo_end if rec.embargo_end is ''
    rec.copyright_name = if rec.copyright_owner is 'publisher' then (if typeof rec.issuer.parent_policy is 'string' then rec.issuer.parent_policy else if typeof rec.issuer.id is 'string' then rec.issuer.id else rec.issuer.id[0]) else if rec.copyright_owner in ['journal','affiliation'] then (meta.journal ? '') else if (haddoi and rec.copyright_owner and rec.copyright_owner.toLowerCase().includes('author')) and meta.author? and meta.author.length and (meta.author[0].name or meta.author[0].family) then (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '') else ''
    if rec.copyright_name in ['publisher','journal'] and (crossref or meta.doi or rec.provenance?.example)
      crossref ?= await @src.crossref.works meta.doi ? rec.provenance.example
      for a in (crossref?.assertion ? [])
        if a.name.toLowerCase() is 'copyright'
          try rec.copyright_name = a.value
          try rec.copyright_name = a.value.replace('\u00a9 ','').replace(/[0-9]/g,'').trim()
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
      rec.meta.source = 'https://' + (if S.dev then 'dev.api.cottagelabs.com/svc/oaworks/permissions/' else 'api.openaccessbutton.org/permissions/') + (if rec.issuer.type then rec.issuer.type + '/' else '') + rec._id
    if typeof rec.issuer?.has_policy is 'string' and rec.issuer.has_policy.toLowerCase().trim() in ['not publisher','takedown']
      # find out if this should be enacted if it is the case for any permission, or only the best permission
      overall_policy_restriction = rec.issuer.has_policy
    delete rec[d] for d in ['_id','permission_required','createdAt','updatedAt','created_date','updated_date']
    try delete rec.issuer.updatedAt
    return rec

  _score = (rec) =>
    score = if rec.can_archive then 1000 else 0
    score += 1000 if rec.provenance?.oa_evidence is 'In DOAJ'
    if rec.requirements?
      # TODO what about cases where the requirement is met?
      # and HOW is requirement met? we search ROR against issuer, but how does that match with author affiliation?
      # should we even be searching for permissions by ROR, or only using it to calculate the ones we find by some other means?
      # and if it is not met then is can_archive worth anything?
      score -= 10
    else
      score += if rec.version is 'publishedVersion' then 200 else if rec.version is 'acceptedVersion' then 100 else 0
    score -= 5 if rec.licences? and rec.licences.length
    score += if rec.issuer?.type is 'journal' then 5 else if rec.issuer?.type is 'publisher' then 4 else if rec.issuer?.type is 'university' then 3 else if rec.issuer?.type in 'article' then 2 else 0
    score -= 25 if rec.embargo_months and rec.embargo_months >= 36 and (not rec.embargo_end or Date.parse(rec.embargo_end) < Date.now())
    return score

  if typeof meta is 'string'
    meta = if meta.startsWith('10.') then {doi: meta} else {issn: meta}

  meta ?= @copy @params
  delete meta.metadata if meta?.metadata is true # just a pass-through for us to show metadata for debug
  if meta?.permissions?
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
  issns = if Array.isArray(meta.issn) then meta.issn else [] # only if directly passed a list of ISSNs for the same article, accept them as the ISSNs list to use
  meta.issn = meta.issn.split(',') if typeof meta.issn is 'string' and meta.issn.includes ','

  if JSON.stringify(meta) is '{}' or (meta.issn and not JSON.stringify(meta.issn).includes('-')) or (meta.doi and (typeof meta.doi isnt 'string' or not meta.doi.startsWith('10.') or not meta.doi.includes '/'))
    return body: 'No valid DOI, ISSN, or ROR provided', status: 404
    
  # NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  # we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = () =>
    psm = @copy meta
    if JSON.stringify(psm) isnt '{}'
      for mk of rsm = (crossref ? (await @svc.oaworks.metadata(meta.doi)) ? {})
        meta[mk] ?= rsm[mk]
  await _getmeta() if getmeta isnt false and meta.doi and (not meta.publisher or not meta.issn)
  meta.published = meta.year + '-01-01' if not meta.published and meta.year
  haddoi = meta.doi?
  if meta.issn
    meta.issn = [meta.issn] if typeof meta.issn is 'string'
    if not issns.length # they're already meta.issn in this case anyway
      for inisn in meta.issn
        issns.push(inisn) if inisn not in issns # check just in case
    try
      meta.doi ?= await @src.crossref.journals.doi issns
    if not haddoi and meta.doi
      await _getmeta()
  if haddoi and meta.type not in ['journal-article']
    return
      body: 'DOI is not a journal article'
      status: 501

  if meta.publisher and meta.publisher.includes('(') and meta.publisher.lastIndexOf(')') > (meta.publisher.length*.7)
    # could be a publisher name with the acronym at the end, like Public Library of Science (PLoS)
    # so get rid of the acronym because that is not included in the publisher name in crossref and other sources
    meta.publisher = meta.publisher.substring(0, meta.publisher.lastIndexOf('(')).trim()

  try
    meta.citation = '['
    meta.citation += meta.title + '. ' if meta.title
    meta.citation += meta.journal + ' ' if meta.journal
    meta.citation += meta.volume + (if meta.issue then ', ' else ' ') if meta.volume
    meta.citation += meta.issue + ' ' if meta.issue
    meta.citation += 'p' + (meta.page ? meta.pages) if meta.page? or meta.pages?
    if meta.year or meta.published
      meta.citation += ' (' + (meta.year ? meta.published).split('-')[0] + ')'
    meta.citation = meta.citation.trim()
    meta.citation += ']'

  perms = best_permission: undefined, all_permissions: []
  rors = []
  if meta.ror?
    meta.ror = [meta.ror] if typeof meta.ror is 'string'
    rs = await @svc.oaworks.permissions.affiliations 'issuer.id:"' + meta.ror.join('" OR issuer.id:"') + '"'
    if not rs?.hits?.total
      try # look up the ROR, get the ISO 3166-1 alpha-2 code, search affiliations for that
        rw = await @src.ror(if meta.ror.length is 1 then meta.ror[0] else 'id:"' + meta.ror.join(" OR id:") + '"')
        rw = rw.hits.hits[0]._source if rw.hits?.total
        if rw.country.country_code
          rs = await @svc.oaworks.permissions.affiliations 'issuer.id:"' + rw.country.country_code + '"'
    for rr in rs?.hits?.hits ? []
      tr = await _format rr._source
      tr.score = await _score tr
      rors.push tr

  if issns.length
    qr = if issns.length then 'issuer.id:"' + issns.join('" OR issuer.id:"') + '"' else ''
    ps = await @svc.oaworks.permissions.journals qr
    for p in ps?.hits?.hits ? []
      rp = await _format p._source
      rp.score = await _score rp
      perms.all_permissions.push rp

  if issns.length
    af = await @svc.oaworks.journal 'ISSN:"' + issns.join('" OR ISSN:"') + '"', 1

  if meta.publisher
    qr = 'issuer.id:"' + meta.publisher + '"' # how exact/fuzzy can this be
    ps = await @svc.oaworks.permissions.publishers qr
    for p in ps?.hits?.hits ? []
      rp = await _format p._source
      rp.score = await _score rp
      perms.all_permissions.push rp

    if not af?
      af = await @svc.oaworks.journal 'publisher:"' + meta.publisher + '"', 1
      if not af?
        fz = await @svc.oaworks.journal 'publisher:"' + meta.publisher.split(' ').join('" AND publisher:"') + '"', 1
        if fz?.publisher is meta.publisher
          af = fz
        else if fz?.publisher
          lvs = await @tdm.levenshtein fz.publisher, meta.publisher
          longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
          af = fz if lvs.distance < 5 or longest/lvs.distance > 10

  if af?.publisher and not af.indoaj
    pisoa = (await @svc.oaworks.permissions.publishers.oa af.publisher).oa

  if af?.indoaj or pisoa
    altoa =
      can_archive: true
      version: 'publishedVersion'
      versions: ['publishedVersion']
      licence: undefined
      licence_terms: ""
      licences: []
      locations: ['institutional repository']
      embargo_months: undefined
      issuer:
        type: 'journal'
        has_policy: 'yes'
        id: af.issn
      meta:
        creator: ['joe+doaj@openaccessbutton.org']
        contributors: ['joe+doaj@openaccessbutton.org']
        monitoring: 'Automatic'

    try altoa.licence = af.doaj.bibjson.license[0].type ? af.license[0].type # could have doaj licence info
    if af.indoaj
      altoa.embargo_months = 0
      altoa.provenance = {oa_evidence: 'In DOAJ'}
    else if pisoa
      altoa.meta.creator = ['joe+oapublisher@openaccessbutton.org']
      altoa.meta.contributors = ['joe+oapublisher@openaccessbutton.org']
      altoa.provenance = {oa_evidence: 'OA publisher'} # does this mean embargo_months should be zero too?
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
    if altoa.licence
      altoa.licences = [{type: altoa.licence, terms: ""}]
    altoa.score = await _score altoa
    perms.all_permissions.push altoa

  if meta.doi
    oadoi ?= await @src.oadoi meta.doi
    if haddoi and oadoi?.best_oa_location?.license and oadoi.best_oa_location.license.includes 'cc' #  (haddoi or oadoi?.journal_is_oa)
      doa =
        can_archive: true
        version: oadoi.best_oa_location.version
        versions: []
        licence: oadoi.best_oa_location.license
        licence_terms: ""
        licences: []
        locations: ['institutional repository']
        issuer:
          type: 'article'
          has_policy: 'yes'
          id: meta.doi
        meta:
          creator: ['support@unpaywall.org']
          contributors: ['support@unpaywall.org']
          monitoring: 'Automatic'
          updated: oadoi.best_oa_location.updated
        provenance:
          oa_evidence: oadoi.best_oa_location.evidence

      if typeof doa.licence is 'string'
        doa.licences = [{type: doa.licence, terms: ""}]
      if doa.version
        doa.versions = if doa.version in ['submittedVersion','preprint'] then ['submittedVersion'] else if doa.version in ['acceptedVersion','postprint'] then ['submittedVersion', 'acceptedVersion'] else  ['submittedVersion', 'acceptedVersion', 'publishedVersion']
      doa.score = await _score doa
      perms.all_permissions.push doa

  # sort rors by score, and sort alts by score, then combine
  if perms.all_permissions.length
    perms.all_permissions.sort (a, b) => return if (a.score < b.score) then 1 else -1
    # note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for wp in perms.all_permissions
      if wp.issuer?.type is 'journal' and not wp.issuer.journal_oa_type
        wp.issuer.journal_oa_type = await @svc.oaworks.permissions.journals.oa.type (issns ? wp.issuer.id), af, oadoi, crossref
      if not wp.provenance?.enforcement_from
        perms.best_permission = @copy wp
        break
      else if not meta.published or Date.parse(meta.published) > Date.parse wp.provenance.enforcement_from.split('/').reverse().join '-'
        # NOTE Date.parse would try to work on format 31/01/2020 but reads it in American, so would think 31 is a month and is too big
        # but 2020-01-31 is treated in ISO so the 31 will be the day. So, given that we use DD/MM/YYYY, split on / then reverse then join on - to get a better parse
        perms.best_permission = @copy wp
        break
    if rors.length # this only happens as an augment to some other permission, so far
      rors.sort (a, b) => return if (a.score < b.score) then 1 else -1
      for ro in rors # check this gives the order in the direction we want, else reverse it
        if ro.issuer?.type is 'journal' and not ro.issuer.journal_oa_type
          ro.issuer.journal_oa_type = await @svc.oaworks.permissions.journals.oa.type (issns ? ro.issuer.id), af, oadoi, crossref
        perms.all_permissions.push ro
        if not perms.best_permission?.author_affiliation_requirement?
          if perms.best_permission?
            if not ro.provenance?.enforcement_from or not meta.published or Date.parse(meta.published) > Date.parse ro.provenance.enforcement_from.split('/').reverse().join '-'
              pb = @copy perms.best_permission
              for key in ['licences', 'versions', 'locations']
                for vl in ro[key]
                  pb[key] ?= []
                  pb[key].push(vl) if vl not in pb[key]
              for l in pb.licences ? []
                pb.licence = l.type if not pb.licence? or l.type.length < pb.licence.length
              pb.version = if 'publishedVersion' in pb.versions or 'publisher pdf' in pb.versions then 'publishedVersion' else if 'acceptedVersion' in pb.versions or 'postprint' in pb.versions then 'acceptedVersion' else 'submittedVersion'
              if pb.embargo_end
                if ro.embargo_end
                  if Date.parse(ro.embargo_end) < Date.parse pb.embargo_end
                    pb.embargo_end = ro.embargo_end
              if pb.embargo_months and ro.embargo_months? and ro.embargo_months < pb.embargo_months
                pb.embargo_months = ro.embargo_months
              pb.can_archive = true if ro.can_archive is true
              pb.requirements ?= {}
              pb.requirements.author_affiliation_requirement = if not meta.ror? then ro.issuer.id else if typeof meta.ror is 'string' then meta.ror else meta.ror[0]
              pb.issuer.affiliation = ro.issuer
              pb.meta ?= {}
              pb.meta.affiliation = ro.meta
              pb.provenance ?= {}
              pb.provenance.affiliation = ro.provenance
              pb.score = parseInt(pb.score) + parseInt(ro.score)
              perms.best_permission = pb
              perms.all_permissions.push pb

  if overall_policy_restriction
    msgs = 
      'not publisher': 'Please find another DOI for this article as this is provided as this doesn’t allow us to find required information like who published it'
    return
      body: if typeof overall_policy_restriction isnt 'string' then overall_policy_restriction else msgs[overall_policy_restriction.toLowerCase()] ? overall_policy_restriction
      status: 501
  else
    perms.metadata = meta if @params.metadata is true or getmeta is true
    return perms



# the original sheet, now split into three separate ones, but keep a note in case of use for testing: 
# https://docs.google.com/spreadsheets/d/1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A/edit
P.svc.oaworks.permissions.journals = (recs) -> return @svc.oaworks.permissions._format recs
P.svc.oaworks.permissions.journals._sheet = '19pDvOY5pge-C0yDSObnkMqqlMJgct3iIjPI2rMPLQEc/Export'
P.svc.oaworks.permissions.journals._prefix = false

P.svc.oaworks.permissions.publishers = (recs) -> return @svc.oaworks.permissions._format recs
P.svc.oaworks.permissions.publishers._sheet = '1tmEfeJ6RCTCQjcCht-FI7FH-04z7MPSKdUnm0UpAxWM/Export'
P.svc.oaworks.permissions.publishers._prefix = false

P.svc.oaworks.permissions.affiliations = (recs) -> return @svc.oaworks.permissions._format recs
P.svc.oaworks.permissions.affiliations._sheet = '1J4WhZjPsAjpoogsj7wSTQGJPguo7TiSe0uNcrvyd_OM/Export'
P.svc.oaworks.permissions.affiliations._prefix = false



P.svc.oaworks.permissions.journals.oa = (issn, oadoi) ->
  # NOTE it is still to be decided what licence is acceptable to be counted as OA on the crossref index. For now it's anything CC, including NC
  try issn ?= @params.journal ? @params.issn ? @params.oa
  ret = {}
  if issn
    ret.articles = await @src.crossref.works.count 'type:"journal-article" AND ISSN:"' + issn + '"'
    ret.open = await @src.crossref.works.count 'type:"journal-article" AND ISSN:"' + issn + '" AND is_oa:true' # could add AND NOT licence:nc
    if ret.articles is ret.open
      ret.oa = true
    if jr = await @svc.oaworks.journal 'ISSN:"' + issn + '" AND indoaj:true', 1
      ret.open = ret.articles
      ret.doaj = true
      ret.oa = true
    if ex = await @src.crossref.journals.doi issn
      oadoi ?= await @src.oadoi ex, 1
      if oadoi?
        delete ret.oa
        ret.open = ret.articles
        ret.oadoi = true
        ret.oa = oadoi?.best_oa_location?.license and oadoi.best_oa_location.license.includes 'cc' # oadoi.journal_is_oa
      else
        ret.oa = false
  return ret

P.svc.oaworks.permissions.journals.oa.type = (issns, jrnl, oadoi, crossref) ->
  if typeof issns is 'string' and issns.startsWith '10.'
    oadoi ?= await @src.oadoi issns
    crossref ?= await @src.crossref.works issns
    issns = undefined
  issns ?= oadoi?.journal_issns ? crossref?.ISSN ? @params.journals ? @params.status ? @params.issn ? @params.issns
  issns = issns.split(',') if typeof issns is 'string'

  js = 'unknown'
  if crossref?.type? and crossref.type isnt 'journal-article'
    js = 'not applicable'
  else if not crossref?.type or crossref.type is 'journal-article'
    js = if oadoi?.oa_status is 'gold' then 'gold' else if oadoi?.oa_status is 'bronze' then 'closed' else if oadoi?.oa_status is 'hybrid' then 'hybrid' else 'closed'
    js = 'gold' if oadoi?.journal_is_oa or oadoi?.journal_is_in_doaj # double check for gold
    if issns
      # check if it really is closed because sometimes OADOI says it is for one particular DOI but really it isn't
      js = 'hybrid' if js is 'closed' and await @src.oadoi.hybrid issns
      # check if it is a known transformative or diamond journal
      jrnl ?= await @svc.oaworks.journal 'ISSN:"' + issns.join('" OR ISSN:"') + '"', 1
      if jrnl?.tj
        js = 'transformative'
      else if jrnl?.doaj?.bibjson?.apc?.has_apc is false
        js = 'diamond'
  return js

P.svc.oaworks.permissions.publishers.oa = (publisher) ->
  try publisher ?= @params.publisher ? @params.oa
  q = 'publisher:"' + publisher.replace(/&/g, '') + '" AND NOT doaj.bibjson.discontinued_date:* AND NOT doaj.bibjson.is_replaced_by:* AND ('
  dt = parseInt (await @date()).split('-')[0]
  c = dt - 2 # how many years back to check for continuance
  while dt > c
    q += (if q.endsWith('(') then '' else ' OR ') + 'years:' + dt
    dt -= 1
  q += ')'
  ret = 
    journals: await @svc.oaworks.journal.count q
    open: await @svc.oaworks.journal.count q + ' AND indoaj:true'
  ret.percent = Math.ceil (ret.open / ret.journals) * 100
  ret.oa = ret.journals and ret.journals is ret.open
  return ret



P.svc.oaworks.permissions._format = (recs=[]) ->
  recs = [recs] if typeof recs is 'object' and not Array.isArray recs

  keys = 
    versionsarchivable: 'versions'
    permissionsrequestcontactemail: 'permissions_contact'
    archivinglocationsallowed: 'locations'
    license: 'licence'
    licencesallowed: 'licences'
    postprintembargo: 'embargo_months'
    depositstatementrequired: 'deposit_statement'
    copyrightowner: 'copyright_owner' # can be journal, publisher, affiliation or author
    publicnotes: 'notes'
    authoraffiliationrolerequirement: 'requirements.role'
    authoraffiliationrequirement: 'requirements.affiliation'
    authoraffiliationdepartmentrequirement: 'requirements.departmental_affiliation'
    iffundedby: 'requirements.funder'
    fundingproportionrequired: 'requirements.funding_proportion'
    subjectcoverage: 'requirements.subject'
    haspolicy: 'issuer.has_policy'
    permissiontype: 'issuer.type'
    parentpolicy: 'issuer.parent_policy'
    contributedby: 'meta.contributors'
    recordlastupdated: 'meta.updated'
    reviewers: 'meta.reviewer'
    addedby: 'meta.creator'
    monitoringtype: 'meta.monitoring'
    policyfulltext: 'provenance.archiving_policy'
    policylandingpage: 'provenance.archiving_policy_splash'
    publishingagreement: 'provenance.sample_publishing_agreement'
    publishingagreementsplash: 'provenance.sample_publishing_splash'
    rights: 'provenance.author_rights'
    embargolist: 'provenance.embargo_list'
    policyfaq: 'provenance.faq'
    miscsource: 'provenance.misc_source'
    enforcementdate: 'provenance.enforcement_from'
    example: 'provenance.example'

  ready = []
  for rec in recs
    nr = 
      can_archive: false
      version: undefined
      versions: undefined
      licence: undefined
      licence_terms: undefined
      licences: undefined
      locations: undefined
      embargo_months: undefined
      embargo_end: undefined
      deposit_statement: undefined
      permission_required: undefined
      permissions_contact: undefined
      copyright_owner: undefined
      copyright_name: undefined
      copyright_year: undefined
      notes: undefined
      requirements: undefined
      issuer: {}
      meta: {}
      provenance: undefined

    try
      rec.recordlastupdated = rec.recordlastupdated.trim()
      if rec.recordlastupdated.includes ','
        nd = false
        for dt in rec.recordlastupdated.split ','
          nd = dt.trim() if nd is false or Date.parse(dt.trim().split('/').reverse().join('-')) > Date.parse nd.split('/').reverse().join '-'
        rec.recordlastupdated = nd if nd isnt false
      nr.meta.updated = rec.recordlastupdated
    nr.meta.updatedAt = Date.parse(nr.meta.updated.split('/').reverse().join('-')) if nr.meta.updated?

    # the google feed import will lowercase these key names and remove whitespace, question marks, brackets too, but not dashes
    nr.issuer.id = if typeof rec.id is 'string' and rec.id.includes(',') then rec.id.split(',') else rec.id
    if nr.issuer.id?
      if typeof nr.issuer.id isnt 'string'
        cids = []
        for nid in nr.issuer.id
          nid = nid.trim()
          if nr.issuer.type is 'journal' and nid.includes('-') and not nid.includes ' '
            nid = nid.toUpperCase()
            if af = await @svc.oaworks.journal 'ISSN:"' + nid + '"', 1
              for an in af.issn
                cids.push(an) if an not in cids
          cids.push(nid) if nid not in cids
        nr.issuer.id = cids
      else if nr.issuer.id.startsWith('10.') and nr.issuer.id.includes('/') and not nr.issuer.id.includes ' '
        nr.DOI = nr.issuer.id
    nr.permission_required = typeof rec.haspolicy is 'string' and rec.haspolicy.toLowerCase().includes 'permission required'

    for k of rec
      if keys[k] and rec[k]? and rec[k].length isnt 0
        nk = keys[k]
        nv = undefined
        if k is 'postprintembargo' # Post-Print Embargo - empty or number of months like 0, 12, 24
          kn = parseInt rec[k].trim()
          nv = kn if kn and typeof kn is 'number'
          nr.embargo_end = '' if nv? # just to allow neat output later - can't be calculated until compared to a particular article
        else if k in ['journal', 'versionsarchivable', 'archivinglocationsallowed', 'licencesallowed', 'policyfulltext', 'contributedby', 'addedby', 'reviewers', 'iffundedby']
          nv = []
          for s in rcs = rec[k].trim().split ','
            st = s.trim()
            if k is 'licencesallowed'
              if st.toLowerCase() isnt 'unclear'
                lc = type: st.toLowerCase()
                try lc.terms = rec.licenceterms.split(',')[rcs.indexOf(s)].trim() # these don't seem to exist any more...
                nv.push lc
            else
              if k is 'versionsarchivable'
                st = st.toLowerCase()
                st = 'submittedVersion' if st is 'preprint'
                st = 'acceptedVersion' if st is 'postprint'
                st = 'publishedVersion' if st is 'publisher pdf'
              nv.push(if k in ['archivinglocationsallowed'] then st.toLowerCase() else st) if st.length and st not in nv
        else if k not in ['recordlastupdated']
          nv = rec[k].trim()
        nv = nv.toLowerCase() if typeof nv is 'string' and (nv.toLowerCase() in ['yes','no'] or k in ['haspolicy','permissiontype','copyrightowner'])
        nv = '' if k in ['copyrightowner','license'] and nv is 'unclear'
        if nv?
          if nk.includes '.'
            nps = nk.split '.'
            nr[nps[0]] ?= {}
            nr[nps[0]][[nps[1]]] = nv
          else
            nr[nk] = nv

    nr.licences ?= []
    if not nr.licence
      for l in nr.licences
        if not nr.licence? or l.type.length < nr.licence.length
          nr.licence = l.type
          nr.licence_terms = l.terms
    nr.versions ?= []
    if nr.versions.length
      nr.can_archive = true
      nr.version = if 'acceptedVersion' in nr.versions or 'postprint' in nr.versions then 'acceptedVersion' else if 'publishedVersion' in nr.versions or 'publisher pdf' in nr.versions then 'publishedVersion' else 'submittedVersion'
    nr.copyright_owner ?= nr.issuer?.type ? ''
    nr.copyright_name ?= ''
    nr.copyright_year ?= '' # the year of publication, to be added at result stage
    ready.push(nr) if not JSON.stringify(nr) isnt '{}'

  return if ready.length is 1 then ready[0] else ready



'''P.svc.oaworks.journal = (q) ->
  try
    if not q? and @params.journal or @params.issn
      q = 'ISSN:"' + (@params.journal ? @params.issn) + '"'
  console.log 'running journal remote lookup', q
  try
    res = await @fetch 'https://api.jct.cottagelabs.com/journal?q=' + q
    return res.hits.hits[0]._source
  catch
    return'''

P.svc.oaworks.journal = _index: true, _prefix: false
#P.svc.oaworks.journal._prefix = false

P.svc.oaworks.journal.load = () ->
  counter = 0
  total = false
  batchsize = 20000 # how many records to batch upload at a time
  batch = [] # batch of json records to upload
  from = 0
  size = 5000

  await @svc.oaworks.journal ''
  while total is false or counter < total
    # this is a fallback to JCT until a local custom process for journal indexing is added
    res = await @fetch 'https://api.jct.cottagelabs.com/journal?q=*&from=' + from + '&size=' + size
    total = res.hits.total if total is false
    for r in res.hits.hits
      counter += 1
      if r._source.issn
        r._source.ISSN ?= []
        for li in (if typeof r._source.issn is 'string' then [r._source.issn] else r._source.issn)
          r._source.ISSN.push(li) if li not in r._source.ISSN
      batch.push r._source
      if batch.length >= batchsize
        await @svc.oaworks.journal batch
        batch = []
    from += size

  await @svc.oaworks.journal(batch) if batch.length
  return counter

P.svc.oaworks.journal.load._bg = true
P.svc.oaworks.journal.load._async = true
P.svc.oaworks.journal.load._auth = 'root'