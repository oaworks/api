
P.suggest = (opts, scope) ->
  opts ?= {}
  opts.scope ?= scope ? ''
  opts.scope += ' ' if opts.scope and not opts.scope.endsWith ' '
  opts.query ?= false # opts.query can be set to true or to an ES default query, otherwise the search string is just appended to the url
  opts.fuzzy ?= '*'
  #opts.key = 'name' # this can be set to the key from a result object to find the display value in, otherwise it looks for defaults [title, name, DOI, _id, value]
  #opts.include = ['_id'] # optionally define to provide objects in return, including the specified keys (and the suggest key)
  # option to provide vals list instead of remote query worthwhile?
  opts.counts ?= true # shows counts from ES aggs in suggestion string (if available)
  #opts.url =  '' # provide a search endpoint URL compatible with 7.x versions of ES - can also be provided on the element, and that's how to do it for multiple elements

  opts.suggestion ?= (e, val, rec, cls) ->
    # e is the event, val is the suggestion value that was selected, rec is the corresponding record if there was one, cls is the classname to group by if there is more than one suggester on the page
    return # customise this function to do whatever is the preferred action on clicking a suggestion (it will already clear the suggestions and fill the box)

  opts.terms ?= [] # TODO store terms here for re-use, and have a way to pick from them instead of making a remote call if not necessary (and these may be strings or objects)

  P.suggesting = false
  opts.suggestions = (e) ->
    try e.preventDefault()

    url = P.attr(e.target, 'url') ? opts.url ? window.location.href.split('?')[0].replace '.html', ''
    for c in P.classes e.target
      cls = c if c.startsWith 'PFor'

    str = P.val e.target
    str = str.trim() if str

    if str and (not opts.starter or not str.startsWith opts.starter) # no point searching if term is same, or still adding to a term that already returned nothing
      P.suggesting = true
      agg = P.attr e.target, 'agg'
      if opts.query or agg
        q = if typeof opts.query is 'object' then JSON.parse(JSON.stringify(opts.query)) else {query: {bool: {filter: []}}}
        if opts.query and opts.fuzzy and str.indexOf('*') is -1 and str.indexOf('~') is -1 and str.indexOf(':') is -1 and str.indexOf('"') is -1  and str.indexOf('AND') is -1 and str.indexOf('OR') is -1
          str = (if opts.fuzzy is '*' then '*' else '') + str.trim().replace(/\s/g, opts.fuzzy + ' ' + (if opts.fuzzy is '*' then '*' else '')) + opts.fuzzy
        q.query.bool.filter.push {"query_string":{"query": str }}
        if agg and not q.aggregations
          q.size ?= 0
          q.aggregations = {}
          q.aggregations[agg] = terms: field: agg, size: 100

      su = url + (if not opts.query then str else if opts.method is 'POST' then '' else '?source=' + JSON.stringify q)
      su += (if su.includes('?') then '&' else '?') + 'include=' + (if typeof opts.include is 'string' then opts.include else opts.include.join(',')) if opts.include
      o =
        url: su
        success: (data) =>
          P.suggesting = false
          P.html opts.scope + '.PSuggestions ' + (cls ? ''), ''
          opts.suggest data, cls
      o.data = q if opts.method is 'POST' and opts.query
      o.headers = { "Authorization": "Basic " + btoa(opts.username + ":" + opts.password) } if opts.username and opts.password
      o.headers = {apikey: opts.apikey} if opts.apikey
      P.ajax o
    else if not str
      P.html opts.scope + '.PSuggestions ' + (cls ? ''), ''
    else
      opts.starter = str

  P.on 'keyup', opts.scope + '.PSuggest', opts.suggestions, 800

  opts.suggest = (data, cls) ->
    cls = opts.scope + '.PSuggestions' + (if cls then ' ' + cls.replace('.', '') else '')
    clsn = cls.replace '.PSuggestions', 'PSuggestion'
    if (not Array.isArray(data) and data?.aggregations) or (Array.isArray(data) and data.length and data[0].doc_count?)
      da = if Array.isArray(data) then data else data.aggregations
      for agg of da
        for k in da[agg].buckets ? []
          P.append cls, '<a class="' + clsn + '" href="' + k.key + '" key="' + agg '">' + k.key + '</a>' + (if opts.counts and k.doc_count > 1 then ' (' + k.doc_count + ')' else '') + '<br>'
    else
      opts._data = []
      counter = 0
      for k in (if Array.isArray(data) then data else (data?.hits?.hits ? []))
        if typeof k is 'string'
          P.append cls, '<a class="' + clsn + '" href="' + k + '">' + k + '</a><br>'
        else
          k = k._source if k._source
          opts.key ?= if k.title then 'title' else if k.name then 'name' else if k.DOI then 'DOI' else if k._id then '_id' else if k.value then 'value' else undefined
          P.append cls, '<a class="' + clsn + '" href="' + (k[opts.key] ? '#') + '" key="' + counter + '">' + (k[opts.key] ? JSON.stringify(k)) + '</a><br>'
        opts._data.push k
        counter += 1

  P.on 'click', opts.scope + '.PSuggestion', (e) ->
    try e.preventDefault()
    for c in P.classes e.target
      cls = c if c.startsWith 'PFor'
    P.html opts.scope + '.PSuggestions ' + (cls ? ''), ''
    val = P.attr e.target, 'href'
    P.set '.PSuggest ' + (cls ? ''), val
    # TODO if on a pradm search context, should be putting the val in the search box and trigger it?
    opts.suggestion e, val, opts._data?[P.attr e.target, 'key'], cls
  , 800
