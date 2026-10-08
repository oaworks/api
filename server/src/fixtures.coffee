
P.fixtures = ->
  # TODO may want this on live but only triggered by schedule, not URL
  if not @S.dev or not @params.trigger or not @S.static?.folder
    return note: 'Fixtures can only be dumped in dev mode with a static folder configured.'

  max = @params.max ? 100
  max = 0 if typeof max isnt 'number'

  # build a test set
  console.log 'Dumping test set to fixtures'
  tests = []
  DOIS = []
  if max and max > 0
    test_sheet = '1GQhgRCZ9ovfTN_wwKCvoAqf9QlO7ozcxScBgjEnpfl8/tests'
    # https://docs.google.com/spreadsheets/d/1GQhgRCZ9ovfTN_wwKCvoAqf9QlO7ozcxScBgjEnpfl8
    tests = await @src.google.sheets test_sheet
    for t in tests
      if DOIS.length >= max
        break
      if t.ID and t.ID.startsWith '10.'
        DOIS.push t.ID.split('__')[0] # clear the test suffix if present
        tests.push t

    f = fs.createWriteStream @S.static.folder + '/fixtures/report_works.jsonl'
    counter = 0
    for d in DOIS
      if typeof d is 'string' and d.startsWith '10.'
        if r = await @report.works d
          f.write('\n') if counter isnt 0
          f.write JSON.stringify r
          counter++
    f.end()
    meta.report_works = counter

    #f = fs.createWriteStream @S.static.folder + '/fixtures/tests_sheet_' + max + '.jsonl'
    #counter = 0
    #for t in tests
    #  if typeof t.ID is 'string' and t.ID.startsWith '10.'
    #    f.write('\n') if counter isnt 0
    #    f.write JSON.stringify t
    #    counter++
    #f.end()
    #meta.tests = counter

  console.log 'Dumping data to fixtures', max
  try
    await fs.stat @S.static.folder + "/fixtures"
  catch
    await fs.mkdir @S.static.folder + "/fixtures"
  meta = {}
  try meta = JSON.parse await fs.readFile @S.static.folder + "/fixtures/_meta.json"
  if meta.started and not meta.finished
    if not @params.clear
      console.log 'Previous fixture dump started but not finished'
      return note: 'There appears to be a dump in progress since ' + meta.started + ' ' + (new Date(meta.started).toISOString()) + '. You can force a restart by applying the ?clear param to this URL.'
    else
      nm = started: meta.started, restarted: Date.now()
      meta = nm
  #else # if not always producing the same file set, could delete
  #  for fn in await fs.readdir @S.static.folder + "/fixtures"
  #    continue if fn isnt '_meta.json'
  #    await fs.unlink @S.static.folder + "/fixtures/" + fn
  meta.started = Date.now() if not meta.restarted or not meta.started
  starter = meta.restarted ? meta.started # may not really be useful to keep track of previous start, but do for now
  await fs.writeFile @S.static.folder + "/fixtures/_meta.json", JSON.stringify(meta)
  for d in ['permissions_journals_transformative', 'permissions_journals', 'permissions_publishers', 'permissions_affiliations', 'src_doaj_journals', 'report_oapolicy', 'report_publishers', 'report_orgs', 'report_orgs_supplements']
    f = fs.createWriteStream @S.static.folder + '/fixtures/' + d + '.jsonl'
    console.log 'Dumping', d, 'to', f.path
    counter = 0
    qr = '*'
    if d is 'report_orgs_supplements'
      if max and max isnt -1
        qr = 'doi.keyword:"' + DOIS.join('" OR doi.keyword:"') + '"'
      else if max is 0
        qr = 'doi.keyword:"NEVERFINDME"' # for max zero we just write an empty supps file, so find no records
    for await r from @index._for d, qr, undefined, (if d.includes('permissions_') or d.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config
      f.write('\n') if counter isnt 0
      f.write JSON.stringify r
      counter++
    f.end()
    meta[d] = counter
    try
      im = JSON.parse await fs.readFile @S.static.folder + "/fixtures/_meta.json"
      if im.started isnt starter
        meta.break = Date.now()
        break

  meta.finished = Date.now()
  meta.took = meta.finished - meta.started
  if not meta.break
    await fs.writeFile @S.static.folder + "/fixtures/_meta.json", JSON.stringify meta
  return meta
