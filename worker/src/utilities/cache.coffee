
# https://developers.cloudflare.com/workers/runtime-apis/cache
# https://developers.cloudflare.com/workers/examples/cache-api

# this is a cloudflare Cache implementation
# if an alternative has to be used, then write the alternative functions in a 
# different cache implementation, and add a method to swap P.cache to those functions
# yes, this could be done now, but if it never gets used then it's just premature optimisation
# if the cache isn't present this returns undefined and the main API code is written to continue 
# so it's an optional layer anyway
# top level API calls can cache, and any uses of fetch can cache directly too
# other methods can use this cache directly as well if they need to

# NOTE the cloudflare cache is only per region, not global. KV store is global (but only eventually consistent)

P.cache = (request, response, age) ->
  if typeof age isnt 'number'
    age = if typeof @S.cache is 'number' then @S.cache else if @S.dev then 120 else 43200 # how long should default cache be? here is 2 mins for dev, 12 hours for live
  # age is max age in seconds until removal from cache (note this is not strict, CF could remove for other reasons)
  # request and response needs to be an actual Request and Response objects
  # returns promise wrapping the Response object
  if @S.cache is false or @S.bg is true
    return
  else
    try
      request ?= @request
      try
        url = request.url.toString()
        for h in ['refresh']
          if url.indexOf(h + '=') isnt -1
            hp = new RegExp h + '=.*?&'
            url = url.replace hp, ''
          if url.indexOf('&' + h + '=') isnt -1
            url = url.split('&' + h + '=')[0]
        cu = new URL url
    if request?
      try
        cu ?= new URL request.url
        ck = new Request cu.toString().replace('?refresh=true','').replace('&refresh=true',''), request
        if not response? or response is ''
          rs = await caches.default.match ck
          if response is ''
            @waitUntil caches.default.delete ck
          return rs
        else
          response = response.clone()
          rp = new Response response.body, response
          rp.headers.append "Cache-Control", "max-age=" + age
          @waitUntil caches.default.put ck, rp
    return

P.cache._auth = 'system'