
S.src.google ?= {}
try S.src.google.secrets = JSON.parse SECRETS_GOOGLE

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
  # NOTE the sheet must be published for this to work, should have the data in Sheet1, and should have columns of data with key names in row 1
  # https://support.google.com/docs/thread/121088347/retrieving-data-from-sheets-results-in-404-error-50-of-the-time
  opts ?= @copy @params
  opts = {sheetid: opts} if typeof opts is 'string'
  if (opts.sheets? or opts.sheet?) and not opts.sheetid?
    opts.sheetid = opts.sheet ? opts.sheets
    delete opts.sheet
    delete opts.sheets
  if not opts.sheetid
    return []
  else if opts.sheetid.startsWith('http') and opts.sheetid.includes 'sheets.googleapis.com/v4/'
    url = opts.sheetid
  else
    if opts.sheetid.includes '/spreadsheets/'
      sid = opts.sheetid.replace('/spreadsheets/d/', '/spreadsheets/').split('/spreadsheets/')[1].split('/')[0]
      if not opts.sheet and opts.sheetid.includes '/values/'
        opts.sheet = opts.sheetid.split('/values/')[1].split('?')[0].split('#')[0]
      opts.sheetid = sid
    else if opts.sheetid.split('/').length is 2
      [opts.sheetid, opts.sheet] = opts.sheetid.split '/'
    opts.sheet ?= 'Sheet1' # needs to be the name of a sheet within the sheet
    # also possible to add sheet ranges in here, and use to update sheet if not just a public one being read (see below for a start on using full v4 API)
    # an API key is now NECESSARY even though this is still only for sheets that are published public. Further auth required to do more.
    url = 'https://sheets.googleapis.com/v4/spreadsheets/' + opts.sheetid + '/values/' + opts.sheet + '?alt=json&key=' + (@S.src.google?.secrets?.serverkey ? @S.src.google?.secrets?.apikey)

  g = await @fetch url, headers: 'Cache-Control': 'no-cache'
  if opts.values is false
    return g
  else if opts.headers is false
    return g.values
  else
    if Array.isArray opts.headers
      headers = opts.headers
    else
      headers = []
      if g.values?
        toprow = g.values.shift() # NOTE there is NO WAY to identify column headers any more it seems, certainly not from this response format. Just pop them off the values list
        for hd in toprow
          try hd = hd.trim()
          headers.push hd #.toLowerCase().replace /[^a-z0-9]/g, ''
    values = []
    for l in g.values
      val = {}
      for h of headers
        #try l[h] = l[h].trim()
        #try
        #  l[h] = true if l[h].toLowerCase() is 'true'
        #  l[h] = false if l[h].toLowerCase() is 'false'
        #try
        #  if ((l[h].startsWith('[') and l[h].endsWith(']')) or (l[h].startsWith('{') and l[h].endsWith('}')))
        #    try l[h] = JSON.parse l[h]
        #if opts.dot isnt false and typeof l[h] isnt 'object' and headers[h].includes '.'
        #  try
        #    await @dot val, headers[h], l[h]
        #  catch
        #    try val[headers[h]] = l[h]
        #else
        try val[headers[h]] = l[h]
      values.push(val) if JSON.stringify(val) isnt '{}'
  
    return values

P.src.google.sheets._bg = true

