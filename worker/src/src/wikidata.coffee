
P.src.wikidata = (qid) ->
  qid ?= @params.wikidata ? @params.url ? @params.wikipedia
  if typeof qid is 'string'
    if qid.includes 'wiki/'
      t = qid.split('wiki/').pop()
      qid = undefined
      try
        w = await @src.wikipedia.lookup {title: t}
        qid = w.data.pageprops.wikibase_item
    if qid
      res = await @fetch 'https://www.wikidata.org/wiki/Special:EntityData/' + qid + '.json'
      qid = res.entities[qid]
  if Array.isArray qid
    recs = []
    for q in qid
      recs.push await @src.wikidata._format q
    return recs
  else if typeof qid is 'object'
    return @src.wikidata._format qid
  else
    return

P.src.wikidata._index = settings: number_of_shards: 9
P.src.wikidata._prefix = false



P.src.wikidata._format = (rec) ->
  #rec.type = rec.type # was this meant to come from somewhere else
  rec._id = rec.id
  rec.qid = rec.id
  rec.createdAt = Date.now()
  rec.label = rec.labels?.en?.value # is an english label required?
  delete rec.labels

  sl = {}
  for sw in (rec.sitelinks ? [])
    sl[sw] = rec.sitelinks[sw] if 'enwiki' in sw
  rec.sitelinks = sl

  rec.description = rec.descriptions?.en?.value
  delete rec.descriptions

  rec.alias = []
  for als in (rec.aliases ? [])
    rec.alias.push(al) for al in rec.aliases[als]
  delete rec.aliases

  rec.snaks = []
  for s in (rec.claims ? [])
    for sn in rec.claims[s]
      ds = await @src.wikidata.desnak sn.mainsnak
      rec.snaks.push(ds) if JSON.stringify(ds) isnt '{}'
      rec.image ?= ds.imgurl
  delete rec.claims

  try rec.wikipedia = rec.sitelinks?.enwiki?.url ? 'https://en.wikipedia.org/wiki/' + rec.sitelinks.enwiki.title.replace(/ /g,'_')
  try rec.wid = rec.sitelinks?.enwiki?.url.split('wiki/').pop()

  return rec


P.src.wikidata.desnak = (ms) ->
  ms ?= @params
  return {} if typeof ms isnt 'object' or not ms.datavalue?.value?

  snak = qualifiers: [], references: [], property: ms.property # like PS30
  try snak['key'] = (await @src.wikidata.property snak.property).label
  if typeof ms.datavalue.value isnt 'object'
    snak.value = ms.datavalue.value # an actual value
    snak.url = snak.value if ms.datatype is 'url'
  else if ms.datavalue.value.latitude
    snak.location = latitude: ms.datavalue.value.latitude, longitude: ms.datavalue.value.longitude, precision: ms.datavalue.value.precision
    snak.value = snak.location.latitude + (if snak.location.longitude then ',' + snak.location.longitude else '')
    snak.globe = ms.datavalue.value.globe.split('/').pop() if ms.datavalue.value.globe? # like Q2 is earth, could be dereferenced later
  else if ms.datavalue.value.amount
    snak[sk] = ms.datavalue.value[sk].toString() for sk in ['amount', 'upperBound', 'lowerBound']
    snak.value = snak.amount
    snak.unit = ms.datavalue.value.unit.split('/').pop() if ms.datavalue.value.unit # like Q712226 is square kilometer, later deref
  else if ms.datavalue.value.time
    snak[sk] = ms.datavalue.value[sk].toString() for sk in ['time', 'timezone', 'before', 'after', 'precision']
    snak.value = snak.time
  else if ms.datavalue.value.id
    snak.qid = ms.datavalue.value.id # like Q32, so needs later dereference and value set in snak.value (it would take too long and may run before the record to dereference exists anyway)
    #try
    #  v = await @src.wikidata snak.qid
    #  snak.value = v?.label

  for q in ms.qualifiers ? []
    for qk in ms.qualifiers[q]
      snak.qualifiers.push await @src.wikidata.desnak qk
  for r in ms.references ? []
    for skid in r['snaks-order']
      for ansk in r.snaks[skid]
        snak.references.push await @src.wikidata.desnak ansk

  if snak.key is 'image' or (typeof snak.value is 'string' and snak.value.toLowerCase().split('.').pop() in ['bmp', 'gif', 'jpg', 'jpeg', 'png', 'svg', 'tif', 'webp'])
    if snak.value.startsWith 'http'
      snak.imgurl = snak.value
    else
      snak.imgurl = 'https://upload.wikimedia.org/wikipedia/commons/'
      img = snak.value.replace /\s/g, '_'
      mds = crypto.createHash('md5').update(img, 'utf8').digest('hex') # base64
      snak.imgurl += mds.charAt(0) + '/' + mds.charAt(0) + mds.charAt(1) + '/' + encodeURIComponent img

  return if not snak.value and not snak.qid then {} else snak


