
S.src.oadoi ?= {}
try S.src.oadoi = JSON.parse SECRETS_OADOI

P.src.oadoi = (doi) ->
  doi ?= @params?.oadoi ? @params?.doi
  if typeof doi is 'string' and doi.startsWith '10.'
    await @sleep 900
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return
    
P.src.oadoi._index = settings: number_of_shards: 9
P.src.oadoi._key = 'doi'
P.src.oadoi._prefix = false

# if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
# https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-