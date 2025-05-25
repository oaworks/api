
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
      res = await @fetch url, {headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works'), 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}

    if res?.message?.DOI?
      return @src.crossref.works._format res.message
  return'''

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
      res = await @fetch 'https://api.crossref.org/works/' + doi, {headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works'), 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}
      if res?.message?.DOI?
        found = await @src.crossref.works._format res.message
        await @src.crossref.works(found) if save
  return found

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
    # updated should only miss crossref internal things like citation count, see https://community.crossref.org/t/date-range-search-of-index-changes-seems-to-retrieve-too-many-records/1468
    # NOTE updated does NOT work for getting all records for a day because CREATED records can be created on a different day from which they are created, and they have no updated value, so the only way to find them is indexed date.
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
  url += 'filter=' + encodeURIComponent(filter) + '&' if filter
  url = url.replace('?&','?').replace(/&$/,'') # tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  try
    res = await @fetch url, {headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works'), 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}
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
    res = await @fetch url, {headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works'), 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}
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



'''P.src.crossref.load = () ->
  batchsize = 10000 # how many records to batch upload at a time - kept low because large crossref files were causing OOM
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

  # https://www.crossref.org/blog/new-public-data-file-120-million-metadata-records/
  # https://academictorrents.com/details/e4287cb7619999709f6e9db5c359dda17e93d515
  # this requires getting the crossref data dump from a torrent, which is a hassle on some commercial cloud providers
  # but once the file is on disk, extract it and this process will be able to go from there
  # there are torrent libs for node that could be used here, but given the infrequency and size of what we want 
  # to torrent, it's safer to do that step separately. Here's some simple instructions for the Jan 2021 crossref release:
  # sudo apt-get install aria2
  # aria2c https://academictorrents.com/download/e4287cb7619999709f6e9db5c359dda17e93d515.torrent
  
  # redo with 2022 dump:
  # https://www.crossref.org/blog/2022-public-data-file-of-more-than-134-million-metadata-records-now-available/
  # https://academictorrents.com/details/4dcfdf804775f2d92b7a030305fa0350ebef6f3e
  # https://academictorrents.com/download/4dcfdf804775f2d92b7a030305fa0350ebef6f3e.torrent

  # and 2023 update:
  # https://www.crossref.org/blog/2023-public-data-file-now-available-with-new-and-improved-retrieval-options/
  # https://academictorrents.com/details/d9e554f4f0c3047d9f49e448a7004f7aa1701b69
  # https://academictorrents.com/download/d9e554f4f0c3047d9f49e448a7004f7aa1701b69.torrent

  infolder = @S.directory + '/crossref/data/'
  lastfile = @S.directory + '/crossref/last' # where to record the ID of the last file processed
  
  files = -1 # max number of files to process. set to -1 to keep going
  filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
  try filenumber = parseInt((await fs.readFile lastfile).toString()) if not @refresh

  #await @src.crossref.works('') if filenumber is 0 and @params.clear

  total = 0
  batch = [] # batch of json records to upload

  # there were 40228 in the 2020 data dump,  but oddly 9999 was missing
  # for 2022 there are 26810
  # for 2023 there are 28701
  while filenumber >= 0 and filenumber isnt files and filenumber < 26810
    if filenumber not in [] # should make this a file exists check probably (just added 9999 to this list when running 2020)
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
'''


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
  # tried to use updated and created to reduce unnecessary useless load of indexed which includes lots of irrelevant internal crossref changes
  # but it does not work, because created records may be created on different days to the day they were created, and do not show up as updated either
  searchtype = 'indexed' #if created then 'created' else 'updated'

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

            '''if (rec.funder? or rec.author?) and rec.year in ['2023', '2022', 2023, 2022]
              doq = false
              for f in (rec.funder ? [])
                break if doq
                doq = rec.DOI if f.name?
              if not doq
                for a in (rec.author ? [])
                  break if doq
                  for af in (a.affiliation ? [])
                    break if doq
                    doq = rec.DOI if af.name?
              queued.push(doq) if doq'''

          if batch.length >= batchsize
            console.log 'Crossref bulk load', startday, days, totalthisday, fromthisday, loaded, queued.length
            await @src.crossref.works batch
            batch = []
          if totalthisday is false
            totalthisday = thisdays.total ? 0
            console.log startday, totalthisday
          fromthisday += 1000
          cursor = thisdays.cursor
      startday += 86400000

    await @src.crossref.works(batch) if batch.length
    #await @report.queue(queued, undefined, undefined, undefined, 'changes') if queued.length
    console.log 'crossref works changes completed', loaded, days, queued.length
    if loaded > 0 or (new Date()).getDay() is 1
      dt = await @datetime()
      await @mail to: @S.log?.logs, subject: 'Crossref works load or changes ' + loaded + ' at ' + dt, text: 'loaded ' + loaded

  return loaded

P.src.crossref.changes._bg = true
P.src.crossref.changes._async = true
P.src.crossref.changes._log = false
P.src.crossref.changes._auth = 'root'
P.src.crossref.changes._notify = false



P.src.crossref.plus = {}
P.src.crossref.plus.load = ->
  # we now have metadata plus: 
  # https://www.crossref.org/documentation/metadata-plus/metadata-plus-snapshots/
  # export CRTOKEN='<insert-your-token-here>'
  # curl -o "all.json.tar.gz" --progress-bar -L -X GET  https://api.crossref.org/snapshots/monthly/latest/all.json.tar.gz -H "Crossref-Plus-API-Token: Bearer ${CRTOKEN}"
  # and there may be issues downloading, at least FAQ seems to indicate some people may have. If so, redo above command to continue where failed with added -C - 

  started = await @epoch()
  last = 0

  if @params.clear
    await @src.crossref.works ''
    map = {properties: {}} # add any specific field mappings necessary to avoid collisions e.g. assertion.value can be text or date or number etc, so force to text
    map.properties.assertion = { # note whole object has to be provided otherwise updating mapping with extra values in the object (or saving a record with extra values) overwrites it
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
    await @src.crossref.works.mapping map
  else
    try last = (await @src.crossref.works 'srcfile:*', size: 1, sort: srcfile: 'desc').srcfile

  fn = @S.directory + '/import/crossref/all.json.tar.gz'
  try
    stats = await fs.stat fn # check if file exists in async fs promises which does not have .exists
  catch
    console.log 'crossref downloading snapshot'
    hds = {}
    hds['Crossref-Plus-API-Token'] = 'Bearer ' + @S.crossref
    resp = await fetch 'https://api.crossref.org/snapshots/monthly/latest/all.json.tar.gz', headers: hds
    wstr = fs.createWriteStream fn
    await new Promise (resolve, reject) =>
      resp.body.pipe wstr
      resp.body.on 'error', reject
      wstr.on 'finish', resolve
    console.log 'snapshot downloaded'

  total = 0
  srcfile = 0
  lines = ''
  complete = false

  '''for await line from readline.createInterface input: fs.createReadStream(fn).pipe zlib.createGunzip()
    if not line.startsWith(' ') and line.endsWith('{') and line.includes('.json') and not isNaN (scf = parseInt line.split('.json')[0].replace(/[^0-9]/g, ''))
      console.log total, srcfile, scf, lines.length
      if lines.length
        # on large file readline streams across multiple hours, definitely saw this issue. Not sure why pause/resume would help in this context, but trying it anyway
        # https://github.com/nodejs/node/issues/42454
        # https://stackoverflow.com/questions/71588045/javascript-async-sleep-function-somehow-leads-to-silent-exiting-of-program/71589103#71589103
        # lr.pause() # did not make any difference
        await _batch()
        #lr.resume()
      srcfile = scf
      lines = '{'
    else
      lines += line
  await _batch(true) if lines.length or batch.length'''

  strm = fs.createReadStream(fn).pipe zlib.createGunzip()
  prevline = ''
  strm.on 'data', (chunk) =>
    line = chunk.toString 'utf8'
    lines += line
    if (prevline + line).includes '\n  "items" : [' # just a shorter space to check than all of lines, and use prevline just in case the inclusion criteria straddled a chunk
      while lines.includes '\n  "items" : ['
        [lp, lines] = lines.replace('\n  "items" : [', 'X0X0X0X0X0X0X0X0X0X0X0').split('X0X0X0X0X0X0X0X0X0X0X0') # cheap split on first occurrence
        if lp.includes '\n  } ]'
          lps = lp.split('\n  } ]')
          scf = parseInt lps.pop().split('.json')[0].replace(/[^0-9]/g, '')
          if srcfile < last
            console.log 'crossref plus load waiting for file', srcfile, last
          else
            recs = []
            for rec in rp = JSON.parse '[' + lps.join(']') + '}]'
              rec = await @src.crossref.works._format rec
              if rec?.DOI
                rec.srcfile = srcfile
                recs.push rec
            console.log 'crossref plus load', rp.length, recs.length
            total += recs.length
            await @src.crossref.works(recs) if recs.length

          srcfile = scf
    prevline = line

  strm.on 'error', (err) => console.log 'crossref plus load file stream error', JSON.stringify err
  strm.on 'end', () =>
    console.log 'stream complete for crossref plus load'
    complete = true
  while not complete
    console.log 'crossref plus load streaming file', lines.length, srcfile, total, Math.floor((Date.now()-started)/1000/60) + 'm'
    await @sleep 30000
  ended = Date.now()
  console.log 'crossref plus load complete', srcfile, total, started, ended, Math.floor((ended-started)/1000/60) + 'm'
  return total

P.src.crossref.plus.load._log = false
P.src.crossref.plus.load._bg = true
P.src.crossref.plus.load._async = true
#P.src.crossref.plus.load._auth = 'root'