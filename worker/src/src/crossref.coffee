
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

P.src.crossref = () ->
  return 'Crossref API wrapper'

P.src.crossref.journals = (issn) ->
  issn ?= @params.journals ? @.params.issn
  res = await @fetch 'https://api.crossref.org/journals/' + issn, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}
  return res?.message

#P.src.crossref.journals._index = true
#P.src.crossref.journals._key = 'ISSN'
#P.src.crossref.journals._prefix = false

P.src.crossref.journals.doi = (issn) ->
  issn ?= @params.doi ? @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  try
    res = await @src.crossref.works 'ISSN:"' + issn.join('" OR ISSN:"') + '"', 1
    return res.DOI
  return

P.src.crossref.works = (doi) ->
  doi ?= @params.works ? @params.doi ? @params.title ? @params.q
  if typeof doi is 'string'
    if doi.indexOf('10.') isnt 0
      res = await @src.crossref.works.title doi
    else
      # a search of an index of works - and remainder of route is a DOI to return one record
      doi = doi.split('//')[1] if doi.indexOf('http') is 0
      doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
      url = 'https://api.crossref.org/works/' + doi
      res = await @fetch url, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}

    if res?.message?.DOI?
      return @src.crossref.works._format res.message

  return

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
  rem = @src.crossref.works qr
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

P.src.crossref.works._format = (rec) ->
  rec.abstract = rec.abstract.replace(/<.*?>/g, '').replace(/^ABSTRACT/, '') if rec.abstract
  rec._id ?= rec.DOI.replace /\//g, '_'
  for a in rec.assertion ? []
    if a.label is 'OPEN ACCESS'
      if a.URL and a.URL.indexOf('creativecommons') isnt -1
        rec.license ?= []
        rec.license.push 'URL': a.URL
      rec.is_oa = true
  for l in rec.license ? []
    if l.URL and l.URL.indexOf('creativecommons') isnt -1 and (not rec.licence or rec.licence.indexOf('creativecommons') is -1)
      rec.licence = l.URL
      try rec.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/^\//, '').replace(/\/$/, '').replace(/\//g, '-').replace(/-$/, '')
      rec.is_oa = true
  try
    if rec.reference and rec.reference.length > 100
      rec.reference_original_length = rec.reference.length
      rec.reference = rec.reference.slice 0, 100
  try
    if rec.relation and rec.relation.length > 100
      rec.relation_original_length = rec.relation.length
      rec.relation = rec.relation.slice 0, 100
  
  for au in rec.author ? []
    au.name = (if au.given then au.given + ' ' else '') + (au.family ? '')

  if rec.published = await @src.crossref.works.published rec
    try rec.year = rec.published.split('-')[0]
    try parseInt rec.year
    try rec.publishedAt = await @epoch rec.published

  return rec

P.src.crossref.works.published = (rec) ->
  rec ?= @params.published
  rec = await @src.crossref.works(rec) if typeof rec is 'string'
  if rec?
    ppe = undefined
    pp = undefined
    for p in ['published','published-print','published-online','issued','deposited']
      if typeof rec[p] is 'object'
        ppp = undefined
        if typeof rec[p]['date-time'] is 'string' and rec[p]['date-time'].split('T')[0].split('-').length is 3
          ppp = rec[p]['date-time'].split('T')[0]
        else if Array.isArray(rec[p]['date-parts']) and rec[p]['date-parts'].length and Array.isArray rec[p]['date-parts'][0]
          rp = rec[p]['date-parts'][0]
          if typeof rp[0] in ['string', 'number'] and rp[0] isnt 'null'
            ppp = rp[0] + (if rp.length > 1 then '-' + (if rp[1].toString().length is 1 then '0' else '') + rp[1] else '-01') + (if rp.length > 2 then '-' + (if rp[2].toString().length is 1 then '0' else '') + rp[2] else '-01')
        if ppp and (not pp or ppe > await @epoch ppp)
          pp = ppp
          ppe = await @epoch pp
    return pp        
  return
  
P.src.crossref.works.published._hide = true

P.src.crossref.works.search = (qrystr, from, size, filter, start, end, sort, order) ->
  qrystr ?= @params.q ? @params.search ? @params
  from ?= @params.from
  size ?= @params.size
  filter ?= @params.filter
  start ?= @params.start
  end ?= @params.end
  sort ?= @params.sort
  order ?= @params.order ? 'asc'
  if start
    filtered = filter ? sort ? 'created' # can be published, indexed, deposited, created. indexed catches the most changes but can be very large and takes a long time
    start = await @date(start) if typeof start isnt 'string' or start.indexOf('-') is -1 # should be like 2021-01-31
    filter = (if filter then filter + ',' else '') + 'from-' + filtered.replace('lished','').replace('xed','x').replace('ited','it') + '-date:' + start
  if end
    filtered ?= filter ? sort ? 'created'
    end = await @date(end) if typeof end isnt 'string' or end.indexOf('-') is -1
    filter = (if filter then filter + ',' else '') + 'until-' + filtered.replace('lished','').replace('xed','x').replace('ited','it') + '-date:' + end
  url = 'https://api.crossref.org/works?'
  url += 'sort=' + sort + '&order=' + order + '&' if sort?
  if typeof qrystr is 'object'
    for k of qrystr
      if k not in ['from','size','filter','start','end','sort','order']
        ky = if k in ['title','citation','issn'] then 'query.bibliographic' else if k is 'journal' then 'query.container-title' else if k in ['author','editor','chair','translator','contributor','affiliation','bibliographic'] then 'query.' + k else k
        url += ky + '=' + encodeURIComponent(qrystr[k]) + '&' 
  else if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'') #.replace(/ AND /g,'+').replace(/ NOT /g,'-')
    qry = qry.replace(/ /g,'+')
    url += 'query=' + encodeURIComponent(qry) + '&'
  if from?
    if from isnt '*' and typeof from is 'string' and not from.replace(/[0-9]/g,'').length
      try
        fp = parseInt from
        from = fp if not isNaN fp
    if typeof from isnt 'number'
      url += 'cursor=' + encodeURIComponent(from) + '&'
    else
      url += 'offset=' + from + '&'
  url += 'rows=' + size + '&' if size? # max size is 1000
  url += 'filter=' + encodeURIComponent(filter) + '&'if filter? and filter isnt ''
  url = url.replace('?&','?').replace(/&$/,'') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  try
    res = await @fetch url, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}
    return total: res.message['total-results'], cursor: res.message['next-cursor'], data: res.message.items, facets: res.message.facets
  catch
    return
