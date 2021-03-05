

P.svc.oaworks.permissions = (meta, roruid, getmeta) ->
  overall_policy_restriction = false
  cr = false
  haddoi = false
  
  meta ?= @copy @params
  if meta?.permissions?
    if meta.permissions.startsWith 'journal/'
      meta.issn = meta.permissions.replace 'journal/', ''
    else if meta.permissions.startsWith 'affiliation/'
      meta.ror = meta.permissions.replace 'affiliation/', ''
    else if meta.permissions.startsWith 'publisher/'
      meta.publisher = meta.permissions.replace 'publisher/', ''
    else if meta.permissions.indexOf('10.') is 0 and meta.permissions.indexOf('/') isnt -1
      meta.doi = meta.permissions
    else if meta.permissions.indexOf('-') isnt 0 and meta.permissions.length < 10 and meta.permissions.length > 6
      meta.issn = meta.permissions
    else
      meta.publisher = meta.permissions # but could be a ROR?
    delete meta.permissions
  
  _prep = (rec) ->
    if haddoi and rec.embargo_months and (meta.published or meta.year)
      em = moment meta.published ? meta.year + '-01-01'
      em = em.add rec.embargo_months, 'months'
      rec.embargo_end = em.format "YYYY-MM-DD"
    delete rec.embargo_end if rec.embargo_end is ''
    rec.copyright_name = if rec.copyright_owner is 'publisher' then (if typeof rec.issuer.parent_policy is 'string' then rec.issuer.parent_policy else if typeof rec.issuer.id is 'string' then rec.issuer.id else rec.issuer.id[0]) else if rec.copyright_owner in ['journal','affiliation'] then (meta.journal ? '') else if (rec.copyright_owner and rec.copyright_owner.toLowerCase().indexOf('author') isnt -1) and meta.author? and meta.author.length and (meta.author[0].name or meta.author[0].family) then (meta.author[0].name ? meta.author[0].family) + (if meta.author.length > 1 then ' et al' else '') else ''
    if rec.copyright_name in ['publisher','journal'] and (cr or meta.doi or rec.provenance?.example)
      if cr is false
        cr = await @src.crossref.works meta.doi ? rec.provenance.example
      if cr?.assertion? and cr.assertion.length
        for a in cr.assertion
          if a.name.toLowerCase() is 'copyright'
            try rec.copyright_name = a.value
            try rec.copyright_name = a.value.replace('\u00a9 ','').replace(/[0-9]/g,'').trim()
    rec.copyright_year = meta.year if haddoi and rec.copyright_year is '' and meta.year
    delete rec.copyright_year if rec.copyright_year is ''
    if haddoi and rec.deposit_statement? and rec.deposit_statement.indexOf('<<') isnt -1
      fst = ''
      for pt in rec.deposit_statement.split '<<'
        if fst is '' and pt.indexOf('>>') is -1
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
    score -= 25 if rec.embargo_months and rec.embargo_months >= 36 and (not rec.embargo_end or moment(rec.embargo_end,"YYYY-MM-DD").isBefore(moment()))
    return score


  inp = {}
  if typeof meta is 'string'
    meta = if meta.indexOf('10.') is 0 then {doi: meta} else {issn: meta}
  delete meta.meta if meta.meta? # just used to pass in a false to getmeta
  if meta.metadata? # if passed a catalogue object
    inp = meta
    meta = meta.metadata
    
  if meta.affiliation
    meta.ror = meta.affiliation
    delete meta.affiliation
  if meta.journal and meta.journal.indexOf(' ') is -1
    meta.issn = meta.journal
    delete meta.journal
  if meta.publisher and meta.publisher.indexOf(' ') is -1 and meta.publisher.indexOf(',') is -1 and not oab_permissions.find 'issuer.type.exact:"publisher" AND issuer.id:"' + meta.publisher + '"'
    # it is possible this may actually be a ror, so switch to ror just in case - if it still matches nothing, no loss
    meta.ror = meta.publisher
    delete meta.publisher

  issns = if Array.isArray(meta.issn) then meta.issn else [] # only if directly passed a list of ISSNs for the same article, accept them as the ISSNs list to use
  meta.issn = meta.issn.split(',') if typeof meta.issn is 'string' and meta.issn.indexOf(',') isnt -1
  meta.ror = meta.ror.split(',') if typeof meta.ror is 'string' and meta.ror.indexOf(',') isnt -1
  
  if not meta.ror
    uc = if typeof roruid is 'object' then roruid else if typeof roruid is 'string' then @svc.oaworks.deposit.config(roruid) else undefined
    if (typeof uc is 'object' and uc.ror?) or typeof roruid is 'string'
      meta.ror = uc?.ror ? roruid

  if JSON.stringify(meta) is '{}' or (meta.issn and JSON.stringify(meta.issn).indexOf('-') is -1) or (meta.doi and (typeof meta.doi isnt 'string' or meta.doi.indexOf('10.') isnt 0 or meta.doi.indexOf('/') is -1))
    return body: 'No valid DOI, ISSN, or ROR provided', statusCode: 404
    
  # NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  # we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = () =>
    psm = @copy meta
    delete psm.ror
    if JSON.stringify(psm) isnt '{}'
      rsm = @svc.oaworks.metadata {metadata: ['crossref_type','issn','publisher','published','year','author','ror']}, psm
      for mk of rsm
        meta[mk] ?= rsm[mk]
  await _getmeta() if getmeta isnt false and meta.doi and (not meta.publisher or not meta.issn)
  meta.published = meta.year + '-01-01' if not meta.published and meta.year
  haddoi = meta.doi?
  af = false
  if meta.issn
    meta.issn = [meta.issn] if typeof meta.issn is 'string'
    if not issns.length # they're already meta.issn in this case anyway
      for inisn in meta.issn
        issns.push(inisn) if inisn not in issns # check just in case
    if not issns.length or not meta.publisher or not meta.doi
      if af = academic_journal.find 'issn.exact:"' + issns.join('" OR issn.exact:"') + '"'
        meta.publisher ?= af.publisher
        for an in (if typeof af.issn is 'string' then [af.issn] else af.issn)
          issns.push(an) if an not in issns # check again
        meta.doi ?= af.doi
    try
      meta.doi ?= await @src.crossref.journals.doi issns
    catch # temporary until wider crossref update completed
      meta.doi ?= await @src.crossref.journals.dois.example issns
    await _getmeta() if not haddoi and meta.doi
  if haddoi and meta.crossref_type not in ['journal-article']
    return
      body: 'DOI is not a journal article'
      status: 501

  if meta.publisher and meta.publisher.indexOf('(') isnt -1 and meta.publisher.lastIndexOf(')') > (meta.publisher.length*.7)
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
    rs = oab_permissions.search 'issuer.id.exact:"' + meta.ror.join('" OR issuer.id.exact:"') + '"'
    if not rs?.hits?.total
      # look up the ROR in wikidata - if found, get the qid from the P17 country snak, look up that country qid
      # get the P297 ISO 3166-1 alpha-2 code, search affiliations for that
      if rwd = wikidata_record.find 'snaks.property.exact:"P6782" AND snaks.property.exact:"P17" AND (snaks.value.exact:"' + meta.ror.join(" OR snaks.value.exact:") + '")'
        snkd = false
        for snak in rwd.snaks
          if snkd
            break
          else if snak.property is 'P17'
            if cwd = wikidata_record.get snak.qid
              for sn in cwd.snaks
                if sn.property is 'P297'
                  snkd = true
                  rs = oab_permissions.search 'issuer.id.exact:"' + sn.value + '"'
                  break
    for rr in rs?.hits?.hits ? []
      tr = _prep rr._source
      tr.score = _score tr
      rors.push tr

  if issns.length or meta.publisher
    qr = if issns.length then 'issuer.id.exact:"' + issns.join('" OR issuer.id.exact:"') + '"' else ''
    if meta.publisher
      qr += ' OR ' if qr isnt ''
      qr += 'issuer.id:"' + meta.publisher + '"' # how exact/fuzzy can this be
    ps = oab_permissions.search qr
    if ps?.hits?.hits? and ps.hits.hits.length
      for p in ps.hits.hits
        rp = _prep p._source
        rp.score = _score rp
        perms.all_permissions.push rp

  if perms.all_permissions.length is 0 and meta.publisher and not meta.doi and not issns.length
    af = academic_journal.find 'publisher:"' + meta.publisher + '"'
    if not af?
      fz = academic_journal.find 'publisher:"' + meta.publisher.split(' ').join(' AND publisher:"') + '"'
      if fz.publisher is meta.publisher
        af = fz
      else
        lvs = @tdm.levenshtein fz.publisher, meta.publisher, true
        longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
        af = fz if lvs.distance < 5 or longest/lvs.distance > 10
    if typeof af is 'object' and af.is_oa
      pisoa = academic_journal.count('publisher:"' + af.publisher + '"') is academic_journal.count('publisher:"' + af.publisher + '" AND is_oa:true')
    af = false if not af.is_oa or not pisoa

  if typeof af is 'object' and af.is_oa isnt false
    af.is_oa = true if not af.is_oa? and ('doaj' in af.src or af.wikidata_in_doaj)
    if af.is_oa
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

      try altoa.licence = af.license[0].type # could have doaj licence info
      altoa.licence ?= af.licence # wikidata licence
      if 'doaj' in af.src or af.wikidata_in_doaj
        altoa.embargo_months = 0
        altoa.provenance = {oa_evidence: 'In DOAJ'}
      if typeof altoa.licence is 'string'
        altoa.licence = altoa.licence.toLowerCase().trim()
        if altoa.licence.indexOf('cc') is 0
          altoa.licence = altoa.licence.replace(/ /g, '-')
        else if altoa.licence.indexOf('creative') isnt -1
          altoa.licence = if altoa.licence.indexOf('0') isnt -1 or altoa.licence.indexOf('zero') isnt -1 then 'cc0' else if altoa.licence.indexOf('share') isnt -1 then 'ccbysa' else if altoa.licence.indexOf('derivative') isnt -1 then 'ccbynd' else 'ccby'
        else
          delete altoa.licence
      else
        delete altoa.licence
      if altoa.licence
        altoa.licences = [{type: altoa.licence, terms: ""}]
      altoa.score = _score altoa
      perms.all_permissions.push altoa

  if haddoi and meta.doi and oadoi = await @src.oadoi meta.doi
    # use oadoi for specific doi
    if oadoi?.best_oa_location?.license and oadoi.best_oa_location.license.indexOf('cc') isnt -1
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
      doa.score = _score doa
      perms.all_permissions.push doa

  # sort rors by score, and sort alts by score, then combine
  if perms.all_permissions.length
    perms.all_permissions.sort (a, b) => return if (a.score > b.score) then 1 else -1
    # note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for wp in perms.all_permissions
      if not wp.provenance?.enforcement_from
        perms.best_permission = @copy wp
        break
      else if not meta.published or moment(meta.published,'YYYY-MM-DD').isAfter(moment(wp.provenance.enforcement_from,'DD/MM/YYYY'))
        perms.best_permission = @copy wp
        break
    if rors.length
      rors.sort (a, b) => return if (a.score > b.score) then 1 else -1
      for ro in rors # check this gives the order in the direction we want, else reverse it
        perms.all_permissions.push ro
        if not perms.best_permission?.author_affiliation_requirement?
          if perms.best_permission?
            if not ro.provenance?.enforcement_from or not meta.published or moment(meta.published,'YYYY-MM-DD').isAfter(moment(ro.provenance.enforcement_from,'DD/MM/YYYY'))
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
                  if moment(ro.embargo_end,"YYYY-MM-DD").isBefore(moment(pb.embargo_end,"YYYY-MM-DD"))
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
    return perms



