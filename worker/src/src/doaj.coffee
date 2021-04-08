
P.src.doaj = {}

P.src.doaj.journals = (issn) ->
  issn ?= @params.journals ? @params.issn
  if issn
    try
      res = await @fetch 'https://doaj.org/api/v2/search/journals/' + issn
      return res.results[0]

P.src.doaj.articles = (qry) ->
  url = 'https://doaj.org/api/v1/search/articles'
  try title = @params.title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace /\s\s+/g, ' '
  if title or typeof qry is 'string'
    qry += 'doi:' if qry.startsWith '10.'
    url += '/' + title ? qry
  else
    url += '?'
    url += op + '=' + params[op] + '&' for op of params
  res = await @fetch url # note for DOAJ this needs a 300ms limiter
  return res.results

