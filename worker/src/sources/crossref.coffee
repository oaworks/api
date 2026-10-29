
# new crossref rate limits since 05/11/2025
# https://www.crossref.org/blog/announcing-changes-to-rest-api-rate-limits/
# if in public pool, single record request e.g. to DOI is 5 per second, one at a time. Query requests are 1 per second, 1 at a time.
# polite pool, single record requests are 10 per second 3 at a time, query requests are 3 per second 3 at a time. Sounds like can have both, e.g 13 total.
# polite pool examples appear to require &mailto=my@email.com as a param - check we are doing that rather than a header, just in case headers not checked any more
# so at most we could send 864000 single record requests per day (if each one responded fast enough)

P.src.crossref = () ->
  return 'Crossref API wrapper'

P.src.crossref.works = _index: settings: number_of_shards: 15
P.src.crossref.works._key = 'DOI'
P.src.crossref.works._prefix = false

P.src.crossref.works.doi = (doi, refresh, save) ->
  doi ?= @params.doi
  refresh = @refresh if not refresh? and @fn is 'src.crossref.works.doi'
  save ?= @params.save ? true
  if typeof doi is 'string' and doi.startsWith '10.'
    doi = doi.split('//')[1] if doi.indexOf('http') is 0
    doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
    if refresh or not found = await @src.crossref.works doi
      res = await @fetch 'https://api.crossref.org/works/' + doi, {rate: ['crossref', 10], headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works')}} #, 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}
      if res?.message?.DOI?
        found = await @src.crossref.works._format res.message
        await @src.crossref.works(found) if save
  return found

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

  rec.retrievedAt = Date.now()
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
P.src.crossref.works.published._log = false
  
P.src.crossref.works.search = (qrystr, from, size, filter, start, end, sort, order) ->
  qrystr ?= @params.q ? @params.search #? @params
  from ?= @params.from
  size ?= @params.size
  filter ?= @params.filter
  start ?= @params.start
  end ?= @params.end
  sort ?= @params.sort
  order ?= @params.order ? 'asc'
  filtered = ''
  if start
    filter ?= sort ? 'updated' # can be published, indexed, deposited, created, updated. indexed catches the most changes but can be very large and takes a long time
    start = await @date(start) if typeof start isnt 'string' or start.indexOf('-') is -1 # should be like 2021-01-31
    filtered = 'from-' + filter.replace('lished','').replace('xed','x').replace('ited','it').replace('dated', 'date') + '-date:' + start
  if end
    filter ?= sort ? 'updated'
    end = await @date(end) if typeof end isnt 'string' or end.indexOf('-') is -1
    filtered += (if filtered then ',' else '') + 'until-' + filter.replace('lished','').replace('xed','x').replace('ited','it').replace('dated', 'date') + '-date:' + end
  filter = filtered if filtered
  url = 'https://api.crossref.org/works?'
  url += 'sort=' + sort + '&order=' + order + '&' if sort?
  if typeof qrystr is 'object'
    for k of qrystr
      if k not in ['from','size','filter','start','end','sort','order']
        ky = if k in ['title','citation','issn'] then 'query.bibliographic' else if k is 'journal' then 'query.container-title' else if k in ['author','editor','chair','translator','contributor','affiliation','bibliographic'] then 'query.' + k else k
        url += ky + '=' + encodeURIComponent(qrystr[k]) + '&' 
  else if qrystr and qrystr isnt 'all'
    qry = qrystr.replace(/\w+?\:/g,'')
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
  url += 'filter=' + encodeURIComponent(filter) + '&' if filter
  url = url.replace('?&','?').replace(/&$/,'') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  try
    res = await @fetch url, {rate: ['crossrefFilter', 3], headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works')}} #, 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}
    return total: res.message['total-results'], cursor: res.message['next-cursor'], data: res.message.items, facets: res.message.facets
  catch
    return



P.src.crossref.changes = (startday, endday, created) ->
  startday ?= @params.changes
  startday = await @epoch(startday) if typeof startday is 'string' and (startday.includes('/') or startday.includes('-'))
  if not startday
    try
      last = await @src.crossref.works 'srcday:*', size: 1, sort: srcday: 'desc'
      startday = last.srcday + 86400000
      console.log 'Crossref changes start day set from latest record srcday', await @date startday
  if not startday
    try
      last = await @src.crossref.works 'indexed.timestamp:*', size: 1, sort: 'indexed.timestamp': 'desc'
      startday = last.indexed.timestamp
      console.log 'Crossref changes start day set from latest record indexed timestamp', await @date startday
  startday ?= 1693526400000 # 1st September 2023
  # 1607126400000 # the timestamp of when changes appeared to start after the last data dump, around 12/12/2020
  # for the 2022 update 1649635200000 was used for 11th April 2022
  startday = await @epoch await @date startday
  endday ?= @params.end
  endday = await @epoch(endday) if typeof endday is 'string' and (endday.includes('/') or endday.includes('-'))
  created ?= @params.created
  searchtype = 'indexed'

  batchsize = 10000
  dn = endday ? Date.now()
  dn = await @epoch await @date dn
  loaded = 0
  queued = []
  days = 0
  batch = []

  if startday >= dn and @fn isnt 'src.crossref.changes'
    console.log 'crossref works changes waiting an hour before looping to check for new changes because start day is not yet a day or more in the past'
    await @sleep 3600000
  else
    while startday < dn
      console.log 'Crossref changes', startday, days
      cursor = '*' # set a new cursor on each index day query
      days += 1
      totalthisday = false
      fromthisday = 0
      retries = 0
      while retries < 3 and (totalthisday is false or fromthisday < totalthisday)
        await @sleep 500
        thisdays = await @src.crossref.works.search undefined, cursor, 1000, searchtype, startday, startday # using same day for crossref API gets that whole day
        if not thisdays?.data
          console.log 'crossref error'
          await @sleep 2000 # wait on crossref downtime
          retries += 1
        else
          for rec in thisdays.data
            fr = await @src.crossref.works._format rec
            fr.srcday = startday
            batch.push fr
            loaded += 1

          if batch.length >= batchsize
            console.log 'Crossref bulk load', startday, days, totalthisday, fromthisday, loaded, queued.length
            await @src.crossref.works batch
            await @sleep 10000
            batch = []
          if totalthisday is false
            totalthisday = thisdays.total ? 0
            console.log startday, totalthisday
          fromthisday += 1000
          cursor = thisdays.cursor
      startday += 86400000

    await @src.crossref.works(batch) if batch.length
    console.log 'crossref works changes completed', loaded, days, queued.length
    if loaded > 0 or (new Date()).getDay() is 1
      dt = await @datetime()
      await @mail to: @S.log?.logs, subject: 'Crossref works load or changes ' + loaded + ' at ' + dt, text: 'loaded ' + loaded

  return loaded

P.src.crossref.changes._bg = true
P.src.crossref.changes._async = true
P.src.crossref.changes._log = false
P.src.crossref.changes._auth = '@oa.works'
P.src.crossref.changes._notify = false



# add any specific field mappings necessary to avoid collisions e.g. assertion.value can be text or date or number etc, so force to text
# note whole object has to be provided otherwise updating mapping with extra values in the object (or saving a record with extra values) overwrites it
_crossref_mapping = {
  "properties": { 
    "assertion": { 
      "properties": {
        "URL": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "explanation": {
          "properties": {
            "URL": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            }
          }
        },
        "group": {
          "properties": {
            "label": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            },
            "name": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            }
          }
        },
        "label": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "name": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "order": {
          "type": "long"
        },
        "value": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        }
      }
    }
  }
}