# https://docs.google.com/spreadsheets/d/1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A/edit
P.svc.oaworks.permission = (recs=[]) ->
  keys = 
    versionsarchivable: 'versions'
    permissionsrequestcontactemail: 'permissions_contact'
    archivinglocationsallowed: 'locations'
    license: 'licence'
    licencesallowed: 'licences'
    'post-printembargo': 'embargo_months'
    depositstatementrequired: 'deposit_statement'
    copyrightowner: 'copyright_owner' # can be journal, publisher, affiliation or author
    publicnotes: 'notes'
    authoraffiliationrolerequirement: 'requirements.role'
    authoraffiliationrequirement: 'requirements.affiliation'
    authoraffiliationdepartmentrequirement: 'requirements.departmental_affiliation'
    iffundedby: 'requirements.funder'
    fundingproportionrequired: 'requirements.funding_proportion'
    subjectcoverage: 'requirements.subject'
    has_policy: 'issuer.has_policy'
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
      if rec.recordlastupdated.indexOf(',') isnt -1
        nd = false
        for dt in rec.recordlastupdated.split ','
          nd = dt.trim() if nd is false or moment(dt.trim(),'DD/MM/YYYY').isAfter(moment(nd,'DD/MM/YYYY'))
        rec.recordlastupdated = nd if nd isnt false
      nr.meta.updated = rec.recordlastupdated
    nr.meta.updatedAt = moment(nr.meta.updated, 'DD/MM/YYYY').valueOf() if nr.meta.updated?

    # the google feed import will lowercase these key names and remove whitespace, question marks, brackets too, but not dashes
    nr.issuer.id = if rec.id.indexOf(',') isnt -1 then rec.id.split(',') else rec.id
    if typeof nr.issuer.id isnt 'string'
      cids = []
      inaj = false
      for nid in nr.issuer.id
        nid = nid.trim()
        if nr.issuer.type is 'journal' and nid.indexOf('-') isnt -1 and nid.indexOf(' ') is -1
          nid = nid.toUpperCase()
          if af = academic_journal.find 'issn.exact:"' + nid + '"'
            inaj = true
            for an in af.issn
              cids.push(an) if an not in cids
        cids.push(nid) if nid not in cids
      nr.issuer.id = cids
    nr.permission_required = rec.has_policy? and rec.has_policy.toLowerCase().indexOf('permission required') isnt -1

    for k of rec
      if keys[k] and rec[k]? and rec[k].length isnt 0
        nk = keys[k]
        nv = undefined
        if k is 'post-printembargo' # Post-Print Embargo - empty or number of months like 0, 12, 24
          try
            kn = parseInt rec[k].trim()
            nv = kn if typeof kn is 'number' and not isNaN kn and kn isnt 0
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
          if nk.indexOf('.') isnt -1
            nps = nk.split '.'
            nr[nps[0]] ?= {}
            nr[nps[0]][[nps[1]]] = nv
          else
            nr[nk] = nv

    # Archived Full Text Link - a URL to a web archive link of the full text policy link (ever multiple?)
    # Record First Added - date like 12/07/2017
    # Post-publication Pre-print Update Allowed - string like No, Yes, could be empty (turn these to booleans?)
    # Can Authors Opt Out - seems to be all empty, could presumably be Yes or No

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

    # TODO if there is a provenance.example DOI look up the metadata for it and find the journal ISSN. 
    # then have a search for ISSN be able to find that. Otherwise, we have coverage by publisher that 
    # contains no journal info, so no way to go from ISSN to the stored record

  if ready.length
    oab_permissions.remove '*'
    oab_permissions.insert ready
  return ready.length

P.svc.oaworks.permission._sheet = '1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A'
