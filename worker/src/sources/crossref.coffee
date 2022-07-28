
# https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
# http://api.crossref.org/works/10.1016/j.paid.2009.02.013

P.src.crossref = () ->
  return 'Crossref API wrapper'

'''P.src.crossref.works = (doi) ->
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
  return'''

#P.src.crossref.works._index = settings: number_of_shards: 9
P.src.crossref.works = _index: settings: number_of_shards: 9
P.src.crossref.works._key = 'DOI'
P.src.crossref.works._prefix = false

P.src.crossref.works.doi = (doi, save) ->
  doi ?= @params.doi
  save ?= @params.save ? false
  if typeof doi is 'string' and doi.startsWith '10.'
    doi = doi.split('//')[1] if doi.indexOf('http') is 0
    doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
    res = await @fetch 'https://api.crossref.org/works/' + doi, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}
    if res?.message?.DOI?
      formatted = await @src.crossref.works._format res.message
      if save
        await @src.crossref.works formatted
      return formatted
  return

P.src.crossref.works.title = (title) ->
  title ?= @params.title ? @params.q
  qr = 'title:"' + title + '"'
  if title.split(' ').length > 2
    qr += ' OR ('
    for t in title.split ' '
      qr += ' AND ' if not qr.endsWith '('
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")'
    qr += ')'
  rem = await @src.crossref.works qr
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

P.src.crossref.journals = _index: true, _prefix: false
P.src.crossref.journals.load = () ->
  await @src.crossref.journals ''
  counter = 0
  total = 0
  batch = []
  cursor = '*'
  while cursor and (counter is 0 or counter < total)
    url = 'https://api.crossref.org/journals?cursor=' + cursor + '&rows=' + 1000
    res = await @fetch url, {headers: {'User-Agent': @S.name + '; mailto:' + @S.mail?.to}}
    total = res.message['total-results'] if total is 0
    cursor = res.message['next-cursor']
    for rec in res.message.items
      rec.ISSN ?= []
      rec.issn = []
      for i in rec.ISSN
        rec.issn.push(i) if typeof i is 'string' and i.length and i not in rec.issn
      rec.dois = rec.counts?['total-dois']
      if rec.breakdowns?['dois-by-issued-year']?
        rec.years = []
        for yr in rec.breakdowns['dois-by-issued-year']
          rec.years.push(yr[0]) if yr.length is 2 and yr[0] not in rec.years
        rec.years.sort()
      if not rec.years? or not rec.years.length or not rec.dois
        rec.discontinued = true
      else
        thisyear = new Date().getFullYear()
        if thisyear not in rec.years and (thisyear-1) not in rec.years and (thisyear-2) not in rec.years and (thisyear-3) not in rec.years
          rec.discontinued = true
      batch.push rec
    counter += 1000
    if batch.length >= 10000
      await @src.crossref.journals batch
      batch = []
  if batch.length
    await @src.crossref.journals batch
    batch = []
  console.log counter
  return counter

P.src.crossref.journals.load._bg = true
P.src.crossref.journals.load._async = true
P.src.crossref.journals.load._auth = 'root'



P.src.crossref.load = () ->
  batchsize = 30000 # how many records to batch upload at a time
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  # https://www.crossref.org/blog/new-public-data-file-120-million-metadata-records/
  # https://academictorrents.com/details/e4287cb7619999709f6e9db5c359dda17e93d515
  # this requires getting the crossref data dump from a torrent, which is a hassle on some commercial cloud providers
  # but once the file is on disk, extract it and this process will be able to go from there
  # there are torrent libs for node that could be used here, but given the infrequency and size of what we want 
  # to torrent, it's safer to do that step separately. Here's some simple instructions for the Jan 2021 crossref release:
  # sudo apt-get install aria2
  # aria2c https://academictorrents.com/download/e4287cb7619999709f6e9db5c359dda17e93d515.torrent
  infolder = @S.directory + '/crossref/crossref_public_data_file_2021_01/'
  lastfile = @S.directory + '/crossref/last' # where to record the ID of the last file processed
  
  files = -1 # max number of files to process. set to -1 to keep going
  filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
  try filenumber = parseInt((await fs.readFile lastfile).toString()) if not @refresh

  #await @src.crossref.works('') if filenumber is 0

  total = 0
  batch = [] # batch of json records to upload

  while filenumber >= 0 and filenumber isnt files and filenumber < 40229 # there are 40228 in the 2020 data dump,  but oddly 9999 is missing in our set
    if filenumber not in [9999] # should make this a file exists check probably
      break if total is howmany
      console.log 'Crossref load starting file', filenumber
      lines = ''
      for await line from readline.createInterface input: fs.createReadStream(infolder + filenumber + '.json.gz').pipe zlib.createGunzip()
        lines += line
      
      for rec in JSON.parse(lines).items
        break if total is howmany
        total += 1
        rec = await @src.crossref.works._format rec
        rec['srcfile'] = filenumber
        batch.push rec
        
        if batch.length is batchsize
          console.log 'Crossref load ' + filenumber, total
          await @src.crossref.works batch
          await fs.writeFile lastfile, filenumber
          batch = []
    filenumber += 1

  await @src.crossref.works(batch) if batch.length

  console.log total
  return total

P.src.crossref.load._bg = true
P.src.crossref.load._async = true
P.src.crossref.load._auth = 'root'



P.src.crossref.changes = (startday) ->
  batchsize = 20000
  startday ?= @params.changes
  if not startday
    try
      last = await @src.crossref.works 'srcday:*', size: 1, sort: srcday: 'desc'
      startday = last.srcday
  startday ?= 1607126400000 # the timestamp of when changes appeared to start after the last data dump, around 12/12/2020
  dn = Date.now()
  loaded = 0
  days = 0
  batch = []
  while startday < dn
    console.log 'Crossref changes', startday, days
    cursor = '*' # set a new cursor on each index day query
    days += 1
    totalthisday = false
    fromthisday = 0
    while totalthisday is false or fromthisday < totalthisday
      await @sleep 500
      thisdays = await @src.crossref.works.search undefined, cursor, 1000, undefined, startday, startday # using same day for crossref API gets that whole day
      if not thisdays?.data
        console.log 'crossref error'
        await @sleep 2000 # wait on crossref downtime
      else
        for rec in thisdays.data
          fr = await @src.crossref.works._format rec
          fr.srcday = startday
          batch.push fr
          loaded += 1
        if batch.length >= batchsize
          console.log 'Crossref bulk load', startday, days, totalthisday, fromthisday, loaded
          await @src.crossref.works batch
          batch = []
        if totalthisday is false
          totalthisday = thisdays.total ? 0
          console.log startday, totalthisday
        fromthisday += 1000
        cursor = thisdays.cursor
    startday += 86400000

  await @src.crossref.works(batch) if batch.length
  
  console.log loaded, days
  return loaded

P.src.crossref.changes._bg = true
P.src.crossref.changes._async = true
P.src.crossref.changes._auth = 'root'
P.src.crossref.changes._notify = false
