

# this should default to a search of ILLs as well... with a restrict
# restrict = @auth.role('openaccessbutton.admin') and this.queryParams.all then [] else [{term:{from:@user?._id}}]
P.ill = (opts) -> # only worked on POST with optional auth
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'

  if not opts?
    opts = @copy @params
    if opts.ill
      opts.doi = opts.ill
      delete opts.ill
  opts.metadata ?= await @metadata opts
  opts.pilot = Date.now() if opts.pilot is true
  opts.live = Date.now() if opts.live is true
  config = opts.config
  try config = JSON.parse config
  if typeof config is 'string' or (not config and opts.from)
    config = await @fetch 'https://api.cottagelabs.com/service/oab/ill/config?uid=' + (opts.from ? config)
    if not config? or JSON.stringify(config) is '{}'
      config = await @fetch 'https://dev.api.cottagelabs.com/service/oab/ill/config?uid=' + (opts.from ? config)
  config ?= {}
      
  vars = name: 'librarian', details: '' # anywhere to get the user name from config?
  ordered = ['title','author','volume','issue','date','pages']
  for o of opts
    if o is 'metadata'
      for m of opts[o]
        if m isnt 'email'
          opts[m] = opts[o][m]
          ordered.push(m) if m not in ordered
      delete opts.metadata
    else
      ordered.push(o) if o not in ordered
  for r in ordered
    if opts[r]
      vars[r] = opts[r]
      if r is 'author'
        authors = '<p>Authors:<br>'
        first = true
        ats = []
        for a in opts[r]
          if a.family
            if first
              first = false
            else
              authors += ', '
            atidy = a.family + (if a.given then ' ' + a.given else '')
            authors += atidy
            ats.push atidy
        vars[r] = ats
  delete opts.author if opts.author? # remove author metadata due to messy provisions causing save issues
  vars.illid = opts._id = await @uid()

  # such as https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=in%3A&si0qs=0021-9231&si1in=au%3A&si1op=AND&si2in=kw%3A&si2op=AND&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch
  # could be provided as: (unless other params are mandatory) 
  # https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?si0qs=0021-9231
  if config.search and config.search.length and (opts.issn or opts.journal)
    if config.search.indexOf('worldcat') isnt -1
      su = config.search.split('?')[0] + '?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in='
      su += if opts.issn? then 'in%3A' else 'ti%3A'
      su += '&si0qs=' + (opts.issn ? opts.journal)
      su += '&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch'
    else
      su = config.search
      su += if opts.issn then opts.issn else opts.journal
    vars.worldcatsearchurl = su

  await @ills opts
  tmpl = await @templates 'instantill_create'
  tmpl = tmpl.content
  if not opts.forwarded and not opts.resolved and (config.email or opts.email)
    @waitUntil @mail svc: 'oaworks', vars: vars, template: tmpl, to: (config.email ? opts.email), from: "InstantILL <InstantILL@openaccessbutton.org>", subject: "ILL request " + opts._id
  tmpl = tmpl.replace /Dear.*?\,/, 'Dear Joe, here is a copy of what was just sent:'
  tos = ['joe+notifications@oa.works']
  tos.push(@S.log.logs)if @S.log?.logs
  @waitUntil @mail svc: 'oaworks', vars: vars, template: tmpl, from: "InstantILL <InstantILL@openaccessbutton.org>", subject: "ILL CREATED " + opts._id, to: tos
  return opts

#P.ills = _index: true
P.ills = -> return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'


P.ill.collect = (params) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'

  params ?= @copy @params
  sid = params.collect # end of the url is an SID
  params._id ?= await @uid()
  # example AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6
  url = 'https://script.google.com/macros/s/' + sid + '/exec?'
  for q of params
    url += (if q is '_id' then 'uuid' else q) + '=' + params[q] + '&' if q isnt 'collect'
  @waitUntil @fetch url
  @waitUntil @svc.rscvd params
  return true

