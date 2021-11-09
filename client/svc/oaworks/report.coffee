
P.append 'body', '
<div id="welcome">
  <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
    <h1 id="title" class="centre statement" style="font-size:40px;">Welcome to OA.Report</h1>
  </div></div>
  <div class="flex" style="margin-top: 5%;">
    <div class="c6 off3">
      <div id="funders">
        <p>Great tool does great things.</p>
        <p>RIGHT NOW DOES NOTHING! UNDERGOING CHANGES...</p>
        <p>Funders! (or organisations) Find out if your recipients are meeting your policy expectations, take action if not:</p>
        <p><input type="text" class="PSuggest PForOrganisation" placeholder="Find an organisation" url="/src/ror/suggest/name/"></p>
        <div class="PSuggestions PForOrganisation"></div>
      </div>
    </div>
  </div>
</div>
<div id="report" style="display:none;"></div>'

P.suggest {include: ["_id"], suggestion: (e, val, rec) ->
  window.location = window.location.href + "/" + rec._id
}, "#funders"


report = '
<div class="flex" style="margin-top: 5%;">
  <div class="c1 off1 green"><h1 class="centre" id="rating"></h1></div><div class="c8">
    <h1 id="title" class="centre statement" style="font-size:40px;">
  </div>
</div>
<div class="flex" style="margin-top: 5%;">
  <div class="c5 off1">
    <p id="papercount"></p>
    <p id="citationcount"></p>
    <p><a href="//static.oa.works/report">Export</a> or <a id="refresh" href="#">refresh</a></p>
    <p><br></p>
    
    <div id="records"></div>
  </div>

  <div id="publishers" class="c5 off1">Publishers<br><br></div>
</div>'
P.html '#report', report

# await @svc.oaworks.report.rating ror) + %

# (if ror._id is '0456r8d26' then '<div class="centre"><img src="https://www.gatesfoundation.org/-/media/logos/logolg.svg"></div>' else '') + '
# (if ror._id is '0456r8d26' then '<a target="_blank" href="https://www.gatesfoundation.org/about/policies-and-resources/open-access-policy">' else '') + ror.name + (if ror._id is '0456r8d26' then '</a>' else '') + '</h1>
# papers = if ror._id is '0456r8d26' then await @svc.oaworks.report.supplements.count() else await @src.crossref.works.count filter
#  citations = await @svc.oaworks.report.citations ror
#  if citations.oa_extra_percent
#    ret += '<br>Get ' + citations.oa_extra_percent + '% more citations by publishing OA!'

#  for await rec from @index._for (if ror._id is '0456r8d26' then 'svc_oaworks_report_supplements' else 'src_crossref_works'), filter, {sort: {published: 'desc'}, until: 100}
#    rec = rec.crossref
#    ret += '<div class="bordered-warning">' if not rec.is_oa
#    ret += '<a target="_blank" href="https://doi.org/' + rec.DOI + '">' + rec.title?[0] + '</a><br>'
#    ret += rec['container-title']?[0] + ', ' + rec.published.split('-').reverse().join('/') + '. ' + rec.publisher + '<br>'
#    for a in rec.author ? []
#      for aff in a.affiliation ? []
#        if aff.name and aff.name.toLowerCase().includes 'gates'
#          ret += 'Author ' + a.given + ' ' + a.family + ' affiliated with ' + aff.name + '. '
#    ret += '</div>' if not rec.is_oa
#    ret += '<br><br>'
#  ret += '<p>TODO add autoscroll to load more</p>'

#for pu in await @svc.oaworks.report.publishers filter
#  ret += '<p>' + pu.name + '<br>' + pu.percent + '% of ' + pu.papers + ' papers open' + (if pu.percent >= 50 then '!' else '') + '</p>'
