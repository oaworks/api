
# best_oa_location* / primary_location* / locations (list)* all have same shape. primary_ always present if locations.length. best_ not always present
# locations is only used for the new way of calculating repository_license_v2 and publisher_license_v2
# NOTE: across openalex and oadoi these values DO NOT match, and it also appears that a best oa location is not
# always necessarily distinct to the location record. For example https://bg.beta.oa.works/src/oadoi/10.4314/just.v29i1.46441
# shows two oa_locations with different landing pages, versions, and host types, but the same PDF URLs
# on openalex the same record https://bg.beta.oa.works/src/openalex/works/10.4314/just.v29i1.46441
# has two locations but one does not have the PDF URL, and the best oa location does not have the PDF URL transposed into it. 
# So it appears OADOI infers it from any OA location to create the best location, whereas openalex does not.
# ALSO our OADOI copy is out of date, even though the current unpaywall (oadoi) API version says it was updated back in 2022
# we've been successfully running updates, and creating from their OADOI data dumps, but it does not appear to match their API.
# https://api.unpaywall.org/works/10.4314/just.v29i1.46441?email=mark@oa.works
# Our openalex copy is https://bg.beta.oa.works/src/openalex/works/10.4314/just.v29i1.46441
# The openalex API copy has been recently updated https://api.openalex.org/works/W1979471373
# and DOES show the same merged data as OADOI. So we HAVE TO fix openalex syncing, and rely on that from now on.
# (the openalex change on 5th Feb probably is after the date we stopped getting correct syncing from them due to issues on our end)
# OTHER issues: 
# 125764 records in our OADOI have oa_locations_embargoed. This does not appear to be present at all in openalex.
# this one in our OADOI: 10.1016/j.enpol.2022.113336 has embargoed locations. It ALSO has an OA location which is NOT present
# in our openalex record. Checking original sources for openalex and OADOI, these two are in sync with our local copies, so this is
# not a syncing problem. Also, there are changes to these records AFTER the first example above, even though that one DOES appear 
# to have syncing issues. Indiciating further that it is less likely just a problem of our syncing, but a problem of what we are 
# receiving to sync with.

P.oareport = -> 'OA.Works OA.report'
P.oareport.works = _index: true

try P.oareport.email = P.report.email

P.oareport.orgs = _sheet: '1OzXJFTedsmvxhpgeAmNHg5Y0sB3ZIXGPk45UUu_a5eE/data', _format: (recs=[]) ->
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
    try nr._id = nr.id if typeof nr.id is 'string' and nr.id.length
    ready.push(nr) if JSON.stringify(nr) isnt '{}'
  return if ready.length is 1 then ready[0] else ready


# adding publisher eLife adds 205k articles
# doing orgs/supplement for Gates without getting assertions caused about a third of Gates records to be missing submitted or accepted dates
# one bulk query like this is still too cumbersome, takes over an hour to build an in-memory map
# relations - about 82k of these. Takes 30 mins to build. Example with is-same-as and is-version-of: 10.7554/elife.87196
# creates about 182k xrefs for 82k records, because they can relate to more than one other record      
# 'is-same-as', 'is-version-of', 'has-version' - NONE of these are for container-title Gates / Wellcome / F1000, but DO require for elife because elife does NOT use update-to values
# BUT what would the order of preference be for replacement DOIs, and what about cascades? should this also or only handle update-to erratum / correction?
# some relations are URLs to remote sources, or other kinds of ID not of any use in this context
# update-to - 295236 of these takes about 2 mins. These appear NOT to overlap with relation, but almost completely overlap with journals (at least when tested for gates, wellcome, f1000)
# preprints - about 1.1m of these takes about 8 mins to build into xrefs map or 4 mins into a separate list
# assertions - about 6.5m of these takes 40 mins. Example with both submitted and accepted 10.1002/bdr2.2210
# key journals - about 750 Gates, 3k Wellcome, 12k F1000. Takes under a min to build. A good example 10.12688/gatesopenres.13035.4
# running for gates wellcome and f1000 in conjunction with update-to above provides 295240 total - so only 4 more
#_oareport_dups = new Map()
P.oareport.duplicate = _index: true, _prefix: false # will it be faster to index or map them? Depends on numbers, how often looking up, how often restarting

'''P.oareport.duplicates = (doi, res, started, preprint, xrec) ->
  started ?= Date.now()
  doi ?= @params.duplicates ? @params.doi

  await @oareport.duplicate('') if @params.empty

  return undefined if not doi
  doi = doi.toLowerCase()

  #if not @refresh and exists = _oareport_dups.get doi
  if not @refresh and (exists = await @oareport.duplicate doi) and exists.createdAt > (Date.now() - 86400*1000*30)
    res = exists
    res.memory = true
  else
    srch = await @oareport.duplicates.search doi
    rels = srch.relations
    records = srch.records
    xrec ?= records[srch.match]
    preprint ?= srch.preprint

    res ?= original: doi, doi: doi, preprint: preprint, count: 0, cascades: 0, duplicate: 0, duplicates: [], preprints: [], timestamp: undefined, record: undefined, dois: [], recs: {}
    relies = []
    incremental = true
    for xrd in records
      #xrd = x._source
      #xrd.DOI = xrd.DOI.toLowerCase() # just in case...
      #console.log 'resp', xrd.DOI
      res.dois.push(xrd.DOI) if xrd.DOI not in res.dois
      res.preprints.push(xrd.DOI) if xrd.subtype is 'preprint' and xrd.DOI not in res.preprints
      res.recs[xrd.DOI] = xrd # keep track of every record to pass back to save looking up later
      # when update-to is present then the xrd record containing it IS an update to whatever DOI was searched
      # BUT there could be more than one record that was an update-to the searched DOI. Also, although the update-to
      # records can contaim timestamps, they are often all identical (e.g. all were indexed/uploaded at the same time)
      # the DOI structure can indicate which is the newest, in some cases, but not all. So at best we can search for 
      # update-to organised by ascending indexed.timestamp, and check the DOI structure, and pick the newest one
      # some records also refer to the record itself in the update-to list, whereas others do not
      # and some records are published YEARS before the ones they are updates to... 
      if xrd['update-to']? and ((preprint and xrd.subtype is 'preprint') or (not preprint and xrd.subtype isnt 'preprint'))
        res.duplicates.push(xrd.DOI) if xrd.DOI not in res.duplicates
        for up in xrd['update-to'] # update-to seems more reliable than relation, so default to this if present
          if up.DOI
            up.DOI = up.DOI.toLowerCase() # DOIs in metadata such as here CAN be mixed case, which is allowed by crossref standards even though crossref themselves use lowercase in the DOI field
            res.duplicates.push(up.DOI) if up.DOI not in res.duplicates
            incremental = false if (rdl = res.duplicates.length) and rdl > 1 and res.duplicates[rdl-1].substring(0, res.duplicates[rdl-1].length-3) isnt res.duplicates[rdl-2].substring(0, res.duplicates[rdl-2].length-3)
        res.timestamp = xrd.indexed.timestamp
        res.doi = xrd.DOI
      res.doi = res.duplicates.sort()[res.duplicates.length-1] if res.duplicates.length and incremental
      # do not fall back to preprints from non-preprints, and vice-versa. But DO match older preprints up to newer preprints
      # example 10.1101/2023.06.26.546135 preprint of 10.7554/elife.89837.3, and 10.12688/verixiv.31.1 has newer preprint 10.12688/verixiv.31.2
      # more useful tests: 10.1186/s12879-019-4314-7 and 10.21203/rs.2.9381/v1 to v5
      # 10.1186/s12936-020-03343-0, 10.12688/gatesopenres.13448.1, 10.12688/verixiv.77.2, 10.26434/chemrxiv-2021-qjzbj-v2, 10.26434/chemrxiv-2021-vfkqb-v3
      # see https://github.com/oaworks/discussion/issues/2218#issuecomment-2112735486 and https://github.com/oaworks/discussion/issues/3478#issuecomment-3254034337
      relies.push(xrd) if xrd.relation? #and ((preprint and xrd.subtype is 'preprint') or (not preprint and xrd.subtype isnt 'preprint'))
    if res.doi and res.doi isnt doi and not res.recs[res.doi]?
      console.log 'oareport duplicates looping', doi, res.doi, res.original, res.cascades
      res.cascades += 1
      return @oareport.duplicates res.doi, res, started, (preprint ? false), xrec
    else # example elife one that loops on relations 10.7554/eLife.89837.2
      for xrd in relies # run the records loop twice so can prioritise update-to across multiple records, shouldn't be too large a list anyway
        #console.log 'relies', xrd.DOI
        for pr in rels
          for arel in xrd.relation?[pr] ? []
            res.duplicates.push(xrd.DOI) if xrd.DOI not in res.duplicates # only add if has a correct sort of relation (or update, above)
            res.recs[xrd.DOI] = xrd
            if typeof arel?.id is 'string' and arel.id.startsWith '10.' # some are URLs to remote sources, or other kinds of ID not of any use in this context
              arel.id = arel.id.toLowerCase()
              res.preprints.push(arel.id) if pr is 'has-preprint' and arel.id not in res.preprints
              if arel.id not in res.duplicates
                res.duplicates.push(arel.id) if arel.id not in res.duplicates
                #and ((preprint and xrd.subtype is 'preprint') or (not preprint and xrd.subtype isnt 'preprint'))
                if (pr isnt 'has-preprint' or preprint) and (pr isnt 'is-preprint-of' or not preprint)
                  if arel.id.includes res.doi
                    res.doi = arel.id
                    res.timestamp = res.recs[res.doi].indexed.timestamp if res.recs[res.doi]?
                  else if (res.doi.substring(0, res.doi.length-3) is arel.id.substring(0, arel.id.length-3)) and (newest = [res.doi, arel.id].sort()[1]) and newest isnt res.doi
                    res.doi = newest
                    res.timestamp = res.recs[res.doi].indexed.timestamp if res.recs[res.doi]?
                  else if arel.id isnt doi and ar = res.recs[arel.id] ? await @src.crossref.works arel.id # can search works.doi to do remote check
                    console.log('oareport duplicates did further looking up for doi and relation', doi, pr, arel.id) if not res.recs[arel.id]?
                    ar.DOI = ar.DOI.toLowerCase()
                    res.recs[arel.id] = ar
                    res.preprints.push(ar.DOI) if ar.subtype is 'preprint' and ar.DOI not in res.preprints
                    if ar.indexed.timestamp > xrd.indexed.timestamp and ar.indexed.timestamp > (res.timestamp ? 0) and ((preprint and ar.subtype is 'preprint') or (not preprint and ar.subtype isnt 'preprint')) #(not preprint or ar.subtype is 'preprint')
                      res.timestamp = ar.indexed.timestamp
                      res.doi = arel.id 

    res.record ?= res.recs[res.doi]
    res.count += Object.keys(res.recs).length
    #delete res.recs

  if not res.memory
    mr = createdAt: started, doi: res.doi, original: res.original, preprint: res.preprint, count: res.count, cascades: res.cascades, duplicate: res.duplicates.length, duplicates: res.duplicates
    #_oareport_dups.set res.original, doi: res.doi, original: res.original, preprint: res.preprint, count: res.count, cascades: res.cascades, duplicate: res.duplicates.length, duplicates: res.duplicates
    mr._id = res.original.replace(/\//g, '_').toLowerCase()
    await @oareport.duplicate mr
    for dd in res.duplicates
      if dd isnt res.original and ((res.preprint and dd in res.preprints) or (not res.preprint and dd not in res.preprints))
        mr._id = dd.replace(/\//g, '_').toLowerCase()
        mr.original = [dd, res.original]
        #_oareport_dups.set dd, doi: res.doi, original: [dd, res.original], preprint: res.preprint, count: res.count, cascades: res.cascades, duplicate: res.duplicates.length, duplicates: res.duplicates
        await @oareport.duplicate mr

  res.duplicate = res.duplicates.length
  res.took = Date.now() - started
  return res

P.oareport.duplicates.search = (doi, relations, keys) ->
  doi ?= @params.search
  doi = doi.toLowerCase()

  relations ?= @params.relations ? ['is-version-of', 'has-version', 'has-preprint', 'is-preprint-of', 'is-same-as'] # prefer is-same-as at end for examples like 10.7554/elife.89837 where it indicates the most recent
  keys ?= @params.keys ? ['update-to.DOI', 'DOI'] # 'DOI',  is updated-by worth checking as well?

  # 10.20944/preprints202009.0645.v2 and 10.1371/journal.pone.0247415 were also useful tests
  keys.push('relation.' + r + '.id') for r in relations
  #qr = keys.join(':"' + doi + '" OR ') + ':"' + doi + '"' # don't search by keyword because that is case sensitive, but relation and update metadata sometimes uses DOIs in different cases even from the parent record
  qr = query: bool: should: [] # switch to using a should term insensitive query because of DOIs like 10.12688/gatesopenres which "greedy matched" too many records
  for key in keys
    qr.query.bool.should.push term: {}
    qr.query.bool.should[qr.query.bool.should.length-1].term[key + '.keyword'] = value: doi, case_insensitive: true
  #xrec ?= await @src.crossref.works doi
  #preprint ?= xrec?.subtype is 'preprint'
  qr ?= @params.q

  resp = await @src.crossref.works qr, size: 10000, sort: 'indexed.timestamp': 'asc'
  #console.log JSON.stringify resp
  #console.log resp.hits.total
  records = resp?.hits?.hits ? []
  count = records.length
  dois = []
  for r, c in records
    records[c] = r._source
    records[c].DOI = records[c].DOI.toLowerCase()
    match = c if records[c].DOI is doi
    dois.push records[c].DOI
  # some DOIs fail to match?
  # 10.21955/gatesopenres.1116653.1, 10.12688/gatesopenres.13072.1, 10.1088/2053-1583/041004, 10.1121
  # some records that appeared not to exist in crossref, can they be matched to others? 10.21955/gatesopenres.1116653.1, 10.12688/gatesopenres.13072.1, 10.1088/2053-1583/041004, 10.1121
  preprint = match? and records[match]?.subtype is 'preprint'
  return {relations, keys, doi, preprint, count, dois, match, records}
'''