P.ill.openurl = (config, meta) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'

  # Will eventually redirect after reading openurl params passed here, somehow. 
  # For now a POST of metadata here by a user with an open url registered will build their openurl
  config ?= @params.config ? {}
  meta ?= @params.meta ? await @metadata()

  if config.ill_redirect_base_url
    config.ill_form ?= config.ill_redirect_base_url
  if config.ill_redirect_params
    config.ill_added_params ?= config.ill_redirect_params

  # add iupui / openURL defaults to config
  defaults =
    sid: 'sid'
    title: 'atitle' # this is what iupui needs (title is also acceptable, but would clash with using title for journal title, which we set below, as iupui do that
    doi: 'rft_id' # don't know yet what this should be
    pmcid: 'pmcid' # don't know yet what this should be
    author: 'aulast' # author should actually be au, but aulast works even if contains the whole author, using aufirst just concatenates
    journal: 'title' # this is what iupui needs
    page: 'pages' # iupui uses the spage and epage for start and end pages, but pages is allowed in openurl, check if this will work for iupui
    published: 'date' # this is what iupui needs, but in format 1991-07-01 - date format may be a problem
    year: 'rft.year' # this is what IUPUI uses
  for d of defaults
    config[d] = defaults[d] if not config[d]

  url = ''
  url += config.ill_added_params.replace('?','') + '&' if config.ill_added_params
  url += config.sid + '=InstantILL&'
  for k of meta
    v = ''
    if k is 'author'
      for author in (if Array.isArray(meta.author) then meta.author else [meta.author])
        v += ', ' if v.length
        v += if typeof author is 'string' then author else if author.family then author.family + (if author.given then ', ' + author.given else '') else JSON.stringify author
    else if k in ['doi','pmid','pmc','pmcid','url','journal','title','year','issn','volume','issue','page','crossref_type','publisher','published','notes']
      v = meta[k]
    url += (if config[k] then config[k] else k) + '=' + encodeURIComponent(v) + '&' if v
  if meta.usermetadata
    nfield = if config.notes then config.notes else 'notes'
    url = url.replace 'usermetadata=true', ''
    if url.indexOf(nfield+'=') is -1
      url += '&' + nfield + '=The user provided some metadata.'
    else
      url = url.replace nfield+'=', nfield+'=The user provided some metadata. '
  return url.replace '/&&/g', '&'


