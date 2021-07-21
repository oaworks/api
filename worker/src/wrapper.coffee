
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
    # _index, _kv
    else if f._index or f._kv and (not f._sheet or @fn isnt n or not @refresh)
      if arguments.length is 1
        rec = if f._kv or (f._index and (arguments[0] is '' or typeof arguments[0] is 'object')) then arguments[0] else undefined
      else if arguments.length is 2 and typeof arguments[0] is 'string' and arguments[0].length and (arguments[1] is '' or typeof arguments[1] is 'object' or f._kv)
        rec = arguments[1]
      else if @fn is n and ((@request.method is 'DELETE' or @params._delete) or (@request.method in ['POST', 'PUT'] and @body? and JSON.stringify(@body) isnt '{}'))
        rec = if @request.method is 'DELETE' or @params._delete then '' else @body # TODO an auth check has to occur somewhere if this is a delete from the API
      if f._index and (@fn isnt n or @request.method isnt 'PUT') and arguments[0] isnt '' and arguments[1] isnt '' # check in case rec is actually a query
        qry = if arguments.length then await @index.translate(arguments[0], arguments[1]) else if rec? or JSON.stringify(@params) isnt '{}' then await @index.translate(rec ? @params) else undefined
        if qry?
          rec = undefined if arguments.length or @fn is n
        else
          lg.key = if typeof arguments[0] is 'string' and arguments[0] isnt rec then arguments[0] else if @fn is n and @fn.replace(/\./g, '/') isnt @route then @route.split(n.split('.').pop()).pop() else undefined
      lg.key = lg.key.replace(/\//g, '_').replace(/^_/,'').replace(/_$/,'') if lg.key
      if typeof rec is 'object' and not Array.isArray(rec) and not rec._id
        rec._id = lg.key ? rec[f._key] ? @uid()
      if f._kv and not qry? and lg.key
        res = await @kv rt + (if lg.key then '/' + lg.key else ''), rec
        lg.cached = @cached = 'kv' if res? and not rec?
      console.log(lg.key, rec, JSON.stringify qry) if @S.dev and @S.bg is true
      if f._index and (rec? or not res?) and (rec? or not @refresh or typeof f isnt 'function')
        res = await @index rt + (if lg.key and (rec? or not qry?) then '/' + lg.key else ''), (rec ? (if not lg.key then qry else undefined))
        if not res? and (not lg.key or not rec?) # this happens if the index does not exist yet, so create it (otherwise res would be a search result object)
          await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases}
          res = await @index rt + (if lg.key then '/' + lg.key else ''), (rec ? (if not lg.key then qry else undefined))
        res = undefined if not rec? and typeof res is 'object' and not Array.isArray(res) and res.hits?.total is 0 and typeof f is 'function' and lg.key # allow the function to run to try to retrieve or create the record from remote
        if res?.hits?.total isnt 1 and qry? and lg.key and ((@fn is n and @fn.replace(/\./g, '/') is @route) or arguments.length is 1) and not lg.key.includes(' ') and not lg.key.includes ':'
          res = await @index rt, qry # if direct lookup didn't work try a search
        if res? and qry? and qry.query?.bool?.must and qry.query.bool.must.length is 1 and (qry.size is 1 or (res.hits.total is 1 and ((@fn isnt n and typeof arguments[0] is 'string' and not arguments[0].includes(' ') and not arguments[0].includes(':') and not arguments[0].includes('*')) or not @params.q?)))
          res.hits.hits[0]._source._id = res.hits.hits[0]._id if res.hits.hits[0]._source? and not res.hits.hits[0]._source._id?
          res = res.hits.hits[0]._source ? res.hits.hits[0].fields # return 1 record instead of a search result. is fields instead of _source still possible in ES7.x?
        lg.cached = @cached = 'index' if res? and not rec?

      '''lg.key = @route.split(n.split('.').pop()).pop() if @fn is n
      if not lg.key and f._index and (@fn isnt n or @request.method in ['GET', 'POST']) and ((arguments.length in [1,2] and arguments[1] isnt '' and qr = await @index.translate arguments[0], arguments[1]) or (not arguments.length and qr = await @index.translate @params))
        lg.qry = qr
      else
        if (arguments.length is 1 and arguments[0] is '') or (@fn is n and @request.method is 'DELETE')
          rec = ''
        else if (typeof arguments[0] is 'string' and arguments[0].length) or typeof arguments[0] is 'object'
          rec = arguments[1] ? arguments[0]
          lg.key = arguments[0] if typeof arguments[0] is 'string'
          rec = undefined if rec is lg.key and arguments.length < 2
        else if @fn is n
          rec = if @request.method in ['POST', 'PUT'] then @body else @copy @params
          delete rec[c] for c in @parts
          rec = undefined if JSON.stringify(rec) is '{}'
        if typeof rec is 'object' and not Array.isArray rec
          rec._id ?= rec[f._key] ? @uid()
          lg.key ?= rec._id
        if f._kv and lg.key
          lg.key = lg.key.replace(/\//g, '_').replace(/^_/,'').replace(/_$/,'')
          res = await @kv rt + '/' + lg.key, rec
          lg.cached = 'kv' if res? and not rec?
      if f._index and (not res? or rec? or lg.key)
        lg.key = lg.key.replace(/\//g, '_').replace(/^_/,'').replace(/_$/,'') if lg.key
        if not f._sheet or @fn isnt n or not @refresh # try either putting the record, or getting a key, or searching
          res = await @index rt + (if lg.key then '/' + lg.key else ''), (if rec? then rec else if lg.key then undefined else lg.qry)
        if not res? and not lg.key # anything apart from a direct record lookup for a record that doesn't exist should at least return an empty search result or an ES response, so if nothing back, create the index and try again
          await @index rt, if typeof f._index isnt 'object' then {} else {settings: f._index.settings, mappings: f._index.mappings, aliases: f._index.aliases}
          if not f._sheet or @fn isnt n or not @refresh # try again now that the index has been created
            res = await @index rt + (if lg.key then '/' + lg.key else ''), (if rec? then rec else if lg.key then undefined else lg.qry)
        if res? and typeof res is 'object' and res.hits? and not rec? and lg.qry?
          if res.hits.total isnt 1 and lg.qry? and typeof arguments[0] is 'string' and arguments[0].length and not arguments[0].includes ' '
            try res = await @index rt, lg.qry # if direct lookup didn't work try a search
          if res.hits?.total is 0 and typeof f is 'function' and (lg.key or arguments[0])
            res = undefined # allow the function to run to try to retrieve or create the record from remote
          else if res.hits?.total? and res.hits.hits?
            lg.cached = 'index'
            if ((lg.key or (typeof lg.qry is 'object' and lg.qry.query?.bool?.must and lg.qry.query.bool.must.length is 1 and lg.qry.query.bool.must[0].query_string?.query)) and res.hits.total is 1) or (res.hits.hits and lg.qry?.size is 1)
              rd = res.hits.hits[0]._id
              res = res.hits.hits[0]._source ? res.hits.hits[0].fields
              res._id ?= rd
      @cached = lg.cached'''

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

    # if _history is required, record more about the incoming record change, if that's what happened
    # _history
    if f._history and typeof rec is 'object' and not Array.isArray(rec) and rec._id
      lg.history = rec._id
      lg.rec = JSON.stringify rec # record the incoming rec to record a history of changes to the record

    # _log
    if f._log isnt false
      lg.qry = JSON.stringify(qry) if qry
      lg.took = Date.now() - started
      @log lg

    return res
