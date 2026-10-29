
S.src.zenodo ?= {}
try S.src.zenodo = JSON.parse SECRETS_ZENODO

# https://developers.zenodo.org/
# requires a token be provided as query param on all requests, called ?access_token=
# access token would require deposit:write and deposit:actions permission in order to deposit something AND then publish it
# need to POST create a deposition, then POST upload files to the deposition, then POST publish the deposition

P.src.zenodo = deposition: {}, records: {}

P.src.zenodo.records.search = (q, dev) ->
  q ?= @params
  dev ?= @params.dev
  size = @params.size ? 10
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/records?size=' + size + '&q=' + encodeURIComponent q # just do simple string queries for now
  return @fetch url # could do a post if q is more complex... so far this just returns an ES search endpoint

P.src.zenodo.deposition.create = (metadata, up, token, dev) ->
  dev ?= @params.dev ? @S.dev
  token ?= @params.token
  token ?= if dev then @S.src?.zenodo?.sandbox else @S.src?.zenodo?.token
  metadata ?= @params.metadata
  return false if not token? or not metadata? or not metadata.title? or not metadata.description?
  url = 'https://' + (if dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions?access_token=' + token
  data = {metadata: metadata}
  if not data.metadata.upload_type
    data.metadata.upload_type = 'publication'
    data.metadata.publication_type = 'article'
  data.metadata.creators ?= [{name:"Works, Open Access"}]
  if up?
    rs = await @fetch url, method: 'POST', body: data, mode: 'cors', credentials: 'include', headers: referer: if @S.dev or dev then 'https://sandbox.zenodo.org' else 'https://zenodo.org'
    rs.uploaded = await @src.zenodo.deposition.upload(rs.id, up.content, up.file, up.name, up.url, token, dev) if rs?.id? and (up.content or up.file)
    rs.published = await @src.zenodo.deposition.publish(rs.id, token, dev) if up.publish
    return rs
  else
    # returns a zenodo deposition resource, which most usefully has an .id parameter (to use to then upload files to)
    return await @fetch url, method: 'POST', body: data, headers: referer: if @S.dev or dev then 'https://sandbox.zenodo.org' else 'https://zenodo.org'

P.src.zenodo.deposition.upload = (id, content, file, filename, url, token, dev) ->
  id ?= @params.upload ? @params.id
  content ?= @params.content
  filename ?= @params.filename
  if not content and not file
    try file = @request.files[0]
  if url and not content and not file
    try content = await @fetch url, buffer: true, headers: referer: if @S.dev or dev then 'https://sandbox.zenodo.org' else 'https://zenodo.org'
  token ?= @params.token
  token ?= if @S.dev or dev then @S.src.zenodo?.sandbox else @S.src?.zenodo?.token
  dev ?= @params.dev
  return false if not token? or not id?
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/files?access_token=' + token
  return @fetch url, file: (content ? file), filename: filename, headers: referer: if @S.dev or dev then 'https://sandbox.zenodo.org' else 'https://zenodo.org'

P.src.zenodo.deposition.publish = (id, token, dev) ->
  id ?= @params.publish ? @params.id
  dev ?= @params.dev
  token ?= @params.token
  token ?= if @S.dev or dev then @S.src.zenodo?.sandbox else @S.src?.zenodo?.token
  return false if not token? or not id?
  url = 'https://' + (if @S.dev or dev then 'sandbox.' else '') + 'zenodo.org/api/deposit/depositions/' + id + '/actions/publish?access_token=' + token
  return @fetch url, method: 'POST', headers: referer: if @S.dev or dev then 'https://sandbox.zenodo.org' else 'https://zenodo.org'

