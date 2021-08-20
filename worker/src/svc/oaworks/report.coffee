
P.svc.oaworks.report = (ror) ->
  ror ?= @params.report ? @params.ror
  ror = await @src.ror(ror) if typeof ror is 'string'
  
  if ror
    filter = await @svc.oaworks.report.filter ror
    filteroa = filter + (if filter then ' AND ' else '') + 'is_oa:true'

    ret = '<body>
    <div class="flex" style="margin-top: 5%;"><div class="c1 off1 green"><h1 class="centre">' + (await @svc.oaworks.report.rating ror) + '%</h1></div><div class="c8">
      ' + (if ror._id is '0456r8d26' then '<div class="centre"><img src="https://www.gatesfoundation.org/-/media/logos/logolg.svg"></div>' else '') + '
      <h1 id="title" class="centre statement" style="font-size:40px;">
      ' + (if ror._id is '0456r8d26' then '<a target="_blank" href="https://www.gatesfoundation.org/about/policies-and-resources/open-access-policy">' else '') + ror.name + (if ror._id is '0456r8d26' then '</a>' else '') + '</h1>
    </div></div>
    <div class="flex" style="margin-top: 5%;"><div class="c5 off1">'
    
    # could limit to author.affiliation.name or funder.name
    papers = await @src.crossref.works.count undefined, filter
    if not papers #papers?.hits?.total
      ret += 'No papers yet'
    else
      ret += papers + ' papers'
      #try
      #  if ror._id is '0456r8d26'
      #    wgids = await @src.crossref.works 'type:"journal-article" AND (funder.award:*OPP* OR funder.award:*INV*)', 0
      #    ret += ' (' + wgids.hits.total + ' with grant IDs)'
      ret += '<br><br>'

      for await rec from @index._for 'src_crossref_works', filter, {sort: {published: 'desc'}, until: 100}
        ret += '<div class="bordered-warning">' if not rec.is_oa
        ret += '<a target="_blank" href="https://doi.org/' + rec.DOI + '">' + rec.title[0] + '</a><br>'
        ret += rec['container-title'][0] + ', ' + rec.published.split('-').reverse().join('/') + '. ' + rec.publisher + '<br>'
        hadawardid = false
        for f in rec.funder ? []
          #if f.name and ((ror._id is '0456r8d26' and f.name.toLowerCase().includes 'gates') or f.name.toLowerCase().includes ror.name.toLowerCase())
          #  ret += 'Funded by ' + f.name + '. '
          if f.award and ror._id is '0456r8d26'
            for fw in (if typeof f.award is 'string' then [f.award] else f.award)
              if fw.includes('OPP') or fw.includes 'INV'
                #/OPPG[HD]\s?\d{4}/g, /OPP\s?1\s?\d{6}/g, /OPP\s?[45]\s?\d{4}/g, /INV\‐\d{6}/g
                hadawardid = true
                ret += 'Grant ID ' + fw + '. '
        if not hadawardid and ror._id is '0456r8d26'
          rs = JSON.stringify rec
          ret += 'Grant ID OPP' + rs.replace('OPP ', 'OPP').split('OPP')[1].split(' ')[0] + '. ' if rs.includes 'OPP'
          ret += 'Grant ID INV' + rs.replace('INV ', 'INV').split('INV')[1].split(' ')[0] + '. ' if rs.includes 'INV'
          # could update the grant IDs number too if more were found this way
        for a in rec.author ? []
          for aff in a.affiliation ? []
            if aff.name.toLowerCase().includes 'gates'
              ret += 'Author ' + a.given + ' ' + a.family + ' affiliated with ' + aff.name + '. '
        ret += '</div>' if not rec.is_oa
        ret += '<br><br>'
      ret += '<p>TODO add autoscroll to load more</p>'

    ret += '</div><div class="c5 off1">Publishers<br><br>'
    for pu in await @svc.oaworks.report.publishers filter
      ret += '<p>' + pu.name + '<br>' + pu.percent + '% of ' + pu.papers + ' papers open' + (if pu.percent >= 50 then '!' else '') + '</p>'
    ret += '</div>'

    #if papers.aggregations
    #  ret += '</div><div class="c4 off1">Publishers<br><br>'
    #  for ag in papers.aggregations.publisher?.buckets ? []
    #    ret += ag.key + ' (' + ag.doc_count + ')<br>'

    ret += '
    </div></div>
    <script>
    </script>
    </body>
    '

  else
    ret = '<script type="text/javascript" src="/client/pradmSuggest.min.js?v=' + @S.version + '"></script>
    <body>
    <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
      <h1 id="title" class="centre statement" style="font-size:40px;">Welcome to OA.Report</h1>
    </div></div>
    <div class="flex" style="margin-top: 5%;">
      <div class="c6 off3">
        <div id="funders">
          <p>Great tool does great things.</p>
          <p>Funders! (or organisations) Find out if your recipients are meeting your policy expectations, take action if not:</p>
          <p><input type="text" class="PSuggest PForOrganisation" placeholder="Find an organisation" url="/src/ror/suggest/name/"></p>
          <div class="PSuggestions PForOrganisation"></div>
        </div>

        <div id="publishers">
          <p>
            Publishers! How accessible are they?<br>
            <a href="/report/publishers.html">View the rankings</a> or pick one:
          </p>
          <p><input type="text" class="PSuggest PForPublisher" placeholder="Find a publisher" url="/src/crossref/works/suggest/publisher/"></p>
          <div class="PSuggestions PForPublisher"></div>
        </div>

        <div id="journals">
          <p>
            Journals! How open are they? Do they meet your funder policy expectations? 
            <a href="/report/journals.html">View the rankings</a> or pick one:
          </p>
          <p><input type="text" class="PSuggest PForJournal" placeholder="Find a journal" url="/src/crossref/works/suggest/container-title/"></p>
          <div class="PSuggestions PForJournal"></div>
        </div>

        <p>Authors! We will help you meet funder policy expectations (which improves future funding applications...):</p>
        <p><input id="author" type="text" placeholder="Tell us your name"></p>
        <div class="PSuggestions PForAuthor"></div>
      </div>
    </div>
    
    <script>
      P.suggest({include: ["_id"], suggestion: function(e, val, rec) {
        window.location = window.location.href + "/" + rec._id;
      }}, "#funders");

      P.suggest({suggestion: function(e, val) {
        window.location = window.location.href + "/publishers/" + val;
      }}, "#publishers");

      P.suggest({suggestion: function(e, val) {
        window.location = window.location.href + "/journals/" + val;
      }}, "#journals");

      P.on("enter", "#author", function(e) {
        window.location = window.location.href + "/author/" + P.val(e.target);
      });
    </script>
    </body>
    '

  @format = 'html'
  return ret