P.oareport.duplicates = (doi, cascades) ->
  # 4:  10.1186/s12889-017-4709-6 (10.1186/s12889-017-4575-2), 2: 10.1016/j.deveng.2021.100088, 10.1016/j.xphs.2021.03.003
  # and after Gates supps 3: 10.1016/j.deveng.2021.100088

  # some error oddities with 10.1186/s13071-023-05895-x or 10.1186/s13071-023-06034-2
  # where undefined tries to get read with a key value of 10.21203/rs.3.rs-2700703/v1

  started = Date.now()
  doi ?= @params.duplicates ? @params.doi
  #console.log doi, cascades

  await @oareport.duplicate('') if @params.empty
  return (if @params.empty then '' else undefined) if not doi

  if not @refresh and (exists = await @oareport.duplicate doi) and exists.createdAt > (started - 86400*1000*30)
    res = exists
    res.memory = true
    res.took = Date.now() - started
    return res

  res = createdAt: started, took: 0, original: doi, doi: undefined, preprint: undefined, count: 0, mismatch: undefined, dois: [], preprints: [], cascades: (cascades ? []), extras: 0, relations: [], timestamps: {}, records: {}
  res.cascades.push(doi) if doi not in res.cascades and @params.cascade isnt false

  relations = @params.relations ? ['is-version-of', 'has-version', 'has-preprint', 'is-preprint-of', 'is-same-as'] # has-translation, is-identical-to, is-replaced-by, replaces
  keys = @params.keys ? ['update-to.DOI', 'DOI'] # 'update-to.DOI', 'updated-by.DOI' possibly not very reliable e.g. see 10.1186/s12889-017-4709-6 and there are many different kinds of update-to that may not represent a true replacement (such as expression-of-concern etc)
  # without update-to.DOI or updated-by.DOI we get unique replacements but only 136. 848 with update-to.DOI. So need to check if they are valid
  keys.push('relation.' + r + '.id') for r in relations
  qr = query: bool: should: []
  for key in keys
    qr.query.bool.should.push term: {}
    qr.query.bool.should[qr.query.bool.should.length-1].term[key + '.keyword'] = value: doi, case_insensitive: true

  resp = await @src.crossref.works qr, size: 10000, sort: 'indexed.timestamp': 'asc'
  resps = resp?.hits?.hits ? []
  res.dois.push(x._source.DOI.toLowerCase()) for x in resps
  for x in resps
    xrd = x._source
    xrd.DOI = xrd.DOI.toLowerCase()
    erratum = true # if this is only here because it has erratum update-to/updated-by, then don't use it e.g 10.1186/s12889-017-4709-6
    for pr in keys
      pr = pr.replace('relation.', '').replace('.DOI', '')
      for arel in xrd.relation?[pr] ? xrd[pr] ? []
        if pr not in ['update-to', 'updated-by'] or arel.type not in ['erratum', 'err', 'expression_of_concern']
          erratum = false
          res.preprints.push(xrd.DOI) if pr is 'is-preprint-of' and xrd.DOI not in res.preprints
          if (arid = arel.id ? arel.DOI) and arid.startsWith '10.'
            prt = pr + (if pr in ['update-to', 'updated-by'] then '_' + arel.type else '')
            res.relations.push(prt) if prt not in res.relations
            arid = arid.toLowerCase()
            if arid not in res.dois and not res.records[arid]? and res.records[arid] = await @src.crossref.works arid
              res.extras += 1
              res.records[arid].DOI = res.records[arid].DOI.toLowerCase()
              ts = res.records[arid].indexed.timestamp
              ts += 1 while ts and res.timestamps[ts]?
              res.timestamps[ts] = res.records[arid].DOI
              res.dois.push arid
              if arid not in res.cascades and @params.cascade isnt false and interim = await @oareport.duplicates arid, res.cascades
                res.cascades.push arid
                for id in interim.dois
                  if id not in res.dois
                    res.dois.push id
                    res.records[id] = interim.records[id]
                    ts = interim.records[id].indexed.timestamp
                    ts += 1 while ts and res.timestamps[ts]?
                    res.timestamps[ts] = id
                  res.preprints.push(id) if id in interim.preprints and id not in res.preprints
            res.preprints.push(arid) if (pr is 'has-preprint' or res.records[arid]?.subtype is 'preprint') and arid not in res.preprints
        res.preprints.push(xrd.DOI) if xrd.subtype is 'preprint' and xrd.DOI not in res.preprints
    if not erratum
      res.records[xrd.DOI] = xrd
      ts = xrd.indexed?.timestamp # better value than this to order on?
      ts += 1 while ts and res.timestamps[ts]?
      res.timestamps[ts] = xrd.DOI
    else if xrd.DOI isnt doi and xrd.DOI in res.dois
      res.dois.splice res.dois.indexOf(xrd.DOI), 1

  res.count = (Object.keys res.records).length
  od = []
  op = []
  for t in Object.keys(res.timestamps).sort()
    od.push(res.timestamps[t]) if res.timestamps[t] not in od
    op.push(res.timestamps[t]) if res.timestamps[t] not in op and res.timestamps[t] in res.preprints
    res.mismatch = true if res.timestamps[t] not in res.dois
  if od.length is res.dois.length
    res.dois = od
  else
    res.mismatch = true
  if op.length is res.preprints.length
    res.preprints = op
  else
    res.mismatch = true
  res.mismatch = true if res.count isnt res.dois.length
  res.preprint = res.original in res.preprints
  idx = res.dois.length
  while idx > 0 and not res.doi
    res.doi = res.dois[idx-1] if (not res.preprint and res.dois[idx-1] not in res.preprints) or (res.preprint and res.dois[idx-1] in res.preprints)
    idx--
  if not cascades
    batch = []
    delete res.records
    delete res.timestamps
    for d in res.dois
      nr = {...res}
      nr._id = d.replace(/\//g, '_').toLowerCase()
      nr.original = if d is nr.original then nr.original else [d, nr.original]
      if nr.preprint isnt (d in nr.preprints)
        nr.doi = undefined
        nr.preprint = d in nr.preprints
        idx = nr.dois.length
        while idx > 0 and not nr.doi
          nr.doi = nr.dois[idx-1] if (not nr.preprint and nr.dois[idx-1] not in nr.preprints) or (nr.preprint and nr.dois[idx-1] in nr.preprints)
          idx--
      batch.push nr
    res.saved = await @oareport.duplicate batch
  delete res._id
  res.took = Date.now() - started
  return res


P.oareport.orgs.analysis = (orgs, format) ->
  if typeof orgs is 'string'
    orgid = orgs
    orgs = []
  else if typeof orgs is 'object'
    orgs = [orgs]
  if not orgs? or orgs.length is 0
    orgid ?= @params.org
    orgs = await @src.google.sheets '1OzXJFTedsmvxhpgeAmNHg5Y0sB3ZIXGPk45UUu_a5eE/data'
  idents = {}
  orgid = orgid.split(',') if typeof orgid is 'string'

  for org in orgs
    if not orgid or org.id in orgid
      org = await @report.orgs._format(org, false) if format isnt false
      for an of (org.analysis ? {})
        if org.analysis[an].query and org.analysis[an].make_key not in [false, 'false', 'False', 'FALSE']
          #expected = await @oareport.works.count decodeURIComponent org.analysis[an].query
          console.log 'OAreport orgs anaysing by query', org.id, org.name, an #, expected
          for await qrc from await @oareport.works._for decodeURIComponent org.analysis[an].query
            idents[qrc.DOI] ?= qrc
            idents[qrc.DOI].meta ?= {}
            idents[qrc.DOI].meta.query_matches ?= []
            oan = org.id + '/' + an
            idents[qrc.DOI].meta.query_matches.push(oan) if oan not in idents[qrc.DOI].meta.query_matches
            nk = org.analysis[an].key ? org.analysis[an].name ? an
            nv = org.analysis[an].value ? true
            if org.analysis[an].list
              hasv = await @dot idents[qrc.DOI], nk
              hasv ?= []
              hasv = [hasv] if not Array.isArray hasv
              nv = [nv] if not Array.isArray nv
              hasv.push(v) for v in nv # when v not in hasv
              nv = hasv
            await @dot idents[qrc.DOI], nk, nv
      if org.country_code and org.paid 
        for await qrc from await @oareport.works._for 'DOI:* AND supplements.org.keyword:"' + org.id + '" AND NOT funder.country.keyword:"' + org.country_code + '"' # AND NOT meta.funder_country_codes.keyword:"' + org.id + '"'
          #idents[qrc.DOI] ?= qrc
          #idents[qrc.DOI].meta.funder_country_codes ?= []
          #idents[qrc.DOI].meta.funder_country_codes.push(org.id) if org.id not in idents[qrc.DOI].meta.funder_country_codes
          idents[qrc.DOI] = await @oareport._funder_country (idents[qrc.DOI] ? qrc), org

  await @oareport.works(recs) if (recs = Object.values idents) and recs.length
  return recs.length


P.oareport.orgs.supplements = _index: true, _auth: '@oa.works'
P.oareport.orgs.supplement = (orgid, sheetname) ->
  await @oareport.works('') if @params.empty #works
  await @oareport.orgs.supplements('') if @params.empty
  started = await @epoch()
  hstarted = await @datetime started
  orgid ?= @params.org #? ['demo'] # change this to be RORs e.g '0456r8d26' is BMGF #['Bill & Melinda Gates Foundation', 'your institution'] #@params.org
  orgid = orgid.split(',') if typeof orgid is 'string'
  sheetname ?= @params.sheet #'name_epmc__bmgf' 'data-availability_ic__all' #'grantid_cw__bmgf'
  sheetname = sheetname.split(',') if typeof sheetname is 'string'
  analyse = []
  sups = {}
  total = 0

  for org in await @src.google.sheets '1OzXJFTedsmvxhpgeAmNHg5Y0sB3ZIXGPk45UUu_a5eE/data'
    if not orgid or org.id in orgid
      org = await @report.orgs._format org, false
      analyse.push org
      for s of (sheets = if Array.isArray(org.sheets) then org.sheets else if typeof org.sheets is 'string' then org.sheets.replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';') else [])
        # TODO get a list of every sheet for this org already in oareport/works, any sheet in the list that does not show in the org any more should have those records updated to remove those supps from the removed sheet
        sheet = sheets[s]
        if not sheetname or sheet.name in sheetname
          await @sleep 5000
          console.log org.id, org.name, sheet.name, s, 'of', sheets.length, sheet.url
          analysis = 1 if analysis isnt false
          update = @params.update ? @params.empty ? true
          last = false
          if not @params.update? and not @params.empty # can force an update on URL call
            try
              check = false
              ctries = 0
              while check is false and ctries < 5
                ctries++
                try
                  check = await @src.google.sheets sheetid: sheet.url, sheet: 'm_admin', headers: false
                catch
                  await @sleep 5000
              if check[0][0].toLowerCase() is 'last updated' and last = check[0][1]
                [ld, lt] = last.split ' '
                last = await @epoch ld.split('/').reverse().join('-') + 'T' + lt
              if typeof last is 'number' and last > 1577836800000 # start of 2020, just in case of a bad date
                try latest = await @oareport.works 'supplements.sheets.keyword:"' + sheet.name + '"', size: 1, sort: 'supplements.updated': 'desc'
                latest = latest.hits.hits[0]._source if latest?.hits?.hits?
                update = last if latest?.meta?.updated and last <= latest.meta.updated
            catch
              update = false
          if update isnt true
            console.log org.id, org.name, sheet.name, 'NOT loading because', last, 'is not after', update
          else
            rows = false
            tries = 0
            while not Array.isArray(rows) and tries < 5 # https://github.com/oaworks/Gates/issues/375
              tries++
              try
                rows = await @src.google.sheets sheetid: sheet.url, sheet: 'Export', headers: false
              catch
                await @sleep 5000
            if Array.isArray(rows) and rows.length
              headers = []
              headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
              floats = ['apc_cost', 'wellcome.apc_paid_actual_currency_excluding_vat', 'wellcome.apc_paid_gbp_inc_vat_if_charged', 'wellcome.additional_publication_fees_gbp', 'wellcome.amount_of_apc_charged_to_coaf_grant_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_rcuk_oa_fund_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_wellcome_grant_inc_vat_in_gbp']
              console.log org.id, org.name, sheet.name, rows.length, 'rows'
              for r of rows
                row = rows[r]
                sup = updated: started, org: org.id, sheets: sheet.name, paid: (if org.paid then true else undefined) # check paid explicitly because some had an empty string instead of a bool
                for hp of headers
                  hl = headers[hp].toLowerCase()
                  if hl in ['pmcid', 'openalex']
                    sup[hl.toUpperCase()] = if hl is 'pmcid' then 'PMC' + row[hp].toLowerCase().replace('pmc', '') else row[hp]
                  else
                    try
                      hpv = if hl in floats then parseFloat(row[hp]) else if typeof row[hp] is 'number' then row[hp] else if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if hl in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else row[hp]
                      hpv = row[hp].replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';') if typeof row[hp] is 'string' and row[hp].includes(';')
                      await @dot(sup, headers[hp], hpv) if hpv? and hpv isnt ''
                sup.DOI = await @report.cleandoi(sup.DOI ? sup.doi) if sup.DOI or sup.doi
                console.log(sup) if sup.DOI and sup.DOI.endsWith '/'
                #sup.DOI = olx.ids.doi.split('doi.org/').pop() if sup.OPENALEX and not sup.DOI and (olx = await @src.openalex.works 'ids.openalex.keyword:"https://openalex.org/' + sup.OPENALEX + '"', 1) and olx.ids?.doi
                delete sup.doi
                if (_id = sup.DOI ? sup.OPENALEX ? sup.PMCID)
                  try _id = _id.toLowerCase()
                  #sups[_id] ?= (await @oareport.orgs.supplements _id) ? _id: _id, supplements: [], first_seen: {}
                  sups[_id] ?= _id: _id.replace(/\//g, '_'), supplements: [], first_seen: {}
                  sups[_id].DOI = sup.DOI if not sups[_id].DOI and sup.DOI
                  sups[_id].OPENALEX = sup.OPENALEX if not sups[_id].OPENALEX and sup.OPENALEX
                  sups[_id].PMCID = sup.PMCID if not sups[_id].PMCID and sup.PMCID
                  sups[_id].updated = started
                  sups[_id].first_seen[org.id] ?= hstarted
                  sups[_id].supplements.push sup
                console.log(org.id, org.name, sheet.name, s, 'of', sheets.length, 'row', r, 'of', rows.length, Date.now() - started) if (rc = parseInt r) and rc % 1000 is 0

  slv = Object.values sups
  if slv.length
    total += slv.length
    console.log 'saving', total, slv.length, 'supplements'
    await @oareport.orgs.supplements slv
    await @sleep 5000
    console.log 'loading works', slv.length
    @oareport.works.load Object.keys sups
    sups = {}
    slv = []
  await @oareport.orgs.analysis(org, false) for org in analyse
  
  te = await @epoch() - started
  console.log 'OAreport orgs supplement sheet reading ' + (if analyse.length then 'and ' + analyse.length + ' org analysis ' else '') + 'complete', total, te
  await @mail to: @S.log?.logs, subject: 'OAreport orgs supplement sheet reading ' + total + ' at ' + te, text: 'In sheets found ' + total
  return total
P.oareport.orgs.supplement._async = true
P.oareport.orgs.supplement._log = false
P.oareport.orgs.supplement._bg = true
P.oareport.orgs.supplement._auth = '@oa.works'



P.oareport._funder_country = (rec, org) ->
  if org?.country_code
    for f in rec.funder ? [] # TODO check how this should match with openalex values rather than just fundrefs to crossref grant DOIs
      if f.id
        if org.fundref
          for potfr in (if org.fundref is 'string' then [org.fundref] else org.fundref)
            if f.id.includes potfr # crossref funder DOIs have also been seen to have errors prefixing
              f.country = org.country_code
              break
        if not f.country and org.openalex_funder_id
          for ootfr in (if org.openalex_funder_id is 'string' then [org.openalex_funder_id] else org.openalex_funder_id)
            if f.id.includes ootfr
              f.country = org.country_code
              break
      if not f.country and f.name  # some records have funder objects that are empty or do not have name
        flc = f.name.toLowerCase().replace /[^a-z ]/g, ''
        if flc.includes(port) or port.includes(flc) or (org.aliases ? []).join('').toLowerCase().replace(/[^a-z ]/g, '').includes(flc) or (org.acronyms ? '').toLowerCase().includes flc
          f.country = org.country_code
        if not f.country and org.acronyms
          for poac in org.acronyms.split ','
            f.country = org.country_code if poac.replace(/[^a-z A-Z]/g, '') in f.name.split ' '
        if not f.country and org.aliases
          for poaa in org.aliases
            f.country = org.country_code if flc.includes poaa.toLowerCase().replace /[^a-z ]/g, ''
  return rec

P.oareport._author_display_name = (rec) ->
  email = if rec.outreach.email_address.includes('@') then rec.outreach.email_address else await @decrypt rec.outreach.email_address
  if rec.openalex?.authorships and rec.openalex.authorships.length is 1 and best_first = rec.openalex.authorships[0].author?.display_name
    rec.outreach.author_display_name = 'Dr. ' + best_first
  else
    ren = email.split('@')[0].toLowerCase().replace /[^a-z]/g, ''
    best_initial = ''
    best_name = ''
    best_corr = ''
    best_score = 1000000
    for rn in rec.openalex.authorships
      if ran = rn.author?.display_name
        lvs = await @levenshtein ren, ran.toLowerCase().replace /[^a-z]/g, ''
        score = lvs.distance / ran.length
        if score < best_score
          best_score = score
          best_name = ran
        if best_score > .2 and (ren.endsWith(ran.split(' ').pop().toLowerCase()) or (ran.split(' ')[0].length > 4 and ren.includes ran.split(' ')[0].toLowerCase()))
          best_score = .1
          best_name = ran
        best_initial = ran if not best_initial and ren.startsWith (ran.split(' ')[0].slice(0,1) + ran.split(' ').pop().slice(0,1)).toLowerCase()
        best_corr = ran if not best_corr and rn.author.is_corresponding
    rec.outreach.author_display_name = 'Dr. ' + gotname if gotname = (if best_name and best_score < .7 then best_name.split(' ').pop() else if best_initial then best_initial else if best_corr then best_corr else best_first)
  return rec


P.oareport.works.process = (ident, sup, org_query_match) -> #, deduplicate) ->
  # odd error: OAreport works process error TypeError: Cannot read properties of undefined (reading '10.1101/2020.03.02.20030056')
  # for 10.12688/wellcomeopenres.15811.1
  # when called from oareport/works/load for Gates
  oa_licenses = ["pd", "cc0", "cc-0", "cc-by", "cc-zero", "public-domain"]

  #console.log 'oareport works processing', ident
  try
    started = await @epoch()
    hstarted = await @datetime started
    ident = @params.process if @fn is 'oareport.works.process'
    #deduplicate ?= @params.deduplicate ? true

    rec = ids: {}, is_free_to_read: false, is_open_access: false, supplements: [], corresponding_authorships: [], corresponding_author_ids: [], meta: {replaced: []}, outreach: {}, data_availability_statement: {}

    ident = ident.toLowerCase().split('.org/').pop().replace /\/$/, ''
    if ident.startsWith 'pmc'
      rec.PMCID = ident.toUpperCase()
      try openalex = await @src.openalex.works 'ids.pmcid:"' + ident.replace('pmc', '') + '"', 1
    else if ident.startsWith '10.'
      rec.DOI = ident

    openalex ?= await @src.openalex.works (if ident.startsWith('w') then 'id.keyword:"https://openalex.org/' + ident + '"' else ident), if ident.startsWith('w') then 1 else undefined #, true # can search works.doi to do remote check
    if openalex?
      rec.DOI ?= openalex.ids.doi.split('doi.org/').pop() if openalex.ids.doi
      rec.PMCID ?= 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if openalex.ids.pmcid
    rec._id = if rec.DOI then rec.DOI.toLowerCase().replace(/\//g, '_') else if openalex?.id then openalex.id.split('.org/').pop().toLowerCase() else if rec.PMCID then rec.PMCID.toLowerCase() else ident

    if not @refresh
      exists = await @oareport.works ident
      exists ?= await @oareport.works 'ids.doi.keyword:"' + ident + '" OR ids.pmcid.keyword:"' + ident + '" OR ids.openalex.keyword:"' + ident + '" OR meta.replaced.keyword:"' + ident + '"', 1
    rec.meta = exists.meta if exists?._id # only take the meta from old records
    #if typeof deduplicate is 'string'
    #  rec.meta.replaced_by ?= []
    #  rec.meta.replaced_by.push(deduplicate) if deduplicate not in rec.meta.replaced_by
    #  deduplicate = false
    if ident.startsWith('10.') and dup = await @oareport.duplicates ident # and deduplicate
      if dup.doi? and dup.doi isnt ident # doi may come back empty if the record does not exist in crossref such as 10.21955/gatesopenres.1116653.1
        if exists? #if not dup.memory # ok to delete or need to retrieve and save content?
          # for now do not delete ones that were duplicated - https://github.com/oaworks/discussion/issues/3478#issuecomment-3254030112
          #try @oareport.works ident, ''
          #exists.meta.replaced_by ?= []
          #exists.meta.replaced_by.push(dup.doi) if dup.doi not in exists.meta.replaced_by
          #try await @oareport.works ident, exists
          exists = undefined
        #else
        #  try await @oareport.works.process ident, sup, org_query_match, dup.doi # do not deduplicate again
        rec.DOI = dup.doi
        rec._id = rec.DOI.toLowerCase().replace /\//g, '_'
        if not exists and not @refresh
          exists = await @oareport.works rec._id
          exists ?= await @oareport.works 'ids.doi.keyword:"' + rec.DOI + '" OR meta.replaced.keyword:"' + rec.DOI + '"', 1
        if exists
          rec.meta = exists.meta # only take the meta from old records
      openalex = await @src.openalex.works dup.doi
      rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '') if openalex?.ids?.pmcid
      rec.meta.replaced.push(ident) if ident isnt dup.doi and ident not in rec.meta.replaced
      rec.meta.replaced.push(dr) for dr in dup.dois when dr isnt dup.doi and dr not in rec.meta.replaced and ((dup.preprint and dr in dup.preprints) or (not dup.preprint and dr not in dup.preprints))
    if (ident.startsWith('w') or ident.startsWith('pmc')) and rec._id.startsWith '10.'
      idc = ident.replace(/^w/, 'W').replace(/^pmc/, 'PMC')
      rec.meta.replaced.push(idc) if idc not in rec.meta.replaced

    if org_query_match?
      rec.meta.org_query_match ?= crossref: {}, openalex: {}
      for oqk in ['crossref', 'openalex']
        for orgk of org_query_match[oqk]
          rec.meta.org_query_match[oqk][orgk] ?= org_query_match[oqk][orgk]
      rec.meta.org_query_matches = (Object.keys(rec.meta.org_query_match.crossref).concat(Object.keys rec.meta.org_query_match.openalex)).length

    if openalex?.id
      rec.ids.openalex = openalex.id.split('/').pop()
      rec.openalex = {}
      rec.openalex[mv] = openalex[mv] for mv in ['id', 'abstract', 'apc_list', 'apc_paid', 'authorships', 'authors_count', 'best_oa_location', 'biblio', 'cited_by_count', 'concepts', 'countries_distinct_count', 'corresponding_author_ids', 'created_date', 'display_name', 'domains', 'fields', 'has_fulltext', 'ids', 'is_paratext', 'is_retracted', 'keywords', 'language', 'mesh', 'open_access', 'primary_location', 'publication_date', 'publication_year', 'referenced_works_count', 'sustainable_development_goals', 'title', 'type', 'type_crossref', 'updated', 'updated_date']
      #rec[tm] = openalex[tm] for tm in ['authorships', 'biblio', 'grants', 'title'] # move others that Joe wanted at top level into here
      for g in openalex.grants ? []
        rec.funder ?= []
        rec.funder.push award: (g.award_id ? '').replace(/, /g, ',').split(','), display_name: g.funder_display_name, source: 'openalex', id: g.funder
      for ll in openalex.locations ? [] # only oa locations or all? oadoi would have been oa_locations
        if ll.license and lll = ll.license.toLowerCase()
          rec.is_open_access = true if lll in oa_licenses
        if ll.source?.is_in_doaj #or rec.is_open_access
          rec.syp_permissions ?= {}
          rec.syp_permissions.can_archive = true
          rec.syp_permissions.archivable_version = ll.version
        if ll.source?.type is 'journal' and ll.license and (not rec.publisher?.license or ll.license.length < rec.publisher.license) and ll.version in ['publishedVersion']
          rec.publisher ?= {}
          rec.publisher.license = ll.license 
          rec.publisher.url_for_pdf = ll.pdf_url
          rec.publisher.version = ll.version
        else if ll.source?.type is 'repository'
          rec.repository ?= {}
          rec.repository.license = ll.license if ll.license and (not rec.repository.license or ll.license.length < rec.repository.license)
          if ll.landing_page_url and ll.landing_page_url.toLowerCase().includes 'pmc'
            if not rec.PMCID
              pp = ll.landing_page_url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0].split('.')[0].replace(/[^0-9]/g, '')
              rec.PMCID = 'PMC' + pp if pp.length and not isNaN parseInt pp
            if ll.license and not rec.epmc?.license #and rec.PMCID and ll.landing_page_url.toLowerCase().includes rec.PMCID.toLowerCase()
              rec.epmc ?= {}
              rec.epmc.license = ll.license
          if not rec.repository.url or not rec.repository.url.includes('pmc') or (not rec.repository.url.includes('ncbi.') and ll.landing_page_url and ll.landing_page_url.includes('ncbi.'))
            rec.repository[ok] = ll[ok] for ok in ['license', 'pdf_url', 'landing_page_url', 'version'] when ll[ok]
      if rec.repository?.url and (rec.repository.url.toLowerCase().includes('europepmc.') or rec.repository.url.toLowerCase().includes('ncbi.'))
        rec.PMCID ?= 'PMC' + rec.repository.url.toLowerCase().split('pmc').pop().split('/')[0].split('#')[0].split('?')[0].split('.')[0].replace(/[^0-9]/g, '')
        rec.repository.url_in_pmc = true
      rec.PMID = openalex.ids.pmid.split('/').pop() if openalex.ids?.pmid
      rec.is_free_to_read = true if openalex.open_access?.is_oa or openalex.open_access?.oa_url
      # there are 125764 records in our OADOI that have oa_locations_embargoed. This does not appear to be present in openalex
      #rec.has_oa_locations_embargoed = if oadoi.oa_locations_embargoed? and oadoi.oa_locations_embargoed.length then true else false
      for c in rec.openalex.concepts ? []
        delete c.wikidata
        try c.score = Math.floor(c.score * 100)
      # 'subfields', 'topics', 'primary_topic', have problems with .id having sometimes a number and sometimes a URL, so ignore for now
      #try t.score = Math.floor(t.score * 100) for t in rec.openalex.topics ? []
      rec.corresponding_author_ids.push(cid) for cid in (openalex.corresponding_author_ids ? []) when cid not in rec.corresponding_author_ids
      for a in rec.openalex.authorships ? []
        delete i.type for i in a.institutions ? []
        a.author.orcid_number = a.author.orcid.split('/').pop() if a.author?.orcid and a.author.orcid.includes 'orcid.org/'
        rec.corresponding_authorships.push(a) if a.author?.id in rec.corresponding_author_ids

    rec.ids.doi ?= rec.DOI
    rec.ids.pmcid ?= rec.PMCID

    try
      _sups = (sup = {}) ->
        rec.supplements ?= []
        rec.supplements = rec.supplements.concat (sup.supplements ? [])
        for o in (sup.first_seen ? {})
          rec.meta.first_seen ?= []
          rec.meta.first_seen[o] ?= sup.first_seen[o] # check which is oldest?
      if sup ?= await @oareport.orgs.supplements rec._id
        await _sups sup
      for rid in rec.meta.replaced
        if rr = await @oareport.orgs.supplements rid
          await _sups rr
      for sid in ['pmcid', 'openalex']
        if rec.ids[sid] and rec.ids[sid] not in rec.meta.replaced and ps = await @oareport.orgs.supplements rec.ids[sid]
          rec.meta.replaced.push rec.ids[sid]
          await _sups ps
      for sp in rec.supplements
        rec.meta.is_updated = true if sp.paid
        delete sp.paid
        rec.outreach.email_address = sp.email if sp.email and not rec.outreach.email_address
        sp.email = await @encrypt(sp.email) if typeof sp.email is 'string' and sp.email.includes '@'
        rec.outreach.author_display_name = sp.author_email_name_ic if sp.author_email_name_ic and not rec.outreach.author_display_name
        try rec.corresponding_author_ids.push(cid) for cid in (if typeof sp.corresponding_author_ids is 'string' then sp.corresponding_author_ids.split(',') else (sp.corresponding_author_ids ? [])) when cid not in rec.corresponding_author_ids
        rec.is_open_access = true if (sp.publisher_license_ic and sp.publisher_license_ic in oa_licenses) or (sp.publisher_license_crossref and sp.publisher_license_crossref in oa_licenses) or (sp.preprint_license and sp.preprint_license in oa_licenses) or sp.oasupport?.status is 'Successful'
        rec.is_free_to_read = true if sp.is_free_ic is true or sp.has_preprint_copy is true
        for stt in ['mturk_has_data_availability_statement', 'has_data_availability_statement_ic', 'has_data_availability_statement', 'data_availability_statement', 'data_availability_statement_ic']
          if sp[stt]? and not rec.data_availability_statement.has_data_availability_statement
            rec.data_availability_statement.has_data_availability_statement = if sp[stt] then true else false
            rec.data_availability_statement.source = 'oareport'
        rec.data_availability_statement[dask] = sp['data_availability_statement_' + (if dask in ['doi', 'url'] then 'resource_' else '') + dask] for dask in ['category', 'accession_number', 'doi', 'url'] when sp['data_availability_statement_' + dask]?
        rec[k] = (if sp[k] is 'NULL' then undefined else sp[k]) for k of sp when rec[k]? and typeof rec[k] isnt 'object' and k not in ['DOI', 'corresponding_author_ids', 'paid', 'is_updated', 'email']
    try rec.data_availability_statement.has_data_availability_statement = false if rec.data_availability_statement.category.toLowerCase() is 'not data availability statement'
    try rec = await @oareport._author_display_name(rec) if rec.openalex?.authorships and rec.outreach.email_address and not rec.outreach.author_display_name
    if rec.openalex?.primary_location?.source?.publisher is 'Public Library of Science' or (rec.DOI and (rec.DOI.startsWith('10.1186') or rec.DOI.startsWith('10.12688/gatesopenres')))
      rec.data_availability_statement.has_data_availability_statement = true
      rec.data_availability_statement.source = 'openalex'

    if rec.meta.is_updated
      issns = []
      # get from crossref if not in openalex for is_updated at least - https://github.com/oaworks/Gates/issues/698#issuecomment-1979820337
      # from crossref and not openalex: submitted_date, accepted_date, funders (but openalex grants can cover it), some license info that may be the same as openalex, and a check on crossref oa value
      #if rec.DOI and (not openalex?.grants or (not rec.meta.checked_crossref and (not rec.crossref?.subtype or not rec.acceptance_date or not rec.submission_date))) and crossref = await @src.crossref.works rec.DOI #, true # can search works.doi to include remote check
      if rec.DOI and not openalex?.grants and crossref = await @src.crossref.works rec.DOI #, true # can search works.doi to include remote check
        issns = crossref.ISSN if crossref.ISSN
        rec.is_free_to_read = true if crossref.is_oa
        if crossref.subtype is 'preprint'
          rec.crossref ?= {}
          rec.crossref.subtype = 'preprint'
        rec.meta.checked_crossref = started
        if not rec.submission_date or not rec.acceptance_date
          for ass in crossref.assertion ? []
            assl = (ass.label ? '').toLowerCase()
            if (assl.includes('accepted') and assl.split(' ').length < 3) or assl.includes 'received'
              ad = await @dateparts ass.value
              rec[(if assl.includes('received') then 'submission' else 'acceptance') + '_date'] ?= ad.date if ad?.date and ad.timestamp
        if openalex? and not openalex.grants # only use when the record was in openalex but grants were NOT in openalex
          for f in crossref.funder ? []
            rec.funder ?= []
            rec.funder.push award: f.award, display_name: f.name, source: 'crossref', id: f.DOI

      if rec.openalex?.primary_location?.source?.publisher and not rec.publisher_simple
        if not _report_publishers.length
          _report_publishers.push(rp._source ? rp) for rp in await @report.publishers('*', 10000) ? []
        publ = rec.openalex.primary_location.source.publisher.toLowerCase()
        for pub in _report_publishers
          if pub.publisher and publ.includes pub.publisher.toLowerCase()
            rec.publisher_simple = pub.publisher_display_name
            break

      if (rec.DOI or rec.PMID or rec.ids?.pmid) and ((not rec.PMCID and not rec.ids?.pmcid) or (not rec.PMID and not rec.ids?.pmid) or not rec.pubmed?.pubtype? or not rec.submission_date or not rec.acceptance_date)
        if pubmed = (if rec.PMID or rec.ids.pmid then await @src.pubmed(rec.PMID ? rec.ids.pmid) else await @src.pubmed.doi rec.DOI) # pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
          issns.push(pi) for pi in (pubmed.ISSN ? []) when pi not in issns
          rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '') if not rec.PMCID and pubmed?.identifier?.pmc
          rec.PMID = pubmed.identifier.pubmed if not rec.PMID and pubmed?.identifier?.pubmed
          rec.pubmed ?= {}
          rec.pubmed.pubtype = pubmed.type # this is a list
          rec.submission_date ?= pubmed.dates?.PubMedPubDate_received?.date
          rec.acceptance_date ?= pubmed.dates?.PubMedPubDate_accepted?.date
      
      if rec.PMCID or rec.ids.pmcid
        rec.meta.checked_epmc_license = started
        if epmc = await @src.epmc.pmc rec.PMCID ? rec.ids.pmcid
          issns.push(epmc.journalInfo.journal.issn) if epmc.journalInfo?.journal?.issn and epmc.journalInfo.journal.issn not in issns
          issns.push(epmc.journalInfo.journal.essn) if epmc.journalInfo?.journal?.essn and epmc.journalInfo.journal.essn not in issns
          rec.PMCID ?= epmc.pmcid
          rec.pubmed ?= {}
          rec.pubmed.pubtype ?= []
          rec.pubmed.pubtype.push(pt) for pt in (epmc.pubTypeList?.pubType ? []) when pt not in rec.pubmed.pubtype
          rec.epmc ?= {}
          rec.epmc.license = (await @src.epmc.licence (rec.PMCID ? rec.ids.pmcid), epmc)?.licence
          # see https://github.com/oaworks/discussion/issues/1884#issuecomment-2009931400
          if not rec.data_availability_statement?.has_data_availability_statement
            if await @src.pubmed.availability rec.PMCID ? rec.ids.pmcid
              rec.data_availability_statement.has_data_availability_statement = true
              rec.data_availability_statement.source = 'pubmed'
            else
              rec.data_availability_statement.has_data_availability_statement = false
              rec.data_availability_statement.source = 'pubmed'
          if not rec.data_availability_statement?.has_data_availability_statement
            if edas = await @src.epmc.statement (rec.PMCID ? rec.ids.pmcid), epmc
              rec.data_availability_statement.has_data_availability_statement = true
              rec.data_availability_statement.source = 'epmc'
              rec.data_availability_statement.full_text = edas
              if urlordois = await @src.epmc.statement.url (rec.PMCID ? rec.ids.pmcid), epmc, edas
                for dor in urlordois
                  if dor and dor.includes 'doi.org/'
                    dord = dor.split('doi.org/')[1].toLowerCase()
                    rec.data_availability_statement.resource_doi ?= []
                    rec.data_availability_statement.resource_doi.push(dord) if dord not in rec.data_availability_statement.resource_doi
                  else
                    rec.data_availability_statement.resource_url ?= []
                    rec.data_availability_statement.resource_url.push(dor) if dor not in rec.data_availability_statement.resource_url
            else
              rec.data_availability_statement.has_data_availability_statement = false
              rec.data_availability_statement.source = 'epmc'
          rec.submission_date ?= await @src.epmc.submitted (rec.PMCID ? rec.ids.pmcid), epmc

      if rec.DOI
        # Note, openalex can have an article in pubmed for example that it then doesn't bother to indicate as being in doaj, because the source it gives is pubmed rather than the journal which may be in doaj. See 10.11606/s1518-8787.2023057004376
        # however in such cases it may well still have apc_paid and apc_list with provenance of doaj, so it can still be discerned that it is in doaj
        #if not rec.syp_permissions?.archivable_version? and (permissions = await @permissions {doi: rec.DOI}, undefined, undefined, undefined, crossref) and permissions.best_permission?
        #if not rec.syp_permissions?.archivable_version? and (permissions = await @permissions_new {doi: rec.DOI}, undefined, openalex) and permissions.best_permission?
        rec.syp_permissions ?= {}
        if (permissions = await @permissions_new {doi: rec.DOI}, undefined, openalex) and permissions.best_permission?
          if not rec.syp_permissions.can_archive or permissions.best_permission.can_archive
            rec.syp_permissions.can_archive = permissions.best_permission.can_archive
            rec.syp_permissions.archivable_version = permissions.best_permission.version if permissions.best_permission.version
        if issns or openalex? or crossref?
          rec.syp_permissions.journal_oa_type = await @permissions_new.journals.oa.type(issns, undefined, openalex, crossref) ? 'unsuccessful'
          #try rec.syp_permissions.journal_oa_type_report = (await @report.works rec.DOI).journal_oa_type
          #rec.syp_permissions.journal_oa_type_old = await @permissions.journals.oa.type(issns, undefined, undefined, crossref) ? 'unsuccessful'
          #rec.is_open_access = true if rec.syp_permissions.journal_oa_type in ['gold', 'diamond']

    rec.outreach.email_address = await @encrypt(rec.outreach.email_address) if typeof rec.outreach.email_address is 'string' and rec.outreach.email_address.includes '@'
    rec.is_open_access = true if not rec.is_open_access and rec.epmc?.license and (ell = rec.epmc.license.toLowerCase()) and ell in oa_licenses
    rec.is_free_to_read = true if rec.is_open_access or rec.PMCID
    rec.meta.updated = await @epoch()
    rec.meta.updated_date = await @date rec.meta.updated
    rec.meta.took = rec.meta.updated - started
    for ik in ['DOI', 'PMCID', 'PMID']
      rec.ids[ik.toLowerCase()] = rec[ik] if rec[ik]
      delete rec[ik] if ik isnt 'DOI'
    @oareport.works(rec) if @params.save isnt false and rec._id and rec._id is (@params.process ? '').toLowerCase().replace /\//g, '_'
    # what about replaced IDs?
    return rec
  catch err
    console.log 'OAreport works process error', err
    try console.log ident
    return
