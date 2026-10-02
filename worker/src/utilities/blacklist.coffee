P.blacklist = (url) ->
  url ?= @params.url
  url = url.toString() if typeof url is 'number'
  return false if url? and (url.length < 4 or url.indexOf('.') is -1)
  blacklist = []
  blacklist.push(i.url.toLowerCase()) for i in await @src.google.sheets "1j1eAnBN-5UoAPLFIFlQCXEnOmXG85RhwT1rKUkrPleI"
  if url
    if not url.startsWith('http') and url.includes ' '
      return false # sometimes things like article titles get sent here, no point checking them on the blacklist
    else
      for b in blacklist
        return true if url.includes b.toLowerCase()
      return false
  else
    return blacklist
