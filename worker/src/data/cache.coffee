
# https://developers.cloudflare.com/workers/runtime-apis/cache

# this is a cloudflare Cache implementation
# if an alternative has to be used, then write the alternative functions in a 
# different cache implementation, and add a method to swap P.cache to those functions
# yes, this could be done now, but if it never gets used then it's just premature optimisation
# if the cache isn't present this returns undefined and the main API code is written to continue 
# so it's an optional layer anyway
# top level API calls can cache, and any uses of fetch can cache directly too
# other methods can use this cache directly as well if they need to

# NOTE the cloudflare cache is only per region, not global. KV store is global (but only eventually consistent)

# https://community.cloudflare.com/t/how-long-does-the-basic-cloudflare-cdn-cache-things-for/85728
# https://support.cloudflare.com/hc/en-us/articles/218411427-What-does-edge-cache-expire-TTL-mean-#summary-of-page-rules-settings
# https://support.cloudflare.com/hc/en-us/articles/200168276

# https://developers.cloudflare.com/workers/examples/cache-api

P.cache = (request, response, age) ->
  if typeof age isnt 'number'
    age = if typeof @S.cache is 'number' then @S.cache else if @S.dev then 120 else 43200 # how long should default cache be? here is 2 mins for dev, 12 hours for live
  # age is max age in seconds until removal from cache (note this is not strict, CF could remove for other reasons)
  # request and response needs to be an actual Request and Response objects
  # returns promise wrapping the Response object
  if @S.cache is false or @S.bg is true # can change this if a backend cache mechanism is added later (prob not worthwhile)
    return undefined
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
            url = url.split('&' + h + '=')[0] # it's the last param, remove from end
        cu = new URL url
    if request?
      try
        cu ?= new URL request.url
        # if request method is POST try changing to GET? and should any headers be removed?
        ck = new Request cu.toString().replace('?refresh=true','').replace('&refresh=true',''), request
        if not response? or response is ''
          rs = await caches.default.match ck
          if response is ''
            @waitUntil caches.default.delete ck
          return rs
        else
          # what about things like apikey, refresh and other params, headers not wanted in cache?
          # need to build a request object here, and include a Last-Modified header? or cacheTtl would just let it time out?
          # and what about overriding the method? Always do that here or allow it to be done before here?
          # it has to be a GET for it to be accepted by the CF cache
          # could use just the URL string as key (and then, which query params to consider, if any?)
          # but if using just the URL string how would the refresh timeout be checked?
          response = response.clone() # body of response can only be read once, so clone it
          rp = new Response response.body, response
          rp.headers.append "Cache-Control", "max-age=" + age
          @waitUntil caches.default.put ck, rp
      catch
        return undefined
    else
      return undefined

P.cache._hide = true
P.cache._auth = 'system'