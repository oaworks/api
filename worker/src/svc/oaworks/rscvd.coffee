
P.svc.rscvd = () ->
  return 'RSCVD API (prototype)'
P.svc.rscvd._index = true
#P.svc.rscvd._html = _qopts: {include: ['title', 'status', 'publisher', 'year', 'doi', 'issn', 'isbn']}

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
          rec = sid: sid, status: 'Awaiting verification'
          rec.type = if r._source.sid is 'AKfycbwFA_R-0gjzVS9029ByVpduCYJbHLH0ujstNng1aNnRogw1htU' then 'Paper' else if r._source.sid is 'AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6' then 'Book' else ''
          try rec.createdAt = new Date parseInt r._source.createdAt
          for kv in params.split '&'
            [key, val] = kv.split '='
            rec[key] = decodeURIComponent decodeURIComponent val
            try rec[key] = await @date(rec[key]) if key in ['date', 'needed-by']
          recs.push rec
    if recs.length
      await @svc.rscvd ''
      @waitUntil @svc.rscvd recs
    return res.hits.total + ', ' + recs.length


P.svc.rscvd.verify = (verify=true) ->
  return undefined if not @params.verify
  await @index._each 'svc_rscvd', 'email:"' + @params.verify + '"', {action: 'index'}, (rec) ->
    rec.verified = verify
    if not rec.status or rec.status is 'Awaiting verification'
      rec.status = if verify then 'Verified' else 'Denied'
    return rec
  return true
P.svc.rscvd.deny = () ->
  return @svc.rscvd.verify false

P.svc.rscvd.status = () ->
  return undefined if not @params.status
  [rid, status] = @params.status.split '/'
  rec = await @svc.rscvd rid
  rec.status = status
  @svc.rscvd rec
  return rec