P.oareport.works.process._log = false



P.oareport.works.load = (idents, timestamp, org, year, supplements, clear) ->
  started = await @epoch()
  supplements ?= @params.load is 'supplements'
  year = if @params.load and @params.load isnt 'supplements' then @params.load else (await @date()).split('-')[0] # load could be supplements or everything but in that case year is not used anyway
  org = @params.org ? @params.orgs ? @params.load is 'orgs'
  idents ?= []
  idents = idents.split(',') if typeof idents is 'string'

  clear ?= @params.clear
  await @oareport.works('') if clear

  startcount = await @oareport.works.count()
  precounts = 0

  if @params.q
    console.log 'OAreport works load for query', @params.q
    for await sw from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'oareport_works', @params.q, scroll: '5m', include: ['ids'] # ['DOI', 'openalex', 'PMCID']
    #for await sw from await @oareport.works._for @params.q, scroll: '5m', include: ['ids'] #['DOI', 'openalex', 'PMCID']
      #idents.push sw.DOI ? sw.openalex ? sw.PMCID
      idents.push sw.ids?.doi ? sw.ids?.openalex ? sw.ids?.pmcid
  else if supplements
    for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'oareport_orgs_supplements', (if timestamp then 'updated:<' + timestamp else if org then 'org:"' + org + '"' else undefined), scroll: '5m', include: ['DOI', 'openalex', 'pmcid']
      idents.push sup.DOI ? sup.openalex ? sup.pmcid
    console.log 'OAreport works to load all from orgs supplements search', timestamp, org, idents.length
  else if not idents.length
    _byqry = (q, cr, org) =>
      idents = {} if org? and Array.isArray idents
      q ?= (if cr then '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' else 'authorships.institutions.display_name:* AND publication_year:') + year
      q = '(' + q + ') AND ' + (if cr then 'srcday' else 'updated_date') + ':>' + timestamp if timestamp
      precount = await @src[if cr then 'crossref' else 'openalex'].works.count q
      console.log 'OAreport works load ' + (if cr then 'crossref' else 'openalex') + ' by query expects', q, precount
      precounts += precount
      for await r from @index._for (if cr then 'src_crossref_works' else 'src_openalex_works'), q, include: (if cr then ['DOI'] else ['id', 'ids']), scroll: '10m'
      #for await r from await @src[if cr then 'crossref' else 'openalex'].works._for q, include: (if cr then ['DOI'] else ['id', 'ids']), scroll: '10m'
        od = if r.DOI then r.DOI else if r.ids?.doi then '10.' + r.ids.doi.split('/10.')[1] else r.id.split('openalex.org/').pop()
        if od
          if org?
            idents[od] ?= crossref: {}, openalex: {}
            idents[od][if cr then 'crossref' else 'openalex'][org.name] = precount
          else
            idents.push(od) if timestamp or od not in idents

    if not org and year is @params.load
      console.log 'OAreport works load for year', year
      await Promise.all [_byqry(), _byqry undefined, true]
    else
      console.log 'OAreport works load for org', (if org then org else 'all'), 'by source.openalex or source.crossref query presence'
      for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'oareport_orgs', (if typeof org is 'string' then 'name.keyword:"' + org + '"' else '*'), scroll: '10m'
      #for await o from await @oareport.orgs._for (if typeof org is 'string' then 'name.keyword:"' + org + '"' else '*'), scroll: '10m'
        # if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
        await _byqry(decodeURIComponent(decodeURIComponent(o.source.openalex)), undefined, o) if o.source?.openalex
        await _byqry(decodeURIComponent(decodeURIComponent(o.source.crossref)), true, o) if o.source?.crossref

    if timestamp
      console.log 'OAreport works load for updated before', timestamp, await @date timestamp
      #for await ot from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'oareport_works', 'DOI:* AND meta.is_updated:true AND updated:<' + timestamp, include: ['DOI'], scroll: '10m'
      for await ot from await @oareport.works._for '(DOI:* OR ids.doi:*) AND meta.is_updated:true AND updated:<' + timestamp, include: ['DOI', 'ids'], scroll: '10m'
        tid = ot.DOI ? ids.doi ? ids.openalex ? ids.pmcid
        idents.push(tid) if tid and tid not in idents

  # replace the following batch processing with a call to queue? But then can't do checks after load
  #await @queue.add idents
  batch = []
  idk = if Array.isArray(idents) then idents else Object.keys idents
  for id in idk
    res = await @oareport.works.process id, undefined, (if Array.isArray(idents) then undefined else idents[id])
    batch.push(res) if res?
    if batch.length >= 10000
      console.log 'OAreport works loading', batch.length, Date.now() - started
      await @oareport.works batch
      batch = []
  await @oareport.works(batch) if batch.length
  await @sleep 5000
  currentcount = await @oareport.works.count()
  te = await @epoch() - started
  console.log 'OAreport works loaded', idk.length, startcount, precounts, currentcount, te

  text = 'Start count: ' + startcount + '\nLoaded: ' + idk.length + '\nCurrent count: ' + currentcount + '\nElapsed time: ' + te
  if precounts
    text += '\nQuery Expected-counts total: ' + precounts
  await @mail to: @S.log?.logs, subject: 'OAreport works loaded ' + idk.length + ' at ' + te, text: text
  return idk.length

