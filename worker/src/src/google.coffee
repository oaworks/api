
# https://developers.google.com/custom-search/json-api/v1/overview#Pricing
# note technically meant to be targeted to a site but can do full search on free tier
# free tier only up to 100 queries a day. After that, $5 per 1000, up to 10k
# has to come from registered IP address
P.src.google = (q, id, key) ->
  q ?= this?.params?.q ? this?.params?.google
  id ?= @S.src.google?.secrets?.search?.id
  key ?= @S.src.google?.secrets?.search?.key
  if q and id and key
    url = 'https://www.googleapis.com/customsearch/v1?key=' + key + '&cx=' + id + '&q=' + q
    return await @fetch url
  else
    return {}

P.src.google.sheets = (opts) ->
  # expects a google sheet ID or a URL to a google sheets feed in json format
  # NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
  opts ?= this?.params ? {}
  opts = {sheetid: opts} if typeof opts is 'string'
  if (opts.sheets? or opts.sheet?) and not opts.sheetid?
    opts.sheetid = opts.sheet ? opts.sheets
    delete opts.sheet
    delete opts.sheets
  values = []
  if not opts.sheetid
    return values
  else if opts.sheetid.indexOf('http') is 0
    url = opts.sheetid
  else
    if opts.sheetid.indexOf('/spreadsheets/d/') isnt -1
      opts.sheetid = opts.sheetid.split('/spreadsheets/d/')[1].split('/')[0] 
    else if opts.sheetid.split('/').length is 2
      [opts.sheetid, opts.sheet] = opts.sheetid.split '/'
    opts.sheet ?= 'default' # or else a number, starting from 1, indicating which sheet in the overall sheet to access
    url = 'https://spreadsheets.google.com/feeds/list/' + opts.sheetid + '/' + opts.sheet + '/public/values?alt=json'

  g = await @fetch url, headers: 'Cache-Control': 'no-cache'
  for l of g.feed.entry
    val = {}
    for k of g.feed.entry[l]
      try val[k.replace('gsx$','')] = g.feed.entry[l][k].$t if k.indexOf('gsx$') is 0 and g.feed.entry[l][k].$t? and g.feed.entry[l][k].$t isnt ''
    keys = @keys val
    values.push(val) if keys.length > 1 or (keys.length and val[keys[0]] not in ['Loading...','#REF!'])

  g = undefined
  return values

P.src.google.sheets._bg = true
#P.src.google.sheets._async = true


# https://developers.google.com/hangouts/chat
# NOTE this will need oauth configuration for a full bot. For now just a web hook
# https://developers.google.com/hangouts/chat/how-tos/webhooks	
# pradm dev "pradm alert" google chat webhook
P.src.google.chat = (params, url) ->
  params = {text: params} if typeof params is 'string'
  params ?= @params
  headers = "Content-Type": 'application/json; charset=UTF-8' # any other possible headers?
  data = method: 'POST', headers: headers, body: text: decodeURIComponent params.text ? params.msg ? params.body ? ''
  url ?= @S.src.google?.secrets?.chat # should url be allowed on params? doesn't strictly need to be secret, the key and token it uses only work for the webhook
  if data.body.text and url?
    return @fetch url, data
  else
    return undefined


