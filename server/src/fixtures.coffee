
P.fixtures = ->
  # TODO may want this on live but only triggered by schedule, not URL
  if not @S.dev or not @params.trigger or not @S.static?.folder
    return note: 'Fixtures can only be dumped in dev mode with a static folder configured.'

  console.log 'Dumping data to fixtures'
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
  meta.started = Date.now() if not meta.restarted or not meta.started
  starter = meta.restarted ? meta.started # may not really be useful to keep track of previous start, but do for now
  await fs.writeFile @S.static.folder + "/fixtures/_meta.json", JSON.stringify(meta)
  for d in ['permissions_journals_transformative', 'permissions_journals', 'permissions_publishers', 'permissions_affiliations', 'src_doaj_journals', 'report_oapolicy', 'report_publishers', 'report_orgs', 'report_orgs_supplements']
    f = fs.createWriteStream @S.static.folder + '/fixtures/' + d + '.jsonl'
    console.log 'Dumping', d, 'to', f.path
    counter = 0
    for await r from @index._for d, undefined, undefined, (if d.includes('permissions_') or d.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config
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
