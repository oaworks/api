
P.fixtures.load = ->
  if not @S.dev or not @params.trigger
    return note: 'Fixtures can only be loaded in development mode.'
  
  res = {}
  folder = process.cwd() + '/fixtures'
  for fl in await fs.readdir folder
    continue if not fl.endsWith('.jsonl') or fl.includes 'tests'
    idx = fl.replace /\.jsonl$/, ''
    console.log 'Loading fixture', fl, 'into', idx
    res[idx] = 0
    batch = []
    # parse the idx name, split by _, use that as dot notation to find the function definition on @, and call it
    # e.g permissions_journals should map to @permissions.journals()
    parts = idx.split '_'
    fn = @
    fn = fn?[part] for part in parts
    if typeof fn is 'function'
      console.log 'Checking existence', idx
      console.log await fn() # if the index was never queried yet this initial call will create with any configured settings first, before we bulk load to it
    for await line from readline.createInterface input: fs.createReadStream(folder + '/' + fl), crlfDelay: Infinity
      continue if not line.trim()
      batch.push JSON.parse line
      res[idx] += 1
      if batch.length >= 5000
        # TODO get rid of the need for controlling prefix here, or at least use the fn defined above to read the _prefix config for it
        await @index._bulk idx, batch, undefined, undefined, (if idx.includes('permissions_') or idx.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config
        batch = []
    if batch.length > 0
      await @index._bulk idx, batch, undefined, undefined, (if idx.includes('permissions_') or idx.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config

  return res