  // NOTE only up to 32 cloudflare workers variables are allowed, a combined count of 
  // secret variables and normal env variables (e.g. set via CF UI)
  // each uploaded secret can only be up to 1KB in size

  // deploy with environment choice? dev/live/other?
  // need node and npm. If not present, this will fail
var CF, DATE, _exec, _put, _w, _walk, args, coffee, exec, fs, https,
  indexOf = [].indexOf;

fs = require('fs');

coffee = require('coffeescript');

https = require('https');

({exec} = require('child_process'));

args = process.argv.slice(2);

if (!args.length) {
  console.log("Doing default full deploy, which executes all options:");
  console.log("build - build one or both of worker and server");
  console.log("deploy - deploy one or both of worker and server");
  console.log("worker - build/deploy the worker (deploys to cloudflare if suitable env settings are available)");
  console.log("server - build/deploy the server (deploys to remote server if suitable env settings are available)");
  console.log("secrets - deploy secrets to cloudflare worker (secrets are automatically included in a server build anyway)\n");
}

DATE = new Date().toString().split(' (')[0];

CF = {};

if (!args.length || (indexOf.call(args, 'deploy') >= 0 && (indexOf.call(args, 'secrets') >= 0 || indexOf.call(args, 'worker') >= 0))) {
  if (fs.existsSync('./secrets/cf.json')) {
    CF = JSON.parse(fs.readFileSync('./secrets/cf.json').toString());
  } else {
    console.log("No cloudflare config loaded.");
    console.log("A folder called secrets should be placed at the top level directory / root of the project, and also one each in server/ and worker/");
    console.log("Anything in these folders will be ignored by any future git commits, so it is safe to put secret data in them.");
    console.log("Deployment to cloudflare requires at least a secrets/cf.json file containing an object with keys ACCOUNT_ID, SCRIPT_ID, API_TOKEN");
  }
}

_put = function(data) {
  var opts, path, req;
  // data is either an object to send to secrets, or a file handle to stream to worker
  path = '/client/v4/accounts/' + CF.ACCOUNT_ID + '/workers/scripts/' + CF.SCRIPT_ID;
  if (typeof data !== 'string') {
    data = JSON.stringify(data);
    path += '/secrets';
  }
  opts = {
    hostname: 'api.cloudflare.com',
    port: 443,
    path: path,
    method: 'PUT',
    headers: {
      'Content-Type': 'application/javascript',
      //'Content-Length': data.length
      'Authorization': 'Bearer ' + CF.API_TOKEN
    }
  };
  req = https.request(opts, function(res) {
    var body;
    if (res.statusCode !== 200) {
      console.log(res.statusCode);
    }
    body = '';
    res.on('data', function(chunk) {
      return body += chunk;
    });
    return res.on('end', function() {
      var e, i, len, ref, ref1, results;
      try {
        body = JSON.parse(body);
        try {
          console.log(((ref = body.result.name) != null ? ref : body.result.id) + ' ' + (body.success ? 'success' : 'error'));
        } catch (error) {}
        ref1 = body.errors;
        results = [];
        for (i = 0, len = ref1.length; i < len; i++) {
          e = ref1[i];
          results.push(console.log(e.message));
        }
        return results;
      } catch (error) {}
    });
  });
  req.on('error', function(err) {
    return console.log(err);
  });
  req.write(data);
  return req.end();
};

_exec = function(cmd) {
  return new Promise(function(d) {
    return exec(cmd, function(e, s) {
      if (e) {
        console.log(e);
        return;
      }
      return d(s);
    });
  });
};

_walk = function(drt, names = []) {
  var d, dirs, i, j, len, len1, n, ref, ref1;
  // list all files in a dir, including subdirs, sorted alpbabetically / hierarchically
  dirs = [];
  ref = fs.readdirSync(drt).sort();
  for (i = 0, len = ref.length; i < len; i++) {
    n = ref[i];
    if (n.indexOf('.') === -1 || ((ref1 = n.split('.').pop()) === 'js' || ref1 === 'coffee' || ref1 === 'json')) {
      if (fs.lstatSync(drt + '/' + n).isDirectory()) {
        dirs.push(drt + '/' + n);
      } else {
        names.push(drt + '/' + n);
      }
    }
  }
  for (j = 0, len1 = dirs.length; j < len1; j++) {
    d = dirs[j];
    names = _walk(d, names);
  }
  return names;
};

