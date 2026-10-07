
P.fixtures.load = ->
  if not @S.dev or not @params.trigger
    return note: 'Fixtures can only be loaded in development mode.'
  
  res = {}
  folder = process.cwd() + '/fixtures'
  for fl in await fs.readdir folder
    continue if not fl.endsWith '.jsonl'
    idx = fl.replace /\.jsonl$/, ''
    console.log 'Loading fixture', fl, 'into', idx
    res[idx] = 0
    batch = []
    for await line from readline.createInterface input: fs.createReadStream(folder + '/' + fl), crlfDelay: Infinity
      continue if not line.trim()
      batch.push JSON.parse line
      res[idx] += 1
      if batch.length >= 10000
        await @index._bulk idx, batch, undefined, undefined, (if idx.includes('permissions_') or idx.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config
        batch = []
    if batch.length > 0
      await @index._bulk idx, batch, undefined, undefined, (if idx.includes('permissions_') or idx.includes('src_doaj_') then false else undefined) # no prefix for these - for now, want to change this config

  return res