P.template = (content, vars) ->
  content ?= @params.content ? @params.template ? @body
  vars ?= @params
  if @params.url or content.startsWith 'http'
    content = await @fetch @params.url ? content
  if content.indexOf(' ') is -1 and content.indexOf('.') isnt -1 and content.length < 100
    try
      cs = await @templates content
      content = cs.content
  ret = {}
  _rv = (obj, pre='') ->
    for o of obj
      ov = if pre then pre + '.' + o else o
      if typeof obj[o] is 'object' and not Array.isArray obj[o]
        _rv obj[o], pre + (if pre is '' then '' else '.') + o
      else if content.toLowerCase().indexOf('{{'+ov+'}}') isnt -1
        rg = new RegExp '{{'+ov+'}}', 'gi'
        content = content.replace rg, (if Array.isArray(obj[o]) then obj[o].join(', ') else (if typeof obj[o] is 'string' then obj[o] else (if obj[o] is true then 'Yes' else (if obj[o] is false then 'No' else ''))))
  _rv vars # replace all vars that are in the content
  kg = new RegExp '{{.*?}}', 'gi'
  if content.indexOf('{{') isnt -1 # retrieve any vars provided IN the content (e.g. a content template can specify a subject for an email to use)
    vs = ['subject','from','to','cc','bcc']
    # the could be vars in content that themselves contain vars, e.g {{subject I am the subject about {{id}} yes I am}}
    # and some of those vars may fail to get filled in. So define the list of possible vars names THEN go through the content with them
    for cp in content.toLowerCase().split '{{'
      pcp = cp.split('{{')[0].split('}}')[0].split(' ')[0]
      vs.push(pcp) if pcp not in vs
    for k in vs
      key = if content.toLowerCase().indexOf('{{'+k) isnt -1 then k else undefined
      if key
        keyu = if content.indexOf('{{'+key.toUpperCase()) isnt -1 then key.toUpperCase() else key
        val = content.split('{{'+keyu)[1]
        val = val.replace(kg,'') if val.split('}}')[0].indexOf('{{') # remove any vars present inside this one that were not able to have their values replaced
        val = val.split('}}')[0].trim()
        ret[key] = val if val
        kkg = new RegExp('{{'+keyu+'.*?}}','gi')
        content = content.replace(kkg,'')
  content = content.replace(kg, '') if content.indexOf('{{') isnt -1 # remove any outstanding vars in content that could not be replaced by provided vars
  ret.content = content
  # TODO consider if worth putting markdown formatting back in here, and how big a markdown parser is
  return ret # an obj of the content plus any vars found within the template

P.templates = _key: 'name', _sheet: '1Xg-dBpCkVWglditd6gESYRgMtve4CAImXe-321ra2fo/Templates'

