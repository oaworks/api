
# NOTE only up to 32 cloudflare workers variables are allowed, a combined count of 
# secret variables and normal variables (e.g. set via CF UI)
# each uploaded secret can only be up to 1KB in size

# need node and npm. If not present, this will fail

fs = require 'fs'
coffee = require 'coffeescript'
https = require 'https'
{exec} = require 'child_process'
crypto = require 'crypto'

KEEPTOKEN = true

args = process.argv.slice 2
rm = []
for a of args
  arg = args[a]
  console.log a, arg
  if arg.toLowerCase().indexOf('token') isnt -1
    rm.push a
    KEEPTOKEN = false
for r in rm
  delete args[r]
args = args.filter (el) -> return el isnt null

if not args.length
  args = ['build', 'deploy', 'worker', 'server', 'secrets']

DEMO = false
if not fs.existsSync('./secrets') and not fs.existsSync('./worker/secrets') and not fs.existsSync('./server/secrets')
  console.log "No settings or secrets available."
  console.log "A folder called secrets should be placed at the root of the project, and one each in server/ and worker/"
  console.log "Anything in these folders will be ignored by any future git commits, so it is safe to put secret data in them."
  DEMO = true

CNS = {}
if fs.existsSync './secrets/construct.json'
  CNS = JSON.parse fs.readFileSync('./secrets/construct.json').toString()
  CNS = CNS[0] if Array.isArray CNS
else
  console.log "Deployment to cloudflare requires a ./secrets/construct.json file containing an object with keys ACCOUNT_ID, SCRIPT_ID, API_TOKEN"

if KEEPTOKEN
  try
    SYSTOKEN = fs.readFileSync('./server/dist/server.js').toString().split('SECRETS_SETTINGS')[1].split('"system":"')[1].split('"')[0]
    console.log 'keeping system token', SYSTOKEN
  catch
    console.log 'could not find system token to keep, creating a new one'
    SYSTOKEN = crypto.randomBytes(32).toString 'hex'
else
  SYSTOKEN = crypto.randomBytes(32).toString 'hex'
DATE = new Date().toString().split(' (')[0]
VERSION = '' # get read from main worker file

_sr = (data, opts) ->
  return new Promise (resolve, reject) =>
    req = https.request opts, (res) =>
      if res.statusCode isnt 200
        console.log res.statusCode
      body = ''
      res.on 'data', (chunk) -> body += chunk
      res.on 'end', () -> 
        try body = JSON.parse body
        resolve body
    req.on 'error', (err) =>
      console.log 'SYNC PUT ERROR', err
      reject err
    req.write data
    req.end()

_put = (data) ->
  if typeof data isnt 'string'
    sn = data.name
    data = JSON.stringify data
    ps = '/secrets'
  else
    sn = ''
    ps = ''
  console.log 'Sending ' + (if sn then sn + ' ' else '') + 'for ' + CNS.SCRIPT_ID + (if CNS.NAME then ' on ' + CNS.NAME else '')
  if CNS.ACCOUNT_ID and CNS.SCRIPT_ID and CNS.API_TOKEN
    # data is either an object to send to secrets, or a file handle to stream to worker
    ret = await _sr data, 
      hostname: 'api.cloudflare.com'
      port: 443
      path: '/client/v4/accounts/' + CNS.ACCOUNT_ID + '/workers/scripts/' + CNS.SCRIPT_ID + ps
      method: 'PUT'
      headers:
        'Content-Type': if ps then 'application/json' else 'application/javascript'
        'Authorization': 'Bearer ' + CNS.API_TOKEN
    try console.log('ERROR', e.code, e.message) for e in ret.errors
    try console.log (ret?.success ? 'false'), CNS.SCRIPT_ID, CNS.NAME, sn
    console.log '------'

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

  if 'server' in args
    if fs.existsSync './server/secrets'
      fls = fs.readdirSync './server/secrets'
      if fls.length
        for F in fls
          SECRETS_DATA = JSON.parse fs.readFileSync('./server/secrets/' + F).toString()
          SECRETS_NAME = 'SECRETS_' + F.split('.')[0].toUpperCase()
          console.log 'Saving server ' + SECRETS_NAME + ' to server file'
          # these are written to file as strings to be interpreted in the file, because that is how they'd 
          # have to be interpreted from CF workers secrets anyway - so no point handling strings sometimes 
          # and objects sometimes in the main code - just deliver these all as strings for parsing in the main.
          sfl = "var " + SECRETS_NAME + " = '" + JSON.stringify(SECRETS_DATA) + "';\n" + sfl
      else
        console.log "No server secrets json files present, so no extra server secrets built into server script\n"
    else
      console.log "No server secrets folder present so no extra server secrets built into server script\n"

  if 'worker' in args or 'server' in args
    if fs.existsSync './worker/secrets'
      wfls = fs.readdirSync './worker/secrets'
      if wfls.length
        for WF in wfls
          SECRETS_DATA = JSON.parse fs.readFileSync('./worker/secrets/' + WF).toString()
          SECRETS_NAME = 'SECRETS_' + WF.split('.')[0].toUpperCase()
          if (if WF.includes('_') then WF.split('_').pop() else WF).split('.')[0].toLowerCase() is 'settings' and not SECRETS_DATA.system
            console.log 'Adding system token', SYSTOKEN
            SECRETS_DATA.system = SYSTOKEN
          if 'worker' in args
            if 'secrets' in args
              if not CNS.API_TOKEN
                console.log "To push secrets to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in ./secrets/construct.json"
              else
                console.log 'Sending worker ' + SECRETS_NAME + ' secrets to cloudflare'
                await _put {name: SECRETS_NAME, text: JSON.stringify(SECRETS_DATA), type: 'secret_text'}
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
      try fs.unlinkSync './worker/dist/worker.min.js.LICENSE.txt' #webpack adds this file, but it's not needed
      console.log 'Worker file size ' + (fs.statSync('./worker/dist/worker.min.js').size)/1024 + 'K'
    if 'server' in args
      fs.writeFileSync './server/dist/server.js', sfl
      try fs.unlinkSync './server/dist/server.min.js.LICENSE.txt' #webpack adds this file, but it's not needed
      await _exec 'cd ./server && npm run build'

  if 'deploy' in args
    if 'worker' in args
      if fs.existsSync './worker/dist/worker.min.js'
        if not CNS.API_TOKEN
          console.log "To deploy worker to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in secrets/construct.json"
        else
          console.log "Deploying worker to cloudflare"
          await _put fs.readFileSync('./worker/dist/worker.min.js').toString()
      else
        console.log "No worker file available to deploy to cloudflare at worker/dist/worker.min.js\n"
  
  if VERSION
    console.log 'v' + VERSION + ' built at ' + DATE

_w()



