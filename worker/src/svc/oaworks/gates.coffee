
P.svc.oaworks.gates = () ->
  if @refresh
    @svc.oaworks.gates.oacheck undefined, undefined, undefined, undefined, true
    return true
  else if @format is 'html'
    return 'I will be a nice HTML UI listing the links to trigger updates and listing the result files'
  else
    return 'OA.works Gates project API parts placeholder'

P.svc.oaworks.gates.awards = (kind, q, total) -> # kind can be opp or inv, which will both be uppercased
  kind ?= @params.kind ? 'opp'
  kind = kind.toLowerCase()
  kind = kind.replace('ids') if kind.endsWith 'ids'
  total ?= @params.total
  q ?= @params.q ? 'type:"journal-article" AND funder.award:*' + (if kind then kind.toUpperCase() + '*' else '')
  matchers = [
    /Melinda\sGates\sFoundation/g,
    /Gates\sCambridge\sTrust/g,
    /investment\s?id\s?\d{5}/gi,
    /OPPG[HD]\s?\d{4}/g,
    /OPP\s?1\s?\d{6}/g,
    /OPP\s?[45]\s?\d{4}/g,
    /INV\‐\d{6}/g
  ]
  fn = '/home/cloo/static/gates/' + (if kind then kind + 'ids' else 'awards') + '.csv'
  await fs.writeFile fn, '"DOI","Paper title","Journal title","ISSN","Publisher name","Published date","Published year","Funder","Crossref_OA","Matches"'
  #res = []
  counter = 0
  from = 0
  size = 1000
  #cr = await @src.crossref.works q, 
  cr = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + q, params: {size: size, from: from}
  try console.log cr.hits.total
  #while cr?.hits?.hits and cr.hits.hits.length and (not total or res.length < total)
  while cr?.hits?.hits and cr.hits.hits.length and (not total or counter < total)
    for r in cr.hits.hits
      #break if total and res.length is total
      break if total and counter is total
      counter += 1
      rec = r._source
      #rs = DOI: rec.DOI
      #rs['Paper title'] = rec.title[0]
      #rs['Journal title'] = rec['container-title'][0]
      #rs.ISSN = rec.ISSN.join ', '
      #rs['Publisher name'] = rec.publisher ? ''
      #rs['Published date'] = rec.published ? ''
      #rs['Published year'] = rec.year ? ''
      #rs.Funder = ''
      Funder = ''
      for funder in rec.funder
        Funder += '\n' if Funder.length
        Funder += funder.name + (if funder.award and funder.award.length then ' (' + funder.award.join(', ') + ')' else '')
      #rs['Crossref_OA'] = rec.is_oa ? ''
      #rs.Matches = ''
      Matches = ''
      try
        ex = await @tdm.extract content: JSON.stringify(rec), matchers: matchers
        if ex.matched
          for lm in ex.matches
            Matches += '\n' if Matches isnt ''
            Matches += lm.matched + ': ' + lm.result.join ', '
      #res.push rs
      await fs.appendFile fn, '\n"' + rec.DOI + '","' + (if rec.title then rec.title[0].replace(/"/g, '') else '') + '","' + (if rec['container-title'] then rec['container-title'][0].replace(/"/g, '') else '') + '","' + (if rec.ISSN then rec.ISSN.join(', ') else '') + '","' + (if rec.publisher then rec.publisher.replace(/"/g, '') else '') + '","' + (rec.published ? '') + '","' + (rec.year ? '') + '","' + Funder.replace(/"/g, '') + '","' + (rec.is_oa ? '') + '","' + Matches + '"'
    from += size
    #cr = await @src.crossref.works q, {size: size, from: from}
    cr = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + q, params: {size: size, from: from}
  #await fs.writeFile '/home/cloo/static/gates/' + (if kind then kind + 'ids' else 'awards') + '.csv', await @convert.json2csv res
  return counter #res.length

P.svc.oaworks.gates.oppids = (q, total) -> return @svc.oaworks.gates.awards 'opp', q, total
P.svc.oaworks.gates.invids = (q, total) -> return @svc.oaworks.gates.awards 'inv', q, total
  
P.svc.oaworks.gates.funders = (funder, q, total) ->
  funder ?= @params.funders ? @params.funder ? 'Melinda Gates Foundation'
  funder = funder.replace /"/g, ''
  fl = funder.toLowerCase()
  total ?= @params.total
  q ?= @params.q ? 'type:"journal-article" AND (author.affiliation.name:"' + funder + '" OR funder.name:"' + funder + '")'
  counter = 0
  await fs.writeFile '/home/cloo/static/gates/funders.csv', '"DOI","Affiliation","Funder","Paper title","Journal Title","ISSN","Publisher name","Published date","Published year","Crossref_OA"'
  from = 0
  size = 1000
  #cr = await @src.crossref.works q, {size: size, from: from}
  cr = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + q, params: {size: size, from: from}
  try console.log cr.hits.total
  while cr?.hits?.hits and cr.hits.hits.length and (not total or counter < total)
    for r in cr.hits.hits
      break if total and counter is total
      counter += 1
      rec = r._source
      affiliation = 'false'
      funder = 'false'
      for a in rec.author ? []
        for aff in a.affiliation ? []
          if aff.name and aff.name.toLowerCase().indexOf(fl) isnt -1
            affiliation = aff.name
            break
      for f in rec.funder ? []
        if f.name and f.name.toLowerCase().indexOf(fl) isnt -1
          funder = f.name
          break
      await fs.appendFile '/home/cloo/static/gates/funders.csv', '\n"' + rec.DOI + '","' + affiliation.replace(/"/g, '') + '","' + funder.replace(/"/g, '') + '","' + (if rec.title then rec.title[0].replace(/"/g, '') else '') + '","' + (if rec['container-title'] then rec['container-title'][0].replace(/"/g, '') else '') + '","' + (if rec.ISSN then rec.ISSN.join(', ') else '') + '","' + (rec.publisher ? '') + '","' + (rec.published ? '') + '","' + (rec.year ? '') + '","' + (rec.is_oa ? '') + '"'
    from += size
    #cr = await @src.crossref.works q, {size: size, from: from}
    cr = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + q, params: {size: size, from: from}
  return counter

P.svc.oaworks.gates.oacheck = (urls, q, funder, total, all) ->
  total ?= @params.total
  all ?= @params.all
  if all
    await @svc.oaworks.gates.oppids q, total
    await @svc.oaworks.gates.invids q, total
    await @svc.oaworks.gates.funders funder, q, total
  dois = []
  doimatches = {}
  croa = {}
  #urls ?= @params.url ? @params.urls ? 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRdIku4CJK7_do57W06sr34lLwExpjuGGFQV8bBeKoAG2Wt5pXNm3_FMDjjFt7R9C9miWO6Dn3DI-zN/pub?gid=1831154623&single=true&output=csv'
  #urls = []
  #for url in (if typeof urls is 'string' then urls.replace(/\s/g, '').split(',') else urls)
  #  content = await @fetch url
  #  for row in content.split '\n'
  #    d = row.replace(/\s/g, '').split(',')[0].replace(/"/g, '').trim()
  #    dois.push(d) if d.startsWith('10.') and d.indexOf('/') isnt -1 and d not in dois
  #for row in await @convert.csv2json 'https://github.com/oaworks/Gates/files/6410205/OACheck._.Gates.Dev.-.01_05_2021.csv'

  done = []
  #await fs.writeFile '/home/cloo/static/gates/oacheck_fixed.csv', '"DOI","in_oadoi","journal_oa_status","Crossref_OA","best_oa_location_url","best_oa_location_url_for_pdf","is_oa","oa_status","has_repository_copy","repository_license","repository_url_for_pdf","repository_url","repository_version","publisher_license","publisher_url_for_pdf","publisher_version","Paper title","Journal Title","ISSN","Publisher name","Published date","Published year","Matches"'
  for d in (await fs.readFile '/home/cloo/static/gates/oacheck_rererun.csv').toString().split '\n'
    dd = d.replace(/"/g, '').split(',')[0].trim()
    if dd.startsWith('10.') and dd.indexOf('/') isnt -1 and dd not in done
      done.push dd
      #await fs.appendFile '/home/cloo/static/gates/oacheck_fixed.csv', '\n' + d
  console.log done.length

  #fn = '/home/cloo/static/gates/oacheck_gates_dev_63.csv'
  out = '/home/cloo/static/gates/oacheck_rererun_opps_invs.csv'

  #for row in (await fs.readFile fn).toString().split '\n'
  #  row = row.replace(/"/g, '').trim()
  #  dois.push(row) if row.startsWith('10.') and row.indexOf('/') isnt -1 and row not in dois and row not in done
  #console.log dois.length

  for fn in ['oppids.csv', 'invids.csv', 'funders.csv']
    for fr in await @convert.csv2json (await fs.readFile '/home/cloo/static/gates/' + fn).toString()
      if not fr.DOI.startsWith '10.'
        console.log fr.DOI
      else if fr.DOI not in done
        dois.push(fr.DOI) if fr.DOI not in dois
        croa[fr.DOI] = fr.Crossref_OA if fr.Crossref_OA? and not croa[fr.DOI]
        doimatches[fr.DOI] = fr.Matches if fr.Matches? and not doimatches[fr.DOI]
    console.log fn, dois.length

  await fs.writeFile out, '"DOI","in_oadoi","journal_oa_status","Crossref_OA","best_oa_location_url","best_oa_location_url_for_pdf","is_oa","oa_status","has_repository_copy","repository_license","repository_url_for_pdf","repository_url","repository_version","publisher_license","publisher_url_for_pdf","publisher_version","Paper title","Journal Title","ISSN","Publisher name","Published date","Published year","Matches"'
  counter = 0
  for doi in dois
    break if @params.total and counter is @params.total
    counter += 1
    if oadoi = await @src.oadoi doi # ensure this is refreshed
      journal_oa_status = if oadoi.oa_status is 'gold' then 'gold' else if oadoi.oa_status is 'bronze' then 'closed' else if oadoi.oa_status is 'hybrid' then 'hybrid' else ''
      if journal_oa_status is 'hybrid' and oadoi.journal_issns
        for issn in (if typeof oadoi.journal_issns is 'string' then oadoi.journal_issns.split(',') else oadoi.journal_issns)
          try
            tj = await @fetch 'https://api.journalcheckertool.org/tj/' + issn
            if tj.transformative_journal is true
              journal_oa_status = 'transformative'
              break
      has_publisher_host_type = false
      repository_license = ''
      repository_url_for_pdf = ''
      repository_url = '' # only for repository
      repository_version = ''
      publisher_license = ''
      publisher_url_for_pdf = ''
      publisher_version = ''
      pmc = false
      for loc in oadoi.oa_locations ? []
        if loc.host_type is 'publisher'
          has_publisher_host_type = true
          publisher_license = loc.license if loc.license and publisher_license is ''
          publisher_url_for_pdf = loc.url_for_pdf if loc.url_for_pdf and publisher_url_for_pdf is ''
          publisher_version = loc.version if loc.version and publisher_version is ''
        if loc.host_type is 'repository'
          repository_license = loc.license if loc.license and (repository_license is '' or pmc is false)
          repository_url_for_pdf = loc.url_for_pdf if loc.url_for_pdf and (repository_url_for_pdf is '' or pmc is false)
          repository_url = loc.url if loc.url and (repository_url is '' or pmc is false)
          repository_version = loc.version if loc.version and (repository_version is '' or pmc is false)
          pmc = true if repository_url.indexOf('pmc') isnt -1
      journal_oa_status = 'closed' if not has_publisher_host_type
      await fs.appendFile out, '\n"' + doi + '","true","' + journal_oa_status + '","' + (croa[doi] ? '') + '","' + (oadoi.best_oa_location?.url ? '') + '","' + (oadoi.best_oa_location?.url_for_pdf ? '') + '","' + (oadoi.is_oa ? '') + '","' + (oadoi.oa_status ? '') + '","' + (oadoi.has_repository_copy ? '') + '","' + repository_license + '","' + repository_url_for_pdf + '","' + repository_url + '","' + repository_version + '","' + publisher_license + '","' + publisher_url_for_pdf + '","' + publisher_version + '","' + (oadoi.title ? '') + '","' + (oadoi.journal_name ? '') + '","' + (oadoi.journal_issns ? '') + '","' + (oadoi.publisher ? '') + '","' + (oadoi.published_date ? '') + '","' + (oadoi.year ? '') + '","' + (doimatches[doi] ? '') + '"'
    else
      await fs.appendFile out, '\n"' + doi + '","false","","' + (croa[doi] ? '') + '","","","","","","","","","","","","","","","","","","' + (doimatches[doi] ? '') + '"'
    console.log counter
  @mail
    to: 'mark@oa.works'
    subject: 'Gates OA check done ' + counter
    text: 'https://static.oa.works/gates'
  return counter

P.svc.oaworks.gates._hides = true
P.svc.oaworks.gates.awards._bg = true
P.svc.oaworks.gates.awards._hide = true
P.svc.oaworks.gates.awards._async = true
P.svc.oaworks.gates.oppids._bg = true
P.svc.oaworks.gates.oppids._async = true
P.svc.oaworks.gates.invids._bg = true
P.svc.oaworks.gates.invids._async = true
P.svc.oaworks.gates.funders._bg = true
P.svc.oaworks.gates.funders._async = true
P.svc.oaworks.gates.oacheck._bg = true
P.svc.oaworks.gates.oacheck._async = true




P.svc.oaworks.gates.recheck = () ->
  out = '/home/cloo/static/gates/rerecheck.csv'
  await fs.writeFile out, '"DOI","in_oadoi","journal_oa_status","Crossref_OA","best_oa_location_url","best_oa_location_url_for_pdf","is_oa","oa_status","has_repository_copy","repository_license","repository_url_for_pdf","repository_url","repository_version","publisher_license","publisher_url_for_pdf","publisher_version","Paper title","Journal Title","ISSN","Publisher name","Published date","Published year","Matches","Recheck"'
  counter = 0
  for d in (await fs.readFile '/home/cloo/static/gates/oacheck_rererun.csv').toString().split '\n"10.'
    parts = d.split '","'
    doi = '10.' + parts[0].replace /"/g, ''
    if counter is 0
      counter += 1 # skip the headers line
    else
      break if @params.total and counter is @params.total + 1
      counter += 1
      wasinoadoi = parts[1].replace /"/g, ''
      hadjournaloastatus = parts[2].replace /"/g, ''
      redo = if wasinoadoi is 'false' then 'notfound' else if hadjournaloastatus is 'closed' then 'closed' else false
      console.log counter, doi, wasinoadoi, hadjournaloastatus
      if redo
        croad = parts[3].replace /"/g, ''
        doid = parts[parts.length-1].replace /"/g, ''
        if oadoi = await @src.oadoi doi
          journal_oa_status = if oadoi.oa_status is 'gold' then 'gold' else if oadoi.oa_status is 'bronze' then 'closed' else if oadoi.oa_status is 'hybrid' then 'hybrid' else ''
          if journal_oa_status is 'hybrid' and oadoi.journal_issns
            for issn in (if typeof oadoi.journal_issns is 'string' then oadoi.journal_issns.split(',') else oadoi.journal_issns)
              try
                tj = await @fetch 'https://api.journalcheckertool.org/tj/' + issn
                if tj.transformative_journal is true
                  journal_oa_status = 'transformative'
                  break
          has_publisher_host_type = false
          repository_license = ''
          repository_url_for_pdf = ''
          repository_url = '' # only for repository
          repository_version = ''
          publisher_license = ''
          publisher_url_for_pdf = ''
          publisher_version = ''
          pmc = false
          for loc in oadoi.oa_locations ? []
            if loc.host_type is 'publisher'
              has_publisher_host_type = true
              publisher_license = loc.license if loc.license and publisher_license is ''
              publisher_url_for_pdf = loc.url_for_pdf if loc.url_for_pdf and publisher_url_for_pdf is ''
              publisher_version = loc.version if loc.version and publisher_version is ''
            if loc.host_type is 'repository'
              repository_license = loc.license if loc.license and (repository_license is '' or pmc is false)
              repository_url_for_pdf = loc.url_for_pdf if loc.url_for_pdf and (repository_url_for_pdf is '' or pmc is false)
              repository_url = loc.url if loc.url and (repository_url is '' or pmc is false)
              repository_version = loc.version if loc.version and (repository_version is '' or pmc is false)
              pmc = true if repository_url.indexOf('pmc') isnt -1
          journal_oa_status = 'closed' if not has_publisher_host_type
          await fs.appendFile '/home/cloo/static/gates/recheck.csv', '\n"' + doi + '","true","' + journal_oa_status + '","' + croad + '","' + (oadoi.best_oa_location?.url ? '') + '","' + (oadoi.best_oa_location?.url_for_pdf ? '') + '","' + (oadoi.is_oa ? '') + '","' + (oadoi.oa_status ? '') + '","' + (oadoi.has_repository_copy ? '') + '","' + repository_license + '","' + repository_url_for_pdf + '","' + repository_url + '","' + repository_version + '","' + publisher_license + '","' + publisher_url_for_pdf + '","' + publisher_version + '","' + (oadoi.title ? '') + '","' + (oadoi.journal_name ? '') + '","' + (oadoi.journal_issns ? '') + '","' + (oadoi.publisher ? '') + '","' + (oadoi.published_date ? '') + '","' + (oadoi.year ? '') + '","' + doid + '","' + redo + '"'
        else
          await fs.appendFile out, '\n"' + doi + '","false","","' + croad + '","","","","","","","","","","","","","","","","","","' + doid + '","' + redo + '"'
      else
        await fs.appendFile out, '\n"10.' + d + ',""'
  @mail
    to: 'mark@oa.works'
    subject: 'Gates OA recheck done ' + counter
    text: 'https://static.oa.works/gates'
  return counter

P.svc.oaworks.gates.recheck._bg = true
P.svc.oaworks.gates.recheck._async = true
