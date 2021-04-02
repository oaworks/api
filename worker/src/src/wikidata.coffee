
# TODO copy over from old system

P.src.wikidata = (q) ->
  try q ?= @params.wikidata ? @params.q ? @params
  if typeof q is 'string'
    if q.indexOf('Q') is 0
      return @fetch 'https://dev.api.cottagelabs.com/use/wikidata/' + q
    else
      return @fetch 'https://dev.api.cottagelabs.com/use/wikidata?q=' + q
  else
    return @fetch 'https://dev.api.cottagelabs.com/use/wikidata', body: q
  