P.svc.rscvd.supply = () ->
  body = '<html><head>'
  body += '<style>table.paradigm tr:nth-child(even) {background: #eee}\
table.paradigm tr:nth-child(odd) {background: #fff}</style>\n'
  body += '</head>'
  body += '\n<body><h1>RSCVD Supply prototype <small id="welcome"></small></h1>'

  opts = {sort: {createdAt: 'desc'}, terms: ['email', 'status']}
  size = 500
  opts.size = size if not @params.size
  qr = await @index.translate (if JSON.stringify(@params) isnt '{}' then @params else 'email:* AND (title:* OR atitle:*)'), opts
  res = await @svc.rscvd qr

  status_filter = '<select class="filter" id="status"><option value="">' + (if @params.q and @params.q.includes('status:') then 'clear status filter' else 'Filter by status') + '</option>'
  for st in res.aggregations.status.buckets
    if st.key
      status_filter += '<option value="' + st.key + '"' + (if @params.q and @params.q.includes(st.key) then ' selected="selected"' else '') + '>' + st.key + ' (' + st.doc_count + ')' + '</option>'
  status_filter += '</select>'

  email_filter = '<select class="filter" id="email"><option value="">' + (if @params.q and @params.q.includes('email:') then 'clear requestee filter' else 'Filter by requestee') + '</option>'
  for st in res.aggregations.email.buckets
    if st.key
      email_filter += '<option value="' + st.key + '"' + (if @params.q and @params.q.includes(st.key) then ' selected="selected"' else '') + '>' + st.key + ' (' + st.doc_count + ')' + '</option>'
  email_filter += '</select>'

  body += '<table class="paradigm" style="border-collapse: collapse;">\n'
  body += '<thead><tr>'

  headers = ['Item', 'Requestee', 'Status'] #, 'Publisher', 'Year', 'DOI', 'ISSN', 'ISBN']
  for h in headers
    body += '<th style="padding:2px; border:1px solid #ccc;">'
    if h is 'Item'
      pager = if qr.from then '<a class="pager ' + (qr.from - (qr.size ? size)) + '" href="#">&lt; back</a> items ' else 'Items '
      if res.hits.total > res.hits.hits.length
        pager += (qr.from ? 1) + ' to ' + ((qr.from ? 0) + (qr.size ? size))
        pager += '. <a class="pager ' + ((qr.from ? 0) + (qr.size ? size)) + '" href="#">next &gt;</a>'
      body += pager
    else
      body += h
      body += '<br>' + email_filter if h is 'Requestee'
      body += '<br>' + status_filter if h is 'Status'
    body += '</th>'
  body += '</tr></thead>'
  body += '<tbody>'

  columns = ['title', 'email', 'status'] #, 'publisher', 'year', 'doi', 'issn', 'isbn']
  for r in res.hits.hits
    for k of r._source
      if typeof r._source[k] is 'string' and r._source[k].includes '%'
        try r._source[k] = decodeURIComponent r._source[k]
    body += '\n<tr>'
    for c in columns
      val = r._source[c] ? ''
      if c is 'title'
        if r._source.sid in ['AKfycbwFA_R-0gjzVS9029ByVpduCYJbHLH0ujstNng1aNnRogw1htU', 'AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6']
          val = '<a class="types" href="#">'
          val += if r._source.sid is 'AKfycbwFA_R-0gjzVS9029ByVpduCYJbHLH0ujstNng1aNnRogw1htU' then 'Paper' else 'Book'
          val += '</a><br>'
        else
          val = ''
        val += (if r._source.doi and r._source.doi.startsWith('10.') then '<a target="_blank" href="https://doi.org/' + r._source.doi + '">' else '') + '<b>' + (r._source.atitle ? r._source.title) + '</b>' + (if r._source.doi and r._source.doi.startsWith('10.') then '</a>' else '')
        if r._source.year or r._source.publisher or (r._source.title and r._source.atitle)
          val += '<br>' + (if r._source.year then r._source.year + ' ' else '') + (if r._source.title and r._source.atitle then '<i><a class="title" href="#">' + r._source.title + '</a></i>' + (if r._source.publisher then ', ' else '') else '') + (r._source.publisher ? '')
        if r._source.doi or r._source.issn or r._source.isbn
          val += '<br>' + (if r._source.doi and r._source.doi.startsWith('10.') then '<a target="_blank" href="https://doi.org/' + r._source.doi + '">' + r._source.doi + '</a> ' else '') + (if r._source.issn then ' ISSN ' + r._source.issn else '') + (if r._source.isbn then ' ISBN ' + r._source.isbn else '')
      else if c is 'email'
        if r._source.verified?
          val = '<b style="color:' + (if r._source.verified then 'green' else 'red') + ';">' + r._source.email + '</b>'
          if r._source.verified
            if r._source['needed-by']
              val += '<br>Required by ' + r._source['needed-by'].split('-').reverse().join('/')
              val += '<br>Ref: ' + r._source.reference if r._source.reference
        else
          val = r._source.email
          val += '<br>' + (r._source.name ? '') + (if r._source.organization then (if r._source.name then ', ' else '') + r._source.organization else '')
      else if c is 'status'
        if r._source.verified?
          if r._source.verified
            val = '<select class="status ' + r._id + '" style="margin-top:5px; margin-bottom:0px; min-width:180px;">'
            sopts = ['Verified', 'Denied', 'Progressing', 'Overdue', 'Provided', 'Cancelled', 'Done']
            sopts.unshift('') if not r._source.status
            for st in sopts
              val += '<option' + (if r._source.status is st then ' selected="selected"' else '') + '>' + st + '</option>'
            val += '</select>'
          else
            val = 'Requestee denied'
        else
          val = '<a class="verify ' + r._source.email + '" style="color:green" href="#">Verify</a> or <a class="verify deny ' + r._source.email + '" style="color:red" href="#">Deny</a><br>the requestee'
      body += '<td style="padding:2px; border:1px solid #ccc; vertical-align:text-top;' + (if c is 'title' then ' width:60%;' else '') + '">' + val + '</td>'
    body += '</tr>'
  body += '\n</tbody></table>'
  body += '</body>'
  body += '\n<script src="/client/pradm.js"></script>'
  body += '\n<script src="/client/pradmLogin.js"></script>'
  body += '''<script>
  pradm.listen("click", ".verify", function(e) {
    e.preventDefault();
    var el = e.target;
    var cls = pradm.classes(el);
    cls.pop();
    pradm.html(el, (cls.indexOf("deny") !== -1 ? "Deny" : "Verify") + 'ing...');
    var url = "/svc/rscvd/" + (cls.indexOf("deny") !== -1 ? "deny" : "verify") + "/" + cls.pop();
    pradm.ajax(url);
    setTimeout(function() { location.reload(); }, 3000);
  });
  pradm.listen("change", ".status", function(e) {
    var el = e.target;
    var cls = pradm.classes(el);
    cls.pop();
    var url = "/svc/rscvd/status/" + cls.pop() + "/" + el.value;
    pradm.html(el, 'Updating...');
    pradm.ajax(url);
    setTimeout(function() { location.reload(); }, 3000);
  });
  pradm.listen("change", ".filter", function(e) {
    var status = pradm.get('#status');
    var email = pradm.get('#email');
    var q = '';
    if (status) q += 'status:"' + status + '"';
    if (email) {
      if (q.length) q += ' AND ';
      q += 'email:"' + email + '"';
    }
    window.history.pushState("", "", window.location.pathname + (q !== '' ? "?q=" + q : ''));
    location.reload();
  });
  pradm.listen("click", ".pager", function(e) {
    e.preventDefault();
    var el = e.target;
    var cls = pradm.classes(el);
    cls.pop();
    window.history.pushState("", "", window.location.pathname + "?from=" + cls.pop());
    location.reload();
  });
  pradm.listen("click", ".title", function(e) {
    e.preventDefault();
    var el = e.target;
    window.history.pushState("", "", window.location.pathname + '?q=title:"' + el.innerHTML + '"');
    location.reload();
  });
  pradm.listen("click", ".types", function(e) {
    e.preventDefault();
    var el = e.target;
    var type = el.innerHTML;
    window.history.pushState("", "", window.location.pathname + '?q=sid:"' + (type === 'Paper' ? 'AKfycbwFA_R-0gjzVS9029ByVpduCYJbHLH0ujstNng1aNnRogw1htU' : 'AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6') + '"');
    location.reload();
  });
  try {
    var name = pradm.account.email.split('@')[0];
    name = name.substring(0,1).toUpperCase() + name.substring(1);
    pradm.html('#welcome', ' for <a id="logout" href="#">' + name + '</a>');
    pradm.listen("click", "#logout", function(e) {
      e.preventDefault();
      pradm.next = true;
      pradm.logout();
    });
  } catch (err) {}
</script>'''
  body += '</html>'
  @format = 'html'
  
  return body #headers: {'Content-Type': 'text/html; charset=UTF-8'}, body: body

P.svc.rscvd.supply._auth = true
