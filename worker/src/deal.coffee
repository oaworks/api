
# get the big deal data from a sheet and expose it in a website
# https://docs.google.com/spreadsheets/d/e/2PACX-1vQ4frfBvvPOKKFhArpV7cRUG0aAbfGRy214y-xlDG_CsW7kNbL-e8tuRvh8y37F4xc8wjO6FK8SD6UT/pubhtml
# https://docs.google.com/spreadsheets/d/1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs/edit

P.deal = _index: true, _prefix: false
P.deal.institution = _index: true, _prefix: false

P.deal.load = () ->
  recs = await @src.google.sheets '1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs'
  institutions = {}
  for rec in recs
    for tk in ['Institution', 'Publisher', 'Collection', 'Year(s)', 'Length of Agreement', 'Package Price', '2015 Carnegie Basic Classification', 'FTE', 'Source', 'URL', 'Share URL Publicly?', 'Notes']
      tl = tk.toLowerCase().replace(/ /g, '').replace('?', '').replace('(','').replace(')','')
      rec[tl] = rec[tk]
      delete rec[tk]
    try
      rec.value = parseInt rec.packageprice.replace /[^0-9]/g, ''
      if typeof rec.fte is 'string'
        try
          rec.fte = parseInt rec.fte
        catch
          delete rec.fte
      if typeof rec.notes is 'string' and rec.notes.toLowerCase().includes 'canadian'
        rec.gbpvalue = Math.floor rec.value * .57
        rec.usdvalue = Math.floor rec.value * .75
      else if rec.packageprice.includes '$'
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

  await @deal ''
  await @deal.institution ''

  await @deal recs
  await @deal.institution insts

  return retrieved: recs.length, institutions: insts.length

