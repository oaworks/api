
P.tabulate = (ls, hide, tc='striped bordered') -> # convert list of objects to simple html table, nested
  headers = []
  t = '</tr></thead><tbody>'
  for obj in ls
    for o of obj
      headers.push(o) if o not in headers
    t += '<tr>'
    for k in headers
      t += '<td>'
      if Array.isArray obj[k]
        obj[k] = if obj[k].length is 0 then undefined else if obj[k].length is 1 then obj[k][0] else if typeof obj[k][0] isnt 'object' then obj[k].join(', ') else obj[k]
      if typeof obj[k] is 'object'
        obj[k] = [obj[k]] if not Array.isArray obj[k]
        t += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;" alt="View more" title="View more">' + obj[k].length + '...</a><pre style="display:none;background:transparent;color:#333;border:none;width:100%;">'
        t += P.tabulate obj[k], true
      else if obj[k]
        t += obj[k]
      t += '</td>'
    t += '</tr>'
  t += '</tbody></table>'
  head = '<tr>'
  head += '<th>' + (if h.toUpperCase() is h or h[0].toUpperCase() is h[0] then h else h[0].toUpperCase() + h.substr(1).toLowerCase()) + '</th>' for h in headers
  return '<table class="' + tc.trim() + '"' + (if hide? then ' style="display:none;"' else '') + '><thead>' + head + t