P.oareport.works.load._log = false
P.oareport.works.load._bg = true
P.oareport.works.load._async = true
P.oareport.works.load._auth = '@oa.works'








P.oareport.check = ->
  checked = report: 0, oareport: 0
  present = report: [], oareport: []
  supplement = report: [], oareport: []
  missing = report: [], oareport: []
  for idx in [] #['report']
    for await o from @index._for 'paradigm_b_' + idx + '_works', 'DOI:* AND supplements.org:Gates', scroll: '10m'
      checked[idx] += 1
      console.log idx, checked
      if (idx is 'report' and await @oareport.works o.DOI) or (idx is 'oareport' and await @report.works o.DOI) # is this good enough or should be against live data?
        present[idx].push o.DOI
      else
        missing[idx].push o.DOI

  #for idx in ['oareport'] #indexes
  #  for await sup from @index._for 'paradigm_b_' + idx + '_orgs_supplements', (if idx is 'oareport' then 'supplements.' else '') + 'org:Gates', scroll: '10m'
  qr = 'supplements.org.keyword:"0456r8d26"'
  for await sup from @index._for 'paradigm_b_oareport_orgs_supplements', qr, scroll: '10m' #'supplements.org:Gates', scroll: '10m'
    checked.oareport += 1
    console.log 'sup', 'oareport', checked
    if sup.DOI
      exists = await @oareport.works sup.DOI
    if not exists and sup.DOI
      exists = await @oareport.works 'meta.replaced.keyword:"' + sup.DOI + '"', 1
    if not exists and sup.PMCID
      exists = await @oareport.works 'ids.pmcid.keyword:"' + sup.PMCID + '" OR meta.replaced.keyword:"' + sup.PMCID + '"', 1
    if not exists and sup.OPENALEX
      exists = await @oareport.works 'ids.openalex.keyword:"' + sup.OPENALEX + '" OR meta.replaced.keyword:"' + sup.OPENALEX + '"'
    if not exists?._id
      supplement.oareport.push sup.DOI ? sup.PMCID ? sup.OPENALEX
    #if not await @report.orgs.supplements.count 'org:Gates AND DOI.keyword:"' + sup.DOI + '"'
    #  supplement.report.push sup.DOI

  res = checked: checked, present: {report: present.report.length, oareport: present.oareport.length}, missing: {report: missing.report.length, oareport: missing.oareport.length}, supplement: {report: supplement.report.length, oareport: supplement.oareport.length}
  console.log supplement.oareport
  console.log res
  fs.writeFile '/home/oaw/static/oareport_check.json', JSON.stringify supplement.oareport, null, 2
  return res
