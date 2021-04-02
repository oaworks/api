
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

_xref_hdr = {'User-Agent': S.name + '; mailto:' + S.mail?.to}

P.src.crossref = {}

P.src.crossref.journals = (issn) ->
  # by being an index, should default to a search of the index, then run this query if not present, which should get saved to the index
  issn ?= @params.journals ? @.params.issn
  isq = @index._q issn
  #url = 'https://api.crossref.org/journals?query=' + issn
  url = 'https://dev.api.cottagelabs.com/use/crossref/journals' + if isq then '?q=' + issn else '/' + issn
  res = await @fetch url #, {headers: _xref_hdr} # TODO check how headers get sent by fetch
  #return if res?.message?['total-results']? and res.message['total-results'].length then res.message['total-results'][0] else undefined
  return if isq then res else if res?.ISSN? then res else undefined

#P.src.crossref.journals._index = true
P.src.crossref.journals._key = 'ISSN'

P.src.crossref.journals.doi = (issn) ->
  issn ?= @params.doi ? @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  try
    #res = await @src.crossref.works 'ISSN.exact:"' + issn.join('" OR ISSN.exact:"') + '"'
    res = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=ISSN.exact:"' + issn.join('" OR ISSN.exact:"') + '"'
    return res.hits.hits[0]._source.DOI
  catch
    return undefined

P.src.crossref.works = (doi) ->
  doi ?= @params.works ? @params.doi ? @params.title or @params.q
  if typeof doi is 'string'
    if doi.indexOf('10.') isnt 0
      res = await @src.crossref.works.title doi
    else
      # a search of an index of works - and remainder of route is a DOI to return one record
      doi = doi.split('//')[1] if doi.indexOf('http') is 0
      doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
      # for now just get from old system instead of crossref
      #url = 'https://api.crossref.org/works/' + doi
      url = 'https://dev.api.cottagelabs.com/use/crossref/works/' + doi
      res = await @fetch url #, {headers: _xref_hdr}

  if res?.DOI? #res?.message?.DOI?
    rec = res #res.data.message
    if rec.year is "null" or (typeof rec.published is 'string' and rec.published.indexOf('null') isnt -1)
      delete rec.year if rec.year is "null" # temporary avoidance of some errors in old crossref data import
      delete rec.published
      delete rec.publishedAt
    delete rec.relation
    delete rec.reference # is there anything worth doing with these? In some cases they are extremely long, enough to cause problems in the index
    try rec.abstract = @convert.html2txt(rec.abstract) if typeof rec.abstract is 'string' and this?.convert?.html2txt?
    return rec
  else
    return undefined

#P.src.crossref.works._kv = false
P.src.crossref.works._index = settings: number_of_shards: 9
P.src.crossref.works._key = 'DOI'

# TODO this really should be handled by the main crossref.works function, then 
# the wrapper should query in advance, like it does, but then be able to tell 
# the difference between an actual query and an attempt to get a specific record
P.src.crossref.works.title = (title) ->
  title ?= @params.title ? @params.q
  qr = 'title:"' + title + '"'
  if title.split(' ').length > 2
    qr += ' OR ('
    for t in title.split ' '
      qr += ' AND ' if not qr.endsWith '('
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")'
    qr += ')'
  rem = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + qr
  #rem = @src.crossref.works qr
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
  for r in rem?.hits?.hits ? []
    if r._source.DOI and r._source.title and r._source.title.length
      rt = (if typeof r._source.title is 'string' then r._source.title else r._source.title[0]).toLowerCase()
      if r._source.subtitle and r._source.subtitle.length
        st = (if typeof r._source.subtitle is 'string' then r._source.subtitle else r._source.subtitle[0]).toLowerCase()
        rt += ' ' + st if typeof st is 'string' and st.length and st not in rt
      rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      if (ltitle.indexOf(rt) isnt -1 or rt.indexOf(ltitle) isnt -1) and ltitle.length/rt.length > 0.7 and ltitle.length/rt.length < 1.3
        if r._source.type is 'journal-article'
          res = r._source
        else if not res? or (res.type isnt 'journal-article' and r._source.type is 'journal-article')
          res = r._source
  return res

# and need the code that builds the index and keeps it up to date
# and someting to trigger a load each day for example
# probably requires a cron schedule to read some kind of setting or KV of last-updated indexes, and their update schedule
# doing the regular index update will probably be a long-running job, so needs to be triggered but run on the backend machine