P.ill.subscription = (config, meta) ->
  return status: 410, body: 'This API has been permanently shut down. Learn more: https://blog.oa.works/sunsetting-the-open-access-button-instantill/'

  if not config and not meta and (@params.sub or @params.subscription) # assume values are being passed directly on GET request
    config = @copy @params
    config.subscription = config.sub if config.sub
    if @params.meta
      meta = @params.meta
      delete config.meta
    else if config.doi and @keys(config).length is 2
      meta = await @metadata config.doi
      delete config.doi
    else
      meta = @copy config
      delete config.doi
  config ?= @params.config ? {}
  if typeof config is 'string'
    config = await @fetch 'https://api.cottagelabs.com/service/oab/ill/config?uid=' + config
    if not config? or JSON.stringify(config) is '{}'
      config = await @fetch 'https://dev.api.cottagelabs.com/service/oab/ill/config?uid=' + (opts.from ? config)
  
  meta ?= @params.meta
  res = {findings:{}, lookups:[], error:[], contents: []}
  if config.subscription?
    if config.ill_redirect_params
      config.ill_added_params ?= config.ill_redirect_params
    # need to get their subscriptions link from their config - and need to know how to build the query string for it
    openurl = await @ill.openurl config, meta
    openurl = openurl.replace(config.ill_added_params.replace('?',''),'') if config.ill_added_params
    if typeof config.subscription is 'string'
      config.subscription = config.subscription.split(',')
    if typeof config.subscription_type is 'string'
      config.subscription_type = config.subscription_type.split(',')
    config.subscription_type ?= []
    for s of config.subscription
      sub = config.subscription[s]
      if typeof sub is 'object'
        subtype = sub.type
        sub = sub.url
      else
        subtype = config.subscription_type[s] ? 'unknown'
      sub = sub.trim()
      if sub
        if subtype is 'serialssolutions' or sub.indexOf('serialssolutions') isnt -1 #  and sub.indexOf('.xml.') is -1
          tid = sub.split('.search')[0]
          tid = tid.split('//')[1] if tid.indexOf('//') isnt -1
          #bs = if sub.indexOf('://') isnt -1 then sub.split('://')[0] else 'http' # always use http because https on the xml endpoint fails
          sub = 'http://' + tid + '.openurl.xml.serialssolutions.com/openurlxml?version=1.0&genre=article&'
        else if (subtype is 'sfx' or sub.indexOf('sfx.') isnt -1) and sub.indexOf('sfx.response_type=simplexml') is -1
          sub += (if sub.indexOf('?') is -1 then '?' else '&') + 'sfx.response_type=simplexml'
        else if (subtype is 'exlibris' or sub.indexOf('.exlibris') isnt -1) and sub.indexOf('response_type') is -1
          # https://github.com/OAButton/discussion/issues/1793
          #sub = 'https://trails-msu.userservices.exlibrisgroup.com/view/uresolver/01TRAILS_MSU/openurl?svc_dat=CTO&response_type=xml&sid=InstantILL&'
          sub = sub.split('?')[0] + '?svc_dat=CTO&response_type=xml&sid=InstantILL&'
          #ID=doi:10.1108%2FNFS-09-2019-0293&genre=article&atitle=Impact%20of%20processing%20and%20packaging%20on%20the%20quality%20of%20murici%20jelly%20%5BByrsonima%20crassifolia%20(L.)%20rich%5D%20during%20storage.&title=Nutrition%20&%20Food%20Science&issn=00346659&volume=50&issue=5&date=20200901&au=Da%20Cunha,%20Mariana%20Crivelari&spage=871&pages=871-883
          
        url = sub + (if sub.indexOf('?') is -1 then '?' else '&') + openurl
        url = url.split('snc.idm.oclc.org/login?url=')[1] if url.indexOf('snc.idm.oclc.org/login?url=') isnt -1
        url = url.replace('cache=true','')
        if subtype is 'sfx' or sub.indexOf('sfx.') isnt -1 and url.indexOf('=10.') isnt -1
          url = url.replace('=10.','=doi:10.')
        if subtype is 'exlibris' or sub.indexOf('.exlibris') isnt -1 and url.indexOf('doi=10.') isnt -1
          url = url.replace 'doi=10.', 'ID=doi:10.'

        pg = ''
        spg = ''
        error = false
        res.lookups.push url
        try
          # proxy may still be required if our main machine was registered with some of these ILL service providers...
          #pg = if url.includes('.xml.serialssolutions') or url.includes('sfx.response_type=simplexml') or url.includes('response_type=xml') then await @fetch(url) else await @puppet url
          pg = await @fetch url
          #try await @mail(to: 'mark@oa.works', subject: 'oa.works serials solutions query running', text: url + '\n\n' + JSON.stringify pg) if @S.dev
          if not pg? or typeof pg is 'object'
            #if subtype is 'serialssolutions'
            #  try await @mail(to: 'mark@oa.works', subject: 'oa.works serials solutions error', text: url + '\n\n' + JSON.stringify pg) if @S.dev
            pg = ''
            error = true
        catch err
          error = true
          #if subtype is 'serialssolutions'
          #  try await @mail to: 'mark@oa.works', subject: 'oa.works serials solutions error', text: url + '\n\n' + JSON.stringify(pg) + '\n\n' + JSON.stringify err
        try
          spg = if pg.indexOf('<body') isnt -1 then pg.toLowerCase().split('<body')[1].split('</body')[0] else pg
          res.contents.push spg
        catch err
          error = true
          #if subtype is 'serialssolutions'
          #  try await @mail to: 'mark@oa.works', subject: 'oa.works serials solutions error', text: url + '\n\n' + JSON.stringify(pg) + '\n\n' + JSON.stringify err

        # sfx 
        # with access:
        # https://cricksfx.hosted.exlibrisgroup.com/crick?sid=Elsevier:Scopus&_service_type=getFullTxt&issn=00225193&isbn=&volume=467&issue=&spage=7&epage=14&pages=7-14&artnum=&date=2019&id=doi:10.1016%2fj.jtbi.2019.01.031&title=Journal+of+Theoretical+Biology&atitle=Potential+relations+between+post-spliced+introns+and+mature+mRNAs+in+the+Caenorhabditis+elegans+genome&aufirst=S.&auinit=S.&auinit1=S&aulast=Bo
        # which will contain a link like:
        # <A title="Navigate to target in new window" HREF="javascript:openSFXMenuLink(this, 'basic1', undefined, '_blank');">Go to Journal website at</A>
        # but the content can be different on different sfx language pages, so need to find this link via the tag attributes, then trigger it, then get the page it opens
        # can test this with 10.1016/j.jtbi.2019.01.031 on instantill page
        # note there is also now an sfx xml endpoint that we have found to check
        if subtype is 'sfx' or url.indexOf('sfx.') isnt -1
          res.error.push('sfx') if error
          if spg.indexOf('getFullTxt') isnt -1 and spg.indexOf('<target_url>') isnt -1
            try
              # this will get the first target that has a getFullTxt type and has a target_url element with a value in it, or will error
              res.url = spg.split('getFullTxt')[1].split('</target>')[0].split('<target_url>')[1].split('</target_url>')[0].trim()
              res.findings.sfx = res.url
              if res.url?
                if res.url.indexOf('getitnow') is -1
                  res.found = 'sfx'
                else
                  res.url = undefined
                  res.findings.sfx = undefined
          else
            if spg.indexOf('<a title="navigate to target in new window') isnt -1 and spg.split('<a title="navigate to target in new window')[1].split('">')[0].indexOf('basic1') isnt -1
              # tried to get the next link after the click through, but was not worth putting more time into it. For now, seems like this will have to do
              res.url = url
              res.findings.sfx = res.url
              if res.url?
                if res.url.indexOf('getitnow') is -1
                  res.found = 'sfx'
                else
                  res.url = undefined
                  res.findings.sfx = undefined

        # eds
        # note eds does need a login, but IP address range is supposed to get round that
        # our IP is supposed to be registered with the library as being one of their internal ones so should not need login
        # however a curl from our IP to it still does not seem to work - will try with puppeteer to see if it is blocking in other ways
        # not sure why the links here are via an oclc login - tested, and we will use without it
        # with access:
        # https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=RE&aulast=Marx&atitle=Platelet-rich+plasma:+growth+factor+enhancement+for+bone+grafts&id=doi:10.1016/S1079-2104(98)90029-4&title=Oral+Surgery,+Oral+Medicine,+Oral+Pathology,+Oral+Radiology,+and+Endodontology&volume=85&issue=6&date=1998&spage=638&issn=1079-2104
        # can be tested on instantill page with 10.1016/S1079-2104(98)90029-4
        # without:
        # https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=MP&aulast=Newton&atitle=Librarian+roles+in+institutional+repository+data+set+collecting:+outcomes+of+a+research+library+task+force&id=doi:10.1080/01462679.2011.530546
        else if subtype is 'eds' or url.indexOf('ebscohost.') isnt -1
          res.error.push('eds') if error
          if spg.indexOf('view this ') isnt -1 and pg.indexOf('<a data-auto="menu-link" href="') isnt -1
            res.url = url.replace('://','______').split('/')[0].replace('______','://') + pg.split('<a data-auto="menu-link" href="')[1].split('" title="')[0]
            res.findings.eds = res.url
            if res.url?
              if res.url.indexOf('getitnow') is -1
                res.found = 'eds'
              else
                res.url = undefined

        # serials solutions
        # the HTML source code for the No Results page includes a span element with the class SS_NoResults. This class is only found on the No Results page (confirmed by serialssolutions)
        # with:
        # https://rx8kl6yf4x.search.serialssolutions.com/?genre=article&issn=14085348&title=Annales%3A%20Series%20Historia%20et%20Sociologia&volume=28&issue=1&date=20180101&atitle=HOW%20TO%20UNDERSTAND%20THE%20WAR%20IN%20SYRIA.&spage=13&PAGES=13-28&AUTHOR=%C5%A0TERBENC%2C%20Primo%C5%BE&&aufirst=&aulast=&sid=EBSCO:aph&pid=
        # can test this on instantill page with How to understand the war in Syria - Annales Series Historia et Sociologia 2018
        # but the with link has a suppressed link that has to be clicked to get the actual page with the content on it
        # <a href="?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick">Click here</a>
        # which is the only link with the showsuppressedlinks param and the clickhere content
        # then the page with the content link is like:
        # https://rx8kl6yf4x.search.serialssolutions.com/?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick
        # and the content is found in a link like this:
        # <div id="ArticleCL" class="cl">
        #   <a target="_blank" href="./log?L=RX8KL6YF4X&amp;D=EAP&amp;J=TC0000940997&amp;P=Link&amp;PT=EZProxy&amp;A=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&amp;H=c7306f7121&amp;U=http%3A%2F%2Fwww.ulib.iupui.edu%2Fcgi-bin%2Fproxy.pl%3Furl%3Dhttp%3A%2F%2Fopenurl.ebscohost.com%2Flinksvc%2Flinking.aspx%3Fgenre%3Darticle%26issn%3D1408-5348%26title%3DAnnales%2BSeries%2Bhistoria%2Bet%2Bsociologia%26date%3D2018%26volume%3D28%26issue%3D1%26spage%3D13%26atitle%3DHOW%2BTO%2BUNDERSTAND%2BTHE%2BWAR%2BIN%2BSYRIA.%26aulast%3D%25C5%25A0TERBENC%26aufirst%3DPrimo%C5%BE">Article</a>
        # </div>
        # without:
        # https://rx8kl6yf4x.search.serialssolutions.com/directLink?&atitle=Writing+at+the+Speed+of+Sound%3A+Music+Stenography+and+Recording+beyond+the+Phonograph&author=Pierce%2C+J+Mackenzie&issn=01482076&title=Nineteenth+Century+Music&volume=41&issue=2&date=2017-10-01&spage=121&id=doi:&sid=ProQ_ss&genre=article
        # we also have an xml alternative for serials solutions
        # see https://journal.code4lib.org/articles/108
        else if subtype is 'serialssolutions' or url.indexOf('serialssolutions.') isnt -1
          res.error.push('serialssolutions') if error
          if spg.indexOf('<ssopenurl:url type="article">') isnt -1
            fnd = spg.split('<ssopenurl:url type="article">')[1].split('</ssopenurl:url>')[0].trim().replace(/&amp;/g, '&') # this gets us something that has an empty accountid param - do we need that for it to work?
            if fnd.length
              res.url = fnd
              res.findings.serials = res.url
              if res.url?
                if res.url.indexOf('getitnow') is -1
                  res.found = 'serials'
                else
                  res.url = undefined
                  res.findings.serials = undefined
            # disable journal matching for now until we have time to get it more accurate - some things get journal links but are not subscribed
            #else if spg.indexOf('<ssopenurl:result format="journal">') isnt -1
            #  # we assume if there is a journal result but not a URL that it means the institution has a journal subscription but we don't have a link
            #  res.journal = true
            #  res.found = 'serials'
          else
            if spg.indexOf('ss_noresults') is -1
              surl = url.split('?')[0] + '?ShowSupressedLinks' + pg.split('?ShowSupressedLinks')[1].split('">')[0]
              #try await @mail to: 'mark@oa.works', subject: 'oa.works serials solutions query running second stage', text: surl + '\n\n' + JSON.stringify pg
              try
                #npg = await @puppet surl # would this still need proxy?
                npg = await @fetch surl
                #try await @mail to: 'mark@oa.works', subject: 'oa.works serials solutions query running second stage succeeded', text: surl + '\n\n' + JSON.stringify npg
                if npg.indexOf('ArticleCL') isnt -1 and npg.split('DatabaseCL')[0].indexOf('href="./log') isnt -1
                  res.url = surl.split('?')[0] + npg.split('ArticleCL')[1].split('DatabaseCL')[0].split('href="')[1].split('">')[0].replace(/&amp;/g, '&')
                  res.findings.serials = res.url
                  if res.url?
                    if res.url.indexOf('getitnow') is -1
                      res.found = 'serials'
                    else
                      res.url = undefined
                      res.findings.serials = undefined
              catch err
                res.error.push('serialssolutions') if error
                #try await @mail to: 'mark@oa.works', subject: 'oa.works serials solutions second stage error', text: 'serials solutions later error\n\n' + url + '\n\n' + surl + '\n\n' + JSON.stringify(pg) + '\n\n' + JSON.stringify err

        else if subtype is 'exlibris' or url.indexOf('.exlibris') isnt -1
          res.error.push('exlibris') if error
          if spg.indexOf('full_text_indicator') isnt -1 and spg.split('full_text_indicator')[1].replace('">', '').indexOf('true') is 0 and spg.indexOf('resolution_url') isnt -1
            res.url = spg.split('<resolution_url>')[1].split('</resolution_url>')[0].replace(/&amp;/g, '&')
            res.findings.exlibris = res.url
            res.found = 'exlibris'

  res.url = await @decode(res.url) if res.url
  return res


