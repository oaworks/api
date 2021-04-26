

P.svc.oaworks.journal = (q) ->
  try
    if not q? and @params.journal or @params.issn
      q = '"' + (@params.journal ? @params.issn) + '"'
  # search the old journal index endpoint until this gets updated
  #crj = await @src.crossref.journals q
  #drj = await @src.doaj.journals q
  try
    res = await @fetch 'https://dev.api.cottagelabs.com/service/jct/journal?q=' + q
    return res.hits.hits[0]._source
  catch
    return undefined

P.svc.oaworks.oapublisher = (publisher) ->
  try publisher ?= @params.publisher
  tc = await @fetch 'https://dev.api.cottagelabs.com/service/jct/journal?q=publisher:"' + publisher + '" AND NOT discontinued:true'
  oac = await @fetch 'https://dev.api.cottagelabs.com/service/jct/journal?q=publisher:"' + publisher + '" AND NOT discontinued:true AND isdoaj:true'
  return tc.hits.total is oac.hits.total