_got_props = {}
P.src.wikidata.properties = () ->
  if not @refresh and JSON.stringify(_got_props) isnt '{}'
    return _got_props
  else
    _got_props = {}
    try
      if content = await @fetch 'https://www.wikidata.org/wiki/Wikidata:Database_reports/List_of_properties/all'
        tb = content.split('<table class="wikitable sortable">')[1].split('</table>')[0]
        rows = tb.split '</tr>'
        rows.shift() # the first row is headers
        for row in rows
          try
            prop = {}
            parts = row.split '</td>'
            try prop.pid = parts[0].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.label = parts[1].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.desc = parts[2].replace('</a>', '').split('>').pop().trim().replace('\n', '')
            try prop.alias = parts[3].replace('</a>', '').split('>').pop().replace(/, or/g, ',').replace(/, /g, ',').trim().replace('\n', '').split(',')
            try prop.type = parts[4].replace('</a>', '').split('>').pop().trim().replace('\n','')
            try prop.count = parts[5].replace('</a>', '').split('>').pop().replace(/,/g, '').trim().replace('\n', '')
            _got_props[prop.pid] = prop if typeof prop.pid is 'string' and prop.pid.length and prop.pid.startsWith 'P'
    return _got_props

P.src.wikidata.property = (prop) ->
  prop ?= @params.property
  return undefined if typeof prop isnt 'string'
  props = await @src.wikidata.properties()
  if props[prop]
    return props[prop]
  else
    q = prop.toLowerCase()
    qf = q.split(' ')[0]
    partials = []
    firsts = []
    for p of props
      pls = props[p].label.toLowerCase()
      if pls is q
        return props[p]
      else if pls.indexOf(q) isnt -1
        partials.push props[p]
      else if pls.indexOf(qf) isnt -1
        firsts.push props[p]
    return partials.concat firsts

P.src.wikidata.property.terms = (prop, size=100, counts=true, alphabetical=false) ->
  prop ?= @params.terms ? @params.property
  terms = {}
  loops = false
  key = false
  max = 0
  lp = 0
  sz = if size < 1000 then size else 1000
  qr = 'snaks.property.exact:' + prop
  while @keys(terms).length < size and (loops is false or lp < loops)
    res = await @src.wikidata {q: qr, size: sz, from: sz*lp}
    max = res.hits.total if res?.hits?.total?
    loops = if not res?.hits?.total? then 0 else Math.floor res.hits.total / sz
    for rec in res?.hits?.hits ? []
      for snak in rec._source?.snaks ? []
        if snak.property is prop
          key = snak.key if snak.key? and key is false
          if not snak.value? and snak.qid?
            qv = await @src.wikidata snak.qid
            snak.value = qv.label if qv?
          if snak.value?
            if not terms[snak.value]?
              terms[snak.value] = 0
              qr += ' AND NOT snaks.qid.exact:' + snak.qid if snak.qid? and qr.split('AND NOT').length < 100 #what is max amount of NOT terms?
            terms[snak.value] += 1
    lp += 1
  out = []
  out.push({term: t, count: terms[t]}) for t of terms
  if alphabetical
    out = out.sort (a,b) -> if a.term.toLowerCase().replace(/ /g,'') > b.term.toLowerCase().replace(/ /g,'') then 1 else -1
  else
    out = out.sort (a,b) -> if b.count > a.count then 1 else -1
  return if counts then {property: key, total: max, terms: out} else out.map x => x.term


P.src.wikidata._flatten = (rec) ->
  res = {}
  for c in rec.snaks
    if not c.value and c.qid
      c.value = (await @src.wikidata _c.qid).label
    if not c.value and c.property
      c.value = (await @src.wikidata.property c).label
    if res[c.key]
      res[c.key] = [res[c.key]] if not Array.isArray res[c.key]
      res[c.key].push c.value
    else
      res[c.key] = c.value
  return res
