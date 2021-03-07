
# deploy with environment choice? dev/live/other?
# need node and npm. If not present, this will fail

import fs from 'fs'
coffee = require 'coffeescript'
{exec} = require 'child_process'

args = process.argv.slice 2

if not args.length
  console.log "Doing default full deploy, which executes all options:"
  console.log "build - build one or both of worker and server"
  console.log "deploy - deploy one or both of worker and server"
  console.log "worker - build/deploy the worker (deploys to cloudflare if suitable env settings are available)"
  console.log "server - build/deploy the server (deploys to remote server if suitable env settings are available)"
  console.log "secrets - deploy secrets to cloudflare worker (secrets are automatically included in a server build anyway)\n"

_walk = (dir, rt='', names=[]) ->
  # list all files in a dir, including subdirs, sorted alpbabetically / hierarchically
  dirs = []
  for n in fs.readdirSync(dir).sort()
    if n.indexOf('.') is -1 or n.split('.').pop() in ['js', 'coffee', 'json']
      if fs.lstatSync(n).isDirectory()
        dirs.push rt + (if rt isnt '' then '/' else '') + n
      else
        names.push rt  + (if rt isnt '' then '/' else '') + n
  names = _walk(rt + (if rt isnt '' then '/' else '') + d, rt, names) for d in dirs
  return names

CF = {}
if 'deploy' in args and ('secrets' in args or 'worker' in args)
  if fs.existsSync './secrets/cf.json'
    CF = JSON.parse fs.readFileSync './secrets/cf.json'
  else
    console.log -e "No env file present in top level secrets folder, so no env variables loaded (unless manually set on terminal)\n"
else
  console.log "No top level secrets folder present, so no configuration secrets available."
  console.log "A folder called secrets should be placed at the top level directory / root of the project, and also one each in server/ and worker/"
  console.log "Anything in these folders will be ignored by any future git commits, so it is safe to put secret data in them."
  console.log "Deployment to cloudflare requires at least a secrets/cf.json file containing keys ACCOUNT_ID, SCRIPT_ID, API_TOKEN\n"

# NOTE only up to 32 cloudflare workers variables are allowed, a combined count of 
# secret variables and normal env variables (e.g. set via CF UI)
# each uploaded secret can only be up to 1KB in size
CF_URL = 'https://api.cloudflare.com/client/v4/accounts/' + CF.ACCOUNT_ID + '/workers/scripts/' + CF.SCRIPT_ID

DATE = new Date().toString().split(' (')[0]

wfl = ''
if not args.length or 'build' in args
  if not args.length or 'worker' in args
    console.log "Building worker"
    if fs.existsSync './worker/dist'
      try
        fs.unlinkSync './worker/dist/worker.js'
    else
      fs.mkdirSync './worker/dist'
    exec 'cd worker && npm install'
    for fl in _walk './worker/src'
      if fl.endsWith '.coffee'
        wfl += coffee.compile fs.readFileSync(fl).toString()
      else
        wfl += fs.readFileSync(fl).toString()
      wfl += '\n'
    wfl += '\nS.built = \"' + DATE + '\"'
    fs.writeFileSync './worker/dist/worker.js', wfl
    exec 'cd worker && npm run build'

  if not args.length or 'server' in args
    console.log "Building server"
    if fs.existsSync './server/dist'
      try
        fs.unlinkSync './server/dist/server.js'
    else
      fs.mkdirSync './server/dist'
    exec 'cd server && npm install'
    for fl in _walk './server/src'
      if fl.endsWith '.coffee'
        wfl += coffee.compile fs.readFileSync(fl).toString()
      else
        wfl += fs.readFileSync(fl).toString()
      wfl += '\n'
      
if not args.length or 'server' in args
  if fs.existsSync './server/secrets'
    fls = fs.readdirSync './server/secrets'
    if fls.length
      for F in fls
        SECRETS_DATA = fs.readFileSync(F).toString()
        SECRETS_NAME = F.split('/').pop().split('.')[0].toUpperCase()
        console.log 'Saving server ' + SECRETS_NAME + ' secrets to server file'
        wfl = "var SECRETS_" + SECRETS_NAME + " = '" + SECRETS_DATA + "'\n" + wfl
    else
      console.log "No server secrets json files present, so no server secrets built into server script\n"
  else
    console.log "No server secrets folder present so no server secrets built into server script\n"

if fs.existsSync './worker/secrets'
  wfls = fs.readdirSync './worker/secrets'
  if wfls.length
    # TODO find necessary KV namespaces from the code / config and create them via cloudflare API?
    for WF in wfls
      SECRETS_DATA = fs.readFileSync(WF).toString()
      SECRETS_NAME = WF.split('/').pop().split('.')[0].toUpperCase()
      SECRETS_OBJECT = '{\"name\": \"SECRETS_' + SECRETS_NAME + '\", \"text\": \"' + SECRETS_DATA + '\"}'
      if not args.length or 'worker' in args
        if not args.length or 'secrets' in args
          if not CF.ACCOUNT_ID or not CF.API_TOKEN or not CF.SCRIPT_ID
            console.log "To push secrets to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in secrets/cf.json"
          else
            console.log 'Sending ' + SECRETS_NAME + ' secrets to cloudflare'
            exec 'curl -X PUT "' + CF_URL + '/secrets" -H "Authorization: Bearer ' + CF.API_TOKEN + '" -H "Content-Type: application/javascript" --data "' + SECRETS_OBJECT + '" | grep \"success\"'
      if not args.length or 'server' in args
        console.log 'Saving worker ' + SECRETS_NAME + ' secrets to server file'
        wfl = "var SECRETS_" + SECRETS_NAME + " = '" + SECRETS_DATA + "'\n" + wfl
  else
    console.log "No worker secrets json files present, so no worker secrets imported to cloudlfare or built into server script\n"
else
  console.log "No worker secrets folder present, so no worker secrets imported to cloudflare or built into server script\n"

if not args.length or 'build' in args
  if not args.length or 'server' in args
    fs.writeFileSync './server/dist/server.js', wfl
    exec 'cd server && npm run build'

if not args.length or 'deploy' in args
  if not args.length or 'worker' in args
    if fs.existsSync './worker/dist/worker.min.js'
      if not CF.ACCOUNT_ID or not CF.API_TOKEN or not CF.SCRIPT_ID
        console.log "To deploy worker to cloudflare, cloudflare account ID, API token, and script ID must be set to vars CF_ACCOUNT_ID, CF_API_TOKEN, CF_SCRIPT_ID, in secrets/env or directly on command line"
      else
        console.log "Deploying worker to cloudflare"
        exec 'curl -X PUT "' + CF_URL + '" -H "Authorization: Bearer ' + CF.API_TOKEN + '" -H "Content-Type: application/javascript" --data-binary "@worker/dist/worker.min.js" | grep -e \"success\" -e \"message\"'
    else
      console.log "No worker file available to deploy to cloudflare at worker/dist/worker.min.js\n"

  if not args.length or 'server' in args
    if fs.existsSync './server/dist/server.min.js'
      console.log "TODO Server deploy to backend server will occur here if there is an env var to ssh it to - or could do that via git hooks"
    else
      console.log "No server file available to deploy to backend at server/dist/server.min.js\n"

try
  VERSION = wfl.split('S.version ?="')[1].split('"')[0]
catch
  VERSION = 'UNKNOWN'
console.log 'v' + VERSION + ' built at ' + DATE