

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
    return undefined

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
