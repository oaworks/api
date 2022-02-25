
P.svc ?= {}

P.svc.rscvd = _index: true

P.svc.rscvd.form = () ->
  if @keys(@params).length > 1
    rec = @copy @params
    delete rec.form
    rec.status = 'Awaiting verification'
    try
      if rq = await @svc.rscvd.requestees 'email:"' + rec.email + '"'
        if rq?.verified or rq?.verification is 'Approved'
          rec.status = 'Verified'
          rec.verified = true
        else if rq?.denied or rq?.verification is 'Denied'
          rec.status = 'Denied'
          rec.verified = false
    if rec.status is 'Awaiting verification' # not yet found in pre-verified list
      try
        av = await @svc.rscvd 'email:"' + rec.email + '" AND verified:*'
        if av?.hits?.hits and av.hits.hits[0]._source.verified is true
          rec.status = 'Verified'
          rec.verified = true
        else if av.hits.hits[0]._source.verified is false
          rec.status = 'Denied'
          rec.verified = false
    rec.type ?= 'paper'
    try rec.createdAt = new Date()
    try rec.neededAt = await @epoch rec['needed-by']
    rec._id = await @svc.rscvd rec
    try
      txt = 'Hi ' + rec.name + ',<br><br>We got your request:<br><br>Title: ' + (rec.atitle ? rec.title ? 'Unknown') + '\nReference (if provided): ' + (rec.reference ? '') + '<br><br>'
      txt += 'If at any point you no longer need this item, please <a href="https://' + (if @S.dev then 'dev.' else '') + 'rscvd.org/cancel?id=' + rec._id + '">cancel your request</a>, it only takes a second.<br><br>'
      txt += 'Our team of volunteers will try and fill your request as soon as possible. If you would like to thank us, please consider <a href="https://rscvd.org/volunteer">joining us in helping supply requests</a>.<br><br>'
      txt += 'Yours,<br><br>RSCVD team'
      @mail
        from: 'rscvd@oa.works'
        to: rec.email
        subject: 'RSCVD Request Receipt'
        text: txt
    return rec
  else
    return

P.svc.rscvd.requestees = 
  _index: true
  _auth: true
  _prefix: false
  _sheet: '1GuIH-Onf0A0dXFokH6Ma0cS0TRbbpAeOyhDVpmDNDNw'

P.svc.rscvd.resolves = (rid, resolver) ->
  rid ?= @params.resolves
  resolver ?= @params.resolver
  if rid
    rec = if typeof rid is 'object' then rid else await @svc.rscvd rid # can pass the ID of a specific record to resolve
  else
    recs = await @svc.rscvd '(status:"Awaiting verification" OR status:"Verified" OR status:"In progress" OR status:"Awaiting Peter") AND NOT resolved:"' + resolver + '" AND NOT unresolved:"' + resolver + '"'
  res = {}
  for r in (if rec? then [rec] else (recs?.hits?.hits ? []))
    if r._source?
      rec = r._source
      rec._id ?= r._id
    meta = @copy rec
    meta.journal = meta.title if meta.title
    meta.title = meta.atitle if meta.atitle
    resolves = await @ill.subscription {subscription: resolver}, meta # should send the metadata in the record
    if resolves?.url # if resolves
      rec.resolved ?= []
      rec.resolved.push resolver
      rec.resolves ?= []
      rec.resolves.push {resolver: resolver, url: resolves.url, user: @user?._id}
      res[r._id] = true
    else # does not resolve
      rec.unresolved ?= []
      rec.unresolved.push resolver
      res[r._id] = false
    @svc.rscvd rec
  return if rid and res[rid] then res[rid] else res

P.svc.rscvd.cancel = () ->
  return undefined if not @params.cancel
  rec = await @svc.rscvd @params.cancel
  rec.status = 'Cancelled'
  @svc.rscvd rec
  return rec

P.svc.rscvd.verify = (email, verify=true) ->
  email ?= @params.verify
  return undefined if not email
  re = await @svc.rscvd.requestees 'email:"' + email + '"'
  re = re.hits.hits[0]._source if re?.hits?.total is 1
  re = undefined if re?.hits?
  re ?= email: email, createdAt: Date.now()
  if verify
    re.verified = true
    re.verified_by = @user.email
  else
    re.denied = true
    re.denied_by = @user.email
  @waitUntil @svc.rscvd.requestees re
  await @svc.rscvd._each 'email:"' + email + '"', {action: 'index'}, (rec) ->
    if not rec.status or rec.status is 'Awaiting verification'
      rec.verified = verify
      if verify
        rec.status = 'Verified'
        rec.verified_by = @user.email
      else
        rec.status = 'Denied'
        rec.denied_by = @user.email
    return rec
  return true
P.svc.rscvd.verify._auth = true
P.svc.rscvd.deny = () ->
  return @svc.rscvd.verify @params.deny, false
P.svc.rscvd.deny._auth = true

P.svc.rscvd.status = () ->
  return undefined if not @params.status
  [rid, status] = @params.status.split '/'
  rec = await @svc.rscvd rid
  rec.status = status
  try
    if rec.status is 'Done'
      rec.done_by = @user.email
    else if rec.status is 'In Progress'
      rec.progressed_by = @user.email
  @svc.rscvd rec
  return rec
P.svc.rscvd.status._auth = true

P.svc.rscvd.poll = (poll, which) ->
  @nolog = true
  poll ?= @params.poll ? (Date.now() - 180000) # default to changes in last 3 mins
  which = @params.which ? ['new', 'verify', 'deny', 'cancel', 'status', 'overdue']
  which = which.split(',') if typeof which is 'string'
  @svc.rscvd.overdue() if 'overdue' in which
  res = new: [], verify: [], deny: [], cancel: [], status: {}
  if 'new' in which
    nn = await @svc.rscvd '(status:"Awaiting verification" OR status:"Verified") AND createdAt:>' + poll, 500
    for n in nn?.hits?.hits ? []
      n._source._id ?= n._id
      res.new.push n._source
  if 'verify' in which
    vs = await @index 'logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.verify"', {sort: {createdAt: 'desc'}, size: 500}
    for v in vs.hits.hits
      vn = v._source.parts.pop()
      res.verify.push(vn) if vn not in res.verify
  if 'deny' in which
    ds = await @index 'logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.deny"', {sort: {createdAt: 'desc'}, size: 500}
    for d in ds.hits.hits
      dn = d._source.parts.pop()
      res.deny.push(dn) if dn not in res.deny
  if 'cancel' in which
    cc = await @index 'logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.cancel"', {sort: {createdAt: 'desc'}, size: 500}
    for c in cc.hits.hits
      cn = c._source.parts.pop()
      res.cancel.push(cn) if cn not in res.cancel
  # TODO need to track changes to Overdue status as well
  if 'status' in which
    ss = await @index 'logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.status"', {sort: {createdAt: 'desc'}, size: 500}
    for s in ss.hits.hits
      st = s._source.parts.pop()
      res.status[s._source.parts.pop()] ?= st # only return the most recent status change for a given record ID
  return res

P.svc.rscvd.overdue = () ->
  counter = 0
  dn = Date.now()
  recs = []
  if @params.overdue
    recs.push await @svc.rscvd @params.overdue
  else
    res = await @svc.rscvd '(status:"Awaiting verification" OR status:"Verified") AND (neededAt:<' + dn + ' OR createdAt:<' + (dn - 1209600000) + ')', 10000
    for r in res.hits.hits
      r._source._id ?= r._id
      recs.push r._source
  for rec in recs
    rec.status = 'Overdue'
    @waitUntil @svc.rscvd rec
    counter += 1
  return counter

