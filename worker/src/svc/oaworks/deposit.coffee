

# need listing of deposits and deposited for each user ID
# and/or given a uid, find the most recent URL that this users uid submitted a deposit for
# need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
# make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)

'''
P.svc.oaworks.deposit = (options={}, files) ->
  # so need some metadata in options.metadata

  d.deposit ?= []
  dep = {createdAt: Date.now(), zenodo: {}}
  dep.embedded = options.embedded if options.embedded
  dep.demo = options.demo if options.demo
  dep.pilot = options.pilot if options.pilot
  if typeof dep.pilot is 'boolean' or dep.pilot in ['true','false'] # catch possible old erros with live/pilot values
    dep.pilot = if dep.pilot is true or dep.pilot is 'true' then Date.now() else undefined
  dep.live = options.live if options.live
  if typeof dep.live is 'boolean' or dep.live in ['true','false']
    dep.live = if dep.live is true or dep.live is 'true' then Date.now() else undefined
  dep.name = (files[0].filename ? files[0].name) if files? and files.length
  dep.email = options.email if options.email
  dep.from = options.from if options.from and options.from isnt 'anonymous' # should it still be possible to deposit anonymously?
  dep.plugin = options.plugin if options.plugin
  dep.confirmed = decodeURIComponent(options.confirmed) if options.confirmed

  uc = options.config # should exist but may not

  perms = @svc.oaworks.permissions d, files, undefined, dep.confirmed # if confirmed is true the submitter has confirmed this is the right file. If confirmed is the checksum this is a resubmit by an admin
  if perms.file?.archivable and ((dep.confirmed? and dep.confirmed is perms.file.checksum) or not dep.confirmed) # if the depositor confirms we don't deposit, we manually review - only deposit on admin confirmation (but on dev allow it)
    zn = {}
    zn.content = files[0].data
    zn.name = perms.file.name
    zn.publish = @S.svc.oaworks?.deposit?.zenodo is true
    creators = []
    try
      for a in d.metadata.author
        if a.family?
          at = {name: a.family + (if a.given then ', ' + a.given else '')}
          try at.orcid = a.ORCID.split('/').pop() if a.ORCID
          try at.affiliation = a.affiliation.name if typeof a.affiliation is 'object' and a.affiliation.name?
          creators.push at 
    creators = [{name:'Unknown'}] if creators.length is 0
    description = if d.metadata.abstract then d.metadata.abstract + '<br><br>' else ''
    description += perms.best_permission?.deposit_statement ? (if d.metadata.doi? then 'The publisher\'s final version of this work can be found at https://doi.org/' + d.metadata.doi else '')
    description = description.trim()
    description += '.' if description.lastIndexOf('.') isnt description.length-1
    description += ' ' if description.length
    description += '<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.'
    meta =
      title: d.metadata.title ? 'Unknown',
      description: description.trim(),
      creators: creators,
      version: if perms.file.version is 'preprint' then 'Submitted Version' else if perms.file.version is 'postprint' then 'Accepted Version' else if perms.file.version is 'publisher pdf' then 'Published Version' else 'Accepted Version',
      journal_title: d.metadata.journal
      journal_volume: d.metadata.volume
      journal_issue: d.metadata.issue
      journal_pages: d.metadata.page
    meta.keywords = d.metadata.keyword if _.isArray(d.metadata.keyword) and d.metadata.keyword.length and typeof d.metadata.keyword[0] is 'string'
    if d.metadata.doi?
      in_zenodo = @src.zenodo.records.doi d.metadata.doi
      if in_zenodo and dep.confirmed isnt perms.file.checksum and not @S.dev
        dep.zenodo.already = in_zenodo.id # we don't put it in again although we could with doi as related field - but leave for review for now
      else if in_zenodo
        meta['related_identifiers'] = [{relation: (if meta.version is 'postprint' or meta.version is 'AAM' or meta.version is 'preprint' then 'isPreviousVersionOf' else 'isIdenticalTo'), identifier: d.metadata.doi}]
      else
        meta.doi = d.metadata.doi
    else if @S.svc.oaworks.zenodo?.prereserve_doi
      meta.prereserve_doi = true
    meta['access_right'] = 'open'
    meta.license = perms.best_permission?.licence ? 'cc-by' # zenodo also accepts other-closed and other-nc, possibly more
    meta.license = 'other-closed' if meta.license.indexOf('other') isnt -1 and meta.license.indexOf('closed') isnt -1
    meta.license = 'other-nc' if meta.license.indexOf('other') isnt -1 and meta.license.indexOf('non') isnt -1 and meta.license.indexOf('commercial') isnt -1
    meta.license += '-4.0' if meta.license.toLowerCase().indexOf('cc') is 0 and isNaN(parseInt(meta.license.substring(meta.license.length-1)))
    try
      if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,'YYYY-MM-DD').valueOf() > Date.now()
        meta['access_right'] = 'embargoed'
        meta['embargo_date'] = perms.best_permission.embargo_end # check date format required by zenodo
    try meta['publication_date'] = d.metadata.published if d.metadata.published? and typeof d.metadata.published is 'string'
    if uc
      uc.community = uc.community_ID if uc.community_ID? and not uc.community?
      if uc.community
        uc.communities ?= []
        uc.communities.push({identifier: ccm}) for ccm in (if typeof uc.community is 'string' then uc.community.split(',') else uc.community)
      if uc.community? or uc.communities?
        uc.communities ?= uc.community
        uc.communities = [uc.communities] if not Array.isArray uc.communities
        meta['communities'] = []
        meta.communities.push(if typeof com is 'string' then {identifier: com} else com) for com in uc.communities
    tk = if @S.dev or dep.demo then @S.svc.oaworks?.zenodo?.sandbox else @S.svc.oaworks?.zenodo?.token
    if tk
      if not dep.zenodo.already
        z = @src.zenodo.deposition.create meta, zn, tk
        if z.id
          dep.zenodo.id = z.id
          dep.zenodo.url = 'https://' + (if @S.dev or dep.demo then 'sandbox.' else '') + 'zenodo.org/record/' + z.id
          dep.zenodo.doi = z.metadata.prereserve_doi.doi if z.metadata?.prereserve_doi?.doi?
          dep.zenodo.file = z.uploaded?.links?.download ? z.uploaded?.links?.download
        else
          dep.error = 'Deposit to Zenodo failed'
          try dep.error += ': ' + JSON.stringify z
    else
      dep.error = 'No Zenodo credentials available'
  dep.version = perms.file.version if perms.file?.version?
  if dep.zenodo.id
    if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,'YYYY-MM-DD').valueOf() > Date.now()
      dep.embargo = perms.best_permission.embargo_end
    dep.type = 'zenodo'
  else if dep.error? and dep.error.toLowerCase().indexOf('zenodo') isnt -1
    dep.type = 'review'
  else if options.from and (not dep.embedded or (dep.embedded.indexOf('openaccessbutton.org') is -1 and dep.embedded.indexOf('shareyourpaper.org') is -1))
    dep.type = if options.redeposit then 'redeposit' else if files? and files.length then 'forward' else 'dark'
  else
    dep.type = 'review'
  # save the deposit record somewhere for later review

  bcc = ['joe@righttoresearch.org','natalia.norori@openaccessbutton.org']
  tos = []
  if typeof uc?.owner is 'string' and uc.owner.indexOf('@') isnt -1
    tos.push uc.owner
  else if dep.from and iacc = API.accounts.retrieve dep.from
    try tos.push iacc.email ? iacc.emails[0].address # the institutional user may set a config value to use as the contact email address but for now it is the account address
  if tos.length is 0
    tos = _.clone bcc
    bcc = []

  dep.permissions = perms
  dep.url = if typeof options.redeposit is 'string' then options.redeposit else if d.url then d.url else undefined

  ed = @copy dep
  if ed.metadata?.author?
    as = []
    for author in ed.metadata.author
      if author.family
        as.push (if author.given then author.given + ' ' else '') + author.family
    ed.metadata.author = as
  ed.adminlink = (if ed.embedded then ed.embedded else 'https://shareyourpaper.org' + (if ed.metadata?.doi? then '/' + ed.metadata.doi else ''))
  ed.adminlink += if ed.adminlink.indexOf('?') is -1 then '?' else '&'
  if perms?.file?.checksum?
    ed.confirmed = encodeURIComponent perms.file.checksum
    ed.adminlink += 'confirmed=' + ed.confirmed + '&'
  ed.adminlink += 'email=' + ed.email
  tmpl = API.mail.template dep.type + '_deposit.html'
  sub = API.service.oab.substitute tmpl.content, ed
  if perms.file?.archivable isnt false # so when true or when undefined if no file is given
    ml =
      from: 'deposits@openaccessbutton.org'
      to: tos
      subject: (sub.subject ? dep.type + ' deposit')
      html: sub.content
    ml.bcc = bcc if bcc.length # passing undefined to mail seems to cause errors, so only set if definitely exists
    ml.attachments = [{filename: (files[0].filename ? files[0].name), content: files[0].data}] if _.isArray(files) and files.length
    @mail ml

  dep.z = z if @S.dev and dep.zenodo.id? and dep.zenodo.id isnt 'EXAMPLE'
  
  if dep.embargo
    try dep.embargo_UI = moment(dep.embargo).format "Do MMMM YYYY"
  return dep

'''
