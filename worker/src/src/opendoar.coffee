

# docs:
# http://opendoar.org/tools/api.html
# http://opendoar.org/tools/api13manual.html
# example:
# http://opendoar.org/api13.php?fields=rname&kwd=Aberdeen%20University%20Research%20Archive

P.src.opendoar = _index: true



P.src.opendoar.parse = (rec) ->
  ret = {_id: rec.$.rID}
  ret.name = rec.rName?[0]
  ret.acronym = rec.rAcronym?[0]
  ret.url = rec.rUrl?[0]
  ret.oai = rec.rOaiBaseUrl?[0]
  ret.uname = rec.uName?[0]
  ret.uacronym = rec.uAcronym?[0]
  ret.uurl = rec.uUrl?[0]
  ret.oname = rec.oName?[0]
  ret.oacronym = rec.oAcronym?[0]
  ret.ourl = rec.oUrl?[0]
  ret.address = rec.rPostalAddress?[0]
  ret.phone = rec.paPhone?[0]
  ret.fax = rec.paFax?[0]
  ret.description = rec.rDescription?[0]
  ret.remarks = rec.rRemarks?[0]
  ret.established = rec.rYearEstablished[0] if rec.rYearEstablished?[0]?.length > 0 and parseInt(rec.rYearEstablished[0])
  ret.type = rec.repositoryType?[0]
  ret.operational = rec.operationalStatus?[0]
  ret.software = rec.rSoftWareName?[0]
  ret.version = rec.rSoftWareVersion?[0]
  ret.location = {geo:{lat:rec.paLatitude[0],lon:rec.paLongitude[0]}} if rec.paLatitude and rec.paLongitude
  if rec.country?[0]?.cCountry?
    ret.country = rec.country[0].cCountry[0]
    ret.countryIso ?= rec.country[0].cIsoCode?[0]
  if rec.classes?[0]?.class?
    ret.classes = []
    for c in rec.classes[0].class
      cl = {}
      cl.code = c.clCode?[0]
      cl.title = c.clTitle?[0]
      ret.classes.push cl
  if rec.languages?[0]?.language?
    ret.languages = []
    for l in rec.languages[0].language
      ll = {}
      ll.iso = l.lIsoCode?[0]
      ll.name = l.lName?[0]
      ret.languages.push ll
  if rec.contentTypes?[0]?.contentType?
    ret.contents = []
    for t in rec.contentTypes[0].contentType
      co = {}
      co.type = t._
      co.id = t.$?.ctID
      ret.contents.push co
  if rec.policies?[0]?.policy
    ret.policies = []
    for p in rec.policies[0].policy
      po = {}
      po.type = p.policyType?[0]?._
      po.grade = p.policyGrade?[0]?._
      if p.poStandard?[0]?.item?
        std = []
        std.push(st) if typeof st is "string" for st in p.poStandard[0].item
        po.standard = std
      ret.policies.push po
  if rec.contacts?[0]?.person?
    ret.contacts = []
    for cn in rec.contacts[0].person
      cont = {}
      cont.name = cn.pName?[0]
      cont.title = cn.pJobTitle?[0]
      cont.email = cn.pEmail?[0]
      cont.phone = cn.pPhone?[0]
      ret.contacts.push cont
  return ret

P.src.opendoar.search = (qrystr, show='basic', raw) ->
  try
    url = 'http://opendoar.org/api13.php?show=' + show + '&kwd=' + qrystr
    res = await @fetch url
    js = await @convert.xml2json res.content
    data = []
    for r in js.OpenDOAR.repositories[0].repository
      data.push await @src.opendoar.parse r
    return { total: js.OpenDOAR.repositories[0].repository.length, data: data}

P.src.opendoar.index = () ->
  try
    url = 'http://opendoar.org/api13.php?all=y&show=max'
    res = await @fetch url
    js = await @convert.xml2json res.content
    data = []
    for r in js.OpenDOAR.repositories[0].repository
      data.push await @src.opendoar.parse r
    @src.opendoar ''
    @src.opendoar data
  return true
