
P.svc.rscvd = () ->
  return 'RSCVD API (prototype)'
P.svc.rscvd._index = true

P.svc.rscvd.retrieve = () ->
  ak = @apikey #? ''
  size = @params.size ? '20000'
  if ak
    res = await @fetch 'https://api.cottagelabs.com/log?apikey=' + ak + '&sort=createdAt:asc&q=endpoint:collect&size=' + size
    recs = []
    for r in res.hits.hits
      # /api/service/oab/ill/collect/AKfycbwFA_R-0gjzVS9029ByVpduCYJbHLH0ujstNng1aNnRogw1htU?where=InstantILL&doi=10.3109%252F0167482X.2010.503330&atitle=Management%2520of%2520post%2520traumatic%2520stress%2520disorder%2520after%2520childbirth%253A%2520a%2520review&crossref_type=journal-article&aulast=Lapp%252C%2520Leann%2520K.%252C%2520Agbokou%252C%2520Catherine%252C%2520Peretti%252C%2520Charles-Siegfried%252C%2520Ferreri%252C%2520Florian&title=Journal%2520of%2520Psychosomatic%2520Obstetrics%2520%2526%2520Gynecology&issue=3&volume=31&pages=113-122&issn=0167-482X&publisher=Informa%2520UK%2520Limited&year=2010&date=2010-07-01&url=https%253A%252F%252Fdoi.org%252F10.3109%252F0167482X.2010.503330&notes=Subscription%2520check%2520done%2C%2520found%2520nothing.%2520OA%2520availability%2520check%2520done%2C%2520found%2520nothing.&email=mcclay.ill%2540qub.ac.uk&name=Ivona%2520Coghlan&organization=McClay%2520Library%252C%2520Queen%27s%2520University%2520Belfast&reference=IC00226&other=
      u = r._source.url
      if typeof u is 'string' and u.startsWith '/api/service/oab/ill/collect/'
        [sid, params] = u.replace('/api/service/oab/ill/collect/', '').split '?'
        if typeof sid is 'string' and typeof params is 'string'
          rec = sid: sid
          for kv in params.split '&'
            [key, val] = kv.split '='
            rec[key] = decodeURIComponent decodeURIComponent val
            try rec[key] = await @date(rec[key]) if key in ['date', 'needed-by']
          recs.push rec
    await @svc.rscvd ''
    @waitUntil @svc.rscvd recs
    return res.hits.total + ', ' + recs.length
