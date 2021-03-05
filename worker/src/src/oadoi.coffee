
P.src.oadoi = (doi) ->
  doi ?= this?.params?.oadoi ? this?.params?.doi
  if typeof doi is 'string' and doi.startsWith('10.')
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
    return @fetch url
  else
    return undefined
    
P.src.oadoi._index = true
P.src.oadoi._kv = false
P.src.oadoi._key = 'doi'