P.search = (opts) ->
  opts ?= {}
  opts.scope ?= 'body' # can be the ID of a div to append the search element to
  opts.msg ?= 'search...' # the first placeholder message displayed in the PSearch box
  opts.url ?= window.location.href.split('?')[0].replace '.html', '' # provide a search endpoint URL compatible with 7.x versions of ES
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
  opts.table ?= true # or could be list of keys such as ['DOI', 'title', 'year', 'ISSN'] or object of keys pointing to display names, or false for non-tabular default layout
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
      opts.search()
  opts.previous = (e) -> return opts.page e, true
  opts.next = (e) -> return opts.page e
  opts.from = () ->
    opts.query.from = parseInt P.val '.PSearchFrom'
    opts.search()
  opts.to = () ->
    opts.query.size = P.val('.PSearchTo') - (opts.query.from ? 0)
    opts.search()
  opts.scroller = () ->
    window.addEventListener 'scroll', () ->
      opts.next() if not opts.paging and (window.innerHeight + window.pageYOffset) >= document.body.offsetHeight

  opts.add = (e) ->
    try e.preventDefault()
    delete opts.query.from
    # TODO add range sliders and a way to get data out of them when they change
    if val = P.val e.target
      if val.startsWith 'opts.'
        if not val.includes ':' # print opts config to the search box placeholder
          opts.placeholder JSON.stringify P.dot opts, val.replace 'opts.', ''
        else # change the opts config to the provided value
          k = val.substr(5, val.indexOf(':')).replace ' ', ''
          v = val.substr(val.indexOf(':')+1).trim()
          try v = JSON.parse v
          opts.scroller() if opts.scroll is false and k is 'opts.scroll' and v is true
          try
            P.dot opts, k, v
            opts.search()
      else if val.includes(':') and not val.split(':')[0].includes(' ') and not val.includes('*') and not val.includes('~') and not val.includes(' AND ') and not val.includes ' OR '
        tf = term: {}
        tf.term[val.split(':')[0]] = val.split(':')[1].replace /"/g, ''
        opts.query.query.bool.filter.push tf
        opts.search()
      else
        if opts.fuzzy and not val.includes('*') and not val.includes('~') and not val.includes(':') and not val.includes('"') and not val.includes(' AND ') and not val.includes 'OR'
          val = val.trim().replace(/\s/g, opts.fuzzy + ' ') + opts.fuzzy
        opts.query.query.bool.filter.push {"query_string": {"default_operator": opts.operator, "query": val.replace(/"/g, '') }}
        opts.search()
    try P.set e.target, ''
    P.blur '.PSearch'

  opts.remove = (e) ->
    try e.preventDefault()
    if P('.PSearchRemove').length <= 2 or P.has e.target, '.PSearchRemoveAll'
      P.html '.PSearches', ''
    else
      P.remove e.target.closest 'a'
    opts.query.query.bool.filter = []
    delete opts.query.from
    opts.search()

  opts.placeholder = (pl) ->
    if not pl
      pl = if (opts.query.from ? 0) + (opts.query.size ? 10) < opts.response.hits.total then (opts.query.from ? 0) + (opts.query.size ? 10) else opts.response.hits.total
      pl += if pl isnt 0 then ' of ' + opts.response.hits.total else ''
    P.set '.PSearch', ''
    P.attr '.PSearch', 'placeholder', pl

  opts.translate = () ->
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
    qsf = JSON.stringify(opts.query.query.bool.filter).toLowerCase()
    P '.PSearchVal', (el) ->
      try val = P.val el
      try val ?= P.html el
      if val
        vc = (if val.includes(':') then val.split(':')[1] else val).toLowerCase().replace(/"/g, '')
        if not qsf.includes vc
          if val.includes ':'
            tf =  term: {}
            tf.term[val.split(':')[0]] = vc
            opts.query.query.bool.filter.push tf
          else
            opts.query.query.bool.filter.push {"query_string": {"default_operator": opts.operator, "query": val }}
    for f in opts.filters ? []
      try opts.query.query.bool.filter.push(f) if not qsf.includes JSON.stringify(f).toLowerCase()
    if opts.random
      opts.seed ?= opts.random if opts.random isnt true
      opts.seed ?= Math.floor Math.random()*1000000000000
      fq = {function_score : {random_score : {seed : opts.seed }}}
      fq.function_score.query = opts.query.query
      opts.query.query = fq
    else if opts.sort?
      opts.query.sort = if typeof opts.sort is 'function' then opts.sort() else opts.sort
    delete opts.query.aggregations if opts.paging
    if opts.method isnt 'POST'
      ou = opts.url.split('source=')[0]
      ou += if not ou.includes('?') then '?' else if not ou.endsWith('&') and not ou.endsWith('?') then '&' else '' 
      opts.url = ou + 'source=' + encodeURIComponent JSON.stringify opts.query
    return opts.query

  opts.first = true
  opts.success = (resp) ->
    P.hide '.PLoading'
    P.show '.PSearchResults'
    opts.response = resp
    if opts.first
      opts.first = false
    else
      opts.placeholder()
    opts.render()
    opts.construct()
    try opts.max = resp.hits.hits.length < (opts.query.size ? 10)
    opts.paging = false

  opts.error = (resp) ->
    P.hide '.PLoading'
    P.show '.PError'
    console.log resp
  opts.searching = false
  opts.search = (e) ->
    if not opts.searching
      opts.searching = true
      P.hide '.PError'
      P.hide('.PSearchResults') if not opts.paging
      P.show '.PLoading'
      P.attr('.PSearch', 'placeholder', 'searching...') if not opts.first
      setTimeout () ->
        o =
          success: opts.success
          error: opts.error
          data: opts.translate() # translate here so it does exist if necessary, but otherwise it at least still needs to run anyway
        delete o.data if opts.method isnt 'POST'
        o.url = opts.url
        if opts.username and opts.password
          o.headers = { "Authorization": "Basic " + btoa(opts.username + ":" + opts.password) }
        if opts.apikey
          o.headers = {apikey: opts.apikey}
        P.ajax o
        opts.searching = false
      , 300

  opts.render = () ->
    if opts.pushstate
      ws = window.location.search.split('source=')[0]
      if JSON.stringify(opts.query) isnt JSON.stringify opts.default
        ws += if not ws.includes('?') then '?' else if not ws.endsWith('&') then '&' else ''
        ws += 'source=' + JSON.stringify opts.query # url encode this?
      ws = ws.substr(0, ws.length-1) while ws.endsWith('&') or ws.endsWith('?')
      try window.history.pushState "", "search", ws
    try P.set '.PSearchFrom', (opts.query.from ? 0)
    try P.set '.PSearchTo', (opts.query.from ? 0) + (if opts.response?.hits?.hits? then opts.response.hits.hits.length else (opts.query.size ? 10))
    if not opts.paging
      P.html '.PSearches', '' # TODO and reset any range sliders or check buttons
      for filter in opts.query.query.bool.filter
        if JSON.stringify(filter).includes 'query_string'
          query = JSON.stringify(filter).split(':"').pop().split('}')[0].replace(/"/g, '').replace(/\*$/, '').replace(/\~$/, '')
          P.append '.PSearches', '<a class="button err PSearchRemove" href="#" alt="Remove" title="Remove"><span class="PSearchVal">' + query + '</span></a> '
        else if filter.term
          bt = '<a class="button err PSearchRemove" href="#" alt="Remove" title="Remove"><span class="PSearchVal">'
          for k of filter.term
            bt += ' ' + k.replace('.keyword','').split('.').pop() + ':' + filter.term[k]
          P.append '.PSearches', bt + '</span></a> '
        else if filter.range
          for kk of filter.range
            key = kk.replace('.keyword','').split('.').pop()
            gte = filter.range[kk].gte
            lte = filter.range[kk].lte
            # TODO adjust the relevant range filter sliders on the UI to match the values
      if opts.query.query.bool.filter.length
        P.append '.PSearches', '<a class="button err c1 PSearchRemove PSearchRemoveAll" href="#" alt="Remove all" title="Remove all">X</a>'
      P.on 'click', '.PSearchRemove', opts.remove

  opts.results = [] # all resulting records, after transform if present
  opts.result = (rec) -> # a function that draws a given result on the page (can be false to not draw results)
    if Array.isArray opts.table
      nt = {}
      nt[t] = '' for t in opts.table
      opts.table = nt
    re = if opts.table then '<tr' else '<p style="word-wrap: break-word; padding:5px; margin-bottom:0px;"'
    re += ' class="PSearchResult PResultFrom' + (opts.query.from ? 0) + '">'
    headers = P.html '.PSearchHeaders'
    for k of (if typeof opts.table is 'object' then opts.table else rec)
      kk = if typeof opts.table is 'object' and not Array.isArray(opts.table) and opts.table[k] then opts.table[k] else k
      P.append('.PSearchHeaders', '<th>' + kk + '</th>') if opts.table and not headers.includes kk
      re += if opts.table then '<td>' else '<b>' + kk + '</b>: '
      if Array.isArray rec[k]
        rec[k] = if rec[k].length is 0 then undefined else if rec[k].length is 1 then rec[k][0] else if typeof rec[k][0] isnt 'object' then rec[k].join(', ') else rec[k]
      if typeof rec[k] is 'object'
        rec[k] = [rec[k]] if not Array.isArray rec[k]
        re += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;" alt="View more" title="View more">' + rec[k].length + '...</a>' #'<pre style="display:none;background:transparent;color:#333;border:none;width:100%;">'
        #re += JSON.stringify(rec[k], undefined, 2) + '</pre>'
        re += P.tabulate rec[k], true
      else if rec[k]
        re += rec[k] #opts.link {text:rec[k][i],val:k+':'+rec[k][i]+''}
      re += if opts.table then '</td>' else ', '
    re += if opts.table then '</tr>' else '</p>'
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
      rec = if typeof opts.transform is 'function' then opts.transform(rec) else (rec._source ? rec.fields ? rec)
      opts.results.push rec
      P.append('.PSearchResults', opts.result rec) if typeof opts.result is 'function'

  if not opts.template and opts.template isnt false
    opts.template = '<div class="PSearchDiv"><div class="PSearchControls' + (if opts.sticky then ' sticky' else '') + ' pb5">'
    opts.template += '<div class="tab flex big">'
    opts.template += '<a href="#" class="button PSearchPrevious c1" alt="Previous page" title="Previous page">&lt;</a>' if opts.scroll is false
    opts.template += '<select class="PSuggester c1"><option value="" disabled="disabled" selected="selected">&#x2315;</option></select>' if opts.suggest
    opts.template += '<input type="text" class="PSearch" placeholder="' + opts.msg + '">'
    #opts.template += '<div class="loader big PLoading"><div class="loading"></div></div>'
    #opts.template += '<a class="button cream c1" style="font-size:2.3em;padding:0;" href="#">&#x2315;</a>'
    #opts.template += '<a href="#" class="button PSearchopts" alt="show/hide search options" title="show/hide search options">+</a>'
    opts.template += '<a href="#" class="button PSearchNext c1" alt="Next page" title="Next page">&gt;</a>' if opts.scroll is false
    opts.template += '</div>'
    opts.template += '<div class="PSuggestions"></div>' if opts.suggest
    opts.template += '<div class="PSearches tab flex" style="margin-top:-1px;"></div>' #<div class="PRange"></div>
    opts.template += '</div>'
    opts.template += if opts.table then '<table class="striped bordered' + (if false and opts.scope isnt 'body' then ' fixed' else '') + ' PSearchTable"><thead' + (if false and opts.sticky then ' class="sticky"' else '') + '><tr class="PSearchHeaders"></tr></thead><tbody class="PSearchResults"></tbody></table>' else '<div class="PSearchResults"></div>'
    opts.template += '<div class="PLoading" style="display: none; padding-bottom: 100px;"><div class="loading big"></div></div>'
    opts.template += '</div>'

  opts.ui ?= () ->
    if opts.template isnt false and not P '.PSearch'
      P.append opts.scope, opts.template
      P.css '.PSearchControls', 'background-color', (P.css(opts.scope, 'background') ? P.css(opts.scope, 'background-color') ? '#FFFFFC')
    P.on 'focus', '.PSearch', () -> try P.show '.POptions'
    P.on 'enter', '.PSearch', opts.add
    for k of opts
      if typeof opts[k] is 'function'
        # could some of these require click or keyup instead of change? how to tell?
        P.on 'change', '.PSearch' + k[0].toUpperCase() + k.substr(1).toLowerCase(), opts[k]
    opts.scroller() if opts.scroll isnt false
    try P.focus('.PSearch') if not P.mobile()
  opts.ui() if typeof opts.ui is 'function'

  for p of pp = P.params()
    if p not in ['search']
      opts.first = false if p is 'source'
      opts[if p is 'source' then 'query' else p] = pp[p]
  if opts.query
    delete opts.query.from if opts.scroll isnt false
    opts.search()
