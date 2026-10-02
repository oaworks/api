
P.licence = (url, content, start, end) ->
  url ?= @params.url
  content ?= @params.content ? @body
  if not url and not content and (@params.licence or @params.doi)
    url = 'https://doi.org/' + (@params.licence ? @params.doi)
  if url
    url = url.replace /(^\s*)|(\s*$)/g,''
    if not content
      console.log url
      #try content = await @puppet url
      try content = await @fetch url
  content = undefined if typeof content is 'number'
  start ?= @params.start
  end ?= @params.end

  lic = {}
  lic.url = url if url
  if typeof content is 'string'
    content = content.split(start)[1] if start? and content.includes start
    content = content.split(end)[0] if end
    if content.length > 100000 # reduced this by and the substrings below by an order of magnitude
      lic.large = true
      content = content.substring(0,50000) + content.substring(content.length-50000, content.length)

    lics = await @licences '*', 10000
    for lh in lics?.hits?.hits ? []
      l = lh._source
      if  not l.matchesondomains or l.matchesondomains is '*' or not url? or l.matchesondomains.toLowerCase().includes url.toLowerCase().replace('http://','').replace('https://','').replace('www.','').split('/')[0]
        match = l.matchtext.toLowerCase().replace(/[^a-z0-9]/g, '')
        urlmatcher = if l.matchtext.includes('://') then l.matchtext.toLowerCase().split('://')[1].split('"')[0].split(' ')[0] else false
        urlmatch = if urlmatcher then content.toLowerCase().includes(urlmatcher) else false
        if urlmatch or content.toLowerCase().replace(/[^a-z0-9]/g,'').includes match
          lic.licence = l.licencetype
          lic.match = l.matchtext
          lic.matched = if urlmatch then urlmatcher else match
          break
  return lic

P.licences = _sheet: '1yJOpE_YMdDxCKaK0DqWoCJDdq8Ep1b-_J1xYVKGsiYI', _prefix: false
