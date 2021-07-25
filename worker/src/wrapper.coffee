
# API calls this to wrap functions on P, apart from top level functions and ones 
# that start with _ or that indicate no wrapping with _wrap: false
# wrapper settings declared on each P function specify which wrap actions to apply
# _auth and _cache settings on a P function are handled by API BEFORE _wrapper is 
# used, so _auth and _cache are not handled within the wrapper
# the wrapepr logs the function call (whether it was the main API call or subsequent)

P._wrapper = (f, n) -> # the function to wrap and the string name of the function
  return () ->
    started = Date.now() # not accurate in a workers environment, but close enough
    rt = n.replace /\./g, '_'
    lg = fn: n

    # _limit can be true, which stays in place until the function completes, or it can be a number which 
    # will be the lifespan of the limit record in the KV store
    # _limit
    if f._limit
      limited = await @kv 'limit/' + n
      while limited
        lg.limited ?= 0
        lg.limited += limited
        await @sleep limited - started
        limited = await @kv 'limit/' + n

    # check for an _async param request and look to see if it is in the async finished store
    # if so, serve the result otherwise re-serve the param to indicate waiting should continue
    # _async
    if typeof @params._async in ['string', 'number']
      if res = await @kv 'async/' + @params._async, ''
        if typeof res is 'string' and res.includes('/') and not res.includes(' ') and not res.includes(':') and not res.startsWith('10.') and res.split('/').length is 2
          try res = await @kv(res) if f._kv
          try res = await @index(res) if not res? and f._index # async stored the _id for the result
        try res = JSON.parse(res) if typeof res is 'string' and (res.startsWith('{') or res.startsWith('['))
      else
        res = _async: @params._async # user should keep waiting

    # serve the underlying sheet / csv link if configured and asked for it
    # _sheet
    else if @fn is n and f._sheet and @parts.indexOf('sheet') is @parts.length-1
      res = status: 302
      if f._sheet.startsWith 'http'
        res.body = f._sheet
      else if @format is 'json' # TODO make it handle sheet and sheet ID in cases where both are provided
        res.body = 'https://spreadsheets.google.com/feeds/list/' + f._sheet + '/' + 'default' + '/public/values?alt=json'
      else
        res.body = 'https://docs.google.com/spreadsheets/d/' + f._sheet
      res.headers = Location: res.body

    # a function with _index will be given child functions that call the default index child functions - if they're present, call them with the route specified
    else if f._indexed
      args = [...arguments]
      args.unshift rt.replace '_' + f._indexed, ''
      res = await @index[f._indexed] ...args
      
    # index / kv should first be checked if configured
    # for index, to create a new record with a specified ID, ONLY specify it as _id in the object as first argument and no second argument
    # updating / deleting can be done providing key in first argument and object / empty string in second argument
    # for kv, create can be done with ID string as first argument and record/value as second argument
    # _index, _kv
    else if (f._index or f._kv) and (not f._sheet or @fn isnt n or not @refresh)
      if @fn is n
        lg.key = @route.split(n.split('.').pop()).pop().replace(/\//g, '_').replace(/^_/,'').replace(/_$/,'') if @fn.replace(/\./g, '/') isnt @route # action on a specific keyed record
        # TODO who should be allowed to submit a record remotely?
        #rec = if @request.method is 'PUT' or (lg.key and @request.method is 'POST') then @body else if @request.method is 'DELETE' or @params._delete then '' else undefined
        if not lg.key and f._index #and not rec?
          qry = await @index.translate(if @request.method is 'POST' then @body else @params) # and if there is @params._delete, delete by query?
      else if arguments.length # could be a key string and record or could be a query and options (and query could look like a key)
        lg.key = arguments[0].replace(/\//g, '_') if typeof arguments[0] is 'string' and arguments[0].length and not arguments[0].includes '\n' # could be key or query string
        delete lg.key if lg.key and lg.key.length isnt lg.key.replace(/[\s\:\*~()\?=%]/g, '').length # only keep if it could be a valid key
        if f._index and arguments[0] isnt '' and arguments[1] isnt '' and qry = await @index.translate arguments[0], arguments[1] # check if it can be a query
          qry = undefined if lg.key and (arguments.length is 1 or typeof arguments[1] is 'object') and exists = await @index rt + '/' + lg.key # it was a record key, not a query
        rec = if qry? then undefined else if lg.key then arguments[1] else if f._index then arguments[0] else undefined

      if typeof rec is 'object' and not Array.isArray rec
        rec._id ?= lg.key ? rec[f._key] ? @uid()
        lg.key ?= rec._id
      #console.log(n, lg.key, JSON.stringify(rec), JSON.stringify qry) if @S.dev and @S.bg is true
      
      if qry?
        res = await @index rt, qry
        lg.qry = JSON.stringify qry
      if rec? or not @refresh or typeof f isnt 'function'
        if f._kv and lg.key and (rec? or not exists?)
          res = await @kv rt + '/' + lg.key, rec # there may or may not be a rec, as it could just be getting the keyed record
          lg.cached = @cached = 'kv' if res? and not rec? and @fn is n
        if f._index and (rec? or not res?)
          res = if exists? and not rec? then exists else await @index rt + (if lg.key and (rec? or not qry?) then '/' + lg.key else ''), (rec ? (if not lg.key then qry else undefined))
          if not res? and (not lg.key or not rec?) # this happens if the index does not exist yet, so create it (otherwise res would be a search result object)
            await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases}
            res = await @index rt + (if lg.key then '/' + lg.key else ''), (rec ? (if not lg.key then qry else undefined))
      try res = undefined if not rec? and res.hits.total is 0 and typeof f is 'function' and lg.key # allow the function to run to try to retrieve or create the record from remote
      try
        if qry.query.bool? and (qry.size is 1 or (res.hits.total is 1 and lg.key)) # return 1 record instead of a search result.
          res.hits.hits[0]._source._id = res.hits.hits[0]._id if res.hits.hits[0]._source? and not res.hits.hits[0]._source._id?
          res = res.hits.hits[0]._source ? res.hits.hits[0].fields # is fields instead of _source still possible in ES7.x?
      lg.cached = @cached = 'index' if res? and not rec? and not lg.cached and @fn is n

    # if _history is required, record more about the incoming record change, if that's what happened
    # _history
    if f._history and typeof rec is 'object' and not Array.isArray(rec) and rec._id
      lg.history = rec._id
      lg.rec = JSON.stringify rec # record the incoming rec to record a history of changes to the record

    # if nothing yet, send to bg for _bg or _sheet functions, if bg is available and not yet on bg
    # _bg, _sheet
    if not res? and (f._bg or f._sheet) and typeof @S.bg is 'string' and @S.bg.indexOf('http') is 0
      bup = headers: {}, body: rec, params: @copy @params
      bup.params.refresh = true if @refresh
      bup.headers['x-' + @S.name.toLowerCase() + '-async'] = @rid
      res = await @fetch @S.bg + '/' + rt.replace(/\_/g, '/'), bup # if this takes too long the whole route function will timeout and cascade to bg
      lg.bg = true # TODO would it be better to just throw error here and divert the entire request to backend?

    # if nothing yet, and function has _sheet, and it wasn't a specific record lookup attempt, 
    # or it was a specific API call to refresh the _sheet index, or any call where index doesn't exist yet,
    # then (create the index if not existing and) populate the index from the sheet
    # this will happen on background where possible, because above will have routed to bg if it was available
    # _sheet
    if not res? and f._sheet and ((@refresh and @fn is n) or not exists = await @index rt)
      if f._sheet.startsWith('http') and f._sheet.includes 'csv'
        sht = await @convert.csv2json f._sheet
      else if f._sheet.startsWith('http') and f._sheet.includes 'json'
        sht = await @fetch f._sheet
        sht = [sht] if sht and not Array.isArray sht
      else
        sht = await @src.google.sheets f._sheet
      if Array.isArray(sht) and sht.length
        sht = await f.apply(@, [sht]) if typeof f is 'function' # process the sheet with the function if necessary, then create or empty the index
        await @index rt, ''
        await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases}
        if arguments.length or JSON.stringify(@params) isnt '{}'
          await @index rt, sht
        else
          @waitUntil @index rt, sht
          res = sht.length # if there are args, don't set the res, so the function can run afterwards if present
      else
        res = 0
    
    # if still nothing happened, and the function defined on P really IS a function
    # (it could also be an index or kv config object with no default function)
    # call the function, either _async if the function indicates it, or directly
    # and record limit settings if present to restrict more runnings of the same function
    # _async, _limit
    if not res? and typeof f is 'function'
      _as = (rt, f, ar, notify) =>
        if f._limit
          ends = if f._limit is true then 86400 else f._limit
          await @kv 'limit/' + n, started + ends, ends # max limit for one day
        r = await f.apply @, ar
        if r? and (f._kv or f._index) and not r.took? and not r.hits?
          if f._key and Array.isArray(r) and r.length and not r[0]._id? and r[0][f._key]?
            c._id ?= c[f._key] for c in r
          id = if Array.isArray(r) then '' else '/' + (r[f._key] ? r._id ? @uid()).replace(/\//g, '_').toLowerCase()
          @kv(rt + id, res, f._kv) if f._kv and not Array.isArray r
          @waitUntil @index(rt + id, r) if f._index
        if f._limit is true
          await @kv 'limit/' + n, '' # where limit is true only delay until function completes, then delete limit record
        if f._async
          @kv 'async/' + @rid, (if id? and not Array.isArray(r) then rt + id else if Array.isArray(r) then r.length else r), 172800 # lasts 48 hours
          @mail({to: notify, text: @base + '/' + rt + '?_async=' + @rid}) if notify
        return r
      if f._async
        lg.async = true
        res = _async: @rid
        @waitUntil _as rt, f, arguments, @params.notify
      else
        res = await _as rt, f, arguments

    # if _diff checking is required, save the args and res and the "log" will alert 
    # if there is a difference in the result for the same args
    # _diff
    if f._diff and res? and not lg.cached and not lg.async
      lg.args = JSON.stringify if arguments.length then arguments else if @fn is n then @params else ''
      lg.res = JSON.stringify res # what if this is huge? just checksum it?
      try lg.checksum = @shorthash lg.res

    # _log
    if f._log isnt false
      lg.took = Date.now() - started
      @log lg

    return res
