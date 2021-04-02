

# need listing of deposits and deposited for each user ID
# and/or given a uid, find the most recent URL that this users uid submitted a deposit for
# need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
# make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)


# NOTE to receive files cloudflare should be setup to DNS route this directly to backend, and any calls to it should call that dns subdomain
# because otherwise cloudflare will limit file upload size (100mb by default, and enterprise plans required for more)
# however also busboy is required, so needs to be a direct call to backend
P.svc.oaworks.deposit = (params, files, dev) ->
  # so need some metadata in params.metadata
  params ?= @copy @params
  files ?= @request.files # TODO check where these will end up - will they only work on bg with busboy?

  dep = {zenodo: {}}
  dep[k] = params[k] for k in ['embedded', 'demo', 'pilot', 'live', 'email', 'plugin']
  dep.pilot = if dep.pilot is true then Date.now() else undefined
  dep.live = if dep.live is true then Date.now() else undefined
  dep.name = (files[0].filename ? files[0].name) if files? and files.length
  dep.from = params.from if params.from isnt 'anonymous' # should it still be possible to deposit anonymously?
  dep.confirmed = decodeURIComponent(params.confirmed) if params.confirmed # if confirmed is true the submitter has confirmed this is the right file. If confirmed is the checksum this is a resubmit by an admin

  uc = params.config # should exist but may not
  if not params.config and params.from
    uc = await @fetch 'https://' + (if @S.dev or dev then 'dev.' else '') + 'api.cottagelabs.com/service/oab/deposit/config?uid=' + params.from

  perms = await @svc.oaworks.permissions params.metadata # should metadata be retrieved if not present? default to looking for a doi or similar somewhere else in params?
  # TODO move file check into here, not in permissions any more
  if perms.file?.archivable and ((dep.confirmed? and dep.confirmed is perms.file.checksum) or not dep.confirmed) # if the depositor confirms we don't deposit, we manually review - only deposit on admin confirmation (but on dev allow it)
    zn = content: files[0].data, name: perms.file.name
    zn.publish = @S.svc.oaworks?.deposit?.zenodo is true
    creators = []
    for a in params.metadata?.author ? []
      if a.family?
        at = {name: a.family + (if a.given then ', ' + a.given else '')}
        try at.orcid = a.ORCID.split('/').pop() if a.ORCID
        try at.affiliation = a.affiliation.name if typeof a.affiliation is 'object' and a.affiliation.name?
        creators.push at 
    creators = [{name:'Unknown'}] if creators.length is 0
    description = if params.metadata.abstract then params.metadata.abstract + '<br><br>' else ''
    description += perms.best_permission?.deposit_statement ? (if params.metadata.doi? then 'The publisher\'s final version of this work can be found at https://doi.org/' + d.metadata.doi else '')
    description = description.trim()
    description += '.' if description.lastIndexOf('.') isnt description.length-1
    description += ' ' if description.length
    description += '<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.'
    meta =
      title: params.metadata.title ? 'Unknown',
      description: description.trim(),
      creators: creators,
      version: if perms.file.version is 'preprint' then 'Submitted Version' else if perms.file.version is 'postprint' then 'Accepted Version' else if perms.file.version is 'publisher pdf' then 'Published Version' else 'Accepted Version',
      journal_title: params.metadata.journal
      journal_volume: params.metadata.volume
      journal_issue: params.metadata.issue
      journal_pages: params.metadata.page
    #meta.keywords = params.metadata.keyword if Array.isArray(params.metadata.keyword) and params.metadata.keyword.length and typeof params.metadata.keyword[0] is 'string'
    if params.metadata.doi?
      in_zenodo = await @src.zenodo.records.doi params.metadata.doi
      if in_zenodo and dep.confirmed isnt perms.file.checksum and not @S.dev and not dev
        dep.zenodo.already = in_zenodo.id # we don't put it in again although we could with doi as related field - but leave for review for now
      else if in_zenodo
        meta['related_identifiers'] = [{relation: (if meta.version is 'postprint' or meta.version is 'AAM' or meta.version is 'preprint' then 'isPreviousVersionOf' else 'isIdenticalTo'), identifier: d.metadata.doi}]
      else
        meta.doi = params.metadata.doi
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
    try meta['publication_date'] = params.metadata.published if params.metadata.published? and typeof params.metadata.published is 'string'
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
    tk = if @S.dev or dev or dep.demo then @S.svc.oaworks?.zenodo?.sandbox else @S.svc.oaworks?.zenodo?.token
    if tk
      if not dep.zenodo.already
        z = await @src.zenodo.deposition.create meta, zn, tk
        if z.id
          dep.zenodo.id = z.id
          dep.zenodo.url = 'https://' + (if @S.dev or dev or dep.demo then 'sandbox.' else '') + 'zenodo.org/record/' + z.id
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
  else if options.from and (not dep.embedded or (dep.embedded.indexOf('oa.works') is -1 and dep.embedded.indexOf('openaccessbutton.org') is -1 and dep.embedded.indexOf('shareyourpaper.org') is -1))
    dep.type = if options.redeposit then 'redeposit' else if files? and files.length then 'forward' else 'dark'
  else
    dep.type = 'review'

  bcc = ['joe@openaccessbutton.org', 'natalia.norori@openaccessbutton.org']
  tos = []
  if typeof uc?.owner is 'string' and uc.owner.indexOf('@') isnt -1
    tos.push uc.owner
  else if uc.email
    tos.push uc.email
  if tos.length is 0
    tos = @copy bcc
    bcc = []

  dep.url = if typeof options.redeposit is 'string' then options.redeposit else if options.url then options.url else undefined

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
  tmpl = await @svc.oaworks.templates dep.type + '_deposit.html'
  tmpl = tmpl.content
  if perms.file?.archivable isnt false # so when true or when undefined if no file is given
    ml =
      from: 'deposits@openaccessbutton.org'
      to: tos
      template: tmpl
      vars: ed
      subject: (sub.subject ? dep.type + ' deposit')
      html: sub.content
    ml.bcc = bcc if bcc.length # passing undefined to mail seems to cause errors, so only set if definitely exists
    ml.attachments = [{filename: (files[0].filename ? files[0].name), content: files[0].data}] if Array.isArray(files) and files.length
    @waitUntil @mail ml

  return dep

P.svc.oaworks.deposit._index = true # store a record of all deposits
