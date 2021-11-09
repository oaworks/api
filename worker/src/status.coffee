
P.status = ->
  res = name: S.name, version: S.version, built: S.built
  for k in ['rid', 'params', 'base', 'parts', 'opts', 'routes']
    try res[k] ?= @[k]
  if @S.bg is true
    try
      res.schedule = {}
      for ss of _schedule
        res.schedule[ss] = {}
        for k of _schedule[ss]
          res.schedule[ss][k] = _schedule[ss][k] if k not in ['fn']
  res.bg = true if @S.bg is true
  res.kv = if typeof @S.kv is 'string' and global[@S.kv] then @S.kv else if typeof @S.kv is 'string' then @S.kv else false
  try res.index = await @index.status()
  if S.dev
    res.bg = @S.bg
    if @S.bg isnt true
      try res.request = @request
    for k in ['headers', 'cookie', 'user', 'body']
      try res[k] ?= @[k]
  else
    try res.index = res.index.status
    res.kv = true if res.kv
    res.user = @user.email if @user?.email
      
  # maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  # maybe some useful info from the recent logs too
  return res


'''

import fs from 'fs'

P.structure = (src) ->
  collections = []
  methods = {}
  settings = {}
  called = {}
  TODO = {}

  method = {}
  incomment = false
  inroute = false
  for l of lns = (await fs.readFile src).toString().replace(/\r\n/g,'\n').split '\n'
    line = lns[l].replace /\t/g, '  '
    if JSON.stringify(method) isnt '{}' and (l is '0' or parseInt(l) is lns.length-1 or (line.indexOf('P.') is 0 and line.indexOf('>') isnt -1))
      method.code = method.code.trim()
      if method.name.indexOf('P.') is 0
        methods[method.name] = method
      method = {}

    if line.indexOf('S.') isnt -1
      stng = (if line.indexOf('@S.') isnt -1 then '@S.' else 'S.') + line.split('S.')[1].split(' ')[0].split(')')[0].split('}')[0].split(',')[0].split('.indexOf')[0].replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace /\.$/, ''
      if stng.split('.').length > 1
        if method.name
          method.settings ?= []
          method.settings.push(stng) if stng not in method.settings
        settings.push(stng) if stng not in settings

    if line.indexOf('P.') is 0
      inroute = line.split(' ')[1].split(',')[0].replace(/'/g,'').replace(/"/g,'')
      if inroute.split('/').pop() is 'test'
        inroute = false
      else
        routes[inroute] ?= {methods: [], code: ''}

    if line.toLowerCase().indexOf('todo') isnt -1
      TODO[method.name ? 'GENERAL'] ?= []
      TODO[method.name ? 'GENERAL'].push line.split(if line.indexOf('todo') isnt -1 then 'todo' else 'TODO')[1].trim()
    if incomment or not line.length
      # TODO these line index and trims should have three single quotes inside the doubles, which breaks parsing while commented out, so removing for now
      if line.indexOf("") isnt -1
        incomment = false
    else if line.trim().startsWith('#') or line.trim().startsWith("")
      if line.trim().startsWith("")
        incomment = true
    else if line.indexOf('P.') is 0 or (not line.startsWith(' ') and line.indexOf('=') isnt -1)
      inroute = false
      method = {}
      method.code = line
      method.name = line.split(' ')[0]
      method.group = if method.name.indexOf('svc.') isnt -1 then method.name.split('svc.')[1].split('.')[0] else if method.name.indexOf('src.') isnt -1 then method.name.split('src.')[1].split('.')[0] else if method.name.indexOf('P.') is 0 then method.name.replace('P.','').split('.')[0] else undefined
      method.args = if line.indexOf('(') is -1 then [] else line.split('(')[1].split(')')[0].split(',')
      for a of method.args
        method.args[a] = method.args[a].trim()
      method.calls = []
      method.remotes = []
    else if inroute
      routes[inroute].code += (if routes[inroute].code then '\n' else '') + line
      if line.indexOf('P.') isnt -1
        rtm = line.replace('P.','')
        if rtm.indexOf('P.') isnt -1
          rtmc = 'P.' + rtm.split('P.')[1].split(' ')[0].split('(')[0].replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace(/\.$/,'')
          routes[inroute].methods.push(rtmc) if rtmc.length and rtmc.split('.').length > 1 and rtmc not in routes[inroute].methods
    else if method.name?
      method.code += '\n' + line
      li = line.indexOf 'P.'
      if li isnt -1
        parts = line.split 'P.'
        parts.shift()
        for p in parts
          p = if tp is 'P.' then tp + p.split(' ')[0].split('(')[0].split(')')[0].trim() else p.trim().replace('call ','').replace('call(','')
          if tp is 'P.' and p not in method.calls
            if p.indexOf('?') is -1
              pt = p.replace(/[^a-zA-Z0-9\.\[\]]/g,'').replace(/\.$/,'')
              if pt.length and pt.split('.').length > 1 and pt not in method.calls
                method.calls.push pt
                called[pt] ?= []
                called[pt].push method.name

  for rk in @keys(routes).sort()
    for mt in routes[rk].methods
      if methods[mt]? and (not methods[mt].routes? or rk not in methods[mt].routes)
        methods[mt].routes ?= []
        methods[mt].routes.push rk
  for cl of called
    methods[cl].called = called[cl].sort() if methods[cl]? # where are the missing ones? in collections?
  
  res = count: @keys(methods).length, collections: collections.sort(), methods: methods, routes: routes, TODO: TODO
  res = P.structure.nodeslinks res
  return res

P.structure.groups = () ->
  sr = API.structure.read()
  return sr.groups ? API.structure.nodeslinks().groups

P.structure.nodeslinks = (sr, group) ->
  sr ?= P.structure()
  positions = {}
  counters = {}
  nds = []
  groups = []
  colls = {}
  for m of sr.methods
    method = sr.methods[m]
    rec = {}
    rec.key = method.name
    counters[rec.key] = 1
    rec.group = method.group
    groups.push(rec.group) if rec.group not in groups
    rec.calls = method.calls
    rec.collections = method.collections
    nds.push rec
    positions[rec.key] = nds.length-1
    for c of method.collections
      colls[c] ?= []
      for pc in method.collections[c]
        apc = 'API.collection.prototype.' + pc
        colls[c].push(apc) if apc not in colls[c]

  lns = []
  extras = []
  esp = {}
  nl = nds.length
  for n of nds
    node = nds[n]
    for c in node.calls ? []
      if not counters[c]
        counters[c] = 1
      else if not group or c.indexOf('.'+group) isnt -1
        counters[c] += 1
      pos = positions[c]
      if not pos?
        pos = esp[c]
      if not pos?
        extras.push {key: c, group: 'MISSING'}
        esp[c] = extras.length-1
        pos = nl + extras.length - 2
      if (not group or c.indexOf('.'+group) isnt -1 or node.group is group)
        lns.push {source: parseInt(n), target: pos}
    for co of node.collections ? {}
      if not counters[co]
        counters[co] = 1
      else if not group or c.indexOf('.'+group) isnt -1
        counters[co] += 1
      if not group or co.indexOf('.'+group) isnt -1 or node.group is group or group in ['collection','collections','es']
        lns.push {source: parseInt(n), target: positions[co]}

  for e of extras
    nds.push extras[e]

  for nd of nds
    cv = counters[nds[nd].key] ? 1
    nds[nd].value = cv
    nds[nd].size = cv

  sr.nodecount ?= nds.length
  sr.linkcount ?= lns.length
  sr.nodes ?= nds
  sr.links ?= lns
  sr.groups ?= groups.sort()

  return sr
'''

