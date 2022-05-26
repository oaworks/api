
P.src.doaj = {}

P.src.doaj.journals = _index: true, _prefix: false

P.src.doaj.journals.load = () ->
  fldr = '/tmp/doaj_' + await @uid()
  await fs.mkdir fldr
  fldr += '/'
  await fs.writeFile fldr + 'doaj.tar', await @fetch 'https://doaj.org/public-data-dump/journal', buffer: true
  tar.extract file: fldr + 'doaj.tar', cwd: fldr, sync: true # extracted doaj dump folders end 2020-10-01
  current = false
  for f in await fs.readdir fldr
    current = f if f.includes 'doaj_journal_data'
  total = 0
  if current
    journals = JSON.parse await fs.readFile fldr + current + '/journal_batch_1.json'
    total = journals.length
    await @src.doaj.journals ''
    await @src.doaj.journals journals
    await fs.unlink fldr + current + '/journal_batch_1.json'
  await fs.rmdir fldr + current
  await fs.unlink fldr + 'doaj.tar'
  await fs.rmdir fldr
  return total

P.src.doaj.journals.load._bg = true
P.src.doaj.journals.load._async = true
P.src.doaj.journals.load._auth = 'root'


'''
P.src.doaj = (qry, params={}) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  #params.sort ?= 'bibjson.year:desc'
  url += op + '=' + params[op] + '&' for op of params
  return @fetch url # with a 400ms timeout

P.src.doaj.es = (params, which='journal,article') ->
  params ?= @params
  # which could be journal or article or journal,article
  # but doaj only allows this type of query on journal,article, so will add this later as a query filter
  url = 'https://doaj.org/query/journal,article/_search?ref=public_journal_article&'
  # this only works with a source param, if one is not present, should convert the query into a source param
  tr = await @index.translate @params
  tr = source: tr # unless doing a post, in which case don't do this part
  tr.source.aggs ?= {} # require this to get doaj to accept the query
  tr.source.query.filtered.query.bool.must.push({term: {_type: which}}) if which isnt 'journal,article'
  url += op + '=' + encodeURIComponent(JSON.stringify(tr[op])) + '&' for op of tr
  try
    return await @fetch url
  catch
    return {}

P.src.doaj.issn = (issn) ->
  issn ?= @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  r = await @src.doaj.journals 'bibjson.eissn.exact:"' + issn.join(' OR bibjson.eissn.exact:"') + '" OR bibjson.pissn.exact:"' + issn.join(' OR bibjson.pissn.exact:"') + '"'
  return if r.hits?.total then r.hits.hits[0]._source else undefined

P.src.doaj.doi = (doi) ->
  return @src.doaj.get 'doi:' + doi

P.src.doaj.title = (title) ->
  return @src.doaj.get 'title:"' + title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ') + '"'
'''

