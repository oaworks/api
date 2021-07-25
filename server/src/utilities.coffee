
'''
# https://www.npmjs.com/package/geoip-lite
# NOTE the underlying IP data can be updated using the package, but need an API key and then configure it 
import geoip from 'geoip-lite'
# TODO had a problem with this because it could not find the data files
# NOTE it also is fairly out of date, and there are restrictions on the maxmind underlying data use, may be better to find something else

P.geoip = (ip) ->
  ip ?= @params.geoip ? @params.ip ? @headers.ip ? @headers['x-real-ip'] ? @headers['x-forwarded-for']
  if ip?
    geo = geoip.lookup ip
    geo.ip = ip
    return geo
  else
    return {}
'''