P.oareport.check._async = true



'''
P.oareport.build = ->
  started = await @epoch()
  clear = @params.clear
  await @oareport.works('') if clear

  year = @params.year
  timestamp = @params.timestamp

  idents = []
  sups = {}

  _byqry = (q, cr) =>
    q ?= (if cr then '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' else 'authorships.institutions.display_name:* AND publication_year:') + year
    q = '(' + q + ') AND ' + (if cr then 'srcday' else 'updated_date') + ':>' + timestamp if timestamp
    for await r from @index._for (if cr then 'src_crossref_works' else 'src_openalex_works'), q, include: (if cr then ['DOI'] else ['id', 'ids']), scroll: '10m'
      od = if r.DOI then r.DOI else if r.ids?.doi then '10.' + r.ids.doi.split('/10.')[1] else r.id.split('openalex.org/').pop()
      idents.push(od) if od and (timestamp or od not in idents)

  await _byqry(@params.q, @params.crossref, @params.oadoi) if @params.q

  orgid = @params.org
  orgid = orgid.split(',') if typeof orgid is 'string'
  sheetname = @params.sheet
  sheetname = sheetname.split(',') if typeof sheetname is 'string'
  analyse = []

  _sheet = (s, sheet, org) =>
    console.log org.id, org.name, sheet.name, s, 'of', sheets.length, sheet.url
    if not clear
      check = 0
      while typeof check is 'number' and check < 5
        md = await @src.google.sheets sheetid: sheet.url, sheet: 'm_admin', headers: false
        if md[0][0].toLowerCase() is 'last updated' and [last, lt] = check[0][1].split ' '
          last = await @epoch last.split('/').reverse().join('-') + 'T' + lt
          if typeof last is 'number' and last > 1577836800000 # start of 2020, just in case of a bad date
            latest = await @oareport.works 'supplements.sheets.keyword:"' + sheet.name + '"', size: 1, sort: 'supplements.updated': 'desc'
            if last <= latest.hits.hits[0]._source.meta.updated
              console.log org.id, org.name, sheet.name, 'NOT loading because', last, 'is not after', latest.hits.hits[0]._source.meta.updated
              return
            check = 6
        check++
        await @sleep(5000) if check < 5

    rows = false
    tries = 0
    while not Array.isArray(rows) and tries < 5 # https://github.com/oaworks/Gates/issues/375
      tries++
      try
        rows = await @src.google.sheets sheetid: sheet.url, sheet: 'Export', headers: false
      catch
        await @sleep 5000
    if Array.isArray(rows) and rows.length
      headers = []
      headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', '')) for header in rows.shift()
      floats = ['apc_cost', 'wellcome.apc_paid_actual_currency_excluding_vat', 'wellcome.apc_paid_gbp_inc_vat_if_charged', 'wellcome.additional_publication_fees_gbp', 'wellcome.amount_of_apc_charged_to_coaf_grant_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_rcuk_oa_fund_inc_vat_if_charged_in_gbp', 'wellcome.amount_of_apc_charged_to_wellcome_grant_inc_vat_in_gbp']
      console.log org.id, org.name, sheet.name, rows.length, 'rows'
      for r of rows
        row = rows[r]
        sup = updated: started, org: org.id, sheets: sheet.name, paid: (if org.paid then true else undefined) # check paid explicitly because some had an empty string instead of a bool
        for hp of headers
          hl = headers[hp].toLowerCase()
          if hl in ['pmcid', 'openalex']
            sup[hl.toUpperCase()] = if hl is 'pmcid' then 'PMC' + row[hp].toLowerCase().replace('pmc', '') else row[hp]
          else
            try
              hpv = if hl in floats then parseFloat(row[hp]) else if typeof row[hp] is 'number' then row[hp] else if not row[hp] then undefined else if row[hp].trim().toLowerCase() in ['true', 'yes'] then true else if row[hp].trim().toLowerCase() in ['false', 'no'] then false else if hl in ['grant_id', 'ror'] then row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') else row[hp]
              hpv = row[hp].replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';') if typeof row[hp] is 'string' and row[hp].includes(';')
              await @dot(sup, headers[hp], hpv) if hpv? and hpv isnt ''
        sup.DOI = await @report.cleandoi(sup.DOI ? sup.doi) if sup.DOI or sup.doi
        sup.DOI = olx.ids.doi.split('doi.org/').pop() if sup.OPENALEX and not sup.DOI and (olx = await @src.openalex.works 'ids.openalex.keyword:"https://openalex.org/' + sup.OPENALEX + '"', 1) and olx.ids?.doi
        delete sup.doi
        if (_id = if sup.DOI then sup.DOI.replace(/\//g, '_') else (sup.OPENALEX ? sup.PMCID))
          analysis = if analysis is 1 then true else analysis
          try _id = _id.toLowerCase()
          sups[_id] ?= (await @oareport.orgs.supplements _id) ? _id: _id, supplements: [], first_seen: {}
          sups[_id].DOI = sup.DOI if not sups[_id].DOI and sup.DOI
          sups[_id].OPENALEX = sup.OPENALEX if not sups[_id].OPENALEX and sup.OPENALEX
          sups[_id].PMCID = sup.PMCID if not sups[_id].PMCID and sup.PMCID
          sups[_id].updated = started
          sups[_id].first_seen[org.id] ?= hstarted
          sups[_id].supplements.push sup
          idents.push(_id) if _id not in idents
        console.log(org.id, org.name, sheet.name, s, 'of', sheets.length, 'row', r, 'of', rows.length, Date.now() - started) if (rc = parseInt r) and rc % 1000 is 0

  for org in await @src.google.sheets '1OzXJFTedsmvxhpgeAmNHg5Y0sB3ZIXGPk45UUu_a5eE/data' # S.report.orgs_sheet
    if not orgid or org.id in orgid
      org = await @report.orgs._format org, false
      sheetprocs = []
      for s of (sheets = if Array.isArray(org.sheets) then org.sheets else if typeof org.sheets is 'string' then org.sheets.replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';') else [])
        if not sheetname or sheets[s].name in sheetname
          await @sleep 5000
          sheetprocs.push _sheet s, sheets[s], org
      await Promise.all sheetprocs
      await _byqry(decodeURIComponent(decodeURIComponent(o.source.openalex))) if o.source?.openalex
      await _byqry(decodeURIComponent(decodeURIComponent(o.source.crossref)), true) if o.source?.crossref
      #await _byqry(decodeURIComponent(decodeURIComponent(o.source.crossref)), undefined, true) if o.source?.oadoi
      analyse.push org

  console.log 'OAreport orgs build got supps', Object.values(sups).length, Date.now() - started

  batch = []
  running = []
  _wr = (i, s) => batch.push await @oareport.works.build i, s # ident, sup
  for i in idents
    running.push _wr (sup.DOI ? sup.OPENALEX ? sup.PMCID ? sup._id), sups[i]
    if running.length is 100 # 500 is too many for ES to handle (without more wait spacing). 200 mostly fine, but then failed once while big load on ES from openalex rebuild. Back to 100. 100 only a few mins slower than 200.
      await Promise.all running
      running = []
      if batch.length >= 10000
        console.log 'OAreport orgs supplementing', batch.length, updated, Date.now() - started
        await @oareport.works batch
        batch = []
  await Promise.all(running) if running.length
  await @oareport.works(batch) if batch.length
  await @oareport.orgs.analysis(org, false) for org in analyse

  # add an email to Front
  console.log 'OAreport build loaded', idents.length, await @epoch() - started
  return idents.length

P.oareport.build._log = false
P.oareport.build._bg = true
P.oareport.build._async = true
P.oareport.build._auth = '@oa.works'
'''




