
'''
P.src.doaj = {}

P.src.doaj.journals = (issn) ->
  if issn
    issn = issn.split(',') if typeof issn is 'string'
    r = await @fetch 'issn.exact:"' + issn.join(' OR issn.exact:"') + '"'
    return if r.hits?.total then r.hits.hits[0]._source else undefined
  else
    # doaj only updates their journal dump once a week so calling journal import
    # won't actually do anything if the dump file name has not changed since last run 
    # or if a refresh is called
    fldr = '/tmp/doaj/'
    fs.mkdirSync(fldr) if not fs.existsSync fldr
    try
      prev = false
      current = false
      fs.writeFileSync fldr + 'doaj.tar', await @fetch 'https://doaj.org/public-data-dump/journal'
      tar.extract file: fldr + 'doaj.tar', cwd: fldr, sync: true # extracted doaj dump folders end 2020-10-01
      for f in fs.readdirSync fldr # readdir alphasorts, so if more than one in tmp then last one will be newest
        if f.indexOf('doaj_journal_data') isnt -1
          if prev
            try fs.unlinkSync fldr + prev + '/journal_batch_1.json'
            try fs.rmdirSync fldr + prev
          prev = current
          current = f
      if current and (prev or refresh)
        return JSON.parse fs.readFileSync fldr + current + '/journal_batch_1.json'
    return []

P.src.doaj.journals._bg = true
#P.src.doaj.journals._index = true


P.src.doaj.articles = (qry) ->
  url = 'https://doaj.org/api/v1/search/articles'
  if typeof qry is 'string'
    qry += 'doi:' if qry.startsWith '10.'
    url += '/' + qry
  else
    url += '?'
    url += op + '=' + params[op] + '&' for op of params
  try
    res = await @fetch url # note for DOAJ this needs a 300ms limiter
    return res.results # is this the right location for doaj articles results?

P.src.doaj.articles.title = (title) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  return @src.doaj.articles 'title:"' + title + '"'
'''
