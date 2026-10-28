
S.src.oadoi ?= {}
try S.src.oadoi = JSON.parse SECRETS_OADOI

P.src.oadoi = _index: settings: number_of_shards: 9
P.src.oadoi._key = 'doi'
P.src.oadoi._prefix = false

P.src.oadoi.doi = (doi, refresh) ->
  doi ?= @params.doi
  refresh = @refresh if not refresh? and @fn is 'src.oadoi.doi'
  if typeof doi is 'string' and doi.startsWith '10.'
    if refresh isnt true and exists = await @src.oadoi doi
      if typeof refresh isnt 'number' or (exists.updated? and (new Date(exists.updated).valueOf()) > (Date.now() - refresh))
        return exists

    try
      console.log 'getting from OADOI', doi
      await @sleep 500
      url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
      if res = await @fetch url
        if res.doi
          ft = await @src.oadoi._format res
          try await @src.oadoi ft
          return ft
  return

P.src.oadoi.hybrid = (issns) ->
  # there is a concern OADOI sometimes says a journal is closed on a particular 
  # record when it is actually a hybrid. So check if some records for 
  # a given journal are hybrid, and if so the whole journal is hybrid.
  issns ?= @params.hybrid ? @params.issn ? @params.issns
  if typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    q = 'journal_issns.keyword:*' + issns.join('* OR journals_issns.keyword:*') + '*'
    q = '(' + q + ')' if q.includes ' OR '
    closed = await @src.oadoi.count q + ' AND oa_status:"closed"'
    hybrid = await @src.oadoi.count q + ' AND oa_status:"hybrid"'
    if closed and hybrid / closed > .001
      return true
    else
      return false
  else
    return

P.src.oadoi.oa = type: (issns) ->
  issns ?= @params.type ? @params.issn ? @params.issns
  if typeof issns is 'string' and issns.startsWith('10.') and rec = await @src.oadoi.doi issns
    issns = rec.journal_issns
  if issns and typeof issns is 'object' and not Array.isArray issns
    issns = issns.journal_issns ? issns.ISSN
  issns = issns.replace(/\s/g, '').split(',') if typeof issns is 'string'
  if Array.isArray(issns) and issns.length
    types = await @src.oadoi.terms 'oa_status.keyword', 'journal_issns.keyword:*' + issns.join('* OR journals_issns.keyword:*') + '*'
    if types.length is 1
      calculated = types[0].term
    else if types.length is 0
      calculated = 'unknown'
    else if JSON.stringify(types).toLowerCase().includes '"hybrid"'
      calculated = await @src.oadoi.hybrid issns
    else if types[1].count / types[0].count > .001
      calculated = types[0].term
    else
      calculated = 'unknown'
    return issn: issns, calculated: calculated, types: types
  else
    return issn: issns, calculated: '', types: []

# if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
# https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-




P.src.oadoi._format = (rec) ->
  # given a record direct from oadoi fix it so that it can be indexed.
  # known issues - they use "deprecated" string in values that used to be dates, which breaks date typing.
  fixes = ['updated', 'evidence']
  for loc in (rec.oa_locations ? [])
    for k in fixes
      loc[k] = undefined if loc[k] and typeof loc[k] is 'string' and loc[k].includes 'deprecated'
  for ol in ['best_oa_location', 'first_oa_location']
    if rec[ol]?
      for k in fixes
        rec[ol][k] = undefined if rec[ol][k] and typeof rec[ol][k] is 'string' and rec[ol][k].includes 'deprecated'
  rec._id = rec.doi.replace(/\//g, '_').toLowerCase()
  return rec