_w = async function() {
  var F, SECRETS_DATA, SECRETS_NAME, VERSION, WF, fl, fls, i, j, k, l, len, len1, len2, len3, ref, ref1, wfl, wfls;
  wfl = '';
  if (!args.length || indexOf.call(args, 'build') >= 0) {
    if (!args.length || indexOf.call(args, 'worker') >= 0) {
      console.log("Building worker");
      if (fs.existsSync('./worker/dist')) {
        try {
          fs.unlinkSync('./worker/dist/worker.js');
        } catch (error) {}
      } else {
        fs.mkdirSync('./worker/dist');
      }
      console.log((await _exec('cd ./worker && npm install')));
      ref = (await _walk('./worker/src'));
      for (i = 0, len = ref.length; i < len; i++) {
        fl = ref[i];
        if (fl.endsWith('.coffee')) {
          wfl += coffee.compile(fs.readFileSync(fl).toString(), {
            bare: true
          });
        } else {
          wfl += fs.readFileSync(fl).toString();
        }
        wfl += '\n';
      }
      wfl += '\nS.built = \"' + DATE + '\";';
      fs.writeFileSync('./worker/dist/worker.js', wfl);
      await _exec('cd ./worker && npm run build');
    }
    if (!args.length || indexOf.call(args, 'server') >= 0) {
      console.log("Building server");
      if (fs.existsSync('./server/dist')) {
        try {
          fs.unlinkSync('./server/dist/server.js');
        } catch (error) {}
      } else {
        fs.mkdirSync('./server/dist');
      }
      console.log((await _exec('cd server && npm install')));
      ref1 = (await _walk('./server/src'));
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        fl = ref1[j];
        if (fl.endsWith('.coffee')) {
          wfl += coffee.compile(fs.readFileSync(fl).toString(), {
            bare: true
          });
        } else {
          wfl += fs.readFileSync(fl).toString();
        }
        wfl += '\n';
      }
    }
  }
  if (!args.length || indexOf.call(args, 'server') >= 0) {
    if (fs.existsSync('./server/secrets')) {
      fls = fs.readdirSync('./server/secrets');
      if (fls.length) {
        for (k = 0, len2 = fls.length; k < len2; k++) {
          F = fls[k];
          SECRETS_DATA = JSON.parse(fs.readFileSync('./server/secrets/' + F).toString());
          SECRETS_NAME = 'SECRETS_' + F.split('.')[0].toUpperCase();
          console.log('Saving server ' + SECRETS_NAME + ' to server file');
          // these are written to file as strings to be interpreted in the file, because that is how they'd 
          // have to be interpreted from CF workers secrets anyway - so no point handling strings sometimes 
          // and objects sometimes in the main code - just deliver these all as strings for parsing in the main.
          wfl = "var " + SECRETS_NAME + " = '" + JSON.stringify(SECRETS_DATA) + "';\n" + wfl;
        }
      } else {
        console.log("No server secrets json files present, so no server secrets built into server script\n");
      }
    } else {
      console.log("No server secrets folder present so no server secrets built into server script\n");
    }
  }
  if (fs.existsSync('./worker/secrets')) {
    wfls = fs.readdirSync('./worker/secrets');
    if (wfls.length) {
      // TODO find necessary KV namespaces from the code / config and create them via cloudflare API?
      for (l = 0, len3 = wfls.length; l < len3; l++) {
        WF = wfls[l];
        SECRETS_DATA = JSON.parse(fs.readFileSync('./worker/secrets/' + WF).toString());
        SECRETS_NAME = 'SECRETS_' + WF.split('.')[0].toUpperCase();
        if (!args.length || indexOf.call(args, 'worker') >= 0) {
          if (!args.length || indexOf.call(args, 'secrets') >= 0) {
            if (!CF.ACCOUNT_ID || !CF.API_TOKEN || !CF.SCRIPT_ID) {
              console.log("To push secrets to cloudflare, cloudflare account ID, API token, and script ID must be set to keys ACCOUNT_ID, API_TOKEN, SCRIPT_ID, in secrets/cf.json");
            } else {
              console.log('Sending worker ' + SECRETS_NAME + ' secrets to cloudflare');
              _put({
                name: SECRETS_NAME,
                text: "'" + JSON.stringify(SECRETS_DATA) + "'"
              }, true);
            }
          }
        }
        if (!args.length || indexOf.call(args, 'server') >= 0) {
          console.log('Saving worker ' + SECRETS_NAME + ' to server file');
          wfl = "var " + SECRETS_NAME + " = '" + JSON.stringify(SECRETS_DATA) + "';\n" + wfl;
        }
      }
    } else {
      console.log("No worker secrets json files present, so no worker secrets imported to cloudlfare or built into server script\n");
    }
  } else {
    console.log("No worker secrets folder present, so no worker secrets imported to cloudflare or built into server script\n");
  }
  if (!args.length || indexOf.call(args, 'build') >= 0) {
    if (!args.length || indexOf.call(args, 'server') >= 0) {
      fs.writeFileSync('./server/dist/server.js', wfl);
      await _exec('cd ./server && npm run build');
    }
  }
  if (!args.length || indexOf.call(args, 'deploy') >= 0) {
    if (!args.length || indexOf.call(args, 'worker') >= 0) {
      if (fs.existsSync('./worker/dist/worker.min.js')) {
        if (!CF.ACCOUNT_ID || !CF.API_TOKEN || !CF.SCRIPT_ID) {
          console.log("To deploy worker to cloudflare, cloudflare account ID, API token, and script ID must be set to vars CF_ACCOUNT_ID, CF_API_TOKEN, CF_SCRIPT_ID, in secrets/env or directly on command line");
        } else {
          console.log("Deploying worker to cloudflare");
          _put(fs.readFileSync('./worker/dist/worker.min.js').toString());
        }
      } else {
        console.log("No worker file available to deploy to cloudflare at worker/dist/worker.min.js\n");
      }
    }
    if (!args.length || indexOf.call(args, 'server') >= 0) {
      if (fs.existsSync('./server/dist/server.min.js')) {
        console.log("\nServer package ready to deploy - this should be configured separately e.g. via githooks or other CI/CD method");
        console.log("However for convenience if a key called scp is added to ./secrets/cf.json it will be used to scp the server file");
        console.log("scp should be a server URL and directory path, such as example.com:/home/username/myfolder");
        console.log("Note this currently requires a linux command line with scp available, and a valid publickey that will allow the scp to succeed\n");
        if (CF.scp) {
          console.log((await _exec('scp ./server/dist/server.min.js ' + CF.scp)));
        }
      }
    }
  }
  try {
    fs.writeFileSync('./construct.js', coffee.compile(fs.readFileSync('./construct.coffee').toString(), {
      bare: true
    }));
  } catch (error) {}
  VERSION = wfl.split('S.version = ')[1].split('\n')[0].replace(/"/g, '').replace(/'/g, '').replace(';', '').trim();
  return console.log('v' + VERSION + ' built at ' + DATE);
};

_w();
