

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
  if ret.total
    res = ret.data[0]
    for i in ret.data
      if i.hasFullText is "true"
        res = i
        break
  if res?
    op = await @src.core.redirect res
    res.url = op.url
    res.redirect = op.redirect
  return res

P.src.core.search = (qrystr, from, size=10, format, timeout=API.settings.use?.core?.timeout ? API.settings.use?._timeout ? 10000) ->
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
    res = await @fetch url #, {timeout:timeout}
    rd = res.data.data
    if format
      for r of rd
        rd[r] = await @src.core.format rd[r]
    return { total: res.data.totalHits, data: rd}

P.src.core.redirect = (record) ->
  res = {}
  if record.fulltextIdentifier
    res.url = record.fulltextIdentifier
  else
    for u in record.fulltextUrls
      if u.indexOf('core.ac.uk') isnt -1
        res.url = u
        break
      else
        resolved = await @resolve u
        if resolved and resolved.indexOf('.pdf') isnt -1
          res.url = resolved
  return res

P.src.core.format = (rec, metadata={}) ->
  try metadata.title ?= rec.title
  try metadata.doi ?= rec.doi
  try
    metadata.author ?= []
    for ar in rec.authors
      as = ar.split(' ')
      a = {name: ar, given:as[0]}
      try a.family = as[as.length-1]
      metadata.author.push a
  try metadata.publisher ?= rec.publisher
  try
    metadata.published ?= rec.datePublished
    if metadata.published.indexOf('-') is -1
      if metadata.published.toString().length is 4
        metadata.year = metadata.published
        metadata.published += '-01-01'
      else
        delete metadata.published
    else
      parts = metadata.published.split '-'
      if parts[0].length is 4
        if parts.length is 2
          parts.push '01'
        if parts.length is 1
          parts.push '01'
          parts.push '01'
        metadata.published = parts.join '-'
      else
        delete metadata.published
  try
    metadata.year ?= rec.year
    metadata.year = metadata.year.toString() if typeof metadata.year is 'number'
    delete metadata.year if typeof metadata.year isnt 'string' or metadata.year.length isnt 4
    try
      if not metadata.published? and metadata.year?
        metadata.published = metadata.year + '-01-01'
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  try metadata.open ?= rec.open
  try metadata.redirect ?= rec.redirect
  return metadata

