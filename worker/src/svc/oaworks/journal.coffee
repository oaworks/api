

P.svc.oaworks.journal = (q) ->
  try
    if not q? and @params.journal or @params.issn
      q = '"' + (@params.journal ? @params.issn) + '"'
  # search the old journal index endpoint until this gets updated
  #crj = await @src.crossref.journals q
  #drj = await @src.doaj.journals q
  try
    res = await @fetch 'https://api.jct.cottagelabs.com/journal?q=' + q
    return res.hits.hits[0]._source
  catch
    return

P.svc.oaworks.journal.oa = (issn) ->
  # NOTE it is still to be decided what licence is acceptable to be counted as OA on the crossref index. For now it's anything CC, including NC
  try issn ?= @params.journal ? @params.issn ? @params.oa
  tc = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=type.exact:"journal-article" AND ISSN.exact:"' + issn + '"'
  oac = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=type.exact:"journal-article" AND ISSN.exact:"' + issn + '" AND is_oa:true' # could add AND NOT licence:nc
  return tc.hits.total is oac.hits.total and (tc.hits.total isnt 0 or oac.hits.total isnt 0)

P.svc.oaworks.publisher = {}
P.svc.oaworks.publisher.oa = (publisher) ->
  try publisher ?= @params.publisher ? @params.oa
  tc = await @fetch 'https://api.jct.cottagelabs.com/journal?q=publisher:"' + publisher.replace(/&/g, '') + '" AND NOT discontinued:true'
  oac = await @fetch 'https://api.jct.cottagelabs.com/journal?q=publisher:"' + publisher.replace(/&/g, '') + '" AND NOT discontinued:true AND indoaj:true'
  return tc? and oac? and tc.hits?.total is oac.hits?.total and (tc.hits.total isnt 0 or oac.hits.total isnt 0)



'''
P.svc.oaworks.journal.import = () ->
  fldr = '/tmp/jct_doaj/'
  if not await fs.exists fldr
    await fs.mkdir fldr
  ret = false
  prev = false
  current = false
  await fs.writeFile fldr + 'doaj.tar', await @fetch 'https://doaj.org/public-data-dump/journal' #{npmRequestOptions:{encoding:null}}
  tar.extract file: fldr + 'doaj.tar', cwd: fldr, sync: true # extracted doaj dump folders end 2020-10-01
  for f in await fs.readdir fldr # readdir alphasorts, so if more than one in tmp then last one will be newest
    if f.includes 'doaj_journal_data'
      if prev
        try await fs.unlink fldr + prev + '/journal_batch_1.json'
        try await fs.rmdir fldr + prev
      prev = current
      current = f

    removed = false
    total = 0
    counter = 0
    batch = []
    while total is 0 or counter < total
      if batch.length >= 10000 or (removed and batch.length >= 5000)
        if not removed
          await @svc.oaworks.journal ''
          removed = true
        await @svc.oaworks.journal batch
        batch = []
      try
        url = 'https://api.crossref.org/journals?offset=' + counter + '&rows=' + 1000
        res = await @fetch url, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}
        total = res.data.message['total-results'] if total is 0
        for rec in res.data.message.items
          if rec.ISSN and rec.ISSN.length and typeof rec.ISSN[0] is 'string'
            rec.crossref = true
            rec.issn = []
            for i in rec.ISSN
              rec.issn.push(i) if typeof i is 'string' and i.length and i not in rec.issn
            rec.dois = rec.counts?['total-dois']
            if rec.breakdowns?['dois-by-issued-year']?
              rec.years = []
              for yr in rec.breakdowns['dois-by-issued-year']
                rec.years.push(yr[0]) if yr.length is 2 and yr[0] not in rec.years
              rec.years.sort()
            if not rec.years? or not rec.years.length or not rec.dois
              rec.discontinued = true
            else
              thisyear = new Date().getFullYear()
              if thisyear not in rec.years and (thisyear-1) not in rec.years and (thisyear-2) not in rec.years and (thisyear-3) not in rec.years
                rec.discontinued = true
            batch.push rec
        counter += 1000
    if batch.length
      await @svc.oaworks.journal batch
      batch = []
    
    # then load the DOAJ data from the file (crossref takes priority because it has better metadata for spotting discontinuations)
    # only about 20% of the ~15k are not already in crossref, so do updates then bulk load the new ones
    imports = 0
    for rec in JSON.parse await fs.readFile fldr + current + '/journal_batch_1.json'
      imports += 1
      qr = if typeof rec.bibjson.pissn is 'string' then 'issn.exact:"' + rec.bibjson.pissn + '"' else ''
      if typeof rec.bibjson.eissn is 'string'
        qr += ' OR ' if qr isnt ''
        qr += 'issn.exact:"' + rec.bibjson.eissn + '"'
      if exists = jct_journal.find qr
        upd = doaj: rec
        upd.indoaj = true
        upd.discontinued = true if rec.bibjson.discontinued_date or rec.bibjson.is_replaced_by
        upd.issn = [] # DOAJ ISSN data overrides crossref because we've seen errors in crossref that are correct in DOAJ such as 1474-9728
        upd.issn.push(rec.bibjson.pissn.toUpperCase()) if typeof rec.bibjson.pissn is 'string' and rec.bibjson.pissn.length and rec.bibjson.pissn.toUpperCase() not in upd.issn
        upd.issn.push(rec.bibjson.eissn.toUpperCase()) if typeof rec.bibjson.eissn is 'string' and rec.bibjson.eissn.length and rec.bibjson.eissn.toUpperCase() not in upd.issn
        jct_journal.update exists._id, upd
      else
        nr = doaj: rec, indoaj: true
        nr.title ?= rec.bibjson.title
        nr.publisher ?= rec.bibjson.publisher.name if rec.bibjson.publisher?.name?
        nr.discontinued = true if rec.bibjson.discontinued_date or rec.bibjson.is_replaced_by
        nr.issn ?= []
        nr.issn.push(rec.bibjson.pissn.toUpperCase()) if typeof rec.bibjson.pissn is 'string' and rec.bibjson.pissn.toUpperCase() not in nr.issn
        nr.issn.push(rec.bibjson.eissn.toUpperCase()) if typeof rec.bibjson.eissn is 'string' and rec.bibjson.eissn.toUpperCase() not in nr.issn
        batch.push nr
    if batch.length
      await @svc.oaworks.journal batch
      batch = []

    return jct_journal.count()

P.svc.oaworks.journal.import._bg = true
'''
