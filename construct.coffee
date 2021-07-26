
# NOTE only up to 32 cloudflare workers variables are allowed, a combined count of 
# secret variables and normal env variables (e.g. set via CF UI)
# each uploaded secret can only be up to 1KB in size

# deploy with environment choice? dev/live/other?
# need node and npm. If not present, this will fail

fs = require 'fs'
coffee = require 'coffeescript'
https = require 'https'
{exec} = require 'child_process'
crypto = require 'crypto'
# uglify-js (2.x, such as 2.8.29) and uglifycss are also required for client transforms
# see below in the client section where it will attempt to require them


ENV = '' # if env is provided, look in usual secrets folders for files prefixed with ENV_ and prefer them, but if not present, use whatever else is there
GROUP = '' # if group is provided look for secrets folders prefixed with GROUP_ and ONLY use those. If they're not present don't use the default ones.
# so group could be used to send workers to completely different CF accounts with separate configs, whereas env allows overwrites of certain configs
# should ENV try to deploy to a script ID prefixed with the ENV name as well? It would have to exist first, or does CF API create it on PUT?

args = process.argv.slice 2
rm = []
for a of args
  arg = args[a]
  if arg.toLowerCase().indexOf('env=') isnt -1
    rm.push a
    ENV = arg.split('=')[1].trim() + '_'
  if arg.toLowerCase().indexOf('group=') isnt -1
    rm.push a
    GROUP = arg.split('=')[1].trim() + '_'
for r in rm
  delete args[r]

if GROUP
  console.log 'Deploying with any secrets in group secrets folders named with prefix ' + GROUP + (if ENV then ', overriding with files prefixed with ' + ENV else '')
else if ENV
  console.log 'Deploying with default secrets folders, overriding with files prefixed with ' + ENV

if args.length and 'worker' not in args and 'server' not in args
  args.push 'worker' # do both unless only one is specified
  args.push 'server'
if not args.length
  args = ['build', 'deploy', 'worker', 'server', 'secrets', 'client']
  console.log "Doing full deploy, which tries all options:"
  console.log "build - build one or both of worker and server (defaults to both unless only one is specified)"
  console.log "deploy - deploy one or both of worker and server (if settings configure somewhere to deploy to)"
  console.log "worker - build/deploy the worker (deploys to cloudflare if suitable env settings are available)"
  console.log "server - build/deploy the server (deploys to remote server if suitable env settings are available)"
  console.log "secrets - deploy secrets (if any) to cloudflare worker (secrets are always included in a server build)"
  console.log "client - builds the supplemental browser scripts in the client directory\n"

if not fs.existsSync('./' + GROUP + 'secrets') and not fs.existsSync('./worker/' + GROUP + 'secrets') and not fs.existsSync('./server/' + GROUP + 'secrets')
  console.log "No settings or secrets available, so DEMO version being built. Read more about settings and secrets in the docs."
  DEMO = true
else
  DEMO = false

SYSTOKEN = crypto.randomBytes(32).toString 'hex'
DATE = new Date().toString().split(' (')[0]
VERSION = '' # get read from main worker file

CNS = []
if fs.existsSync './' + GROUP + 'secrets/' + ENV + 'construct.json'
  CNS = JSON.parse fs.readFileSync('./' + GROUP + 'secrets/' + ENV + 'construct.json').toString()
  CNS = [CNS] if not Array.isArray CNS
else
  console.log "No cloudflare config loaded."
  console.log "A folder called " + GROUP + "secrets should be placed at the top level directory / root of the project, and also one each in server/ and worker/"
  console.log "Anything in these folders will be ignored by any future git commits, so it is safe to put secret data in them."
  console.log "Deployment to cloudflare requires a ./secrets/construct.json file containing an object with keys ACCOUNT_ID, SCRIPT_ID, API_TOKEN"

