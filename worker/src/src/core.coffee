
# core docs:
# http://core.ac.uk/docs/
# http://core.ac.uk/docs/#!/articles/searchArticles
# http://core.ac.uk:80/api-v2/articles/search/doi:"10.1186/1471-2458-6-309"

P.src.core = {}
P.src.core.doi = (doi) ->
  return @src.core.get 'doi:"' + doi + '"'

P.src.core.title = (title) ->
  try title = title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ')
  return @src.core.get 'title:"' + title + '"'

P.src.core.get = (qrystr) ->
  ret = await @src.core.search qrystr
  if ret?.total
    res = ret.data[0]
    for i in ret.data
      if i.hasFullText is "true"
        res = i
        break
  return res

P.src.core.search = (qrystr, from, size=10) ->
  # assume incoming query string is of ES query string format
  # assume from and size are ES typical
  # but core only accepts certain field searches:
  # title, description, fullText, authorsString, publisher, repositoryIds, doi, identifiers, language.name and year
  # for paging core uses "page" from 1 (but can only go up to 100?) and "pageSize" defaulting to 10 but can go up to 100
  apikey = @S.src.core?.apikey
  return undefined if not apikey
  #var qry = '"' + qrystr.replace(/\w+?\:/g,'') + '"'; # TODO have this accept the above list
  url = 'http://core.ac.uk/api-v2/articles/search/' + qrystr + '?urls=true&apiKey=' + apikey
  url += '&pageSize=' + size if size isnt 10
  url += '&page=' + (Math.floor(from/size)+1) if from
  try
    res = await @fetch url #, {timeout: 10000}
    return total: res.data.totalHits, data: res.data.data
