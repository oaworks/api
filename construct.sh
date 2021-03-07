
# deploy with environment choice? dev/live/other?

# need node and npm. If not present, prompt user to apt install nodejs npm, or just try it?
# at least coffeesript and webpack are also required, but this script runs npm install in the 
# worker and server dirs which should provide them as necessary

if [ $# -eq 0 ]; then
  echo "Doing default full deploy, which executes all options:"
  echo "build - build one or both of worker and server"
  echo "deploy - deploy one or both of worker and server"
  echo "worker - build/deploy the worker (deploys to cloudflare if suitable env settings are available)"
  echo "server - build/deploy the server (deploys to remote server if suitable env settings are available)"
  echo -e "secrets - deploy secrets to cloudflare worker (secrets are automatically included in a server build anyway)\n"
fi

if [ -d "secrets" ]; then
  if test -f ./secrets/env; then
    export $(grep -v '^#' "./secrets/env" | xargs)
  else
    echo -e "No env file present in top level secrets folder, so no env variables loaded (unless manually set on terminal)\n"
  fi
else
  echo "No top level secrets folder present, so not configuration secrets available."
  echo "A folder called secrets should be placed at the top level directory / root of the project, and also one each in server/ and worker/"
  echo "Anything in these folders will be ignored by any future git commits, so it is safe to put secret data in them."
  echo -e "Deployment to cloudflare requires at least a secrets/env file containing CF_ACCOUNT_ID, CF_SCRIPT_ID, CF_API_TOKEN\n"
fi

DATE=`date`

if [ $# -eq 0 ] || [[ $@ == *"build"* ]]; then
  if [ $# -eq 0 ] || [[ $@ == *"worker"* ]]; then
    echo "Building worker"
    cd worker
    if [ -d "dist" ]; then
      rm dist/worker.coffee
      rm dist/worker.js
    else
      mkdir dist
    fi
    npm install
    #find src/ -name '*.coffee' -exec cat {} \; > dist/worker.coffee
    find src/ -name '*.coffee' | sort -k11 | while IFS= read -r filename; do cat "$filename" >> dist/worker.coffee; done
    BUILT="\n\nS.built = \"$DATE\""
    echo -e $BUILT >> dist/worker.coffee
    coffee -c dist/worker.coffee
    npm run build
    cd ../
  fi

  if [ $# -eq 0 ] || [[ $@ == *"server"* ]]; then
    echo "Building server"
    cd server
    if [ -d "dist" ]; then
      rm dist/server.coffee
      rm dist/server.js
    else
      mkdir dist
    fi
    npm install
    #find src/ -name '*.coffee' -exec cat {} \; > dist/server.coffee
    find src/ -name '*.coffee' | sort -k11 | while IFS= read -r filename; do cat "$filename" >> dist/server.coffee; done
    coffee -c dist/server.coffee
    cat ../worker/dist/worker.js dist/server.js > $$.tmp && mv $$.tmp dist/server.js
    cd ../
  fi
fi

if [ $# -eq 0 ] || [[ $@ == *"server"* ]]; then
  if [ -d "server/secrets" ]; then
    if find server/secrets -mindepth 1 | read; then
      for F in server/secrets/*.json; do
        SECRETS_DATA="$(cat $F | sed 's/\"/\\"/g' | tr '\n' ' ')"
        SECRETS_NAME=${F#"server/secrets/"}
        SECRETS_NAME=${SECRETS_NAME%".json"}
        SECRETS_NAME=${SECRETS_NAME%"secrets"}
        SECRETS_NAME=${SECRETS_NAME^^}
        if [[ $SECRETS_NAME != "env" ]]; then # not really needed but just in case someone accidentally puts their env in env.json instead of just env
          echo "Saving server $SECRETS_NAME secrets to server file"
          echo "var SECRETS_$SECRETS_NAME = '$SECRETS_DATA'" | cat - server/dist/server.js > $$.tmp && mv $$.tmp server/dist/server.js
          #echo "var SECRETS_$SECRETS_NAME = '$SECRETS_DATA'" >> server/dist/server.js
        fi
      done
    else
      echo -e "No server secrets json files present, so no server secrets built into server script\n"
    fi
  else
    echo -e "No server secrets folder present so no server secrets built into server script"\n
  fi
fi

# NOTE only up to 32 cloudflare workers variables are allowed, a combined count of 
# secret variables and normal env variables (e.g. set via CF UI)
# each uploaded secret can only be up to 1KB in size
CF_URL="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$CF_SCRIPT_ID"
CF_SECRETS_URL="$CF_URL/secrets"

if [ -d "worker/secrets" ]; then
  if find worker/secrets -mindepth 1 | read; then
    # TODO find necessary KV namespaces from the code / config and create them via cloudflare API?
    for F in worker/secrets/*.json; do
      SECRETS_DATA="$(cat $F | sed 's/\"/\\"/g' | tr '\n' ' ')"
      SECRETS_NAME=${F#"worker/secrets/"}
      SECRETS_NAME=${SECRETS_NAME%".json"}
      SECRETS_NAME=${SECRETS_NAME%"secrets"}
      SECRETS_NAME=${SECRETS_NAME^^}
      if [[ $SECRETS_NAME != "env" ]]; then # not really needed but just in case someone accidentally puts their env in env.json instead of just env
        SECRETS_OBJECT="{\"name\": \"SECRETS_$SECRETS_NAME\", \"text\": \"$SECRETS_DATA\"}"
        if [ $# -eq 0 ] || [[ $@ == *"worker"* ]]; then
          if [ $# -eq 0 ] || [[ $@ == *"secrets"* ]]; then
            if [ -z "$CF_ACCOUNT_ID" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$CF_SCRIPT_ID" ]; then
              echo "To push secrets to cloudflare, cloudflare account ID, API token, and script ID must be set to vars CF_ACCOUNT_ID, CF_API_TOKEN, CF_SCRIPT_ID, in secrets/env or directly on command line"
            else
              echo "Sending $SECRETS_NAME secrets to cloudflare"
              curl -X PUT "$CF_SECRETS_URL" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/javascript" --data "$SECRETS_OBJECT" | grep \"success\"
            fi
          fi
        fi
        if [ $# -eq 0 ] || [[ $@ == *"server"* ]]; then
          echo "Saving worker $SECRETS_NAME secrets to server file"
          echo "var SECRETS_$SECRETS_NAME = '$SECRETS_DATA'" | cat - server/dist/server.js > $$.tmp && mv $$.tmp server/dist/server.js
        fi
      fi
    done
  else
    echo -e "No worker secrets json files present, so no worker secrets imported to cloudlfare or built into server script\n"
  fi
else
  echo -e "No worker secrets folder present, so no worker secrets imported to cloudflare or built into server script"\n
fi

if [ $# -eq 0 ] || [[ $@ == *"build"* ]]; then
  if [ $# -eq 0 ] || [[ $@ == *"server"* ]]; then
    cd server
    npm run build
    cd ../
  fi
fi

if [ $# -eq 0 ] || [[ $@ == *"deploy"* ]]; then
  if [ $# -eq 0 ] || [[ $@ == *"worker"* ]]; then
    if test -f ./worker/dist/worker.min.js; then
      if [ -z "$CF_ACCOUNT_ID" ] || [ -z "$CF_API_TOKEN" ] || [ -z "$CF_SCRIPT_ID" ]; then
        echo "To deploy worker to cloudflare, cloudflare account ID, API token, and script ID must be set to vars CF_ACCOUNT_ID, CF_API_TOKEN, CF_SCRIPT_ID, in secrets/env or directly on command line"
      else
        echo "Deploying worker to cloudflare"
        curl -X PUT "$CF_URL" -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/javascript" --data-binary "@worker/dist/worker.min.js" | grep -e \"success\" -e \"message\"
      fi
    else
      echo -e "No worker file available to deploy to cloudflare at worker/dist/worker.min.js\n"
    fi
  fi

  if [ $# -eq 0 ] || [[ $@ == *"server"* ]]; then
    if test -f ./server/dist/server.min.js; then
      echo "TODO Server deploy to backend server will occur here if there is an env var to ssh it to - or could do that via git hooks"
    else
      echo -e "No server file available to deploy to backend at server/dist/server.min.js\n"
    fi
  fi
fi

VERSION=`cat worker/src/api.coffee | grep "S.version ?="`
VERSION=${VERSION#"S.version ?= '"}
VERSION=${VERSION%"'"}
echo "v$VERSION built at $DATE"