'''
P.oareport.review = (org, fr, to) ->
  org ?= @params.review ? @params.org ? 'Bill & Melinda Gates Foundation'
  fr ?= @params.from ? '2023-12-31'
  to ?= @params.to ? '2024-06-07'
  oareportdates = '(openalex.publication_date:>' + fr + ' AND openalex.publication_date:<' + to + ')'
  oareportquery = ''
  reportdates = '(published_date:>' + fr + ' AND published_date:<' + to + ')'
  reportquery = ''
  res = org: org, from: fr, to: to, counts: {}, terms: {}, is_oa: {oareport: {}, report: {}}, queries: {}, missing: {} # oareport: {queries: {}, counts: {}}, report: {queries: {}, counts: {}}
  _process = (which) =>
    isp = ''
    for await o from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + which + '_orgs', 'name.keyword:"' + org + '"', scroll: '10m'
      for a of o.analysis ? {}
        if o.analysis[a].query
          qr = decodeURIComponent o.analysis[a].query
          oareportquery = qr if not oareportquery and which is 'oareport'
          reportquery = qr if not reportquery and which is 'report'
          if fr and to
            qr = (if which is 'oareport' then oareportdates else reportdates) + ' AND ' + qr
          isp = qr if not isp and a is 'is_paper'
          res.queries[a] ?= {}
          res.queries[a][which] = qr
          res.counts[a] ?= {}
          res.counts[a][which] = await @index.count 'paradigm_' + (if @S.dev then 'b_' else '') + which + '_works', qr
    if isp
      for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + which + '_works', isp, scroll: '10m', include: ['DOI']
        if not exists = await @[if which is 'oareport' then 'report' else 'oareport'].works rec.DOI
          res.missing['in_' + which + '_not_in_' + (if which is 'oareport' then 'report' else 'oareport')] ?= []
          res.missing['in_' + which + '_not_in_' + (if which is 'oareport' then 'report' else 'oareport')].push rec.DOI
      res.missing['not_in_' + (if which is 'oareport' then 'report' else 'oareport') + '_count'] = res.missing['in_' + which + '_not_in_' + (if which is 'oareport' then 'report' else 'oareport')].length
  await _process(e) for e in ['oareport', 'report']

  oarq = decodeURIComponent '(openalex.publication_date:%3E2023-12-31%20AND%20openalex.publication_date:%3C2024-06-07)%20AND%20((openalex.primary_location.source.display_name:%22gates%20open%20research%22%20OR%20supplements.sheets:*pub__bmgf%20OR%20supplements.sheets:(%22grantid_cw__bmgf%22%20OR%20%22pmc__bmgf%22%20OR%20%22all-time__bmgf%22%20OR%20%22name_epmc__bmgf%22%20OR%20%22staff__bmgf%22%20OR%20%22chronos_v2__bmgf%22%20OR%20%22finance__bmgf%22%20OR%20%22users__bmgf%22%20OR%20%22preprints_oa_locations__bmgf%22%20OR%20%22preprints-enrichment__bmgf%22)%20OR%20(funder.id:(%2210.13039/100000865%22%20OR%20%2210.13039/501100005370%22)%20OR%20funder.name:(%22Bill%20%26%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22)%20OR%20openalex.grants.funder:(%22F4320306137%22%20OR%20%22F4320323264%22))%20OR%20(openalex.authorships.institutions.ror:(%220456r8d26%22%20OR%20%22033sn5p83%22)%20OR%20openalex.authorships.institutions.display_name:(%22Bill%20%26%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22)%20OR%20openalex.authorships.raw_affiliation_string:(%22Bill%20&%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22))%20OR%20supplements.funder.display_name_ic:%22bill-and-melinda-gates-foundation%22)%20AND%20NOT%20(supplements.removed_from_report:%22bill-and-melinda-gates-foundation%22%20OR%20supplements.is_financial_disclosure:%22bill-and-melinda-gates-foundation%22))%20AND%20openalex.type:(%22article%22%20OR%20%22editorial%22%20OR%20%22letter%22%20OR%20%22review%22)%20AND%20NOT%20openalex.type_crossref:%22proceedings-article%22%20AND%20NOT%20(supplements.is_preprint:true%20OR%20(pubtype:preprint%20AND%20NOT%20supplements.is_preprint:false)%20OR%20subtype:preprint)%20AND%20openalex.id:*%20AND%20openalex.primary_location.source.display_name:*'
  rq = decodeURIComponent '(published_date:%3E2023-12-31%20AND%20published_date:%3C2024-06-07)%20AND%20((journal:%22gates%20open%20research%22%20OR%20supplements.sheets:*pub__bmgf%20OR%20supplements.sheets:(%22grantid_cw__bmgf%22%20OR%20%22pmc__bmgf%22%20OR%20%22all-time__bmgf%22%20OR%20%22name_epmc__bmgf%22%20OR%20%22staff__bmgf%22%20OR%20%22chronos_v2__bmgf%22%20OR%20%22finance__bmgf%22%20OR%20%22users__bmgf%22%20OR%20%22preprints_oa_locations__bmgf%22%20OR%20%22preprints-enrichment__bmgf%22)%20OR%20(funder.DOI:(%2210.13039/100000865%22%20OR%20%2210.13039/501100005370%22)%20OR%20funder.name:(%22Bill%20%26%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22)%20OR%20openalx.grants.funder:(%22F4320306137%22%20OR%20%22F4320323264%22))%20OR%20(authorships.institutions.ror:(%220456r8d26%22%20OR%20%22033sn5p83%22)%20OR%20authorships.institutions.display_name:(%22Bill%20%26%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22)%20OR%20authorships.raw_affiliation_string:(%22Bill%20&%20Melinda%20Gates%20Foundation%22%20OR%20%22melinda%20gates%20foundation%22%20OR%20%22gates%20cambridge%20trust%22%20OR%20%22gates%20ventures%22))%20OR%20supplements.funder.display_name_ic:%22bill-and-melinda-gates-foundation%22)%20AND%20NOT%20(supplements.removed_from_report:%22bill-and-melinda-gates-foundation%22%20OR%20supplements.is_financial_disclosure:%22bill-and-melinda-gates-foundation%22))%20AND%20type:(%22article%22%20OR%20%22editorial%22%20OR%20%22letter%22%20OR%20%22review%22)%20AND%20NOT%20openalx.type_crossref:%22proceedings-article%22%20AND%20NOT%20(supplements.is_preprint:true%20OR%20(pubtype:preprint%20AND%20NOT%20supplements.is_preprint:false)%20OR%20subtype:preprint)%20AND%20openalex:*%20AND%20journal:*'

  res.terms.oareport = await @oareport.works.terms 'syp_permissions.journal_oa_type.keyword', oarq
  res.terms.report = await @report.works.terms 'journal_oa_type.keyword', rq

  oaoaq = '(epmc_licence.keyword:("pd" OR "public-domain" OR "cc0" OR "cc-by") OR syp_permissions.journal_oa_type.keyword:("gold" OR "diamond") OR openalex.locations.license.keyword:("pd" OR "public-domain" OR "cc0" OR "cc-by") OR supplements.publisher_license_ic.keyword:("cc0" OR "cc-by"))'
  roaq = '(epmc_licence.keyword:("pd" OR "public-domain" OR "cc0" OR "cc-by") OR journal_oa_type.keyword:("gold" OR "diamond") OR openalx.locations.license.keyword:("pd" OR "public-domain" OR "cc0" OR "cc-by") OR supplements.publisher_license_ic.keyword:("cc0" OR "cc-by"))'

  res.is_oa.oareport.is_oa_derived = await @oareport.works.count oarq + ' AND ' + oaoaq
  #res.is_oa.oareport.is_oa_but_not_by_derived = await @oareport.works.count oarq + ' AND is_open_access:true AND NOT ' + oaoaq
  res.is_oa.oareport.is_oa_but_not_by_derived_dois = []
  for await rd from await @oareport.works._for oarq + ' AND is_open_access:true AND NOT ' + oaoaq, scroll: '10m', include: ['DOI']
    res.is_oa.oareport.is_oa_but_not_by_derived_dois.push rd.DOI
  res.is_oa.oareport.is_oa_but_not_by_derived = res.is_oa.oareport.is_oa_but_not_by_derived_dois.length
  res.is_oa.report.is_oa_derived_from_oareport = await @report.works.count rq + ' AND ' + roaq

  oarcdas = '(data_availability_statement.has_data_availability_statement:true OR openalex.primary_location.source.publisher:"Public Library of Science" OR DOI:"10.1186*" OR DOI:"10.12688/gatesopenres*")'

  res.oareport_has_checked_das = await @oareport.works.count oarq + ' AND ' + oarcdas

  return res
'''