'''
# docs:
# https://developers.google.com/places/web-service/autocomplete
# example:
# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>


# https://developers.google.com/knowledge-graph/
# https://developers.google.com/knowledge-graph/reference/rest/v1/
API.use.google.knowledge.retrieve = (mid,types) ->
  exists = API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve'
  return exists if exists
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=1&ids=' + mid
  if types
    types = types.join('&types=') if typeof types isnt 'string' # are multiple types done by comma separation or key repetition?
    u += '&types=' + types
  ret = {}
  try
    res = API.http.proxy 'GET', u, true
    ret = res.data.itemListElement[0].result
    ret.score = res.data.itemListElement[0].resultScore
  if not _.isEmpty ret
    API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve', ret
  return ret

API.use.google.knowledge.search = (qry,limit=10,refresh=604800000) -> # default 7 day cache
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=' + limit + '&query=' + encodeURIComponent qry
  API.log 'Searching google knowledge for ' + qry

  checksum = API.job.sign qry
  exists = API.http.cache checksum, 'google_knowledge_search', undefined, refresh
  return exists if exists

  res = API.http.proxy('GET',u,true).data
  try API.http.cache checksum, 'google_knowledge_search', res
  return res

API.use.google.knowledge.find = (qry) ->
  res = API.use.google.knowledge.search qry
  try
    return res.itemListElement[0].result #could add an if resultScore > ???
  catch
    return undefined

# https://cloud.google.com/natural-language/docs/getting-started
# https://cloud.google.com/natural-language/docs/basics
API.use.google.cloud.language = (content, actions=['entities','sentiment'], auth) ->
  actions = actions.split(',') if typeof actions is 'string'
  return {} if not content?
  checksum = API.job.sign content, actions
  exists = API.http.cache checksum, 'google_language'
  return exists if exists

  lurl = 'https://language.googleapis.com/v1/documents:analyzeEntities?key=' + API.settings.use.google.serverkey
  document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}
  result = {}
  if 'entities' in actions
    try result.entities = API.http.proxy('POST',lurl,{data:document,headers:{'Content-Type':'application/json'}},true).data.entities
  if 'sentiment' in actions
    try result.sentiment = API.http.proxy('POST',lurl.replace('analyzeEntities','analyzeSentiment'),{data:document,headers:{'Content-Type':'application/json'}},true).data
  API.http.cache(checksum, 'google_language', result) if not _.isEmpty result
  return result

# https://cloud.google.com/translate/docs/quickstart
API.use.google.cloud.translate = (q, source, target='en', format='text') ->
  # ISO source and target language codes
  # https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
  return {} if not q?
  checksum = API.job.sign q, {source: source, target: target, format: format}
  exists = API.http.cache checksum, 'google_translate'
  return exists if exists
  lurl = 'https://translation.googleapis.com/language/translate/v2?key=' + API.settings.use.google.serverkey
  result = API.http.proxy('POST', lurl, {data:{q:q, source:source, target:target, format:format}, headers:{'Content-Type':'application/json'}},true)
  if result?.data?.data?.translations
    res = result.data.data.translations[0].translatedText
    API.http.cache(checksum, 'google_language', res) if res.length
    return res
    #return result.data.data
  else
    return {}

API.use.google.places.autocomplete = (qry,location,radius) ->
  url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' + qry + '&key=' + API.settings.use.google.serverkey
  url += '&location=' + location + '&radius=' + (radius ? '10000') if location?
  try
    return API.http.proxy('GET',url,true).data
  catch err
  return {status:'error', error: err}

API.use.google.places.place = (id,qry,location,radius) ->
  if not id?
    try
      results = API.use.google.places.autocomplete qry,location,radius
      id = results.predictions[0].place_id
    catch err
      return {status:'error', error: err}
  url = 'https://maps.googleapis.com/maps/api/place/details/json?placeid=' + id + '&key=' + API.settings.use.google.serverkey
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.places.url = (qry) ->
  try
    results = API.use.google.places.place undefined,qry
    return {data: {url:results.result.website.replace('://','______').split('/')[0].replace('______','://')}}
  catch err
    return {status:'error', error: err}

API.use.google.places.nearby = (params={}) ->
  url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
  params.key ?= API.settings.use.google.serverkey
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.places.search = (params) ->
  url = 'https://maps.googleapis.com/maps/api/place/textsearch/json?'
  params.key ?= API.settings.use.google.serverkey
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.sheets.api = {}
# https://developers.google.com/sheets/api/reference/rest
API.use.google.sheets.api.get = (sheetid, opts={}) ->
  opts = {stale:opts} if typeof opts is 'number'
  opts.stale ?= 3600000
  opts.key ?= API.settings.use.google.serverkey
  try
    sheetid = sheetid.split('/spreadsheets/d/')[1].split('/')[0] if sheetid.indexOf('/spreadsheets/d/') isnt -1
    url = 'https://sheets.googleapis.com/v4/spreadsheets/' + sheetid
    url += '/values/' + opts.start + ':' + opts.end if opts.start and opts.end
    url += '?key=' + opts.key
    API.log 'Getting google sheet via API ' + url
    g = HTTP.call 'GET', url
    return g.data ? g
  catch err
    return err

# auth for sheets interactions that makes changes is complex, requiring oauth and an email account to be registered to the sheet, it seems
# https://developers.google.com/sheets/api/guides/authorizing
# https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/append
# https://developers.google.com/identity/protocols/oauth2
# https://developers.google.com/sheets/api/quickstart/nodejs#step_3_set_up_the_sample
# https://cloud.google.com/apigee/docs/api-platform/security/oauth/access-tokens
# https://docs.wso2.com/display/IntegrationCloud/Get+Credentials+for+Google+Spreadsheet
# https://help.gooddata.com/doc/en/building-on-gooddata-platform/data-preparation-and-distribution/additional-data-load-reference/data-load-tutorials/load-data-from-google-spreadsheets-via-google-api
# https://isd-soft.com/tech_blog/accessing-google-apis-using-service-account-node-js/
API.use.google.sheets.api.values = (sheetid, opts={}) ->
  opts.start ?= 'A1'
  if not opts.end?
    sheet = if typeof sheetid is 'object' then sheetid else API.use.google.sheets.api.get sheetid, opts
    opts.sheet ?= 0 # could also be the ID or title of a sheet in the sheet... if so iterate them to find the matching one
    rows = sheet.sheets[opts.sheet].properties.gridProperties.rowCount
    cols = sheet.sheets[opts.sheet].properties.gridProperties.columnCount
    opts.end = ''
    ls = Math.floor cols/26
    opts.end += (ls + 9).toString(36).toUpperCase() if ls isnt 0
    opts.end += (cols + 9-ls).toString(36).toUpperCase()
    opts.end += rows
  values = []
  try
    keys = false
    res = API.use.google.sheets.api.get sheetid, opts
    opts.keys ?= 0 # always assume keys? where to tell which row to get them from? 0-indexed or 1-indexed or named?
    keys = opts.keys if Array.isArray opts.keys
    for s in res.values
      if opts.keys? and keys is false
        keys = s
      else
        obj = {}
        for k of keys
          try
            obj[keys[k]] = s[k] if s[k] isnt ''
        values.push(obj) if not _.isEmpty obj
    return values
	
'''
