
# get the big deal data from a sheet and expose it in a website
# https://docs.google.com/spreadsheets/d/e/2PACX-1vQ4frfBvvPOKKFhArpV7cRUG0aAbfGRy214y-xlDG_CsW7kNbL-e8tuRvh8y37F4xc8wjO6FK8SD6UT/pubhtml
# https://docs.google.com/spreadsheets/d/1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs/edit

P.svc.oaworks.deal = _index: true, _hides: true, _prefix: false
P.svc.oaworks.deal.institution = _index: true, _prefix: false

P.svc.oaworks.deal.import = () ->
  recs = await @src.google.sheets '1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs'
  institutions = {}
  for rec in recs
    try
      rec.value = parseInt rec.packageprice.replace /[^0-9]+/g, ''
      if typeof rec.fte is 'string'
        try
          rec.fte = parseInt rec.fte
        catch
          delete rec.fte
      if rec.notes.toLowerCase().indexOf('canadian') isnt -1
        rec.gbpvalue = Math.floor rec.value * .57
        rec.usdvalue = Math.floor rec.value * .75
      else if rec.packageprice.indexOf('$') isnt -1
        rec.gbpvalue = Math.floor rec.value * .77
        rec.usdvalue = Math.floor rec.value
      else
        rec.gbpvalue = Math.floor rec.value
        rec.usdvalue = Math.floor rec.value * 1.3
    rec.usdvalue ?= ''
    try rec.years = '2013' if rec.years is '2103' # fix what is probably a typo
    try delete rec.url if rec.shareurlpublicly.toLowerCase() isnt 'yes'
    try delete rec.shareurlpublicly
    try rec.collection = 'Unclassified' if rec.collection is ''
    try
      rec.carnegiebasicclassification = rec['2015carnegiebasicclassification']
      delete rec['2015carnegiebasicclassification']
    try
      institutions[rec.institution] ?= {institution:rec.institution, deals:[], value:0, usdvalue:0, gbpvalue:0}
      rdc = JSON.parse JSON.stringify rec
      try delete rdc.institution
      try
        institutions[rec.institution].value += rec.value
        institutions[rec.institution].gbpvalue += rec.gbpvalue
        institutions[rec.institution].usdvalue += rec.usdvalue
      institutions[rec.institution].deals.push rdc

  insts = []
  for i of institutions
    insts.push institutions[i]

  await @svc.oaworks.deal ''
  await @svc.oaworks.deal.institution ''

  await @svc.oaworks.deal recs
  await @svc.oaworks.deal.institution insts

  return retrieved: recs.length, institutions: insts.length

