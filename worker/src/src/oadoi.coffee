
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

P.src.oadoi.hybrid = (issns) ->
  # there is a concern OADOI sometimes says a journal is closed on a particular 
  # record when it is actually a hybrid. So check if at least 1% of records for 
  # a given journal are hybrid, and if so the whole journal is hybrid.
  issns ?= @params.hybrid ? @params.issn ? @params.issns
  if typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    q = 'journal_issns:"' + issns.join('" OR journals_issns:"') + '"'
    closed = await @src.oadoi.count q + ' AND oa_status:"closed"'
    q = '(' + q + ')' if q.includes ' OR '
    hybrid = await @src.oadoi.count q + ' AND oa_status:"hybrid"'
    if closed and hybrid / closed > .001
      return true
    else
      return false
  else
    return

# if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
# https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-