
P.search = (opts) ->
  opts ?= {}
  opts.msg ?= 'search...' # the first placeholder message displayed in the PSearch box
  opts.url ?= window.location.href.split('?')[0].replace '.html', '' # provide a search endpoint URL compatible with 7.x versions of ES
  # opts.translate can be an optional function to translate the query to suit a different kind of endpoint (or just overwrite opts.qry, which builds the query)
  # note that if the query response is going to be different, other rewrites will be needed too
  opts.default ?= {query: {bool: {must: [], filter: []}}}
  # opts.size can be defined separately to save writing the whole default query, defaults to 10
  # opts.sort can be any ES sort format
  # or opts.random can be true to convert the query to a constant_score random sort query with seed for paging (opts.seed can optionally be provided too)
  # opts.aggregations can be defined separate from default query to save having to rewrite the whole thing
  opts.query ?= true # this could be false to not run a query at startup, or can be defined if the startup query should be different from default
  opts.operator ?= "AND" # query operator param for the search box query params
  opts.fuzzy ?= "*" # fuzzify the search box query params if they are simple strings. Can be * or ~ or if false the query will not be fuzzified
  opts.pushstate ?= true # try pushing query state to browser URL bar or not
  opts.sticky ?= true # if sticky, the search bar should stick to the top when scrolling up
  opts.scroll ?= true # when results are scrolled to bottom retrieve the next set of results
  # opts.method can be set to POST to force an ajax POST, otherwise query will be a GET with ?source= stringified query
  opts.table = ['DOI', 'title', 'year', 'ISSN']
  P.search.opts = opts

  opts.paging = false
  opts.max = false
  opts.page = (e, previous) -> # best to call this via previous or next
    try e.preventDefault()
    opts.query.from = (opts.query.from ? 0) + ((if previous then -1 else 1) * (opts.query.size ? 10))
    opts.query.from = 0 if opts.query.from < 0
    if P '.PResultFrom' + opts.query.from
      P.hide '.PSearchResult'
      P.show '.PResultFrom' + opts.query.from
      opts.placeholder()
    else if not opts.max
      P.show '.PLoading'
      opts.paging = true
      opts.execute()
  opts.previous = (e) -> return opts.page e, true
  opts.next = (e) -> return opts.page e
  opts.from = () ->
    opts.query.from = parseInt P.val '.PSearchFrom'
    opts.execute()
  opts.to = () ->
    opts.query.size = P.val('.PSearchTo') - (opts.query.from ? 0)
    opts.execute()
  opts.scroller = () ->
    window.addEventListener 'scroll', () ->
      opts.next() if not opts.paging and (window.innerHeight + window.pageYOffset) >= document.body.offsetHeight

  opts.add = (e) ->
    try e.preventDefault()
    delete opts.query.from
    # TODO add range sliders and a way to get data out of them when they change
    if val = P.val e.target
      if val.indexOf('opts.') is 0
        if val.indexOf(':') is -1 # print opts config to the search box placeholder
          opts.placeholder P.dot opts, val.replace 'opts.', ''
        else # change the opts config to the provided value
          k = val.substring(8, val.indexOf(':')).replace ' ', ''
          v = val.substring(val.indexOf(':')+1).trim()
          try v = JSON.parse v
          opts.scroller() if opts.scroll is false and k is 'opts.scroll' and v is true
          try
            P.dot opts, k, v
            opts.execute()
      else if val.indexOf(':') isnt -1 and val.split(':')[0].indexOf(' ') is -1 and val.indexOf('*') is -1 and val.indexOf('~') is -1 and val.indexOf(' AND ') is -1 and val.indexOf(' OR ') is -1
        tf =  term: {}
        tf.term[val.split(':')[0]] = val.split(':')[1].replace /"/g, ''
        opts.query.query.bool.filter.push tf
        opts.execute()
      else if val.startsWith('"') and val.endsWith '"'
        opts.query.query.bool.filter.push {"match_phrase": {"_all": val.replace(/"/g, '')}}
        opts.execute()
      else
        opts.query.query.bool.filter.push {"query_string": {"default_operator": opts.operator, "query": opts.fuzzify val }}
        opts.execute()
    try P.set e.target, ''
    P.blur '.PSearch'

  opts.remove = (e) ->
    try e.preventDefault()
    P.remove e.target.closest 'a'
    if false # TODO if it's the remove all button...
      opts.query = undefined
    else
      opts.query.query.bool.filter = []
      delete opts.query.from
    opts.execute()

  opts.placeholder = (pl) ->
    if not pl
      pl = if (opts.query.from ? 0) + (opts.query.size ? 10) < opts.response.hits.total then (opts.query.from ? 0) + (opts.query.size ? 10) else opts.response.hits.total
      pl += if pl isnt 0 then ' of ' + opts.response.hits.total else ''
    P.set '.PSearch', ''
    P.attr '.PSearch', 'placeholder', pl

  opts.suggesting = false
  opts.suggestions = (e) ->
    try e.preventDefault()
    opts.query.query.bool.filter.splice(-1,1) if opts.query.query.bool.filter.length isnt 0
    if (e.keyCode ? e.which) is 13
      opts.add e
    else
      opts.suggesting = true
      opts.query.query.bool.filter.push {"query_string":{"query": opts.fuzzify P.val e.target }}
      opts.execute()
  opts.suggest = (data) ->
    data ?= opts.response
    P.html '.PSuggestions', ''
    for a in data.aggregations ? []
      for j in a.buckets
        P.append '.PSuggestions', j.key + ' (' + j.doc_count + ')<br>' # how to make this a link that triggers a search

  opts.fuzzify = (str) ->
    if opts.fuzzy and str.indexOf('*') is -1 and str.indexOf('~') is -1 and str.indexOf(':') is -1 and str.indexOf('"') is -1  and str.indexOf('AND') is -1 and str.indexOf('OR') is -1 and str.indexOf(' ') is -1
      ns = ''
      for part in str.split ' '
        if part.length
          part += opts.fuzzy
          part = '*' + part if opts.fuzzy is '*'
          ns += part + ' '
      return ns
    else
      return str

  opts.qry = () ->
    for a in opts.aggregations ? []
      opts.default.aggregations ?= []
      opts.default.aggregations.push if typeof a is 'string' then {terms: {field: a}} else a
    opts.default.size ?= opts.size
    for sk in ['includes', 'excludes']
      if opts[sk]?
        opts.default._source ?= {}
        opts.default._source[sk] ?= opts[sk]
    if opts.filters
      opts.default.query.bool.filter = opts.filters
    delete opts.query if typeof opts.query isnt 'object' # it can be true or false at startup
    opts.query ?= JSON.parse JSON.stringify opts.default
    P '.PSearchVal', (el) ->
      try val = P.val el
      try val ?= P.html el
      if val
        if val.indexOf(':') isnt -1
          tf =  term: {}
          tf.term[val.split(':')[0]] = val.split(':')[1].replace /"/g, ''
          opts.query.query.bool.filter.push tf
        else if val.indexOf('*') isnt -1 or val.indexOf('~') isnt -1 or val.indexOf(' AND ') isnt -1 or val.indexOf(' OR ') is -1
          opts.query.query.bool.filter.push {"query_string": {"default_operator": opts.operator, "query": val }}
        else
          opts.query.query.bool.filter.push {"match_phrase": {"_all": val}}
    for f in opts.filters ? []
      qsf = JSON.stringify opts.query.query.bool.filter
      try opts.query.query.bool.filter.push(f) if qsf.indexOf(JSON.stringify(f)) is -1
    if opts.random
      opts.seed ?= opts.random if opts.random isnt true
      opts.seed ?= Math.floor Math.random()*1000000000000
      fq = {function_score : {random_score : {seed : opts.seed }}}
      fq.function_score.query = opts.query.query
      opts.query.query = fq
    else if opts.sort?
      opts.query.sort = if typeof opts.sort is 'function' then opts.sort() else opts.sort
    delete opts.query.aggregations if opts.paging
    opts.query = opts.translate(opts.query) if typeof opts.translate is 'function'
    if opts.method isnt 'POST'
      ou = opts.url.split('source=')[0]
      ou += if ou.indexOf('?') is -1 then '?' else if not ou.endsWith('&') and not ou.endsWith('?') then '&' else '' 
      opts.url = ou + 'source=' + encodeURIComponent JSON.stringify opts.query
    return opts.query

  opts._first = true
  opts.success = (resp) ->
    P.hide '.PLoading'
    opts.response = resp
    if opts.suggesting
      opts.suggest()
    else
      if opts._first
        opts._first = false
      else
        opts.placeholder()
      opts.render()
      opts.construct()
    try opts.max = not opts.suggesting and resp.hits.hits.length < (opts.query.size ? 10)
    opts.suggesting = false
    opts.paging = false

  opts.error = (resp) ->
    P.hide '.PLoading'
    P.show '.PError'
    console.log resp
  opts.executing = false
  opts.execute = (e) ->
    if not opts.executing
      opts.executing = true
      P.hide '.PError'
      P.show '.PLoading'
      P.attr('.PSearch', 'placeholder', 'searching...') if not opts._first
      setTimeout () ->
        o =
          success: opts.success
          error: opts.error
          data: opts.qry() # create this here so it does exist if necessary, but otherwise it at least still needs to run anyway
        delete o.data if opts.method isnt 'POST'
        o.url = opts.url
        if opts.username and opts.password
          o.headers = { "Authorization": "Basic " + btoa(opts.username + ":" + opts.password) }
        if opts.apikey
          o.headers = {apikey: opts.apikey}
        P.ajax o
        opts.executing = false
      , 300

  opts.render = () ->
    if opts.pushstate and not opts.suggesting
      ws = window.location.search.split('source=')[0]
      if JSON.stringify(opts.query) isnt JSON.stringify opts.default
        ws += if ws.indexOf('?') is -1 then '?' else if not ws.endsWith('&') then '&' else ''
        ws += 'source=' + JSON.stringify opts.query # url encode this?
      ws = ws.substring(0,ws.length-1) if ws.endsWith('&') or ws.endsWith('?')
      try window.history.pushState "", "search", ws
    try P.set '.PSearchFrom', (opts.query.from ? 0)
    try P.set '.PSearchTo', (opts.query.from ? 0) + (if opts.response?.hits?.hits? then opts.response.hits.hits.length else (opts.query.size ? 10))
    try P.html '.PSearches', '' # TODO and reset any range sliders or check buttons
    for f of opts.query.query.bool.filter
      filter = opts.query.query.bool.filter[f]
      if JSON.stringify(filter).indexOf('match_all') is -1
        query = JSON.stringify(filter).split(':"').pop().split('}')[0].replace /"/g, ''
        P.append '.PSearches', '<a class="button PSearchRemove" href="#"><b>X</b> <span class="PSearchVal">' + query + '</span></a>'
      else if filter.term
        bt = '<a style="margin:5px;" class="button PSearchRemove" href="#"><b>X</b> <span class="PSearchVal">'
        for k of filter.term
          bt += ' ' + k.replace('.keyword','').split('.').pop() + ':' + filter.term[k]
        P.append '.PSearches', bt + '</span></a>'
      else if filter.range
        for kk of filter.range
          key = kk.replace('.keyword','').split('.').pop()
          gte = filter.range[kk].gte
          lte = filter.range[kk].lte
          # TODO adjust the relevant range filter sliders on the UI to match the values
    if opts.query.query.bool.filter.length > 2
      P.append '.PSearches', '<a class="button PSearchRemove" href="#">clear all</a>'
    P.listen 'click', '.PSearchRemove', opts.remove

  opts.results = [] # all resulting records, after transform if present
  opts.result = (rec) -> # a function that draws a given result on the page (can be false to not draw results)
    # table can be false for a simple text layout. OR it can be undefined, which defaults to building a table of every key in the result records
    # table can be a list of keys to include, or an object of keys pointing to preferred header names to use
    if not opts._table_was_defined?
      opts._table_was_defined = typeof opts.table is 'object'
    if Array.isArray opts.table
      nt = {}
      nt[t] = '' for t in opts.table
      opts.table = nt
    re = if opts.table isnt false then '<tr' else '<p style="word-wrap: break-word; padding:5px; margin-bottom:0px;"'
    re += ' class="PSearchResult PResultFrom' + (opts.query.from ? 0) + '">'
    headers = P.html '.PSearchHeaders'
    for k of (if typeof opts.table is 'object' then opts.table else rec)
      kk = if typeof opts.table is 'object' and opts.table[k] then opts.table[k] else k
      opts.table ?= {}
      if opts.table isnt false
        if not opts._table_was_defined
          opts.table[k] ?= ''
        P.append('.PSearchHeaders', '<th>' + kk + '</th>') if headers.indexOf(kk) is -1
      re += if opts.table isnt false then '<td>' else '<b>' + kk + '</b>: '
      if Array.isArray rec[k]
        rec[k] = if rec[k].length is 0 then undefined else if rec[k].length is 1 then rec[k][0] else rec[k]
        if Array.isArray rec[k] # if still an array of strings, join them
          objects = false
          for s in rec[k]
            if typeof s is 'object'
              objects = true
              break
          rec[k] = rec[k].join(', ') if not objects
      if rec[k]
        re += if typeof rec[k] is 'object' then JSON.stringify(rec[k]) else rec[k] #opts.link {text:rec[k][i],val:k+':'+rec[k][i]+''}
      re += if opts.table isnt false then '</td>' else ', '
    re += if opts.table isnt false then '</tr>' else '</p>'
    return re

  opts.transform = false # an optional function that transforms an individual result
  opts.construct = (data) ->
    data ?= JSON.parse JSON.stringify opts.response
    data = data.hits.hits if data?.hits?.hits?
    if opts.paging
      P.hide('.PSearchResult') if opts.scroll is false
    else
      opts.results = []
      P.html '.PSearchResults', ''
    for rec in data ? []
      rec = if typeof opts.transform is 'function' then opts.transform(rec) else if rec._source? then rec._source else rec
      opts.results.push rec
      P.append('.PSearchResults', opts.result rec) if typeof opts.result is 'function'

  if not opts.template and opts.template isnt false
    # NOTE: TODO sticky is not working yet in this layout
    opts.template = '<div class="container big PSearchDiv"><div' + (if opts.sticky then ' class="sticky"' else '') + '>'
    opts.template += '<a href="#" class="button PSearchPrevious" alt="previous" title="previous">&lt;</a>' if opts.scroll is false
    opts.template += '<input style="margin-top:5px;" type="text" class="PSearch big" placeholder="' + opts.msg + '">' # can add PSuggest to this to trigger suggestions
    #opts.template += '<a href="#" class="button PSearchopts" alt="show/hide search options" title="show/hide search options">+</a>'
    opts.template += '<a href="#" class="button PSearchNext" alt="next" title="next">&gt;</a>' if opts.scroll is false
    opts.template += '<div class="PSuggestions"></div><div class="PSearches" style="margin-top:5px; margin-bottom:5px;"></div>' #<div class="PRange"></div>
    opts.template += if opts.table isnt false then '<table class="striped"><thead' + (if opts.sticky then ' class="sticky"' else '') + '><tr class="PSearchHeaders"></tr></thead><tbody class="PSearchResults"></tbody></table>' else '<div class="PSearchResults"></div>'
    opts.template += '<div class="PLoading" style="display:none;"><div class="loading big"></div></div>'
    opts.template += '</div></div>'
  
  opts.ui ?= () ->
    if opts.template isnt false and not P '.PSearch'
      P.append 'body', opts.template
    P.on 'focus', '.PSearch', () -> try P.show '.POptions'
    P.on 'enter', '.PSearch', opts.add
    P.on 'keyup', '.PSuggest', opts.suggestions, 600
    for k of opts
      if typeof opts[k] is 'function'
        # could some of these require click or keyup instead of change? how to tell?
        P.on 'change', '.PSearch' + k.substring(0,1).toUpperCase() + k.substring(1).toLowerCase(), opts[k]
    opts.scroller() if opts.scroll isnt false
    try P.focus '.PSearch'
  opts.ui() if typeof opts.ui is 'function'

  for p of pp = P.params()
    if p not in ['search']
      opts[if p is 'source' then 'query' else p] = pp[p]
  if opts.query
    delete opts.query.from if opts.scroll isnt false
    opts.execute() 
