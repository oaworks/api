
P.pings = _index: true

P.ping = () ->
  data = @copy @params
  if JSON.stringify(data) isnt '{}'
    data.ip = @headers['x-forwarded-for'] ? @headers['cf-connecting-ip'] ? @headers['x-real-ip']
    data.forwarded = @headers['x-forwarded-for']
    await @pings data
    return true
  else
    return false