'''P.oareport.journal_oa_type = ->
  res = count: 0, dc: 0, wasgold: 0, wasdiamond: 0, pretypes: {}, posttypes: {}, diffs: []
  for await r from @index._for 'paradigm_b_oareport_works', 'DOI:* AND supplements.org:Gates AND (syp_permissions.journal_oa_type:Gold OR syp_permissions.journal_oa_type:Diamond)', scroll: '10m', include: ['DOI', 'syp_permissions']
    res.count += 1
    j = await @permissions_new.journals.oa.type r.DOI
    if j isnt r.syp_permissions.journal_oa_type
      res.diffs.push doi: r.DOI, was: r.syp_permissions.journal_oa_type, now: j
      res[if r.syp_permissions.journal_oa_type is 'gold' then 'wasgold' else 'wasdiamond'] += 1
    res.pretypes[r.syp_permissions.journal_oa_type] ?= 0
    res.pretypes[r.syp_permissions.journal_oa_type] += 1
    res.posttypes[j] ?= 0
    res.posttypes[j] += 1
  res.dc = res.diffs.length
  console.log res
  await @mail to: ['mark+notifications@oa.works'], subject: 'OA report journal oa type tested ' + res.count, text: JSON.stringify res
  return res
P.oareport.journal_oa_type._async = true'''



