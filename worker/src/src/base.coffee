

# BASE provide a search endpoint, but must register our IP to use it first
# limited to non-commercial and 1 query per second, contact them for more options
# register here: https://www.base-search.net/about/en/contact.php (registered)
# docs here:
# http://www.base-search.net/about/download/base_interface.pdf

P.src.base = {}

P.src.base.doi = (doi) ->
	#return @src.base.get doi
	return await @fetch 'https://dev.api.cottagelabs.com/use/base/doi/' + doi

P.src.base.title = (title) ->
  title = title.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036F]/g, '').replace(/ß/g,'ss')
  ret = await @src.base.get 'dctitle:"'+title+'"'
  if ret?.dctitle? or ret.title?
    ret.title ?= ret.dctitle
    if ret.title
      ct = ret.title.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036F]/g, '').replace(/ß/g,'ss')
      if ct and ct.length <= title.length*1.2 and ct.length >= title.length*.8 and title.replace(/ /g,'').indexOf(ct.replace(' ','').replace(' ','').replace(' ','').split(' ')[0]) isnt -1
        return ret
  return undefined

P.src.base.get = (qry) ->
	res = await @src.base.search qry
	return if res?.data?.length then res.data[0] else undefined

P.src.base.search = (qry='*', from, size) ->
  # it uses offset and hits (default 10) for from and size, and accepts solr query syntax
  # string terms, "" to be next to each other, otherwise ANDed, can accept OR, and * or ? wildcards, brackets to group, - to negate
  #proxy = @S.proxy # need to route through the proxy so requests come from registered IP
  #return undefined if not proxy
  qry = qry.replace(/ /g,'+') if qry.indexOf('"') is -1 and qry.indexOf(' ') isnt -1
  url = 'https://api.base-search.net/cgi-bin/BaseHttpSearchInterface.fcgi?func=PerformSearch&format=json&query=' + qry
  url += '&offset=' + from if from # max 1000
  url += '&hits=' + size if size # max 125
  url += '&sortBy=dcdate+desc'
  try
    # add bg true to this as well, or proxy
    res = await @fetch url #, {timeout:timeout,npmRequestOptions:{proxy:proxy}}
    res = JSON.parse(res).response
    res.data = res.docs
    delete res.docs
    res.total = res.numFound
    return res