_put = (data) ->
  if typeof data isnt 'string'
    data = JSON.stringify data
    ps = '/secrets'
  else
    ps = ''
  for CNE in CNS
    console.log 'Sending for ' + CNE.SCRIPT_ID + (if CNE.NAME then ' on ' + CNE.NAME else '')
    if CNE.ACCOUNT_ID and CNE.SCRIPT_ID and CNE.API_TOKEN
      # data is either an object to send to secrets, or a file handle to stream to worker
      opts =
        hostname: 'api.cloudflare.com'
        port: 443
        path: '/client/v4/accounts/' + CNE.ACCOUNT_ID + '/workers/scripts/' + CNE.SCRIPT_ID + ps
        method: 'PUT'
        headers:
          'Content-Type': 'application/javascript'
          #'Content-Length': data.length
          'Authorization': 'Bearer ' + CNE.API_TOKEN
    
      req = https.request opts, (res) -> 
        console.log(res.statusCode) if res.statusCode isnt 200
        body = ''
        res.on 'data', (chunk) -> body += chunk
        res.on 'end', () -> 
          try
            body = JSON.parse body
            try console.log (body.result.name ? body.result.id) + ' ' + (if body.success then 'success' else 'error')
            console.log(e.message) for e in body.errors
      req.on 'error', (err) -> console.log err
      req.write data
      req.end()

_exec = (cmd) ->
  return new Promise (d) ->
    exec cmd, (e, s) ->
      if e
        console.log e
        return
      d s

_walk = (drt, names=[]) ->
  # list all files in a dir, including subdirs, sorted alpbabetically / hierarchically
  dirs = []
  for n in fs.readdirSync(drt).sort()
    if n.indexOf('.') is -1 or n.split('.').pop() in ['js', 'coffee', 'json', 'css']
      if fs.lstatSync(drt + '/' + n).isDirectory()
        dirs.push drt + '/' + n
      else
        names.push drt  + '/' + n
  names = _walk(d, names) for d in dirs
  return names

