
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

_xref_hdr = {'User-Agent': S.name + '; mailto:' + S.mail?.to}

P.src.crossref = () ->
  return 'Crossref API wrapper'

P.src.crossref.journals = (issn) ->
  # by being an index, should default to a search of the index, then run this query if not present, which should get saved to the index
  issn ?= @params.journals ? @.params.issn
  isissn = typeof issn is 'string' and issn.length is 9 and issn.split('-').length is 2 and issn.indexOf('-') is 4
  #url = 'https://api.crossref.org/journals?query=' + issn
  url = 'https://dev.api.cottagelabs.com/use/crossref/journals' + (if isissn then '/' + issn else '?q=') + issn
  res = await @fetch url #, {headers: _xref_hdr} # TODO check how headers get sent by fetch
  #return if res?.message?['total-results']? and res.message['total-results'].length then res.message['total-results'][0] else undefined
  return if isissn then (if res?.ISSN? then res else undefined) else res

#P.src.crossref.journals._index = true
#P.src.crossref.journals._key = 'ISSN'
#P.src.crossref.journals._prefix = false

P.src.crossref.journals.doi = (issn) ->
  issn ?= @params.doi ? @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  try
    #res = await @src.crossref.works 'ISSN.exact:"' + issn.join('" OR ISSN.exact:"') + '"'
    res = await @fetch 'https://dev.api.cottagelabs.com/use/crossref/works?q=ISSN.exact:"' + issn.join('" OR ISSN.exact:"') + '"'
    return res.hits.hits[0]._source.DOI
  catch
    return undefined

P.src.crossref.works = (doi, opts) ->
  doi ?= @params.works ? @params.doi ? @params.title ? @params.q
  if typeof doi is 'string'
    if doi.indexOf('10.') isnt 0
      res = await @src.crossref.works.title doi
    else
      # a search of an index of works - and remainder of route is a DOI to return one record
      doi = doi.split('//')[1] if doi.indexOf('http') is 0
      doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
      # for now just get from old system instead of crossref
      #url = 'https://api.crossref.org/works/' + doi
      url = 'https://dev.api.cottagelabs.com/use/crossref/works?doi=' + doi
      res = await @fetch url #, {headers: _xref_hdr}

    if res?.DOI? #res?.message?.DOI?
      rec = await @src.crossref.works._prep res #res.data.message
      return rec
  else
    # for now just get from old system instead of crossref
    #url = 'https://api.crossref.org/works/' + doi
    url = 'https://dev.api.cottagelabs.com/use/crossref/works?q=' + doi
    return await @fetch url, params: opts #, {headers: _xref_hdr}
    
  return undefined

#P.src.crossref.works._kv = false
P.src.crossref.works._index = settings: number_of_shards: 9
P.src.crossref.works._key = 'DOI'
P.src.crossref.works._prefix = false

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

P.src.crossref.works._prep = (rec) ->
  rec.abstract = rec.abstract.replace(/<.*?>/g, '').replace(/^ABSTRACT/, '') if rec.abstract
  rec._id ?= rec.DOI.replace /\//g, '_'
  # try to build a published_date and publishedAt field?
  for a in rec.assertion ? []
    if a.label is 'OPEN ACCESS'
      if a.URL and a.URL.indexOf('creativecommons') isnt -1
        rec.license ?= []
        rec.license.push 'URL': a.URL
      rec.is_oa = true
  for l in rec.license ? []
    if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not rec.licence or rec.licence.indexOf('creativecommons') is -1)
      rec.licence = l.URL
      try rec.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/^\//, '').replace(/\/$/, '').replace(/\//g, '-')
      rec.is_oa = true
  try
    if rec.reference and rec.reference.length > 200
      rec.reference_original_length = rec.reference.length
      rec.reference = rec.reference.slice 0, 200
  try
    if rec.relation and rec.relation.length > 100
      rec.relation_original_length = rec.relation.length
      rec.relation = rec.relation.slice 0, 100
    
  for p in ['published-print','published-online','issued','deposited','indexed']
    if rec[p]
      try
        if rec[p]['date-time'] and rec[p]['date-time'].split('T')[0].split('-').length is 3
          rec.published ?= rec[p]['date-time'].split('T')[0]
          rec.year ?= rec.published.split('-')[0] if rec.published?
        pbl = ''
        if rec[p]['date-parts'] and rec[p]['date-parts'].length and rec[p]['date-parts'][0]
          rp = rec[p]['date-parts'][0]
          pbl = rp[0]
          if pbl and pbl isnt 'null'
            if rp.length is 1
              pbl += '-01-01'
            else
              pbl += if rp.length > 1 then '-' + (if rp[1].toString().length is 1 then '0' else '') + rp[1] else '-01'
              pbl += if rp.length > 2 then '-' + (if rp[2].toString().length is 1 then '0' else '') + rp[2] else '-01'
            if not rec.published
              rec.year = pbl.split('-')[0]
            rec.publishedAt ?= rec[p].timestamp

  return rec
