
# http://zenodo.org/dev
# https://zenodo.org/api/deposit/depositions
# api key required: http://zenodo.org/dev#restapi-auth
# requires a token be provided as query param on all requests, called ?access_token=

# access token would require deposit:write and deposit:actions permission in order to deposit something AND then publish it

# need to POST create a deposition, then POST upload files to the deposition, then POST publish the deposition

P.src.zenodo = deposition: {}, records: {}

# zenodo can now be searched, technically in test, at zenodo.org/api/records
# see search page for instructions (it is ES) https://help.zenodo.org/guides/search/
P.src.zenodo.records.search = (q, dev) ->
  # it does have sort but does not seem to parse direction yet, so not much use sorting on publication_date
  # does not seem to do paging or cursors yet either - but size works
  q ?= @params
  dev ?= @params.dev
  size = @params.size ? 10
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/records?size=' + size + '&q=' + encodeURIComponent q # just do simple string queries for now
  return @fetch url # could do a post if q is more complex... so far this just returns an ES search endpoint

P.src.zenodo.records.record = (zid, dev) ->
  zid ?= @params.record ? @params.id
  dev ?= @params.dev
  return @fetch 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/records/' + zid

P.src.zenodo.records.get = (q, dev) ->
  q ?= @params.get
  dev ?= @params.dev
  r = await @src.zenodo.records.search q, dev
  try
    return r.hits.hits[0] # appears to be the complete record so no need to get from /api/records/CONCEPTRECID
  catch
    return

P.src.zenodo.records.doi = (doi, dev) ->
  doi ?= @params.doi
  dev ?= @params.dev
  return @src.zenodo.records.get 'doi:"' + doi + '"', dev

P.src.zenodo.records.title = (title, dev) ->
  title ?= @params.title
  dev ?= @params.dev
  return @src.zenodo.records.get 'title:"' + title + '"', dev

P.src.zenodo.records.format = (rec) ->
  rec ?= @params
  metadata = {}
  try metadata.pdf ?= rec.pdf
  try metadata.url ?= rec.url
  metadata.doi ?= rec.doi
  try 
    if typeof rec.metadata.publication_date is 'string' and rec.metadata.publication_date.split('-').length is 3
      metadata.published = rec.metadata.publication_date
      try metadata.year = metadata.published.split('-')[0]
  try metadata.title ?= rec.metadata.title
  try metadata.journal ?= rec.metadata.journal.title
  try metadata.issue ?= rec.metadata.journal.issue
  try metadata.page ?= rec.metadata.journal.pages
  try metadata.volume ?= rec.metadata.journal.volume
  try metadata.keyword ?= rec.metadata.keywords
  try metadata.licence ?= rec.metadata.license.id
  try metadata.abstract = await @convert.html2txt rec.metadata.description
  try
    if rec.metadata.access_right = "open"
      metadata.url ?= if rec.files? and rec.files.length and rec.files[0].links?.self? then rec.files[0].links.self else rec.links.html
      metadata.open ?= metadata.url
  try
    for f in rec.files
      if f.type is 'pdf'
        metadata.pdf ?= f.links.self
        break
  try
    metadata.author ?= []
    for a in rec.metadata.creators
      a = {name: a} if typeof a is 'string'
      if a.name? and a.name.toLowerCase() isnt 'unknown'
        as = a.name.split ' '
        try a.family = as[as.length-1]
        try a.given = a.name.replace(a.family,'').trim()
      if a.affiliation?
        a.affiliation = a.affiliation[0] if _.isArray a.affiliation
        a.affiliation = {name: a.affiliation} if typeof a.affiliation is 'string'
      metadata.author.push a
  return metadata

P.src.zenodo.deposition.create = (metadata, up, token, dev) ->
  # https://zenodo.org/dev#restapi-rep-meta
  dev ?= @params.dev ? @S.dev
  token ?= @params.token
  token ?= if dev then @S.src?.zenodo?.sandbox else @S.src?.zenodo?.token
  metadata ?= @params.metadata # or try to retrieve from oaworks.metadata?
  return false if not token? or not metadata? or not metadata.title? or not metadata.description?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions?access_token=' + token
  data = {metadata: metadata}
  if not data.metadata.upload_type
    data.metadata.upload_type = 'publication'
    data.metadata.publication_type = 'article'
  # required field, will blank list work? If not, need object with name: Surname, name(s) and optional affiliation and creator
  data.metadata.creators ?= [{name:"Works, Open Access"}]
  if up?
    rs = await @fetch url, method: 'POST', body: data
    rs.uploaded = await @src.zenodo.deposition.upload(rs.id, up.content, up.file, up.name, up.url, token, dev) if rs?.id? and (up.content or up.file)
    rs.published = await @src.zenodo.deposition.publish(rs.id, token, dev) if up.publish
    return rs
  else
    # returns a zenodo deposition resource, which most usefully has an .id parameter (to use to then upload files to)
    return await @fetch url, method: 'POST', body: data

P.src.zenodo.deposition.upload = (id, content, file, filename, url, token, dev) ->
  id ?= @params.upload ? @params.id
  content ?= @params.content
  filename ?= @params.filename
  if not content and not file
    try file = @request.files[0]
  if url and not content and not file
    try content = await @fetch url, buffer: true
  token ?= @params.token
  token ?= if @S.dev or dev then @S.src.zenodo?.sandbox else @S.src?.zenodo?.token
  dev ?= @params.dev
  return false if not token? or not id?
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/files?access_token=' + token
  return @fetch url, file: (content ? file), filename: filename
# NOTE this should not only be run on backend, it should be contacted directly on backend via a DNS pass-through at cloudflare
# because cloudflare will limit the size of files getting POSTed through. Or whatever method calls this one should be directly contacted on backend

P.src.zenodo.deposition.publish = (id, token, dev) ->
  # NOTE published things cannot be deteted
  id ?= @params.publish ? @params.id
  dev ?= @params.dev
  token ?= @params.token
  token ?= if @S.dev or dev then @S.src.zenodo?.sandbox else @S.src?.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/actions/publish?access_token=' + token
  return @fetch url, method: 'POST'

P.src.zenodo.deposition.delete = (id, token, dev) ->
  id ?= @params.publish ? @params.id
  dev ?= @params.dev
  token ?= @params.token
  token ?= if @S.dev or dev then @S.src.zenodo?.sandbox else @S.src.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '?access_token=' + token
  await @fetch url, method: 'DELETE'
  return true