_w = () ->
  # add checks for things that need to be installed? could be handy
  #console.log await _exec 'which google-chrome'

  wfl = ''
  sfl = ''
  if 'build' in args
    if 'worker' in args or 'server' in args
      console.log "Building worker" + (if 'worker' in args then '' else ' (necessary for compilation into server)')
      if fs.existsSync './worker/dist'
        try fs.unlinkSync './worker/dist/worker.js'
      else
        fs.mkdirSync './worker/dist'
      console.log await _exec 'cd ./worker && npm install'
      for fl in await _walk './worker/src'
        console.log fl
        if fl.endsWith '.coffee'
          wfl += coffee.compile fs.readFileSync(fl).toString(), bare: true
        else if fl.endsWith '.js'
          wfl += fs.readFileSync(fl).toString()
        wfl += '\n'
      wfl += '\nS.built = \"' + DATE + '\";'
      wfl += '\nS.demo = true;' if DEMO
      VERSION = wfl.split('S.version = ')[1].split('\n')[0].split('//')[0].replace(/"/g, '').replace(/'/g, '').replace(';','').trim()
      if VERSION
        if fs.existsSync './worker/package.json'
          wp = JSON.parse fs.readFileSync('./worker/package.json').toString()
          wp.version = VERSION
          fs.writeFileSync './worker/package.json', JSON.stringify wp, '', 2
        if fs.existsSync './server/package.json'
          sp = JSON.parse fs.readFileSync('./server/package.json').toString()
          sp.version = VERSION
          fs.writeFileSync './server/package.json', JSON.stringify sp, '', 2

    if 'server' in args
      console.log "Building server"
      if not wfl.length
        if fs.existsSync './worker/dist/worker.js'
          wfl = fs.readFileSync('./worker/dist/worker.js').toString()
        else
          console.log 'Server build cannot complete until worker build has run at least once, making ./worker/dist/worker.js available for incorporation'
          process.exit()
      sfl = wfl
      if fs.existsSync './server/dist'
        try fs.unlinkSync './server/dist/server.js'
      else
        fs.mkdirSync './server/dist'
      console.log await _exec 'cd server && npm install'
      for fl in await _walk './server/src'
        console.log fl
        if fl.endsWith '.coffee'
          sfl += coffee.compile fs.readFileSync(fl).toString(), bare: true
        else if fl.endsWith '.js'
          sfl += fs.readFileSync(fl).toString()
        sfl += '\n'
      if wfl
        adds = []
        for line in sfl.split '\n'
          if line.startsWith('P.') and (line.indexOf('function') isnt -1 or line.replace(/\s/g, '').indexOf('={') isnt -1 or line.indexOf('._') isnt -1) and line.indexOf('->') is -1 # avoid commented out coffeescript definitions, by the time they're converted to js these would not be defined with -> functions
            bgp = line.split('=')[0].split('._')[0].replace(/\s/g, '')
            if wfl.indexOf('\n' + bgp) is -1 or bgp in adds
              adds.push(bgp) if bgp not in adds
              if line.indexOf('function') is -1
                console.log 'adding ' + line + ' to worker stub'
                wfl += '\n' + line + '// added by constructor\n'
              else
                console.log 'adding ' + bgp + ' bg stub to worker'
                wfl += '\n' + bgp + ' = {_bg: true}' + '// added by constructor\n'

  if 'client' in args
    # TODO add a browser build of the main app too, at least all parts that can run browser-side
    console.log "Building client files"
    for fl in await _walk './client'
      if fl.endsWith '.coffee'
        console.log fl
        cpl = coffee.compile fs.readFileSync(fl).toString(), bare: true
        fs.writeFileSync fl.replace('.coffee', '.js'), cpl
        try
          uglifyjs = require 'uglify-js'
          uglyjs = uglifyjs.minify flj: cpl
          fs.writeFileSync fl.replace('.coffee', '.min.js'), uglyjs.code
          # this can also be used to build bundles, given an object of filenames and their contents
          # secrets/construct.json could be extended to define bundle lists, if that becomes useful in future
          #jshashname = 'pradm_' + crypto.createHash('md5').update(uglyjs.code).digest('hex')
        catch
          console.log 'Could not minify - maybe uglify-js needs to be installed'
      else if fl.endsWith('.js') and not fl.endsWith('.min.js') and not fs.existsSync fl.replace '.js', '.coffee'
        try
          console.log fl
          uglifyjs = require 'uglify-js'
          uglyjs = uglifyjs.minify fl: cpl
          fs.writeFileSync fl.replace('.js', '.min.js'), uglyjs.code
        catch
          console.log 'Could not minify - maybe uglify-js needs to be installed'
      else if fl.endsWith('.css') and not fl.endsWith '.min.css'
        try
          console.log fl
          uglifycss = require 'uglifycss'
          uglycss = uglifycss.processFiles [fl] # this can also be used to bundle a list of filenames
          #csshashname = 'pradm_' + crypto.createHash('md5').update(uglycss).digest('hex')
          fs.writeFileSync fl.replace('.css', '.min.css'), uglycss
        catch
          console.log 'Could not minify - maybe uglifycss needs to be installed'

  if 'server' in args
    if fs.existsSync './server/' + GROUP + 'secrets'
      fls = fs.readdirSync './server/' + GROUP + 'secrets'
      if fls.length
        for F in fls
          # only use files prefixed with env if it is present, or the default files if no file for the env is available
          # don't use any that are prefixed for some other env - NOTE this means settings files MUST NOT have underscores in them except for when separating the env
          if ENV is '' or F.indexOf(ENV) is 0 or (F.indexOf('_') is -1 and not fs.existsSync './server/' + GROUP + 'secrets/' + ENV + F)
            SECRETS_DATA = JSON.parse fs.readFileSync('./server/' + GROUP + 'secrets/' + F).toString()
            SECRETS_NAME = 'SECRETS_' + F.split('.')[0].toUpperCase().replace ENV + '_', ''
            console.log 'Saving server ' + SECRETS_NAME + ' to server file'
            # these are written to file as strings to be interpreted in the file, because that is how they'd 
            # have to be interpreted from CF workers secrets anyway - so no point handling strings sometimes 
            # and objects sometimes in the main code - just deliver these all as strings for parsing in the main.
            sfl = "var " + SECRETS_NAME + " = '" + JSON.stringify(SECRETS_DATA) + "';\n" + sfl
      else
        console.log "No server secrets json files present, so no extra server secrets built into server script\n"
    else
      console.log "No server secrets folder present so no extra server secrets built into server script\n"

  if fs.existsSync './worker/' + GROUP + 'secrets'
    wfls = fs.readdirSync './worker/' + GROUP + 'secrets'
    if wfls.length
      # TODO find necessary KV namespaces from the code / config and create them via cloudflare API?
      for WF in wfls
        if ENV is '' or WF.indexOf(ENV) is 0 or (WF.indexOf('_') is -1 and not fs.existsSync './worker/' + GROUP + 'secrets/' + ENV + WF)
          SECRETS_DATA = JSON.parse fs.readFileSync('./worker/' + GROUP + 'secrets/' + WF).toString()
          SECRETS_NAME = 'SECRETS_' + WF.split('.')[0].toUpperCase().replace ENV + '_', ''
          if (if WF.includes('_') then WF.split('_').pop() else WF).split('.')[0].toLowerCase() is 'settings' and not SECRETS_DATA.system
            console.log 'Adding system token', SYSTOKEN
            SECRETS_DATA.system = SYSTOKEN
          if 'worker' in args
            if 'secrets' in args
              if not CNS.length
                console.log "To push secrets to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in ./secrets/construct.json"
              else
                console.log 'Sending worker ' + SECRETS_NAME + ' secrets to cloudflare'
                _put {name: SECRETS_NAME, text: JSON.stringify(SECRETS_DATA)}
          if 'server' in args
            console.log 'Saving worker ' + SECRETS_NAME + ' to server file'
            sfl = "var " + SECRETS_NAME + " = '" + JSON.stringify(SECRETS_DATA) + "';\n" + sfl
    else
      console.log "No worker secrets json files present, so no worker secrets imported to cloudlfare or built into server script\n"
  else
    console.log "No worker secrets folder present, so no worker secrets imported to cloudflare or built into server script\n"

  if 'build' in args
    if 'worker' in args or 'server' in args # server needs worker to be built as well anyway
      fs.writeFileSync './worker/dist/worker.js', wfl
      await _exec 'cd ./worker && npm run build'
      console.log 'Worker file size ' + (fs.statSync('./worker/dist/worker.min.js').size)/1024 + 'K'
    if 'server' in args
      fs.writeFileSync './server/dist/server.js', sfl
      await _exec 'cd ./server && npm run build'

  if 'deploy' in args
    if 'worker' in args
      if fs.existsSync './worker/dist/worker.min.js'
        if not CNS.length
          console.log "To deploy worker to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in secrets/construct.json"
        else
          console.log "Deploying worker to cloudflare"
          _put fs.readFileSync('./worker/dist/worker.min.js').toString()
      else
        console.log "No worker file available to deploy to cloudflare at worker/dist/worker.min.js\n"
  
    if 'server' in args
      for CNE in CNS
        if CNE.SCP
          if fs.existsSync './server/dist/server.min.js'
            console.log "Deploying server to " + CNE.SCP + (if CNE.NAME then ' for ' + CNE.NAME else '')
            console.log await _exec 'scp ./server/dist/server.min.js ' + CNE.SCP
          else
            console.log "No server file available to deploy at server/dist/server.min.js\n"
            break

  if 'construct' in args
    # not done by default, and not mentioned. Unnecessary, because even if a js is constructed, it still needs coffee for the translation stage
    try fs.writeFileSync './construct.js', coffee.compile fs.readFileSync('./construct.coffee').toString(), bare: true

  if VERSION
    console.log 'v' + VERSION + ' built at ' + DATE

_w()