'''
P.oareport.checkppmi = ->
  res = supplement: 0, oareport: 0, nodoi: 0, noid: 0, dedups: 0, olxnodoi: 0, olxnopmcid: 0, olxispreprint: 0, missing: [], dedup: {}

  for await sup from @index._for 'paradigm_b_oareport_orgs_supplements', 'supplements.org.keyword:"ppmi"', scroll: '10m' #'supplements.org:Gates', scroll: '10m'
    res.supplement += 1
    console.log 'sup', 'oareport', res.supplement
    if sup.DOI
      if not await @oareport.works sup.DOI
        console.log sup.DOI
        res.missing.push sup.DOI
      else
        res.oareport += 1
    else
      res.nodoi += 1
      if sup.PMCID or sup.OPENALEX
        if exists = await @oareport.works (if sup.PMCID then 'ids.pmcid.keyword:"' + sup.PMCID + '"' else 'ids.openalex.keyword:"' + sup.OPENALEX + '"'), 1
          res.oareport += 1
          if exists.ids?.doi
            res.dedups += 1
            res.dedup[exists.ids.doi] ?= []
            res.dedup[exists.ids.doi].push(sup.PMCID) if sup.PMCID
            res.dedup[exists.ids.doi].push(sup.OPENALEX) if sup.OPENALEX
        else
          console.log sup.DOI, sup.PMCID, sup.OPENALEX
          res.missing.push if sup.PMCID then sup.PMCID else sup.OPENALEX
          if not sup.PMCID and olx = await @src.openalex.works 'id.keyword:"https://openalex.org/' + sup.OPENALEX + '"', 1
            if olx.id and olx.id.includes sup.OPENALEX
              res.olxnodoi += 1 if not olx.ids?.doi
              res.olxnopmcid += 1 if not olx.ids?.pmcid
              res.olxispreprint += 1 if olx.type is 'preprint'
      else
        res.noid += 1

  console.log res.supplement, res.oareport
  fs.writeFile '/home/oaw/static/oareport_check.json', JSON.stringify res, null, 2
  return res
#P.oareport.checkppmi._async = true
'''




'''P.oldemails = ->
  a1 = ''
  a2 = ''
  res = '"id","count","service","email"'
  counter = 0
  for user in await @fetch 'https://bg.api.oa.works/logs/terms/params.from.keyword?q=params.plugin:shareyourpaper%20OR%20params.plugin:instantill&apikey=' + a1
    console.log counter++, user
    email = ''
    service = ''
    try
      await @sleep 200
      old = await @fetch 'https://api.openaccessbutton.org/users/' + user.term + '?apikey=' + a2
      email = old.email if old?.email
      service = 'instantill' if old?.service?.openaccessbutton?.ill?
      service = 'shareyourpaper' if old?.service?.openaccessbutton?.shareyourpaper? or old?.service?.openaccessbutton?.syp? or old?.service?.openaccessbutton?.deposit?
    res += '\n"' + user.term + '","' + user.count + '","' + service + '","' + email + '"'
  return status: 200, headers: {'Content-Type': 'text/csv'}, body: res
P.oldemails._auth = '@oa.works'
'''

'''P.oareport.testfors = ->
  res = byindex: 0, byroute: 0, fromindex: [], fromroute: []
  for await r from @index._for 'paradigm_b_oareport_works', '*', until: 20, include: ['DOI']
    console.log res.byindex, res.byroute, r.DOI
    res.byindex += 1
    res.fromindex.push r
  for await p from await @oareport.works._for '*', until: 20, include: ['DOI']
    console.log res.byindex, res.byroute, p.DOI
    res.byroute += 1
    res.fromroute.push p
  return res'''


'''_works_map = new Map()
_works_map_last = Date.now() # generalise this into index? Could get quite big in memory, and is it any faster/better than update to ES?
P.oareport.works.update = (recs, previous, immediate) ->
  recs ?= @params.update ? @body
  if typeof recs is 'string'
    return _works_map.get(recs) ? @oareport.works recs
  
  recs = [recs] if not Array.isArray recs
  previous ?= []
  previous = [previous] if not Array.isArray previous
  for r of recs ? []
    rec = recs[r]
    rec._id = rec.DOI.toLowerCase().replace(/\//g, '_') if not rec._id and rec.DOI
    if rec?._id
      if work = _works_map.get(rec._id) ? previous[r] ? await @oareport.works rec._id
        for k of rec
          work[k] = rec[k] # cascade through complex objects, handle extra supps, etc
      else
      _works_map.set rec._id, rec
    else
      await @oareport.works rec

  now = Date.now()
  ws = _works_map.size
  if ws and (immediate or ws >= 10000 or _works_map_last < now - 600000)
    await @oareport.works [..._works_map.values()]
    _works_map = new Map() if ws >= 10000
    _works_map_last = now
  return work ? rec'''

#P.oareport.query = ->
#  qry = await @index.translate @params
#  qry.collapse = field: 'DOI.keyword'
#  console.log JSON.stringify qry
#  return @index._send 'src_crossref_works,paradigm_b_oareport_orgs_supplements/_search', qry

