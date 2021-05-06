
# Docs: https://europepmc.org/GristAPI
# Fields you can search by: https://europepmc.org/GristAPI#API

# Example, get info by grant ID: http://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=gid:088130&resultType=core&format=json
# Use case: To get the name of a Principal Investigator, call @src.grist(the_grant_id).data.Person
# Will return {FamilyName: "Friston", GivenName: "Karl", Initials: "KJ", Title: "Prof"}

P.src.grist = (qrystr, from) ->
  # note in Grist API one of the params is resultType, in EPMC REST API the same param is resulttype .
  qrystr ?= @params.grist
  if qrystr.indexOf('gid:') isnt 0 and qrystr.indexOf(' ') is -1 and parseInt qrystr
    qrystr = 'gid:' + qrystr # check the qrystr to decide if this should be added or not
  url = 'https://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=' + encodeURIComponent(qrystr) + '&resultType=core&format=json'
  url += '&page=' + (Math.floor(from/25)+1) if from?
  res = await @fetch url
  return total: res.HitCount, data: (res.RecordList?.Record ? {})