P.svc.oaworks.report._hides = true

P.svc.oaworks.report.filter = (ror) ->
  ror ?= @params.report ? @params.filter ? @params.ror
  ror = await @src.ror(ror) if typeof ror is 'string'
  if ror?._id is '0456r8d26'
    filter = 'type:"journal-article" AND (funder.award:*OPP* OR funder.award:*INV* OR "melinda gates foundation" OR "gates cambridge trust" OR "' + ror._id + '")'
  else
    filter = 'type:"journal-article"' + if ror then ' AND ("' + ror.name + '" OR "' + ror._id + '")' else ''
  return filter

P.svc.oaworks.report.rating = (ror) ->
  ror ?= @params.report ? @params.rating ? @params.ror
  if ror
    try
      filter = await @svc.oaworks.report.filter ror
      filteroa = filter + (if filter then ' AND ' else '') + 'is_oa:true'
      console.log filteroa
      papers = await @src.crossref.works.count undefined, filter
      opens = await @src.crossref.works.count undefined, filteroa
      console.log papers, opens
      pc = Math.ceil((opens/papers) * 1000)/10
      return if pc > 100 then 100 else pc
    catch
      return 0
  else
    return


P.svc.oaworks.report.publishers = (filter) ->
  if filter or not publist = P.svc.oaworks.report._publishers # allow to cache the result for a while...
    pubs = {}
    for pub in await @src.crossref.works.terms 'publisher', filter, 200
      pubs[pub.term] = {papers: pub.count}
    
    filter ?= ''
    filter = '(' + filter + ')' if filter.includes(' OR ') and not filter.includes ')'
    filteroa = (if filter then filter + ' AND ' else '') + 'is_oa:true'
  
    for opub in await @src.crossref.works.terms 'publisher', filteroa, 200
      pubs[opub.term] ?= {}
      pubs[opub.term].open = opub.count
    
    publist = []
    for p of pubs
      pubs[p].name = p
      if pubs[p].open? and not pubs[p].papers?
        pubs[p].papers = await @src.crossref.works.count undefined, filter + (if filter then ' AND ' else '') + ' publisher.keyword:"' + p + '"'
      if pubs[p].papers and not pubs[p].open?
        pubs[p].open = await @src.crossref.works.count undefined, filteroa + ' AND publisher.keyword:"' + p + '"'
      pubs[p].rating = if pubs[p].open and pubs[p].papers then pubs[p].open / pubs[p].papers else 0
      pubs[p].percent = Math.ceil(pubs[p].rating * 1000)/10
      pubs[p].percent = 100 if pubs[p].percent > 100
      if pubs[p].papers and pubs[p].rating
        publist.push pubs[p]
    
    #publist.sort (a, b) => return b.rating - a.rating
    publist.sort (a, b) => return b.rating - a.rating or b.open - a.open
    
    P.svc.oaworks.report._publishers = publist

  if @fn isnt 'svc.oaworks.report.publishers'
    return publist
  else
    @format = 'html'
    ret = '<body>
      <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
        <h1 id="title" class="centre statement" style="font-size:40px;">Publisher ranking :)</h1>
      </div></div>
      <div class="flex" style="margin-top: 5%;">
        <div class="c6 off3">'
  
    for pu in publist
      ret += '<p>' + pu.name + ' ' + pu.percent + '% of ' + pu.papers + ' papers open' + (if pu.percent >= 50 then '!' else '') + '</p>'
        
    ret += '</div>
      </div>
      </body>'

    return ret




P.svc.oaworks.report.journals = () ->
  if @params.journals
    ret = '<body>
      <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
        <h1 id="title" class="centre statement" style="font-size:40px;">' + @params.journals + '</h1>
      </div></div>
      <div class="flex" style="margin-top: 5%;">
        <div class="c6 off3">
          <br><br>Info like journal is in or not in DOAJ, journal has XX % OA articles
          <br><br>Allow to filter a particular funder, see how many of their articles are OA
          <br><br>And/or user provides their institutional affiliation to see if this journal is in an agreement with them / their country...
        </div>
      </div>
      </body>'
    
    @format = 'html'
    return ret
  else
    if not jrnlist = P.svc.oaworks.report._journals
      jrnls = {}
      for jrnl in await @src.crossref.works.terms 'container-title', undefined, 200
        jrnls[jrnl.term] = {papers: jrnl.count}
      
      for oj in await @src.crossref.works.terms 'container-title', 'is_oa:true', 200
        jrnls[oj.term] ?= {}
        jrnls[oj.term].open = oj.count
      
      jrnlist = []
      for j of jrnls
        jrnls[j].name = j
        if jrnls[j].open? and not jrnls[j].papers?
          jrnls[j].papers = await @src.crossref.works.count undefined, 'container-title.keyword:"' + j + '"'
        if jrnls[j].papers and not jrnls[j].open?
          jrnls[j].open = await @src.crossref.works.count undefined, 'is_oa:true AND container-title.keyword:"' + j + '"'
        jrnls[j].rating = if jrnls[j].open and jrnls[j].papers then jrnls[j].open / jrnls[j].papers else 0
        jrnls[j].percent = Math.ceil(jrnls[j].rating * 1000)/10
        jrnls[j].percent = 100 if jrnls[j].percent > 100
        if jrnls[j].papers and jrnls[j].rating
          jrnlist.push jrnls[j]
      
      #jrnlist.sort (a, b) => return b.rating - a.rating
      jrnlist.sort (a, b) => return b.rating - a.rating or b.open - a.open
    
      P.svc.oaworks.report._journals = jrnlist
  
    if @fn isnt 'svc.oaworks.report.journals'
      return jrnlist
    else
      ret = '<body>
        <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
          <h1 id="title" class="centre statement" style="font-size:40px;">Journal ranking :)</h1>
        </div></div>
        <div class="flex" style="margin-top: 5%;">
          <div class="c6 off3">'
    
      for jo in jrnlist
        ret += '<p>' + jo.name + ' ' + jo.percent + '% of ' + jo.papers + ' papers open' + (if jo.percent >= 50 then '!' else '') + '</p>'
          
      ret += '</div>
        </div>
        </body>'
      
      @format = 'html'
      return ret



P.svc.oaworks.report.author = (n) ->
  n ?= @params.author

  ret = '<body>
    <div class="flex" style="margin-top: 5%;"><div class="c6 off3">
      <h1 id="title" class="centre statement" style="font-size:40px;">' + (n ? '') + '</h1>
    </div></div>
    <div class="flex" style="margin-top: 5%;">
      <div class="c6 off3">
        <p>Show list of possible names to disambiguate. Ask for ORCID or additional info to identify. (Prod to get an ORCID if not got one.)</p>'
  
  if n
    names = []
    parts = n.toLowerCase().split ' '
    qr = ''
    for part in parts
      qr += ' OR ' if qr
      qr += 'author.family:' + part + ' OR author.given:' + part
    for await rec from @index._for 'src_crossref_works', qr, until: 20
      for a in rec.author ? []
        if a.family and a.given and (a.family.toLowerCase() in parts or a.given.toLowerCase() in parts) and a.given + ' ' + a.family not in names
          names.push a.given + ' ' + a.family
          ret += '<p>' + a.given + ' ' + a.family  + '</p>'
  
  ret += '
        <p>Ask for an email address for this author</p>
        <p>Provide estimate count of papers we think are by this author, how many are open, which funders funded, and estimate of how compliant to funder policies this author is.</p>
        <p>Allow to filter to a specific funder</p>
        <p>List papers that appear to be by this author, provide a checkbox to confirm</p>
        <p>Ask author/person to "share the paper" if not already OA, (and prompt which funders, if any, require this to be done hence improving author compliance score).</p>
      </div>
    </div>
    </body>'
  
  @format = 'html'
  return ret
