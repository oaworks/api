  // global S and P are accessible anywhere, and all files are merged into one on build.
  // NOTE it IS possible for scripts to persist between cloudflare worker requests, but also not guaranteed or intentional
  // so can't rely on them being clean every time, nor rely on them for storing state. Hence every new fetch event builds its own @S and P onto the global
var P, S, SS, _schedule, _unique, k,
  indexOf = [].indexOf;

try {
  // from CF variable this will need parsed, so just default to passing them as strings and parsing them
  S = JSON.parse(SECRETS_SETTINGS);
} catch (error) {}

try {
  SS = JSON.parse(SECRETS_SERVER); // backend server can provide overrides in a server.json secrets file
  for (k in SS) {
    S[k] = SS[k];
  }
} catch (error) {}

if (S == null) {
  S = {};
}

if (S.name == null) {
  S.name = 'OA.Works'; // this would also be used as the default name for the KV store, if one was not set specifically, as below or in settings
}

if (S.kv == null) {
  S.kv = 'oaworks';
}

if (S.version == null) {
  S.version = '6.1.0'; // the construct script will use this to overwrite any version in the worker and server package.json files
}

// S.pass can be set to false if there is a bg URL but worker errors should NOT pass through on exception to it (otherwise they will by default)
S.pass = [
  'docs',
  'client',
  '.well-known' // if this is a list of strings, any route starting with these will throw error and pass back to bg (this would happen anyway with no function defined for them, but this avoids unnecessary processing)
];

if (S.dev == null) {
  S.dev = true;
}

try {
  if (process.env.name && process.env.name.endsWith('_async')) { // optional setting defining a URL to an async worker to pass requests to
    S.async = true;
  }
} catch (error) {}

try {
  if (process.env.name && process.env.name.endsWith('_loop')) { // additional setting defining a URL to pass async looped scheduled requests to
    S.async_loop = true;
  }
} catch (error) {}

try {
  if (process.env.name && process.env.name.endsWith('_schedule')) { // additional setting defining a URL to pass async scheduled requests to (including looped ones, if async_loop is not set)
    S.async_schedule = true;
  }
} catch (error) {}

if (S.headers == null) {
  S.headers = {
    'Access-Control-Allow-Methods': 'HEAD, GET, PUT, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control',
    'Permissions-Policy': 'interest-cohort=()'
  };
}

if (S.formats == null) {
  S.formats = [
    'html',
    'csv',
    'json' // formats to allow to check for
  ];
}

if (S.svc == null) {
  S.svc = {};
}

if (S.src == null) {
  S.src = {};
}

try {
  // check _auth, refuse if not appropriate
  // _auth - if true an authorised user is required. If a string or a list, an authorised user with that role is required. For empty list, cascade the url routes as groups. always try to find user even if auth is not required, so that user is optionally available
  // _auths can be used instead to cascade the _auth setting to everything below it

  // check cache unless _cache is false, set result from cache if matches
  // _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache)
  // _caches - can be used to cascade the cache setting to everything below it
  // NOTE _auth and _cache are ALWAYS checked first at the incoming request level, and NOT checked for subsequent called functions (fetch can also use cache internally)

  // if an _async param was provided, check the async index for a completed result
  // if found, delete it and save it to wherever it should be (if anywhere), just as if a normal result had been processed
  // return the result to the user (via usual caching, logging etc if appropriate)

  // otherwise check for args and/or params
  // if args has length, args have priority
  // otherwise go with params (or just pass through?)

  // _kv - if true store the result in CF workers KV, and check for it on new requests - like a cache, but global, with 1s eventual consistency whereas cache is regional
  // _kv gets checked prior to _index UNLESS there are args that appear to be a query
  // for _kv, args[0] has to be a string for a key, with no args[1] - otherwise pass through

  // _index - if true send the result to an index. Or can be an object of index initialisation settings, mappings, aliases
  // _key - optional which key, if not default _id, to use from a result object to save it as - along with the function route which will be derived if not provided
  // _prefix - if false, the index is not prefixed with the app/index name, so can be accessed by any running version. Otherwise, an index is only accessible to the app version with the matching prefix.
  // _sheet - if true get a sheet ID from settings for the given endpoint, if string then it is the sheet ID. If present it implies _index:true if _index is not set

  // _async - if true, don't wait for the result, just return _async:@rid. If bg is configured and _bg isn't false on the function, send to bg. Otherwise just continue it locally.
  // _bg - if true pass request to backend server e.g for things that are known will be long running
  // this can happen at the top level route or if it calls any function that falls back to bg, the whole query falls back

  // by this point, with nothing else available, run the process (by now either on bg or worker, whichever was appropriate)
  // if the response indicates an error, e.g. it is an object with a status: 404 or similar, return to the response
  // also do not save if a Response object is directly passed as result from the function (and don't send to _response either, just return it)

  // if a valid result is available, and wasn't already a record in kv or index, write the result to kv/index if configured to do so
  // otherwise result needs to have a _key or _id
  // cache the result unless _cache is false or it was an index creation or sheet load

  // log the request, and whether or not data was sent, and if a result was achieved, and other useful info
  addEventListener('fetch', function(event) {
    if (S.pass !== false) {
      event.passThroughOnException();
    }
    return event.respondWith(P.call(event));
  });
} catch (error) {}

_unique = {};

_schedule = {};

P = async function() {
  var _lp, asr, authd, base, base1, base2, base3, bd, cpk, ct, du, entry, fd, fn, hd, hk, i, j, kp, kpn, l, len, len1, len2, len3, name, o, pf, pk, pkn, pkp, pks, prs, qp, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref4, ref5, ref6, ref7, ref8, ref9, res, resp, rk, shn, si;
  // the context here is the fetch event
  this.started = Date.now(); // not strictly accurate in a workers environment, but handy nevertheless, used for comparison when logs are finally written
  try {
    
    // make @S settings object local to this fetch event
    // this header is defined later because the built date is added to the end of the file by the deploy script, so it's not known until now
    if ((base = S.headers)[name = 'x-' + S.name.toLowerCase()] == null) {
      base[name] = (S.version ? 'v' + S.version : '') + (S.built ? ' built ' + S.built : '');
    }
  } catch (error) {}
  this.S = JSON.parse(JSON.stringify(S));
  if (typeof this.waitUntil !== 'function') { // it will be on worker, but not on backend
    if ((this.S.bg == null) || typeof this.S.bg === 'string') { // or could there be other places there is no waitUntil, but we want to deploy there without it being in bg mode?
      this.S.bg = true;
    }
    if ((base1 = this.S).cache == null) {
      base1.cache = false;
    }
    this.waitUntil = function(fn) {
      return true; // just let it run
    };
  } else if (!this.S.kv) { // try setting a default key-value store reference on the worker
    // where will backend overwrite this to true? can this be set on the global S, and overwritten on backend?
    this.S.kv = this.S.name.replace(/\s/g, '');
    if (!global[this.S.kv]) {
      delete this.S.kv;
    }
  }
  // make @params @body, @headers, @cookie
  if (this.params == null) {
    this.params = {};
  }
  if ((this.request.url != null) && this.request.url.includes('?')) {
    pkp = '';
    ref = this.request.url.split('?')[1].split('&');
    for (i = 0, len = ref.length; i < len; i++) {
      qp = ref[i];
      //qp = await P.decode qp
      kp = qp.split('=');
      if (kp[0].length) { // avoid &&
        if (kp.length === 1 && pkp && (kp[0].startsWith(' ') || kp[0].includes('%'))) {
          this.params[pkp] += '&' + decodeURIComponent(kp[0]);
        } else {
          this.params[kp[0]] = kp.length === 1 ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'true' ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'false' ? false : qp.endsWith('=') ? true : kp[1];
          if (typeof this.params[kp[0]] === 'string' && this.params[kp[0]].replace(/[0-9]/g, '').length === 0 && (this.params[kp[0]] === '0' || !this.params[kp[0]].startsWith('0'))) {
            kpn = parseInt(this.params[kp[0]]);
            if (!isNaN(kpn)) {
              this.params[kp[0]] = kpn;
            }
          }
          if (typeof this.params[kp[0]] === 'string' && this.params[kp[0]].includes('%')) {
            try {
              this.params[kp[0]] = decodeURIComponent(this.params[kp[0]]);
            } catch (error) {}
          }
          if (typeof this.params[kp[0]] === 'string' && (this.params[kp[0]].startsWith('[') || this.params[kp[0]].startsWith('{'))) {
            try {
              this.params[kp[0]] = JSON.parse(this.params[kp[0]]);
            } catch (error) {}
          }
        }
        pkp = kp[0];
      }
    }
  }
  this.headers = {};
  try {
    ref1 = [...this.request.headers];
    // request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      hd = ref1[j];
      this.headers[hd[0].toLowerCase()] = hd[1];
    }
  } catch (error) {
    try {
    // backend server passes a normal object, so just use that if not set above
      for (hk in this.request.headers) {
        this.headers[hk.toLowerCase()] = this.request.headers[hk];
      }
    } catch (error) {}
  }
  if ((base2 = this.headers).ip == null) {
    base2.ip = (ref2 = this.headers['x-real-ip']) != null ? ref2 : this.headers['x-forwarded-for'];
  }
  ct = (ref3 = this.headers['content-type']) != null ? ref3 : '';
  if (this.S.bg === true) {
    if (this.request.body != null) {
      this.body = this.request.body;
    }
  } else if (ct.includes('/json')) {
    this.body = (await this.request.json());
  } else if (ct.includes('form')) { // NOTE below, multipart may need to go to bg if receiving a file to save
    // TODO consider checking for request.arrayBuffer() as file content not in a multipart.
    // and for multipart, check to see if there actually is a file
    // https://stackoverflow.com/questions/14872460/how-to-detect-a-file-upload-examining-the-http-message
    bd = {};
    fd = (await this.request.formData());
    for (entry in fd.entries()) {
      if (entry[0]) {
        if (bd[entry[0]] != null) {
          if (!Array.isArray(bd[entry[0]])) {
            bd[entry[0]] = [bd[entry[0]]];
          }
          bd[entry[0]].push(entry[1]);
        } else {
          bd[entry[0]] = entry[1];
        }
      }
    }
    if ((bd != null) && JSON.stringify(bd) !== '{}') {
      this.body = bd;
    }
  }
  if ((this.body == null) && ((ref4 = this.request.method) === 'POST' || ref4 === 'PUT' || ref4 === 'DELETE')) {
    try {
      // TODO get worker to hand off to bg if available, if receiving any sort of file
      bd = (await this.request.text()); // NOTE this will always be at least an empty string when request method isnt GET
    } catch (error) {}
    if (bd) {
      // can also do URL.createObjectURL @request.blob() here, but would that be useful? Or revert to bg?
      this.body = bd;
    }
  }
  try {
    if (typeof this.body === 'string' && (this.body.startsWith('{') || this.body.startsWith('['))) {
      this.body = JSON.parse(this.body);
    }
  } catch (error) {}
  if (typeof this.body === 'object' && !Array.isArray(this.body)) {
    for (qp in this.body) {
      if (qp) {
        if ((base3 = this.params)[qp] == null) {
          base3[qp] = this.body[qp];
        }
      }
    }
  }
  try {
    this.cookie = (ref5 = this.headers.Cookie) != null ? ref5 : this.headers.cookie;
  } catch (error) {}
  
  // set some request and user IDs / keys in @rid, @apikey, and @refresh
  this.rid = this.headers['x-' + this.S.name.toLowerCase() + '-rid'];
  try {
    if (this.rid == null) {
      this.rid = this.headers['cf-ray'];
    }
  } catch (error) {}
  if (this.rid == null) {
    this.rid = P.uid(); // @uid is not defined yet
  }
  try {
    this.apikey = (ref6 = (ref7 = this.headers['x-apikey']) != null ? ref7 : this.headers.apikey) != null ? ref6 : this.params.apikey;
  } catch (error) {}
  ref8 = ['x-apikey', 'apikey'];
  for (l = 0, len2 = ref8.length; l < len2; l++) {
    rk = ref8[l];
    if (this.headers[rk] != null) {
      delete this.headers[rk];
    }
    if (this.params[rk] != null) {
      delete this.params[rk];
    }
  }
  if (this.params.refresh) {
    this.refresh = this.params.refresh;
    delete this.params.refresh; // what to do about refresh getting into the cache key?
  }
  
  // set the @url, the @base, the @route, and the url route parts in @parts
  if (!this.request.url.startsWith('http://') && !this.request.url.startsWith('https://')) {
    // in case there's a url param with them as well, check if they're at the start
    // there's no base to the URL passed on the backend server, so here the @base isn't shifted from the parts list
    this.url = this.request.url.split('?')[0].replace(/^\//, '').replace(/\/$/, '');
    try {
      if (this.url.includes('%')) {
        du = decodeURIComponent(this.url);
      }
    } catch (error) {}
    this.parts = this.url.length ? (du != null ? du : this.url).split('/') : [];
    try {
      this.base = this.headers.host;
    } catch (error) {}
  } else {
    this.url = this.request.url.split('?')[0].replace(/\/$/, '').split('://')[1];
    try {
      if (this.url.includes('%')) {
        du = decodeURIComponent(this.url);
      }
    } catch (error) {}
    this.parts = (du != null ? du : this.url).split('/');
    this.base = this.parts.shift();
  }
  if (typeof this.headers.accept === 'string') {
    if (this.headers.accept.includes('/csv')) {
      this.format = 'csv';
    }
  }
  if (this.parts.length && this.parts[this.parts.length - 1].includes('.')) { // format specified in url takes precedence over header
    pf = this.parts[this.parts.length - 1].split('.').pop().toLowerCase();
    if (indexOf.call(this.S.formats, pf) >= 0) {
      this.format = pf;
      this.parts[this.parts.length - 1] = this.parts[this.parts.length - 1].replace('.' + pf, '');
    }
  }
  if (typeof this.S.bg === 'string' && Array.isArray(this.S.pass) && this.parts.length && (ref9 = this.parts[0], indexOf.call(this.S.pass, ref9) >= 0)) {
    throw new Error(); // send to backend to handle requests for anything that should be served from folders on disk
  }
  shn = 'x-' + this.S.name.toLowerCase() + '-system';
  if (this.S.name && this.S.system && this.headers[shn] === this.S.system) {
    delete this.headers[shn];
    this.system = true;
  }
  this._logs = []; // place for a running request to dump multiple logs, which will combine and save at the end of the overall request
  this.route = this.parts.join('/');
  this.routes = [];
  this.fn = ''; // the function name that was mapped to by the URL routes in the request will be stored here
  if (this.route === '') { // don't bother doing anything, just serve a direct P._response with the API details
    if ((ref10 = this.request.method) === 'HEAD' || ref10 === 'OPTIONS') {
      return P._response.call(this, '');
    } else {
      return P._response.call(this, {
        name: (ref11 = this.S.name) != null ? ref11 : 'OA.Works API',
        version: this.S.version,
        base: (this.S.dev ? this.base : void 0),
        built: this.S.built,
        user: (ref12 = (ref13 = this.user) != null ? ref13.email : void 0) != null ? ref12 : void 0
      });
    }
  }
  // loop through everything defined on P, wrap and configure all functions, and set them onto @ so they can be called in relation to this fetch event
  // also pick up any URL params provided along the way - anything that doesn't map to a function or an object is considered some sort of param
  // params will be added to @params, keyed to whatever the most recent URL part that DID map to a function was
  // so for example /svc/oaworks/find maps to svc.oaworks.find, and /svc/oaworks/find/10.1234/567890 ALSO maps to it, 
  // and puts the remainder of the route (which is a DOI) into @params.find, so the find function can read it from there
  fn = void 0; // the actual function to run, once it's found (not just the name of it, which is put in @fn)
  prs = [...this.parts];
  pk = void 0;
  pks = [];
  _lp = async(p, a, n, auths, caches) => {
    var base10, base11, base4, base5, base6, base7, base8, base9, ik, len3, lpd, nd, o, ref14, ref15, ref16, results, sfn, uk;
    if (pk && this.fn.startsWith(n)) {
      while (prs.length && (p[prs[0]] == null)) {
        this.params[pk] = (this.params[pk] ? this.params[pk] + '/' : '') + prs.shift();
        if (indexOf.call(pks, pk) < 0) {
          pks.push(pk);
        }
      }
    }
    results = [];
    for (k in p) {
      if ((ref14 = typeof p[k]) !== 'function' && ref14 !== 'object') {
        results.push(a[k] = p[k]);
      } else if (p[k] != null) {
        nd = n + (n ? '.' : '') + k;
        if (typeof p[k] === 'object' && !p[k]._index && !p[k]._indexed && !p[k]._sheet && !p[k]._kv && !p[k]._bg) { // index, kv, or bg could be objects that need wrapped
          a[k] = JSON.parse(JSON.stringify(p[k]));
        } else {
          if ((base4 = p[k])._auth == null) {
            base4._auth = (base5 = p[k])._auths != null ? base5._auths : base5._auths = auths;
          }
          if (Array.isArray(p[k]._auths) && p[k]._auths.length === 0) { // an empty auth array defaults to group names corresponding to the function subroutes
            p[k]._auths = nd.split('.');
          }
          if (Array.isArray(p[k]._auth) && p[k]._auth.length === 0) { // an empty auth array defaults to group names corresponding to the function subroutes
            p[k]._auth = nd.split('.');
          }
          if ((base6 = p[k])._cache == null) {
            base6._cache = (base7 = p[k])._caches != null ? base7._caches : base7._caches = caches;
          }
          if (nd.startsWith('auth')) {
            if ((base8 = p[k])._cache == null) {
              base8._cache = false;
            }
          }
          if (p[k]._sheet) {
            if ((base9 = p[k])._index == null) {
              base9._index = true;
            }
          }
          if (p[k]._index) { // add index functions to index endpoints
            ref15 = ['keys', 'terms', 'suggest', 'count', 'percent', 'min', 'max', 'range', 'sum', 'average', 'mapping', '_for', '_each', '_bulk', '_refresh'];
            // of P.index
            for (o = 0, len3 = ref15.length; o < len3; o++) {
              ik = ref15[o];
              if ((base10 = p[k])[ik] == null) {
                base10[ik] = {
                  _indexed: ik,
                  _auth: (ik.startsWith('_') ? 'system' : p[k]._auth)
                };
              }
            }
          }
          if (typeof p[k] === 'function' && !p[k]._index && !p[k]._indexed && !p[k]._kv && !p[k]._bg && (!nd.includes('.') || n.startsWith('index') || nd.split('.').pop().startsWith('_'))) {
            a[k] = p[k].bind(this);
          } else {
            a[k] = P._wrapper(p[k], nd).bind(this);
          }
          for (uk in p[k]) {
            if (uk.startsWith('_')) {
              a[k][uk] = p[k][uk];
            }
          }
        }
        if ((base11 = a[k])._name == null) {
          base11._name = nd;
        }
        if (a[k]._schedule && !_schedule[nd] && this.S.bg === true && this.S.cron !== false) {
          console.log('Adding schedule', a[k]._schedule, nd);
          _schedule[nd] = {
            schedule: a[k]._schedule,
            fn: a[k]
          };
          sfn = (fnm) => {
            return async() => {
              var aru, crd, err, fno, lpd, ref16, ref17, ref18, ref19, ref20;
              fno = _schedule[fnm].fn;
              aru = (ref16 = this.S.async_runner) != null ? ref16[(ref17 = fno._runner) != null ? ref17 : fnm] : void 0;
              if (this.S.dev !== true && !this.S.async && !this.S.async_loop && !this.S.async_schedule && (process.env.pm_id != null) && ((ref18 = process.env.pm_id) !== 1 && ref18 !== '1')) {
                return console.log('NOT running scheduled task because not on dev and process pid is not 1', fnm, this.datetime());
              } else if (typeof aru !== 'string' && !this.S.async_schedule && typeof this.S.async === 'string') {
                return console.log('NOT running scheduled task because not on the available async process', fnm, this.datetime());
              } else if (typeof aru !== 'string' && typeof this.S.async_schedule === 'string' && (fno._schedule !== 'loop' || !this.S.async_loop)) {
                return console.log('NOT running scheduled task because not on the available async scheduled process', fnm, this.datetime());
              } else if (typeof aru !== 'string' && typeof this.S.async_loop === 'string' && fno._schedule === 'loop') {
                return console.log('NOT running scheduled looped task because not on the available loop process', fnm, this.datetime());
              } else if (typeof aru === 'string' && process.env.name && !process.env.name.endsWith(((ref19 = fno._runner) != null ? ref19 : fnm).replace(/\./g, '_'))) {
                return console.log('NOT running scheduled task because not on the specified process runner', (ref20 = fno._runner) != null ? ref20 : fnm, this.datetime());
              } else {
                console.log('scheduled task', fnm, this.datetime());
                _schedule[fnm].last = (await this.datetime());
                delete _schedule[fnm].error;
                try {
                  if (fno._sheet) {
                    crd = (await this._loadsheet(_schedule[fnm].fn, fno._name.replace(/\./g, '_')));
                  } else {
                    crd = (await _schedule[fnm].fn(fno._args)); // args can optionally be provided for the scheduled call
                  }
                  try {
                    _schedule[fnm].result = JSON.stringify(crd).substr(0, 200);
                  } catch (error) {}
                  _schedule[fnm].success = true;
                  console.log('scheduled task result', crd);
                  if (fno._schedule === 'loop') {
                    console.log('Schedule looping', fnm);
                    lpd = (await sfn(fnm));
                    return lpd();
                  }
                } catch (error) {
                  err = error;
                  _schedule[fnm].success = false;
                  try {
                    return _schedule[fnm].error = JSON.stringify(err);
                  } catch (error) {}
                }
              }
            };
          };
          if ((ref16 = a[k]._schedule) === 'loop' || ref16 === 'startup') {
            console.log('Starting scheduled', a[k]._schedule, nd);
            lpd = (await sfn(nd));
            lpd();
          } else {
            cron.schedule(a[k]._schedule, sfn(nd));
          }
        }
        if (!k.startsWith('_')) { // underscored methods cannot be accessed from URLs
          if (prs.length && prs[0] === k && this.fn.startsWith(n)) {
            pk = prs.shift();
            this.fn += (this.fn === '' ? '' : '.') + pk;
            if (typeof a[k] === 'function' && !n.includes('._')) { // URL routes can't call _abc functions or ones under them
              fn = a[k];
            }
          }
          if (typeof a[k] === 'function' && nd.replace('svc.', '').replace('src.', '').split('.').length === 1) { //and ((not nd.startsWith('svc') and not nd.startsWith('src')) or nd.split('.').length < 3)
            this.routes.push(nd.replace(/\./g, '/')); // TODO this could check the auth method, and only show things the current user can access, and also search for description / comment? NOTE this is just about visibility, they're still accessible if given right auth (if any)
          }
        }
        if (!Array.isArray(p[k]) && (!k.startsWith('_') || typeof a[k] === 'function')) {
          results.push(_lp(p[k], a[k], nd, auths != null ? auths : p[k]._auths, caches != null ? caches : p[k]._caches));
        } else {
          results.push(void 0);
        }
      } else {
        results.push(void 0);
      }
    }
    return results;
  };
  _lp(P, this, '');
  if (pk && prs.length) { // catch any remaining url params beyond the max depth of P
    this.params[pk] = this.params[pk] ? this.params[pk] + '/' + prs.join('/') : prs.join('/');
  }
// tidy any params provided within the URL
  for (o = 0, len3 = pks.length; o < len3; o++) {
    cpk = pks[o];
    if (this.params[cpk].toLowerCase() === 'true') {
      this.params[cpk] = true;
    }
    if (this.params[cpk].toLowerCase() === 'false') {
      this.params[cpk] = false;
    }
    if (typeof this.params[cpk] === 'string' && this.params[cpk].replace(/[0-9]/g, '').length === 0 && !this.params[cpk].startsWith('0')) {
      pkn = parseInt(this.params[cpk]);
      if (!isNaN(pkn)) {
        this.params[cpk] = pkn;
      }
    }
  }
  if (this.S.dev && this.S.bg === true) {
    console.log('=== ' + (this.system ? 'SYSTEM ' : '') + this.request.method + ' ===', this.base, this.fn, this.domain, typeof this.body);
  }
  if (((ref14 = typeof fn) === 'object' || ref14 === 'function') && fn._bg && typeof this.S.bg === 'string' && this.S.bg.startsWith('http')) {
    throw new Error();
  } else if (((ref15 = typeof fn) === 'object' || ref15 === 'function') && fn._async && typeof this.S.async === 'string' && (typeof ((ref16 = this.S.async_runner) != null ? ref16[(ref17 = fn._runner) != null ? ref17 : this.fn] : void 0) !== 'string' || !process.env.name || !process.env.name.endsWith(((ref18 = fn._runner) != null ? ref18 : this.fn).replace(/\./g, '_')))) {
    asr = (ref19 = (ref20 = this.S.async_runner) != null ? ref20[(ref21 = fn._runner) != null ? ref21 : this.fn] : void 0) != null ? ref19 : this.S.async;
    console.log('Fetching from async process', asr, this.request.url);
    res = (await this.fetch(asr + this.request.url, {
      method: this.request.method,
      headers: this.headers,
      body: this.request.body
    }));
  } else if (typeof fn === 'function') {
    authd = this.fn === 'auth' ? void 0 : (await this.auth());
    if (typeof authd === 'object' && authd._id && authd.email) {
      this.user = authd;
    }
    if (typeof fn._auth === 'function') {
      authd = (await fn._auth());
    } else if (fn._auth === true && (this.user != null)) { // just need a logged in user if true
      authd = true;
    } else if (fn._auth) { // which should be a string... comma-separated, or a list
      authd = (await this.auth.role(fn._auth)); // _auth should be true or name of required group.role
    } else {
      authd = true;
    }
    if (authd || this.system) {
      if ((ref22 = this.request.method) === 'HEAD' || ref22 === 'OPTIONS') {
        res = '';
      } else if (fn._cache !== false && !this.refresh && (this.request.method === 'GET' || (this.request.method === 'POST' && (await this.index.translate(this.params)))) && (res = (await this.cache()))) { // this will return empty if nothing relevant was ever put in there anyway
        // how about caching of responses to logged in users, by param or header?
        this.cached = 'cache';
        res = new Response(res.body, res); // no need to catch this for backend execution because cache function will never find anything on backend anyway
        res.headers.append('x-' + this.S.name.toLowerCase() + '-cached', 'cache'); // this would leave any prior "index" value, for example. Or use .set to overwrite
        res.headers.delete('x-' + this.S.name.toLowerCase() + '-took');
      } else {
        res = (await fn());
        this.completed = true;
      }
    } else {
      this.unauthorised = true;
      await this.sleep(200 * (1 + Math.random())); // https://en.wikipedia.org/wiki/Timing_attack
      res = {
        status: 401 // not authorised
      };
      res.body = (await this.auth(false)); // this returns an auth web page if the request appeared to come from a web browser (and not from js)
    }
  }
  if (((res == null) || (typeof res === 'object' && res.status === 404)) && this.url.replace('.ico', '').replace('.gif', '').replace('.png', '').endsWith('favicon')) {
    res = '';
  }
  resp = typeof res === 'object' && !Array.isArray(res) && typeof ((ref23 = res.headers) != null ? ref23.append : void 0) === 'function' ? res : (await this._response(res, fn));
  if (this.parts.length && ((ref24 = this.parts[0]) !== 'log' && ref24 !== 'status') && (!this.system || ((ref25 = this.parts[0]) !== 'kv' && ref25 !== 'index')) && ((ref26 = this.request.method) !== 'HEAD' && ref26 !== 'OPTIONS') && (res != null) && res !== '') {
    if (this.completed && fn._cache !== false && resp.status === 200 && (typeof res !== 'object' || Array.isArray(res) || ((ref27 = res.hits) != null ? ref27.total : void 0) !== 0) && (typeof res !== 'number' || !this.refresh)) {
      si = fn._cache; // fn._cache can be a number of seconds for cache to live, so pass it to cache to use if suitable
      if ((si == null) && typeof res === 'object' && !Array.isArray(res) && (((ref28 = res.hits) != null ? ref28.hits : void 0) != null)) { // if this is a search result, cache only 1 minute max if nothing else was set for it
        si = 60;
      }
      this.cache(void 0, resp, si);
    } else if (this.refresh) {
      this.cache(void 0, '');
    }
    if (((ref29 = typeof fn) === 'object' || ref29 === 'function') && fn._log !== false) {
      this.log();
    }
  }
  if (!this.completed && !this.cached && !this.unauthorised && this.S.pass !== false && typeof this.S.bg === 'string' && ((ref30 = this.request.method) !== 'HEAD' && ref30 !== 'OPTIONS')) {
    throw new Error(); // TODO check for functions that often timeout and set them to _bg by default
  } else {
    return resp;
  }
};

// build a suitable response object
// API above calls this to create a response, unless the result of the called function
// is already a suitable response (which itself could use this function, or manually 
// build a response if preferred/necessary)
P._response = async function(res, fn) {
  var ah, at, base, base1, base2, h, hdr, hh, i, j, keys, len, len1, m, ph, pt, ref, ref1, ref2, ref3, ret, rm, status, tt;
  if ((base = this.S).headers == null) {
    base.headers = {};
  }
  if (res == null) {
    res = 404;
    status = 404;
  } else if (this.fn !== 'status' && typeof res === 'object' && !Array.isArray(res) && ((typeof res.status === 'number' && res.status > 300 && res.status < 600) || res.headers)) {
    if (res.headers != null) {
      for (h in res.headers) {
        this.S.headers[h] = res.headers[h];
      }
      delete res.headers;
    }
    status = (ref = res.status) != null ? ref : 200;
    delete res.status;
    keys = this.keys(res);
    if (keys.length === 0) {
      res = status;
    } else if (keys.length === 1) { // if only one thing left, set the res to that. e.g. most likely body, content, json
      res = res[keys[0]];
    }
  } else {
    status = 200;
  }
  if (!this.S.headers['Content-Type'] && !this.S.headers['content-type']) {
    if (this.format && (ref1 = this.format, indexOf.call(this.S.formats, ref1) >= 0)) {
      if (typeof res !== 'string') {
        try {
          res = (await this.convert['json2' + this.format](res));
        } catch (error) {}
      }
      if (typeof res === 'string' && this.format === 'html') {
        res = res.replace(/\>\</g, '>\n<');
        if (!res.includes('<html') && !this.params.partial) {
          ret = '<!DOCTYPE html><html dir="ltr" lang="en">\n<head>\n';
          ret += '<meta charset="utf-8">\n<meta name="viewport" content="width=device-width, initial-scale=1.0">\n';
          if (res.includes('<title')) {
            [pt, tt] = res.split('<title');
            [tt, at] = tt.split('</title>');
            ret += '<title' + tt + '</title>\n';
            res = pt + at;
          } else if (res.includes('id="title"')) {
            ret += '<title>' + res.split('id="title"')[1].split('>')[1].split('<')[0] + '</title>\n';
          }
          ref2 = ['<meta ', '<link '];
          for (i = 0, len = ref2.length; i < len; i++) {
            hdr = ref2[i];
            if (res.includes(hdr)) {
              ref3 = res.split(hdr);
              for (j = 0, len1 = ref3.length; j < len1; j++) {
                m = ref3[j];
                rm = hdr + m.split('>')[0];
                res = res.replace(rm, '');
                ret += rm + '\n';
              }
            }
          }
          if (res.includes('<head>')) {
            [ph, hh] = res.split('<head>');
            [hh, ah] = hh.split('</head>');
            ret += hh;
            res = ph + ah;
          }
          if (!ret.includes('icon')) {
            ret += '<link rel="icon" href="data:,">';
          }
          ret += '\n</head>\n';
          ret += !res.includes('<body') ? '\n<body>\n' + res + '\n</body>\n' : res;
          res = ret + '\n</html>';
        }
      }
      this.S.headers['Content-Type'] = this.format === 'html' ? 'text/html; charset=UTF-8' : 'text/csv; charset=UTF-8';
    }
    if (typeof res !== 'string') {
      try {
        res = JSON.stringify(res, '', 2);
      } catch (error) {}
    }
    if ((base1 = this.S.headers)['Content-Type'] == null) {
      base1['Content-Type'] = 'application/json; charset=UTF-8';
    }
  }
  try {
    if ((base2 = this.S.headers)['Content-Length'] == null) {
      base2['Content-Length'] = Buffer.byteLength(res);
    }
  } catch (error) {}
  try {
    this.S.headers['x-' + this.S.name.toLowerCase() + '-took'] = Date.now() - this.started;
  } catch (error) {}
  try {
    if (this.cached) {
      this.S.headers['x-' + this.S.name.toLowerCase() + '-cached'] = this.cached;
    }
  } catch (error) {}
  try {
    if (this.S.bg === true) {
      return {
        status: status,
        headers: this.S.headers,
        body: res
      };
    } else {
      return new Response(res, {
        status: status,
        headers: this.S.headers
      });
    }
  } catch (error) {
    return {
      status: status,
      headers: this.S.headers,
      body: res
    };
  }
};

P._loadsheet = async function(f, rt) {
  var i, len, ref, ref1, sht, t;
  if (f._sheet.startsWith('http') && f._sheet.includes('csv')) {
    sht = (await this.convert.csv2json(f._sheet));
  } else if (f._sheet.startsWith('http') && f._sheet.includes('json')) {
    sht = (await this.fetch(f._sheet));
    if (sht && !Array.isArray(sht)) {
      sht = [sht];
    }
  } else {
    sht = (await this.src.google.sheets(f._sheet));
  }
  if (Array.isArray(sht) && sht.length) {
    if (typeof f._format === 'function') {
      sht = (await f._format.apply(this, [sht]));
    }
    if (f._key) {
      for (i = 0, len = sht.length; i < len; i++) {
        t = sht[i];
        if (t._id == null) {
          t._id = ((ref = t[f._key]) != null ? ref : this.uid()).replace(/\//g, '_').toLowerCase();
        }
      }
    }
    await this.index(rt, '');
    await this.index(rt, typeof f._index !== 'object' ? {} : {
      settings: f._index.settings,
      mappings: (ref1 = f._index.mappings) != null ? ref1 : f._index.mapping,
      aliases: f._index.aliases
    });
    await this.index(rt, sht);
    return sht.length;
  } else {
    return 0;
  }
};

// API calls this to wrap functions on P, apart from top level functions and ones 
// that start with _
// wrapper settings declared on each P function specify which wrap actions to apply
// _auth and _cache settings on a P function are handled by API BEFORE _wrapper is 
// used, so _auth and _cache are not handled within the wrapper
// the wrapper logs the function call (whether it was the main API call or subsequent)
P._wrapper = function(f, n) { // the function to wrap and the string name of the function
  return async function() {
    var _as, _makecsv, ak, args, base, bup, c, eurl, ex, exists, filecount, fl, flid, i, j, ks, l, len, len1, len2, len3, len4, lg, limited, nfeml, o, orgsidx, out, pfs, pidx, pok, prid, q, qrs, qry, rec, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, rt, started, tk, tot;
    started = Date.now(); // not accurate in a workers environment, but close enough
    rt = n.replace(/\./g, '_');
    lg = {
      fn: n
    };
    // _limit can be true, which stays in place until the function completes, or it can be a number which 
    // will be the lifespan of the limit record in the KV store
    // _limit
    if (f._limit) {
      limited = (await this.kv('limit/' + n));
      while (limited) {
        if (lg.limited == null) {
          lg.limited = 0;
        }
        lg.limited += limited;
        await this.sleep(limited - started);
        limited = (await this.kv('limit/' + n));
      }
    }
    // check for an _async param request and look to see if it is in the async finished store
    // if so, serve the result otherwise re-serve the param to indicate waiting should continue
    // _async
    if ((ref = typeof this.params._async) === 'string' || ref === 'number') {
      if (res = (await this.kv('async/' + this.params._async, ''))) {
        if (typeof res === 'string' && res.includes('/') && !res.includes(' ') && !res.includes(':') && !res.startsWith('10.') && res.split('/').length === 2) {
          try {
            if (f._kv) {
              res = (await this.kv(res));
            }
          } catch (error) {}
          try {
            if ((res == null) && f._index) { // async stored the _id for the result
              res = (await this.index(res));
            }
          } catch (error) {}
        }
        try {
          if (typeof res === 'string' && (res.startsWith('{') || res.startsWith('['))) {
            res = JSON.parse(res);
          }
        } catch (error) {}
      } else {
        res = {
          _async: this.params._async // user should keep waiting
        };
      }
    
    // serve the underlying sheet / csv link if configured and asked for it
    // _sheet
    } else if (this.fn === n && f._sheet && this.parts.indexOf('sheet') === this.parts.length - 1) {
      res = {
        status: 302
      };
      if (f._sheet.startsWith('http')) {
        res.body = f._sheet;
      } else if (this.format === 'json') { // TODO make it handle sheet and sheet ID in cases where both are provided
        //res.body = 'https://spreadsheets.google.com/feeds/list/' + f._sheet + '/' + 'default' + '/public/values?alt=json'
        res.body = 'https://sheets.googleapis.com/v4/spreadsheets/' + f._sheet.split('/')[0] + '/values/' + ((ref1 = (ref2 = f._sheetid) != null ? ref2 : f._sheet.split('/')[1]) != null ? ref1 : 'Sheet1') + '?alt=json';
      } else {
        res.body = 'https://docs.google.com/spreadsheets/d/' + f._sheet.split('/')[0];
      }
      res.headers = {
        Location: res.body
      };
    // a function with _index will be given child functions that call the default index child functions - if they're present, call them with the route specified
    } else if (f._indexed) {
      args = [...arguments];
      args.unshift(rt.replace('_' + f._indexed, ''));
      res = (await this.index[f._indexed](...args));
    
    // index / kv should first be checked if configured
    // for index, to create a new record with a specified ID, ONLY specify it as _id in the object as first argument and no second argument
    // updating / deleting can be done providing key in first argument and object / empty string in second argument
    // for kv, create can be done with ID string as first argument and record/value as second argument
    // _index, _kv
    } else if ((f._index || f._kv) && (!f._sheet || this.fn !== n || !this.refresh)) {
      if (this.fn === n) {
        if (this.fn.replace(/\./g, '/') !== this.route) { // action on a specific keyed record
          lg.key = this.route.split(n.split('.').pop()).pop().replace(/\//g, '_').replace(/^_/, '').replace(/_$/, '');
        }
        if (!lg.key && f._index) { //and not rec?
          qry = (await this.index.translate(this.request.method === 'POST' ? this.body : this.params));
        }
      // TODO who should be allowed to submit a record remotely?
      //rec = if @request.method is 'PUT' or (lg.key and @request.method is 'POST') then @body else if @request.method is 'DELETE' or @params._delete then '' else undefined
      // and if there is @params._delete, delete by query?
      } else if (arguments.length) { // could be a key string and record or could be a query and options (and query could look like a key)
        if (typeof arguments[0] === 'string' && arguments[0].length && !arguments[0].includes('\n') && arguments[0].length === arguments[0].replace(/[\s\*~\?="]/g, '').length) { // removed \: and % from regex to allow DOIs containing : as ID
          // could be key or query string - if query string is ambiguous, make it definitive by sending an object with q: 'query string'
          lg.key = arguments[0].replace(/\//g, '_').trim();
        }
        if (typeof arguments[0] === 'number') { // some indexes could use a number as an ID
          lg.key = arguments[0].toString();
        }
        if (f._index && !lg.key) { // check if it can be a query
          qry = (await this.index.translate(arguments[0], arguments[1]));
        }
        rec = qry != null ? void 0 : lg.key ? arguments[1] : f._index ? arguments[0] : void 0;
      }
      if (typeof rec === 'object') {
        if (!Array.isArray(rec)) {
          if (rec._id == null) {
            rec._id = ((ref3 = (ref4 = lg.key) != null ? ref4 : rec[f._key]) != null ? ref3 : this.uid()).replace(/\//g, '_').toLowerCase();
          }
          if (lg.key == null) {
            lg.key = rec._id.replace(/\//g, '_').toLowerCase();
          }
        } else if (rec.length) {
          for (i = 0, len = rec.length; i < len; i++) {
            c = rec[i];
            if (c._id == null) {
              c._id = ((ref5 = c[f._key]) != null ? ref5 : this.uid()).replace(/\//g, '_').toLowerCase();
            }
          }
        }
      }
      //console.log(n, lg.key, JSON.stringify(rec), JSON.stringify(qry), res, @refresh, typeof f, exists) if @S.dev and @S.bg is true
      if ((rec != null) || !this.refresh || typeof f !== 'function') {
        if (f._kv && lg.key) {
          res = (await this.kv(rt + '/' + lg.key, rec)); // there may or may not be a rec, as it could just be getting the keyed record
          if ((res != null) && (rec == null)) {
            lg.cached = 'kv';
          }
        }
        if (f._index) {
          if (this.params.size === 'all') {
            if (this.S.bg !== true) {
              if (typeof this.S.bg === 'string') {
                throw new Error(); // trip out to backend
              } else {
                res = {
                  status: 404
                };
              }
            }
            nfeml = this.params.email;
            if (this.params.orgkey) {
              pok = this.params.orgkey;
              delete this.params.orgkey;
            }
            pfs = (ref6 = this.params.funders) != null ? ref6 : this.params.flatten;
            delete qry.orgkey;
            delete qry.funders;
            delete qry.flatten;
            delete qry.email;
            delete this.params.size;
            delete qry.size;
            tot = (await this.index.count(rt, qry));
            if (tot > 200000 || !((ref7 = this.S.static) != null ? ref7.folder : void 0)) {
              res = {
                status: 401
              };
            } else {
              flid = (this.fn ? this.fn.replace(/\./g, '_') : '') + '_' + this.uid();
              eurl = this.S.static.url + '/export/' + flid + '.csv';
              if (tot > 100000) {
                await this.mail({
                  to: (ref8 = (ref9 = this.S.log) != null ? ref9.notify : void 0) != null ? ref8 : 'mark@oa.works',
                  text: 'Someone is creating a large csv of size ' + tot + '\n\n' + eurl + (nfeml === 'joe@oa.works' ? '' : '\n\nbut they are not the user who is allowed, so it should get capped')
                });
              }
              out = this.S.static.folder + '/export';
              try {
                filecount = ((await fs.readdir(out))).length;
                if (filecount > 900 && filecount % 20 === 0) {
                  this.mail({
                    to: (ref10 = (ref11 = this.S.log) != null ? ref11.notify : void 0) != null ? ref10 : 'mark@oa.works',
                    text: 'Warning, export file count is ' + filecount + ' they will be deleted at 1000'
                  });
                }
              } catch (error) {
                // add auto deletion of old export files?
                await fs.mkdir(out);
                filecount = 0;
              }
              try {
                if (filecount > 999) {
                  ref12 = (await fs.readdir(out));
                  for (j = 0, len1 = ref12.length; j < len1; j++) {
                    fl = ref12[j];
                    await fs.unlink(out + '/' + fl);
                  }
                  this.mail({
                    to: (ref13 = (ref14 = this.S.log) != null ? ref14.notify : void 0) != null ? ref13 : 'mark@oa.works',
                    text: 'Export files had reached 1000 so have been deleted '
                  });
                }
              } catch (error) {}
              if (filecount > 1000) {
                res = {
                  status: 401
                };
              } else {
                out += '/' + flid + '.csv';
                await fs.appendFile(out, '');
                if (this.params.includes != null) {
                  this.params.include = this.params.includes;
                  delete this.params.includes;
                }
                if (this.params.excludes != null) {
                  this.params.exclude = this.params.excludes;
                  delete this.params.excludes;
                }
                if (this.params.include != null) {
                  ks = typeof this.params.include === 'string' ? this.params.include.split(',') : this.params.include;
                  if (pok) {
                    if (typeof this.params.include === 'string' && !this.params.include.includes('orgs')) {
                      this.params.include += ',orgs';
                    } else if (Array.isArray(this.params.include) && indexOf.call(this.params.include, 'orgs') < 0) {
                      this.params.include.push('orgs');
                    }
                    if (indexOf.call(qry._source.includes, 'orgs') < 0) {
                      qry._source.includes.push('orgs');
                    }
                  }
                } else {
                  ks = [];
                  ref15 = (await this.index.keys(rt));
                  for (l = 0, len2 = ref15.length; l < len2; l++) {
                    ak = ref15[l];
                    tk = ak.split('.')[0];
                    if (indexOf.call(ks, tk) < 0 && tk !== '_id') {
                      ks.push(tk);
                    }
                  }
                }
                if (this.params.exclude != null) {
                  ref16 = (typeof this.params.exclude === 'string' ? this.params.exclude.split(',') : this.params.exclude);
                  for (o = 0, len3 = ref16.length; o < len3; o++) {
                    ex = ref16[o];
                    pidx = ks.indexOf(ex);
                    if (pidx !== -1 && (!pok || ex !== 'orgs')) {
                      ks = ks.splice(pidx, 1);
                    }
                  }
                  if (pok) {
                    orgsidx = qry._source.excludes.indexOf('orgs');
                    if (orgsidx !== -1) {
                      qry._source.excludes = qry._source.excludes.splice(orgsidx, 1);
                    }
                  }
                }
                if (nfeml) {
                  await this.mail({
                    to: nfeml,
                    subject: 'Your export has started (ref: ' + flid + '.csv)',
                    text: 'Your export has started. You can download the file any time, it will keep growing until it is complete, when you will get another notification.<br><br><a href="' + eurl + '">Download CSV</a><br><br>Thanks'
                  });
                }
                _makecsv = async(rt, qry, out, keys, notify, eurl, pfs, pok) => {
                  var author, awards, blfl, bljnd, blp, blr, bn, fi, first, funder, inst, institutions, key, len10, len11, len4, len5, len6, len7, len8, len9, names, nar, orgk, q, ref17, ref18, ref19, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, rol, rors, rou, rpke, s, st, u, v, val, w, x, y, z;
                  first = true;
                  if (pok != null) {
                    rpke = (await this.encrypt(pok));
                    orgk = (await this.report.orgs.orgkeys('key.keyword:"' + rpke + '"', 1));
                  }
                  if (pfs) {
                    keys = ['DOI', 'funder.name', 'funder.award', 'authorships.institutions.display_name', 'authorships.institutions.ror'];
                  }
                  for (q = 0, len4 = keys.length; q < len4; q++) {
                    key = keys[q];
                    await fs.appendFile(out, (!first ? ',"' : '"') + key.replace('supplements.', '') + '"');
                    first = false;
                  }
                  ref17 = this.index._for(rt, qry, {
                    scroll: '5m',
                    max: notify.includes('@oa.works') ? 200000 : 100000
                  });
                  for await (blr of ref17) {
                    await fs.appendFile(out, '\n');
                    if (pfs) {
                      names = '';
                      awards = '';
                      institutions = '';
                      rors = '';
                      if (blr.funder != null) {
                        first = true;
                        ref18 = blr.funder;
                        for (s = 0, len5 = ref18.length; s < len5; s++) {
                          funder = ref18[s];
                          names += (first ? '' : ';') + ((ref19 = funder.name) != null ? ref19 : '');
                          if ((funder.award != null) && funder.award.length) {
                            funder.award = funder.award.join(' ');
                          }
                          if (funder.award == null) {
                            funder.award = '';
                          }
                          if (Array.isArray(funder.award)) {
                            if (funder.award.length) {
                              funder.award = funder.award.join(' ');
                            } else {
                              funder.award = '';
                            }
                          }
                          funder.award = funder.award.replace(/;/g, '');
                          awards += (first ? '' : ';') + funder.award;
                          first = false;
                        }
                      }
                      if (blr.authorships != null) {
                        first = true;
                        ref20 = blr.authorships;
                        for (u = 0, len6 = ref20.length; u < len6; u++) {
                          author = ref20[u];
                          if (!first) {
                            institutions += ';';
                            rors += ';';
                          }
                          first = false;
                          if (author.institutions != null) {
                            fi = true;
                            ref21 = author.institutions;
                            for (v = 0, len7 = ref21.length; v < len7; v++) {
                              inst = ref21[v];
                              institutions += (fi ? '' : ',') + ((ref22 = inst.display_name) != null ? ref22 : '');
                              rors += (fi ? '' : ',') + ((ref23 = inst.ror) != null ? ref23 : '');
                              fi = false;
                            }
                          }
                        }
                      }
                      await fs.appendFile(out, '"' + blr.DOI + '","' + names + '","' + awards + '","' + institutions + '","' + rors + '"');
                    } else {
                      first = true;
                      for (w = 0, len8 = keys.length; w < len8; w++) {
                        k = keys[w];
                        if (k.includes('.')) {
                          try {
                            blfl = (await this.flatten(blr));
                          } catch (error) {
                            blfl = void 0;
                          }
                        } else {
                          blfl = blr;
                        }
                        if (Array.isArray(blfl)) {
                          if (blfl.length && typeof blfl[0] === 'object') {
                            st = [];
                            for (x = 0, len9 = blfl.length; x < len9; x++) {
                              blp = blfl[x];
                              if ((blp != null ? blp[k] : void 0) != null) {
                                st.push(blp[k]);
                              }
                            }
                            blfl = st;
                          }
                          nar = {};
                          nar[k] = blfl;
                          blfl = nar;
                        }
                        if ((blfl == null) || (blfl[k] == null)) {
                          val = '';
                        } else if (typeof blfl[k] === 'object') {
                          if (Array.isArray(blfl[k])) {
                            bljnd = '';
                            ref24 = blfl[k];
                            for (y = 0, len10 = ref24.length; y < len10; y++) {
                              bn = ref24[y];
                              if (typeof bn === 'object') {
                                bn = JSON.stringify(bn);
                              }
                              if (!bljnd.includes(bn)) { // Joe doesn't want duplicates kept
                                bljnd += (bljnd ? ';' : '') + bn;
                              }
                            }
                            blfl[k] = bljnd;
                          }
                          val = JSON.stringify(blfl[k]);
                        } else {
                          val = blfl[k];
                        }
                        if (typeof val === 'string') {
                          val = val.replace(/"/g, '').replace(/\n/g, '').replace(/\s\s+/g, ' ');
                        }
                        if ((k === 'email' || k === 'supplements.email') && !val.includes('@') && typeof (orgk != null ? orgk.org : void 0) === 'string' && orgk.org.length) {
                          rol = [];
                          ref26 = (ref25 = blr.orgs) != null ? ref25 : [];
                          for (z = 0, len11 = ref26.length; z < len11; z++) {
                            rou = ref26[z];
                            rol.push(rou.toLowerCase());
                          }
                          if (ref27 = orgk.org.toLowerCase(), indexOf.call(rol, ref27) >= 0) {
                            val = (await this.decrypt(val));
                          }
                        }
                        await fs.appendFile(out, (!first ? ',"' : '"') + val + '"');
                        first = false;
                      }
                    }
                  }
                  if (notify) {
                    return (await this.mail({
                      to: notify,
                      subject: 'Your export is complete (ref: ' + out.split('/').pop() + ')',
                      text: 'Your export is complete. We recommend you download and store files elsewhere as soon as possible as we may delete this file at any time.<br><br><a href="' + eurl + '">Download CSV</a><br><br>Thanks'
                    }));
                  }
                };
                this.waitUntil(_makecsv(rt, qry, out, ks, nfeml, eurl, pfs, pok));
                delete this.format;
                res = eurl;
              }
            }
          } else {
            res = (await this.index(rt + (lg.key ? '/' + lg.key : ''), rec != null ? rec : qry));
          }
          if ((res == null) && (!lg.key || (rec == null))) { // this happens if the index does not exist yet, so create it (otherwise res would be a search result object)
            await this.index(rt, typeof f._index !== 'object' ? {} : {
              settings: f._index.settings,
              mappings: (ref17 = f._index.mappings) != null ? ref17 : f._index.mapping,
              aliases: f._index.aliases
            });
            if (rec !== '') {
              res = (await this.index(rt + (lg.key ? '/' + lg.key : ''), rec != null ? rec : (!lg.key ? qry : void 0)));
            }
          }
          if ((res == null) && (rec == null) && lg.key && typeof arguments[0] === 'string' && (qry = (await this.index.translate(arguments[0], arguments[1])))) {
            qrs = (await this.index(rt, qry));
            if ((qrs != null ? (ref18 = qrs.hits) != null ? ref18.total : void 0 : void 0) === 1) {
              ref19 = (await this.keys(qrs.hits.hits[0]._source));
              for (q = 0, len4 = ref19.length; q < len4; q++) {
                k = ref19[q];
                if ((typeof qrs.hits.hits[0]._source[k] === 'string' && arguments[0] === qrs.hits.hits[0]._source[k]) || (Array.isArray(qrs.hits.hits[0]._source[k]) && (ref20 = arguments[0], indexOf.call(qrs.hits.hits[0]._source[k], ref20) >= 0))) {
                  res = qrs.hits.hits[0]._source;
                  if (res._id == null) {
                    res._id = qrs.hits.hits[0]._id;
                  }
                  break;
                }
              }
            }
          }
          if ((qry != null ? qry.size : void 0) === 1 && typeof res === 'object' && (((ref21 = res.hits) != null ? ref21.hits : void 0) != null)) {
            if (!res.hits.hits.length) {
              res = void 0;
            } else {
              if ((base = res.hits.hits[0]._source)._id == null) {
                base._id = res.hits.hits[0]._id;
              }
              res = res.hits.hits[0]._source;
            }
          }
        }
      }
      if (qry != null) {
        lg.qry = JSON.stringify(qry);
      }
      if ((res != null) && (rec == null) && !lg.cached) {
        lg.cached = 'index';
      }
      if (lg.cached && this.fn === n) {
        this.cached = lg.cached;
      }
    }
    // if nothing yet, send to bg for _bg or _sheet functions, if bg is available and not yet on bg
    // _bg, _sheet
    if ((res == null) && (f._bg || f._sheet) && typeof this.S.bg === 'string' && this.S.bg.startsWith('http')) {
      bup = {
        headers: {},
        body: rec,
        params: this.copy(this.params)
      };
      if (this.refresh) {
        bup.params.refresh = true;
      }
      bup.headers['x-' + this.S.name.toLowerCase() + '-rid'] = this.rid;
      res = (await this.fetch(this.S.bg + '/' + rt.replace(/\_/g, '/'), bup)); // if this takes too long the whole route function will timeout and cascade to bg
      lg.bg = true;
    }
    // if nothing yet, and function has _sheet, and it wasn't a specific record lookup attempt, 
    // or it was a specific API call to refresh the _sheet index, or any call where index doesn't exist yet,
    // then (create the index if not existing and) populate the index from the sheet
    // this will happen on background where possible, because above will have routed to bg if it was available
    // _sheet
    if ((res == null) && f._sheet && rec !== '' && ((this.refresh && this.fn === n) || !(exists = (await this.index(rt))))) {
      res = (await this._loadsheet(f, rt));
      if (arguments.length || JSON.stringify(this.params) !== '{}') { // if there are args, don't set the res, so the function can run afterwards if present
        res = void 0;
      }
    }
    
    // if still nothing happened, and the function defined on P really IS a function
    // (it could also be an index or kv config object with no default function)
    // call the function, either _async if the function indicates it, or directly
    // and record limit settings if present to restrict more runnings of the same function
    // _async, _limit
    if ((res == null) && (!f._index || rec !== '') && typeof f === 'function') {
      _as = async(rt, f, ar, notify, nn) => {
        var ends, id, len5, r, ref22, ref23, s, txt;
        if (f._limit) {
          ends = f._limit === true ? 86400 : f._limit;
          await this.kv('limit/' + nn, started + ends, ends); // max limit for one day
        }
        r = (await f.apply(this, ar));
        delete _unique[nn];
        if (typeof r === 'object' && (f._kv || f._index) && (r.took == null) && (r.hits == null)) {
          if (f._key && Array.isArray(r) && r.length && (r[0]._id == null) && (r[0][f._key] != null)) {
            for (s = 0, len5 = r.length; s < len5; s++) {
              c = r[s];
              if (c._id == null) {
                c._id = c[f._key].replace(/\//g, '_').toLowerCase();
              }
            }
          }
          id = Array.isArray(r) ? '' : '/' + ((ref22 = (ref23 = r[f._key]) != null ? ref23 : r._id) != null ? ref22 : this.uid()).replace(/\//g, '_').toLowerCase();
          if (f._kv && !Array.isArray(r)) {
            this.kv(rt + id, res, f._kv);
          }
          if (f._index) {
            this.waitUntil(this.index(rt + id, r));
          }
        }
        if (f._limit === true) {
          await this.kv('limit/' + nn, ''); // where limit is true only delay until function completes, then delete limit record
        }
        if (f._async && f._schedule !== 'loop') {
          this.kv('async/' + this.rid, ((id != null) && !Array.isArray(r) ? rt + id : Array.isArray(r) ? r.length : r), 172800); // lasts 48 hours
          if (this.fn === nn && f._notify !== false) {
            txt = this.fn + ' done at ' + ((await this.datetime(void 0, false))) + '\n\n' + JSON.stringify(r) + '\n\n' + this.base + '/' + rt + '?_async=' + this.rid;
            if (notify) {
              this.mail({
                to: notify,
                text: txt
              });
            }
          }
        }
        return r;
      };
      if (f._async && this.fn === n) {
        lg.async = true;
        if (f._unique && (prid = _unique[n])) {
          res = {
            _async: prid
          };
        } else {
          if (f._unique) {
            _unique[this.fn] = this.rid;
          }
          res = {
            _async: this.rid
          };
          this.waitUntil(_as(rt, f, arguments, this.params.notify, n));
        }
      } else {
        res = (await _as(rt, f, arguments));
      }
    }
    // _log - DISABLED all wrapped logging. Only requests onto the API routes get logged as of 11/10/2023
    //if f._log isnt false and not f._index and not lg.qry? and not n.includes '._'
    //  lg.took = Date.now() - started
    //  @log lg
    return res;
  };
};

P.svc = {};

P.src = {};

P.status = async function() {
  var i, j, len, len1, ref, ref1, ref2, res, ss;
  res = {
    name: S.name,
    version: S.version,
    built: S.built
  };
  try {
    res.pmid = process.env.pm_id;
  } catch (error) {}
  try {
    res.pmname = process.env.name;
  } catch (error) {}
  ref = ['rid', 'params', 'base', 'parts', 'opts', 'routes'];
  for (i = 0, len = ref.length; i < len; i++) {
    k = ref[i];
    try {
      if (res[k] == null) {
        res[k] = this[k];
      }
    } catch (error) {}
  }
  if (this.S.bg === true) {
    try {
      res.schedule = {};
      for (ss in _schedule) {
        res.schedule[ss] = {};
        for (k in _schedule[ss]) {
          if (k !== 'fn') {
            res.schedule[ss][k] = _schedule[ss][k];
          }
        }
      }
    } catch (error) {}
  }
  if (this.S.bg === true) {
    res.bg = true;
  }
  res.kv = typeof this.S.kv === 'string' && global[this.S.kv] ? this.S.kv : typeof this.S.kv === 'string' ? this.S.kv : false;
  try {
    res.index = (await this.index.status());
  } catch (error) {}
  if (S.dev) {
    res.bg = this.S.bg;
    if (this.S.bg !== true) {
      try {
        res.request = this.request;
      } catch (error) {}
    }
    ref1 = ['headers', 'cookie', 'user', 'body'];
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      k = ref1[j];
      try {
        if (res[k] == null) {
          res[k] = this[k];
        }
      } catch (error) {}
    }
  } else {
    try {
      res.index = res.index.status;
    } catch (error) {}
    if (res.kv) {
      res.kv = true;
    }
    res.user = (ref2 = this.user) != null ? ref2.email : void 0;
  }
  return res;
};

// curl -X GET "https://api.oa.works/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
// curl -X GET "https://api.oa.works/auth?apikey=YOURAPIKEYHERE"

// store user record object in kv as users/:UID (value is stringified json object)
// and store a map of API keys as well, auth/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
// store a login token at auth/token/:TOKEN (value is email) (autoexpire login tokens at 20mins 1200s)
// and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about three months 7890000s, but rotate them on non-cookie use)
// and store users to the index as well if available
var indexOf = [].indexOf;

P.auth = async function(key) {
  var cookie, email, oauth, ref, ref1, ref2, ref3, ref4, ref5, restok, resume, ret, uid, user;
  // if params.auth, someone looking up the URL route for this acc. Who would have the right to see that?
  if (typeof key === 'string') { // or key can be false, to pass through to unauthorised / login / request page
    return this.users._get(key);
  }
  if (!key && (this.user != null) && (this.fn === 'auth' || key === false)) {
    user = this.user;
  } else if (key !== false) {
    if ((this.params.access_token && (oauth = (await this.auth._oauth(this.params.access_token)))) || ((this.params.token || this.params.auth) && (email = (await this.kv('auth/token/' + ((ref = this.params.token) != null ? ref : this.params.auth), ''))))) { // true causes delete after found
      if (!(user = (await this.users._get((ref1 = oauth != null ? oauth.email : void 0) != null ? ref1 : email)))) { // get the user record if it already exists
        user = (await this.users._create(oauth != null ? oauth : email)); // create the user record if not existing, as this is the first token login attempt for this email address
      }
    }
    if (!user && this.apikey) {
      if (this.S.bg === true) {
        user = (await this.users._get(void 0, this.apikey));
      }
      if (!user && (uid = (await this.kv('auth/apikey/' + this.apikey)))) {
        user = (await this.users._get(uid)); // no user creation if apikey doesn't match here - only create on login token above 
      }
    }
    if (!user && (this.params.resume || this.cookie)) { // accept resume on a header too?
      if (!(resume = this.params.resume)) { // login by resume token if provided in param or cookie
        try {
          cookie = JSON.parse(decodeURIComponent(this.cookie).split(((ref2 = (ref3 = S.auth) != null ? (ref4 = ref3.cookie) != null ? ref4.name : void 0 : void 0) != null ? ref2 : 'oaworksLogin') + "=")[1].split(';')[0]);
          resume = cookie.resume;
          uid = cookie._id;
        } catch (error) {}
      }
      if (uid == null) {
        uid = this.headers['x-id'];
      }
      if (this.params.email && !uid) {
        uid = this.hashhex(this.params.email.trim().toLowerCase()); // accept resume with email instead of id?
      }
      if (resume && uid && (restok = (await this.kv('auth/resume/' + uid + '/' + resume)))) {
        user = (await this.users._get(uid));
        if (user != null) {
          user.resume = resume;
        }
      }
    }
  }
  if (typeof user === 'object' && user._id) {
    // if 2fa is enabled, request a second form of ID (see below about implementing 2fa)

    // record the user login timestamp, and if login came from a service the user does not yet have a role in, add the service user role
    // who can add the service param?
    if (this.params.service && (((ref5 = user.roles) != null ? ref5[this.params.service] : void 0) == null)) {
      if (user.roles == null) {
        user.roles = {};
      }
      user.roles[this.params.service] = 'user';
      this.users._update(user);
    }
    if ((user.resume == null) && !this.apikey) {
      user.resume = this.uid();
      this.kv('auth/resume/' + user._id + '/' + user.resume, {
        createdAt: Date.now()
      }, 7890000); // resume token lasts three months (could make six at 15768000)
    }
    if ((await this.auth.role('root', this.user))) {
      this.log({
        msg: 'root login' //, notify: true
      });
    }
  }
  
  // if this is called with no variables, and no defaults, provide a count of users?
  // but then if logged in and on this route, what does it provide? the user account?
  if (!this.format && (this.fn === 'auth' || this.unauthorised) && this.headers['user-agent'] && this.headers['user-agent'].toLowerCase().includes('mozilla') && this.headers.accept && this.headers.accept.includes('/html') && !this.headers.accept.includes('/json')) {
    this.format = 'html';
  }
  if (!key && this.format === 'html') {
    ret = '<body>';
    ret += '<script type="text/javascript" src="/client/oaworksLogin.min.js?v=' + this.S.version + '"></script>\n';
    ret += '<h1>' + (this.base ? this.base.replace('bg.', '(bg) ') : this.S.name) + '</h1>';
    if (this.user == null) {
      ret += '<input autofocus id="OALoginEmail" class="OALoginEmail" type="text" name="email" placeholder="email">';
      ret += '<input id="OALoginToken" class="OALoginToken" style="display:none;" type="text" name="token" placeholder="token (check your email)">';
      ret += '<p class="OALoginWelcome" style="display:none;">Welcome back</p>';
      ret += '<p class="OALoginLogout" style="display:none;"><a id="OALoginLogout" href="#">logout</a></p>';
    } else {
      ret += '<p>' + user.email + '</p><p><a id="PLogout" href="#">logout</a></p>';
    }
    return ret + '</body>';
  } else {
    return user;
  }
};

P.auth.token = function(email, from, subject, text, html, template, url) {
  var ref, ref1, token;
  if (email == null) {
    email = this.params.email;
  }
  if (email) {
    email = email.trim().toLowerCase();
    if (from == null) {
      from = (ref = (ref1 = S.auth) != null ? ref1.from : void 0) != null ? ref : 'login@oa.works';
    }
    token = this.uid(8);
    if (this.S.dev && this.S.bg === true) {
      console.log(email, token);
    }
    if (url == null) {
      url = this.params.url;
    }
    if (url) {
      url += '#' + token;
      if (subject == null) {
        subject = 'Complete your login to ' + (url.includes('//') ? url.split('//')[1] : url).split('/')[0];
      }
    } else {
      url = this.base + '/' + this.route.replace('/token', '/' + token);
      if (subject == null) {
        subject = 'Complete your login to ' + (this.base ? this.base.replace('bg.', '(bg) ') : this.S.name);
      }
    }
    this.kv('auth/token/' + token, email, 1200); // create a token that expires in 20 minutes
    this.waitUntil(this.mail({
      from: from,
      to: email,
      subject: subject,
      text: text != null ? text : 'Your login code is:\r\n\r\n' + token + '\r\n\r\nor use this link:\r\n\r\n' + url + '\r\n\r\nnote: this single-use code is only valid for 20 minutes.',
      html: html != null ? html : '<html><body><p>Your login code is:</p><p><b>' + token + '</b></p><p>or click on this link</p><p><a href=\"' + url + '\">' + url + '</a></p><p>note: this single-use code is only valid for 10 minutes.</p></body></html>',
      //template: template
      params: {
        token: token,
        url: url
      }
    }));
    return {
      email: email //@uid 8 # is there a case where this would somehow be useful? It's not getting saved anywhere for later confirmation...
    };
  } else {

  }
};


// auth/:uid/role/:grl
// check if a user has a role or one of a list of roles
P.auth.role = async function(grl, user) {
  var cascade, g, group, i, j, len, len1, ref, ref1, ref2, ref3, ri, rl, role;
  if (grl == null) {
    grl = this.params.role;
  }
  user = typeof user === 'object' ? user : user || this.params.auth ? (await this.users._get(user != null ? user : this.params.auth)) : this.user;
  if (grl === 'system' && this.system) {
    return 'system';
  }
  if ((user != null ? user.email : void 0) && (ref = user.email, indexOf.call((typeof this.S.root === 'string' ? [this.S.root] : Array.isArray(this.S.root) ? this.S.root : []), ref) >= 0)) {
    return 'root';
  }
  if (grl.startsWith('@') && ((user != null ? user.email : void 0) != null) && user.email.endsWith(grl)) { // a user can be allowed if the required auth is the @domain.com of their email address
    return grl;
  }
  if ((user != null ? user.roles : void 0) != null) {
    ref1 = (typeof grl === 'string' ? grl.split(',') : grl ? grl : []);
    for (i = 0, len = ref1.length; i < len; i++) {
      g = ref1[i];
      [group, role] = g.replace('/', '.').split('.');
      if (group === user._id) { // user is owner on their own group
        return 'owner';
      }
      if (role) {
        if (indexOf.call((ref2 = user.roles[group]) != null ? ref2 : [], role) >= 0) {
          return role;
        } else if (user.roles[group] != null) {
          cascade = ['service', 'owner', 'super', 'admin', 'auth', 'bulk', 'delete', 'remove', 'create', 'insert', 'publish', 'put', 'draft', 'post', 'edit', 'update', 'user', 'get', 'read', 'info', 'public', 'request'];
          if (-1 < (ri = cascade.indexOf(role))) {
            ref3 = cascade.splice(0, ri);
            for (j = 0, len1 = ref3.length; j < len1; j++) {
              rl = ref3[j];
              if (indexOf.call(user.roles[group], rl) >= 0) {
                return rl;
              }
            }
          }
        }
      }
    }
  }
  return false;
};

// /auth/:uid/add/:grl
// add a user to a role, or remove, or deny
// deny meaning automatically not allowed any other role on the group
// whereas otherwise a user (or system on behalf of) should be able to request a role (TODO)
P.auth.add = async function(grl, user, remove, deny) {
  var base, group, ref, ref1, ref2, ref3, role;
  user = typeof user === 'object' ? user : user || this.params.auth ? (await this.users._get(user != null ? user : this.params.auth)) : this.user;
  if (!grl && this.user._id !== user._id) {
    if (!(await this.auth.role('system'))) {
      // TODO what about one logged in user acting on the roles route of another? - which groups could a user add another user to?
      return false;
    }
  }
  if (grl == null) {
    grl = (ref = (ref1 = this.params.add) != null ? ref1 : this.params.remove) != null ? ref : this.params.deny;
  }
  if (!grl) {
    return false;
  }
  [group, role] = grl.replace('/', '.').split('.');
  if (remove == null) {
    remove = (this.request.method === 'DELETE' || this.params._delete === true) && this.fn === 'auth.roles';
  }
  if (group === 'root' || role === 'root') { // root only allowed by config. can't be set via API.
    return false;
  } else if (deny) {
    user.roles[group] = ['deny']; // no other roles can be kept
    this.users._update(user);
  } else if (!role) {
    if (user.roles[group] != null) {
      if (remove != null) {
        delete user.roles[group];
        this.users._update(user);
      }
    } else {
      user.roles[group] = ['user'];
      this.users._update(user);
    }
  } else if (((ref2 = user.roles) != null ? ref2[group] : void 0) && indexOf.call(user.roles[group], role) >= 0) {
    if (remove != null) {
      user.roles[group].splice(user.roles[group].indexOf(role), 1);
      if (!user.roles[group].length) {
        delete user.roles[group];
      }
      this.users._update(user);
    }
  } else if (role !== 'request' || indexOf.call((ref3 = user.roles[group]) != null ? ref3 : [], 'deny') < 0) {
    if ((base = user.roles)[group] == null) {
      base[group] = [];
    }
    if (indexOf.call(user.roles[group], 'request') >= 0) {
      user.roles[group] = user.roles[group].splice(user.roles[group].indexOf('request'), 1);
    }
    user.roles.group.push(role);
    this.users._update(user);
  }
  // TODO if role to add is 'request' then notify someone who can authorise - or have a cron job send batch notifications
  return user;
};

P.auth.remove = function(grl, user) {
  return this.auth.add(grl, user, true); // remove and deny would auth on add
};

P.auth.deny = function(grl, user) {
  return this.auth.add(grl, user, void 0, true);
};

P.auth.request = function(grl, user) {
  if (grl == null) {
    grl = this.params.request; // anyone can request so no auth needed for request
  }
  grl = grl.split('/')[0] + '/request';
  return this.auth.add(grl, user);
};

P.auth.logout = async function(user) { // how about triggering a logout on a different user account
  if (user == null) {
    user = this.user;
  }
  if (user) {
    await this.kv._each('auth/resume/' + (typeof user === 'string' ? (user.includes('@') ? this.hashhex(user.trim().toLowerCase()) : user) : user._id), '');
    return true;
  } else {
    return false;
  }
};

P.auth._oauth = async function(token, cid) {
  var ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, ret, sets, validate;
  // https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  sets = {};
  if (token) { //?= @params.access_token
    try {
      // we did also have facebook oauth in here, still in old code, but decided to drop it unless explicitly required again
      validate = (await this.fetch('https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + token, {
        method: 'POST' // has to be a POST even though it sends nothing
      }));
      if (cid == null) {
        cid = (ref = (ref1 = this.S.svc[(ref2 = this.params.service) != null ? ref2 : 'z']) != null ? (ref3 = ref1.google) != null ? (ref4 = ref3.oauth) != null ? (ref5 = ref4.client) != null ? ref5.id : void 0 : void 0 : void 0 : void 0) != null ? ref : (ref6 = S.use) != null ? (ref7 = ref6.google) != null ? (ref8 = ref7.oauth) != null ? (ref9 = ref8.client) != null ? ref9.id : void 0 : void 0 : void 0 : void 0;
      }
      if ((cid != null) && ((ref10 = validate.data) != null ? ref10.aud : void 0) === cid) {
        ret = (await this.fetch('https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + token));
        return {
          email: ret.data.email.toLowerCase(),
          google: {
            id: ret.data.id
          },
          name: (ref11 = ret.data.name) != null ? ref11 : ret.data.given_name + (ret.data.family_name ? ' ' + ret.data.family_name : ''),
          avatar: ret.data.picture
        };
      }
    } catch (error) {}
  }
};

// an oauth client-side would require the google oauth client token. It's not a secret, but must be got in advance from google account provider
// ours is '360291218230-r9lteuqaah0veseihnk7nc6obialug84.apps.googleusercontent.com' - but that's no use to anyone else, unless wanting to login with us
// the Oauth URL that would trigger something like this would be like:
// grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true'
// grl += '&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
// grl += '&state=' + state + '&redirect_uri=' + P.oauthRedirectUri + '&client_id=' + P.oauthGoogleClientId
// state would be something like Math.random().toString(36).substring(2,8) and would be sent and also kept for checking against the response
// the response from oauth login page would go back to current page and have a # with access_token= and state=
// NOTE as it is after a # these would only be available on a browser, as servers don't get the # part of a URL
// if the states match, send the access_token into the above method and if it validates then we can login the user
P.users = {
  _index: true,
  _auth: 'system'
};

P.users._get = async function(uid, apikey) {
  var ref, us, user;
  if (apikey) {
    us = (await this.index('users', 'apikey:"' + apikey + '"'));
    if ((us != null ? (ref = us.hits) != null ? ref.total : void 0 : void 0) === 1) {
      user = us.hits.hits[0]._source;
      if (user._id == null) {
        user._id = us.hits.hits[0]._id;
      }
    }
  } else if (typeof uid === 'string') {
    if (uid.startsWith('users/')) {
      uid = uid.replace('users/', '');
    }
    if (uid.includes('@')) {
      uid = this.hashhex(uid.trim().toLowerCase());
    }
    if (this.S.bg !== true) {
      try {
        user = (await this.kv('users/' + uid));
      } catch (error) {}
    }
    if (user == null) {
      try {
        user = (await this.index('users/' + uid));
      } catch (error) {}
      if ((user != null) && this.S.bg !== true) { // may have found a user from the index who isn't in the local kv yet, so put it in
        try {
          await this.kv('users/' + uid, user);
        } catch (error) {}
        try {
          await this.kv('auth/apikey/' + user.apikey, uid);
        } catch (error) {}
      }
    }
  }
  return user;
};

P.users._create = async function(user) {
  var u;
  if (typeof user === 'string') {
    user = {
      email: user
    };
  }
  if (typeof user.email !== 'string' || !user.email.includes('@')) {
    return false;
  }
  u = {
    _id: this.hashhex(user.email.trim().toLowerCase()),
    email: user.email,
    apikey: this.uid()
  };
  delete user.email;
  try {
    u.profile = user; // could use other input as profile input data? better for services to store this where necessary though
  } catch (error) {}
  try {
    u.creation = this.base + '/' + this.route; // which domain the user was created from
  } catch (error) {}
  u.roles = {};
  u.createdAt = new Date();
  try {
    await this.kv('users/' + u._id, u);
  } catch (error) {}
  try {
    await this.kv('auth/apikey/' + u.apikey, u._id);
  } catch (error) {}
  try {
    this.waitUntil(this.index('users/' + u._id, u));
  } catch (error) {}
  return u;
};

P.users._update = async function(uid, user) {
  // TODO how to decide who can update users, remotely or locally, and is it always a total update or could be a partial?
  if (typeof uid === 'object' && user._id && (user == null)) {
    user = uid;
    uid = user._id;
  }
  if (typeof uid === 'string' && typeof user === 'object' && JSON.stringify(user) !== '{}') {
    if (uid.startsWith('users/')) {
      uid = uid.replace('users/', '');
    }
    if (uid.includes('@')) {
      uid = this.hashhex(uid.trim().toLowerCase());
    }
    user.updatedAt = new Date();
    try {
      await this.kv('users/' + uid, user);
    } catch (error) {}
    try {
      this.waitUntil(this.index('users/' + uid, user));
    } catch (error) {}
    return true;
  } else {
    return false;
  }
};

P.users._delete = async function(uid) {
  var ref, user;
  if (user = (typeof uid === 'object' ? uid : ((ref = this.user) != null ? ref._id : void 0) === uid ? this.user : (await this.users._get(uid)))) {
    try {
      await this.kv._each('auth/resume/' + user._id, '');
    } catch (error) {}
    try {
      await this.kv('auth/apikey/' + user.apikey, '');
    } catch (error) {}
    try {
      await this.kv('users/' + user._id, '');
    } catch (error) {}
    try {
      return (await this.index('users/' + user._id, ''));
    } catch (error) {}
  }
};

// get the big deal data from a sheet and expose it in a website
// https://docs.google.com/spreadsheets/d/e/2PACX-1vQ4frfBvvPOKKFhArpV7cRUG0aAbfGRy214y-xlDG_CsW7kNbL-e8tuRvh8y37F4xc8wjO6FK8SD6UT/pubhtml
// https://docs.google.com/spreadsheets/d/1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs/edit
P.deal = {
  _index: true,
  _prefix: false
};

P.deal.institution = {
  _index: true,
  _prefix: false
};

P.deal.load = async function() {
  var i, institutions, insts, j, k, len, len1, name, rdc, rec, recs, ref, tk, tl;
  recs = (await this.src.google.sheets('1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs'));
  institutions = {};
  for (j = 0, len = recs.length; j < len; j++) {
    rec = recs[j];
    ref = ['Institution', 'Publisher', 'Collection', 'Year(s)', 'Length of Agreement', 'Package Price', '2015 Carnegie Basic Classification', 'FTE', 'Source', 'URL', 'Share URL Publicly?', 'Notes'];
    for (k = 0, len1 = ref.length; k < len1; k++) {
      tk = ref[k];
      tl = tk.toLowerCase().replace(/ /g, '').replace('?', '').replace('(', '').replace(')', '');
      rec[tl] = rec[tk];
      delete rec[tk];
    }
    try {
      rec.value = parseInt(rec.packageprice.replace(/[^0-9]/g, ''));
      if (typeof rec.fte === 'string') {
        try {
          rec.fte = parseInt(rec.fte);
        } catch (error) {
          delete rec.fte;
        }
      }
      if (typeof rec.notes === 'string' && rec.notes.toLowerCase().includes('canadian')) {
        rec.gbpvalue = Math.floor(rec.value * .57);
        rec.usdvalue = Math.floor(rec.value * .75);
      } else if (rec.packageprice.includes('$')) {
        rec.gbpvalue = Math.floor(rec.value * .77);
        rec.usdvalue = Math.floor(rec.value);
      } else {
        rec.gbpvalue = Math.floor(rec.value);
        rec.usdvalue = Math.floor(rec.value * 1.3);
      }
    } catch (error) {}
    if (rec.usdvalue == null) {
      rec.usdvalue = '';
    }
    try {
      if (rec.years === '2103') { // fix what is probably a typo
        rec.years = '2013';
      }
    } catch (error) {}
    try {
      if (rec.shareurlpublicly.toLowerCase() !== 'yes') {
        delete rec.url;
      }
    } catch (error) {}
    try {
      delete rec.shareurlpublicly;
    } catch (error) {}
    try {
      if (rec.collection === '') {
        rec.collection = 'Unclassified';
      }
    } catch (error) {}
    try {
      rec.carnegiebasicclassification = rec['2015carnegiebasicclassification'];
      delete rec['2015carnegiebasicclassification'];
    } catch (error) {}
    try {
      if (institutions[name = rec.institution] == null) {
        institutions[name] = {
          institution: rec.institution,
          deals: [],
          value: 0,
          usdvalue: 0,
          gbpvalue: 0
        };
      }
      rdc = JSON.parse(JSON.stringify(rec));
      try {
        delete rdc.institution;
      } catch (error) {}
      try {
        institutions[rec.institution].value += rec.value;
        institutions[rec.institution].gbpvalue += rec.gbpvalue;
        institutions[rec.institution].usdvalue += rec.usdvalue;
      } catch (error) {}
      institutions[rec.institution].deals.push(rdc);
    } catch (error) {}
  }
  insts = [];
  for (i in institutions) {
    insts.push(institutions[i]);
  }
  await this.deal('');
  await this.deal.institution('');
  await this.deal(recs);
  await this.deal.institution(insts);
  return {
    retrieved: recs.length,
    institutions: insts.length
  };
};

// need listing of deposits and deposited for each user ID
// and/or given a uid, find the most recent URL that this users uid submitted a deposit for
// need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
// make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)
// NOTE to receive files should send to background server
// cloudflare will limit file upload size (100mb by default, and enterprise plans required for more)
var indexOf = [].indexOf;

P.deposits = {
  _index: true // store a record of all deposits. This used to filter to only those for the logged in user, that should be changed to deposited endpoint
};

P.deposit = async function(params, file, dev) {
  var a, as, at, author, bcc, ccm, com, creators, dep, description, ee, i, in_zenodo, j, k, len, len1, len2, len3, len4, m, meta, ml, n, o, parts, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref38, ref39, ref4, ref40, ref41, ref42, ref43, ref5, ref6, ref7, ref8, ref9, tk, tmpl, tos, uc, z, zn, zs;
  if (params == null) {
    params = this.copy(this.params);
  }
  if (((ref = params.metadata) != null ? ref.doi : void 0) && !params.doi) {
    params.doi = params.metadata.doi;
  }
  if (this.request.files) {
    if (file == null) {
      file = this.request.files[0];
    }
  }
  if (Array.isArray(file)) {
    file = file[0];
  }
  if (dev == null) {
    dev = this.S.dev;
  }
  dep = {
    createdAt: Date.now()
  };
  dep.created_date = (await this.datetime(dep.createdAt));
  ref1 = ['embedded', 'demo', 'pilot', 'live', 'email', 'plugin'];
  for (i = 0, len = ref1.length; i < len; i++) {
    k = ref1[i];
    dep[k] = params[k];
  }
  if (dep.pilot === true) {
    dep.pilot = Date.now();
  }
  if (dep.live === true) {
    dep.live = Date.now();
  }
  dep.name = (ref2 = file != null ? file.filename : void 0) != null ? ref2 : file != null ? file.name : void 0;
  if (params.from !== 'anonymous') {
    dep.from = params.from;
  }
  if (params.confirmed) {
    // if confirmed is true the submitter has confirmed this is the right file (and decode saves it as a "true" string, not bool, so doesn't clash in ES). If confirmed is the checksum this is a resubmit by an admin
    dep.confirmed = decodeURIComponent(params.confirmed);
  }
  dep.doi = (ref3 = params.doi) != null ? ref3 : (ref4 = params.metadata) != null ? ref4.doi : void 0;
  if ((params.metadata == null) && params.doi) {
    params.metadata = (await this.metadata(params.doi));
  }
  dep.metadata = params.metadata;
  uc = params.config; // should exist but may not
  if (typeof params.config === 'string') {
    uc = JSON.parse(params.config);
  }
  if (!params.config && params.from) {
    uc = (await this.fetch('https://' + (dev ? 'dev.' : '') + 'api.cottagelabs.com/service/oab/deposit/config?uid=' + params.from));
  }
  dep.permissions = (ref5 = params.permissions) != null ? ref5 : (await this.permissions((ref6 = params.metadata) != null ? ref6 : params.doi)); // SYP only works on DOI so far, so deposit only works if permissions can work, which requires a DOI if about a specific article
  if (!params.redeposit) {
    if ((file == null) && params.email && (params.metadata != null)) {
      dep.type = 'dark';
    } else {
      dep.archivable = (await this.archivable(file, void 0, dep.confirmed, params.metadata, dep.permissions, dev));
      if (((ref7 = dep.archivable) != null ? ref7.metadata : void 0) != null) {
        delete dep.archivable.metadata;
      }
    }
  }
  if (((ref8 = dep.archivable) != null ? ref8.archivable : void 0) && (!dep.confirmed || dep.confirmed === dep.archivable.checksum)) { // if the depositor confirms we don't deposit, we manually review - only deposit on admin confirmation (but on dev allow it)
    zn = {
      content: file.data,
      name: dep.archivable.name
    };
    zn.publish = true;
    creators = [];
    ref11 = (ref9 = (ref10 = params.metadata) != null ? ref10.author : void 0) != null ? ref9 : [];
    for (j = 0, len1 = ref11.length; j < len1; j++) {
      a = ref11[j];
      if (a.family != null) {
        at = {
          name: a.family + (a.given ? ', ' + a.given : '')
        };
        try {
          if (a.ORCID) {
            at.orcid = a.ORCID.split('/').pop();
          }
        } catch (error) {}
        try {
          if (typeof a.affiliation === 'object' && (a.affiliation.name != null)) {
            at.affiliation = a.affiliation.name;
          }
        } catch (error) {}
        creators.push(at);
      }
    }
    if (creators.length === 0) {
      creators = [
        {
          name: 'Unknown'
        }
      ];
    }
    description = params.metadata.abstract ? params.metadata.abstract + '<br><br>' : '';
    description += (ref12 = (ref13 = dep.permissions.best_permission) != null ? ref13.deposit_statement : void 0) != null ? ref12 : (params.metadata.doi != null ? 'The publisher\'s final version of this work can be found at https://doi.org/' + params.metadata.doi : '');
    description = description.trim();
    if (description.lastIndexOf('.') !== description.length - 1) {
      description += '.';
    }
    if (description.length) {
      description += ' ';
    }
    description += '<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.';
    meta = {
      title: (ref14 = params.metadata.title) != null ? ref14 : 'Unknown',
      description: description.trim(),
      creators: creators,
      version: dep.archivable.version === 'submittedVersion' ? 'Submitted Version' : dep.archivable.version === 'acceptedVersion' ? 'Accepted Version' : dep.archivable.version === 'publishedVersion' ? 'Published Version' : 'Accepted Version',
      journal_title: params.metadata.journal,
      journal_volume: params.metadata.volume,
      journal_issue: params.metadata.issue,
      journal_pages: params.metadata.page
    };
    if (params.doi) {
      zs = (await this.src.zenodo.records.search('"' + params.doi + '"', dev));
      if (zs != null ? (ref15 = zs.hits) != null ? ref15.total : void 0 : void 0) {
        in_zenodo = zs.hits.hits[0];
      }
      if (in_zenodo && dep.confirmed !== dep.archivable.checksum && !dev) {
        dep.zenodo = {
          already: in_zenodo.id
        };
      } else {
        meta['related_identifiers'] = [
          {
            relation: (meta.version === 'postprint' || meta.version === 'AAM' || meta.version === 'preprint' ? 'isPreviousVersionOf' : 'isIdenticalTo'),
            identifier: params.doi
          }
        ];
      }
    }
    meta.prereserve_doi = true;
    meta['access_right'] = 'open';
    meta.license = (ref16 = (ref17 = dep.permissions.best_permission) != null ? ref17.licence : void 0) != null ? ref16 : 'cc-by'; // zenodo also accepts other-closed and other-nc, possibly more
    if (meta.license.includes('other') && meta.license.includes('closed')) {
      meta.license = 'other-closed';
    }
    if (meta.license.includes('other') && meta.license.includes('non') && meta.license.includes('commercial')) {
      meta.license = 'other-nc';
    }
    if (meta.license.toLowerCase().startsWith('cc') && isNaN(parseInt(meta.license.substring(meta.license.length - 1)))) {
      meta.license += '-4.0';
    }
    try {
      if ((ref18 = dep.permissions.best_permission) != null ? ref18.embargo_end : void 0) {
        ee = (await this.epoch(dep.permissions.best_permission.embargo_end));
        if (ee > Date.now()) {
          meta['access_right'] = 'embargoed';
          meta['embargo_date'] = dep.permissions.best_permission.embargo_end; // check date format required by zenodo
          dep.embargo = dep.permissions.best_permission.embargo_end;
        }
      }
    } catch (error) {}
    try {
      if ((params.metadata.published != null) && typeof params.metadata.published === 'string') {
        meta['publication_date'] = params.metadata.published;
      }
    } catch (error) {}
    if (uc != null) {
      dep.config = uc;
      if ((uc.community_ID != null) && (uc.community == null)) {
        uc.community = uc.community_ID;
      }
      if (uc.community) {
        if (uc.communities == null) {
          uc.communities = [];
        }
        ref19 = (typeof uc.community === 'string' ? uc.community.split(',') : uc.community);
        for (m = 0, len2 = ref19.length; m < len2; m++) {
          ccm = ref19[m];
          uc.communities.push({
            identifier: ccm
          });
        }
      }
      if ((uc.community != null) || (uc.communities != null)) {
        if (uc.communities == null) {
          uc.communities = uc.community;
        }
        if (!Array.isArray(uc.communities)) {
          uc.communities = [uc.communities];
        }
        meta.communities = [];
        ref20 = uc.communities;
        for (n = 0, len3 = ref20.length; n < len3; n++) {
          com = ref20[n];
          meta.communities.push(typeof com === 'string' ? {
            identifier: com
          } : com);
        }
      }
      if (meta.communities && meta.communities.length) {
        dep.community = meta.communities[0].identifier;
      }
    }
    if (tk = (dev || dep.demo ? (ref21 = this.S.src.zenodo) != null ? ref21.sandbox : void 0 : (ref22 = this.S.src.zenodo) != null ? ref22.token : void 0)) {
      if (!((ref23 = dep.zenodo) != null ? ref23.already : void 0)) {
        z = (await this.src.zenodo.deposition.create(meta, zn, tk, dev));
        if (z.id) {
          dep.zenodo = {
            id: z.id,
            url: 'https://' + (dev || dep.demo ? 'sandbox.' : '') + 'zenodo.org/record/' + z.id,
            doi: ((ref24 = z.metadata) != null ? (ref25 = ref24.prereserve_doi) != null ? ref25.doi : void 0 : void 0) != null ? z.metadata.prereserve_doi.doi : void 0,
            file: (ref26 = (ref27 = z.uploaded) != null ? (ref28 = ref27.links) != null ? ref28.download : void 0 : void 0) != null ? ref26 : (ref29 = z.uploaded) != null ? (ref30 = ref29.links) != null ? ref30.download : void 0 : void 0
          };
          if (dep.doi == null) {
            dep.doi = dep.zenodo.doi;
          }
          dep.type = 'zenodo';
        } else {
          dep.error = 'Deposit to Zenodo failed';
          try {
            dep.error += ': ' + JSON.stringify(z);
          } catch (error) {}
          dep.type = 'review';
        }
      }
    } else {
      dep.error = 'No Zenodo credentials available';
      dep.type = 'review';
    }
  }
  if ((ref31 = dep.archivable) != null ? ref31.timeout : void 0) {
    dep.error = 'Archivable timeout';
    dep.type = 'review';
  }
  dep.version = (ref32 = dep.archivable) != null ? ref32.version : void 0;
  if (!dep.type && params.from && (!dep.embedded || (!dep.embedded.includes('oa.works') && !dep.embedded.includes('openaccessbutton.org') && !dep.embedded.includes('shareyourpaper.org')))) {
    dep.type = params.redeposit ? 'redeposit' : file ? 'forward' : 'dark';
  }
  if (dep.doi) {
    if (dep.type == null) {
      dep.type = 'review';
    }
    dep.url = typeof params.redeposit === 'string' ? params.redeposit : params.url ? params.url : void 0;
    await this.deposits(dep);
    if ((dep.type !== 'review' || (file != null)) && ((ref33 = dep.archivable) != null ? ref33.archivable : void 0) !== false && (!(typeof exists !== "undefined" && exists !== null ? (ref34 = exists.zenodo) != null ? ref34.already : void 0 : void 0) || dev)) {
      bcc = ['joe@oa.works', 'shared@oa.works'];
      if (dev) {
        bcc.push('mark@oa.works');
      }
      tos = [];
      if (typeof (uc != null ? uc.owner : void 0) === 'string' && uc.owner.includes('@') && !dep.error) {
        tos.push(uc.owner);
      } else if (uc != null ? uc.email : void 0) {
        tos.push(uc.email);
      }
      if (tos.length === 0) {
        tos = this.copy(bcc);
        bcc = [];
      }
      as = [];
      ref37 = (ref35 = (ref36 = dep.metadata) != null ? ref36.author : void 0) != null ? ref35 : [];
      for (o = 0, len4 = ref37.length; o < len4; o++) {
        author = ref37[o];
        if (author.family) {
          as.push((author.given ? author.given + ' ' : '') + author.family);
        }
      }
      dep.metadata.author = as;
      dep.adminlink = (dep.embedded ? dep.embedded : 'https://shareyourpaper.org' + (dep.metadata.doi ? '/' + dep.metadata.doi : ''));
      dep.adminlink += dep.adminlink.includes('?') ? '&' : '?';
      if (((ref38 = dep.archivable) != null ? ref38.checksum : void 0) != null) {
        dep.confirmed = encodeURIComponent(dep.archivable.checksum);
        dep.adminlink += 'confirmed=' + dep.confirmed + '&';
      }
      if (ref39 = dep.email, indexOf.call(dep.adminlink, ref39) < 0) {
        dep.adminlink += 'email=' + dep.email;
      }
      tmpl = (await this.templates(dep.type + '_deposit'));
      parts = (await this.template(tmpl.content, dep));
      delete dep.adminlink;
      delete dep.confirmed;
      ml = {
        from: 'deposits@oa.works',
        to: tos,
        subject: (ref40 = parts.subject) != null ? ref40 : dep.type + ' deposit',
        html: parts.content
      };
      if (bcc && bcc.length) { // passing undefined to mail seems to cause errors, so only set if definitely exists
        ml.bcc = bcc;
      }
      if (file) {
        ml.attachment = {
          file: file.data,
          filename: (ref41 = (ref42 = (ref43 = dep.archivable) != null ? ref43.name : void 0) != null ? ref42 : file.name) != null ? ref41 : file.filename
        };
      }
      await this.mail(ml);
    }
  }
  // embargo_UI is a legacy value for old embeds, can be removed once we switch to new separate embed repo code
  if (dep.embargo) {
    try {
      dep.embargo_UI = (new Date(dep.embargo)).toLocaleString('en-GB', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
      }).replace(/(11|12|13) /, '$1th ').replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ').replace(/([0-9]) /, '$1th ');
    } catch (error) {}
  }
  return dep;
};

P.deposit._bg = true;

P.archivable = async function(file, url, confirmed, meta, permissions, dev) {
  var _check, f, ref;
  if (dev == null) {
    dev = this.S.dev;
  }
  if (this.request.files) {
    if (file == null) {
      file = this.request.files[0];
    }
  }
  if (Array.isArray(file)) {
    file = file[0];
  }
  f = {
    archivable: void 0,
    archivable_reason: void 0,
    version: 'unknown',
    same_paper: void 0,
    licence: void 0
  };
  _check = async() => {
    var a, af, an, authorsfound, base, content, contentsmall, err, ft, hts, i, inc, ind, j, l, len, len1, len2, lowercontentsmall, lowercontentstart, ls, m, matched, re, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rts, sc, wtm, wts;
    if (typeof meta === 'string' || ((meta == null) && (this.params.doi || this.params.title))) {
      meta = (await this.metadata((ref = meta != null ? meta : this.params.doi) != null ? ref : this.params.title));
    }
    if (meta == null) {
      meta = {};
    }
    
    // handle different sorts of file passing
    if (typeof file === 'string') {
      file = {
        data: file
      };
    }
    if ((file == null) && (url != null)) {
      file = (await this.fetch(url)); // check if this gets file content
    }
    if (file != null) {
      if (file.name == null) {
        file.name = file.filename;
      }
      try {
        f.name = file.name;
      } catch (error) {}
      try {
        f.format = (file.name != null) && file.name.includes('.') ? file.name.split('.').pop() : 'html';
      } catch (error) {}
      f.format = f.format.toLowerCase();
      if (file.data) {
        if ((typeof content === "undefined" || content === null) && (f.format != null) && (this.convert[f.format + '2txt'] != null)) {
          try {
            content = (await this.convert[f.format + '2txt'](file.data));
          } catch (error) {}
        }
        try {
          if (content == null) {
            content = file.data;
          }
        } catch (error) {}
        try {
          content = content.toString();
        } catch (error) {}
      }
    }
    if ((content == null) && !confirmed) {
      if ((file != null) || (url != null)) {
        f.error = (ref1 = file.error) != null ? ref1 : 'Could not extract any content';
      }
    } else {
      contentsmall = content.length < 20000 ? content : content.substring(0, 6000) + content.substring(content.length - 6000, content.length);
      lowercontentsmall = contentsmall.toLowerCase();
      lowercontentstart = (lowercontentsmall.length < 6000 ? lowercontentsmall : lowercontentsmall.substring(0, 6000)).replace(/[^a-z0-9\/]+/g, "");
      if (f.name == null) {
        f.name = meta.title;
      }
      try {
        f.checksum = crypto.createHash('md5').update(content, 'utf8').digest('base64');
      } catch (error) {}
      f.same_paper_evidence = {}; // check if the file meets our expectations
      try {
        f.same_paper_evidence.words_count = content.split(' ').length; // will need to be at least 500 words
      } catch (error) {}
      try {
        f.same_paper_evidence.words_more_than_threshold = f.same_paper_evidence.words_count > 500 ? true : false;
      } catch (error) {}
      try {
        f.same_paper_evidence.doi_match = meta.doi && lowercontentstart.includes(meta.doi.toLowerCase().replace(/[^a-z0-9\/]+/g, "")) ? true : false;
      } catch (error) {}
      try {
        f.same_paper_evidence.title_match = meta.title && lowercontentstart.includes(meta.title.toLowerCase().replace(/[^a-z0-9\/]+/g, "")) ? true : false;
      } catch (error) {}
      if (meta.author != null) {
        try {
          authorsfound = 0;
          f.same_paper_evidence.author_match = false;
          if (typeof meta.author === 'string') {
            // get the surnames out if possible, or author name strings, and find at least one in the doc if there are three or less, or find at least two otherwise
            meta.author = {
              name: meta.author
            };
          }
          if (!Array.isArray(meta.author)) {
            meta.author = [meta.author];
          }
          ref2 = meta.author;
          for (i = 0, len = ref2.length; i < len; i++) {
            a = ref2[i];
            if (f.same_paper_evidence.author_match === true) {
              break;
            } else {
              try {
                an = ((ref3 = (ref4 = (ref5 = (ref6 = a.last) != null ? ref6 : a.lastname) != null ? ref5 : a.family) != null ? ref4 : a.surname) != null ? ref3 : a.name).trim().split(',')[0].split(' ')[0].toLowerCase().replace(/[^a-z0-9\/]+/g, "");
                af = ((ref7 = (ref8 = (ref9 = a.first) != null ? ref9 : a.firstname) != null ? ref8 : a.given) != null ? ref7 : a.name).trim().split(',')[0].split(' ')[0].toLowerCase().replace(/[^a-z0-9\/]+/g, "");
                inc = lowercontentstart.indexOf(an);
                if (an.length > 2 && af.length > 0 && inc !== -1 && lowercontentstart.substring(inc - 20, inc + an.length + 20).includes(af)) {
                  authorsfound += 1;
                  if ((meta.author.length < 3 && authorsfound === 1) || (meta.author.length > 2 && authorsfound > 1)) {
                    f.same_paper_evidence.author_match = true;
                    break;
                  }
                }
              } catch (error) {}
            }
          }
        } catch (error) {}
      }
      if (f.format != null) {
        ref10 = ['doc', 'tex', 'pdf', 'htm', 'xml', 'txt', 'rtf', 'odf', 'odt', 'page'];
        for (j = 0, len1 = ref10.length; j < len1; j++) {
          ft = ref10[j];
          if (f.format.includes(ft)) {
            f.same_paper_evidence.document_format = true;
            break;
          }
        }
      }
      f.same_paper = f.same_paper_evidence.words_more_than_threshold && (f.same_paper_evidence.doi_match || f.same_paper_evidence.title_match || f.same_paper_evidence.author_match) && f.same_paper_evidence.document_format ? true : false;
      if (f.same_paper_evidence.words_count < 150 && f.format === 'pdf') {
        // there was likely a pdf file reading failure due to bad PDF formatting
        f.same_paper_evidence.words_count = 0;
        f.archivable_reason = 'We could not find any text in the provided PDF. It is possible the PDF is a scan in which case text is only contained within images which we do not yet extract. Or, the PDF may have errors in it\'s structure which stops us being able to machine-read it';
      }
      f.version_evidence = {
        score: 0,
        strings_checked: 0,
        strings_matched: []
      };
      try {
        ref11 = (await this.src.google.sheets((dev ? '1XA29lqVPCJ2FQ6siLywahxBTLFaDCZKaN5qUeoTuApg' : '10DNDmOG19shNnuw6cwtCpK-sBnexRCCtD4WnxJx_DPQ')));
        // dev https://docs.google.com/spreadsheets/d/1XA29lqVPCJ2FQ6siLywahxBTLFaDCZKaN5qUeoTuApg/edit#gid=0
        // live https://docs.google.com/spreadsheets/d/10DNDmOG19shNnuw6cwtCpK-sBnexRCCtD4WnxJx_DPQ/edit#gid=0
        for (m = 0, len2 = ref11.length; m < len2; m++) {
          l = ref11[m];
          f.version_evidence.strings_checked += 1;
          wts = l['what to search'];
          rts = l['where to search'];
          hts = l['how to search'];
          ind = l['what it Indicates'];
          try {
            if (wts.includes('<<') && wts.includes('>>')) {
              wtm = wts.split('<<')[1].split('>>')[0];
              if (meta[wtm.toLowerCase()] != null) {
                wts = wts.replace('<<' + wtm + '>>', meta[wtm.toLowerCase()]);
              }
            }
            matched = false;
            if (hts === 'string') {
              matched = (rts === 'file' && contentsmall.includes(wts)) || (rts !== 'file' && (((meta.title != null) && meta.title.includes(wts)) || ((f.name != null) && f.name.includes(wts)))) ? true : false;
            } else {
              re = new RegExp(wts, 'gium');
              matched = (rts === 'file' && lowercontentsmall.match(re) !== null) || (rts !== 'file' && (((meta.title != null) && meta.title.match(re) !== null) || ((f.name != null) && f.name.match(re) !== null))) ? true : false;
            }
            if (matched) {
              sc = l.value;
              if (typeof sc === 'string') {
                try {
                  sc = parseInt(sc);
                } catch (error) {}
              }
              if (typeof sc !== 'number') {
                sc = 1;
              }
              if (ind && ((ref12 = ind.toLowerCase()) === 'publisher pdf' || ref12 === 'publishedversion')) {
                f.version_evidence.score += sc;
              } else {
                f.version_evidence.score -= sc;
              }
              f.version_evidence.strings_matched.push({
                indicates: ind,
                found: hts + ' ' + wts,
                in: rts,
                score_value: sc
              });
            }
          } catch (error) {
            err = error;
            if ((base = f.version_evidence).strings_errored == null) {
              base.strings_errored = [];
            }
            f.version_evidence.strings_errored.push({
              tried: hts + ' ' + wts,
              in: rts,
              error: err.toString()
            });
          }
        }
      } catch (error) {}
      if (f.version_evidence.score > 0) {
        f.version = 'publishedVersion';
      }
      if (f.version_evidence.score < 0) {
        f.version = 'acceptedVersion';
      }
      if (f.version === 'unknown' && f.version_evidence.strings_checked > 0) { //and f.format? and f.format isnt 'pdf'
        f.version = 'acceptedVersion';
      }
      try {
        ls = (await this.licence(void 0, lowercontentsmall)); // check for licence info in the file content
        if ((ls != null ? ls.licence : void 0) != null) {
          f.licence = ls.licence;
          f.licence_evidence = ls;
        }
      } catch (error) {}
      f.archivable = false;
      if (confirmed) {
        f.archivable = true;
        if (confirmed === f.checksum) {
          f.archivable_reason = 'The administrator has confirmed that this file is a version that can be archived.';
          f.admin_confirms = true;
        } else {
          f.archivable_reason = 'The depositor says that this file is a version that can be archived';
          f.depositor_says = true;
        }
      } else if (f.same_paper) {
        if (f.format !== 'pdf') {
          f.archivable = true;
          f.archivable_reason = 'Since the file is not a PDF, we assume it is an accepted version';
        }
        if (!f.archivable && (f.licence != null) && f.licence.toLowerCase().startsWith('cc')) {
          f.archivable = true;
          f.archivable_reason = 'It appears this file contains a ' + f.licence + ' licence statement. Under this licence the article can be archived';
        }
        if (!f.archivable) {
          if (f.version) {
            if ((meta != null) && JSON.stringify(meta) !== '{}') {
              if (permissions == null) {
                permissions = (await this.permissions(meta));
              }
            }
            if (f.version === (permissions != null ? (ref13 = permissions.best_permission) != null ? ref13.version : void 0 : void 0)) {
              f.archivable = true;
              f.archivable_reason = 'We believe this is a ' + f.version.split('V')[0] + ' version and our permission system says that version can be shared';
            } else {
              if (f.archivable_reason == null) {
                f.archivable_reason = 'We believe this file is a ' + f.version.split('V')[0] + ' version and our permission system does not list that as an archivable version';
              }
            }
          } else {
            f.archivable_reason = 'We cannot confirm if it is an archivable version or not';
          }
        }
      } else {
        if (f.archivable_reason == null) {
          f.archivable_reason = !f.same_paper_evidence.words_more_than_threshold ? 'The file is less than 500 words, and so does not appear to be a full article' : !f.same_paper_evidence.document_format ? 'File is an unexpected format ' + f.format : !meta.doi && !meta.title ? 'We have insufficient metadata to validate file is for the correct paper ' : 'File does not contain expected metadata such as DOI or title';
        }
      }
    }
    if (f.archivable && (f.licence == null)) {
      if (permissions != null ? (ref14 = permissions.best_permission) != null ? ref14.licence : void 0 : void 0) {
        f.licence = permissions.best_permission.licence;
      } else if (((ref15 = permissions != null ? (ref16 = permissions.best_permission) != null ? ref16.deposit_statement : void 0 : void 0) != null ? ref15 : '').toLowerCase().startsWith('cc')) {
        f.licence = permissions.best_permission.deposit_statement;
      }
    }
    return f.metadata = meta;
  };
  _check();
  setTimeout((() => {
    return f.timeout = true;
  }), (ref = this.params.timeout) != null ? ref : 60000);
  while ((f.archivable == null) && !f.timeout) {
    await this.sleep(500);
  }
  return f;
};

P.archivable._bg = true;

`P.deposited = () ->
  uid ?= @params.uid ? @user.id
  params = await @copy @params
  restrict = [{exists:{field:'deposit.type'}}]
  restrict.push({term:{'deposit.from.exact':uid}}) if uid
  restrict.push({exists:{field:'deposit.zenodo.url'}}) if @params.submitted # means filter to only those that are actually deposited, not just records of a deposit occurring
  params.size ?= 10000
  params.sort ?= 'createdAt:asc'
  fields = ['metadata','permissions.permissions','permissions.ricks','permissions.best_permission','permissions.file','deposit','url']
  if params.fields
    fields = params.fields.split ','
    delete params.fields
  res = oab_catalogue.search params, {restrict:restrict}
  re = []
  for r in res.hits.hits
    dr = r._source
    if csv and dr.metadata?.reference?
      delete dr.metadata.reference
    if csv and dr.error
      try
        dr.error = dr.error.split(':')[0].split('{')[0].trim()
      catch
        delete dr.error
    if csv and dr.metadata?.author?
      for a of dr.metadata.author
        dr.metadata.author[a] = if dr.metadata.author[a].name then dr.metadata.author[a].name else if dr.metadata.author[a].given and dr.metadata.author[a].family then dr.metadata.author[a].given + ' ' + dr.metadata.author[a].family else ''
    for d in dr.deposit
      if (not uid? or d.from is uid) and (not @params.submitted or d.zenodo?.file?)
        red = {doi: dr.metadata.doi, title: dr.metadata.title, type: d.type, createdAt: d.createdAt}
        already = false
        if @params.submitted
          red.file = d.zenodo.file
          for ad in re
            if ad.doi is red.doi and ad.file is red.file
              already = true
              break
        if not already
          for f in fields
            if f not in ['metadata.doi','metadata.title','deposit.type','deposit.createdAt','metadata.reference']
              if f is 'deposit'
                red[f] = d
              else
                red[f] = API.collection.dot dr, f
          re.push red
  if params.sort is 'createdAt:asc'
    re = _.sortBy re, 'createdAt'
  if 'deposit.createdAt' not in fields
    for dr in re
      delete dr.createdAt
  if @format is 'csv'
    for f of re
      re[f] = API.collection.flatten re[f]
  return re`;

`P.deposit.config = (user, config) -> # should require an authorised user
  if not config? and @body?
    config = @body
    config[o] ?= @params[o] for o of @params
  if config.uid and await @auth 'openaccessbutton.admin', @user
    user = @users._get config.uid
    delete config.uid
  else
    user = @user
  user ?= @params.uid ? @user.id ? @params.url
  if typeof user is 'string' and user.includes '.' # user is actually url where an embed has been called from
    try
      res = oab_find.search q
      res = oab_find.search 'plugin.exact:shareyourpaper AND config:* AND embedded:"' + user.split('?')[0].split('#')[0] + '"'
      return JSON.parse res.hits.hits[0]._source.config
    catch
      return {}
  else
    user = @users._get(user) if typeof user is 'string'
    user ?= @user
    if typeof user is 'object' and config?
      # ['depositdate','community','institution_name','repo_name','email_domains','terms','old_way','deposit_help','email_for_manual_review','file_review_time','if_no_doi_go_here','email_for_feedback','sayarticle','oa_deposit_off','library_handles_dark_deposit_requests','dark_deposit_off','ror','live','pilot','activate_try_it_and_learn_more','not_library']
      config.pilot = Date.now() if config.pilot is true
      config.live = Date.now() if config.live is true
      try config.community = config.community.split('communities/')[1].split('/')[0] if typeof config.community is 'string' and config.community.includes 'communities/'
      delete config.autorunparams if config.autorunparams is false
      if JSON.stringify(config).indexOf('<script') is -1
        if not user.service?
          @users._update user._id, {service: {openaccessbutton: {deposit: {config: config}}}}
        else if not user.service.openaccessbutton?
          @users._update user._id, {'service.openaccessbutton': {deposit: {config: config}}}
        else if not user.service.openaccessbutton.deposit?
          @users._update user._id, {'service.openaccessbutton.deposit': {config: config}}
        else
          upd = {'service.openaccessbutton.deposit.config': config}
          if user.service.openaccessbutton.deposit.config? and not user.service.openaccessbutton.deposit.old_config? and user.service.openaccessbutton.deposit.had_old isnt false
            upd['service.openaccessbutton.deposit.old_config'] = user.service.openaccessbutton.deposit.config
          @users._update user._id, upd
    try
      config ?= user.service.openaccessbutton.deposit?.config ? {}
      try config.owner ?= user.email ? user.emails[0].address
      return config
    catch
      return {}`;

`P.deposit.url = (uid) ->
  # given a uid, find the most recent URL that this users uid submitted a deposit for
  uid ?= @params.uid ? @user?.id
  q = {size: 0, query: {filtered: {query: {bool: {must: [{term: {plugin: "shareyourpaper"}},{term: {"from.exact": uid}}]}}}}}
  q.aggregations = {embeds: {terms: {field: "embedded.exact"}}}
  res = oab_find.search q
  for eu in res.aggregations.embeds.buckets
    eur = eu.key.split('?')[0].split('#')[0]
    if eur.indexOf('shareyourpaper.org') is -1 and eur.indexOf('openaccessbutton.org') is -1
      return eur
  return false`;

var indexOf = [].indexOf;

P.metadata = async function(doi) {
  var res;
  res = (await this.find(doi)); // may not be a DOI, but most likely thing
  return res != null ? res.metadata : void 0;
};

P.metadata._log = false;

P.find = async function(options, metadata = {}, content) {
  var _ill, _metadata, _permissions, _searches, dd, dps, epmc, i, len, mag, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, res, uo;
  res = {};
  _metadata = async(input) => {
    var ct, k;
    ct = (await this.citation(input));
    for (k in ct) {
      if (k === 'url' || k === 'paywall') {
        if (res[k] == null) {
          res[k] = ct[k];
        }
      } else {
        if (metadata[k] == null) {
          metadata[k] = ct[k];
        }
      }
    }
    return true;
  };
  if (typeof options === 'string') {
    options = options.split('doi.org/').pop().startsWith('10.') ? {
      doi: options
    } : {
      title: options
    };
  }
  try {
    if (options == null) {
      options = this.copy(this.params);
    }
  } catch (error) {}
  if (options == null) {
    options = {};
  }
  if (content == null) {
    content = (ref = options.dom) != null ? ref : (typeof this.body === 'string' ? this.body : void 0);
  }
  if (options.metadata) {
    options.find = options.metadata;
  }
  if (options.find) {
    if (options.find.startsWith('10.') && options.find.includes('/')) {
      options.doi = options.find;
    } else {
      options.url = options.find;
    }
    delete options.find;
  }
  if (options.url == null) {
    options.url = (ref1 = options.q) != null ? ref1 : options.id;
  }
  if (options.url) {
    if (typeof options.url === 'number') {
      options.url = options.url.toString();
    }
    if (options.url.startsWith('/10.')) {
      // we don't use a regex to try to pattern match a DOI because people often make mistakes typing them, so instead try to find one
      // in ways that may still match even with different expressions (as long as the DOI portion itself is still correct after extraction we can match it)
      dd = '10.' + options.url.split('/10.')[1].split('&')[0].split('#')[0];
      if (dd.includes('/') && dd.split('/')[0].length > 6 && dd.length > 8) {
        dps = dd.split('/');
        if (dps.length > 2) {
          dd = dps.join('/');
        }
        if (metadata.doi == null) {
          metadata.doi = dd;
        }
      }
    }
    if (options.url.replace('doi:', '').replace('doi.org/', '').trim().startsWith('10.')) {
      if (metadata.doi == null) {
        metadata.doi = options.url.replace('doi:', '').replace('doi.org/', '').trim();
      }
      options.url = 'https://doi.org/' + metadata.doi;
    } else if (options.url.toLowerCase().startsWith('pmc')) {
      if (metadata.pmcid == null) {
        metadata.pmcid = options.url.toLowerCase().replace('pmcid', '').replace('pmc', '');
      }
      options.url = 'http://europepmc.org/articles/PMC' + metadata.pmcid;
    } else if (options.url.replace(/pmid/i, '').replace(':', '').length < 10 && options.url.includes('.') && !isNaN(parseInt(options.url.replace(/pmid/i, '').replace(':', '').trim()))) {
      if (metadata.pmid == null) {
        metadata.pmid = options.url.replace(/pmid/i, '').replace(':', '').trim();
      }
      options.url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + metadata.pmid;
    } else if ((metadata.title == null) && !options.url.startsWith('http')) {
      if (options.url.includes('{') || ((ref2 = options.url.replace('...', '').match(/\./gi)) != null ? ref2 : []).length > 3 || ((ref3 = options.url.match(/\(/gi)) != null ? ref3 : []).length > 2) {
        options.citation = options.url;
      } else {
        metadata.title = options.url;
      }
    }
    if (!options.url.startsWith('http') || !options.url.includes('.')) {
      delete options.url;
    }
  }
  if (typeof options.title === 'string' && (options.title.includes('{') || ((ref4 = options.title.replace('...', '').match(/\./gi)) != null ? ref4 : []).length > 3 || ((ref5 = options.title.match(/\(/gi)) != null ? ref5 : []).length > 2)) {
    options.citation = options.title; // titles that look like citations
    delete options.title;
  }
  if (options.doi) {
    options.doi = (await this.decode(options.doi));
  }
  if (metadata.doi == null) {
    metadata.doi = options.doi;
  }
  if (metadata.title == null) {
    metadata.title = options.title;
  }
  if (metadata.pmid == null) {
    metadata.pmid = options.pmid;
  }
  if (metadata.pmcid == null) {
    metadata.pmcid = (ref6 = options.pmcid) != null ? ref6 : options.pmc;
  }
  if (options.citation) {
    await _metadata(options.citation);
  }
  try {
    metadata.title = metadata.title.replace(/(<([^>]+)>)/g, '').replace(/\+/g, ' ').trim();
  } catch (error) {}
  try {
    metadata.title = (await this.decode(metadata.title));
  } catch (error) {}
  try {
    metadata.doi = metadata.doi.split(' ')[0].replace('http://', '').replace('https://', '').replace('doi.org/', '').replace('doi:', '').trim();
  } catch (error) {}
  if (typeof metadata.doi !== 'string' || !metadata.doi.startsWith('10.')) {
    delete metadata.doi;
  }
  // switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if (!metadata.title && content && typeof options.url === 'string' && (options.url.includes('alma.exlibrisgroup.com') || options.url.includes('/exlibristest'))) {
    delete options.url;
  }
  if (options.demo != null) {
    // set a demo tag in certain cases
    // e.g. for instantill/shareyourpaper/other demos - dev and live demo accounts
    res.demo = options.demo;
  }
  if ((metadata.doi === '10.1234/567890' || ((metadata.doi != null) && metadata.doi.startsWith('10.1234/oab-syp-'))) || metadata.title === 'Engineering a Powerfully Simple Interlibrary Loan Experience with InstantILL' || ((ref7 = options.from) === 'qZooaHWRz9NLFNcgR' || ref7 === 'eZwJ83xp3oZDaec86')) {
    if (res.demo == null) {
      res.demo = true;
    }
  }
  if (res.demo) { // don't save things coming from the demo accounts into the catalogue later
    if (res.test == null) {
      res.test = true;
    }
  }
  epmc = false;
  mag = false;
  _searches = async() => {
    var _crd, _oad, cr, ref8, scraped;
    if (((content != null) || (options.url != null)) && !(metadata.doi || (metadata.pmid != null) || (metadata.pmcid != null) || (metadata.title != null))) {
      scraped = (await this.scrape(content != null ? content : options.url));
      await _metadata(scraped);
    }
    if (!metadata.doi) {
      if (metadata.pmid || metadata.pmcid) {
        epmc = (await this.src.epmc[metadata.pmcid ? 'pmc' : 'pmid']((ref8 = metadata.pmcid) != null ? ref8 : metadata.pmid));
        await _metadata(epmc);
      }
      if (!metadata.doi && metadata.title && metadata.title.length > 8 && metadata.title.split(' ').length > 1) {
        metadata.title = metadata.title.replace(/\+/g, ' '); // some+titles+come+in+like+this
        cr = (await this.src.crossref.works.title(metadata.title));
        if ((cr != null ? cr.type : void 0) && (cr != null ? cr.DOI : void 0)) {
          await _metadata(cr);
        }
        //if not metadata.doi
        //  mag = await @src.microsoft.graph metadata.title
        //  await _metadata(mag) if mag isnt false and mag?.PaperTitle
        if (!metadata.doi && !epmc) {
          epmc = (await this.src.epmc.title(metadata.title));
          if (epmc !== false) {
            await _metadata(epmc);
          }
        }
      }
    }
    if (metadata.doi) {
      _oad = async() => {
        var oad;
        oad = (await this.src.oadoi(metadata.doi));
        if (oad == null) {
          res.doi_not_in_oadoi = metadata.doi;
        }
        if ((oad != null ? oad.doi : void 0) && (metadata != null ? metadata.doi : void 0) && oad.doi.toLowerCase() === metadata.doi.toLowerCase()) { // check again for doi in case removed by failed crossref lookup
          await _metadata(oad);
        }
        return true;
      };
      _crd = async() => {
        cr = (await this.src.crossref.works(metadata.doi));
        if (cr == null) {
          cr = (await this.src.crossref.works.doi(metadata.doi));
        }
        if (!(cr != null ? cr.type : void 0)) {
          res.doi_not_in_crossref = metadata.doi;
        } else {
          try {
            // temporary fix of date info until crossref index reloaded
            cr.published = (await this.src.crossref.works.published(cr));
            try {
              cr.year = cr.published.split('-')[0];
            } catch (error) {}
            try {
              cr.year = parseInt(cr.year);
            } catch (error) {}
            try {
              cr.publishedAt = (await this.epoch(cr.published));
            } catch (error) {}
          } catch (error) {}
          await _metadata(cr);
        }
        return true;
      };
      await Promise.all([_oad(), _crd()]);
    }
    return true;
  };
  await _searches();
  // if nothing useful can be found and still only have title try using bing - or drop this ability?
  //  if mag isnt false and not metadata.doi and not content and not options.url and not epmc and metadata.title and metadata.title.length > 8 and metadata.title.split(' ').length > 1
  //    mct = metadata.title.toLowerCase().replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ') # this previously had a unidecode on it...
  //    bong = await @src.microsoft.bing mct
  //    if bong?.data and bong.data.length
  //      bct = bong.data[0].name.toLowerCase().replace('(pdf)', '').replace(/[^a-z0-9 ]+/g, ' ').replace(/\s\s+/g, ' ') # this had unidecode to match to above...
  //      if mct.replace(/ /g, '').startsWith bct.replace(/ /g, '') #and not await @blacklist bong.data[0].url
  //        # if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
  //        options.url = bong.data[0].url.replace /"/g, ''
  //        metadata.pmid = options.url.replace(/\/$/,'').split('/').pop() if typeof options.url is 'string' and options.url.includes 'pubmed.ncbi'
  //        metadata.doi ?= '10.' + options.url.split('/10.')[1] if typeof options.url is 'string' and options.url.includes '/10.'
  //    if metadata.doi or metadata.pmid or options.url
  //      await _searches() # run again if anything more useful found
  _ill = async() => {
    var ref8;
    if ((metadata.doi || (metadata.title && metadata.title.length > 8 && metadata.title.split(' ').length > 1)) && (options.from || (options.config != null)) && (options.plugin === 'instantill' || options.ill === true)) {
      try {
        if (res.ill == null) {
          res.ill = {
            subscription: (await this.ill.subscription((ref8 = options.config) != null ? ref8 : options.from, metadata))
          };
        }
      } catch (error) {}
    }
    return true;
  };
  _permissions = async() => {
    var ref8;
    if (metadata.doi && (options.permissions || options.plugin === 'shareyourpaper')) {
      if (res.permissions == null) {
        res.permissions = (await this.permissions(metadata, (ref8 = options.config) != null ? ref8.ror : void 0, false));
      }
    }
    return true;
  };
  await Promise.all([_ill(), _permissions()]);
  ref8 = ['title', 'journal', 'year', 'doi'];
  // certain user-provided search values are allowed to override any that we could find ourselves
  // TODO is this ONLY relevant to ILL? or anything else?
  for (i = 0, len = ref8.length; i < len; i++) {
    uo = ref8[i];
    if (options[uo] && options[uo] !== metadata[uo]) {
      metadata[uo] = options[uo];
    }
  }
  res.metadata = metadata; // if JSON.stringify(metadata) isnt '{}'
  return res;
};

// Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
// Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.citation = function(citation) {
  var a, aff, ak, au, bt, cf, clc, cn, i, j, k, key, l, len, len1, len2, len3, len4, len5, len6, len7, len8, len9, m, mn, n, o, p, pt, pts, q, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref38, ref39, ref4, ref40, ref41, ref42, ref43, ref44, ref45, ref46, ref47, ref48, ref49, ref5, ref50, ref51, ref52, ref53, ref54, ref55, ref56, ref57, ref6, ref7, ref8, ref9, res, rmn, rt, s, sy, t, u, v;
  res = {};
  try {
    if (citation == null) {
      citation = (ref = this.params.citation) != null ? ref : this.params;
    }
  } catch (error) {}
  if (typeof citation === 'string' && (citation.startsWith('{') || citation.startsWith('['))) {
    try {
      citation = JSON.parse(citation);
    } catch (error) {}
  }
  if (typeof citation === 'object') {
    res.doi = (ref1 = citation.DOI) != null ? ref1 : citation.doi;
    if (citation.pmid) {
      res.pmid = citation.pmid;
    }
    if (citation.pmcid) {
      res.pmcid = citation.pmcid;
    }
    try {
      res.type = (ref2 = citation.type) != null ? ref2 : citation.genre;
    } catch (error) {}
    if (res.issn == null) {
      res.issn = (ref3 = (ref4 = (ref5 = citation.ISSN) != null ? ref5 : citation.issn) != null ? ref4 : (ref6 = citation.journalInfo) != null ? (ref7 = ref6.journal) != null ? ref7.issn : void 0 : void 0) != null ? ref3 : (ref8 = citation.journal) != null ? ref8.issn : void 0;
    }
    if (((ref9 = citation.journalInfo) != null ? (ref10 = ref9.journal) != null ? ref10.eissn : void 0 : void 0) != null) {
      if (res.issn == null) {
        res.issn = [];
      }
      if (typeof res.issn === 'string') {
        res.issn = [res.issn];
      }
      res.issn.push(citation.journalInfo.journal.eissn);
    }
    if (citation.journal_issns) {
      if (res.issn == null) {
        res.issn = citation.journal_issns.split(',');
      }
    }
    try {
      if (Array.isArray(citation.title)) {
        if (res.title == null) {
          res.title = citation.title[0];
        }
      }
    } catch (error) {}
    try {
      if ((citation.subtitle != null) && citation.subtitle.length && citation.subtitle[0].length) {
        res.title += ': ' + citation.subtitle[0];
      }
    } catch (error) {}
    if (res.title == null) {
      res.title = (ref11 = citation.dctitle) != null ? ref11 : (ref12 = citation.bibjson) != null ? ref12.title : void 0;
    }
    if ((ref13 = citation.title) !== 404 && ref13 !== '404') {
      if (res.title == null) {
        res.title = citation.title;
      }
    }
    if (typeof res.title === 'string') {
      res.title = res.title.replace(/\s\s+/g, ' ').trim();
    }
    try {
      if (res.journal == null) {
        res.journal = citation['container-title'][0];
      }
    } catch (error) {}
    try {
      res.shortname = citation['short-container-title'][0];
    } catch (error) {}
    try {
      res.shortname = (ref14 = citation.journalInfo.journal.isoabbreviation) != null ? ref14 : citation.journalInfo.journal.medlineAbbreviation;
    } catch (error) {}
    if (res.shortname && !res.journal_short) { // temporary fix for change to metadata field name
      res.journal_short = res.shortname;
    }
    if (res.journal == null) {
      res.journal = (ref15 = (ref16 = citation.journal_name) != null ? ref16 : (ref17 = citation.journalInfo) != null ? (ref18 = ref17.journal) != null ? ref18.title : void 0 : void 0) != null ? ref15 : (ref19 = citation.journal) != null ? ref19.title : void 0;
    }
    if (citation.journal) {
      res.journal = citation.journal.split('(')[0].trim();
    }
    try {
      ref20 = ['title', 'journal'];
      for (i = 0, len = ref20.length; i < len; i++) {
        key = ref20[i];
        res[key] = res[key].charAt(0).toUpperCase() + res[key].slice(1);
      }
    } catch (error) {}
    if (res.publisher == null) {
      res.publisher = citation.publisher;
    }
    if (res.publisher) {
      res.publisher = res.publisher.trim();
    }
    try {
      if (citation.issue != null) {
        if (res.issue == null) {
          res.issue = citation.issue;
        }
      }
    } catch (error) {}
    try {
      if ((ref21 = citation.journalInfo) != null ? ref21.issue : void 0) {
        if (res.issue == null) {
          res.issue = citation.journalInfo.issue;
        }
      }
    } catch (error) {}
    try {
      if (citation.volume != null) {
        if (res.volume == null) {
          res.volume = citation.volume;
        }
      }
    } catch (error) {}
    try {
      if ((ref22 = citation.journalInfo) != null ? ref22.volume : void 0) {
        if (res.volume == null) {
          res.volume = citation.journalInfo.volume;
        }
      }
    } catch (error) {}
    try {
      if (citation.page != null) {
        if (res.page == null) {
          res.page = citation.page.toString();
        }
      }
    } catch (error) {}
    if (citation.pageInfo) {
      res.page = citation.pageInfo.toString();
    }
    if (citation.abstract || citation.abstractText) {
      res.abstract = (ref23 = citation.abstract) != null ? ref23 : citation.abstractText;
    }
    ref24 = ['published-print', 'journal-issue.published-print', 'journalInfo.printPublicationDate', 'firstPublicationDate', 'journalInfo.electronicPublicationDate', 'published', 'published_date', 'issued', 'published-online', 'created', 'deposited'];
    for (j = 0, len1 = ref24.length; j < len1; j++) {
      p = ref24[j];
      if (typeof res.published !== 'string') {
        if (rt = (ref25 = (ref26 = citation[p]) != null ? ref26 : (ref27 = citation['journal-issue']) != null ? ref27[p.replace('journal-issue.', '')] : void 0) != null ? ref25 : (ref28 = citation['journalInfo']) != null ? ref28[p.replace('journalInfo.', '')] : void 0) {
          if (typeof rt === 'number') {
            rt = rt.toString();
          }
          try {
            if (typeof rt !== 'string') {
              rt = rt['date-time'].toString();
            }
          } catch (error) {}
          if (typeof rt !== 'string') {
            try {
              for (k in rt['date-parts'][0]) {
                if ((ref29 = typeof rt['date-parts'][0][k]) !== 'number' && ref29 !== 'string') {
                  rt['date-parts'][0][k] = '01';
                }
              }
              rt = rt['date-parts'][0].join('-');
            } catch (error) {}
          }
          if (typeof rt === 'string') {
            res.published = rt.includes('T') ? rt.split('T')[0] : rt;
            res.published = res.published.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace(/-(\d)$/, "-0$1");
            if (!res.published.includes('-')) {
              res.published += '-01';
            }
            if (res.published.split('-').length !== 3) {
              res.published += '-01';
            }
            if (res.year == null) {
              res.year = res.published.split('-')[0];
            }
            if (res.published.split('-').length !== 3) {
              delete res.published;
            }
            if (res.year.toString().length !== 4) {
              delete res.year;
            }
          }
        }
        if (res.published) {
          break;
        }
      }
    }
    if (citation.year) {
      if (res.year == null) {
        res.year = citation.year;
      }
    }
    try {
      if (res.year == null) {
        res.year = citation.journalInfo.yearOfPublication.trim();
      }
    } catch (error) {}
    if ((res.author == null) && ((citation.author != null) || (citation.z_authors != null) || ((ref30 = citation.authorList) != null ? ref30.author : void 0))) {
      if (res.author == null) {
        res.author = [];
      }
      try {
        ref33 = (ref31 = (ref32 = citation.author) != null ? ref32 : citation.z_authors) != null ? ref31 : citation.authorList.author;
        for (n = 0, len2 = ref33.length; n < len2; n++) {
          a = ref33[n];
          if (typeof a === 'string') {
            res.author.push({
              name: a
            });
          } else {
            au = {};
            au.given = (ref34 = a.given) != null ? ref34 : a.firstName;
            au.family = (ref35 = a.family) != null ? ref35 : a.lastName;
            au.name = (au.given ? au.given + ' ' : '') + ((ref36 = au.family) != null ? ref36 : '');
            if (a.affiliation != null) {
              try {
                ref37 = (au.affiliation ? (Array.isArray(a.affiliation) ? a.affiliation : [a.affiliation]) : au.authorAffiliationDetailsList.authorAffiliation);
                for (o = 0, len3 = ref37.length; o < len3; o++) {
                  aff = ref37[o];
                  if (typeof aff === 'string') {
                    if (au.affiliation == null) {
                      au.affiliation = [];
                    }
                    au.affiliation.push({
                      name: aff.replace(/\s\s+/g, ' ').trim()
                    });
                  } else if (typeof aff === 'object' && (aff.name || aff.affiliation)) {
                    if (au.affiliation == null) {
                      au.affiliation = [];
                    }
                    au.affiliation.push({
                      name: ((ref38 = aff.name) != null ? ref38 : aff.affiliation).replace(/\s\s+/g, ' ').trim()
                    });
                  }
                }
              } catch (error) {}
            }
            res.author.push(au);
          }
        }
      } catch (error) {}
    }
    try {
      if ((citation.subject != null) && citation.subject.length && typeof citation.subject[0] === 'string') {
        res.subject = citation.subject;
      }
    } catch (error) {}
    try {
      if ((((ref39 = citation.keywordList) != null ? ref39.keyword : void 0) != null) && citation.keywordList.keyword.length && typeof citation.keywordList.keyword[0] === 'string') {
        res.keyword = citation.keywordList.keyword;
      }
    } catch (error) {}
    try {
      ref44 = [...((ref40 = (ref41 = citation.meshHeadingList) != null ? ref41.meshHeading : void 0) != null ? ref40 : []), ...((ref42 = (ref43 = citation.chemicalList) != null ? ref43.chemical : void 0) != null ? ref42 : [])];
      for (q = 0, len4 = ref44.length; q < len4; q++) {
        m = ref44[q];
        if (res.keyword == null) {
          res.keyword = [];
        }
        mn = typeof m === 'string' ? m : (ref45 = m.name) != null ? ref45 : m.descriptorName;
        if (typeof mn === 'string' && mn && indexOf.call(res.keyword, mn) < 0) {
          res.keyword.push(mn);
        }
      }
    } catch (error) {}
    if (typeof citation.license === 'string') {
      res.licence = citation.license.trim().replace(/ /g, '-');
    }
    if (typeof citation.licence === 'string') {
      res.licence = citation.licence.trim().replace(/ /g, '-');
    }
    try {
      if (((ref46 = citation.best_oa_location) != null ? ref46.license : void 0) && ((ref47 = citation.best_oa_location) != null ? ref47.license : void 0) !== null) {
        if (res.licence == null) {
          res.licence = citation.best_oa_location.license;
        }
      }
    } catch (error) {}
    if (!res.licence) {
      if (Array.isArray(citation.assertion)) {
        ref48 = citation.assertion;
        for (r = 0, len5 = ref48.length; r < len5; r++) {
          a = ref48[r];
          if (a.label === 'OPEN ACCESS' && a.URL && a.URL.includes('creativecommons')) {
            if (res.licence == null) {
              res.licence = a.URL; // and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
            }
          }
        }
      }
      if (Array.isArray(citation.license)) {
        ref50 = (ref49 = citation.license) != null ? ref49 : [];
        for (s = 0, len6 = ref50.length; s < len6; s++) {
          l = ref50[s];
          if (l.URL && l.URL.includes('creativecommons') && (!res.licence || !res.licence.includes('creativecommons'))) {
            if (res.licence == null) {
              res.licence = l.URL;
            }
          }
        }
      }
    }
    if (typeof res.licence === 'string' && res.licence.includes('/licenses/')) {
      res.licence = 'cc-' + res.licence.split('/licenses/')[1].replace(/$\//, '').replace(/\//g, '-').replace(/-$/, '');
    }
    // if there is a URL to use but not open, store it as res.paywall
    if (res.url == null) {
      res.url = (ref51 = (ref52 = citation.best_oa_location) != null ? ref52.url_for_pdf : void 0) != null ? ref51 : (ref53 = citation.best_oa_location) != null ? ref53.url : void 0; //? citation.url # is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?
    }
    if (!res.url && (((ref54 = citation.fullTextUrlList) != null ? ref54.fullTextUrl : void 0) != null)) { // epmc fulltexts
      ref55 = citation.fullTextUrlList.fullTextUrl;
      for (t = 0, len7 = ref55.length; t < len7; t++) {
        cf = ref55[t];
        if (((ref56 = cf.availabilityCode.toLowerCase()) === 'oa' || ref56 === 'f') && (!res.url || (cf.documentStyle === 'pdf' && !res.url.includes('pdf')))) {
          res.url = cf.url;
        }
      }
    }
  } else if (typeof citation === 'string') {
    try {
      citation = citation.replace(/citation\:/gi, '').trim();
      if (citation.includes('title')) {
        citation = citation.split('title')[1].trim();
      }
      citation = citation.replace(/^"/, '').replace(/^'/, '').replace(/"$/, '').replace(/'$/, '');
      if (citation.includes('doi:')) {
        res.doi = citation.split('doi:')[1].split(',')[0].split(' ')[0].trim();
      }
      if (citation.includes('doi.org/')) {
        res.doi = citation.split('doi.org/')[1].split(',')[0].split(' ')[0].trim();
      }
      if (!res.doi && citation.includes('http')) {
        res.url = 'http' + citation.split('http')[1].split(' ')[0].trim();
      }
      try {
        if (citation.includes('|') || citation.includes('}')) {
          res.title = citation.split('|')[0].split('}')[0].trim();
        }
        if (citation.split('"').length > 2) {
          res.title = citation.split('"')[1].trim();
        } else if (citation.split("'").length > 2) {
          if (res.title == null) {
            res.title = citation.split("'")[1].trim();
          }
        }
      } catch (error) {}
      try {
        pts = citation.replace(/,\./g, ' ').split(' ');
        for (u = 0, len8 = pts.length; u < len8; u++) {
          pt = pts[u];
          if (!res.year) {
            pt = pt.replace(/[^0-9]/g, '');
            if (pt.length === 4) {
              sy = parseInt(pt);
              if (typeof sy === 'number' && !isNaN(sy)) {
                res.year = sy;
              }
            }
          }
        }
      } catch (error) {}
      try {
        if (!res.title && res.year && citation.indexOf(res.year) < (citation.length / 4)) {
          res.title = citation.split(res.year)[1].trim();
          if (!res.title.includes('(') || res.title.indexOf(')') < res.title.indexOf('(')) {
            res.title = res.title.replace(')', '');
          }
          if (res.title.indexOf('.') < 3) {
            res.title = res.title.replace('.', '');
          }
          if (res.title.indexOf(',') < 3) {
            res.title = res.title.replace(',', '');
          }
          res.title = res.title.trim();
          if (res.title.includes('.')) {
            res.title = res.title.split('.')[0];
          } else if (res.title.includes(',')) {
            res.title = res.title.split(',')[0];
          }
        }
      } catch (error) {}
      if (res.title) {
        try {
          bt = citation.split(res.title)[0];
          if (res.year && bt.includes(res.year)) {
            bt = bt.split(res.year)[0];
          }
          if (res.url && bt.indexOf(res.url) > 0) {
            bt = bt.split(res.url)[0];
          }
          if (res.url && bt.startsWith(res.url)) {
            bt = bt.replace(res.url);
          }
          if (res.doi && bt.startsWith(res.doi)) {
            bt = bt.replace(res.doi);
          }
          if (bt.indexOf('.') < 3) {
            bt = bt.replace('.', '');
          }
          if (bt.indexOf(',') < 3) {
            bt = bt.replace(',', '');
          }
          if (bt.lastIndexOf('(') > (bt.length - 3)) {
            bt = bt.substring(0, bt.lastIndexOf('('));
          }
          if (bt.lastIndexOf(')') > (bt.length - 3)) {
            bt = bt.substring(0, bt.lastIndexOf(')'));
          }
          if (bt.lastIndexOf(',') > (bt.length - 3)) {
            bt = bt.substring(0, bt.lastIndexOf(','));
          }
          if (bt.lastIndexOf('.') > (bt.length - 3)) {
            bt = bt.substring(0, bt.lastIndexOf('.'));
          }
          bt = bt.trim();
          if (bt.length > 6) {
            if (bt.includes(',')) {
              res.author = [];
              ref57 = bt.split(',');
              for (v = 0, len9 = ref57.length; v < len9; v++) {
                ak = ref57[v];
                res.author.push({
                  name: ak
                });
              }
            } else {
              res.author = [
                {
                  name: bt
                }
              ];
            }
          }
        } catch (error) {}
        try {
          rmn = citation.split(res.title)[1];
          if (res.url && rmn.includes(res.url)) {
            rmn = rmn.replace(res.url);
          }
          if (res.doi && rmn.includes(res.doi)) {
            rmn = rmn.replace(res.doi);
          }
          if (rmn.indexOf('.') < 3) {
            rmn = rmn.replace('.', '');
          }
          if (rmn.indexOf(',') < 3) {
            rmn = rmn.replace(',', '');
          }
          rmn = rmn.trim();
          if (rmn.length > 6) {
            res.journal = rmn;
            if (rmn.includes(',')) {
              res.journal = res.journal.split(',')[0].replace(/in /gi, '').trim();
            }
            if (res.journal.indexOf('.') < 3) {
              res.journal = res.journal.replace('.', '');
            }
            if (res.journal.indexOf(',') < 3) {
              res.journal = res.journal.replace(',', '');
            }
            res.journal = res.journal.trim();
          }
        } catch (error) {}
      }
      try {
        if (res.journal) {
          rmn = citation.split(res.journal)[1];
          if (res.url && rmn.includes(res.url)) {
            rmn = rmn.replace(res.url);
          }
          if (res.doi && rmn.includes(res.doi)) {
            rmn = rmn.replace(res.doi);
          }
          if (rmn.indexOf('.') < 3) {
            rmn = rmn.replace('.', '');
          }
          if (rmn.indexOf(',') < 3) {
            rmn = rmn.replace(',', '');
          }
          rmn = rmn.trim();
          if (rmn.length > 4) {
            if (rmn.includes('retrieved')) {
              rmn = rmn.split('retrieved')[0];
            }
            if (rmn.includes('Retrieved')) {
              rmn = rmn.split('Retrieved')[0];
            }
            res.volume = rmn;
            if (res.volume.includes('(')) {
              res.volume = res.volume.split('(')[0];
              res.volume = res.volume.trim();
              try {
                res.issue = rmn.split('(')[1].split(')')[0];
                res.issue = res.issue.trim();
              } catch (error) {}
            }
            if (res.volume.includes(',')) {
              res.volume = res.volume.split(',')[0];
              res.volume = res.volume.trim();
              try {
                res.issue = rmn.split(',')[1];
                res.issue = res.issue.trim();
              } catch (error) {}
            }
            if (res.volume) {
              try {
                if (isNaN(parseInt(res.volume))) {
                  delete res.volume;
                }
              } catch (error) {}
            }
            if (res.issue) {
              if (res.issue.includes(',')) {
                res.issue = res.issue.split(',')[0].trim();
              }
              try {
                if (isNaN(parseInt(res.issue))) {
                  delete res.issue;
                }
              } catch (error) {}
            }
            if (res.volume && res.issue) {
              try {
                rmn = citation.split(res.journal)[1];
                if (rmn.includes('retriev')) {
                  rmn = rmn.split('retriev')[0];
                }
                if (rmn.includes('Retriev')) {
                  rmn = rmn.split('Retriev')[0];
                }
                if (res.url && rmn.includes(res.url)) {
                  rmn = rmn.split(res.url)[0];
                }
                if (res.doi && rmn.includes(res.doi)) {
                  rmn = rmn.split(res.doi)[0];
                }
                rmn = rmn.substring(rmn.indexOf(res.volume) + (res.volume + '').length);
                rmn = rmn.substring(rmn.indexOf(res.issue) + (res.issue + '').length);
                if (rmn.indexOf('.') < 2) {
                  rmn = rmn.replace('.', '');
                }
                if (rmn.indexOf(',') < 2) {
                  rmn = rmn.replace(',', '');
                }
                if (rmn.indexOf(')') < 2) {
                  rmn = rmn.replace(')', '');
                }
                rmn = rmn.trim();
                if (!isNaN(parseInt(rmn.substring(0, 1)))) {
                  res.pages = rmn.split(' ')[0].split('.')[0].trim();
                  if (res.pages.length > 5) {
                    res.pages = res.pages.split(', ')[0];
                  }
                }
              } catch (error) {}
            }
          }
        }
      } catch (error) {}
      if (!res.author && citation.includes('et al')) {
        cn = citation.split('et al')[0].trim();
        if (citation.startsWith(cn)) {
          res.author = [
            {
              name: cn + 'et al'
            }
          ];
        }
      }
      if (res.title && !res.volume) {
        try {
          clc = citation.split(res.title)[1].toLowerCase().replace('volume', 'vol').replace('vol.', 'vol').replace('issue', 'iss').replace('iss.', 'iss').replace('pages', 'page').replace('pp', 'page');
          if (clc.includes('vol')) {
            res.volume = clc.split('vol')[1].split(',')[0].split('(')[0].split('.')[0].split(' ')[0].trim();
          }
          if (!res.issue && clc.includes('iss')) {
            res.issue = clc.split('iss')[1].split(',')[0].split('.')[0].split(' ')[0].trim();
          }
          if (!res.pages && clc.includes('page')) {
            res.pages = clc.split('page')[1].split('.')[0].split(', ')[0].split(' ')[0].trim();
          }
        } catch (error) {}
      }
    } catch (error) {}
  }
  if (typeof res.year === 'number') {
    res.year = res.year.toString();
  }
  return res;
};

// temporary legacy wrapper for old site front page availability check
// that page should be moved to use the new embed, like shareyourpaper
P.availability = async function(params, v2) {
  var afnd, base, qry, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref3, ref4, ref5, ref6, ref7, ref8, ref9, request, resp, rq;
  if (params == null) {
    params = this.copy(this.params);
  }
  delete this.params.dom;
  if (params.availability) {
    if (params.availability.startsWith('10.') && params.availability.includes('/')) {
      params.doi = params.availability;
    } else if (params.availability.includes(' ')) {
      params.title = params.availability;
    } else {
      params.id = params.availability;
    }
    delete params.availability;
  }
  if (Array.isArray(params.url)) {
    params.url = params.url[0];
  }
  if (!params.test && params.url && false) { //await @blacklist params.url
    if (params.dom) {
      params.dom = 'redacted';
    }
    return {
      status: 400
    };
  } else {
    afnd = {
      data: {
        availability: [],
        requests: [],
        accepts: [],
        meta: {
          article: {},
          data: {}
        }
      }
    };
    if (params != null) {
      afnd.data.match = (ref = (ref1 = (ref2 = (ref3 = (ref4 = (ref5 = (ref6 = (ref7 = params.doi) != null ? ref7 : params.pmid) != null ? ref6 : params.pmc) != null ? ref5 : params.pmcid) != null ? ref4 : params.title) != null ? ref3 : params.url) != null ? ref2 : params.id) != null ? ref1 : params.citation) != null ? ref : params.q;
    }
    if (typeof v2 === 'object' && JSON.stringify(v2) !== '{}' && (v2.metadata != null)) {
      afnd.v2 = v2;
    }
    if (afnd.v2 == null) {
      afnd.v2 = (await this.find(params));
    }
    if (afnd.v2 != null) {
      if ((base = afnd.data).match == null) {
        base.match = (ref8 = (ref9 = (ref10 = (ref11 = (ref12 = (ref13 = afnd.v2.input) != null ? ref13 : (ref14 = afnd.v2.metadata) != null ? ref14.doi : void 0) != null ? ref12 : (ref15 = afnd.v2.metadata) != null ? ref15.title : void 0) != null ? ref11 : (ref16 = afnd.v2.metadata) != null ? ref16.pmid : void 0) != null ? ref10 : (ref17 = afnd.v2.metadata) != null ? ref17.pmc : void 0) != null ? ref9 : (ref18 = afnd.v2.metadata) != null ? ref18.pmcid : void 0) != null ? ref8 : (ref19 = afnd.v2.metadata) != null ? ref19.url : void 0;
      }
      if (Array.isArray(afnd.data.match)) {
        afnd.data.match = afnd.data.match[0];
      }
      try {
        afnd.data.ill = afnd.v2.ill;
        if (afnd.v2.metadata != null) {
          afnd.data.meta.article = JSON.parse(JSON.stringify(afnd.v2.metadata));
        }
        if (Array.isArray(afnd.data.meta.article.url)) {
          afnd.data.meta.article.url = afnd.data.meta.article.url[0];
        }
        if ((afnd.v2.url != null) && (afnd.data.meta.article.source == null)) {
          afnd.data.meta.article.source = 'oaworks'; // source doesn't play significant role any more, could prob just remove this if not used anywhere
        }
        if (afnd.v2.url) {
          afnd.data.availability.push({
            type: 'article',
            url: (Array.isArray(afnd.v2.url) ? afnd.v2.url[0] : afnd.v2.url)
          });
        }
      } catch (error) {}
      try {
        if (afnd.data.availability.length === 0 && (afnd.v2.metadata.doi || afnd.v2.metadata.title || afnd.v2.meadata.url)) {
          if (afnd.v2.metadata.doi) {
            qry = 'doi.exact:"' + afnd.v2.metadata.doi + '"';
          } else if (afnd.v2.metadata.title) {
            qry = 'title.exact:"' + afnd.v2.metadata.title + '"';
          } else {
            qry = 'url.exact:"' + (Array.isArray(afnd.v2.metadata.url) ? afnd.v2.metadata.url[0] : afnd.v2.metadata.url) + '"';
          }
          if (qry) { // ' + (if @S.dev then 'dev.' else '') + '
            resp = (await this.fetch('https://api.cottagelabs.com/service/oab/requests?q=' + qry + ' AND type:article&sort=createdAt:desc'));
            if (resp != null ? (ref20 = resp.hits) != null ? ref20.total : void 0 : void 0) {
              request = resp.hits.hits[0]._source;
              rq = {
                type: 'article',
                _id: request._id
              };
              rq.ucreated = params.uid && ((ref21 = request.user) != null ? ref21.id : void 0) === params.uid ? true : false;
              afnd.data.requests.push(rq);
            }
          }
        }
      } catch (error) {}
    }
    if (afnd.data.availability.length === 0 && afnd.data.requests.length === 0) {
      afnd.data.accepts.push({
        type: 'article'
      });
    }
    return afnd;
  }
};

// this should default to a search of ILLs as well... with a restrict
// restrict = @auth.role('openaccessbutton.admin') and this.queryParams.all then [] else [{term:{from:@user?._id}}]
var indexOf = [].indexOf;

P.ill = async function(opts) { // only worked on POST with optional auth
  var a, atidy, ats, authors, config, first, i, j, len, len1, m, o, ordered, r, ref, ref1, ref2, ref3, ref4, su, tmpl, vars;
  if (opts == null) {
    opts = this.copy(this.params);
    if (opts.ill) {
      opts.doi = opts.ill;
      delete opts.ill;
    }
  }
  if (opts.metadata == null) {
    opts.metadata = (await this.metadata(opts));
  }
  if (opts.pilot === true) {
    opts.pilot = Date.now();
  }
  if (opts.live === true) {
    opts.live = Date.now();
  }
  config = opts.config;
  try {
    config = JSON.parse(config);
  } catch (error1) {}
  if (typeof config === 'string' || (!config && opts.from)) {
    config = (await this.fetch('https://api.cottagelabs.com/service/oab/ill/config?uid=' + ((ref = opts.from) != null ? ref : config)));
    if ((config == null) || JSON.stringify(config) === '{}') {
      config = (await this.fetch('https://dev.api.cottagelabs.com/service/oab/ill/config?uid=' + ((ref1 = opts.from) != null ? ref1 : config)));
    }
  }
  if (config == null) {
    config = {};
  }
  vars = {
    name: 'librarian',
    details: '' // anywhere to get the user name from config?
  };
  ordered = ['title', 'author', 'volume', 'issue', 'date', 'pages'];
  for (o in opts) {
    if (o === 'metadata') {
      for (m in opts[o]) {
        if (m !== 'email') {
          opts[m] = opts[o][m];
          if (indexOf.call(ordered, m) < 0) {
            ordered.push(m);
          }
        }
      }
      delete opts.metadata;
    } else {
      if (indexOf.call(ordered, o) < 0) {
        ordered.push(o);
      }
    }
  }
  for (i = 0, len = ordered.length; i < len; i++) {
    r = ordered[i];
    if (opts[r]) {
      vars[r] = opts[r];
      if (r === 'author') {
        authors = '<p>Authors:<br>';
        first = true;
        ats = [];
        ref2 = opts[r];
        for (j = 0, len1 = ref2.length; j < len1; j++) {
          a = ref2[j];
          if (a.family) {
            if (first) {
              first = false;
            } else {
              authors += ', ';
            }
            atidy = a.family + (a.given ? ' ' + a.given : '');
            authors += atidy;
            ats.push(atidy);
          }
        }
        vars[r] = ats;
      }
    }
  }
  if (opts.author != null) {
    delete opts.author; // remove author metadata due to messy provisions causing save issues
  }
  vars.illid = opts._id = (await this.uid());
  // such as https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=in%3A&si0qs=0021-9231&si1in=au%3A&si1op=AND&si2in=kw%3A&si2op=AND&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch
  // could be provided as: (unless other params are mandatory) 
  // https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?si0qs=0021-9231
  if (config.search && config.search.length && (opts.issn || opts.journal)) {
    if (config.search.indexOf('worldcat') !== -1) {
      su = config.search.split('?')[0] + '?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=';
      su += opts.issn != null ? 'in%3A' : 'ti%3A';
      su += '&si0qs=' + ((ref3 = opts.issn) != null ? ref3 : opts.journal);
      su += '&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch';
    } else {
      su = config.search;
      su += opts.issn ? opts.issn : opts.journal;
    }
    vars.worldcatsearchurl = su;
  }
  await this.ills(opts);
  tmpl = (await this.templates('instantill_create'));
  tmpl = tmpl.content;
  if (!opts.forwarded && !opts.resolved && (config.email || opts.email)) {
    this.waitUntil(this.mail({
      svc: 'oaworks',
      vars: vars,
      template: tmpl,
      to: (ref4 = config.email) != null ? ref4 : opts.email,
      from: "InstantILL <InstantILL@openaccessbutton.org>",
      subject: "ILL request " + opts._id
    }));
  }
  tmpl = tmpl.replace(/Dear.*?\,/, 'Dear Joe, here is a copy of what was just sent:');
  this.waitUntil(this.mail({
    svc: 'oaworks',
    vars: vars,
    template: tmpl,
    from: "InstantILL <InstantILL@openaccessbutton.org>",
    subject: "ILL CREATED " + opts._id,
    to: 'joe@oa.works'
  }));
  return opts;
};

P.ills = {
  _index: true
};

P.ill.collect = async function(params) {
  var q, sid, url;
  if (params == null) {
    params = this.copy(this.params);
  }
  sid = params.collect; // end of the url is an SID
  if (params._id == null) {
    params._id = (await this.uid());
  }
  // example AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6
  url = 'https://script.google.com/macros/s/' + sid + '/exec?';
  for (q in params) {
    if (q !== 'collect') {
      url += (q === '_id' ? 'uuid' : q) + '=' + params[q] + '&';
    }
  }
  this.waitUntil(this.fetch(url));
  this.waitUntil(this.svc.rscvd(params));
  return true;
};

P.ill.openurl = async function(config, meta) {
  var author, d, defaults, i, k, len, nfield, ref, ref1, ref2, url, v;
  // Will eventually redirect after reading openurl params passed here, somehow. 
  // For now a POST of metadata here by a user with an open url registered will build their openurl
  if (config == null) {
    config = (ref = this.params.config) != null ? ref : {};
  }
  if (meta == null) {
    meta = (ref1 = this.params.meta) != null ? ref1 : (await this.metadata());
  }
  if (config.ill_redirect_base_url) {
    if (config.ill_form == null) {
      config.ill_form = config.ill_redirect_base_url;
    }
  }
  if (config.ill_redirect_params) {
    if (config.ill_added_params == null) {
      config.ill_added_params = config.ill_redirect_params;
    }
  }
  // add iupui / openURL defaults to config
  defaults = {
    sid: 'sid',
    title: 'atitle', // this is what iupui needs (title is also acceptable, but would clash with using title for journal title, which we set below, as iupui do that
    doi: 'rft_id', // don't know yet what this should be
    pmcid: 'pmcid', // don't know yet what this should be
    author: 'aulast', // author should actually be au, but aulast works even if contains the whole author, using aufirst just concatenates
    journal: 'title', // this is what iupui needs
    page: 'pages', // iupui uses the spage and epage for start and end pages, but pages is allowed in openurl, check if this will work for iupui
    published: 'date', // this is what iupui needs, but in format 1991-07-01 - date format may be a problem
    year: 'rft.year' // this is what IUPUI uses
  };
  for (d in defaults) {
    if (!config[d]) {
      config[d] = defaults[d];
    }
  }
  url = '';
  if (config.ill_added_params) {
    url += config.ill_added_params.replace('?', '') + '&';
  }
  url += config.sid + '=InstantILL&';
  for (k in meta) {
    v = '';
    if (k === 'author') {
      ref2 = (Array.isArray(meta.author) ? meta.author : [meta.author]);
      for (i = 0, len = ref2.length; i < len; i++) {
        author = ref2[i];
        if (v.length) {
          v += ', ';
        }
        v += typeof author === 'string' ? author : author.family ? author.family + (author.given ? ', ' + author.given : '') : JSON.stringify(author);
      }
    } else if (k === 'doi' || k === 'pmid' || k === 'pmc' || k === 'pmcid' || k === 'url' || k === 'journal' || k === 'title' || k === 'year' || k === 'issn' || k === 'volume' || k === 'issue' || k === 'page' || k === 'crossref_type' || k === 'publisher' || k === 'published' || k === 'notes') {
      v = meta[k];
    }
    if (v) {
      url += (config[k] ? config[k] : k) + '=' + encodeURIComponent(v) + '&';
    }
  }
  if (meta.usermetadata) {
    nfield = config.notes ? config.notes : 'notes';
    url = url.replace('usermetadata=true', '');
    if (url.indexOf(nfield + '=') === -1) {
      url += '&' + nfield + '=The user provided some metadata.';
    } else {
      url = url.replace(nfield + '=', nfield + '=The user provided some metadata. ');
    }
  }
  return url.replace('/&&/g', '&');
};

P.ill.subscription = async function(config, meta) {
  var err, error, fnd, npg, openurl, pg, ref, ref1, ref2, res, s, spg, sub, subtype, surl, tid, url;
  if (!config && !meta && (this.params.sub || this.params.subscription)) { // assume values are being passed directly on GET request
    config = this.copy(this.params);
    if (config.sub) {
      config.subscription = config.sub;
    }
    if (this.params.meta) {
      meta = this.params.meta;
      delete config.meta;
    } else if (config.doi && this.keys(config).length === 2) {
      meta = (await this.metadata(config.doi));
      delete config.doi;
    } else {
      meta = this.copy(config);
      delete config.doi;
    }
  }
  if (config == null) {
    config = (ref = this.params.config) != null ? ref : {};
  }
  if (typeof config === 'string') {
    config = (await this.fetch('https://api.cottagelabs.com/service/oab/ill/config?uid=' + config));
    if ((config == null) || JSON.stringify(config) === '{}') {
      config = (await this.fetch('https://dev.api.cottagelabs.com/service/oab/ill/config?uid=' + ((ref1 = opts.from) != null ? ref1 : config)));
    }
  }
  if (meta == null) {
    meta = this.params.meta;
  }
  res = {
    findings: {},
    lookups: [],
    error: [],
    contents: []
  };
  if (config.subscription != null) {
    if (config.ill_redirect_params) {
      if (config.ill_added_params == null) {
        config.ill_added_params = config.ill_redirect_params;
      }
    }
    // need to get their subscriptions link from their config - and need to know how to build the query string for it
    openurl = (await this.ill.openurl(config, meta));
    if (config.ill_added_params) {
      openurl = openurl.replace(config.ill_added_params.replace('?', ''), '');
    }
    if (typeof config.subscription === 'string') {
      config.subscription = config.subscription.split(',');
    }
    if (typeof config.subscription_type === 'string') {
      config.subscription_type = config.subscription_type.split(',');
    }
    if (config.subscription_type == null) {
      config.subscription_type = [];
    }
    for (s in config.subscription) {
      sub = config.subscription[s];
      if (typeof sub === 'object') {
        subtype = sub.type;
        sub = sub.url;
      } else {
        subtype = (ref2 = config.subscription_type[s]) != null ? ref2 : 'unknown';
      }
      sub = sub.trim();
      if (sub) {
        if (subtype === 'serialssolutions' || sub.indexOf('serialssolutions') !== -1) { //  and sub.indexOf('.xml.') is -1
          tid = sub.split('.search')[0];
          if (tid.indexOf('//') !== -1) {
            tid = tid.split('//')[1];
          }
          //bs = if sub.indexOf('://') isnt -1 then sub.split('://')[0] else 'http' # always use http because https on the xml endpoint fails
          sub = 'http://' + tid + '.openurl.xml.serialssolutions.com/openurlxml?version=1.0&genre=article&';
        } else if ((subtype === 'sfx' || sub.indexOf('sfx.') !== -1) && sub.indexOf('sfx.response_type=simplexml') === -1) {
          sub += (sub.indexOf('?') === -1 ? '?' : '&') + 'sfx.response_type=simplexml';
        } else if ((subtype === 'exlibris' || sub.indexOf('.exlibris') !== -1) && sub.indexOf('response_type') === -1) {
          // https://github.com/OAButton/discussion/issues/1793
          //sub = 'https://trails-msu.userservices.exlibrisgroup.com/view/uresolver/01TRAILS_MSU/openurl?svc_dat=CTO&response_type=xml&sid=InstantILL&'
          sub = sub.split('?')[0] + '?svc_dat=CTO&response_type=xml&sid=InstantILL&';
        }
        //ID=doi:10.1108%2FNFS-09-2019-0293&genre=article&atitle=Impact%20of%20processing%20and%20packaging%20on%20the%20quality%20of%20murici%20jelly%20%5BByrsonima%20crassifolia%20(L.)%20rich%5D%20during%20storage.&title=Nutrition%20&%20Food%20Science&issn=00346659&volume=50&issue=5&date=20200901&au=Da%20Cunha,%20Mariana%20Crivelari&spage=871&pages=871-883
        url = sub + (sub.indexOf('?') === -1 ? '?' : '&') + openurl;
        if (url.indexOf('snc.idm.oclc.org/login?url=') !== -1) {
          url = url.split('snc.idm.oclc.org/login?url=')[1];
        }
        url = url.replace('cache=true', '');
        if (subtype === 'sfx' || sub.indexOf('sfx.') !== -1 && url.indexOf('=10.') !== -1) {
          url = url.replace('=10.', '=doi:10.');
        }
        if (subtype === 'exlibris' || sub.indexOf('.exlibris') !== -1 && url.indexOf('doi=10.') !== -1) {
          url = url.replace('doi=10.', 'ID=doi:10.');
        }
        pg = '';
        spg = '';
        error = false;
        res.lookups.push(url);
        try {
          // proxy may still be required if our main machine was registered with some of these ILL service providers...
          //pg = if url.includes('.xml.serialssolutions') or url.includes('sfx.response_type=simplexml') or url.includes('response_type=xml') then await @fetch(url) else await @puppet url
          pg = (await this.fetch(url));
          spg = pg.indexOf('<body') !== -1 ? pg.toLowerCase().split('<body')[1].split('</body')[0] : pg;
          res.contents.push(spg);
        } catch (error1) {
          err = error1;
          error = true;
        }
        // sfx 
        // with access:
        // https://cricksfx.hosted.exlibrisgroup.com/crick?sid=Elsevier:Scopus&_service_type=getFullTxt&issn=00225193&isbn=&volume=467&issue=&spage=7&epage=14&pages=7-14&artnum=&date=2019&id=doi:10.1016%2fj.jtbi.2019.01.031&title=Journal+of+Theoretical+Biology&atitle=Potential+relations+between+post-spliced+introns+and+mature+mRNAs+in+the+Caenorhabditis+elegans+genome&aufirst=S.&auinit=S.&auinit1=S&aulast=Bo
        // which will contain a link like:
        // <A title="Navigate to target in new window" HREF="javascript:openSFXMenuLink(this, 'basic1', undefined, '_blank');">Go to Journal website at</A>
        // but the content can be different on different sfx language pages, so need to find this link via the tag attributes, then trigger it, then get the page it opens
        // can test this with 10.1016/j.jtbi.2019.01.031 on instantill page
        // note there is also now an sfx xml endpoint that we have found to check
        if (subtype === 'sfx' || url.indexOf('sfx.') !== -1) {
          if (error) {
            res.error.push('sfx');
          }
          if (spg.indexOf('getFullTxt') !== -1 && spg.indexOf('<target_url>') !== -1) {
            try {
              // this will get the first target that has a getFullTxt type and has a target_url element with a value in it, or will error
              res.url = spg.split('getFullTxt')[1].split('</target>')[0].split('<target_url>')[1].split('</target_url>')[0].trim();
              res.findings.sfx = res.url;
              if (res.url != null) {
                if (res.url.indexOf('getitnow') === -1) {
                  res.found = 'sfx';
                } else {
                  res.url = void 0;
                  res.findings.sfx = void 0;
                }
              }
            } catch (error1) {}
          } else {
            if (spg.indexOf('<a title="navigate to target in new window') !== -1 && spg.split('<a title="navigate to target in new window')[1].split('">')[0].indexOf('basic1') !== -1) {
              // tried to get the next link after the click through, but was not worth putting more time into it. For now, seems like this will have to do
              res.url = url;
              res.findings.sfx = res.url;
              if (res.url != null) {
                if (res.url.indexOf('getitnow') === -1) {
                  res.found = 'sfx';
                } else {
                  res.url = void 0;
                  res.findings.sfx = void 0;
                }
              }
            }
          }
        // eds
        // note eds does need a login, but IP address range is supposed to get round that
        // our IP is supposed to be registered with the library as being one of their internal ones so should not need login
        // however a curl from our IP to it still does not seem to work - will try with puppeteer to see if it is blocking in other ways
        // not sure why the links here are via an oclc login - tested, and we will use without it
        // with access:
        // https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=RE&aulast=Marx&atitle=Platelet-rich+plasma:+growth+factor+enhancement+for+bone+grafts&id=doi:10.1016/S1079-2104(98)90029-4&title=Oral+Surgery,+Oral+Medicine,+Oral+Pathology,+Oral+Radiology,+and+Endodontology&volume=85&issue=6&date=1998&spage=638&issn=1079-2104
        // can be tested on instantill page with 10.1016/S1079-2104(98)90029-4
        // without:
        // https://snc.idm.oclc.org/login?url=http://resolver.ebscohost.com/openurl?sid=google&auinit=MP&aulast=Newton&atitle=Librarian+roles+in+institutional+repository+data+set+collecting:+outcomes+of+a+research+library+task+force&id=doi:10.1080/01462679.2011.530546
        } else if (subtype === 'eds' || url.indexOf('ebscohost.') !== -1) {
          if (error) {
            res.error.push('eds');
          }
          if (spg.indexOf('view this ') !== -1 && pg.indexOf('<a data-auto="menu-link" href="') !== -1) {
            res.url = url.replace('://', '______').split('/')[0].replace('______', '://') + pg.split('<a data-auto="menu-link" href="')[1].split('" title="')[0];
            res.findings.eds = res.url;
            if (res.url != null) {
              if (res.url.indexOf('getitnow') === -1) {
                res.found = 'eds';
              } else {
                res.url = void 0;
              }
            }
          }
        // serials solutions
        // the HTML source code for the No Results page includes a span element with the class SS_NoResults. This class is only found on the No Results page (confirmed by serialssolutions)
        // with:
        // https://rx8kl6yf4x.search.serialssolutions.com/?genre=article&issn=14085348&title=Annales%3A%20Series%20Historia%20et%20Sociologia&volume=28&issue=1&date=20180101&atitle=HOW%20TO%20UNDERSTAND%20THE%20WAR%20IN%20SYRIA.&spage=13&PAGES=13-28&AUTHOR=%C5%A0TERBENC%2C%20Primo%C5%BE&&aufirst=&aulast=&sid=EBSCO:aph&pid=
        // can test this on instantill page with How to understand the war in Syria - Annales Series Historia et Sociologia 2018
        // but the with link has a suppressed link that has to be clicked to get the actual page with the content on it
        // <a href="?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick">Click here</a>
        // which is the only link with the showsuppressedlinks param and the clickhere content
        // then the page with the content link is like:
        // https://rx8kl6yf4x.search.serialssolutions.com/?ShowSupressedLinks=yes&SS_LibHash=RX8KL6YF4X&url_ver=Z39.88-2004&rfr_id=info:sid/sersol:RefinerQuery&rft_val_fmt=info:ofi/fmt:kev:mtx:journal&SS_ReferentFormat=JournalFormat&SS_formatselector=radio&rft.genre=article&SS_genreselector=1&rft.aulast=%C5%A0TERBENC&rft.aufirst=Primo%C5%BE&rft.date=2018-01-01&rft.issue=1&rft.volume=28&rft.atitle=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&rft.spage=13&rft.title=Annales%3A+Series+Historia+et+Sociologia&rft.issn=1408-5348&SS_issnh=1408-5348&rft.isbn=&SS_isbnh=&rft.au=%C5%A0TERBENC%2C+Primo%C5%BE&rft.pub=Zgodovinsko+dru%C5%A1tvo+za+ju%C5%BEno+Primorsko&paramdict=en-US&SS_PostParamDict=disableOneClick
        // and the content is found in a link like this:
        // <div id="ArticleCL" class="cl">
        //   <a target="_blank" href="./log?L=RX8KL6YF4X&amp;D=EAP&amp;J=TC0000940997&amp;P=Link&amp;PT=EZProxy&amp;A=HOW+TO+UNDERSTAND+THE+WAR+IN+SYRIA.&amp;H=c7306f7121&amp;U=http%3A%2F%2Fwww.ulib.iupui.edu%2Fcgi-bin%2Fproxy.pl%3Furl%3Dhttp%3A%2F%2Fopenurl.ebscohost.com%2Flinksvc%2Flinking.aspx%3Fgenre%3Darticle%26issn%3D1408-5348%26title%3DAnnales%2BSeries%2Bhistoria%2Bet%2Bsociologia%26date%3D2018%26volume%3D28%26issue%3D1%26spage%3D13%26atitle%3DHOW%2BTO%2BUNDERSTAND%2BTHE%2BWAR%2BIN%2BSYRIA.%26aulast%3D%25C5%25A0TERBENC%26aufirst%3DPrimo%C5%BE">Article</a>
        // </div>
        // without:
        // https://rx8kl6yf4x.search.serialssolutions.com/directLink?&atitle=Writing+at+the+Speed+of+Sound%3A+Music+Stenography+and+Recording+beyond+the+Phonograph&author=Pierce%2C+J+Mackenzie&issn=01482076&title=Nineteenth+Century+Music&volume=41&issue=2&date=2017-10-01&spage=121&id=doi:&sid=ProQ_ss&genre=article
        // we also have an xml alternative for serials solutions
        // see https://journal.code4lib.org/articles/108
        } else if (subtype === 'serialssolutions' || url.indexOf('serialssolutions.') !== -1) {
          if (error) {
            res.error.push('serialssolutions');
          }
          if (spg.indexOf('<ssopenurl:url type="article">') !== -1) {
            fnd = spg.split('<ssopenurl:url type="article">')[1].split('</ssopenurl:url>')[0].trim().replace(/&amp;/g, '&'); // this gets us something that has an empty accountid param - do we need that for it to work?
            if (fnd.length) {
              res.url = fnd;
              res.findings.serials = res.url;
              if (res.url != null) {
                if (res.url.indexOf('getitnow') === -1) {
                  res.found = 'serials';
                } else {
                  res.url = void 0;
                  res.findings.serials = void 0;
                }
              }
            }
          } else {
            // disable journal matching for now until we have time to get it more accurate - some things get journal links but are not subscribed
            //else if spg.indexOf('<ssopenurl:result format="journal">') isnt -1
            //  # we assume if there is a journal result but not a URL that it means the institution has a journal subscription but we don't have a link
            //  res.journal = true
            //  res.found = 'serials'
            if (spg.indexOf('ss_noresults') === -1) {
              try {
                surl = url.split('?')[0] + '?ShowSupressedLinks' + pg.split('?ShowSupressedLinks')[1].split('">')[0];
                //npg = await @puppet surl # would this still need proxy?
                npg = (await this.fetch(surl));
                if (npg.indexOf('ArticleCL') !== -1 && npg.split('DatabaseCL')[0].indexOf('href="./log') !== -1) {
                  res.url = surl.split('?')[0] + npg.split('ArticleCL')[1].split('DatabaseCL')[0].split('href="')[1].split('">')[0].replace(/&amp;/g, '&');
                  res.findings.serials = res.url;
                  if (res.url != null) {
                    if (res.url.indexOf('getitnow') === -1) {
                      res.found = 'serials';
                    } else {
                      res.url = void 0;
                      res.findings.serials = void 0;
                    }
                  }
                }
              } catch (error1) {
                if (error) {
                  res.error.push('serialssolutions');
                }
              }
            }
          }
        } else if (subtype === 'exlibris' || url.indexOf('.exlibris') !== -1) {
          if (error) {
            res.error.push('exlibris');
          }
          if (spg.indexOf('full_text_indicator') !== -1 && spg.split('full_text_indicator')[1].replace('">', '').indexOf('true') === 0 && spg.indexOf('resolution_url') !== -1) {
            res.url = spg.split('<resolution_url>')[1].split('</resolution_url>')[0].replace(/&amp;/g, '&');
            res.findings.exlibris = res.url;
            res.found = 'exlibris';
          }
        }
      }
    }
  }
  if (res.url) {
    res.url = (await this.decode(res.url));
  }
  return res;
};

P.licence = async function(url, content, start, end) {
  var i, l, len, lh, lic, lics, match, ref, ref1, ref2, ref3, ref4, urlmatch, urlmatcher;
  if (url == null) {
    url = this.params.url;
  }
  if (content == null) {
    content = (ref = this.params.content) != null ? ref : this.body;
  }
  if (!url && !content && (this.params.licence || this.params.doi)) {
    url = 'https://doi.org/' + ((ref1 = this.params.licence) != null ? ref1 : this.params.doi);
  }
  if (url) {
    url = url.replace(/(^\s*)|(\s*$)/g, '');
    if (!content) {
      console.log(url);
      try {
        //try content = await @puppet url
        content = (await this.fetch(url));
      } catch (error) {}
    }
  }
  if (typeof content === 'number') {
    content = void 0;
  }
  if (start == null) {
    start = this.params.start;
  }
  if (end == null) {
    end = this.params.end;
  }
  lic = {};
  if (url) {
    lic.url = url;
  }
  if (typeof content === 'string') {
    if ((start != null) && content.includes(start)) {
      content = content.split(start)[1];
    }
    if (end) {
      content = content.split(end)[0];
    }
    if (content.length > 100000) { // reduced this by and the substrings below by an order of magnitude
      lic.large = true;
      content = content.substring(0, 50000) + content.substring(content.length - 50000, content.length);
    }
    lics = (await this.licences('*', 10000));
    ref4 = (ref2 = lics != null ? (ref3 = lics.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
    for (i = 0, len = ref4.length; i < len; i++) {
      lh = ref4[i];
      l = lh._source;
      if (!l.matchesondomains || l.matchesondomains === '*' || (url == null) || l.matchesondomains.toLowerCase().includes(url.toLowerCase().replace('http://', '').replace('https://', '').replace('www.', '').split('/')[0])) {
        match = l.matchtext.toLowerCase().replace(/[^a-z0-9]/g, '');
        urlmatcher = l.matchtext.includes('://') ? l.matchtext.toLowerCase().split('://')[1].split('"')[0].split(' ')[0] : false;
        urlmatch = urlmatcher ? content.toLowerCase().includes(urlmatcher) : false;
        if (urlmatch || content.toLowerCase().replace(/[^a-z0-9]/g, '').includes(match)) {
          lic.licence = l.licencetype;
          lic.match = l.matchtext;
          lic.matched = urlmatch ? urlmatcher : match;
          break;
        }
      }
    }
  }
  return lic;
};

P.licences = {
  _sheet: '1yJOpE_YMdDxCKaK0DqWoCJDdq8Ep1b-_J1xYVKGsiYI',
  _prefix: false
};

var indexOf = [].indexOf;

P.permissions = async function(meta, ror, getmeta, oadoi, crossref, best) { // oadoi and crossref are just ways for other functions to pass in oadoi or crossref record objects to save looking them up again
  var _format, _getmeta, _score, altoa, bp, crj, dl, doa, en, haddoi, i, indoaj, inisn, issns, j, key, l, len, len1, len10, len2, len3, len4, len5, len6, len7, len8, len9, ll, m, msgs, n, nisns, o, overall_policy_restriction, p, pb, perms, ps, q, qr, r, rec, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref38, ref4, ref5, ref6, ref7, ref8, ref9, ro, rors, rp, rr, rs, rw, s, t, tr, u, vl, wp;
  overall_policy_restriction = false;
  haddoi = false;
  _format = async function(rec) {
    var a, d, em, eph, fst, i, j, l, len, len1, len2, ph, pt, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, swaps;
    if (haddoi && rec.embargo_months && (meta.published || meta.year)) {
      em = new Date(Date.parse((ref = meta.published) != null ? ref : meta.year + '-01-01'));
      em = new Date(em.setMonth(em.getMonth() + rec.embargo_months));
      rec.embargo_end = em.toISOString().split('T')[0];
    }
    if (rec.embargo_end === '') {
      delete rec.embargo_end;
    }
    rec.copyright_name = rec.copyright_owner && rec.copyright_owner.toLowerCase() === 'publisher' ? (typeof rec.issuer.parent_policy === 'string' ? rec.issuer.parent_policy : typeof rec.issuer.id === 'string' ? rec.issuer.id : rec.issuer.id[0]) : rec.copyright_owner && ((ref1 = rec.copyright_owner.toLowerCase()) === 'journal' || ref1 === 'affiliation') ? (ref2 = meta.journal) != null ? ref2 : '' : (haddoi && rec.copyright_owner && rec.copyright_owner.toLowerCase().includes('author')) && (meta.author != null) && meta.author.length && (meta.author[0].name || meta.author[0].family) ? ((ref3 = meta.author[0].name) != null ? ref3 : meta.author[0].family) + (meta.author.length > 1 ? ' et al' : '') : '';
    if (((ref4 = rec.copyright_name.toLowerCase()) === 'publisher' || ref4 === 'journal') && (crossref || meta.doi || ((ref5 = rec.provenance) != null ? ref5.example : void 0))) {
      if (crossref == null) {
        crossref = (await this.src.crossref.works((ref6 = meta.doi) != null ? ref6 : rec.provenance.example));
      }
      ref8 = (ref7 = crossref != null ? crossref.assertion : void 0) != null ? ref7 : [];
      for (i = 0, len = ref8.length; i < len; i++) {
        a = ref8[i];
        if (a.name.toLowerCase() === 'copyright') {
          try {
            rec.copyright_name = a.value;
          } catch (error) {}
          try {
            rec.copyright_name = a.value.replace('\u00a9 ', '').replace(/[0-9]/g, '').trim();
          } catch (error) {}
        }
      }
    }
    if (haddoi && rec.copyright_year === '' && meta.year) {
      rec.copyright_year = meta.year;
    }
    if (rec.copyright_year === '') {
      delete rec.copyright_year;
    }
    if (haddoi && (rec.deposit_statement != null) && rec.deposit_statement.includes('<<')) {
      fst = '';
      ref9 = rec.deposit_statement.split('<<');
      for (j = 0, len1 = ref9.length; j < len1; j++) {
        pt = ref9[j];
        if (fst === '' && !pt.includes('>>')) {
          fst += pt;
        } else {
          eph = pt.split('>>');
          ph = eph[0].toLowerCase();
          swaps = {
            'journal title': 'journal',
            'vol': 'volume',
            'date of publication': 'published',
            '(c)': 'year',
            'article title': 'title',
            'copyright name': 'copyright_name'
          };
          if (swaps[ph] != null) {
            ph = swaps[ph];
          }
          if (ph === 'author') {
            try {
              fst += ((ref10 = meta.author[0].name) != null ? ref10 : meta.author[0].family) + (meta.author.length > 1 ? ' et al' : '');
            } catch (error) {}
          } else {
            fst += (ref11 = (ref12 = meta[ph]) != null ? ref12 : rec[ph]) != null ? ref11 : '';
          }
          try {
            fst += eph[1];
          } catch (error) {}
        }
      }
      rec.deposit_statement = fst;
    }
    if (rec._id != null) {
      if (rec.meta == null) {
        rec.meta = {};
      }
      rec.meta.source = 'https://' + (S.dev ? 'beta.oa.works/permissions/' : 'api.oa.works/permissions/') + (rec.issuer.type ? rec.issuer.type + '/' : '') + rec._id;
    }
    if (typeof ((ref13 = rec.issuer) != null ? ref13.has_policy : void 0) === 'string' && ((ref14 = rec.issuer.has_policy.toLowerCase().trim()) === 'not publisher' || ref14 === 'takedown')) {
      overall_policy_restriction = rec.issuer.has_policy;
    }
    ref15 = ['_id', 'hide'];
    for (l = 0, len2 = ref15.length; l < len2; l++) {
      d = ref15[l];
      delete rec[d];
    }
    return rec;
  };
  _score = (rec) => {
    var ref, ref1, ref2, ref3, ref4, ref5, score;
    score = rec.can_archive ? 1000 : 0;
    if (((ref = rec.provenance) != null ? ref.oa_evidence : void 0) === 'In DOAJ') {
      score += 1000;
    }
    if (rec.requirements != null) {
      score -= 10;
    } else {
      score += rec.version === 'publishedVersion' ? 200 : rec.version === 'acceptedVersion' ? 100 : 0;
    }
    if (rec.licence) {
      score -= 5;
    }
    score += ((ref1 = rec.issuer) != null ? ref1.type.toLowerCase() : void 0) === 'journal' ? 5 : ((ref2 = rec.issuer) != null ? ref2.type.toLowerCase() : void 0) === 'publisher' ? 4 : ((ref3 = rec.issuer) != null ? ref3.type.toLowerCase() : void 0) === 'university' ? 3 : (ref4 = (ref5 = rec.issuer) != null ? ref5.type.toLowerCase() : void 0) === 'article' ? 2 : 0;
    if (rec.embargo_months && rec.embargo_months >= 36 && (!rec.embargo_end || Date.parse(rec.embargo_end) < Date.now())) {
      score -= 25;
    }
    return score;
  };
  if (typeof meta === 'string') {
    meta = meta.startsWith('10.') ? {
      doi: meta
    } : {
      issn: meta
    };
  }
  if (meta == null) {
    meta = this.copy(this.params);
  }
  if ((meta != null ? meta.metadata : void 0) === true) { // just a pass-through for us to show metadata for debug
    delete meta.metadata;
  }
  if (((meta != null ? meta.permissions : void 0) != null) && typeof meta.permissions === 'string') {
    if (meta.permissions.startsWith('journal/')) {
      meta.issn = meta.permissions.replace('journal/', '');
    } else if (meta.permissions.startsWith('affiliation/')) {
      meta.ror = meta.permissions.replace('affiliation/', '');
    } else if (meta.permissions.startsWith('publisher/')) {
      meta.publisher = meta.permissions.replace('publisher/', '');
    } else if (meta.permissions.startsWith('10.') && meta.permissions.includes('/')) {
      meta.doi = meta.permissions;
    } else if (meta.permissions.includes('-') && meta.permissions.length < 10 && meta.permissions.length > 6) {
      meta.issn = meta.permissions;
    } else if (!meta.permissions.includes(' ') && !meta.permissions.includes(',') && meta.permissions.replace(/[0-9]/g, '').length !== meta.permissions.length) {
      meta.ror = meta.permissions;
    } else {
      meta.publisher = meta.permissions; // but could be a ROR?
    }
    delete meta.permissions;
  }
  if (meta.affiliation) {
    meta.ror = meta.affiliation;
    delete meta.affiliation;
  }
  if (meta.ror == null) {
    meta.ror = ror;
  }
  if (typeof meta.ror === 'string' && meta.ror.includes(',')) {
    meta.ror = meta.ror.split(',');
  }
  if (meta.journal && !meta.journal.includes(' ') && meta.journal.includes('-')) {
    meta.issn = meta.journal;
    delete meta.journal;
  }
  issns = Array.isArray(meta.issn) ? meta.issn : []; // only if directly passed a list of ISSNs for the same article, accept them as the ISSNs list to use
  if (typeof meta.issn === 'string' && meta.issn.includes(',')) {
    meta.issn = meta.issn.split(',');
  }
  delete meta.best;
  if (JSON.stringify(meta) === '{}' || (meta.issn && !JSON.stringify(meta.issn).includes('-')) || (meta.doi && (typeof meta.doi !== 'string' || !meta.doi.startsWith('10.') || !meta.doi.includes('/')))) {
    return {
      body: 'No valid DOI, ISSN, or ROR provided',
      status: 404
    };
  }
  if (best == null) {
    best = this.params.best;
  }
  if (best && meta.doi && !meta.ror.length) {
    if (bp = (await this.permissions.best(meta.doi))) {
      if (best === true || bp.updated > best) {
        delete bp.updated;
        delete bp.DOI;
        return {
          best_permission: bp
        };
      }
    }
  }
  // NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  // we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = async() => {
    var mk, psm, ref, results, rsm;
    psm = this.copy(meta);
    if (JSON.stringify(psm) !== '{}') {
      results = [];
      for (mk in rsm = (ref = crossref != null ? crossref : (await this.metadata(meta.doi))) != null ? ref : {}) {
        results.push(meta[mk] != null ? meta[mk] : meta[mk] = rsm[mk]);
      }
      return results;
    }
  };
  if (getmeta !== false && meta.doi && (!meta.publisher || !meta.issn)) {
    await _getmeta();
  }
  if (!meta.published && meta.year) {
    meta.published = meta.year + '-01-01';
  }
  haddoi = meta.doi != null;
  if (meta.issn) {
    if (typeof meta.issn === 'string') {
      meta.issn = [meta.issn];
    }
    if (!issns.length) { // they're already meta.issn in this case anyway
      ref = meta.issn;
      for (i = 0, len = ref.length; i < len; i++) {
        inisn = ref[i];
        if (indexOf.call(issns, inisn) < 0) { // check just in case
          issns.push(inisn);
        }
      }
    }
    try {
      if (meta.doi == null) {
        meta.doi = (await this.permissions.journals.example(issns));
      }
    } catch (error) {}
    if (!haddoi && meta.doi) {
      await _getmeta();
    }
  }
  if (haddoi && ((ref1 = meta.type) !== 'journal-article')) {
    return {
      body: 'DOI is not a journal article',
      status: 501
    };
  }
  if (meta.publisher && meta.publisher.includes('(') && meta.publisher.lastIndexOf(')') > (meta.publisher.length * .7)) {
    // could be a publisher name with the acronym at the end, like Public Library of Science (PLoS)
    // so get rid of the acronym because that is not included in the publisher name in crossref and other sources
    meta.publisher = meta.publisher.substring(0, meta.publisher.lastIndexOf('(')).trim();
  }
  try {
    meta.citation = '[';
    if (meta.title) {
      meta.citation += meta.title + '. ';
    }
    if (meta.journal) {
      meta.citation += meta.journal + ' ';
    }
    if (meta.volume) {
      meta.citation += meta.volume + (meta.issue ? ', ' : ' ');
    }
    if (meta.issue) {
      meta.citation += meta.issue + ' ';
    }
    if ((meta.page != null) || (meta.pages != null)) {
      meta.citation += 'p' + ((ref2 = meta.page) != null ? ref2 : meta.pages);
    }
    if (meta.year || meta.published) {
      meta.citation += ' (' + ((ref3 = meta.year) != null ? ref3 : meta.published).split('-')[0] + ')';
    }
    meta.citation = meta.citation.trim();
    meta.citation += ']';
  } catch (error) {}
  perms = {
    best_permission: void 0,
    all_permissions: []
  };
  rors = [];
  if (meta.ror != null) {
    if (typeof meta.ror === 'string') {
      meta.ror = [meta.ror];
    }
    rs = (await this.permissions.affiliations('issuer.id:"' + meta.ror.join('" OR issuer.id:"') + '"'));
    if (!(rs != null ? (ref4 = rs.hits) != null ? ref4.total : void 0 : void 0)) { // look up the ROR, get the ISO 3166-1 alpha-2 code, search affiliations for that
      try {
        rw = (await this.src.ror(meta.ror.length === 1 ? meta.ror[0] : 'id:"' + meta.ror.join(" OR id:") + '"'));
        if ((ref5 = rw.hits) != null ? ref5.total : void 0) {
          rw = rw.hits.hits[0]._source;
        }
        if (rw.country.country_code) {
          rs = (await this.permissions.affiliations('issuer.id:"' + rw.country.country_code + '"'));
        }
      } catch (error) {}
    }
    ref8 = (ref6 = rs != null ? (ref7 = rs.hits) != null ? ref7.hits : void 0 : void 0) != null ? ref6 : [];
    for (j = 0, len1 = ref8.length; j < len1; j++) {
      rr = ref8[j];
      tr = (await _format(rr._source));
      tr.score = (await _score(tr));
      rors.push(tr);
    }
  }
  indoaj = void 0;
  if (issns) {
    ref9 = this.index._for('src_doaj_journals', 'bibjson.pissn:"' + issns.join('" OR bibjson.pissn:"') + '" OR bibjson.eissn:"' + issns.join('" OR bibjson.eissn:"') + '"');
    for await (rec of ref9) {
      if (!indoaj) {
        indoaj = rec;
      }
      if (ref10 = rec.bibjson.pissn, indexOf.call(issns, ref10) < 0) {
        issns.push(rec.bibjson.pissn);
      }
      if (ref11 = rec.bibjson.eissn, indexOf.call(issns, ref11) < 0) {
        issns.push(rec.bibjson.eissn);
      }
    }
    if (false) { //not indoaj?
      nisns = [];
      ref12 = this.index._for('src_openalex_venues', 'issn:"' + issns.join('" OR issn:"') + '"');
      for await (rec of ref12) {
        ref13 = rec.issn;
        for (l = 0, len2 = ref13.length; l < len2; l++) {
          en = ref13[l];
          if (indexOf.call(nisns, en) < 0) {
            nisns.push(en);
          }
        }
      }
      issns = nisns;
    }
    if (issns.length) {
      ps = (await this.permissions.journals('issuer.id:"' + issns.join('" OR issuer.id:"') + '"'));
      ref16 = (ref14 = ps != null ? (ref15 = ps.hits) != null ? ref15.hits : void 0 : void 0) != null ? ref14 : [];
      for (m = 0, len3 = ref16.length; m < len3; m++) {
        p = ref16[m];
        rp = (await _format(p._source));
        rp.score = (await _score(rp));
        perms.all_permissions.push(rp);
      }
    }
  }
  if (meta.publisher) {
    qr = 'issuer.id:"' + meta.publisher + '"'; // how exact/fuzzy can this be
    ps = (await this.permissions.publishers(qr));
    ref19 = (ref17 = ps != null ? (ref18 = ps.hits) != null ? ref18.hits : void 0 : void 0) != null ? ref17 : [];
    for (n = 0, len4 = ref19.length; n < len4; n++) {
      p = ref19[n];
      rp = (await _format(p._source));
      rp.score = (await _score(rp));
      perms.all_permissions.push(rp);
    }
  }
  altoa = {
    can_archive: true,
    version: 'publishedVersion',
    versions: ['publishedVersion'],
    licence: void 0,
    locations: ['institutional repository'],
    embargo_months: void 0,
    issuer: {
      type: 'Journal',
      has_policy: 'yes'
    },
    meta: {
      creator: 'joe+doaj@oa.works',
      contributors: ['joe+doaj@oa.works'],
      monitoring: 'Automatic'
    }
  };
  if (issns && (indoaj != null ? indoaj : indoaj = (await this.src.doaj.journals('bibjson.eissn.keyword:"' + issns.join('" OR bibjson.eissn.keyword:"') + '" OR bibjson.pissn.keyword:"' + issns.join('" OR bibjson.pissn.keyword:"') + '"', 1)))) {
    ref22 = (ref20 = (ref21 = indoaj.bibjson) != null ? ref21.license : void 0) != null ? ref20 : [];
    for (o = 0, len5 = ref22.length; o < len5; o++) {
      dl = ref22[o];
      if (!altoa.licence || altoa.licence.length > dl.type) {
        altoa.licence = dl.type;
      }
      if (altoa.licences == null) {
        altoa.licences = [];
      }
      altoa.licences.push({
        type: dl.type
      });
    }
    if ((altoa.licence == null) && (crj = (await this.src.crossref.journals('ISSN.keyword:"' + issns.join('" OR ISSN.keyword:"') + '"', 1)))) {
      ref24 = (ref23 = crj.license) != null ? ref23 : [];
      for (q = 0, len6 = ref24.length; q < len6; q++) {
        ll = ref24[q];
        if (!altoa.licence || altoa.licence.length > ll.type) {
          altoa.licence = ll.type;
        }
      }
    }
    if (typeof altoa.licence === 'string') {
      altoa.licence = altoa.licence.toLowerCase().trim();
      if (altoa.licence.startsWith('cc')) {
        altoa.licence = altoa.licence.replace(/ /g, '-');
      } else if (altoa.licence.includes('creative')) {
        altoa.licence = altoa.licence.includes('0') || altoa.licence.includes('zero') ? 'cc0' : altoa.licence.includes('share') ? 'ccbysa' : altoa.licence.includes('derivative') ? 'ccbynd' : 'ccby';
      } else {
        delete altoa.licence;
      }
    } else {
      delete altoa.licence;
    }
    altoa.issuer.id = indoaj.bibjson.eissn && indoaj.bibjson.pissn ? [indoaj.bibjson.pissn, indoaj.bibjson.eissn] : indoaj.bibjson.pissn ? [indoaj.bibjson.pissn] : [indoaj.bibjson.eissn];
    altoa.embargo_months = 0;
    altoa.provenance = {
      oa_evidence: 'In DOAJ'
    };
    altoa.score = (await _score(altoa));
    perms.all_permissions.push(altoa);
  } else if (!issns && meta.publisher && ((await this.permissions.publishers.oa(meta.publisher))).oa) {
    altoa.issuer.id = meta.publisher;
    altoa.meta.creator = ['joe+oapublisher@oa.works'];
    altoa.meta.contributors = ['joe+oapublisher@oa.works'];
    altoa.provenance = {
      oa_evidence: 'OA publisher' // does this mean embargo_months should be zero too?
    };
    altoa.score = (await _score(altoa));
    perms.all_permissions.push(altoa);
  }
  if (meta.doi) {
    if (oadoi == null) {
      oadoi = (await this.src.oadoi(meta.doi));
    }
    if (haddoi && (oadoi != null ? (ref25 = oadoi.best_oa_location) != null ? ref25.license : void 0 : void 0) && oadoi.best_oa_location.license.includes('cc')) { //  (haddoi or oadoi?.journal_is_oa)
      doa = {
        can_archive: true,
        version: oadoi.best_oa_location.version,
        versions: [],
        licence: oadoi.best_oa_location.license,
        locations: ['institutional repository'],
        issuer: {
          type: 'article',
          has_policy: 'yes',
          id: meta.doi
        },
        meta: {
          creator: 'support@unpaywall.org',
          contributors: ['support@unpaywall.org'],
          monitoring: 'Automatic',
          updated: oadoi.best_oa_location.updated
        },
        provenance: {
          oa_evidence: oadoi.best_oa_location.evidence
        }
      };
      if (doa.version) {
        doa.versions = (ref26 = doa.version) === 'submittedVersion' ? ['submittedVersion'] : (ref27 = doa.version) === 'acceptedVersion' ? ['submittedVersion', 'acceptedVersion'] : ['submittedVersion', 'acceptedVersion', 'publishedVersion'];
      }
      doa.score = (await _score(doa));
      perms.all_permissions.push(doa);
    }
  }
  // sort rors by score, and sort alts by score, then combine
  if (perms.all_permissions.length) {
    perms.all_permissions.sort((a, b) => {
      if (a.score < b.score) {
        return 1;
      } else {
        return -1;
      }
    });
    ref28 = perms.all_permissions;
    // note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for (r = 0, len7 = ref28.length; r < len7; r++) {
      wp = ref28[r];
      if (wp.licences == null) {
        wp.licences = [];
        if (wp.licence) {
          wp.licences.push({
            type: wp.licence
          });
        }
      }
      if (haddoi && ((ref29 = wp.issuer) != null ? ref29.journal_oa_type_from : void 0) && meta.published && Date.parse(meta.published) < Date.parse(wp.issuer.journal_oa_type_from)) {
        delete wp.issuer.journal_oa_type;
      }
      delete wp.issuer.journal_oa_type_from;
      if ((issns || ((ref30 = wp.issuer) != null ? ref30.type : void 0) === 'journal') && !wp.issuer.journal_oa_type) {
        wp.issuer.journal_oa_type = (await this.permissions.journals.oa.type(issns != null ? issns : wp.issuer.id, indoaj, oadoi, crossref));
      }
      if (!((ref31 = wp.provenance) != null ? ref31.enforcement_from : void 0)) {
        if (perms.best_permission == null) {
          perms.best_permission = this.copy(wp);
        }
      } else if (!meta.published || Date.parse(meta.published) > Date.parse(wp.provenance.enforcement_from.split('/').reverse().join('-'))) {
        // NOTE Date.parse would try to work on format 31/01/2020 but reads it in American, so would think 31 is a month and is too big
        // but 2020-01-31 is treated in ISO so the 31 will be the day. So, given that we use DD/MM/YYYY, split on / then reverse then join on - to get a better parse
        if (perms.best_permission == null) {
          perms.best_permission = this.copy(wp);
        }
      }
    }
    if (rors.length) { // this only happens as an augment to some other permission, so far
      rors.sort((a, b) => {
        if (a.score < b.score) {
          return 1;
        } else {
          return -1;
        }
      });
// check this gives the order in the direction we want, else reverse it
      for (s = 0, len8 = rors.length; s < len8; s++) {
        ro = rors[s];
        if (haddoi && ((ref32 = ro.issuer) != null ? ref32.journal_oa_type_from : void 0) && meta.published && Date.parse(meta.published) < Date.parse(ro.issuer.journal_oa_type_from)) {
          delete ro.issuer.journal_oa_type;
        }
        delete ro.issuer.journal_oa_type_from;
        if ((issns || ((ref33 = ro.issuer) != null ? ref33.type : void 0) === 'journal') && !ro.issuer.journal_oa_type) {
          ro.issuer.journal_oa_type = (await this.permissions.journals.oa.type(issns != null ? issns : ro.issuer.id, indoaj, oadoi, crossref));
        }
        perms.all_permissions.push(ro);
        if (((ref34 = perms.best_permission) != null ? ref34.author_affiliation_requirement : void 0) == null) {
          if (perms.best_permission != null) {
            if (!((ref35 = ro.provenance) != null ? ref35.enforcement_from : void 0) || !meta.published || Date.parse(meta.published) > Date.parse(ro.provenance.enforcement_from.split('/').reverse().join('-'))) {
              pb = this.copy(perms.best_permission);
              ref36 = ['versions', 'locations'];
              for (t = 0, len9 = ref36.length; t < len9; t++) {
                key = ref36[t];
                ref37 = ro[key];
                for (u = 0, len10 = ref37.length; u < len10; u++) {
                  vl = ref37[u];
                  if (pb[key] == null) {
                    pb[key] = [];
                  }
                  if (indexOf.call(pb[key], vl) < 0) {
                    pb[key].push(vl);
                  }
                }
              }
              pb.version = indexOf.call(pb.versions, 'publishedVersion') >= 0 ? 'publishedVersion' : indexOf.call(pb.versions, 'acceptedVersion') >= 0 ? 'acceptedVersion' : 'submittedVersion';
              if (pb.embargo_end) {
                if (ro.embargo_end) {
                  if (Date.parse(ro.embargo_end) < Date.parse(pb.embargo_end)) {
                    pb.embargo_end = ro.embargo_end;
                  }
                }
              }
              if (pb.embargo_months && (ro.embargo_months != null) && ro.embargo_months < pb.embargo_months) {
                pb.embargo_months = ro.embargo_months;
              }
              if (ro.can_archive === true) {
                pb.can_archive = true;
              }
              if (pb.requirements == null) {
                pb.requirements = {};
              }
              pb.requirements.author_affiliation_requirement = meta.ror == null ? ro.issuer.id : typeof meta.ror === 'string' ? meta.ror : meta.ror[0];
              pb.issuer.affiliation = ro.issuer;
              if (pb.meta == null) {
                pb.meta = {};
              }
              pb.meta.affiliation = ro.meta;
              if (pb.provenance == null) {
                pb.provenance = {};
              }
              pb.provenance.affiliation = ro.provenance;
              pb.score = parseInt(pb.score) + parseInt(ro.score);
              perms.best_permission = pb;
              perms.all_permissions.push(pb);
            }
          }
        }
      }
    }
  }
  if (overall_policy_restriction) {
    msgs = {
      'not publisher': 'Please find another DOI for this article as this is provided as this does not allow us to find required information like who published it'
    };
    return {
      body: typeof overall_policy_restriction !== 'string' ? overall_policy_restriction : (ref38 = msgs[overall_policy_restriction.toLowerCase()]) != null ? ref38 : overall_policy_restriction,
      status: 501
    };
  } else {
    if (meta.doi && !rors.length && perms.best_permission) {
      bp = (await this.copy(perms.best_permission));
      bp.updated = (await this.epoch());
      bp.DOI = meta.doi;
      this.waitUntil(this.permissions.best(bp));
    }
    if (this.params.metadata === true || getmeta === true) {
      perms.metadata = meta;
    }
    return perms;
  }
};

P.permissions._log = false;

P.permissions.best = {
  _index: true,
  _key: 'DOI' // save calculated best permissions for cases where that is good enough. TODO could update them every week
};

P.permissions.journals = {
  _sheet: '1ZTcYJUzhNJYIuxsjKzdVFCbOhJsviVik-8K1DpU7-eE/Main',
  _prefix: false,
  _format: async function(recs = []) {
    var af, an, cids, i, j, k, kn, l, len, len1, len2, nid, nr, ready, rec, ref, ref1, ref2, ref3;
    ready = [];
    ref = (typeof recs === 'object' && !Array.isArray(recs) ? [recs] : recs);
    for (i = 0, len = ref.length; i < len; i++) {
      rec = ref[i];
      nr = { // a controlled structure for JSON output, can't be guaranteed as not JSON spec, but Joe likes it for visual review
        can_archive: void 0,
        version: void 0,
        versions: [],
        licence: void 0,
        locations: void 0,
        embargo_months: void 0,
        embargo_end: void 0,
        deposit_statement: void 0,
        copyright_owner: '',
        copyright_name: '',
        copyright_year: '',
        issuer: {},
        meta: {},
        provenance: {},
        requirements: {}
      };
      for (k in rec) {
        if (typeof rec[k] === 'string') {
          rec[k] = rec[k].trim();
        }
        if (k === 'id') {
          nr.issuer.id = typeof rec.id === 'string' && rec.id.includes(',') ? rec.id.split(',') : rec.id;
          if (typeof nr.issuer.id === 'string' && nr.issuer.id.startsWith('10.') && nr.issuer.id.includes('/') && !nr.issuer.id.includes(' ')) {
            nr.DOI = nr.issuer.id;
          } else {
            cids = [];
            ref1 = (typeof nr.issuer.id === 'string' ? [nr.issuer.id] : nr.issuer.id);
            for (j = 0, len1 = ref1.length; j < len1; j++) {
              nid = ref1[j];
              nid = nid.trim();
              if (nr.issuer.type === 'journal' && nid.includes('-') && !nid.includes(' ')) {
                nid = nid.toUpperCase();
                if (af = (await this.journal('ISSN:"' + nid + '"', 1))) {
                  ref2 = af.issn;
                  //if af = await @src.openalex.venues 'issn:"' + nid + '"', 1
                  for (l = 0, len2 = ref2.length; l < len2; l++) {
                    an = ref2[l];
                    if (indexOf.call(cids, an) < 0) {
                      cids.push(an);
                    }
                  }
                }
              }
              if (indexOf.call(cids, nid) < 0) {
                cids.push(nid);
              }
            }
            nr.issuer.id = cids;
          }
        } else if (k === 'embargo_months') {
          kn = typeof rec[k] === 'number' ? rec[k] : typeof rec[k] === 'string' ? parseInt(rec[k].trim()) : void 0;
          if (kn && typeof kn === 'number') {
            nr.embargo_months = kn;
            nr.embargo_end = ''; // just to allow neat output later - can't be calculated until compared to a particular article
          }
        } else if (k && (rec[k] != null) && ((ref3 = rec[k]) !== '' && ref3 !== 'none' && ref3 !== 'unclear')) {
          if (k === 'versions' && rec.versions.length) {
            nr.can_archive = true;
            nr.version = rec.versions.includes('ublish') ? 'publishedVersion' : rec.versions.includes('ccept') ? 'acceptedVersion' : 'submittedVersion';
          }
          if (k === 'versions' || k === 'locations' || k === 'meta.contributors' || k === 'meta.creator' || k === 'meta.reviewer' || k === 'provenance.archiving_policy' || k === 'requirements.funder' || k === 'journal') {
            rec[k] = rec[k].trim().replace(/\, /, ',').replace(/ \,/, ',').split(',');
          }
          await this.dot(nr, (k === 'license' ? 'licence' : k), rec[k]);
        }
      }
      if ((!nr.copyright_owner || nr.copyright_owner.toLowerCase() === 'journal') && nr.issuer.type) {
        nr.copyright_owner = nr.issuer.type;
      }
      if (JSON.stringify(nr.requirements) === '{}') {
        delete nr.requirements;
      }
      ready.push(nr);
    }
    if (ready.length === 1) {
      return ready[0];
    } else {
      return ready;
    }
  }
};

P.permissions.publishers = {
  _sheet: '11rsHmef1j9Q9Xb0WtQ_BklQceaSkkFEIm7tJ4qz0fJk/Main',
  _prefix: false,
  _format: P.permissions.journals._format
};

P.permissions.affiliations = {
  _sheet: '15fa1DADj6y_3aZQcP9-zBalhaThxzZw9dyEbxMBBb5Y/Main',
  _prefix: false,
  _format: P.permissions.journals._format
};

P.permissions.journals.example = async function(issn) {
  var ref, res;
  if (issn == null) {
    issn = (ref = this.params.doi) != null ? ref : this.params.issn;
  }
  if (typeof issn === 'string') {
    issn = issn.split(',');
  }
  try {
    res = (await this.src.crossref.works('ISSN:"' + issn.join('" OR ISSN:"') + '"', 1));
    return res.DOI;
  } catch (error) {}
};

P.permissions.journals.example._log = false;

P.permissions.journals.transformative = {
  _index: true,
  _prefix: false
};

P.permissions.journals.transformative.load = async function() {
  var batch, i, len, rec, ref, tfs;
  batch = [];
  tfs = (await this.fetch('https://api.journalcheckertool.org/journal?q=tj:true&include=issn&size=10000'));
  ref = tfs.hits.hits;
  for (i = 0, len = ref.length; i < len; i++) {
    rec = ref[i];
    batch.push(rec._source);
  }
  if (batch.length) {
    await this.permissions.journals.transformative('');
    await this.permissions.journals.transformative(batch);
  }
  return batch.length;
};

P.permissions.journals.transformative.load._bg = true;

P.permissions.journals.transformative.load._async = true;

P.permissions.journals.transformative.load._auth = 'root';

P.permissions.journals.oa = async function(issn, oadoi) {
  var ex, jr, ref, ref1, ref2, ref3, ret;
  try {
    // NOTE it is still to be decided what licence is acceptable to be counted as OA on the crossref index. For now it's anything CC, including NC
    if (issn == null) {
      issn = (ref = (ref1 = (ref2 = this.params.journals) != null ? ref2 : this.params.journal) != null ? ref1 : this.params.issn) != null ? ref : this.params.oa;
    }
  } catch (error) {}
  ret = {};
  if (issn) {
    ret.articles = (await this.src.crossref.works.count('type:"journal-article" AND ISSN:"' + issn + '"'));
    ret.open = (await this.src.crossref.works.count('type:"journal-article" AND ISSN:"' + issn + '" AND is_oa:true')); // could add AND NOT licence:nc
    if (ret.articles === ret.open) {
      ret.oa = true;
    }
    if (jr = (await this.src.doaj.journals('bibjson.pissn:"' + issn + '" OR bibjson.eissn:"' + issn + '"', 1))) {
      ret.open = ret.articles;
      ret.doaj = true;
      ret.oa = true;
    }
    if (ex = (await this.permissions.journals.example(issn))) {
      if (oadoi == null) {
        oadoi = (await this.src.oadoi(ex, 1));
      }
      if (oadoi != null) {
        delete ret.oa;
        ret.open = ret.articles;
        ret.oadoi = true;
        ret.oa = (oadoi != null ? (ref3 = oadoi.best_oa_location) != null ? ref3.license : void 0 : void 0) && oadoi.best_oa_location.license.includes('cc'); // oadoi.journal_is_oa
      } else {
        ret.oa = false;
      }
    }
  }
  return ret;
};

P.permissions.journals.oa._log = false;

P.permissions.journals.oa.type = async function(issns, doajrnl, oadoi, crossref) {
  var js, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8;
  if (issns == null) {
    issns = (ref = (ref1 = (ref2 = (ref3 = (ref4 = (ref5 = oadoi != null ? oadoi.journal_issns : void 0) != null ? ref5 : crossref != null ? crossref.ISSN : void 0) != null ? ref4 : this.params.journals) != null ? ref3 : this.params.journal) != null ? ref2 : this.params.type) != null ? ref1 : this.params.issn) != null ? ref : this.params.issns;
  }
  if (typeof issns === 'string') {
    if (issns.includes('doi.org/')) {
      issns = issns.split('doi.org/')[1];
    }
    if (issns.startsWith('10.')) {
      if (oadoi == null) {
        oadoi = (await this.src.oadoi(issns));
      }
      if (crossref == null) {
        crossref = (await this.src.crossref.works(issns));
      }
      issns = (ref6 = oadoi != null ? oadoi.journal_issns : void 0) != null ? ref6 : crossref != null ? crossref.ISSN : void 0;
    }
  }
  if (typeof issns === 'string') {
    issns = issns.split(',');
  }
  js = 'unknown';
  if (((crossref != null ? crossref.type : void 0) != null) && crossref.type !== 'journal-article') {
    js = 'not applicable';
  } else if (!(crossref != null ? crossref.type : void 0) || crossref.type === 'journal-article') {
    js = (oadoi != null ? oadoi.oa_status : void 0) === 'gold' || (oadoi != null ? oadoi.journal_is_oa : void 0) || (oadoi != null ? oadoi.journal_is_in_doaj : void 0) ? 'gold' : (oadoi != null ? oadoi.oa_status : void 0) === 'bronze' ? 'closed' : (oadoi != null ? oadoi.oa_status : void 0) === 'hybrid' ? 'hybrid' : 'closed';
    if ((doajrnl == null) && issns) {
      doajrnl = (await this.src.doaj.journals('bibjson.eissn.keyword:"' + issns.join('" OR bibjson.eissn.keyword:"') + '" OR bibjson.pissn.keyword:"' + issns.join('" OR bibjson.pissn.keyword:"') + '"', 1));
    }
    if (doajrnl != null) {
      js = ((ref7 = doajrnl.bibjson) != null ? (ref8 = ref7.apc) != null ? ref8.has_apc : void 0 : void 0) === false ? 'diamond' : 'gold';
    } else if (issns) {
      if (issns && (await this.permissions.journals.transformative.count('issn:"' + issns.join('" OR issn:"') + '"'))) {
        js = 'transformative';
      } else if (js === 'closed' && (await this.src.oadoi.hybrid(issns))) {
        // check if it really is closed because sometimes OADOI says it is for one particular DOI but really it isn't (or was at time of publication of that article, but isn't now)
        js = 'hybrid';
      }
    }
  }
  return js;
};

P.permissions.journals.oa.type._log = false;

P.permissions.publishers.oa = async function(publisher) {
  var fz, lvs, ref, ret;
  ret = {
    publisher: ((ref = publisher != null ? publisher : this.params.publisher) != null ? ref : this.params.oa).replace(/&/g, '')
  };
  if (!(await this.src.crossref.journals('publisher:"' + ret.publisher + '"', 1))) {
    if (fz = (await this.src.crossref.journals('publisher:"' + ret.publisher.split(' ').join('" AND publisher:"') + '"', 1))) {
      if (fz.publisher.toLowerCase() !== ret.publisher.toLowerCase()) {
        lvs = (await this.levenshtein(fz.publisher, ret.publisher));
        if (lvs.distance < 5 || (lvs.length.a > lvs.length.b ? lvs.length.a : lvs.length.b) / lvs.distance > 10) {
          ret.publisher = fz.publisher;
        }
      }
    } else {
      ret.journals = 0;
    }
  }
  if (ret.journals == null) {
    ret.journals = (await this.src.crossref.journals.count('publisher:"' + ret.publisher + '" AND NOT discontinued:true'));
  }
  ret.open = (await this.src.doaj.journals.count('publisher:"' + ret.publisher + '" AND NOT bibjson.discontinued_date:* AND NOT .bibjson.is_replaced_by:*'));
  ret.percent = ret.journals ? Math.ceil((ret.open / ret.journals) * 100) : ret.open ? 100 : 0;
  ret.oa = (!ret.journals && ret.open) || (ret.journals && ret.journals === ret.open);
  return ret;
};

P.permissions.publishers.oa._log = false;

var _do_batch, _done_batch, _processed_batch, _processed_batch_last, _processing_dois, _queue_batch, _queue_batch_last, _queued_batch,
  indexOf = [].indexOf;

try {
  S.report = JSON.parse(SECRETS_REPORT);
} catch (error) {}

if (S.report == null) {
  S.report = {};
}

P.report = function() {
  return 'OA.Works report';
};

_queue_batch = [];

_queued_batch = [];

_queue_batch_last = Date.now();

_do_batch = [];

_done_batch = [];

_processing_dois = [];

_processed_batch = [];

_processed_batch_last = Date.now();

P.report.queued = {
  _index: true //, _auth: '@oa.works'
};

P.report.queue = async function(dois, ol, refresh, everything, action) {
  var batch, d, doi, j, len, ref, ref1, rf, thedoi;
  if (this.params.empty) {
    await this.report.queued('');
  }
  if (dois == null) {
    dois = (ref = this.params.queue) != null ? ref : this.params.doi;
  }
  if (ol == null) {
    ol = this.params.ol;
  }
  if (refresh == null) {
    refresh = this.refresh;
  }
  if (everything == null) {
    everything = this.params.everything;
  }
  if (dois) {
    ref1 = (!Array.isArray(dois) ? [dois] : dois);
    for (j = 0, len = ref1.length; j < len; j++) {
      doi = ref1[j];
      thedoi = typeof doi === 'object' ? doi.DOI : doi;
      if (thedoi && typeof thedoi === 'string' && thedoi.startsWith('10.') && indexOf.call(_queued_batch, thedoi) < 0) {
        _queued_batch.push(thedoi);
        rf = typeof doi === 'object' && (doi.refresh != null) ? doi.refresh : refresh;
        rf = rf === true ? 0 : rf === false ? void 0 : rf;
        _queue_batch.push({
          doi: thedoi,
          ol: (typeof doi === 'object' && (doi.ol != null) ? doi.ol : ol),
          refresh: rf,
          everything: (typeof doi === 'object' && (doi.everything != null) ? doi.everything : everything),
          action: (typeof doi === 'object' && (doi.action != null) ? doi.action : action)
        });
      }
    }
  }
  if (_queue_batch.length > 2000 || Date.now() > (_queue_batch_last + 15000)) {
    batch = [];
    while (d = _queue_batch.shift()) {
      _queued_batch.shift();
      batch.push({
        _id: d.doi,
        DOI: d.doi,
        ol: d.ol,
        refresh: d.refresh,
        everything: d.everything,
        action: d.action,
        createdAt: Date.now()
      });
    }
    if (batch.length) {
      await this.report.queued(batch);
    }
    _queue_batch_last = Date.now();
  }
  return {
    queue: _queue_batch.length
  };
};

P.report.queue._log = false;

P.report.queue._auth = '@oa.works';

P.report.runqueue = async function(doi, qry = 'NOT action:*') {
  var batch, d, ddd, j, len, opts, q, qd, ref, ref1, ref2, ref3, ref4;
  if (doi == null) {
    doi = this.params.runqueue;
  }
  if (doi != null) {
    qry = 'for requested doi ' + doi;
  } else {
    if (!_do_batch.length) {
      q = (await this.report.queued(qry, {
        size: 2000,
        sort: {
          createdAt: 'desc'
        }
      }));
      if (!(q != null ? (ref = q.hits) != null ? ref.total : void 0 : void 0) && qry === 'NOT action:*' && ((this.S.async_runner == null) || ((await this.keys(this.S.async_runner))).length < 2)) { //isnt '*' # do anything if there are no specific ones to do
        console.log('no queued records found for specified qry', qry, 'checking for any other queued records...');
        q = (await this.report.queued('*', {
          size: 2000,
          sort: {
            createdAt: 'desc'
          }
        }));
        qry = 'queried * as none for qry ' + qry;
      }
      if (!(q != null ? (ref1 = q.hits) != null ? ref1.total : void 0 : void 0) && !_queue_batch.length) {
        console.log('no queued records to process, waiting 5s...');
        await this.sleep(5000);
      }
      ref4 = (ref2 = q != null ? (ref3 = q.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
      for (j = 0, len = ref4.length; j < len; j++) {
        qd = ref4[j];
        _do_batch.push(qd._source);
      }
    } else {
      qry = '';
    }
    opts = _do_batch.shift();
    doi = opts != null ? opts.DOI : void 0;
  }
  console.log('report run queue', qry, doi, opts, _done_batch.length, _processed_batch.length, _processing_dois, _processing_dois.length);
  if (typeof doi === 'string' && doi.startsWith('10.') && indexOf.call(_processing_dois, doi) < 0 && indexOf.call(_done_batch, doi) < 0) {
    await this.sleep(10);
    while (_processing_dois.length >= 5) {
      await this.sleep(500);
    }
    _processing_dois.push(doi);
    this.report.works.process(doi, opts != null ? opts.ol : void 0, opts != null ? opts.refresh : void 0, opts != null ? opts.everything : void 0, void 0, doi);
  }
  if (_processed_batch.length >= 2000 || Date.now() > (_processed_batch_last + 15000) || (_processing_dois.length === 0 && indexOf.call(_done_batch, doi) >= 0)) {
    console.log('run queue saving batch', _processed_batch.length);
    await this.report.works(_processed_batch); // NOTE - if these are NOT run on separate worker processes (see below) there could be duplication here
    _processed_batch = []; // or a risk of deleting unsaved ones here
    while (ddd = _done_batch.shift()) {
      await this.report.queued(ddd, '');
    }
    _processed_batch_last = Date.now();
  }
  if (_queue_batch.length > 2000 || Date.now() > (_queue_batch_last + 15000)) {
    batch = [];
    while (d = _queue_batch.shift()) {
      _queued_batch.shift();
      batch.push({
        _id: d.doi,
        DOI: d.doi,
        ol: d.ol,
        refresh: d.refresh,
        everything: d.everything,
        createdAt: Date.now()
      });
    }
    console.log('run queue saving queued batch', _queue_batch.length, batch.length);
    if (batch.length) {
      await this.report.queued(batch);
    }
    _queue_batch_last = Date.now();
  }
  return true;
};

// for each of the below, add a loop schedule to have them running - run them on SEPARATE worker processes, via settings
P.report.doqueue = function(doi, qry) {
  return this.report.runqueue(doi != null ? doi : this.params.doqueue, qry != null ? qry : this.params.q);
};

P.report.doqueue._log = false;

P.report.doqueue._auth = '@oa.works';

P.report.doqueue._bg = true;

P.report.dochangesqueue = function(doi, qry = 'action:"changes" OR action:"years"') {
  return this.report.runqueue(doi != null ? doi : this.params.dochangesqueue, qry != null ? qry : this.params.q);
};

P.report.dochangesqueue._log = false;

P.report.dochangesqueue._auth = '@oa.works';

P.report.dochangesqueue._bg = true;

P.report.dev2live = async function(reverse) {
  var batch, counter, f, ref, rm, t, toalias;
  toalias = this.params.toalias;
  if (typeof toalias === 'number') {
    toalias += '';
  }
  if (!reverse) {
    f = 'paradigm_b_report_works';
    t = 'paradigm_report_works';
  } else {
    f = 'paradigm_report_works';
    t = 'paradigm_b_report_works';
  }
  if (this.params.clear) {
    await this.index._send(t, '', void 0, false, toalias);
  }
  counter = 0;
  batch = [];
  ref = this.index._for(f);
  // q, opts, prefix, alias
  for await (rm of ref) {
    counter += 1;
    if (rm.DOI && !rm.DOI.includes(' pmcid:') && !rm.DOI.includes('\n') && !rm.DOI.includes('?ref')) {
      batch.push(rm);
    }
    if (batch.length === 30000) {
      console.log('report works', (reverse ? 'live2dev' : 'dev2live'), f, t, toalias, counter);
      await this.index._bulk(t, batch, void 0, void 0, false, toalias);
      batch = [];
    }
  }
  if (batch.length) {
    await this.index._bulk(t, batch, void 0, void 0, false, toalias);
    batch = [];
  }
  return counter;
};

P.report.dev2live._async = true;

P.report.dev2live._bg = true;

//P.report.dev2live._auth = 'root'
P.report.live2dev = function() {
  return this.report.dev2live(true);
};

P.report.live2dev._async = true;

P.report.live2dev._bg = true;

P.report.live2dev._auth = 'root';

P.report.oapolicy = {
  _sheet: S.report.oapolicy_sheet,
  _format: function(recs = []) {
    var bs, err, h, j, len, nr, ready, rec, ref;
    ready = [];
    bs = 0;
    ref = (typeof recs === 'object' && !Array.isArray(recs) ? [recs] : recs);
    for (j = 0, len = ref.length; j < len; j++) {
      rec = ref[j];
      nr = {};
      for (h in rec) {
        if (typeof rec[h] === 'string') {
          rec[h] = rec[h].trim();
          if (rec[h].toLowerCase() === 'true') {
            rec[h] = true;
          } else if (rec[h].toLowerCase() === 'false') {
            rec[h] = false;
          } else if ((rec[h].startsWith('[') && rec[h].endsWith(']')) || (rec[h].startsWith('{') && rec[h].endsWith('}'))) {
            try {
              rec[h] = JSON.parse(rec[h]);
            } catch (error) {
              err = error;
              console.log('cant parse ' + h, rec[h], err);
              bs += 1;
            }
          } else if (rec[h].includes(';')) {
            rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';');
          }
        }
        if ((rec[h] != null) && rec[h] !== '') {
          if (h.includes('.')) {
            try {
              this.dot(nr, h, rec[h]);
            } catch (error) {}
          } else {
            nr[h] = rec[h];
          }
        }
      }
      if (JSON.stringify(nr) !== '{}') {
        //nr._id = nr.uid
        ready.push(nr);
      }
    }
    if (ready.length === 1) {
      return ready[0];
    } else {
      return ready;
    }
  }
};

P.report.cleandoi = function(doi) {
  var ref;
  if (doi == null) {
    doi = (ref = this.params.cleandoi) != null ? ref : this.params.doi;
  }
  try {
    if (doi.startsWith('http')) {
      doi = '10.' + doi.split('/10.')[1];
    }
  } catch (error) {}
  try {
    if (doi.startsWith('doi ')) {
      doi = doi.toLowerCase().replace('doi ', '');
    }
  } catch (error) {}
  try {
    doi = doi.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').replace(/^\//, '').split(' ')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim();
  } catch (error) {}
  try {
    doi = doi.split(',http')[0];
  } catch (error) {}
  if (typeof doi === 'string' && doi.startsWith('10.')) {
    return doi;
  } else {
    return '';
  }
};

P.report.cleandoi._log = false;

P.report.orgs = {
  _sheet: S.report.orgs_sheet,
  _format: async function(recs = []) {
    var bs, err, h, j, l, len, len1, nr, ready, rec, ref, ref1, s;
    ready = [];
    bs = 0;
    ref = (typeof recs === 'object' && !Array.isArray(recs) ? [recs] : recs);
    for (j = 0, len = ref.length; j < len; j++) {
      rec = ref[j];
      nr = {};
      for (h in rec) {
        if (typeof rec[h] === 'string') {
          rec[h] = rec[h].trim();
          if (rec[h].toLowerCase() === 'true') {
            rec[h] = true;
          } else if (rec[h].toLowerCase() === 'false') {
            rec[h] = false;
          } else if ((rec[h].startsWith('[') && rec[h].endsWith(']')) || (rec[h].startsWith('{') && rec[h].endsWith('}'))) {
            try {
              rec[h] = JSON.parse(rec[h]);
            } catch (error) {
              err = error;
              console.log('cant parse ' + h, rec[h], err);
              bs += 1;
            }
          } else if (rec[h].includes(';')) {
            rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';');
          }
        }
        if (h.includes('.')) {
          try {
            this.dot(nr, h, rec[h]);
          } catch (error) {}
        } else {
          nr[h] = rec[h];
        }
      }
      if (Array.isArray(nr.sheets)) {
        ref1 = nr.sheets;
        for (l = 0, len1 = ref1.length; l < len1; l++) {
          s = ref1[l];
          s.url = (await this.encrypt(s.url));
        }
      } else {
        delete nr.sheets;
      }
      if (JSON.stringify(nr) !== '{}') {
        ready.push(nr);
      }
    }
    if (ready.length === 1) {
      return ready[0];
    } else {
      return ready;
    }
  }
};

P.report.orgs.orgkeys = {
  _index: true,
  _auth: '@oa.works'
};

P.report.orgs.key = async function(org) {
  var key, rec;
  if (org == null) {
    org = this.params.org;
  }
  if (org == null) {
    return void 0;
  }
  org = org.toLowerCase();
  rec = (await this.report.orgs.orgkeys('org.keyword:"' + org + '"', 1));
  if ((rec == null) || this.refresh) {
    if (rec != null) {
      rec.lastRefreshedAt = (await this.epoch());
      try {
        rec.lastRefreshedBy = this.user.email;
      } catch (error) {}
    } else {
      rec = {
        org: org,
        createdAt: (await this.epoch())
      };
      try {
        rec.createdBy = this.user.email;
      } catch (error) {}
    }
    key = (await this.uid());
    rec.key = (await this.encrypt(key));
    await this.report.orgs.orgkeys(rec);
    return key;
  } else {
    rec.lastRetrievedAt = (await this.epoch());
    try {
      rec.lastRetrievedBy = this.user.email;
    } catch (error) {}
    await this.report.orgs.orgkeys(rec);
    return this.decrypt(rec.key);
  }
};

P.report.orgs.key._log = false;

P.report.orgs.key._auth = '@oa.works';

P.report.orgs.supplements = {
  _index: true,
  _auth: '@oa.works'
};

P.report.orgs.supplements.load = async function(orgname, sheetname, clear) {
  var aps, check, dois, h, header, headers, hp, hpv, j, l, last, latest, ld, len, len1, len2, len3, len4, len5, lt, m, n, org, osdids, osw, p, ptc, r, rc, rec, recs, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref3, ref4, ref5, ref6, ref7, ref8, ref9, replacements, row, rows, rr, s, sheetnames, sheets, sheets_latest, started, sup, sups, total, tries, update;
  started = (await this.epoch());
  if (this.fn === 'report.orgs.supplements.load') {
    if (clear == null) {
      clear = this.params.clear;
    }
  }
  if (clear) {
    await this.report.orgs.supplements('');
  }
  if (orgname == null) {
    orgname = this.params.org;
  }
  if (sheetname == null) {
    sheetname = this.params.sheet;
  }
  recs = (await this.src.google.sheets(S.report.orgs_sheet));
  total = 0;
  dois = [];
  replacements = {};
  sheets = [];
  sheets_latest = {};
  sheetnames = [];
  if (!clear) {
    ref = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', 'replaced:*');
    for await (sup of ref) {
      replacements[sup.replaced] = sup.DOI;
    }
  }
  ref1 = (typeof recs === 'object' && !Array.isArray(recs) ? [recs] : recs);
  for (j = 0, len = ref1.length; j < len; j++) {
    rec = ref1[j];
    org = {};
    for (h in rec) {
      if (typeof rec[h] === 'string') {
        rec[h] = rec[h].trim();
        if (rec[h].toLowerCase() === 'true') {
          rec[h] = true;
        } else if (rec[h].toLowerCase() === 'false') {
          rec[h] = false;
        } else if ((rec[h].startsWith('[') && rec[h].endsWith(']')) || (rec[h].startsWith('{') && rec[h].endsWith('}'))) {
          try {
            rec[h] = JSON.parse(rec[h]);
          } catch (error) {}
        } else if (rec[h].includes(';')) {
          rec[h] = rec[h].replace(/; /g, ';').replace(/ ;/g, ';').trim().split(';');
        }
      }
      if (h.includes('.')) {
        try {
          await this.dot(org, h, rec[h]);
        } catch (error) {}
      } else {
        org[h] = rec[h];
      }
    }
    if (Array.isArray(org.sheets)) {
      ref2 = org.sheets;
      for (l = 0, len1 = ref2.length; l < len1; l++) {
        s = ref2[l];
        if ((!orgname || org.name === orgname) && (!sheetname || s.name === sheetname)) {
          console.log(org.name, s.name, s.url);
          rc = 0;
          osdids = [];
          headers = [];
          rows = [];
          update = (ref3 = this.params.update) != null ? ref3 : true;
          last = false;
          sups = [];
          await this.sleep(1000);
          if (this.params.update == null) { // can force an update on URL call
            try {
              check = (await this.src.google.sheets({
                sheetid: s.url,
                sheet: 'm_admin',
                headers: false
              }));
              await this.sleep(1000); // more sleeps to avoid google 429 sadness
              if (Array.isArray(check) && check.length && check[0][0].toLowerCase() === 'last updated' && (last = check[0][1])) {
                [ld, lt] = last.split(' ');
                ld = ld.split('/').reverse().join('-');
                last = (await this.epoch(ld + 'T' + lt));
                console.log(org.name, s.name, 'last updated', last);
                if (typeof last === 'number' && last > 1672531200000) { // start of 2023, just in case of a bad date
                  if (!(latest = sheets_latest[s.name])) {
                    try {
                      latest = (await this.report.orgs.supplements('sheets.keyword:"' + s.name + '"', {
                        size: 1,
                        sort: {
                          updated: 'desc'
                        }
                      }));
                    } catch (error) {}
                    if ((latest != null ? (ref4 = latest.hits) != null ? ref4.hits : void 0 : void 0) != null) {
                      latest = latest.hits.hits[0]._source;
                      sheets_latest[s.name] = latest;
                    }
                  }
                  if ((latest != null ? latest.updated : void 0) && last <= latest.updated) {
                    update = last;
                  }
                }
              } else {
                if (!(latest = sheets_latest[s.name])) {
                  try {
                    latest = (await this.report.orgs.supplements('sheets.keyword:"' + s.name + '"', {
                      size: 1,
                      sort: {
                        updated: 'desc'
                      }
                    }));
                  } catch (error) {}
                  if ((latest != null ? (ref5 = latest.hits) != null ? ref5.hits : void 0 : void 0) != null) {
                    latest = latest.hits.hits[0]._source;
                    sheets_latest[s.name] = latest;
                  }
                }
                if ((latest != null ? latest.updated : void 0) && latest.updated >= (started - 86400000)) {
                  update = false;
                }
              }
            } catch (error) {}
          }
          if (update !== true) {
            console.log(org.name, s.name, 'NOT loading because', last, 'is not after', update);
          } else {
            await this.sleep(1000);
            try {
              rows = (await this.src.google.sheets({
                sheetid: s.url,
                sheet: 'Export',
                headers: false
              }));
            } catch (error) {}
            tries = 0;
            while ((!Array.isArray(rows) || !rows.length) && tries < 5) { // https://github.com/oaworks/Gates/issues/375
              await this.sleep(5000);
              tries += 1;
              try {
                rows = (await this.src.google.sheets({
                  sheetid: s.url,
                  sheet: 'Export',
                  headers: false
                }));
              } catch (error) {}
            }
            if (Array.isArray(rows) && rows.length) {
              ref6 = rows.shift();
              for (m = 0, len2 = ref6.length; m < len2; m++) {
                header = ref6[m];
                headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', ''));
              }
              for (n = 0, len3 = rows.length; n < len3; n++) {
                row = rows[n];
                rc += 1;
                rr = {
                  org: org.name,
                  sheets: s.name,
                  ror: org.ror,
                  paid: (org.paid === true ? org.paid : void 0) // check paid explicitly because some had an empty string instead of a bool
                };
                for (hp in headers) {
                  h = headers[hp];
                  if (h === 'doi' || h === 'DOI') {
                    rr[h] = row[hp];
                  } else {
                    hpv = '';
                    if (h === 'apc_cost' || h === 'wellcome.apc_paid_actual_currency_excluding_vat' || h === 'wellcome.apc_paid_gbp_inc_vat_if_charged' || h === 'wellcome.additional_publication_fees_gbp' || h === 'wellcome.amount_of_apc_charged_to_coaf_grant_inc_vat_if_charged_in_gbp' || h === 'wellcome.amount_of_apc_charged_to_rcuk_oa_fund_inc_vat_if_charged_in_gbp' || h === 'wellcome.amount_of_apc_charged_to_wellcome_grant_inc_vat_in_gbp') {
                      try {
                        hpv = parseFloat(row[hp]);
                      } catch (error) {}
                    } else {
                      hpv = typeof row[hp] === 'number' ? row[hp] : !row[hp] ? void 0 : (ref7 = row[hp].trim().toLowerCase()) === 'true' || ref7 === 'yes' ? true : (ref8 = row[hp].trim().toLowerCase()) === 'false' || ref8 === 'no' ? false : (ref9 = h.toLowerCase()) === 'grant_id' || ref9 === 'ror' ? row[hp].replace(/\//g, ',').replace(/ /g, '').split(',') : row[hp];
                      if (typeof row[hp] === 'string' && row[hp].includes(';')) {
                        hpv = row[hp].split(';');
                      }
                    }
                    if ((hpv != null) && hpv !== '') {
                      if (h.includes('.')) {
                        await this.dot(rr, h, hpv);
                      } else {
                        rr[h] = hpv;
                      }
                    }
                  }
                }
                if (!rr.doi) {
                  rr.doi = ((ref10 = rr.DOI) != null ? ref10 : '') + '';
                } else {
                  if (rr.DOI == null) {
                    rr.DOI = rr.doi + '';
                  }
                }
                try {
                  if (rr.DOI.startsWith('http')) {
                    rr.DOI = '10.' + rr.DOI.split('/10.')[1];
                  }
                } catch (error) {}
                try {
                  if (rr.DOI.startsWith('doi ')) {
                    rr.DOI = rr.DOI.toLowerCase().replace('doi ', '');
                  }
                } catch (error) {}
                try {
                  rr.DOI = rr.DOI.toLowerCase().trim().split('\\')[0].replace(/\/\//g, '/').replace(/\/ /g, '/').replace(/^\//, '').split(' ')[0].split('?')[0].split('#')[0].split(' pmcid')[0].split('\n')[0].replace(/[\u{0080}-\u{FFFF}]/gu, '').trim();
                } catch (error) {}
                try {
                  rr.DOI = rr.DOI.split(',http')[0];
                } catch (error) {}
                if (typeof rr.DOI === 'string' && rr.DOI.startsWith('10.')) {
                  if (!clear && (replacements[rr.DOI] != null)) {
                    rr.replaced = rr.DOI;
                    rr.DOI = replacements[rr.DOI];
                  }
                  if (typeof rr.email === 'string' && rr.email.includes('@')) {
                    rr.email = (await this.encrypt(rr.email));
                  }
                  rr.osdid = (org.name.replace(/[^a-zA-Z0-9-_ ]/g, '') + '_' + s.name + '_' + rr.DOI).replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_');
                  rr._id = rr.osdid;
                  osdids.push(rr.osdid);
                  if (ref11 = rr.DOI, indexOf.call(dois, ref11) < 0) {
                    `kc = false
if not clear
  present = await @report.works 'supplements.osdid.keyword:"' + rr.osdid + '"', 1
  present = present.hits.hits[0]._source if present?.hits?.hits? and present.hits.hits.length
  try
    for prs in present.supplements
      if prs.osdid is rr.osdid
        present = prs
        break
  if present?
    kc = await @copy rr
    delete kc.updated
    for k of present
      break if k not in ['updated'] and JSON.stringify(rr[k] ? '').toLowerCase() isnt JSON.stringify(present[k]).toLowerCase() # JSON string match on object isn't guaranteed but probably likely enough for the number of times we'll need it
      delete kc[k]`;
                    dois.push(rr.DOI); //if clear or JSON.stringify(kc) isnt '{}'
                  }
                  rr.updated = started;
                  sups.push(rr);
                  total += 1;
                }
              }
              console.log(org.name, s.name, sups.length, dois.length);
              await this.report.orgs.supplements(sups);
            }
            await this.sleep(2000);
            ref12 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', 'org.keyword:"' + org.name + '" AND sheets.keyword:"' + s.name + '"', {
              scroll: '30m',
              include: ['osdid']
            });
            for await (sup of ref12) {
              if (ref13 = sup.osdid, indexOf.call(osdids, ref13) < 0) {
                await this.report.orgs.supplements(sup.osdid, '');
                if (ref14 = sup.DOI, indexOf.call(dois, ref14) < 0) { // need to rerun for ones where something has been deleted too so that deleted supplements get removed from the work
                  dois.push(sup.DOI);
                }
              }
            }
          }
          sheets.push({
            org: org.name,
            sheet: s.name,
            rows: rc,
            update: update,
            supplements: sups.length
          });
          sheetnames.push(s.name);
        }
      }
    }
  }
  // check for sheets that have since been removed
  if (!clear && !orgname && !sheetname) {
    ref15 = (await this.report.works.suggest('supplements.sheets', void 0, 5000));
    for (p = 0, len4 = ref15.length; p < len4; p++) {
      aps = ref15[p];
      if (indexOf.call(sheetnames, aps) < 0) {
        ref16 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', 'sheets.keyword:"' + aps + '"', {
          scroll: '30m',
          include: ['osdid']
        });
        for await (sup of ref16) {
          await this.report.orgs.supplements(sup.osdid, '');
        }
        ref17 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', 'supplements.sheets.keyword:"' + aps + '"', {
          scroll: '30m',
          include: ['DOI']
        });
        for await (osw of ref17) {
          if (osw.DOI && (ref18 = osw.DOI, indexOf.call(dois, ref18) < 0)) {
            dois.push(osw.DOI);
          }
        }
      }
    }
  }
  if (clear) { // need to check to run everything that had a supplement
    ref19 = (await this.report.works('orgs:* OR supplements.sheets:*', {
      include: ['DOI']
    }));
    for (r = 0, len5 = ref19.length; r < len5; r++) {
      ptc = ref19[r];
      if (ptc.DOI && (ref20 = ptc.DOI, indexOf.call(dois, ref20) < 0)) {
        dois.push(ptc.DOI);
      }
    }
  }
  await this.sleep(60000); // wait a while for the supplements index to finish building and then run the processing for DOIs
  //await @mail to: 'mark@oa.works', subject: 'OA report orgs supplements loaded ' + total, text: 'report orgs supplements load ' + total + '\ndois ' + dois.length + '\ntook ' + await @epoch() - started
  console.log('report orgs supplements load', total, dois.length, (await this.epoch()) - started);
  if (dois.length) {
    console.log('report orgs supplements load ready to call works load', dois.length);
    await this.report.works.load(void 0, void 0, dois, void 0, void 0, started, void 0, sheets);
  }
  return total;
};

P.report.orgs.supplements.load._bg = true;

P.report.orgs.supplements.load._async = true;

P.report.orgs.supplements.load._log = false;

P.report.orgs.supplements.load._auth = '@oa.works';

P.report.emails = {
  _sheet: S.report.emails_sheet,
  _key: 'doi',
  _auth: '@oa.works'
};

P.report.email = async function(doi) {
  var j, len, ok, rec, ref, ref1, ref2, rol, rou, rpke;
  if (!doi && !this.params.orgkey) {
    return void 0;
  }
  if (doi == null) {
    doi = (ref = this.params.email) != null ? ref : this.params.doi;
  }
  if (doi == null) {
    return void 0;
  }
  rec = (await this.report.works(doi));
  if (rec != null ? rec.email : void 0) {
    if (rec.email.includes('@')) {
      return rec.email;
    }
    rpke = (await this.encrypt(this.params.orgkey));
    ok = (await this.report.orgs.orgkeys('key.keyword:"' + rpke + '"', 1));
    if (typeof (ok != null ? ok.org : void 0) === 'string' && ok.org.length) {
      rol = [];
      ref1 = rec.orgs;
      for (j = 0, len = ref1.length; j < len; j++) {
        rou = ref1[j];
        rol.push(rou.toLowerCase());
      }
      if (ref2 = ok.org, indexOf.call(rol, ref2) >= 0) {
        return this.decrypt(rec.email);
      }
    }
  }
};

P.report.email._log = false;

P.report.works = {
  _index: true
};

P.report.works.process = async function(cr, openalex, refresh, everything, replaced, queued) {
  var _rsup, a, ad, ass, assl, best_initial, best_name, best_score, brd, c, email, epmc, err, exists, f, i, j, k, l, lc, len, len1, len10, len11, len2, len3, len4, len5, len6, len7, len8, len9, lic, loc, lvs, m, n, oadoi, ok, ox, p, permissions, pp, pt, pubmed, r, ran, rec, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref38, ref39, ref4, ref40, ref41, ref42, ref43, ref44, ref45, ref46, ref47, ref48, ref49, ref5, ref50, ref51, ref52, ref6, ref7, ref8, ref9, ren, rn, score, sd, started, sup, u, ud, ude, v, w, x, xref, y, z;
  try {
    started = (await this.epoch());
    if (cr == null) {
      cr = this.params.process;
    }
    if (refresh === 0) {
      refresh = true;
    }
    if (refresh == null) {
      refresh = this.refresh;
    }
    if (everything == null) {
      everything = this.params.everything; // if so then runs epmc and permissions, which otherwise only run for records with orgs providing supplements
    }
    if (typeof openalex === 'string') {
      openalex = openalex.split(openalex.includes('doi.org') ? 'doi.org/' : '/').pop();
      openalex = openalex.replace(/\/$/, '');
      if (openalex.startsWith('10.')) {
        openalex = openalex.toLowerCase();
        if (cr == null) {
          cr = openalex;
        }
      }
      if (openalex.startsWith('W') || openalex.startsWith('10.')) {
        try {
          ox = (await this.src.openalex.works((openalex.startsWith('W') ? 'id.keyword:"https://openalex.org/' + openalex + '"' : 'ids.doi:"https://doi.org/' + openalex + '"'), 1));
          try {
            if (ox != null ? (ref = ox.hits) != null ? (ref1 = ref.hits) != null ? ref1.length : void 0 : void 0 : void 0) {
              ox = ox.hits.hits[0]._source;
            }
          } catch (error) {}
          if (ox != null ? ox.id : void 0) {
            openalex = ox;
          }
        } catch (error) {}
      }
    }
    if (refresh !== true && ((typeof openalex === 'object' && ((ref2 = openalex.ids) != null ? ref2.doi : void 0)) || (typeof openalex === 'string' && openalex.startsWith('10.')))) {
      exists = (await this.report.works(typeof openalex === 'string' ? openalex : openalex.ids.doi.split('.org/')[1]));
      if (!(exists != null ? exists.updated : void 0) || (refresh && exists && exists.updated < refresh)) {
        exists = void 0;
      }
    }
    if (typeof openalex === 'string' && !(openalex.startsWith('W') || openalex.startsWith('10.'))) {
      openalex = void 0;
    }
    if ((cr == null) && typeof openalex === 'object' && (openalex != null ? (ref3 = openalex.ids) != null ? ref3.doi : void 0 : void 0)) {
      cr = openalex.ids.doi;
    }
    if (typeof cr === 'string' && cr.includes('doi.org/')) {
      cr = cr.split('doi.org/').pop();
    }
    if (typeof cr === 'string' && !cr.startsWith('10.')) {
      cr = void 0;
    }
    if (typeof cr === 'string') {
      cr = cr.toLowerCase();
    }
    if (typeof cr === 'string' && (xref = (await this.src.crossref.works(cr)))) { // not exists? and 
      cr = xref;
    }
    if (typeof cr === 'object' && !cr.DOI) {
      cr = void 0;
    }
    if ((cr != null) && refresh !== true) {
      if (exists == null) {
        exists = (await this.report.works(typeof cr === 'string' ? cr : cr.DOI));
      }
      if (!(exists != null ? exists.updated : void 0) || (refresh && exists && exists.updated < refresh)) {
        exists = void 0;
      }
    }
    if ((cr != null) && !(exists != null ? exists.openalex : void 0)) {
      if (openalex == null) {
        openalex = (await this.src.openalex.works(typeof cr === 'object' ? cr.DOI : cr));
      }
    }
    if (typeof openalex === 'string' || !(openalex != null ? openalex.id : void 0)) {
      openalex = void 0;
    }
    if (typeof cr === 'object' && cr.DOI) {
      if ((exists != null ? exists.updated : void 0) && ((ref4 = cr.indexed) != null ? ref4.timestamp : void 0) && exists.updated < cr.indexed.timestamp) {
        exists = void 0;
      }
      rec = {
        DOI: cr.DOI.toLowerCase(),
        subject: cr.subject,
        subtitle: cr.subtitle,
        volume: cr.volume,
        published_year: cr.year,
        issue: cr.issue,
        publisher: cr.publisher,
        published_date: cr.published,
        funder: cr.funder,
        issn: cr.ISSN,
        subtype: cr.subtype
      };
      ref6 = (ref5 = cr.assertion) != null ? ref5 : [];
      for (j = 0, len = ref6.length; j < len; j++) {
        ass = ref6[j];
        assl = ((ref7 = ass.label) != null ? ref7 : '').toLowerCase();
        if (assl.includes('accepted') && assl.split(' ').length < 3) {
          ad = (await this.dateparts(ass.value));
          if (ad != null ? ad.date : void 0) {
            if (rec.accepted_date == null) {
              rec.accepted_date = ad.date;
            }
          }
        }
        if (assl.includes('received')) {
          sd = (await this.dateparts(ass.value));
          if (sd != null ? sd.date : void 0) {
            if (rec.submitted_date == null) {
              rec.submitted_date = sd.date;
            }
          }
        }
      }
      ref9 = (ref8 = rec.funder) != null ? ref8 : [];
      for (l = 0, len1 = ref9.length; l < len1; l++) {
        f = ref9[l];
        delete f['doi-asserted-by'];
      }
      if (cr.title && typeof cr.title !== 'string' && cr.title.length) {
        rec.title = cr.title[0];
      }
      if (cr['container-title'] && cr['container-title'].length) {
        rec.journal = cr['container-title'][0];
      }
      if (cr['reference-count'] != null) {
        rec['reference-count'] = cr['reference-count'];
      }
      ref11 = (ref10 = cr.license) != null ? ref10 : [];
      for (m = 0, len2 = ref11.length; m < len2; m++) {
        lc = ref11[m];
        if ((ref12 = lc['content-version']) === 'am' || ref12 === 'vor' || ref12 === 'tdm' || ref12 === 'unspecified') {
          rec['crossref_license_url_' + lc['content-version']] = lc.URL;
        }
      }
      rec.crossref_is_oa = cr.is_oa == null ? false : cr.is_oa;
      brd = [];
      _rsup = async(sup, ud) => {
        sup.DOI = cr.DOI;
        sup.replaced = ud;
        await this.report.orgs.supplements(sup.osdid, '');
        sup._id = sup.osdid = sup.osdid.split('_10.')[0] + '_' + sup.DOI.replace(/[\u{0080}-\u{FFFF}]/gu, '').toLowerCase().replace(/\//g, '_').replace(/ /g, '_');
        return brd.push(sup);
      };
      ref14 = (ref13 = cr['update-to']) != null ? ref13 : [];
      for (n = 0, len3 = ref14.length; n < len3; n++) {
        ud = ref14[n];
        if (ud.DOI !== cr.DOI && ((ref15 = ud.type.toLowerCase()) !== 'erratum' && ref15 !== 'correction')) { // some new version statements are for the same DOI, so no point changing anything
          rec.replaces = [];
          rec.replaces.push({
            DOI: ud.DOI,
            type: ud.type,
            updated: (ref16 = ud.updated) != null ? ref16.timestamp : void 0
          });
          if (ude = (await this.report.works(ud.DOI))) {
            await this.report.works(ud.DOI, '');
          }
          ref17 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', 'DOI.keyword:"' + ud.DOI + '"');
          for await (sup of ref17) {
            _rsup(sup, ud.DOI);
          }
        }
      }
      if (brd.length) {
        //vseens = []
        //for rtype in ['is-same-as', 'is-version-of', 'has-version'] # NOTE that these can be reciprocal and more than dual, and not always fully related, so can cause recurring loops. e.g. see https://bg.beta.oa.works/src/crossref/works/10.26434/chemrxiv-2021-vfkqb-v3
        //  for rr in (cr.relation?[rtype] ? []) # so we can't be sure which is the 'newest' or 'best' version, or that we will always know of all versions the first time round. So just note their relation to each other and default to whichever one got into the index first
        //    if rr['id-type'] is 'doi' and rr.id not in vseens and rr.id isnt cr.DOI and rr.id isnt replaced and newer = await @report.works rr.id # crossref is also capable of saying a DOI is the same as another DOI that does not exist in crossref, but in that case it won't exist in report works yet either
        //      _rsup(sup, rr.id) for await sup from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_orgs_supplements', 'DOI.keyword:"' + cr.DOI + '"'
        //    vseens.push rr.id
        //    break if newer?
        //  break if newer?
        await this.report.orgs.supplements(brd);
      }
      //if newer?
      //  return @report.works.process newer, openalex, refresh, everything, cr.DOI
      if (replaced) { // if this was passed in by a secondary call to process
        if (rec.replaces == null) {
          rec.replaces = [];
        }
        rec.replaces.push({
          DOI: replaced,
          type: 'relation'
        });
      }
    }
    if (openalex != null) {
      try {
        if ((exists != null ? exists.updated : void 0) && openalex.updated_date && exists.updated < (await this.epoch(openalex.updated_date))) {
          exists = void 0;
        }
      } catch (error) {}
      if (rec == null) {
        rec = {};
      }
      if (openalex.id) {
        rec.openalex = openalex.id.split('/').pop();
      }
      if (!rec.DOI && (((ref18 = openalex.ids) != null ? ref18.doi : void 0) != null)) {
        rec.DOI = openalex.ids.doi.split('doi.org/').pop().toLowerCase();
      }
      if ((ref19 = openalex.ids) != null ? ref19.pmid : void 0) {
        rec.PMID = openalex.ids.pmid.split('/').pop();
      }
      if (!rec.PMCID && ((ref20 = openalex.ids) != null ? ref20.pmcid : void 0)) {
        rec.PMCID = 'PMC' + openalex.ids.pmcid.split('/').pop().toLowerCase().replace('pmc', '');
      }
      if (openalex.title) {
        rec.title = openalex.title;
      }
      ref21 = ['authorships', 'concepts', 'cited_by_count', 'type', 'is_paratext', 'is_retracted'];
      for (p = 0, len4 = ref21.length; p < len4; p++) {
        ok = ref21[p];
        rec[ok] = openalex[ok];
      }
      if (openalex.publication_date) {
        rec.published_date = openalex.publication_date;
      }
      if (openalex.publication_year) {
        rec.published_year = openalex.publication_year;
      }
      if (((ref22 = openalex.host_venue) != null ? ref22.issn : void 0) && openalex.host_venue.issn.length) {
        rec.issn = openalex.host_venue.issn;
      }
      if (openalex.biblio) {
        rec.biblio = openalex.biblio;
      }
      if (openalex['referenced_works']) {
        rec['referenced_works'] = openalex['referenced_works'].length;
      }
      ref24 = (ref23 = rec.concepts) != null ? ref23 : [];
      for (r = 0, len5 = ref24.length; r < len5; r++) {
        c = ref24[r];
        delete c.wikidata;
        try {
          c.score = Math.floor(c.score * 100);
        } catch (error) {}
      }
      ref26 = (ref25 = rec.authorships) != null ? ref25 : [];
      for (u = 0, len6 = ref26.length; u < len6; u++) {
        a = ref26[u];
        ref28 = (ref27 = a.institutions) != null ? ref27 : [];
        for (v = 0, len7 = ref28.length; v < len7; v++) {
          i = ref28[v];
          delete i.type;
        }
      }
    }
    if (rec == null) {
      rec = {};
    }
    if (!rec.DOI && typeof cr === 'string') {
      rec.DOI = cr.toLowerCase();
    }
    if (rec.is_paratext || rec.is_retracted) {
      if (queued) {
        _done_batch.push(queued);
        _processing_dois.splice(_processing_dois.indexOf(queued), 1);
      }
      return;
    }
    delete rec.is_paratext;
    delete rec.is_retracted;
    if (!(exists != null ? exists.oadoi : void 0) && rec.DOI) {
      rec.oadoi = true;
      oadoi = (await this.src.oadoi(rec.DOI));
      ref30 = (ref29 = oadoi != null ? oadoi.oa_locations : void 0) != null ? ref29 : [];
      for (w = 0, len8 = ref30.length; w < len8; w++) {
        loc = ref30[w];
        if (loc.host_type === 'publisher') {
          if (rec.publisher_license == null) {
            rec.publisher_license = loc.license;
          }
          if (rec.publisher_url_for_pdf == null) {
            rec.publisher_url_for_pdf = loc.url_for_pdf;
          }
          if (rec.publisher_version == null) {
            rec.publisher_version = loc.version;
          }
        }
        if (loc.host_type === 'repository') {
          if (loc.url && loc.url.toLowerCase().includes('pmc')) {
            if (!rec.PMCID) {
              pp = loc.url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0];
              if (pp.length && pp.replace(/[^0-9]/g, '').length === pp.length && !isNaN(parseInt(pp))) {
                rec.PMCID = 'PMC' + pp;
              }
            }
            if (loc.license && !rec.epmc_licence) {
              rec.epmc_licence = loc.license;
            }
          }
          if (!rec.repository_url || !rec.repository_url.includes('pmc')) {
            ref31 = ['license', 'url_for_pdf', 'url', 'version'];
            for (x = 0, len9 = ref31.length; x < len9; x++) {
              ok = ref31[x];
              if (loc[ok]) {
                rec['repository_' + ok] = loc[ok];
              }
            }
          }
        }
      }
      if (rec.repository_url && rec.repository_url.toLowerCase().includes('pmc')) {
        if (rec.PMCID == null) {
          rec.PMCID = 'PMC' + rec.repository_url.toLowerCase().split('pmc').pop().split('/')[0].split('#')[0].split('?')[0];
        }
        rec.repository_url_in_pmc = true;
      }
      if (oadoi != null) {
        rec.best_oa_location_url = (ref32 = oadoi.best_oa_location) != null ? ref32.url : void 0;
        rec.best_oa_location_url_for_pdf = (ref33 = oadoi.best_oa_location) != null ? ref33.url_for_pdf : void 0;
        rec.oa_status = oadoi.oa_status;
        rec.has_repository_copy = oadoi.has_repository_copy;
        rec.has_oa_locations_embargoed = (oadoi.oa_locations_embargoed != null) && oadoi.oa_locations_embargoed.length ? true : false;
        rec.title = oadoi.title;
        if (!rec.issn && typeof oadoi.journal_issns === 'string' && oadoi.journal_issns.length) {
          rec.issn = oadoi.journal_issns.split(',');
        }
        if (rec.journal == null) {
          rec.journal = oadoi.journal_name;
        }
        if (rec.publisher == null) {
          rec.publisher = oadoi.publisher;
        }
        if (oadoi.published_date) {
          rec.published_date = oadoi.published_date;
        }
        if (oadoi.year) {
          rec.published_year = oadoi.year;
        }
        if (oadoi.is_oa != null) {
          rec.oadoi_is_oa = oadoi.is_oa;
        }
      }
    }
    rec.supplements = [];
    rec.orgs = [];
    if (rec.DOI) {
      ref34 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', 'DOI.keyword:"' + rec.DOI + '"', {
        sort: {
          'osdid.keyword': 'asc'
        }
      });
      for await (sup of ref34) {
        if (ref35 = sup.org, indexOf.call(rec.orgs, ref35) < 0) {
          rec.orgs.push(sup.org);
        }
        if (sup.paid) {
          rec.paid = true;
        }
        if (!rec.email && sup.email) {
          rec.email = sup.email;
        }
        if (sup.author_email_name_ic) {
          rec.author_email_name = sup.author_email_name_ic;
        }
        rec.supplements.push(sup);
      }
    }
    if ((exists != null) && refresh !== true) {
      if (!rec.author_email_name && exists.author_email_name && exists.email && rec.email && rec.email.toLowerCase() === exists.email.toLowerCase()) {
        rec.author_email_name = exists.author_email_name;
      }
      for (k in exists) {
        if (rec[k] == null) {
          rec[k] = exists[k];
        }
      }
    }
    if ((rec.authorships != null) && rec.email && !rec.author_email_name && (((exists != null ? exists.authorships : void 0) == null) || !(exists != null ? exists.email : void 0))) {
      email = rec.email.includes('@') ? rec.email : (await this.decrypt(rec.email));
      if (rec.authorships.length === 1) {
        rec.author_email_name = 'Dr. ' + ((ref36 = rec.authorships[0].author) != null ? ref36.display_name : void 0);
      } else {
        ren = email.split('@')[0].toLowerCase().replace(/[^a-z]/g, '');
        best_initial = '';
        best_name = '';
        best_score = 1000000;
        ref37 = rec.authorships;
        for (y = 0, len10 = ref37.length; y < len10; y++) {
          rn = ref37[y];
          if (ran = (ref38 = rn.author) != null ? ref38.display_name : void 0) {
            lvs = (await this.levenshtein(ren, ran.toLowerCase().replace(/[^a-z]/g, '')));
            score = lvs.distance / ran.length;
            if (score < best_score) {
              best_score = score;
              best_name = ran;
            }
            if (best_score > .2 && (ren.endsWith(ran.split(' ').pop().toLowerCase()) || (ran.split(' ')[0].length > 4 && ren.includes(ran.split(' ')[0].toLowerCase())))) {
              best_score = .1;
              best_name = ran;
            }
            if (!best_initial && ren.startsWith((ran.split(' ')[0].slice(0, 1) + ran.split(' ').pop().slice(0, 1)).toLowerCase())) {
              best_initial = ran;
            }
          }
        }
        if (best_name && best_score < .7) {
          rec.author_email_name = 'Dr. ' + best_name.split(' ').pop();
        }
        if (!rec.author_email_name && best_initial) {
          rec.author_email_name = 'Dr. ' + best_initial;
        }
      }
    }
    if (typeof rec.email === 'string' && rec.email.includes('@')) {
      rec.email = (await this.encrypt(rec.email));
    }
    if (rec.orgs.length) { //and (refresh or (exists?.orgs ? []).length isnt rec.orgs.length) # control whether to run time-expensive things on less important records
      everything = true;
    }
    
    //if (not exists? and rec.orgs.length) or (exists?.orgs ? []).length isnt rec.orgs.length or (rec.paid and rec.paid isnt exists?.paid) #or not exists.journal_oa_type
    if (rec.DOI) {
      if (!rec.PMCID || !rec.PMID || !rec.pubtype || !rec.submitted_date || !rec.accepted_date) {
        if (pubmed = (rec.PMID ? (await this.src.pubmed(rec.PMID)) : (await this.src.pubmed.doi(rec.DOI)))) { // pubmed is faster to lookup but can't rely on it being right if no PMC found in it, e.g. 10.1111/nyas.14608
          if (!rec.PMCID && (pubmed != null ? (ref39 = pubmed.identifier) != null ? ref39.pmc : void 0 : void 0)) {
            rec.PMCID = 'PMC' + pubmed.identifier.pmc.toLowerCase().replace('pmc', '');
          }
          if (!rec.PMID && (pubmed != null ? (ref40 = pubmed.identifier) != null ? ref40.pubmed : void 0 : void 0)) {
            rec.PMID = pubmed.identifier.pubmed;
          }
          rec.pubtype = pubmed.type; // this is a list
          if (rec.submitted_date == null) {
            rec.submitted_date = (ref41 = pubmed.dates) != null ? (ref42 = ref41.PubMedPubDate_received) != null ? ref42.date : void 0 : void 0;
          }
          if (rec.accepted_date == null) {
            rec.accepted_date = (ref43 = pubmed.dates) != null ? (ref44 = ref43.PubMedPubDate_accepted) != null ? ref44.date : void 0 : void 0;
          }
        }
      }
      if (!rec.journal_oa_type) { // restrict permissions only to records with orgs supplements? for now no
        permissions = (await this.permissions((await this.copy(rec)), void 0, void 0, oadoi, cr, started - 1209600000)); // (if refresh then undefined else started - 1209600000) # use cached best permissions up to two weeks old
        rec.can_archive = permissions != null ? (ref45 = permissions.best_permission) != null ? ref45.can_archive : void 0 : void 0;
        if ((rec.can_archive == null) && (((ref46 = oadoi != null ? (ref47 = oadoi.best_oa_location) != null ? ref47.license : void 0 : void 0) != null ? ref46 : '').includes('cc') || (oadoi != null ? oadoi.journal_is_in_doaj : void 0))) {
          rec.can_archive = true;
        }
        rec.version = permissions != null ? (ref48 = permissions.best_permission) != null ? ref48.version : void 0 : void 0;
        rec.journal_oa_type = (await this.permissions.journals.oa.type(rec.issn, void 0, oadoi, cr)); // calculate journal oa type separately because it can be different for a journal in general than for what permissions calculates in more specificity
        if (rec.journal_oa_type == null) {
          rec.journal_oa_type = 'unsuccessful';
        }
      }
      if (everything) {
        if (!rec.PMCID || !rec.pubtype) { //or not rec.submitted_date or not rec.accepted_date # only thing restricted to orgs supplements for now is remote epmc lookup and epmc licence calculation below
          if (epmc = (await this.src.epmc.doi(rec.DOI))) {
            if (epmc.pmcid) {
              rec.PMCID = epmc.pmcid;
            }
            ref50 = (ref49 = epmc.pubTypeList) != null ? ref49 : [];
            //rec.submitted_date ?= epmc.firstIndexDate - removed as found to be not accurate enough https://github.com/oaworks/Gates/issues/559
            //rec.accepted_date ?= epmc.firstPublicationDate
            for (z = 0, len11 = ref50.length; z < len11; z++) {
              pt = ref50[z];
              rec.pubtype = Array.isArray(rec.pubtype) ? rec.pubtype : rec.pubtype ? [rec.pubtype] : [];
              if (ref51 = pt.pubType, indexOf.call(rec.pubtype, ref51) < 0) {
                rec.pubtype.push(pt.pubType);
              }
            }
          }
        }
      }
    }
    if (everything) {
      if (rec.PMCID && rec.repository_url_in_pmc && !rec.epmc_licence && !rec.tried_epmc_licence) {
        rec.tried_epmc_licence = true;
        lic = (await this.src.epmc.licence(rec.PMCID, epmc));
        rec.epmc_licence = lic != null ? lic.licence : void 0;
      }
      if (rec.pmc_has_data_availability_statement == null) {
        rec.pmc_has_data_availability_statement = rec.PMCID && (await this.src.pubmed.availability(rec.PMCID));
      }
      if (!rec.data_availability_statement && rec.PMCID) { //rec.pmc_has_data_availability_statement
        rec.data_availability_statement = (await this.src.epmc.statement(rec.PMCID, epmc));
      }
    }
    rec.is_oa = rec.oadoi_is_oa || rec.crossref_is_oa || ((ref52 = rec.journal_oa_type) === 'gold');
    if (rec._id == null) {
      rec._id = rec.DOI ? rec.DOI.toLowerCase().replace(/\//g, '_') : rec.openalex; // and if no openalex it will get a default ID
    }
    rec.supplemented = (await this.epoch());
    rec.updated = rec.supplemented;
    rec.took = rec.supplemented - started;
    if (rec.DOI && this.params.process === rec.DOI && this.params.save !== false) {
      await this.report.works(rec);
    } else if (queued) {
      _done_batch.push(queued);
      if (rec._id != null) {
        _processed_batch.push(rec);
      }
      _processing_dois.splice(_processing_dois.indexOf(queued), 1);
    }
    //console.log 'report works processed', rec.DOI, rec.took
    return rec;
  } catch (error) {
    err = error;
    console.log('report works process error', err, (typeof cr === 'object' ? cr.DOI : cr));
    if (queued) {
      _done_batch.push(queued);
      _processing_dois.splice(_processing_dois.indexOf(queued), 1);
    }
  }
};

P.report.works.process._log = false;

P.report.works.load = async function(timestamp, org, dois, year, clear, supplements, everything, info) {
  var _crossref, _openalex, crt, d, i, j, l, len, len1, o, ref, ref1, ref10, ref11, ref12, ref13, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, refresh, sd, started, sup, text, took, total, updated;
  started = (await this.epoch());
  if (year == null) {
    year = (ref = this.params.load) != null ? ref : ((await this.date())).split('-')[0];
  }
  if (org == null) {
    org = (ref1 = (ref2 = this.params.org) != null ? ref2 : this.params.orgs) != null ? ref1 : this.params.load === 'orgs';
  }
  if ((dois == null) && typeof this.params.load === 'string' && this.params.load.startsWith('10.')) {
    dois = this.params.load;
  }
  if (typeof dois === 'string') {
    dois = [dois];
  }
  if (this.fn.startsWith('report.works.load')) {
    if (clear == null) {
      clear = this.params.clear;
    }
  }
  refresh = this.refresh;
  if (everything == null) {
    everything = this.params.load === 'everything';
  }
  //await @report.works('') if clear
  total = 0;
  if (this.params.q) {
    if (dois == null) {
      dois = [];
    }
    ref3 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', this.params.q, {
      scroll: '5m',
      include: ['DOI', 'openalex']
    });
    for await (sup of ref3) {
      sd = (ref4 = sup.DOI) != null ? ref4 : sup.openalex;
      if (indexOf.call(dois, sd) < 0) {
        dois.push(sd);
      }
    }
    console.log('report works supplements to load from query', this.params.q);
  } else if (this.params.load === 'supplements') {
    if (dois == null) {
      dois = [];
    }
    ref5 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs_supplements', (timestamp ? 'updated:<' + timestamp : org ? 'org:"' + org + '"' : void 0), {
      scroll: '5m',
      include: ['DOI']
    });
    for await (sup of ref5) {
      if (ref6 = sup.DOI, indexOf.call(dois, ref6) < 0) {
        dois.push(sup.DOI);
      }
    }
    console.log('report works supplements to load', timestamp, org, dois.length);
  } else if (everything) {
    if (dois == null) {
      dois = [];
    }
    ref7 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', 'NOT pmc_has_data_availability_statement:*', {
      scroll: '5m',
      include: ['DOI', 'openalex']
    });
    for await (sup of ref7) {
      sd = (ref8 = sup.DOI) != null ? ref8 : sup.openalex;
      if (indexOf.call(dois, sd) < 0) {
        dois.push(sd);
      }
    }
    console.log('report works supplements to load everything for records that do not yet have everything', dois.length);
  }
  if (Array.isArray(dois)) {
    console.log('report works queueing dois batch', dois.length);
    for (j = 0, len = dois.length; j < len; j++) {
      d = dois[j];
      await this.report.queue(d, void 0, timestamp != null ? timestamp : refresh, everything);
      total += 1;
    }
  } else {
    _crossref = async(cq, action) => {
      var cr, precount, ref9, results;
      if (cq == null) {
        cq = '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year;
      }
      if (timestamp) {
        cq = '(' + cq + ') AND srcday:>' + timestamp;
      }
      precount = (await this.src.crossref.works.count(cq));
      console.log('report works load crossref by query expects', cq, precount);
      ref9 = this.index._for('src_crossref_works', cq, {
        include: ['DOI'],
        scroll: '30m'
      });
      results = [];
      for await (cr of ref9) {
        await this.report.queue(cr.DOI, void 0, timestamp != null ? timestamp : refresh, everything, action);
        results.push(total += 1);
      }
      return results;
    };
    if (org !== true && year === this.params.load) {
      await _crossref(void 0, 'years');
    }
    _openalex = async(oq, action) => {
      var ol, oodoi, precount, ref10, ref9, results;
      if (oq == null) {
        oq = 'authorships.institutions.display_name:* AND publication_year:' + year;
      }
      if (timestamp) {
        oq = '(' + oq + ') AND updated_date:>' + timestamp;
      }
      precount = (await this.src.openalex.works.count(oq));
      console.log('report works load openalex by query expects', oq, precount);
      ref9 = this.index._for('src_openalex_works', oq, {
        include: ['id', 'ids'],
        scroll: '30m'
      });
      results = [];
      for await (ol of ref9) {
        oodoi = ((ref10 = ol.ids) != null ? ref10.doi : void 0) ? '10.' + ol.ids.doi.split('/10.')[1] : void 0;
        //if ol.id and ol.id.includes('/') and (not oodoi or (oodoi not in oo and oodoi not in cc))
        //  await @report.queue undefined, (oodoi ? ol.id.split('/').pop()), (timestamp ? refresh), everything
        if (oodoi) {
          await this.report.queue(oodoi, void 0, timestamp != null ? timestamp : refresh, everything, action);
          results.push(total += 1);
        } else {
          results.push(void 0);
        }
      }
      return results;
    };
    if (org !== true && year === this.params.load) {
      await _openalex(void 0, 'years');
    }
    ref9 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_orgs', (typeof org === 'string' ? 'name:"' + org + '"' : 'paid:true'), {
      scroll: '10m'
    });
    for await (o of ref9) {
      // if an org has no known records in report/works yet, could default it here to a timestamp of start of current year, or older, to pull in all records first time round
      if ((ref10 = o.source) != null ? ref10.crossref : void 0) {
        try {
          if (o.source.crossref.includes('%')) {
            o.source.crossref = decodeURIComponent(decodeURIComponent(o.source.crossref));
          }
        } catch (error) {}
        console.log('report works load crossref by org', o.name);
        try {
          await _crossref(o.source.crossref);
        } catch (error) {}
      }
      if ((ref11 = o.source) != null ? ref11.openalex : void 0) {
        try {
          if (o.source.openalex.includes('%')) {
            o.source.openalex = decodeURIComponent(decodeURIComponent(o.source.openalex));
          }
        } catch (error) {}
        console.log('report works load openalex by org', o.name);
        try {
          await _openalex(o.source.openalex);
        } catch (error) {}
      }
    }
    if (timestamp) {
      ref12 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', 'orgs:* AND updated:<' + timestamp, {
        scroll: '10m'
      });
      for await (crt of ref12) {
        if (updated = (await this.src.crossref.works.count('DOI.keyword:"' + crt.DOI + '" AND srcday:>' + timestamp))) {
          await this.report.queue(crt.DOI, void 0, timestamp != null ? timestamp : refresh, everything);
        }
      }
    }
  }
  took = (await this.epoch()) - started;
  text = 'Report works queued ' + total + (this.S.dev ? ' (dev)' : '') + '\n';
  if (dois && dois.length) {
    text += dois.length + ' DOIs were provided to process\n';
  }
  if (this.params.load === 'supplements') {
    text += 'These were derived by searching for all works that already have supplements attached\n';
  }
  if (everything) {
    text += 'These were derived by searching for all works that have not yet had everything fully processed\n';
  }
  if (supplements) {
    text += 'These were provided by an orgs supplements refresh which took ' + Math.ceil((started - supplements) / 1000 / 60) + 'm\n';
  }
  if (typeof org === 'string') {
    text += 'The load process was limited to ' + org + '\n';
  }
  if (timestamp) {
    text += 'The load process was run for changes since ' + ((await this.datetime(timestamp))) + '\n';
  }
  if (year && (this.params.load || !timestamp) && !(dois != null ? dois : []).length) {
    text += 'The load process was run for year ' + year + '\n';
  }
  ref13 = info != null ? info : [];
  for (l = 0, len1 = ref13.length; l < len1; l++) {
    i = ref13[l];
    text += '\n' + JSON.stringify(i) + '\n';
  }
  console.log('Report works loaded', total, took);
  await this.mail({
    to: ['mark@oa.works', 'joe@oa.works'],
    subject: 'OA report works loaded ' + total,
    text: text
  });
  return total;
};

P.report.works.load._log = false;

P.report.works.load._bg = true;

P.report.works.load._async = true;

P.report.works.load._auth = '@oa.works';

P.report.works.changes = function(timestamp, org) {
  var ref, ref1;
  // do not reload orgs first before running changes, Joe wants that to remain a manual process
  if (timestamp == null) {
    timestamp = (ref = (ref1 = this.params.changes) != null ? ref1 : this.params.timestamp) != null ? ref : Date.now() - 90000000;
  }
  if (org == null) {
    org = this.params.org;
  }
  this.report.works.load(timestamp, org); // start from timestamp a little more than a day ago, by default
  return true;
};

P.report.works.changes._log = false;

P.report.works.changes._bg = true;

P.report.works.changes._async = true;

P.report.works.changes._auth = '@oa.works';

P.report.works.check = async function(year) {
  var cq, cr, crossref_seen_openalex, not_in_works, ol, olid, olx, oodoi, oq, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, res, seen, worked;
  if (year == null) {
    year = (ref = (ref1 = this.params.check) != null ? ref1 : this.params.year) != null ? ref : '2023';
  }
  seen = [];
  not_in_works = [];
  crossref_seen_openalex = [];
  res = {
    year: year,
    crossref: 0,
    crossref_count: 0,
    openalex: 0,
    openalex_count: 0,
    crossref_in_works: 0,
    crossref_in_works_had_openalex: 0,
    crossref_not_in_works_in_openalex: 0,
    openalex_already_seen_in_works_by_crossref: 0,
    openalex_in_works: 0,
    openalex_in_works_by_id: 0,
    openalex_with_doi_but_not_seen: 0,
    openalex_not_in_works: 0,
    duplicates: 0
  };
  await fs.writeFile(this.S.static.folder + '/report_check_missing_' + year + '.json', '[');
  cq = '(funder.name:* OR author.affiliation.name:*) AND year.keyword:' + year;
  res.crossref_count = (await this.src.crossref.works.count(cq));
  await fs.writeFile(this.S.static.folder + '/report_check_' + year + '.json', JSON.stringify(res, '', 2));
  ref2 = this.index._for('src_crossref_works', cq, {
    include: ['DOI'],
    scroll: '30m'
  });
  for await (cr of ref2) {
    if (res.crossref % 100 === 0) {
      console.log(res);
    }
    if (ref3 = cr.DOI, indexOf.call(seen, ref3) < 0) {
      seen.push(cr.DOI);
    } else {
      res.duplicates += 1;
    }
    res.crossref += 1;
    if (worked = (await this.report.works(cr.DOI))) {
      res.crossref_in_works += 1;
    }
    if (!worked && (ref4 = cr.DOI, indexOf.call(not_in_works, ref4) < 0)) {
      await fs.appendFile(this.S.static.folder + '/report_check_missing_' + year + '.json', (not_in_works.length ? ',' : '') + '\n"' + cr.DOI + '"');
      not_in_works.push(cr.DOI);
    }
    if (worked != null ? worked.openalex : void 0) {
      res.crossref_in_works_had_openalex += 1;
      crossref_seen_openalex.push(cr.DOI);
    } else if (olx = (await this.src.openalex.works.count('ids.doi:"https://doi.org/' + cr.DOI + '"'))) {
      res.crossref_not_in_works_in_openalex += 1;
    }
  }
  oq = 'authorships.institutions.display_name:* AND publication_year:' + year;
  res.openalex_count = (await this.src.openalex.works.count(oq));
  await fs.writeFile(this.S.static.folder + '/report_check_' + year + '.json', JSON.stringify(res, '', 2));
  ref5 = this.index._for('src_openalex_works', oq, {
    include: ['id', 'ids'],
    scroll: '30m'
  });
  for await (ol of ref5) {
    if (res.openalex % 100 === 0) {
      console.log(res);
    }
    res.openalex += 1;
    oodoi = ((ref6 = ol.ids) != null ? ref6.doi : void 0) ? '10.' + ol.ids.doi.split('/10.')[1] : void 0;
    if (oodoi) {
      if (indexOf.call(crossref_seen_openalex, oodoi) >= 0) {
        res.openalex_already_seen_in_works_by_crossref += 1;
      }
      if (indexOf.call(seen, oodoi) < 0) {
        if (oodoi) {
          res.openalex_with_doi_but_not_seen += 1;
        }
        seen.push(oodoi);
      } else {
        res.duplicates += 1;
      }
    }
    olid = ol.id.split('/').pop();
    if (oodoi && (worked = (await this.report.works(oodoi)))) {
      res.openalex_in_works += 1;
    } else if (worked = (await this.report.works('openalex.keyword:"' + olid + '"', 1))) {
      res.openalex_in_works += 1;
      res.openalex_in_works_by_id += 1;
    } else {
      res.openalex_not_in_works += 1;
    }
    if (!worked && (ref7 = oodoi != null ? oodoi : olid, indexOf.call(not_in_works, ref7) < 0)) {
      await fs.appendFile(this.S.static.folder + '/report_check_missing_' + year + '.json', (not_in_works.length ? ',' : '') + '\n"' + (oodoi != null ? oodoi : olid) + '"');
      not_in_works.push(oodoi != null ? oodoi : olid);
    }
  }
  res.seen = seen.length;
  res.not_in_works = not_in_works.length;
  await fs.appendFile(this.S.static.folder + '/report_check_missing_' + year + '.json', '\n]');
  await fs.writeFile(this.S.static.folder + '/report_check_seen_' + year + '.json', JSON.stringify(seen, '', 2));
  await fs.writeFile(this.S.static.folder + '/report_check_' + year + '.json', JSON.stringify(res, '', 2));
  console.log(res);
  return res;
};

P.report.works.check._async = true;

P.report.works.check._bg = true;

P.report.works.check._auth = '@oa.works';

`P.report.fixmedline = ->
fixes = []
checked = 0
for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'DOI:* AND submitted_date:* AND PMCID:*', scroll: '30m', include: ['DOI', 'PMID']
  checked += 1
  console.log('fix medline checked', checked) if checked % 1000 is 0
  from_crossref = false
  if cr = await @src.crossref.works rec.DOI
    for ass in (cr.assertion ? [])
      if (ass.label ? '').toLowerCase().includes 'received'
        from_crossref = true
        break
  from_pubmed = false
  if not from_crossref
    if pubmed = (if rec.PMID then await @src.pubmed(rec.PMID) else await @src.pubmed.doi rec.DOI)
      from_pubmed = true if pubmed.dates?.PubMedPubDate_received?.date
  if not from_crossref and not from_pubmed
    fixes.push rec.DOI
    console.log 'fix medline found', fixes.length, 'to fix'
batch = []
if fixes.length
  for DOI in fixes
    if rec = await @report.works DOI
      delete rec.submitted_date
      delete rec.accepted_date
      batch.push rec
    if batch.length is 5000
      await @report.works batch
      batch = []
  if batch.length
    await @report.works batch
console.log 'fix medline completed with', fixes.length, 'fixed'
return fixes.length
P.report.fixmedline._bg = true
P.report.fixmedline._async = true
P.report.fixmedline._auth = '@oa.works'`;

`P.report.fixtitle = ->
  fixes = 0
  checked = 0
  batch = []
  for alpha in 'abcdefghijklmnopqrstuvwxyz'.split ''
    for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'title.keyword:"' + alpha + '" OR title.keyword:"' + alpha.toUpperCase() + '"', scroll: '30m'
      checked += 1
      console.log('fix title checked', alpha, checked, fixes) if checked % 1000 is 0
      if rec.title.length is 1
        if oadoi = await @src.oadoi rec.DOI
          rec.title = oadoi.title if oadoi.title
        if rec.title.length is 1 and openalex = await @src.openalex.works rec.DOI
          rec.title = openalex.title if openalex.title
        if rec.title.length is 1 and cr = await @src.crossref.works rec.DOI
          rec.title = cr.title if cr.title
          rec.title = rec.title[0] if typeof rec.title isnt 'string'
        if rec.title.length isnt 1
          fixes += 1
          batch.push rec
        if batch.length is 20000
          await @report.works batch
          batch = []
  if batch.length
    await @report.works batch
  console.log 'fix title completed with', checked, fixes
  return fixes
P.report.fixtitle._bg = true
P.report.fixtitle._async = true
P.report.fixtitle._auth = '@oa.works'`;

`P.report.fixcroa = ->
  fixes = 0
  checked = 0
  batch = []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'crossref_is_oa:true', scroll: '30m'
    checked += 1
    console.log('fix crossref is OA checked', checked, fixes) if checked % 100 is 0
    if cr = await @src.crossref.works rec.DOI
      if cr.is_oa isnt true
        fixes += 1
        rec.crossref_is_oa = false
        batch.push rec
    if batch.length is 20000
      await @report.works batch
      batch = []
  if batch.length
    await @report.works batch
  console.log 'fix crossref is OA completed with', checked, fixes
  return fixes
P.report.fixcroa._bg = true
P.report.fixcroa._async = true
P.report.fixcroa._auth = '@oa.works'

P.report.fixtype = ->
  fixes = 0
  fixols = 0
  nool = 0
  checked = 0
  batch = []
  for await rec from @index._for 'paradigm_' + (if @S.dev then 'b_' else '') + 'report_works', 'NOT type:*', scroll: '30m'
    checked += 1
    console.log('fix type checked', checked, fixes, fixols, nool, batch.length) if checked % 100 is 0
    fixed = false
    if ol = await @src.openalex.works rec.DOI
      if ol.type
        fixed = true
        fixes += 1
        rec.type = ol.type
        batch.push rec
    else
      nool += 1
    if not fixed and nol = await @src.openalex.works.doi rec.DOI, true
      console.log 'report fixtype updated openalex', rec.DOI
      fixes += 1
      fixols += 1
      rec.type = nol.type
      batch.push rec
    if batch.length is 5000
      await @report.works batch
      batch = []
  if batch.length
    await @report.works batch
  console.log 'fix type completed with', checked, fixes, fixols, nool
  return fixes
P.report.fixtype._bg = true
P.report.fixtype._async = true
P.report.fixtype._auth = '@oa.works'`;

`P.exports = ->
for idx in ['paradigm_svc_rscvd']
  total = 0
  fdn = @S.directory + '/report/export_' + idx + '.jsonl'
  try
    out = await fs.createWriteStream fdn #, 'utf-8'
    for await o from @index._for idx, undefined, undefined, false
      await out.write (if total then '\n' else '') + JSON.stringify o
      total += 1
      console.log('exporting', total) if total % 1000 is 0
  catch err
    console.log 'exports error', JSON.stringify err
  console.log idx, 'export done', total
return true
P.exports._bg = true
P.exports._async = true
P.exports._log = false`;

`P.reloads = ->
for idx in ['paradigm_b_users', 'paradigm_b_report_orgs_orgkeys', 'paradigm_users', 'paradigm_report_orgs_orgkeys', 'paradigm_deposits', 'paradigm_ills', 'paradigm_svc_rscvd']
  total = 0
  batch = []
  pre = ''
  for await line from readline.createInterface input: fs.createReadStream @S.directory + '/import/export_' + idx + '.jsonl'
    if line.endsWith '}'
      batch.push JSON.parse pre + line
      pre = ''
      total += 1
    else
      pre += line
  await @index._bulk(idx, batch, undefined, undefined, false) if batch.length
  console.log idx, 'reloaded', total
return true
P.reloads._bg = true
P.reloads._async = true`;

`P.report.test = _index: true, _alias: 'altest2'
P.report.test.add = ->
  toalias = @params.toalias
  toalias += '' if typeof toalias is 'number'
  l = await @dot P, 'report.test._alias'
  await @report.test hello: 'world', alias: l ? 'none'
  await @sleep 2000
  res = count: await @report.test.count(), ford: 0, records: []
  t = 'report_test'
  batch = [{hello: 'world', alias: l ? 'none', batch: 1}, {hello: 'world', alias: l ? 'none', batch: 2}]
  await @index._bulk t, batch, undefined, undefined, undefined, toalias
  await @sleep 2000
  for await i from @index._for 'report_test', '*'
    res.ford += 1
    res.records.push i
  return res`;

var indexOf = [].indexOf;

if (P.svc == null) {
  P.svc = {};
}

P.svc.rscvd = {
  _index: true
};

P.svc.rscvd.form = async function() {
  var av, rec, ref, ref1, ref2, ref3, rq, txt;
  if (this.keys(this.params).length > 1) {
    rec = this.copy(this.params);
    delete rec.form;
    rec.status = 'Awaiting verification';
    try {
      if (rq = (await this.svc.rscvd.requestees('email:"' + rec.email + '"'))) {
        if ((rq != null ? rq.verified : void 0) || (rq != null ? rq.verification : void 0) === 'Approved') {
          rec.status = 'Verified';
          rec.verified = true;
        } else if ((rq != null ? rq.denied : void 0) || (rq != null ? rq.verification : void 0) === 'Denied') {
          rec.status = 'Denied';
          rec.verified = false;
        }
      }
    } catch (error) {}
    if (rec.status === 'Awaiting verification') { // not yet found in pre-verified list
      try {
        av = (await this.svc.rscvd('email:"' + rec.email + '" AND verified:*'));
        if ((av != null ? (ref = av.hits) != null ? ref.hits : void 0 : void 0) && av.hits.hits[0]._source.verified === true) {
          rec.status = 'Verified';
          rec.verified = true;
        } else if (av.hits.hits[0]._source.verified === false) {
          rec.status = 'Denied';
          rec.verified = false;
        }
      } catch (error) {}
    }
    if (rec.type == null) {
      rec.type = 'paper';
    }
    try {
      rec.createdAt = new Date();
    } catch (error) {}
    try {
      rec.neededAt = (await this.epoch(rec['needed-by']));
    } catch (error) {}
    rec._id = (await this.svc.rscvd(rec));
    try {
      txt = 'Hi ' + rec.name + ',<br><br>We got your request:<br><br>Title: ' + ((ref1 = (ref2 = rec.atitle) != null ? ref2 : rec.title) != null ? ref1 : 'Unknown') + '\nReference (if provided): ' + ((ref3 = rec.reference) != null ? ref3 : '') + '<br><br>';
      txt += 'If at any point you no longer need this item, please <a href="https://' + (this.S.dev ? 'dev.' : '') + 'rscvd.org/cancel?id=' + rec._id + '">cancel your request</a>, it only takes a second.<br><br>';
      txt += 'Our team of volunteers will try and fill your request as soon as possible. If you would like to thank us, please consider <a href="https://rscvd.org/volunteer">joining us in helping supply requests</a>.<br><br>';
      txt += 'Yours,<br><br>RSCVD team';
      this.mail({
        from: 'rscvd@oa.works',
        to: rec.email,
        subject: 'RSCVD Request Receipt',
        text: txt
      });
    } catch (error) {}
    return rec;
  } else {

  }
};

P.svc.rscvd.requestees = {
  _index: true,
  _auth: true,
  _prefix: false,
  _sheet: '1GuIH-Onf0A0dXFokH6Ma0cS0TRbbpAeOyhDVpmDNDNw'
};

P.svc.rscvd.resolves = async function(rid, resolver) {
  var i, len, meta, r, rec, recs, ref, ref1, ref2, ref3, res, resolves;
  if (rid == null) {
    rid = this.params.resolves;
  }
  if (resolver == null) {
    resolver = this.params.resolver;
  }
  if (rid) {
    rec = typeof rid === 'object' ? rid : (await this.svc.rscvd(rid)); // can pass the ID of a specific record to resolve
  } else {
    recs = (await this.svc.rscvd('(status:"Awaiting verification" OR status:"Verified" OR status:"In progress" OR status:"Awaiting Peter") AND NOT resolved:"' + resolver + '" AND NOT unresolved:"' + resolver + '"'));
  }
  res = {};
  ref2 = (rec != null ? [rec] : (ref = recs != null ? (ref1 = recs.hits) != null ? ref1.hits : void 0 : void 0) != null ? ref : []);
  for (i = 0, len = ref2.length; i < len; i++) {
    r = ref2[i];
    if (r._source != null) {
      rec = r._source;
      if (rec._id == null) {
        rec._id = r._id;
      }
    }
    meta = this.copy(rec);
    if (meta.title) {
      meta.journal = meta.title;
    }
    if (meta.atitle) {
      meta.title = meta.atitle;
    }
    resolves = (await this.ill.subscription({
      subscription: resolver
    }, meta)); // should send the metadata in the record
    if (resolves != null ? resolves.url : void 0) { // if resolves
      if (rec.resolved == null) {
        rec.resolved = [];
      }
      rec.resolved.push(resolver);
      if (rec.resolves == null) {
        rec.resolves = [];
      }
      rec.resolves.push({
        resolver: resolver,
        url: resolves.url,
        user: (ref3 = this.user) != null ? ref3._id : void 0
      });
      res[r._id] = true; // does not resolve
    } else {
      if (rec.unresolved == null) {
        rec.unresolved = [];
      }
      rec.unresolved.push(resolver);
      res[r._id] = false;
    }
    this.svc.rscvd(rec);
  }
  if (rid && res[rid]) {
    return res[rid];
  } else {
    return res;
  }
};

P.svc.rscvd.cancel = async function() {
  var rec;
  if (!this.params.cancel) {
    return void 0;
  }
  rec = (await this.svc.rscvd(this.params.cancel));
  rec.status = 'Cancelled';
  this.svc.rscvd(rec);
  return rec;
};

P.svc.rscvd.verify = async function(email, verify = true) {
  var re, ref;
  if (email == null) {
    email = this.params.verify;
  }
  if (!email) {
    return void 0;
  }
  re = (await this.svc.rscvd.requestees('email:"' + email + '"'));
  if ((re != null ? (ref = re.hits) != null ? ref.total : void 0 : void 0) === 1) {
    re = re.hits.hits[0]._source;
  }
  if ((re != null ? re.hits : void 0) != null) {
    re = void 0;
  }
  if (re == null) {
    re = {
      email: email,
      createdAt: Date.now()
    };
  }
  if (verify) {
    re.verified = true;
    re.verified_by = this.user.email;
  } else {
    re.denied = true;
    re.denied_by = this.user.email;
  }
  this.waitUntil(this.svc.rscvd.requestees(re));
  await this.svc.rscvd._each('email:"' + email + '"', {
    action: 'index'
  }, function(rec) {
    if (!rec.status || rec.status === 'Awaiting verification') {
      rec.verified = verify;
      if (verify) {
        rec.status = 'Verified';
        rec.verified_by = this.user.email;
      } else {
        rec.status = 'Denied';
        rec.denied_by = this.user.email;
      }
    }
    return rec;
  });
  return true;
};

P.svc.rscvd.verify._auth = true;

P.svc.rscvd.deny = function() {
  return this.svc.rscvd.verify(this.params.deny, false);
};

P.svc.rscvd.deny._auth = true;

P.svc.rscvd.status = async function() {
  var rec, rid, status;
  if (!this.params.status) {
    return void 0;
  }
  [rid, status] = this.params.status.split('/');
  rec = (await this.svc.rscvd(rid));
  rec.status = status;
  try {
    if (rec.status === 'Done') {
      rec.done_by = this.user.email;
    } else if (rec.status === 'In Progress') {
      rec.progressed_by = this.user.email;
    }
  } catch (error) {}
  this.svc.rscvd(rec);
  return rec;
};

P.svc.rscvd.status._auth = true;

P.svc.rscvd.poll = async function(poll, which) {
  var base, base1, c, cc, cn, d, dn, ds, i, j, k, l, len, len1, len2, len3, len4, m, n, name, nn, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, res, s, ss, st, v, vn, vs;
  if (poll == null) {
    poll = (ref = this.params.poll) != null ? ref : Date.now() - 180000; // default to changes in last 3 mins
  }
  which = (ref1 = this.params.which) != null ? ref1 : ['new', 'verify', 'deny', 'cancel', 'status', 'overdue'];
  if (typeof which === 'string') {
    which = which.split(',');
  }
  if (indexOf.call(which, 'overdue') >= 0) {
    this.svc.rscvd.overdue();
  }
  res = {
    new: [],
    verify: [],
    deny: [],
    cancel: [],
    status: {}
  };
  if (indexOf.call(which, 'new') >= 0) {
    nn = (await this.svc.rscvd('(status:"Awaiting verification" OR status:"Verified") AND createdAt:>' + poll, 500));
    ref4 = (ref2 = nn != null ? (ref3 = nn.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
    for (i = 0, len = ref4.length; i < len; i++) {
      n = ref4[i];
      if ((base = n._source)._id == null) {
        base._id = n._id;
      }
      res.new.push(n._source);
    }
  }
  if (indexOf.call(which, 'verify') >= 0) {
    vs = (await this.index('logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.verify"', {
      sort: {
        createdAt: 'desc'
      },
      size: 500
    }));
    ref5 = vs.hits.hits;
    for (j = 0, len1 = ref5.length; j < len1; j++) {
      v = ref5[j];
      vn = v._source.parts.pop();
      if (indexOf.call(res.verify, vn) < 0) {
        res.verify.push(vn);
      }
    }
  }
  if (indexOf.call(which, 'deny') >= 0) {
    ds = (await this.index('logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.deny"', {
      sort: {
        createdAt: 'desc'
      },
      size: 500
    }));
    ref6 = ds.hits.hits;
    for (k = 0, len2 = ref6.length; k < len2; k++) {
      d = ref6[k];
      dn = d._source.parts.pop();
      if (indexOf.call(res.deny, dn) < 0) {
        res.deny.push(dn);
      }
    }
  }
  if (indexOf.call(which, 'cancel') >= 0) {
    cc = (await this.index('logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.cancel"', {
      sort: {
        createdAt: 'desc'
      },
      size: 500
    }));
    ref7 = cc.hits.hits;
    for (l = 0, len3 = ref7.length; l < len3; l++) {
      c = ref7[l];
      cn = c._source.parts.pop();
      if (indexOf.call(res.cancel, cn) < 0) {
        res.cancel.push(cn);
      }
    }
  }
  // TODO need to track changes to Overdue status as well
  if (indexOf.call(which, 'status') >= 0) {
    ss = (await this.index('logs', 'createdAt:>' + poll + ' AND fn:"svc.rscvd.status"', {
      sort: {
        createdAt: 'desc'
      },
      size: 500
    }));
    ref8 = ss.hits.hits;
    for (m = 0, len4 = ref8.length; m < len4; m++) {
      s = ref8[m];
      st = s._source.parts.pop();
      if ((base1 = res.status)[name = s._source.parts.pop()] == null) {
        base1[name] = st; // only return the most recent status change for a given record ID
      }
    }
  }
  return res;
};

P.svc.rscvd.poll._log = false;

P.svc.rscvd.overdue = async function() {
  var base, counter, dn, i, j, len, len1, r, rec, recs, ref, res;
  counter = 0;
  dn = Date.now();
  recs = [];
  if (this.params.overdue) {
    recs.push((await this.svc.rscvd(this.params.overdue)));
  } else {
    res = (await this.svc.rscvd('(status:"Awaiting verification" OR status:"Verified") AND (neededAt:<' + dn + ' OR createdAt:<' + (dn - 1209600000) + ')', 10000));
    ref = res.hits.hits;
    for (i = 0, len = ref.length; i < len; i++) {
      r = ref[i];
      if ((base = r._source)._id == null) {
        base._id = r._id;
      }
      recs.push(r._source);
    }
  }
  for (j = 0, len1 = recs.length; j < len1; j++) {
    rec = recs[j];
    rec.status = 'Overdue';
    this.waitUntil(this.svc.rscvd(rec));
    counter += 1;
  }
  return counter;
};

// https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
// http://api.crossref.org/works/10.1016/j.paid.2009.02.013
var indexOf = [].indexOf;

P.src.crossref = function() {
  return 'Crossref API wrapper';
};

`P.src.crossref.works = (doi) ->
doi ?= @params.works ? @params.doi ? @params.title ? @params.q
if typeof doi is 'string'
  if doi.indexOf('10.') isnt 0
    res = await @src.crossref.works.title doi
  else
    # a search of an index of works - and remainder of route is a DOI to return one record
    doi = doi.split('//')[1] if doi.indexOf('http') is 0
    doi = '10.' + doi.split('/10.')[1] if doi.indexOf('10.') isnt 0 and doi.indexOf('/10.') isnt -1
    url = 'https://api.crossref.org/works/' + doi
    res = await @fetch url, {headers: {'User-Agent': (@S.name ? 'OA.Works') + '; mailto:' + (@S.mail?.to ? 'sysadmin@oa.works'), 'Crossref-Plus-API-Token': 'Bearer ' + @S.crossref}}

  if res?.message?.DOI?
    return @src.crossref.works._format res.message
return`;

P.src.crossref.works = {
  _index: {
    settings: {
      number_of_shards: 15
    }
  }
};

P.src.crossref.works._key = 'DOI';

P.src.crossref.works._prefix = false;

P.src.crossref.works.doi = async function(doi, save) {
  var formatted, ref, ref1, ref2, ref3, ref4, res;
  if (doi == null) {
    doi = this.params.doi;
  }
  if (save == null) {
    save = (ref = this.params.save) != null ? ref : false;
  }
  if (typeof doi === 'string' && doi.startsWith('10.')) {
    if (doi.indexOf('http') === 0) {
      doi = doi.split('//')[1];
    }
    if (doi.indexOf('10.') !== 0 && doi.indexOf('/10.') !== -1) {
      doi = '10.' + doi.split('/10.')[1];
    }
    res = (await this.fetch('https://api.crossref.org/works/' + doi, {
      headers: {
        'User-Agent': ((ref1 = this.S.name) != null ? ref1 : 'OA.Works') + '; mailto:' + ((ref2 = (ref3 = this.S.mail) != null ? ref3.to : void 0) != null ? ref2 : 'sysadmin@oa.works'),
        'Crossref-Plus-API-Token': 'Bearer ' + this.S.crossref
      }
    }));
    if ((res != null ? (ref4 = res.message) != null ? ref4.DOI : void 0 : void 0) != null) {
      formatted = (await this.src.crossref.works._format(res.message));
      if (save) {
        await this.src.crossref.works(formatted);
      }
      return formatted;
    }
  }
};

P.src.crossref.works.title = async function(title) {
  var j, len, len1, ltitle, m, qr, r, ref, ref1, ref2, ref3, ref4, rem, res, rt, st, t;
  if (title == null) {
    title = (ref = this.params.title) != null ? ref : this.params.q;
  }
  qr = 'title:"' + title + '"';
  if (title.split(' ').length > 2) {
    qr += ' OR (';
    ref1 = title.split(' ');
    for (j = 0, len = ref1.length; j < len; j++) {
      t = ref1[j];
      if (!qr.endsWith('(')) {
        qr += ' AND ';
      }
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")';
    }
    qr += ')';
  }
  rem = (await this.src.crossref.works(qr));
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
  ref4 = (ref2 = rem != null ? (ref3 = rem.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
  for (m = 0, len1 = ref4.length; m < len1; m++) {
    r = ref4[m];
    if (r._source.DOI && r._source.title && r._source.title.length) {
      rt = (typeof r._source.title === 'string' ? r._source.title : r._source.title[0]).toLowerCase();
      if (r._source.subtitle && r._source.subtitle.length) {
        st = (typeof r._source.subtitle === 'string' ? r._source.subtitle : r._source.subtitle[0]).toLowerCase();
        if (typeof st === 'string' && st.length && indexOf.call(rt, st) < 0) {
          rt += ' ' + st;
        }
      }
      rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
      if ((ltitle.indexOf(rt) !== -1 || rt.indexOf(ltitle) !== -1) && ltitle.length / rt.length > 0.7 && ltitle.length / rt.length < 1.3) {
        if (r._source.type === 'journal-article') {
          res = r._source;
        } else if ((res == null) || (res.type !== 'journal-article' && r._source.type === 'journal-article')) {
          res = r._source;
        }
      }
    }
  }
  return res;
};

P.src.crossref.works._format = async function(rec) {
  var a, au, j, l, len, len1, len2, m, n, ref, ref1, ref2, ref3, ref4, ref5, ref6;
  if (rec.abstract) {
    rec.abstract = rec.abstract.replace(/<.*?>/g, '').replace(/^ABSTRACT/, '');
  }
  if (rec._id == null) {
    rec._id = rec.DOI.replace(/\//g, '_');
  }
  ref1 = (ref = rec.assertion) != null ? ref : [];
  for (j = 0, len = ref1.length; j < len; j++) {
    a = ref1[j];
    if (a.label === 'OPEN ACCESS') {
      if (a.URL && a.URL.indexOf('creativecommons') !== -1) {
        if (rec.license == null) {
          rec.license = [];
        }
        rec.license.push({
          'URL': a.URL
        });
      }
      rec.is_oa = true;
    }
  }
  ref3 = (ref2 = rec.license) != null ? ref2 : [];
  for (m = 0, len1 = ref3.length; m < len1; m++) {
    l = ref3[m];
    if (l.URL && l.URL.indexOf('creativecommons') !== -1 && (!rec.licence || rec.licence.indexOf('creativecommons') === -1)) {
      rec.licence = l.URL;
      try {
        rec.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/^\//, '').replace(/\/$/, '').replace(/\//g, '-').replace(/-$/, '');
      } catch (error) {}
      rec.is_oa = true;
    }
  }
  try {
    if (rec.reference && rec.reference.length > 100) {
      rec.reference_original_length = rec.reference.length;
      rec.reference = rec.reference.slice(0, 100);
    }
  } catch (error) {}
  try {
    if (rec.relation && rec.relation.length > 100) {
      rec.relation_original_length = rec.relation.length;
      rec.relation = rec.relation.slice(0, 100);
    }
  } catch (error) {}
  ref5 = (ref4 = rec.author) != null ? ref4 : [];
  for (n = 0, len2 = ref5.length; n < len2; n++) {
    au = ref5[n];
    au.name = (au.given ? au.given + ' ' : '') + ((ref6 = au.family) != null ? ref6 : '');
  }
  if (rec.published = (await this.src.crossref.works.published(rec))) {
    try {
      rec.year = rec.published.split('-')[0];
    } catch (error) {}
    try {
      parseInt(rec.year);
    } catch (error) {}
    try {
      rec.publishedAt = (await this.epoch(rec.published));
    } catch (error) {}
  }
  return rec;
};

P.src.crossref.works.published = async function(rec) {
  var j, len, p, pp, ppe, ppp, ref, ref1, rp;
  if (rec == null) {
    rec = this.params.published;
  }
  if (typeof rec === 'string') {
    rec = (await this.src.crossref.works(rec));
  }
  if (rec != null) {
    ppe = void 0;
    pp = void 0;
    ref = ['published', 'published-print', 'published-online', 'issued', 'deposited'];
    for (j = 0, len = ref.length; j < len; j++) {
      p = ref[j];
      if (typeof rec[p] === 'object') {
        ppp = void 0;
        if (typeof rec[p]['date-time'] === 'string' && rec[p]['date-time'].split('T')[0].split('-').length === 3) {
          ppp = rec[p]['date-time'].split('T')[0];
        } else if (Array.isArray(rec[p]['date-parts']) && rec[p]['date-parts'].length && Array.isArray(rec[p]['date-parts'][0])) {
          rp = rec[p]['date-parts'][0];
          if (((ref1 = typeof rp[0]) === 'string' || ref1 === 'number') && rp[0] !== 'null') {
            ppp = rp[0] + (rp.length > 1 ? '-' + (rp[1].toString().length === 1 ? '0' : '') + rp[1] : '-01') + (rp.length > 2 ? '-' + (rp[2].toString().length === 1 ? '0' : '') + rp[2] : '-01');
          }
        }
        if (ppp && (!pp || ppe > (await this.epoch(ppp)))) {
          pp = ppp;
          ppe = (await this.epoch(pp));
        }
      }
    }
    return pp;
  }
};

P.src.crossref.works.published._log = false;

P.src.crossref.works.search = async function(qrystr, from, size, filter, start, end, sort, order) {
  var filtered, fp, k, ky, qry, ref, ref1, ref2, ref3, ref4, res, url;
  if (qrystr == null) {
    qrystr = (ref = this.params.q) != null ? ref : this.params.search; //? @params
  }
  if (from == null) {
    from = this.params.from;
  }
  if (size == null) {
    size = this.params.size;
  }
  if (filter == null) {
    filter = this.params.filter;
  }
  if (start == null) {
    start = this.params.start;
  }
  if (end == null) {
    end = this.params.end;
  }
  if (sort == null) {
    sort = this.params.sort;
  }
  if (order == null) {
    order = (ref1 = this.params.order) != null ? ref1 : 'asc';
  }
  filtered = '';
  if (start) {
    if (filter == null) {
      filter = sort != null ? sort : 'updated'; // can be published, indexed, deposited, created, updated. indexed catches the most changes but can be very large and takes a long time
    }
    if (typeof start !== 'string' || start.indexOf('-') === -1) { // should be like 2021-01-31
      // updated should only miss crossref internal things like citation count, see https://community.crossref.org/t/date-range-search-of-index-changes-seems-to-retrieve-too-many-records/1468
      // NOTE updated does NOT work for getting all records for a day because CREATED records can be created on a different day from which they are created, and they have no updated value, so the only way to find them is indexed date.
      start = (await this.date(start));
    }
    filtered = 'from-' + filter.replace('lished', '').replace('xed', 'x').replace('ited', 'it').replace('dated', 'date') + '-date:' + start;
  }
  if (end) {
    if (filter == null) {
      filter = sort != null ? sort : 'updated';
    }
    if (typeof end !== 'string' || end.indexOf('-') === -1) {
      end = (await this.date(end));
    }
    filtered += (filtered ? ',' : '') + 'until-' + filter.replace('lished', '').replace('xed', 'x').replace('ited', 'it').replace('dated', 'date') + '-date:' + end;
  }
  if (filtered) {
    filter = filtered;
  }
  url = 'https://api.crossref.org/works?';
  if (sort != null) {
    url += 'sort=' + sort + '&order=' + order + '&';
  }
  if (typeof qrystr === 'object') {
    for (k in qrystr) {
      if (k !== 'from' && k !== 'size' && k !== 'filter' && k !== 'start' && k !== 'end' && k !== 'sort' && k !== 'order') {
        ky = k === 'title' || k === 'citation' || k === 'issn' ? 'query.bibliographic' : k === 'journal' ? 'query.container-title' : k === 'author' || k === 'editor' || k === 'chair' || k === 'translator' || k === 'contributor' || k === 'affiliation' || k === 'bibliographic' ? 'query.' + k : k;
        url += ky + '=' + encodeURIComponent(qrystr[k]) + '&';
      }
    }
  } else if (qrystr && qrystr !== 'all') {
    qry = qrystr.replace(/\w+?\:/g, ''); //.replace(/ AND /g,'+').replace(/ NOT /g,'-')
    qry = qry.replace(/ /g, '+');
    url += 'query=' + encodeURIComponent(qry) + '&';
  }
  if (from != null) {
    if (from !== '*' && typeof from === 'string' && !from.replace(/[0-9]/g, '').length) {
      try {
        fp = parseInt(from);
        if (!isNaN(fp)) {
          from = fp;
        }
      } catch (error) {}
    }
    if (typeof from !== 'number') {
      url += 'cursor=' + encodeURIComponent(from) + '&';
    } else {
      url += 'offset=' + from + '&';
    }
  }
  if (size != null) {
    url += 'rows=' + size + '&'; // max size is 1000
  }
  if (filter) {
    url += 'filter=' + encodeURIComponent(filter) + '&';
  }
  url = url.replace('?&', '?').replace(/&$/, ''); // tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  try {
    res = (await this.fetch(url, {
      headers: {
        'User-Agent': ((ref2 = this.S.name) != null ? ref2 : 'OA.Works') + '; mailto:' + ((ref3 = (ref4 = this.S.mail) != null ? ref4.to : void 0) != null ? ref3 : 'sysadmin@oa.works'),
        'Crossref-Plus-API-Token': 'Bearer ' + this.S.crossref
      }
    }));
    return {
      total: res.message['total-results'],
      cursor: res.message['next-cursor'],
      data: res.message.items,
      facets: res.message.facets
    };
  } catch (error) {

  }
};

P.src.crossref.journals = {
  _index: true,
  _prefix: false
};

P.src.crossref.journals.load = async function() {
  var batch, counter, cursor, i, j, len, len1, len2, m, n, rec, ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, thisyear, total, url, yr;
  await this.src.crossref.journals('');
  counter = 0;
  total = 0;
  batch = [];
  cursor = '*';
  while (cursor && (counter === 0 || counter < total)) {
    url = 'https://api.crossref.org/journals?cursor=' + cursor + '&rows=' + 1000;
    res = (await this.fetch(url, {
      headers: {
        'User-Agent': ((ref = this.S.name) != null ? ref : 'OA.Works') + '; mailto:' + ((ref1 = (ref2 = this.S.mail) != null ? ref2.to : void 0) != null ? ref1 : 'sysadmin@oa.works'),
        'Crossref-Plus-API-Token': 'Bearer ' + this.S.crossref
      }
    }));
    if (total === 0) {
      total = res.message['total-results'];
    }
    cursor = res.message['next-cursor'];
    ref3 = res.message.items;
    for (j = 0, len = ref3.length; j < len; j++) {
      rec = ref3[j];
      if (rec.ISSN == null) {
        rec.ISSN = [];
      }
      rec.issn = [];
      ref4 = rec.ISSN;
      for (m = 0, len1 = ref4.length; m < len1; m++) {
        i = ref4[m];
        if (typeof i === 'string' && i.length && indexOf.call(rec.issn, i) < 0) {
          rec.issn.push(i);
        }
      }
      rec.dois = (ref5 = rec.counts) != null ? ref5['total-dois'] : void 0;
      if (((ref6 = rec.breakdowns) != null ? ref6['dois-by-issued-year'] : void 0) != null) {
        rec.years = [];
        ref7 = rec.breakdowns['dois-by-issued-year'];
        for (n = 0, len2 = ref7.length; n < len2; n++) {
          yr = ref7[n];
          if (yr.length === 2 && (ref8 = yr[0], indexOf.call(rec.years, ref8) < 0)) {
            rec.years.push(yr[0]);
          }
        }
        rec.years.sort();
      }
      if ((rec.years == null) || !rec.years.length || !rec.dois) {
        rec.discontinued = true;
      } else {
        thisyear = new Date().getFullYear();
        if (indexOf.call(rec.years, thisyear) < 0 && (ref9 = thisyear - 1, indexOf.call(rec.years, ref9) < 0) && (ref10 = thisyear - 2, indexOf.call(rec.years, ref10) < 0) && (ref11 = thisyear - 3, indexOf.call(rec.years, ref11) < 0)) {
          rec.discontinued = true;
        }
      }
      batch.push(rec);
    }
    counter += 1000;
    if (batch.length >= 10000) {
      await this.src.crossref.journals(batch);
      batch = [];
    }
  }
  if (batch.length) {
    await this.src.crossref.journals(batch);
    batch = [];
  }
  console.log(counter);
  return counter;
};

P.src.crossref.journals.load._bg = true;

P.src.crossref.journals.load._async = true;

P.src.crossref.journals.load._auth = 'root';

`P.src.crossref.load = () ->
batchsize = 10000 # how many records to batch upload at a time - kept low because large crossref files were causing OOM
howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going

# https://www.crossref.org/blog/new-public-data-file-120-million-metadata-records/
# https://academictorrents.com/details/e4287cb7619999709f6e9db5c359dda17e93d515
# this requires getting the crossref data dump from a torrent, which is a hassle on some commercial cloud providers
# but once the file is on disk, extract it and this process will be able to go from there
# there are torrent libs for node that could be used here, but given the infrequency and size of what we want 
# to torrent, it's safer to do that step separately. Here's some simple instructions for the Jan 2021 crossref release:
# sudo apt-get install aria2
# aria2c https://academictorrents.com/download/e4287cb7619999709f6e9db5c359dda17e93d515.torrent

# redo with 2022 dump:
# https://www.crossref.org/blog/2022-public-data-file-of-more-than-134-million-metadata-records-now-available/
# https://academictorrents.com/details/4dcfdf804775f2d92b7a030305fa0350ebef6f3e
# https://academictorrents.com/download/4dcfdf804775f2d92b7a030305fa0350ebef6f3e.torrent

# and 2023 update:
# https://www.crossref.org/blog/2023-public-data-file-now-available-with-new-and-improved-retrieval-options/
# https://academictorrents.com/details/d9e554f4f0c3047d9f49e448a7004f7aa1701b69
# https://academictorrents.com/download/d9e554f4f0c3047d9f49e448a7004f7aa1701b69.torrent

infolder = @S.directory + '/crossref/data/'
lastfile = @S.directory + '/crossref/last' # where to record the ID of the last file processed

files = -1 # max number of files to process. set to -1 to keep going
filenumber = 0 # crossref files are named by number, from 0, e.g. 0.json.gz
try filenumber = parseInt((await fs.readFile lastfile).toString()) if not @refresh

#await @src.crossref.works('') if filenumber is 0 and @params.clear

total = 0
batch = [] # batch of json records to upload

# there were 40228 in the 2020 data dump,  but oddly 9999 was missing
# for 2022 there are 26810
# for 2023 there are 28701
while filenumber >= 0 and filenumber isnt files and filenumber < 26810
  if filenumber not in [] # should make this a file exists check probably (just added 9999 to this list when running 2020)
    break if total is howmany
    console.log 'Crossref load starting file', filenumber
    lines = ''
    for await line from readline.createInterface input: fs.createReadStream(infolder + filenumber + '.json.gz').pipe zlib.createGunzip()
      lines += line
    
    for rec in JSON.parse(lines).items
      break if total is howmany
      total += 1
      rec = await @src.crossref.works._format rec
      rec['srcfile'] = filenumber
      batch.push rec
      
      if batch.length is batchsize
        console.log 'Crossref load ' + filenumber, total
        await @src.crossref.works batch
        await fs.writeFile lastfile, filenumber
        batch = []
  filenumber += 1

await @src.crossref.works(batch) if batch.length

console.log total
return total

P.src.crossref.load._bg = true
P.src.crossref.load._async = true
P.src.crossref.load._auth = 'root'`;

P.src.crossref.changes = async function(startday, endday, created) {
  var a, af, batch, batchsize, cursor, days, dn, doq, f, fr, fromthisday, j, last, len, len1, len2, len3, loaded, m, n, o, queued, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, retries, searchtype, thisdays, totalthisday;
  if (startday == null) {
    startday = this.params.changes;
  }
  if (typeof startday === 'string' && (startday.includes('/') || startday.includes('-'))) {
    startday = (await this.epoch(startday));
  }
  if (!startday) {
    try {
      last = (await this.src.crossref.works('srcday:*', {
        size: 1,
        sort: {
          srcday: 'desc'
        }
      }));
      startday = last.srcday + 86400000;
      console.log('Crossref changes start day set from latest record srcday', (await this.date(startday)));
    } catch (error) {}
  }
  if (!startday) {
    try {
      last = (await this.src.crossref.works('indexed.timestamp:*', {
        size: 1,
        sort: {
          'indexed.timestamp': 'desc'
        }
      }));
      startday = last.indexed.timestamp;
      console.log('Crossref changes start day set from latest record indexed timestamp', (await this.date(startday)));
    } catch (error) {}
  }
  if (startday == null) {
    startday = 1693526400000; // 1st September 2023
  }
  // 1607126400000 # the timestamp of when changes appeared to start after the last data dump, around 12/12/2020
  // for the 2022 update 1649635200000 was used for 11th April 2022
  startday = (await this.epoch((await this.date(startday))));
  if (endday == null) {
    endday = this.params.end;
  }
  if (typeof endday === 'string' && (endday.includes('/') || endday.includes('-'))) {
    endday = (await this.epoch(endday));
  }
  if (created == null) {
    created = this.params.created;
  }
  // tried to use updated and created to reduce unnecessary useless load of indexed which includes lots of irrelevant internal crossref changes
  // but it does not work, because created records may be created on different days to the day they were created, and do not show up as updated either
  searchtype = 'indexed'; //if created then 'created' else 'updated'
  batchsize = 10000;
  dn = endday != null ? endday : Date.now();
  dn = (await this.epoch((await this.date(dn))));
  loaded = 0;
  queued = 0;
  days = 0;
  batch = [];
  while (startday < dn) {
    console.log('Crossref changes', startday, days);
    cursor = '*'; // set a new cursor on each index day query
    days += 1;
    totalthisday = false;
    fromthisday = 0;
    retries = 0;
    while (retries < 3 && (totalthisday === false || fromthisday < totalthisday)) {
      await this.sleep(500);
      thisdays = (await this.src.crossref.works.search(void 0, cursor, 1000, searchtype, startday, startday)); // using same day for crossref API gets that whole day
      if (!(thisdays != null ? thisdays.data : void 0)) {
        console.log('crossref error');
        await this.sleep(2000); // wait on crossref downtime
        retries += 1;
      } else {
        ref = thisdays.data;
        for (j = 0, len = ref.length; j < len; j++) {
          rec = ref[j];
          fr = (await this.src.crossref.works._format(rec));
          fr.srcday = startday;
          batch.push(fr);
          loaded += 1;
          if (((rec.funder != null) || (rec.author != null)) && ((ref1 = rec.year) === '2023' || ref1 === '2022' || ref1 === 2023 || ref1 === 2022)) {
            doq = false;
            ref3 = (ref2 = rec.funder) != null ? ref2 : [];
            for (m = 0, len1 = ref3.length; m < len1; m++) {
              f = ref3[m];
              if (doq) {
                break;
              }
              if (f.name != null) {
                doq = rec.DOI;
              }
            }
            if (!doq) {
              ref5 = (ref4 = rec.author) != null ? ref4 : [];
              for (n = 0, len2 = ref5.length; n < len2; n++) {
                a = ref5[n];
                if (doq) {
                  break;
                }
                ref7 = (ref6 = a.affiliation) != null ? ref6 : [];
                for (o = 0, len3 = ref7.length; o < len3; o++) {
                  af = ref7[o];
                  if (doq) {
                    break;
                  }
                  if (af.name != null) {
                    doq = rec.DOI;
                  }
                }
              }
            }
            if (doq) {
              try {
                await this.report.queue(doq, void 0, void 0, void 0, 'changes');
              } catch (error) {}
              queued += 1;
            }
          }
        }
        if (batch.length >= batchsize) {
          console.log('Crossref bulk load', startday, days, totalthisday, fromthisday, loaded, queued);
          await this.src.crossref.works(batch);
          batch = [];
        }
        if (totalthisday === false) {
          totalthisday = (ref8 = thisdays.total) != null ? ref8 : 0;
          console.log(startday, totalthisday);
        }
        fromthisday += 1000;
        cursor = thisdays.cursor;
      }
    }
    startday += 86400000;
  }
  if (batch.length) {
    await this.src.crossref.works(batch);
  }
  console.log('crossref works changes completed', loaded, days, queued);
  return loaded;
};

P.src.crossref.changes._bg = true;

P.src.crossref.changes._async = true;

P.src.crossref.changes._log = false;

P.src.crossref.changes._auth = 'root';

P.src.crossref.changes._notify = false;

P.src.crossref.plus = {};

P.src.crossref.plus.load = async function() {
  var complete, ended, fn, hds, last, lines, map, prevline, resp, srcfile, started, stats, strm, total, wstr;
  // we now have metadata plus: 
  // https://www.crossref.org/documentation/metadata-plus/metadata-plus-snapshots/
  // export CRTOKEN='<insert-your-token-here>'
  // curl -o "all.json.tar.gz" --progress-bar -L -X GET  https://api.crossref.org/snapshots/monthly/latest/all.json.tar.gz -H "Crossref-Plus-API-Token: Bearer ${CRTOKEN}"
  // and there may be issues downloading, at least FAQ seems to indicate some people may have. If so, redo above command to continue where failed with added -C - 
  started = (await this.epoch());
  last = 0;
  if (this.params.clear) {
    await this.src.crossref.works('');
    map = {
      properties: {} // add any specific field mappings necessary to avoid collisions e.g. assertion.value can be text or date or number etc, so force to text
    };
    map.properties.assertion = { // note whole object has to be provided otherwise updating mapping with extra values in the object (or saving a record with extra values) overwrites it
      "properties": {
        "URL": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "explanation": {
          "properties": {
            "URL": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            }
          }
        },
        "group": {
          "properties": {
            "label": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            },
            "name": {
              "type": "text",
              "fields": {
                "keyword": {
                  "type": "keyword",
                  "ignore_above": 256
                }
              }
            }
          }
        },
        "label": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "name": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "order": {
          "type": "long"
        },
        "value": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        }
      }
    };
    await this.src.crossref.works.mapping(map);
  } else {
    try {
      last = ((await this.src.crossref.works('srcfile:*', {
        size: 1,
        sort: {
          srcfile: 'desc'
        }
      }))).srcfile;
    } catch (error) {}
  }
  fn = this.S.directory + '/import/crossref/all.json.tar.gz';
  try {
    stats = (await fs.stat(fn)); // check if file exists in async fs promises which does not have .exists
  } catch (error) {
    console.log('crossref downloading snapshot');
    hds = {};
    hds['Crossref-Plus-API-Token'] = 'Bearer ' + this.S.crossref;
    resp = (await fetch('https://api.crossref.org/snapshots/monthly/latest/all.json.tar.gz', {
      headers: hds
    }));
    wstr = fs.createWriteStream(fn);
    await new Promise((resolve, reject) => {
      resp.body.pipe(wstr);
      resp.body.on('error', reject);
      return wstr.on('finish', resolve);
    });
    console.log('snapshot downloaded');
  }
  total = 0;
  srcfile = 0;
  lines = '';
  complete = false;
  `for await line from readline.createInterface input: fs.createReadStream(fn).pipe zlib.createGunzip()
  if not line.startsWith(' ') and line.endsWith('{') and line.includes('.json') and not isNaN (scf = parseInt line.split('.json')[0].replace(/[^0-9]/g, ''))
    console.log total, srcfile, scf, lines.length
    if lines.length
      # on large file readline streams across multiple hours, definitely saw this issue. Not sure why pause/resume would help in this context, but trying it anyway
      # https://github.com/nodejs/node/issues/42454
      # https://stackoverflow.com/questions/71588045/javascript-async-sleep-function-somehow-leads-to-silent-exiting-of-program/71589103#71589103
      # lr.pause() # did not make any difference
      await _batch()
      #lr.resume()
    srcfile = scf
    lines = '{'
  else
    lines += line
await _batch(true) if lines.length or batch.length`;
  strm = fs.createReadStream(fn).pipe(zlib.createGunzip());
  prevline = '';
  strm.on('data', async(chunk) => {
    var j, len, line, lp, lps, rec, recs, ref, rp, scf;
    line = chunk.toString('utf8');
    lines += line;
    if ((prevline + line).includes('\n  "items" : [')) { // just a shorter space to check than all of lines, and use prevline just in case the inclusion criteria straddled a chunk
      while (lines.includes('\n  "items" : [')) {
        [lp, lines] = lines.replace('\n  "items" : [', 'X0X0X0X0X0X0X0X0X0X0X0').split('X0X0X0X0X0X0X0X0X0X0X0'); // cheap split on first occurrence
        if (lp.includes('\n  } ]')) {
          lps = lp.split('\n  } ]');
          scf = parseInt(lps.pop().split('.json')[0].replace(/[^0-9]/g, ''));
          if (srcfile < last) {
            console.log('crossref plus load waiting for file', srcfile, last);
          } else {
            recs = [];
            ref = rp = JSON.parse('[' + lps.join(']') + '}]');
            for (j = 0, len = ref.length; j < len; j++) {
              rec = ref[j];
              rec = (await this.src.crossref.works._format(rec));
              if (rec != null ? rec.DOI : void 0) {
                rec.srcfile = srcfile;
                recs.push(rec);
              }
            }
            console.log('crossref plus load', rp.length, recs.length);
            total += recs.length;
            if (recs.length) {
              await this.src.crossref.works(recs);
            }
          }
          srcfile = scf;
        }
      }
    }
    return prevline = line;
  });
  strm.on('error', (err) => {
    return console.log('crossref plus load file stream error', JSON.stringify(err));
  });
  strm.on('end', () => {
    console.log('stream complete for crossref plus load');
    return complete = true;
  });
  while (!complete) {
    console.log('crossref plus load streaming file', lines.length, srcfile, total, Math.floor((Date.now() - started) / 1000 / 60) + 'm');
    await this.sleep(30000);
  }
  ended = Date.now();
  console.log('crossref plus load complete', srcfile, total, started, ended, Math.floor((ended - started) / 1000 / 60) + 'm');
  return total;
};

P.src.crossref.plus.load._log = false;

P.src.crossref.plus.load._bg = true;

P.src.crossref.plus.load._async = true;

//P.src.crossref.plus.load._auth = 'root'

var base;

if ((base = S.src).doaj == null) {
  base.doaj = {};
}

try {
  S.src.doaj.secrets = JSON.parse(SECRETS_DOAJ);
} catch (error) {}

P.src.doaj = {};

P.src.doaj.journals = {
  _index: true,
  _prefix: false
};

P.src.doaj.journals.load = async function() {
  var current, f, fldr, i, journals, len, ref, total;
  fldr = '/tmp/doaj_' + (await this.uid());
  await fs.mkdir(fldr);
  fldr += '/';
  await fs.writeFile(fldr + 'doaj.tar', (await this.fetch('https://doaj.org/public-data-dump/journal?api_key=' + S.src.doaj.secrets.apikey, {
    buffer: true
  })));
  tar.extract({
    file: fldr + 'doaj.tar',
    cwd: fldr,
    sync: true // extracted doaj dump folders end 2020-10-01
  });
  current = false;
  ref = (await fs.readdir(fldr));
  for (i = 0, len = ref.length; i < len; i++) {
    f = ref[i];
    if (f.includes('doaj_journal_data')) {
      current = f;
    }
  }
  total = 0;
  if (current) {
    journals = JSON.parse((await fs.readFile(fldr + current + '/journal_batch_1.json')));
    total = journals.length;
    await this.src.doaj.journals('');
    await this.src.doaj.journals(journals);
    await fs.unlink(fldr + current + '/journal_batch_1.json');
  }
  await fs.rmdir(fldr + current);
  await fs.unlink(fldr + 'doaj.tar');
  await fs.rmdir(fldr);
  return total;
};

P.src.doaj.journals.load._bg = true;

P.src.doaj.journals.load._async = true;

P.src.doaj.journals.load._auth = 'root';

`P.src.doaj = (qry, params={}) ->
  url = 'https://doaj.org/api/v1/search/articles/' + qry + '?'
  #params.sort ?= 'bibjson.year:desc'
  url += op + '=' + params[op] + '&' for op of params
  return @fetch url # with a 400ms timeout

P.src.doaj.es = (params, which='journal,article') ->
  params ?= @params
  # which could be journal or article or journal,article
  # but doaj only allows this type of query on journal,article, so will add this later as a query filter
  url = 'https://doaj.org/query/journal,article/_search?ref=public_journal_article&'
  # this only works with a source param, if one is not present, should convert the query into a source param
  tr = await @index.translate @params
  tr = source: tr # unless doing a post, in which case don't do this part
  tr.source.aggs ?= {} # require this to get doaj to accept the query
  tr.source.query.filtered.query.bool.must.push({term: {_type: which}}) if which isnt 'journal,article'
  url += op + '=' + encodeURIComponent(JSON.stringify(tr[op])) + '&' for op of tr
  try
    return await @fetch url
  catch
    return {}

P.src.doaj.issn = (issn) ->
  issn ?= @params.issn
  issn = issn.split(',') if typeof issn is 'string'
  r = await @src.doaj.journals 'bibjson.eissn.exact:"' + issn.join(' OR bibjson.eissn.exact:"') + '" OR bibjson.pissn.exact:"' + issn.join(' OR bibjson.pissn.exact:"') + '"'
  return if r.hits?.total then r.hits.hits[0]._source else undefined

P.src.doaj.doi = (doi) ->
  return @src.doaj.get 'doi:' + doi

P.src.doaj.title = (title) ->
  return @src.doaj.get 'title:"' + title.toLowerCase().replace(/(<([^>]+)>)/g,'').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ') + '"'`;

  // Europe PMC client
  // https://europepmc.org/RestfulWebService
  // https://www.ebi.ac.uk/europepmc/webservices/rest/search/
  // https://europepmc.org/Help#fieldsearch

// GET https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:10.1007/bf00197367&resulttype=core&format=json
  // default page is 1 and default pageSize is 25
  // resulttype lite is smaller, lacks so much metadata, no mesh, terms, etc
  // open_access:y added to query will return only open access articles, and they will have fulltext xml available at a link like the following:
  // https://www.ebi.ac.uk/europepmc/webservices/rest/PMC3257301/fullTextXML
  // can also use HAS_PDF:y to get back ones where we should expect to be able to get a pdf, but it is not clear if those are OA and available via eupmc
  // can ensure a DOI is available using HAS_DOI
  // can search publication date via FIRST_PDATE:1995-02-01 or FIRST_PDATE:[2000-10-14 TO 2010-11-15] to get range
var _last_ncbi, _ncbi_running,
  indexOf = [].indexOf;

P.src.epmc = {
  _index: true,
  _prefix: false,
  _key: 'id' // id will be the pubmed ID from the looks of it
};

P.src.epmc.notinepmc = {
  _index: true,
  _prefix: false,
  _key: 'id',
  _hide: true // keep track of ones we already looked up
};

P.src.epmc.search = async function(qrystr, from, size) {
  var ref, ref1, ref2, ref3, ref4, res, ret, url;
  if (qrystr == null) {
    qrystr = (ref = (ref1 = (ref2 = this.params.search) != null ? ref2 : this.params.epmc) != null ? ref1 : this.params.doi) != null ? ref : '';
  }
  if (qrystr.startsWith('10.') && !qrystr.includes(' ') && qrystr.split('/').length >= 2) {
    qrystr = 'DOI:' + qrystr;
  }
  if (typeof qrystr === 'string' && !qrystr.startsWith('PMCID:') && qrystr.toLowerCase().startsWith('pmc') && !qrystr.includes(' ')) {
    qrystr = 'PMCID:PMC' + qrystr.toLowerCase().replace('pmc', '');
  }
  if (typeof qrystr === 'number') {
    qrystr = 'PMCID:PMC' + qrystr;
  }
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + ' sort_date:y&resulttype=core&format=json';
  if (size != null) {
    url += '&pageSize=' + size; //can handle 1000, have not tried more, docs do not say
  }
  if (from != null) {
    url += '&cursorMark=' + from; // used to be a from pager, but now uses a cursor
  }
  ret = {};
  await this.sleep(150);
  res = (await this.fetch(url));
  ret.total = res.hitCount;
  ret.data = (ref3 = (ref4 = res.resultList) != null ? ref4.result : void 0) != null ? ref3 : [];
  ret.cursor = res.nextCursorMark;
  if (ret.data.length) {
    this.waitUntil(this.src.epmc(ret.data));
  }
  return ret;
};

P.src.epmc.doi = async function(ident, refresh) {
  var exists, ne, ref, res;
  if (!ident) {
    if (refresh == null) {
      refresh = this.refresh;
    }
  }
  if (ident == null) {
    ident = this.params.doi;
  }
  exists = (await this.src.epmc('doi:"' + ident + '"'));
  if (exists != null ? (ref = exists.hits) != null ? ref.total : void 0 : void 0) {
    return exists.hits.hits[0]._source;
  } else if (!refresh && (ne = (await this.src.epmc.notinepmc(ident)))) {

  } else {
    res = (await this.src.epmc.search('DOI:' + ident));
    if (res.total) {
      if (!res.data[0].doi) {
        res.data[0].doi = ident;
        this.waitUntil(this.src.epmc(res.data[0]));
      }
      return res.data[0];
    } else {
      await this.src.epmc.notinepmc({
        id: ident.replace(/\//g, '_'),
        doi: ident
      });
    }
  }
};

P.src.epmc.pmid = async function(ident, refresh) {
  var exists, ne, ref, res;
  if (!ident) {
    if (refresh == null) {
      refresh = this.refresh;
    }
  }
  if (ident == null) {
    ident = this.params.pmid;
  }
  exists = (await this.src.epmc('pmid:"' + ident + '"'));
  if (exists != null ? (ref = exists.hits) != null ? ref.total : void 0 : void 0) {
    return exists.hits.hits[0]._source;
  } else if (!refresh && (ne = (await this.src.epmc.notinepmc(ident)))) {

  } else {
    res = (await this.src.epmc.search('EXT_ID:' + ident + ' AND SRC:MED'));
    if (res.total) {
      return res.data[0];
    } else {
      await this.src.epmc.notinepmc({
        id: ident,
        pmid: ident
      });
    }
  }
};

P.src.epmc.pmc = async function(ident, refresh) {
  var exists, ne, ref, ref1, res;
  if (!ident) {
    if (refresh == null) {
      refresh = this.refresh;
    }
  }
  if (ident == null) {
    ident = (ref = this.params.pmc) != null ? ref : this.params.pmcid;
  }
  ident = 'PMC' + ident.toLowerCase().replace('pmc', '');
  exists = (await this.src.epmc('pmcid:"' + ident + '"'));
  if (exists != null ? (ref1 = exists.hits) != null ? ref1.total : void 0 : void 0) {
    return exists.hits.hits[0]._source;
  } else if (!refresh && (ne = (await this.src.epmc.notinepmc(ident)))) {

  } else {
    res = (await this.src.epmc.search('PMCID:' + ident));
    if (res.total) {
      return res.data[0];
    } else {
      await this.src.epmc.notinepmc({
        id: ident,
        pmcid: ident
      });
    }
  }
};

P.src.epmc.title = async function(title) {
  var exists, ref, res;
  if (title == null) {
    title = this.params.title;
  }
  try {
    title = title.toLowerCase().replace(/(<([^>]+)>)/g, '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
  } catch (error) {}
  exists = (await this.src.epmc('title:"' + title + '"'));
  if (exists != null ? (ref = exists.hits) != null ? ref.total : void 0 : void 0) {
    return exists.hits.hits[0]._source;
  } else {
    res = (await this.src.epmc.search('title:"' + title + '"'));
    if (res.total) {
      return res.data[0];
    } else {
      return void 0;
    }
  }
};

P.src.epmc.licence = async function(pmcid, rec, fulltext, refresh) {
  var lics, ref, ref1;
  if (!pmcid) {
    if (refresh == null) {
      refresh = this.refresh;
    }
  }
  if (pmcid == null) {
    pmcid = (ref = (ref1 = this.params.licence) != null ? ref1 : this.params.pmcid) != null ? ref : this.params.epmc;
  }
  if (pmcid) {
    pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc', '');
  }
  if (pmcid && (rec == null)) {
    rec = (await this.src.epmc.pmc(pmcid));
  }
  if (rec || fulltext) {
    if (((rec != null ? rec.calculated_licence : void 0) != null) && !refresh) {
      if (rec.calculated_licence.licence === 'not found') {
        return void 0;
      } else {
        return rec.calculated_licence;
      }
    } else {
      if (pmcid == null) {
        pmcid = rec != null ? rec.pmcid : void 0;
      }
      if ((rec != null ? rec.license : void 0) && typeof rec.license === 'string') {
        lics = {
          licence: rec.license,
          source: 'epmc_api'
        };
        if (lics.licence.startsWith('cc')) {
          lics.licence = lics.licence.replace(/ /g, '-');
        }
      } else {
        if (!fulltext && pmcid) {
          fulltext = (await this.src.epmc.xml(pmcid, rec));
        }
        if ((this.licence != null) && fulltext) {
          if (typeof fulltext === 'string' && fulltext.startsWith('<')) {
            lics = (await this.licence(void 0, fulltext, '<permissions>', '</permissions>'));
            if ((lics != null ? lics.licence : void 0) != null) {
              lics.source = 'epmc_xml_permissions';
            }
          }
          if ((lics != null ? lics.licence : void 0) == null) {
            lics = (await this.licence(void 0, fulltext));
            if ((lics != null ? lics.licence : void 0) != null) {
              lics.source = 'epmc_xml_outside_permissions';
            }
          }
        }
        if (((lics != null ? lics.licence : void 0) == null) && typeof fulltext === 'string' && fulltext.includes('<permissions>')) {
          lics = {
            licence: 'non-standard-licence',
            source: 'epmc_xml_permissions'
          };
        }
      }
    }
    
    //if pmcid and @licence? and (not lics?.licence? or lics?.licence is 'non-standard-licence')
    //  await @sleep 1000
    //  url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace 'pmc', ''
    //  if pg = await @puppet url
    //    try lics = await @licence undefined, pg
    //    lics.source = 'epmc_html' if lics?.licence?
    if ((lics != null ? lics.licence : void 0) != null) {
      rec.calculated_licence = lics;
      await this.src.epmc(rec.id, rec);
      return lics;
    } else {
      rec.calculated_licence = {
        licence: 'not found'
      };
      await this.src.epmc(rec.id, rec);
    }
  }
};

_last_ncbi = Date.now();

_ncbi_running = 0;

P.src.epmc.xml = async function(pmcid, rec) {
  var ft, ncdl, ref, ref1, url;
  if (pmcid == null) {
    pmcid = (ref = (ref1 = this.params.xml) != null ? ref1 : this.params.pmcid) != null ? ref : this.params.epmc;
  }
  if (pmcid) {
    pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc', '');
  }
  if (pmcid) {
    try {
      ft = (await fs.readFile('/home/cloo/static/epmc/fulltext/' + pmcid + '.xml'));
      return ft.toString();
    } catch (error) {
      if (rec == null) {
        rec = (await this.src.epmc.pmc(pmcid));
      }
      if (!(rec != null ? rec.no_ft : void 0)) {
        ncdl = Date.now() - _last_ncbi;
        while (ncdl < 500 || _ncbi_running >= 2) { // should be able to hit 3r/s although it's possible we call from other workers on same server. This will have to do for now
          await this.sleep(500 - ncdl);
          ncdl = Date.now() - _last_ncbi;
        }
        _last_ncbi = Date.now();
        _ncbi_running += 1;
        // without sleep (and at 150, 300, 400) threw rate limit error on ncbi and ebi - this does not guarantee it because other calls could be made, but is a quick fix
        // try ncbi first as it is faster but it does not have everything in epmc - however when present the xml files are the same
        url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=' + pmcid;
        ft = (await this.fetch(url));
        _ncbi_running -= 1;
        if ((typeof ft !== 'string' || !ft.length) && (rec != null)) { // if it is in epmc, can try getting from there instead
          url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML';
          ft = (await this.fetch(url));
        }
        if (typeof ft === 'string' && ft.length) {
          try {
            await fs.writeFile('/home/cloo/static/epmc/fulltext/' + pmcid + '.xml', ft);
          } catch (error) {}
          return ft;
        } else if (rec != null) {
          rec.no_ft = true;
          await this.src.epmc(rec.id, rec);
        }
      }
    }
  }
};

P.src.epmc.fulltext = async function(pmcid) { // check fulltext exists in epmc explicitly
  var exists, ref, ref1;
  if (pmcid == null) {
    pmcid = (ref = (ref1 = this.params.fulltext) != null ? ref1 : this.params.pmcid) != null ? ref : this.params.epmc;
  }
  if (pmcid) {
    await this.sleep(150);
    exists = (await this.fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML', {
      method: 'HEAD'
    }));
    return (exists != null ? exists.status : void 0) === 200;
  } else {

  }
};

P.src.epmc.aam = async function(pmcid, rec, fulltext) {
  var pg, ref, ref1, s1, s2, s3, s4, url;
  if (pmcid == null) {
    pmcid = (ref = (ref1 = this.params.aam) != null ? ref1 : this.params.pmcid) != null ? ref : this.params.epmc;
  }
  if (typeof fulltext === 'string' && fulltext.includes('pub-id-type=\'manuscript\'') && fulltext.includes('pub-id-type="manuscript"')) {
    return {
      aam: true,
      info: 'fulltext'
    };
  } else {
    try {
      if (pmcid && !rec) {
        // if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
        rec = (await this.src.epmc.pmc(pmcid));
      }
    } catch (error) {}
    if (pmcid == null) {
      pmcid = rec != null ? rec.pmcid : void 0;
    }
    if (pmcid) {
      fulltext = (await this.src.epmc.xml(pmcid, rec));
      if (typeof fulltext === 'string' && fulltext.includes('pub-id-type=\'manuscript\'') && fulltext.includes('pub-id-type="manuscript"')) {
        return {
          aam: true,
          info: 'fulltext'
        };
      } else {
        await this.sleep(1000);
        url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc', '');
        //pg = await @puppet url
        pg = (await this.fetch(url));
        if (!pg) {
          return {
            aam: false,
            info: 'not in EPMC (404)'
          };
        } else if (typeof pg === 'string') {
          s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal';
          s2 = 'Author manuscript; available in PMC';
          s3 = 'logo-nihpa.gif';
          s4 = 'logo-wtpa2.gif';
          if (pg.includes(s1) || pg.includes(s2) || pg.includes(s3) || pg.includes(s4)) {
            return {
              aam: true,
              info: 'splashpage'
            };
          } else {
            return {
              aam: false,
              info: 'EPMC splashpage checked, no indicator found'
            };
          }
        } else if (pg != null) {
          return {
            info: 'EPMC was accessed but aam could not be decided from what was returned' //if typeof pg is 'object' and pg.status is 403
          };
        } else {
          return {
            info: 'EPMC may be blocking access, AAM status unknown'
          };
        }
      }
    }
  }
  return {
    aam: false,
    info: ''
  };
};

P.src.epmc.statement = async function(pmcid, rec) {
  var i, len, ps, psl, ref, ref1, ref2, ref3, ref4, statement, strs, xml;
  if (pmcid == null) {
    pmcid = (ref = (ref1 = (ref2 = (ref3 = this.params.statement) != null ? ref3 : this.params.pmc) != null ? ref2 : this.params.pmcid) != null ? ref1 : this.params.PMC) != null ? ref : this.params.PMCID;
  }
  if (pmcid) {
    pmcid = 'PMC' + (pmcid + '').toLowerCase().replace('pmc', '');
    if (xml = (await this.src.epmc.xml(pmcid, rec))) {
      // because of xml parsing issues with embedded html in pmc xml, just regex it out if present
      // pubmed data does not hold corresponding statements to pmc, but the pmc records from ncbi do contain them as they are the same as fulltext records from epmc
      // see <notes notes-type="data-availability"> in
      // https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
      // or <custom-meta id="data-availability"> in 
      // https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9009769
      // which also has it in "notes" but with no type and no other content <notes> but a <title> of Data Availability
      // catches most of https://www.ncbi.nlm.nih.gov/books/NBK541158/
      statement = '';
      strs = [];
      if (xml.includes('type="data-availability">')) {
        statement = xml.split('type="data-availability">')[1].split('</sec>')[0].split('</notes>')[0];
        if (statement.includes('<title>')) {
          statement = statement.split('<title>').pop().split('</title')[0];
        }
      } else if (xml.includes('id="data-availability"')) {
        statement = xml.split('id="data-availability"')[1];
        if (statement.includes('meta-value')) {
          statement = statement.split('meta-value>')[1].split(',')[0];
        }
      }
      if (!statement && xml.includes('<notes>')) {
        ref4 = xml.split('<notes>');
        for (i = 0, len = ref4.length; i < len; i++) {
          ps = ref4[i];
          psl = ps.toLowerCase();
          if (psl.includes('data availability') || psl.includes('data accessibility') || psl.includes('supporting data')) {
            if (ps.includes('</title>')) {
              statement = ps.split('</title>')[1];
            }
            statement = statement.split('</notes>')[0];
            break;
          }
        }
      }
      // if still no statement could look in other fields, but they mostly appear in notes and are of more certain quality when they do
      //statement = '' if statement.includes '<def-item' # seem to be more junk in these
      if (statement) {
        if (statement.includes('<list-item')) {
          statement = statement.split('<list-item').pop().split('>').pop();
        }
        // most examples so far are a statement paragraph with zero or one url...
        statement = statement.replace(/<[ap].*?>/gi, '').replace(/<\/[ap]>/gi, '').replace(/<xref.*?>/gi, '').replace(/<\/xref>/gi, '').replace(/<ext.*?>/gi, '').replace(/<\/ext.*?>/gi, '').replace(/<br>/gi, '').replace(/\n/g, '').split('</')[0].trim();
        if (statement.length > 10) { // hard to be a good statement if shorter than this
          return statement;
        }
      }
    }
  }
};

P.src.epmc.dass = async function() {
  var daclose, dasclose, ex, fl, ft, ftl, had, matches, max, post, pre, prep, ps, rec, ref, ref1, res, saysavail, saysdata, saysstate;
  // what about code availability statements without data availability e.g. PMC6198754
  max = (ref = this.params.dass) != null ? ref : 1;
  res = [];
  had = 0;
  fl = 0;
  prep = 0;
  saysdata = 0;
  saysavail = 0;
  saysstate = 0;
  daclose = 0;
  dasclose = 0;
  ref1 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', 'PMCID:PMC9722710 AND orgs:Melinda', {
    include: ['PMCID']
  });
  //, sort: 'PMCID': 'asc'
  for await (rec of ref1) {
    if (res.length === max) {
      break;
    }
    try {
      ft = ((await fs.readFile('/home/cloo/static/epmc/fulltext/' + rec.PMCID + '.xml'))).toString();
    } catch (error) {}
    if (ft) {
      fl += 1;
      ex = {
        pmcid: rec.PMCID // catch multiple relevant statements like in PMC8012878, or PMC9722710 where there are sec within sec all part of the statement (and after an earlier false data match)
      };
      ftl = ft.toLowerCase();
      if (ftl.includes('>data') || ftl.includes('"data') || ftl.includes(' data')) {
        saysdata += 1;
        if (ftl.includes('availab')) {
          saysavail += 1;
          matches = ftl.match(/.{100}[>" ](data|availab).{1,50}(availab|data).{200}/g);
          if ((matches != null) && matches.length && matches[0].includes('data') && matches[0].includes('availab')) {
            daclose += 1;
            ex.close = matches[0];
            ex.index = matches.index;
          }
          if (ftl.includes('statement')) {
            saysstate += 1;
            matches = ftl.match(/.{100}[>" ](data|availab|statement).{1,50}(availab|data|statement).{1,50}(availab|data|statement).{200}/g);
            if ((matches != null) && matches.length && smatches[0].includes('data') && matches[0].includes('availab') && matches[0].includes('statement')) {
              dasclose += 1;
              ex.closer = matches[0];
              ex.index = matches.index;
            }
          }
        }
      }
      if (ft.includes('"data')) {
        [pre, post] = ft.split('"data');
        ex.pre = pre.slice(-100);
        ex.post = post.slice(0, 1000);
        ex.tag = pre.split('<').pop().split('>')[0].split(' ')[0];
        post = post.split('</' + ex.tag)[0];
        post = post.split(/\>(.*)/s)[1];
        if (post.split('</').length > 2) {
          post = post.replace('</', ': </').replace('::', ':').replace('.:', ':');
        }
        post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace(/(<([^>]+)>)/ig, '');
        if (post.length > 20 && post.length < 1000 && (ex.pre + post).toLowerCase().includes('availab') && (ex.pre + post).toLowerCase().includes('data')) {
          ex.das = ((await this.decode(post.trim()))).replace(/"/g, '').replace(/\s+/g, ' ');
        }
      }
      if (!ex.das && (ft.includes('>Data') || ft.includes('>Availab') || ft.includes('>data'))) {
        [pre, post] = ft.split(ft.includes('>Data') ? '>Data' : ft.includes('>Availab') ? '>Availab' : '>data');
        ex.pre = pre.slice(-100);
        ex.post = post.slice(0, 1000);
        post = (post.startsWith('il') || post.startsWith('l') ? 'Availab' : 'Data ') + post;
        ex.tag = pre.split('<').pop().split(' ')[0];
        if (post.indexOf('</' + ex.tag) < 40) {
          post = post.replace('</' + ex.tag + '>', ': ').replace('::', ':').replace('.:', ':');
          ps = pre.split('<');
          ex.tag = ps[ps.length - 2].split(' ')[0];
        }
        post = post.split('</' + ex.tag)[0];
        post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace(/(<([^>]+)>)/ig, '');
        if (post.length > 20 && post.length < 1000 && (ex.pre + post).toLowerCase().includes('availab') && (ex.pre + post).toLowerCase().includes('data')) {
          ex.das = ((await this.decode(post.trim()))).replace(/"/g, '').replace(/\s+/g, ' ');
        }
      }
      res.push(ex); //pmcid: ex.pmcid, das: ex.das) #if ex.das
      if (ex.das) {
        had += 1;
      }
      if (ex.pre && ex.post) {
        prep += 1;
      }
    }
  }
  return {
    total: res.length,
    files: fl,
    data: saysdata,
    available: saysavail,
    statement: saysstate,
    close: daclose,
    closer: dasclose,
    index: -1,
    prep: prep,
    das: had,
    records: res
  };
};

P.src.epmc.das = async function(pmcid, verbose) { // restrict to report/works records if pmcid is directly provided?
  var clean, ex, ft, ftl, i, len, matches, max, nt, part, post, pre, ps, rec, ref, ref1, ref2, res, split, splits, splitter, tag;
  max = (ref = pmcid != null ? pmcid : this.params.das) != null ? ref : 100; // ['PMC9722710', 'PMC8012878', 'PMC6198754'] # multiples PMC8012878. code? PMC6198754. Another example for something? was PMC9682356
  if (typeof max === 'string') {
    max = max.split(',');
  }
  if (verbose == null) {
    verbose = this.params.verbose;
  }
  res = {
    total: 0,
    files: 0,
    data: 0,
    available: 0,
    statement: 0,
    close: 0,
    closer: 0,
    prep: 0,
    das: 0,
    records: []
  };
  ref1 = this.index._for('paradigm_' + (this.S.dev ? 'b_' : '') + 'report_works', '(PMCID:' + (typeof max === 'number' ? '*' : max.join(' OR PMCID:')) + ') AND orgs:Melinda', {
    include: ['PMCID'],
    sort: {
      'PMCID.keyword': 'asc'
    }
  });
  for await (rec of ref1) {
    if (typeof max === 'number' && res.records.length === max) {
      break;
    }
    try {
      ft = ((await fs.readFile('/home/cloo/static/epmc/fulltext/' + rec.PMCID + '.xml'))).toString();
    } catch (error) {}
    if (ft) {
      res.files += 1;
      ex = {
        pmcid: rec.PMCID,
        file: 'https://static.oa.works/epmc/fulltext/' + rec.PMCID + '.xml',
        splits: [],
        tag: [],
        pre: [],
        post: [],
        das: []
      };
      ftl = ft.toLowerCase();
      if (ftl.includes('>data') || ftl.includes('"data') || ftl.includes(' data')) {
        res.data += 1;
        if (ftl.includes('availab')) {
          res.available += 1;
          matches = ftl.match(/.{100}[>" ](data|availab).{1,50}(availab|data).{200}/g);
          if ((matches != null) && matches.length && matches[0].includes('data') && matches[0].includes('availab')) {
            res.close += 1;
            ex.close = matches;
          }
          if (ftl.includes('statement')) {
            res.statement += 1;
            matches = ftl.match(/.{100}[>" ](data|availab|statement).{1,50}(availab|data|statement).{1,50}(availab|data|statement).{200}/g);
            if ((matches != null) && matches.length && matches[0].includes('data') && matches[0].includes('availab') && matches[0].includes('statement')) {
              res.closer += 1;
              ex.closer = matches;
            }
          }
        }
      }
      ref2 = ['"data', '>Data', '>Availab', '>data'];
      for (i = 0, len = ref2.length; i < len; i++) {
        split = ref2[i];
        if (ft.includes(split)) {
          ex.splits.push(split);
          pre = '';
          splits = ft.split(split);
          while (part = splits.shift()) {
            if (!pre) {
              pre = part;
            } else {
              ex.pre.push(pre.slice(-1000));
              tag = pre.split('<').pop().split('>')[0].split(' ')[0];
              post = split.startsWith('"') ? part.split(/\>(.*)/s)[1] : (part.startsWith('il') || part.startsWith('l') ? 'Availab' : 'Data') + part;
              ex.post.push(post.slice(0, 1000));
              if (post.includes('</' + tag) && post.indexOf('</' + tag) < 40) {
                ps = pre.split('<');
                nt = ps[ps.length - 2].split('>')[0].split(' ')[0];
                if (!nt.startsWith('/')) {
                  //post = post.replace('</' + tag + '>', ': ').replace('::', ':').replace('.:', ':')
                  tag = nt;
                }
              }
              ex.tag.push(tag);
              splitter = '\n' + pre.split('<' + tag)[0].split('\n').pop().split('<')[0] + '</' + tag;
              if (post.split('</' + tag)[0].includes('\n')) {
                while (!post.includes(splitter) && splits[0]) {
                  post += (split.startsWith('>') ? '>' : '') + (splits[0].startsWith('il') || splits[0].startsWith('l') ? 'Availab' : 'Data') + splits.shift();
                }
              }
              post = post.split(splitter)[0];
              //post = post.split(/\>(.*)/s)[1]
              //post = post.replace('</', ': </').replace('::', ':').replace('.:', ':') if post.split('</').length > 2
              post = post.replace(/\n/g, ' ').replace(/\s+/g, ' ').replace(/(<([^>]+)>)/ig, '');
              if (post.length > 20 && post.length < 3000 && (pre + post).toLowerCase().includes('availab') && (pre + post).toLowerCase().includes('data')) {
                clean = ((await this.decode(post.trim()))).replace(/"/g, '').replace(/\s+/g, ' ');
                if (indexOf.call(ex.das, clean) < 0) {
                  ex.das.push(clean);
                }
                delete ex.close;
                delete ex.closer;
              }
              pre = '';
            }
          }
        }
      }
      res.records.push(verbose === false ? {
        file: ex.file,
        das: ex.das
      } : ex);
      if (ex.das.length) {
        res.das += 1;
      }
      if (ex.pre && ex.post) {
        res.prep += 1;
      }
    }
  }
  res.total = res.records.length;
  if (verbose === false) {
    res = {
      total: res.total,
      das: res.das,
      records: res.records
    };
  }
  if (verbose === false && res.total === 1) {
    res = (res.records.length && res.records[0].das.length ? res.records[0].das[0] : false);
  }
  return res;
};

var base;

if ((base = S.src).google == null) {
  base.google = {};
}

try {
  S.src.google.secrets = JSON.parse(SECRETS_GOOGLE);
} catch (error) {}

// https://developers.google.com/custom-search/json-api/v1/overview#Pricing
// note technically meant to be targeted to a site but can do full search on free tier
// free tier only up to 100 queries a day. After that, $5 per 1000, up to 10k
// has to come from registered IP address
P.src.google = async function(q, id, key) {
  var ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, url;
  if (q == null) {
    q = (ref = this != null ? (ref1 = this.params) != null ? ref1.q : void 0 : void 0) != null ? ref : this != null ? (ref2 = this.params) != null ? ref2.google : void 0 : void 0;
  }
  if (id == null) {
    id = (ref3 = this.S.src.google) != null ? (ref4 = ref3.secrets) != null ? (ref5 = ref4.search) != null ? ref5.id : void 0 : void 0 : void 0;
  }
  if (key == null) {
    key = (ref6 = this.S.src.google) != null ? (ref7 = ref6.secrets) != null ? (ref8 = ref7.search) != null ? ref8.key : void 0 : void 0 : void 0;
  }
  if (q && id && key) {
    url = 'https://www.googleapis.com/customsearch/v1?key=' + key + '&cx=' + id + '&q=' + q;
    return (await this.fetch(url));
  } else {
    return {};
  }
};

P.src.google.sheets = async function(opts) {
  var g, h, hd, headers, i, j, l, len, len1, ref, ref1, ref2, ref3, ref4, ref5, ref6, sid, toprow, url, val, values;
  // expects a google sheet ID or a URL to a google sheets feed in json format
  // NOTE the sheet must be published for this to work, should have the data in Sheet1, and should have columns of data with key names in row 1
  // https://support.google.com/docs/thread/121088347/retrieving-data-from-sheets-results-in-404-error-50-of-the-time
  if (opts == null) {
    opts = this.copy(this.params);
  }
  if (typeof opts === 'string') {
    opts = {
      sheetid: opts
    };
  }
  if (((opts.sheets != null) || (opts.sheet != null)) && (opts.sheetid == null)) {
    opts.sheetid = (ref = opts.sheet) != null ? ref : opts.sheets;
    delete opts.sheet;
    delete opts.sheets;
  }
  if (!opts.sheetid) {
    return [];
  } else if (opts.sheetid.startsWith('http') && opts.sheetid.includes('sheets.googleapis.com/v4/')) {
    url = opts.sheetid;
  } else {
    if (opts.sheetid.includes('/spreadsheets/')) {
      sid = opts.sheetid.replace('/spreadsheets/d/', '/spreadsheets/').split('/spreadsheets/')[1].split('/')[0];
      if (!opts.sheet && opts.sheetid.includes('/values/')) {
        opts.sheet = opts.sheetid.split('/values/')[1].split('?')[0].split('#')[0];
      }
      opts.sheetid = sid;
    } else if (opts.sheetid.split('/').length === 2) {
      [opts.sheetid, opts.sheet] = opts.sheetid.split('/');
    }
    if (opts.sheet == null) {
      opts.sheet = 'Sheet1'; // needs to be the name of a sheet within the sheet
    }
    // also possible to add sheet ranges in here, and use to update sheet if not just a public one being read (see below for a start on using full v4 API)
    // an API key is now NECESSARY even though this is still only for sheets that are published public. Further auth required to do more.
    url = 'https://sheets.googleapis.com/v4/spreadsheets/' + opts.sheetid + '/values/' + opts.sheet + '?alt=json&key=' + ((ref1 = (ref2 = this.S.src.google) != null ? (ref3 = ref2.secrets) != null ? ref3.serverkey : void 0 : void 0) != null ? ref1 : (ref4 = this.S.src.google) != null ? (ref5 = ref4.secrets) != null ? ref5.apikey : void 0 : void 0);
  }
  g = (await this.fetch(url, {
    headers: {
      'Cache-Control': 'no-cache'
    }
  }));
  if (opts.values === false) {
    return g;
  } else if (opts.headers === false) {
    return g.values;
  } else {
    if (Array.isArray(opts.headers)) {
      headers = opts.headers;
    } else {
      headers = [];
      if (g.values != null) {
        toprow = g.values.shift(); // NOTE there is NO WAY to identify column headers any more it seems, certainly not from this response format. Just pop them off the values list
        for (i = 0, len = toprow.length; i < len; i++) {
          hd = toprow[i];
          try {
            hd = hd.trim();
          } catch (error) {}
          headers.push(hd); //.toLowerCase().replace /[^a-z0-9]/g, ''
        }
      }
    }
    values = [];
    ref6 = g.values;
    for (j = 0, len1 = ref6.length; j < len1; j++) {
      l = ref6[j];
      val = {};
      for (h in headers) {
        try {
          //try l[h] = l[h].trim()
          //try
          //  l[h] = true if l[h].toLowerCase() is 'true'
          //  l[h] = false if l[h].toLowerCase() is 'false'
          //try
          //  if ((l[h].startsWith('[') and l[h].endsWith(']')) or (l[h].startsWith('{') and l[h].endsWith('}')))
          //    try l[h] = JSON.parse l[h]
          //if opts.dot isnt false and typeof l[h] isnt 'object' and headers[h].includes '.'
          //  try
          //    await @dot val, headers[h], l[h]
          //  catch
          //    try val[headers[h]] = l[h]
          //else
          val[headers[h]] = l[h];
        } catch (error) {}
      }
      if (JSON.stringify(val) !== '{}') {
        values.push(val);
      }
    }
    return values;
  }
};

P.src.google.sheets._bg = true;

P.src.google.sheets._log = false;

var base;

if ((base = S.src).microsoft == null) {
  base.microsoft = {};
}

try {
  S.src.microsoft = JSON.parse(SECRETS_MICROSOFT);
} catch (error) {}

P.src.microsoft = {};

// https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
// annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
// and it seems the bing UI is sometimes more accurate
P.src.microsoft.bing = async function(q, key, market, count, cache) {
  var ref, ref1, ref10, ref11, ref12, ref13, ref14, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, url;
  if (q == null) {
    q = (ref = (ref1 = this != null ? (ref2 = this.params) != null ? ref2.bing : void 0 : void 0) != null ? ref1 : this != null ? (ref3 = this.params) != null ? ref3.q : void 0 : void 0) != null ? ref : this != null ? (ref4 = this.params) != null ? ref4.query : void 0 : void 0;
  }
  if (key == null) {
    key = (ref5 = this != null ? (ref6 = this.params) != null ? ref6.key : void 0 : void 0) != null ? ref5 : (ref7 = S.src.microsoft.bing) != null ? ref7.key : void 0;
  }
  if (market == null) {
    market = (ref8 = this != null ? (ref9 = this.params) != null ? ref9.market : void 0 : void 0) != null ? ref8 : 'en-GB';
  }
  if (count == null) {
    count = (ref10 = this != null ? (ref11 = this.params) != null ? ref11.count : void 0 : void 0) != null ? ref10 : 20;
  }
  if (cache == null) {
    cache = (ref12 = this != null ? (ref13 = this.params) != null ? ref13.cache : void 0 : void 0) != null ? ref12 : 259200; // cache for 3 days
  }
  if ((q != null) && (key != null)) {
    url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?';
    if (market) {
      url += 'mkt=' + market + '&';
    }
    if (count) {
      url += 'count=' + count + '&';
    }
    url += 'q=' + q;
    res = (await this.fetch(url, {
      headers: {
        'Ocp-Apim-Subscription-Key': key
      },
      cache: cache
    }));
    if (res != null ? (ref14 = res.webPages) != null ? ref14.value : void 0 : void 0) {
      return {
        total: res.webPages.totalEstimatedMatches,
        data: res.webPages.value
      };
    }
  }
  return {
    total: 0,
    data: []
  };
};

P.src.microsoft.bing._auth = '@oa.works';

`P.src.microsoft.graph = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.journal = _prefix: false, _index: true
P.src.microsoft.graph.author = _prefix: false, _index: settings: number_of_shards: 9
P.src.microsoft.graph.affiliation = _prefix: false, _index: true
P.src.microsoft.graph.urls = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.abstract = _prefix: false, _index: settings: number_of_shards: 6
P.src.microsoft.graph.relation = _prefix: false, _index: settings: number_of_shards: 12

P.src.microsoft.graph.paper = (q) -> # can be a search or a record to get urls and relations for
  url_source_types = # defined by MAG
    '1': 'html'
    '2': 'text'
    '3': 'pdf'
    '4': 'doc'
    '5': 'ppt'
    '6': 'xls'
    '8': 'rtf'
    '12': 'xml'
    '13': 'rss'
    '20': 'swf'
    '27': 'ics'
    '31': 'pub'
    '33': 'ods'
    '34': 'odp'
    '35': 'odt'
    '36': 'zip'
    '40': 'mp3'

  if @params.title and not q
    return @src.microsoft.graph.paper.title()

  q = @params.q ? @params.paper ? @params
  res = if typeof q is 'object' and q.PaperId and q.Rank then q else await @src.microsoft.graph q
  for r in (res?.hits?.hits ? (if res then [res] else []))
    #if ma = await @src.microsoft.graph.abstract r._source.PaperId, 1
    #  r._source.abstract = ma
    try
      urlres = await @src.microsoft.graph.urls 'PaperId:"' + r._source.PaperId + '"' # don't bother for-looping these because result size should be low, and saves on creating and deleting a scrol context for every one
      for ur in urlres.hits.hits
        r._source.url ?= []
        puo = url: ur._source.SourceUrl, language: ur._source.LanguageCode
        try puo.type = url_source_types[ur._source.SourceType.toString()]
        r._source.url.push puo
    try
      rres = await @src.microsoft.graph.relation 'PaperId:"' + r._source.PaperId + '"', 100 # 100 authors should be enough...
      for rr in rres.hits.hits
        if rr._source.AuthorId # which it seems they all do, along with OriginalAuthor and OriginalAffiliation
          r._source.author ?= []
          r._source.author.push name: rr._source.OriginalAuthor, sequence: rr._source.AuthorSequenceNumber, id: rr._source.AuthorId, affiliation: {name: rr._source.OriginalAffiliation, id: rr._source.AffiliationId}
    
  return res
  

P.src.microsoft.graph.title = (q) ->
  q ?= @params.title ? @params.q
  if typeof q is 'string'
    title = q.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_\`~()]/g,' ').replace(/\s{2,}/g,' ').trim() # MAG PaperTitle is lowercased. OriginalTitle isnt
    res = await @src.microsoft.graph 'PaperTitle:"' + title + '"', 1
    res = res.hits.hits[0]?._source if res?.hits?.hits
    if res?.PaperTitle
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_\`~()]/g,' ').replace(/\s{2,}/g,' ').trim()
      lvs = await @levenshtein title, rt, false
      longest = if lvs.length.a > lvs.length.b then lvs.length.a else lvs.length.b
      if lvs.distance < 2 or longest/lvs.distance > 10
        return @src.microsoft.graph.paper res
  return




# https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
# We used to get files via MS Azure dump and run an import script. Have to manually go to 
# Azure, use storage explorer to find the most recent blob container, select the file(s)
# to download, right click and select shared access signature, create it, copy it, and download that.
# THEN DELETE THE BLOB BECAUSE THEY CHARGE US FOR EVERY CREATION, EVERY DOWNLOAD, AND STORAGE TIME FOR AS LONG AS IT EXISTS
# but now the service has been discontinued. Maybe there will be a replacement in future

P.src.microsoft.load = (kinds) ->
  howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going...

  keys =
    #journal: ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    #affiliation: ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate']
    #author: ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate']
    #relation: ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
    #abstract: ['PaperId', 'Abstract']
    #urls: ['PaperId', 'SourceType', 'SourceUrl', 'LanguageCode']
    paper: ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate']

  kinds ?= if @params.load then @params.load.split(',') else if @params.kinds then @params.kinds.split(',') else @keys keys

  # totals: 49027 journals, 26997 affiliations, 269880467 authors, 699632917 relations, 429637001 urls, 145551658 abstracts (in 2 files), 259102074 papers
  # paper URLs PaperId is supposedly a Primary Key but there are clearly many more of them than Papers...
  # of other files not listed here yet: 1726140322 paper references
  # of about 49k journals about 9 are dups, 37k have ISSN. 32k were already known from other soruces. Of about 250m papers, about 99m have DOIs
  infolder = @S.directory + '/import/mag/2021-04-26/' # where the lines should be read from
  lastfile = @S.directory + '/import/mag/last' # prefix of where to record the ID of the last item read from the kind of file
  
  total = 0
  blanks = 0
  done = not @params.parallel
  ds = {}
  
  paper_journal_count = 0
  paper_journal_lookups = {} # store these in memory when loading papers as they're looked up because there aren't many and it will work out faster than searching every time
  url_source_types = # defined by MAG
    '1': 'html'
    '2': 'text'
    '3': 'pdf'
    '4': 'doc'
    '5': 'ppt'
    '6': 'xls'
    '8': 'rtf'
    '12': 'xml'
    '13': 'rss'
    '20': 'swf'
    '27': 'ics'
    '31': 'pub'
    '33': 'ods'
    '34': 'odp'
    '35': 'odt'
    '36': 'zip'
    '40': 'mp3'

  _loadkind = (kind) =>
    console.log 'MAG loading', kind
    batchsize = if kind in ['abstract'] then 20000 else if kind in ['relation'] then 75000 else if kind in ['urls'] then 100000 else 50000 # how many records to batch upload at a time
    batch = []
    kindlastfile = lastfile + '_' + kind
    kindtotal = 0
    try lastrecord = parseInt((await fs.readFile kindlastfile).toString().split(' ')[0]) if not @refresh

    if lastrecord isnt 'DONE'
      if not lastrecord
        if kind is 'paper'
          await @src.microsoft.graph ''
        else
          await @src.microsoft.graph[kind] ''
      
      infile = (if kind in ['urls'] then infolder.replace('2021-04-26/', '') else infolder) + (if kind is 'relation' then 'PaperAuthorAffiliations.txt' else (if kind in ['urls'] then 'Paper' else '') + kind.substr(0,1).toUpperCase() + kind.substr(1) + (if kind in ['urls'] then '' else 's') + '.txt')

      for await line from readline.createInterface input: fs.createReadStream infile
        kindtotal += 1
        break if total is howmany
        vals = line.split '\t'
        try console.log(kind, 'waiting', kindtotal, lastrecord) if lastrecord and not (kindtotal/100000).toString().includes '.'
        if not lastrecord or kindtotal is lastrecord or parseInt(vals[0]) is lastrecord
          lastrecord = undefined
          total += 1
          kc = 0
          obj = {}
          if kind not in ['relation', 'urls']
            obj._id = vals[0]
            try obj._id = obj._id.trim()
            delete obj._id if not obj._id # there appear to be some blank lines so skip those
          if obj._id or kind in ['relation', 'urls']
            if kind is 'abstract'
              try
                obj.PaperId = parseInt vals[0]
                ind = JSON.parse vals[1]
                al = []
                al.push('') while al.length < ind.IndexLength
                for k in ind.InvertedIndex
                  for p in ind.InvertedIndex[k]
                    al[p] = k
                obj.Abstract = al.join(' ').replace /\n/g, ' '
            else
              for key in keys[kind]
                vs = vals[kc]
                try vs.trim()
                obj[key] = vs if vs and key not in ['NormalizedName']
                if key in ['Rank', 'AuthorSequenceNumber', 'Year', 'EstimatedCitation', 'FamilyRank', 'SourceType'] or key.endsWith('Count') or key.endsWith 'Id'
                  try
                    psd = parseInt obj[key]
                    obj[key] = psd if not isNaN psd
                kc += 1
            if kind is 'paper'
              if obj.JournalId
                try
                  js = obj.JournalId.toString()
                  if jrnl = paper_journal_lookups[js]
                    obj.journal = title: jrnl.DisplayName, ISSN: jrnl.Issn.split(','), url: jrnl.Webpage, id: obj.JournalId
                  else if jrnl = await @src.microsoft.graph.journal js
                    paper_journal_lookups[js] = jrnl
                    paper_journal_count += 1
                    console.log paper_journal_count
                    obj.journal = title: jrnl.DisplayName, ISSN: jrnl.Issn.split(','), url: jrnl.Webpage

          if JSON.stringify(obj) isnt '{}' # readline MAG author dump somehow managed to cause blank rows even though they couldn't be found in the file, so skip empty records
            batch.push obj
          else
            blanks += 1
  
        if batch.length is batchsize
          console.log kind, total, kindtotal, blanks
          if kind is 'paper'
            await @src.microsoft.graph batch
          else
            batched = await @src.microsoft.graph[kind] batch
            console.log 'batch returned', batched # should be the count of how many were successfully saved
          await fs.writeFile kindlastfile, kindtotal + ' ' + vals[0]
          batch = []
  
      if batch.length
        if kind is 'paper'
          await @src.microsoft.graph batch 
        else
          await @src.microsoft.graph[kind] batch
      await fs.writeFile kindlastfile, 'DONE'
    ds[k] = true

  for k in kinds
    if @params.parallel
      if k isnt 'paper'
        ds[k] = false
        _loadkind k
    else
      await _loadkind k

  while not done
    done = true
    for d of ds
      done = false if ds[d] is false
    if done and 'paper' in kinds
      await _loadkind 'paper'
    await @sleep 1000

  console.log total, blanks
  return total

P.src.microsoft.load._bg = true
P.src.microsoft.load._async = true
P.src.microsoft.load._auth = 'root'`;

var base;

if ((base = S.src).oadoi == null) {
  base.oadoi = {};
}

try {
  S.src.oadoi = JSON.parse(SECRETS_OADOI);
} catch (error) {}

`P.src.oadoi = (doi) ->
doi ?= @params?.oadoi ? @params?.doi
if typeof doi is 'string' and doi.startsWith '10.'
  await @sleep 900
  url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to
  return @fetch url
else
  return`;

P.src.oadoi = {
  _index: {
    settings: {
      number_of_shards: 15
    }
  }
};

P.src.oadoi._key = 'doi';

P.src.oadoi._prefix = false;

P.src.oadoi.search = async function(doi) {
  var ref, ref1, ref2, ref3, ref4, url;
  if (doi == null) {
    doi = (ref = (ref1 = (ref2 = this.params) != null ? ref2.oadoi : void 0) != null ? ref1 : (ref3 = this.params) != null ? ref3.doi : void 0) != null ? ref : (ref4 = this.params) != null ? ref4.search : void 0;
  }
  if (typeof doi === 'string' && doi.startsWith('10.')) {
    await this.sleep(900);
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to;
    return this.fetch(url);
  } else {

  }
};

P.src.oadoi.hybrid = async function(issns) {
  var closed, hybrid, q, ref, ref1, ref2;
  // there is a concern OADOI sometimes says a journal is closed on a particular 
  // record when it is actually a hybrid. So check if some records for 
  // a given journal are hybrid, and if so the whole journal is hybrid.
  if (issns == null) {
    issns = (ref = (ref1 = this.params.hybrid) != null ? ref1 : this.params.issn) != null ? ref : this.params.issns;
  }
  if (typeof issns === 'object' && !Array.isArray(issns)) {
    issns = (ref2 = issns.journal_issns) != null ? ref2 : issns.ISSN;
  }
  if (typeof issns === 'string') {
    issns = issns.replace(/\s/g, '').split(',');
  }
  if (Array.isArray(issns) && issns.length) {
    q = 'journal_issns.keyword:*' + issns.join('* OR journals_issns.keyword:*') + '*';
    if (q.includes(' OR ')) {
      q = '(' + q + ')';
    }
    closed = (await this.src.oadoi.count(q + ' AND oa_status:"closed"'));
    hybrid = (await this.src.oadoi.count(q + ' AND oa_status:"hybrid"'));
    if (closed && hybrid / closed > .001) {
      return true;
    } else {
      return false;
    }
  } else {

  }
};

// if we ever decide to use title search on oadoi (only covers crossref anyway so no additional benefit to us at the moment):
// https://support.unpaywall.org/support/solutions/articles/44001977396-how-do-i-use-the-title-search-api-

// https://support.unpaywall.org/support/solutions/articles/44001867302-unpaywall-change-notes
// https://unpaywall.org/products/data-feed/changefiles
P.src.oadoi.load = async function() {
  var batch, complete, ended, infile, lines, resp, started, stats, strm, total, wstr;
  started = (await this.epoch());
  //batchsize = 10000 # how many records to batch upload at a time - 20k ran smooth, took about 6 hours.
  //howmany = @params.howmany ? -1 # max number of lines to process. set to -1 to keep going
  infile = this.S.directory + '/import/oadoi/snapshot.jsonl'; // where the lines should be read from
  try {
    // could also be possible to stream this from oadoi source via api key, which always returns the snapshot from the previous day 0830
    // streaming caused timeouts so download first if not present
    // http://api.unpaywall.org/feed/snapshot?api_key=
    stats = (await fs.stat(infile)); // check if file exists in async fs promises which does not have .exists
  } catch (error) {
    console.log('OADOI downloading snapshot');
    resp = (await fetch('https://api.unpaywall.org/feed/snapshot?api_key=' + this.S.src.oadoi.apikey));
    wstr = fs.createWriteStream(infile);
    await new Promise((resolve, reject) => {
      resp.body.pipe(wstr);
      resp.body.on('error', reject);
      return wstr.on('finish', resolve);
    });
    console.log('snapshot downloaded');
  }
  if (this.params.clear) { //if not lastrecord
    //lastfile = @S.directory + '/import/oadoi/last' # where to record the ID of the last item read from the file
    //try lastrecord = (await fs.readFile lastfile).toString() if not @refresh
    await this.src.oadoi('');
  }
  total = 0;
  batch = [];
  lines = '';
  complete = false;
  `# it appears it IS gz compressed even if they provide it without the .gz file extension
for await line from readline.createInterface input: fs.createReadStream(infile).pipe zlib.createGunzip() #, crlfDelay: Infinity
  break if total is howmany
  rec = JSON.parse line.trim().replace /\,$/, ''
  if not lastrecord or lastrecord.toLowerCase() is rec.doi.toLowerCase()
    lastrecord = undefined
    total += 1
    rec._id = rec.doi.replace /\//g, '_'
    batch.push rec
    if batch.length is batchsize
      console.log 'OADOI bulk loading', batch.length, total
      await @src.oadoi batch
      batch = []
      await fs.writeFile lastfile, rec.doi`;
  strm = fs.createReadStream(infile).pipe(zlib.createGunzip());
  strm.on('data', async(chunk) => {
    var line, lp, rec;
    line = chunk.toString('utf8');
    if (typeof line === 'string' && line) {
      lines += line;
    }
    while (lines.includes('\n')) {
      [lp, lines] = lines.replace('\n', 'X0X0X0X0X0X0X0X0X0X0X0').split('X0X0X0X0X0X0X0X0X0X0X0'); // cheap split on first occurrence
      rec = {};
      try {
        rec = JSON.parse(lp); //.trim().replace /\,$/, ''
      } catch (error) {}
      if (rec != null ? rec.doi : void 0) {
        batch.push(rec);
      } else {
        console.log('oadoi load failed to parse record from string', lp);
      }
      if (batch.length >= 10000) {
        total += batch.length;
        console.log('OADOI bulk loading', batch.length, total);
        await this.src.oadoi(batch);
        batch = [];
      }
    }
    return lines != null ? lines : lines = '';
  });
  strm.on('error', (err) => {
    return console.log('oadoi load file stream error', JSON.stringify(err));
  });
  strm.on('end', () => {
    console.log('stream complete for oadoi load');
    return complete = true;
  });
  while (!complete) {
    console.log('oadoi load streaming file', lines.length, total, Math.floor((Date.now() - started) / 1000 / 60) + 'm');
    await this.sleep(30000);
  }
  if (batch.length) {
    await this.src.oadoi(batch);
  }
  ended = Date.now();
  console.log('oadoi load complete', total, started, ended, Math.floor((ended - started) / 1000 / 60) + 'm');
  return total;
};

P.src.oadoi.load._bg = true;

P.src.oadoi.load._async = true;

P.src.oadoi.load._log = false;

//P.src.oadoi.load._auth = 'root'
P.src.oadoi.changes = async function(oldest) {
  var batch, batchsize, changes, counter, days, i, last, lc, len, lfl, line, lm, lr, rec, ref, ref1, resp, upto, uptofile, wstr;
  batchsize = 30000;
  // the 2021-08-19 file was very large, 139M compressed and over 1.2GB uncompressed, and trying to stream it kept resulting in zlib unexpected end of file error
  // suspect it can't all be streamed before timing out. So write file locally then import then delete, and write 
  // error file dates to a list file, and manually load them separately if necessary
  uptofile = this.S.directory + '/import/oadoi/upto'; // where to record the ID of the most recent change day file that's been processed up to
  //errorfile = @S.directory + '/import/oadoi/errors'
  if (oldest == null) {
    oldest = this.params.changes;
  }
  if (!oldest) {
    try {
      oldest = parseInt(((await fs.readFile(uptofile))).toString());
    } catch (error) {}
  }
  if (!oldest) {
    try {
      last = (await this.src.oadoi('*', {
        size: 1,
        sort: {
          updated: {
            order: 'desc'
          }
        }
      }));
      oldest = (new Date(last.updated)).valueOf();
    } catch (error) {}
  }
  if (!oldest) { // or could remove this to just allow running back through all
    console.log('Timestamp day to work since is required - run load first to auto-generate');
    return;
  }
  changes = (await this.fetch('https://api.unpaywall.org/feed/changefiles?api_key=' + this.S.src.oadoi.apikey + '&interval=day'));
  //seen = []
  //dups = 0
  counter = 0;
  days = 0;
  upto = false;
  ref = changes.list.reverse();
  // list objects go back in order from most recent day
  for (i = 0, len = ref.length; i < len; i++) {
    lr = ref[i];
    lm = (new Date(lr.last_modified)).valueOf();
    console.log(lr.last_modified, lm, oldest, last != null ? last.updated : void 0);
    //if oldest and lm <= oldest
    //  break
    if (lr.filetype === 'jsonl' && (!oldest || lm > oldest)) { //and lr.date not in ['2021-08-19'] # streaming this file (and some others) causes on unexpected end of file error
      console.log('OADOI importing changes for', lr.last_modified);
      days += 1;
      batch = [];
      lc = 0;
      lfl = this.S.directory + '/import/oadoi/' + lr.date + '.jsonl.gz';
      resp = (await fetch(lr.url));
      wstr = fs.createWriteStream(lfl);
      await new Promise((resolve, reject) => {
        resp.body.pipe(wstr);
        resp.body.on('error', reject);
        return wstr.on('finish', resolve);
      });
      ref1 = readline.createInterface({
        input: fs.createReadStream(lfl).pipe(zlib.createGunzip())
      });
      //for await line from readline.createInterface input: (await fetch lr.url).body.pipe zlib.createGunzip().on('error', (err) -> fs.appendFile(errorfile, lr.date); console.log err)
      for await (line of ref1) {
        upto = lm; // if upto is false
        lc += 1;
        rec = JSON.parse(line.trim().replace(/\,$/, ''));
        rec._id = rec.doi.replace(/\//g, '_');
        batch.push(rec);
        counter += 1;
        if (batch.length >= batchsize) {
          console.log('OADOI bulk loading changes', days, batch.length, lc); //, seen.length, dups
          await this.src.oadoi(batch);
          batch = [];
        }
      }
      if (batch.length) {
        await this.src.oadoi(batch);
      }
      fs.unlink(lfl);
    }
    if (upto) {
      try {
        await fs.writeFile(uptofile, upto);
      } catch (error) {}
    }
  }
  console.log('oadoi changes complete', days, counter); //, seen.length, dups
  return counter; //seen.length
};

P.src.oadoi.changes._bg = true;

P.src.oadoi.changes._async = true;

P.src.oadoi.changes._log = false;

P.src.oadoi.changes._auth = 'root';

P.src.oadoi.changes._notify = false;

var base,
  indexOf = [].indexOf;

if ((base = S.src).openalex == null) {
  base.openalex = {};
}

try {
  S.src.openalex = JSON.parse(SECRETS_OPENALEX);
} catch (error) {}

// https://docs.openalex.org/api
// https://docs.openalex.org/download-snapshot/snapshot-data-format
// https://docs.openalex.org/download-snapshot/download-to-your-machine

// https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
// curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
// unzip awscliv2.zip
// sudo ./aws/install

// aws s3 sync 's3://openalex' 'openalex' --no-sign-request

// note for resizing storage volume:
// sudo resize2fs /dev/sdv (or whatever the identity of the volume is)
P.src.openalex = function() {
  return true;
};

P.src.openalex.works = {
  _index: {
    settings: {
      number_of_shards: 15
    }
  },
  _prefix: false
};

//P.src.openalex.authors = _index: {settings: {number_of_shards: 15}}, _prefix: false
//P.src.openalex.institutions = _index: true, _prefix: false
//P.src.openalex.concepts = _index: true, _prefix: false
//P.src.openalex.venues = _index: true, _prefix: false
P.src.openalex.works._format = function(rec) {
  var abs, j, k, len, len1, n, ref, ref1, ref2, ref3, ref4, word, xc;
  try {
    ref = rec.concepts;
    for (j = 0, len = ref.length; j < len; j++) {
      xc = ref[j];
      if (xc.score != null) {
        xc.score = Math.floor(xc.score);
      }
    }
  } catch (error) {}
  try {
    rec._id = (ref1 = (ref2 = rec.doi) != null ? ref2 : rec.DOI) != null ? ref1 : (ref3 = rec.ids) != null ? ref3.doi : void 0;
    if (rec._id.includes('http') && rec._id.includes('/10.')) {
      rec._id = '10.' + rec._id.split('/10.').pop();
    }
    if (!rec._id || !rec._id.startsWith('10.')) {
      rec._id = rec.id.split('/').pop();
    }
  } catch (error) {
    rec._id = rec.id.split('/').pop();
  }
  try {
    abs = [];
    for (word in rec.abstract_inverted_index) {
      ref4 = rec.abstract_inverted_index[word];
      for (k = 0, len1 = ref4.length; k < len1; k++) {
        n = ref4[k];
        abs[n] = word;
      }
    }
    if (abs.length) {
      rec.abstract = abs.join(' ');
    }
  } catch (error) {}
  try {
    delete rec.abstract_inverted_index;
  } catch (error) {}
  return rec;
};

P.src.openalex.works.doi = async function(doi, refresh) {
  var found, ref;
  if (doi == null) {
    doi = this.params.doi;
  }
  if (refresh == null) {
    refresh = this.params.refresh;
  }
  if (refresh || !(found = (await this.src.openalex.works('ids.doi:"https://doi.org/' + doi + '"', 1)))) {
    if (found = (await this.fetch('https://api.openalex.org/works/https://doi.org/' + doi + (((ref = this.S.src.openalex) != null ? ref.apikey : void 0) ? '?api_key=' + this.S.src.openalex.apikey : '')))) {
      if (found.id) {
        found = (await this.src.openalex.works._format(found));
        this.waitUntil(this.src.openalex.works(found));
      }
    }
  }
  return found;
};

P.src.openalex.load = async function(what, changes, clear, sync, last) {
  var _dofile, change, de, entry, expectedfiles, hasnew, howmany, inf, infiles, j, k, l, len, len1, len2, len3, m, manifest, maxbatchsize, maxrunners, processedfiles, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, running, stats, synced, total, updated;
  if (what == null) {
    what = (ref = (ref1 = this.params.load) != null ? ref1 : this.params.openalex) != null ? ref : 'works';
  }
  if (what !== 'works') { //, 'venues', 'authors', 'institutions', 'concepts']
    return false;
  }
  if (clear == null) {
    clear = (ref2 = this.params.clear) != null ? ref2 : false;
  }
  if (sync == null) {
    sync = (ref3 = this.params.sync) != null ? ref3 : false;
  }
  if (clear === true) {
    await this.src.openalex[what]('');
    await this.sleep(60000);
  }
  howmany = (ref4 = this.params.howmany) != null ? ref4 : -1; // max number of lines to process. set to -1 to keep going
  maxbatchsize = 10000; // how many records to batch upload at a time
  total = 0;
  infiles = this.S.directory + '/import/openalex/data/' + what;
  if (typeof changes === 'string') {
    changes = [changes];
  } else if (changes === true) {
    console.log('Checking for Openalex changes in', what);
    changes = [];
    try {
      manifest = JSON.parse(((await fs.readFile(infiles + '/manifest'))).toString());
      last = (await this.epoch(manifest.entries[manifest.entries.length - 1].url.split('=')[1].split('/')[0]));
    } catch (error) {
      last = 0;
    }
    if (sync) {
      // can also just import certain types, like at s3://openalex/data/works
      synced = (await this._child('aws', ['s3', 'sync', 's3://openalex', this.S.directory + '/import/openalex', '--no-sign-request']));
      console.log('Openalex sync returned', synced);
    } else {
      await fs.writeFile(infiles + '/manifest', (await this.fetch('https://openalex.s3.amazonaws.com/data/' + what + '/manifest', {
        buffer: true
      })));
      console.log('Openalex manifest updated');
    }
    hasnew = false;
    manifest = JSON.parse(((await fs.readFile(infiles + '/manifest'))).toString());
    ref5 = manifest.entries;
    for (j = 0, len = ref5.length; j < len; j++) {
      entry = ref5[j];
      de = entry.url.split('=')[1].split('/')[0];
      if (!hasnew) {
        if (((await this.epoch(de))) > last) {
          hasnew = true;
        }
      }
      if (hasnew && indexOf.call(changes, de) < 0) {
        changes.push(de);
      }
    }
    if (changes.length) {
      console.log('Found changes', changes);
    }
  } else if (sync === true) {
    console.log('Openalex load syncing', what);
    synced = (await this._child('aws', ['s3', 'sync', 's3://openalex/data/' + what, infiles, '--no-sign-request']));
    console.log('Openalex sync returned', synced);
  }
  if (!sync && changes && changes.length) {
    for (k = 0, len1 = changes.length; k < len1; k++) {
      change = changes[k];
      console.log('Openalex syncing files', what, change);
      try {
        stats = (await fs.stat(infiles + '/updated_date=' + change));
      } catch (error) {
        await this._child('aws', ['s3', 'sync', 's3://openalex/data/' + what + '/updated_date=' + change, infiles + '/updated_date=' + change, '--no-sign-request']);
      }
    }
  }
  expectedfiles = 0;
  processedfiles = 0;
  running = 0;
  maxrunners = 3;
  ref6 = (await fs.readdir(infiles));
  // folder names are like updated_date=2022-04-30
  for (l = 0, len2 = ref6.length; l < len2; l++) {
    updated = ref6[l];
    if (!updated.startsWith('manifest') && (!changes || changes.length === 0 || (ref7 = updated.split('=')[1], indexOf.call(changes, ref7) >= 0))) {
      // if we find in future there is no need to download a whole copy of openalex, instead of s3 sync the whole lot it may be better 
      // to just use streams of the files in each change folder direct from s3, and never have to land them on disk
      _dofile = async(infile) => {
        var batch, len3, line, m, rec, ref8, ref9, xc;
        batch = [];
        ref8 = readline.createInterface({
          input: fs.createReadStream(infiles + '/' + updated + '/' + infile).pipe(zlib.createGunzip())
        });
        //, crlfDelay: Infinity
        for await (line of ref8) {
          if (total === howmany) {
            break;
          }
          rec = JSON.parse(line.trim().replace(/\,$/, ''));
          total += 1;
          if (what === 'venues' || what === 'institutions' || what === 'concepts' || what === 'authors') {
            rec._id = rec.id.split('/').pop();
            if (what === 'authors' && (rec.x_concepts != null)) {
              ref9 = rec.x_concepts;
              for (m = 0, len3 = ref9.length; m < len3; m++) {
                xc = ref9[m];
                if (xc.score != null) {
                  xc.score = Math.floor(xc.score);
                }
              }
            }
          } else if (what === 'works') {
            rec = (await this.src.openalex.works._format(rec));
          }
          batch.push(rec);
          if (batch.length >= maxbatchsize) {
            console.log('Openalex ' + what + ' bulk loading', updated, infile, batch.length, total);
            await this.src.openalex[what](batch);
            batch = [];
          }
        }
        if (batch.length) {
          console.log('Openalex ' + what + ' bulk loading final set for', updated, infile, batch.length, expectedfiles, processedfiles, total);
          await this.src.openalex[what](batch);
        }
        console.log('removing', infiles + '/' + updated + '/' + infile);
        await fs.unlink(infiles + '/' + updated + '/' + infile);
        processedfiles += 1;
        running -= 1;
        return true;
      };
      ref8 = (await fs.readdir(infiles + '/' + updated));
      for (m = 0, len3 = ref8.length; m < len3; m++) {
        inf = ref8[m];
        console.log('Openalex load running', running);
        expectedfiles += 1;
        while (running === maxrunners) {
          await this.sleep(5000);
          console.log('Openalex load running', running);
        }
        running += 1;
        _dofile(inf);
      }
      while (running !== 0) {
        await this.sleep(5000);
      }
      await fs.rmdir(infiles + '/' + updated);
    }
  }
  console.log(expectedfiles, processedfiles, total);
  return {
    expected: expectedfiles,
    processed: processedfiles,
    total: total
  };
};

P.src.openalex.load._bg = true;

P.src.openalex.load._async = true;

P.src.openalex.load._log = false;

P.src.openalex.load._auth = 'root';

P.src.openalex.changes = async function(what, last) {
  var a, batch, cursor, doq, ended, filter, i, j, k, l, len, len1, len2, len3, len4, m, o, queued, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, started, total, url, w, whats;
  started = (await this.epoch());
  if (what == null) {
    what = (ref = (ref1 = this.params.changes) != null ? ref1 : this.params.openalex) != null ? ref : 'works';
  }
  if (typeof last !== 'object') {
    last = {
      updated: last
    };
  }
  if (last == null) {
    last = {};
  }
  if (this.params.last) { // can be a date like 2022-12-13 to match the last updated file date on openalex update files
    last.updated = this.params.last;
    last.created = this.params.last;
  }
  // if no last, calculate it as previous day? or read last from index?
  if ((last.updated == null) || (last.created == null)) {
    try {
      last.updated = ((await this.src.openalex.works('updated_date:*', {
        size: 1,
        sort: {
          updated_date: 'desc'
        }
      }))).updated_date;
    } catch (error) {}
    try {
      last.created = ((await this.src.openalex.works('created_date:*', {
        size: 1,
        sort: {
          created_date: 'desc'
        }
      }))).created_date;
    } catch (error) {}
  }
  if (last.updated == null) {
    last.updated = ((await this.datetime((await this.epoch()) - 86400000))).replace('Z', '000'); // datetime format for openalex (ISO) 2023-09-25T22:33:51.835860
  }
  if (last.created == null) {
    last.created = ((await this.datetime((await this.epoch()) - 86400000))).replace('Z', '000');
  }
  // doing this only for works now, as it does not appear the other types get updated in the same way any more
  whats = ['works']; //, 'venues', 'authors', 'institutions', 'concepts']
  if (what) {
    if (indexOf.call(whats, what) < 0) {
      return false;
    }
  } else {
    what = whats;
  }
  // https://docs.openalex.org/how-to-use-the-api/get-lists-of-entities/paging
  console.log('Openalex changes checking from', last);
  total = 0;
  queued = 0;
  ref2 = (Array.isArray(what) ? what : [what]);
  for (j = 0, len = ref2.length; j < len; j++) {
    w = ref2[j];
    ref3 = ['updated'];
    //, 'created'] # apparently, now, (2/10/2023) all records do have an updated_date... 
    for (k = 0, len1 = ref3.length; k < len1; k++) {
      filter = ref3[k];
      if (((await this.epoch(last.updated))) < started - 3600000) { // if it has been at least an hour since something was updated...
        batch = [];
        cursor = '*';
        // doing created and updated separately because although we initially thought updated would include created, there is suggestions it does not, in missing records
        // https://github.com/ourresearch/openalex-api-tutorials/blob/main/notebooks/getting-started/premium.ipynb
        url = 'https://api.openalex.org/' + w + '?filter=from_' + filter + '_date:' + last[filter] + '&api_key=' + this.S.src.openalex.apikey + '&per-page=200&cursor=';
        console.log('Openalex changes querying', url + cursor);
        try {
          res = (await this.fetch(url + cursor));
          try {
            console.log('Openalex changes query retrieved', res.results.length);
          } catch (error) {}
          while ((res != null) && typeof res === 'object' && Array.isArray(res.results) && res.results.length) {
            ref4 = res.results;
            for (l = 0, len2 = ref4.length; l < len2; l++) {
              rec = ref4[l];
              if (w === 'works') {
                rec = (await this.src.openalex.works._format(rec));
                if (rec._id.startsWith('10.') && (rec.authorships != null) && ((ref5 = rec.publication_year) === '2023' || ref5 === '2022' || ref5 === 2023 || ref5 === 2022)) {
                  doq = false;
                  ref6 = rec.authorships;
                  for (m = 0, len3 = ref6.length; m < len3; m++) {
                    a = ref6[m];
                    if (doq) {
                      break;
                    }
                    ref8 = (ref7 = a.institutions) != null ? ref7 : [];
                    for (o = 0, len4 = ref8.length; o < len4; o++) {
                      i = ref8[o];
                      if (doq) {
                        break;
                      }
                      if (i.display_name != null) {
                        doq = rec._id;
                      }
                    }
                  }
                  if (doq) {
                    try {
                      await this.report.queue(doq, void 0, void 0, void 0, 'changes');
                    } catch (error) {}
                    queued += 1;
                  }
                }
              }
              batch.push(rec);
            }
            if (batch.length >= 10000) {
              console.log('Openalex ' + what + ' ' + filter + ' bulk loading changes', batch.length, total, queued);
              total += batch.length;
              await this.src.openalex[what](batch);
              batch = [];
            }
            if ((ref9 = res.meta) != null ? ref9.next_cursor : void 0) {
              cursor = res.meta.next_cursor;
              res = (await this.fetch(url + encodeURIComponent(cursor)));
            }
          }
        } catch (error) {}
        if (batch.length) {
          total += batch.length;
          await this.src.openalex[what](batch);
          batch = [];
        }
      }
    }
  }
  ended = (await this.epoch()); // schedule this to loop, and run at most every hour
  if (this.fn !== 'src.openalex.changes' && ended - started < 3600000) {
    console.log('Openalex changes waiting to loop');
    await this.sleep(3600000 - (ended - started));
  }
  console.log('Openalex changes changed', total, queued);
  return total;
};

P.src.openalex.changes._log = false;

P.src.openalex.changes._bg = true;

P.src.openalex.changes._async = true;

//P.src.openalex.changes._auth = 'root'

// there are pubmed data loaders on the server side, they build an index that can 
// be queried directly. However some of the below functions may still be useful 
// for lookups to the pubmed API at other times

// pubmed API http://www.ncbi.nlm.nih.gov/books/NBK25497/
// examples http://www.ncbi.nlm.nih.gov/books/NBK25498/#chapter3.ESearch__ESummaryEFetch
// get a pmid - need first to issue a query to get some IDs...
// http://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?id=21999661&db=pubmed
// then scrape the QueryKey and WebEnv values from it and use like so:
// http://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed&query_key=1&WebEnv=NCID_1_54953983_165.112.9.28_9001_1461227951_1012752855_0MetA0_S_MegaStore_F_1

// NOTE: interestingly there are things in pubmed with PMC IDs that are NOT in EPMC, they return 
// nothing in the epmc website or API. For example PMID 33685375 has PMC7987225 and DOI 10.2989/16085906.2021.1872664
// (the crossref record has no PMID or PMC in it, but the pubmed record has all)

// NOTE also there are items in pubmed with identifier.pmc which seem fine but some have
// identifier.pmcid which may NOT be fine. e.g. PMID 31520348 shows a pmc ID of 6156939
// but in PMC that is a DIFFERENT article. The DOI provided in pubmed matches the correct 
// article in EPMC, which is not an article in PMC.
var indexOf = [].indexOf;

P.src.pubmed = {
  _key: 'PMID',
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 6
    }
  }
};

P.src.pubmed.doi = async function(doi) {
  var found;
  if (doi == null) {
    doi = this.params.doi;
  }
  if (doi && (found = (await this.src.pubmed('identifier.doi:"' + doi + '"', 1)))) {
    return found;
  }
};

// otherwise search entrez with DOI?
P.src.pubmed.pmc = async function(pmc) {
  var found;
  if (pmc == null) {
    pmc = this.params.pmc;
  }
  if (pmc && (found = (await this.src.pubmed('identifier.pmc:"PMC' + pmc.toString().toLowerCase().replace('pmc', '') + '"', 1)))) {
    return found;
  }
};

// otherwise try calling entrez?
P.src.pubmed.entrez = {};

P.src.pubmed.entrez.summary = async function(qk, webenv, id) {
  var frec, i, ii, j, l, len, len1, len2, md, rec, recs, ref, ref1, ref2, si, sio, url;
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=pubmed';
  if (id != null) {
    if (Array.isArray(id)) {
      id = id.join(',');
    }
    url += '&id=' + id; // can be a comma separated list as well
  } else {
    url += '&query_key=' + qk + '&WebEnv=' + webenv;
  }
  try {
    md = (await this.convert.xml2json((await this.fetch(url))));
    recs = [];
    if (!Array.isArray(md.eSummaryResult.DocSum)) {
      md.eSummaryResult.DocSum = [md.eSummaryResult.DocSum];
    }
    ref = md.eSummaryResult.DocSum;
    for (i = 0, len = ref.length; i < len; i++) {
      rec = ref[i];
      frec = {
        id: rec.Id
      };
      ref1 = rec.Item;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        ii = ref1[j];
        if (ii._.Type === 'List') {
          frec[ii._.Name] = [];
          if (ii.Item != null) {
            ref2 = ii.Item;
            for (l = 0, len2 = ref2.length; l < len2; l++) {
              si = ref2[l];
              sio = {};
              sio[si._.Name] = si.$;
              frec[ii._.Name].push(sio);
            }
          }
        } else {
          frec[ii._.Name] = ii.$;
        }
      }
      recs.push(frec);
      if ((id == null) || !id.includes(',')) {
        return recs[0];
      }
    }
    return recs;
  } catch (error) {

  }
};

P.src.pubmed.entrez.pmid = async function(pmid) {
  var res, result, url;
  if (pmid == null) {
    pmid = this.params.pmid;
  }
  // can prob switch this direct for an efetch
  // https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=35717313
  // also could do for pmc and others
  // https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?db=pubmed&id=' + pmid;
  try {
    await this.sleep(200);
    res = (await this.fetch(url));
    result = (await this.convert.xml2json(res));
    return this.src.pubmed.entrez.summary(result.ePostResult.QueryKey, result.ePostResult.WebEnv);
  } catch (error) {

  }
};

// switch this to use the code in pubmed.load as a formatter for records? Or have load call format
P.src.pubmed.search = async function(str, full, size = 10, ids = false) {
  var i, j, len, len1, pg, rec, ref, ref1, res, result, uid, url;
  if (str == null) {
    str = (ref = this.params.search) != null ? ref : this.params.q;
  }
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&retmax=' + size + '&sort=pub date&term=' + str;
  try {
    if (typeof ids === 'string') {
      ids = ids.split(',');
    }
    if (Array.isArray(ids)) {
      res = {
        total: ids.length,
        data: []
      };
    } else {
      await this.sleep(200);
      res = (await this.fetch(url));
      result = (await this.convert.xml2json(res));
      res = {
        total: result.eSearchResult.Count[0],
        data: []
      };
      if (ids === true) {
        res.data = result.eSearchResult.IdList[0].Id;
        return res;
      } else {
        ids = result.eSearchResult.IdList[0].Id;
      }
    }
    if (full) { // may need a rate limiter on this
      for (i = 0, len = ids.length; i < len; i++) {
        uid = ids[i];
        pg = (await this.src.pubmed.pmid(uid)); // should rate limit this to 300ms?
        res.data.push(pg);
        if (res.data.length === size) {
          break;
        }
      }
    } else {
      ref1 = (await this.src.pubmed.entrez.summary(void 0, void 0, ids));
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        rec = ref1[j];
        res.data.push(rec);
        if (res.data.length === size) {
          break;
        }
      }
    }
    return res;
  } catch (error) {

  }
};

P.src.pubmed.pmid = function(pmid) {
  if (pmid == null) {
    pmid = this.params.pmid;
  }
  try {
    // check local index first, if not present then try to retrieve from entrez
    return this.src.pubmed.entrez.pmid(pmid); // save if it was not present?
  } catch (error) {}
};

P.src.pubmed.aheadofprint = async function(pmid) {
  var res;
  if (pmid == null) {
    pmid = this.params.pmid;
  }
  try {
    // should switch this for an efetch
    // https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&id=35717313
    await this.sleep(100);
    res = (await this.fetch('https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'));
    return res.includes('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus'); // would these be url encoded or proper characters?
  } catch (error) {

  }
};

P.src.pubmed.availabilities = {
  _sheet: '1ZQa6tOqFsm_nF3XUk9-FhDk5gmVtXeRC4I3uldDl-gM/Export',
  _prefix: false,
  _key: 'PMC'
};

P.src.pubmed.availability = async function(pmcid) {
  var exists, ref, ref1, ref2, ref3, ref4;
  // availabilities for now are loaded from a sheet. However they could be done by xml lookup. see below
  if (pmcid == null) {
    pmcid = (ref = (ref1 = (ref2 = (ref3 = (ref4 = this.params.pubmed) != null ? ref4 : this.params.availability) != null ? ref3 : this.params.pmc) != null ? ref2 : this.params.pmcid) != null ? ref1 : this.params.PMC) != null ? ref : this.params.PMCID;
  }
  pmcid = 'pmc' + (pmcid + '').toLowerCase().replace('pmc', '');
  if (exists = (await this.src.pubmed.availabilities(pmcid))) {
    return true;
  } else {
    return false;
  }
};

P.src.pubmed.availability.statement = function(pmcid, rec) {
  return P.src.epmc.statement(pmcid, rec);
};

// https://www.nlm.nih.gov/databases/download/pubmed_medline.html
// https://www.nlm.nih.gov/bsd/licensee/2021_stats/2021_LO.html

// in case the medline data does not include all PMCs or PMIDs, there is a converter API
// and/or PMC sources that could be used to map things (with just over 6 million PMC IDs in the pubmed 
// data, looks like probably all PMC articles were in the data dump anyway)
// https://www.ncbi.nlm.nih.gov/pmc/tools/id-converter-api/
// https://www.ncbi.nlm.nih.gov/pmc/tools/ftp/

// annual files published each December, listed at: https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/
// lists files such as https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/pubmed21n0001.xml.gz
// up to 1062 for 2020. Contains other files including .md5 files for each gz file
// Managed to load 31847922
// PMID 30036026 failed with a “published” value of 1-01-01

// daily update files listed at https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/
// such as https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/pubmed21n1063.xml.gz
// can contain one or more files for each day since the last annual file dump

// elements the files should contain:
// https://www.nlm.nih.gov/bsd/licensee/elements_alphabetical.html
// and descriptions:
// https://www.nlm.nih.gov/bsd/licensee/elements_descriptions.html#history

// TODO consider using ncbi to get all pmc files:
// https://www.ncbi.nlm.nih.gov/pmc/tools/pmcaws/
P.src.pubmed.load = async function(changes) {
  var _loop, a, addr, batchsize, exists, f, fls, fnumber, howmany, i, len, listing, nf, ref, ref1, ref2, ref3, running, streamers, total;
  if ((changes == null) && this.params.load === 'changes') {
    // there are 30k or less records per pubmed file so tried batching by file, but streaming more than one file at a time caused OOM
    // so reduce batch size if necessary. default node heap size is 1400M I think, so increased to 3072M and try again
    // check if increasing heap that machine running it has enough - AND note that on production if using PM2 to run as cluster, then 
    // need enough memory for each process to max out. Running 3 with 15k batch size was stable but reaching almost 3000M at times and 
    // didn't seem much faster, so now set to do whole files as batches with two streamers at a time, see how that goes
    changes = true;
  }
  batchsize = -1; // how many records to batch upload at a time
  streamers = (ref = this.params.streamers) != null ? ref : 1; // how many files to stream at a time
  howmany = (ref1 = this.params.howmany) != null ? ref1 : -1; // max number of lines to process. set to -1 to keep going...
  if (this.refresh && !changes) {
    await this.src.pubmed('');
  }
  addr = changes ? 'https://ftp.ncbi.nlm.nih.gov/pubmed/updatefiles/' : 'https://ftp.ncbi.nlm.nih.gov/pubmed/baseline/';
  fls = [];
  fnumber = typeof this.params.load === 'number' ? this.params.load : typeof this.params.changes === 'number' ? this.params.changes : void 0;
  listing = (await this.fetch(addr));
  ref2 = listing.split('href="');
  for (i = 0, len = ref2.length; i < len; i++) {
    a = ref2[i];
    f = a.split('"')[0];
    if ((f.endsWith('.gz') && f.includes(fnumber + '.xml')) || (!fnumber && f.startsWith('pubmed') && f.endsWith('.gz') && (((ref3 = this.params.load) === 'baseline') || (this.refresh && !changes) || !(exists = (await this.src.pubmed.count('srcfile:"' + addr + f + '"')))))) {
      fls.push(addr + f);
    } else if (!f.endsWith('.md5')) {
      console.log('pubmed load skipping file', addr + f);
    }
  }
  running = 0;
  total = 0;
  _loop = async(fn) => {
    var an, base, base1, base2, base3, batch, current, idt, j, k, km, len1, line, ll, name, rec, ref4, ref5, rf, sds, somedate, somedatestatus, v;
    console.log('Pubmed loading' + (changes ? ' changes' : ''), fn, fls.length, running);
    // stream them, unzip, and parse line by line, processing each record once a full record has been parsed out
    // the first 2020 gz file for example is 19M, uncompressed it is 182M. 30k records or so per file
    batch = [];
    rec = {};
    current = '';
    try {
      ref4 = readline.createInterface({
        input: ((await fetch(fn))).body.pipe(zlib.createGunzip())
      });
      // this still fails on error because the try doesn't catch
      for await (line of ref4) {
        if (batchsize > 0 && batch.length >= batchsize) {
          await this.src.pubmed(batch);
          batch = [];
          console.log(fn, total);
        }
        line = line.trim().replace('&amp;', '&');
        if (line === '</PubmedArticle>') { // <PubmedArticle>...</PubmedArticle> is a total article record
          total += 1;
          //if published isnt false and published.year
          //  rec.published = await @dateparts published
          rec.srcfile = fn;
          rec._id = rec.PMID;
          batch.push(rec);
          rec = {};
          if (total === howmany) {
            break;
          }
        } else if (!line.startsWith('<?') && !line.includes('?xml') && !line.includes('!DOCTYPE') && !line.includes('/>') && !line.includes('PubmedArticle') && !line.includes('PubmedData') && !line.includes('History') && !line.includes('ArticleIdList') && !line.includes('List>')) {
          current = line.split('>')[0].split(' ')[0].replace('<', ''); // track current line any use? check for </ ?
          km = {
            '<ArticleTitle>': 'title',
            '<AbstractText>': 'abstract',
            '<ISOAbbreviation>': 'iso',
            '<Issue>': 'issue',
            '<Title>': 'journal',
            '<Language>': 'language',
            '<NlmUniqueID>': 'NLMID',
            '<PMID>': 'PMID',
            '<Volume>': 'volume',
            '<CopyrightInformation>': 'copyright',
            '<NumberOfReferences>': 'references_count',
            '<PublicationStatus>': 'status',
            '<SpaceFlightMission>': 'spaceflightmission'
          };
          for (k in km) {
            if (line.includes(k) || line.includes(k.replace('>', ' '))) {
              if (rec[name = km[k]] == null) {
                rec[name] = line.split('>')[1].split('</')[0];
              }
            }
          }
          if (line.includes('<MedlinePgn>')) { // vals like 1345-56 makes ES interpret a date, then others that don't will fail
            rec.pages = line.split('>')[1].split('</')[0].replace(' - ', ' to ').replace('-', ' to ');
          } else if (line.includes('<ISSN')) {
            if (rec.ISSN == null) {
              rec.ISSN = [];
            }
            v = line.split('>')[1].split('</')[0];
            if (indexOf.call(rec.ISSN, v) < 0) {
              rec.ISSN.push(v);
            }
          } else if (line.includes('<Keyword>')) {
            if (rec.keyword == null) {
              rec.keyword = [];
            }
            v = line.split('>')[1].split('</')[0];
            if (indexOf.call(rec.keyword, v) < 0) {
              rec.keyword.push(v);
            }
          } else if (line.includes('<GeneSymbol>')) {
            if (rec.gene == null) {
              rec.gene = [];
            }
            v = line.split('>')[1].split('</')[0];
            if (indexOf.call(rec.gene, v) < 0) {
              rec.gene.push(v);
            }
          } else if (line.includes('<PublicationType>') || line.includes('<PublicationType ')) {
            if (rec.type == null) {
              rec.type = [];
            }
            v = line.split('>')[1].split('</')[0];
            if (indexOf.call(rec.type, v) < 0) {
              rec.type.push(v);
            }
          } else if (line.includes('<Chemical>')) {
            if (rec.chemical == null) {
              rec.chemical = [];
            }
            rec.chemical.push({});
          } else if (line.includes('<NameOfSubstance>') || line.includes('<NameOfSubstance ')) {
            if (rec.chemical == null) {
              rec.chemical = [{}];
            }
            rec.chemical[rec.chemical.length - 1].name = line.split('>')[1].split('</')[0];
            rec.chemical[rec.chemical.length - 1].nameID = line.split('UI="')[1].split('"')[0];
          } else if (line.includes('<RegistryNumber>')) {
            if (rec.chemical == null) {
              rec.chemical = [{}];
            }
            rec.chemical[rec.chemical.length - 1].registry = line.split('>')[1].split('</')[0];
          } else if (line.includes('<DataBank>') || line.includes('<DataBank ')) {
            if (rec.databank == null) {
              rec.databank = [];
            }
            rec.databank.push({});
          } else if (line.includes('<DataBankName>')) {
            if (rec.databank == null) {
              rec.databank = [{}];
            }
            rec.databank[rec.databank.length - 1].name = line.split('>')[1].split('</')[0];
          } else if (line.includes('<AccessionNumber>')) {
            if (rec.databank == null) {
              rec.databank = [{}];
            }
            if ((base = rec.databank[rec.databank.length - 1]).accession == null) {
              base.accession = [];
            }
            rec.databank[rec.databank.length - 1].accession.push(line.split('>')[1].split('</')[0]);
          } else if (line.includes('<Grant>') || line.includes('<Grant ')) {
            if (rec.grant == null) {
              rec.grant = [];
            }
            rec.grant.push({});
          } else if (line.includes('<GrantID>')) {
            if (rec.grant == null) {
              rec.grant = [{}];
            }
            rec.grant[rec.grant.length - 1].id = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Acronym>')) {
            if (rec.grant == null) {
              rec.grant = [{}];
            }
            rec.grant[rec.grant.length - 1].acronym = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Agency>')) {
            if (rec.grant == null) {
              rec.grant = [{}];
            }
            rec.grant[rec.grant.length - 1].agency = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Country>')) {
            if ((!rec.grant || rec.grant[rec.grant.length - 1].country) && !rec.country) {
              rec.country = line.split('>')[1].split('</')[0];
            } else if (rec.grant && rec.grant.length) {
              rec.grant[rec.grant.length - 1].country = line.split('>')[1].split('</')[0];
            }
          } else if (line.includes('<MeshHeading>') || line.includes('<MeshHeading ')) {
            if (rec.mesh == null) {
              rec.mesh = [];
            }
            rec.mesh.push({});
          } else if (line.includes('<DescriptorName>') || line.includes('<DescriptorName ')) {
            if (rec.mesh == null) {
              rec.mesh = [{}];
            }
            rec.mesh[rec.mesh.length - 1].description = line.split('>')[1].split('</')[0];
            rec.mesh[rec.mesh.length - 1].descriptionID = line.split('UI="')[1].split('"')[0];
          } else if (line.includes('<QualifierName>') || line.includes('<QualifierName ')) {
            if (rec.mesh == null) {
              rec.mesh = [{}];
            }
            if ((base1 = rec.mesh[rec.mesh.length - 1]).qualifier == null) {
              base1.qualifier = [];
            }
            rec.mesh[rec.mesh.length - 1].qualifier.push({
              name: line.split('>')[1].split('</')[0],
              id: line.split('UI="')[1].split('"')[0]
            });
          // where are author Identifiers going? Don't seem to have picked any up
          } else if (line.includes('<Author>') || line.includes('<Author ') || line.includes('<Investigator>') || line.includes('<Investigator ')) {
            if (rec.author == null) {
              rec.author = [];
            }
            rec.author.push(line.includes('<Investigator') ? {
              investigator: true
            } : {});
          } else if (line.includes('<LastName>')) { // some fields called PersonalNameSubjectList can cause a problem but don't know what they are so not including them
            if (rec.author == null) {
              rec.author = [{}];
            }
            rec.author[rec.author.length - 1].lastname = line.split('>')[1].split('</')[0];
          } else if (line.includes('<ForeName>')) { // skip <Initials>
            if (rec.author == null) {
              rec.author = [{}];
            }
            rec.author[rec.author.length - 1].firstname = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Affiliation>')) {
            if (rec.author == null) {
              rec.author = [{}];
            }
            rec.author[rec.author.length - 1].affiliation = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Identifier>')) {
            if (rec.author == null) {
              rec.author = [{}];
            }
            rec.author[rec.author.length - 1].identifier = line.split('>')[1].split('</')[0];
          } else if (line.includes('<Note>') || line.includes('<Note ') || line.includes('<GeneralNote>') || line.includes('<GeneralNote ')) {
            if (rec.notes == null) {
              rec.notes = [];
            }
            rec.notes.push(line.split('>')[1].split('</')[0]);
          } else if (line.includes('<DeleteCitation>') || line.includes('<DeleteCitation ')) {
            rec.deletedFromMedline = true; // this indicates Medline deleted the record, we should prob just remove all these too, but let's see how many there are
          } else if (line.includes('<ArticleId>') || line.includes('<ArticleId ')) {
            if (rec.identifier == null) {
              rec.identifier = {};
            }
            try {
              idt = line.split('IdType="')[1].split('"')[0];
              if ((base2 = rec.identifier)[idt] == null) {
                base2[idt] = line.split('>')[1].split('</')[0];
              }
            } catch (error) {}
          // check how History dates are being handled, where is the attribute that indicates what sort of date they are?
          } else if (!line.includes('</') && (line.includes('Date>') || line.includes('<Date') || line.includes('<PubMedPubDate') || line.includes('<ArticleDate>') || line.includes('ArticleDate ') || line.includes('<PubDate>') || line.includes('<PubDate '))) {
            somedate = line.split('>')[0].split(' ')[0].replace('<', '');
            try {
              ll = line.toLowerCase();
              if (ll.includes('pubstatus')) {
                somedatestatus = ll.split('>')[0].split('pubstatus')[1];
              }
              if (somedatestatus.includes('"')) {
                somedatestatus = somedatestatus.split('"')[1];
              }
            } catch (error) {}
          } else if (somedate && (line.includes('<Year>') || line.includes('<Month>') || line.includes('<Day>'))) {
            if (rec.dates == null) {
              rec.dates = {};
            }
            sds = somedate + (somedatestatus ? '_' + somedatestatus : '');
            if ((base3 = rec.dates)[sds] == null) {
              base3[sds] = {};
            }
            rec.dates[sds][line.split('>')[0].replace('<', '').toLowerCase()] = line.split('>')[1].split('</')[0];
            delete rec.dates[sds].date;
            delete rec.dates[sds].timestamp;
            try {
              rec.dates[sds] = (await this.dateparts(rec.dates[sds]));
            } catch (error) {}
            try {
              if (somedatestatus) {
                rec.dates[sds].pubstatus = somedatestatus;
              }
            } catch (error) {}
          } else if (somedate && line.includes('</' + somedate)) {
            somedate = '';
            somedatestatus = '';
          // handle the contents of ReferenceList and be aware it uses self closing xml as well e.g. <ReferenceList/> (as may other tags)
          } else if (line.includes('<Reference>') || line.includes('<Reference ')) {
            if (rec.references == null) {
              rec.references = [];
            }
          } else if (line.includes('<Citation')) {
            if (rec.references == null) {
              rec.references = [];
            }
            rf = {
              author: []
            };
            try {
              ref5 = line.split('. ')[0].split(', ');
              for (j = 0, len1 = ref5.length; j < len1; j++) {
                an = ref5[j];
                rf.author.push({
                  name: an
                });
              }
            } catch (error) {}
            try {
              rf.title = line.split('. ')[1].split('?')[0].trim();
            } catch (error) {}
            try {
              rf.journal = line.replace(/\?/g, '.').split('. ')[2].trim();
            } catch (error) {}
            try {
              if (line.includes('doi.org/')) {
                rf.doi = line.split('doi.org/')[1].split(' ')[0].trim();
              }
            } catch (error) {}
            try {
              rf.url = 'http' + rc.split('http')[1].split(' ')[0];
            } catch (error) {}
            if (JSON.stringify(rf) !== '{}') {
              rec.references.push(rf);
            }
          }
        }
      }
      if (batch.length) {
        await this.src.pubmed(batch);
        console.log(fn, total);
      }
    } catch (error) {}
    return running -= 1;
  };
  while (fls.length) {
    if (howmany > 0 && total >= howmany) {
      break;
    }
    await this.sleep(1000);
    if (running < streamers) {
      running += 1;
      nf = fls.shift();
      await _loop(nf);
    }
  }
  console.log(total, fls.length);
  if (this.params.howmany) {
    return batch;
  } else {
    return total;
  }
};

P.src.pubmed.load._bg = true;

//P.src.pubmed.load._async = true
P.src.pubmed.load._log = false;

//P.src.pubmed.load._auth = 'root'
P.src.pubmed.changes = function() {
  return this.src.pubmed.load(true);
};

P.src.pubmed.changes._bg = true;

P.src.pubmed.changes._log = false;

//P.src.pubmed.changes._async = true
P; //.src.pubmed.changes._auth = 'root'

P.src.pubmed.changes._notify = false;

// https://ror.readme.io/docs/rest-api
P.src.ror = async function(rid) {
  if (rid == null) {
    rid = this.params.ror;
  }
  if (typeof rid === 'string' && !rid.includes(' ')) {
    rid = rid.split('/').pop(); // just in case it was the full ROR URL (which is their official ID)
    if (rid.length < 11) { // are all RORs 9 long...?
      return this.src.ror._format((await this.fetch('https://api.ror.org/organizations/' + rid)));
    }
  }
};

P.src.ror._index = true;

P.src.ror._prefix = false;

P.src.ror.query = function(q) {
  var ref;
  if (q == null) {
    q = (ref = this.params.query) != null ? ref : this.params.q;
  }
  if (typeof q === 'string') {
    return this.fetch('https://api.ror.org/organizations?query="' + q + '"');
  }
};

P.src.ror.grid = async function(grid) {
  var ref, ref1, res, rr;
  if (grid == null) {
    grid = this.params.grid;
  }
  if (typeof grid === 'string' && grid.startsWith('grid.')) {
    res = (await this.src.ror('external_ids.GRID.all:"' + grid + '"'));
    if ((res != null ? res.id : void 0) || (res != null ? (ref = res.hits) != null ? ref.total : void 0 : void 0) === 1) {
      if (res.id) {
        return res;
      } else {
        return res.hits.hits[0]._source;
      }
    } else {
      res = (await this.src.ror.query(grid));
      if (res != null ? (ref1 = res.items) != null ? ref1[0] : void 0 : void 0) {
        rr = (await this.src.ror._format(res.items[0]));
        this.waitUntil(this.src.ror(rr));
        return rr;
      }
    }
  }
};

P.src.ror.title = async function(title) {
  var ref, ref1, ref2, res, rr;
  if (title == null) {
    title = (ref = this.params.title) != null ? ref : this.params.q;
  }
  if (typeof title === 'string') {
    if (!this.refresh) {
      res = (await this.src.ror('title:"' + title + '"'));
    }
    if ((res != null ? res.id : void 0) || (res != null ? (ref1 = res.hits) != null ? ref1.total : void 0 : void 0) === 1) {
      if (res.id) {
        return res;
      } else {
        return res.hits.hits[0]._source;
      }
    } else {
      res = (await this.src.ror.query(title));
      if (res != null ? (ref2 = res.items) != null ? ref2[0] : void 0 : void 0) {
        rr = (await this.src.ror._format(res.items[0]));
        this.waitUntil(this.src.ror(rr));
        return rr;
      }
    }
  }
};

P.src.ror._format = function(rec) {
  try {
    rec._id = rec.id.split('/').pop();
  } catch (error) {}
  return rec;
};

// https://ror.readme.io/docs/rest-api
// https://ror.readme.io/docs/data-dump

// data dump comes from:
// https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent
// and within the result object, filename is at hits.hits[0].files[0].links.self
// presumably always the first one?
// it's a zip, once unzipped is a JSON list, and the objects are NOT in jsonlines
// but they are pretty-printed, so risk identify start and end of objects by their whitespacing
P.src.ror.dumps = function() {
  return this.fetch('https://zenodo.org/api/records/?communities=ror-data&sort=mostrecent');
};

P.src.ror.load = async function() {
  var batch, created, endobj, files, fn, last, latest, line, lobj, rec, ref, startobj, total;
  total = 0;
  batch = [];
  try {
    files = (await this.src.ror.dumps());
    latest = (await this.epoch(files.hits.hits[0].files[0].created));
  } catch (error) {}
  last = (await this.src.ror('src:*', {
    sort: {
      'createdAt': 'desc'
    },
    size: 1
  }));
  if ((last != null ? last.hits : void 0) != null) {
    last = last.hits.hits[0]._source;
  }
  console.log(latest, last != null ? last.createdAt : void 0, last != null ? last.src : void 0);
  if ((last != null) && last.createdAt < latest) {
    fn = files.hits.hits[0].files[0].links.self;
    console.log(fn);
    created = (await this.epoch());
    startobj = false;
    endobj = false;
    lobj = '';
    await this.src.ror('');
    ref = readline.createInterface({
      input: ((await fetch(fn))).body.pipe(zlib.createGunzip())
    });
    //for await line from readline.createInterface input: fs.createReadStream infile
    for await (line of ref) {
      try {
        if (!startobj && line.length === 5 && line.replace(/\s\s\s\s/, '') === '{') {
          startobj = true;
          lobj = '{';
        } else if (!endobj && line.replace(',', '').length === 5 && line.replace(/\s\s\s\s/, '').replace(',', '') === '}') {
          endobj = true;
          lobj += '}';
        } else if (line !== '[' && line !== ']') {
          lobj += line;
        }
        if (startobj === true && endobj === true) {
          startobj = false;
          endobj = false;
          rec = (await this.src.ror._format(JSON.parse(lobj)));
          rec.src = fn;
          rec.createdAt = created;
          lobj = '';
          total += 1;
          batch.push(rec);
          if (batch.length === 20000) { // how many records to batch upload at a time
            console.log('ROR bulk loading', batch.length, total);
            await this.src.ror(batch);
            batch = [];
          }
        }
      } catch (error) {}
    }
  }
  if (batch.length) {
    await this.src.ror(batch);
  }
  console.log(total);
  return total;
};

P.src.ror.load._bg = true;

P.src.ror.load._async = true;

P.src.ror.load._auth = 'root';

var base;

if ((base = S.src).zenodo == null) {
  base.zenodo = {};
}

try {
  S.src.zenodo = JSON.parse(SECRETS_ZENODO);
} catch (error) {}

// http://zenodo.org/dev
// https://zenodo.org/api/deposit/depositions
// api key required: http://zenodo.org/dev#restapi-auth
// requires a token be provided as query param on all requests, called ?access_token=

// access token would require deposit:write and deposit:actions permission in order to deposit something AND then publish it

// need to POST create a deposition, then POST upload files to the deposition, then POST publish the deposition
P.src.zenodo = {
  deposition: {},
  records: {}
};

// zenodo can now be searched, technically in test, at zenodo.org/api/records
// see search page for instructions (it is ES) https://help.zenodo.org/guides/search/
P.src.zenodo.records.search = function(q, dev) {
  var ref, size, url;
  // it does have sort but does not seem to parse direction yet, so not much use sorting on publication_date
  // does not seem to do paging or cursors yet either - but size works
  if (q == null) {
    q = this.params;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  size = (ref = this.params.size) != null ? ref : 10;
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/records?size=' + size + '&q=' + encodeURIComponent(q); // just do simple string queries for now
  return this.fetch(url); // could do a post if q is more complex... so far this just returns an ES search endpoint
};

P.src.zenodo.records.record = function(zid, dev) {
  var ref;
  if (zid == null) {
    zid = (ref = this.params.record) != null ? ref : this.params.id;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  return this.fetch('https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/records/' + zid);
};

P.src.zenodo.records.get = async function(q, dev) {
  var r;
  if (q == null) {
    q = this.params.get;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  r = (await this.src.zenodo.records.search(q, dev));
  try {
    return r.hits.hits[0];
  } catch (error) {

  }
};

P.src.zenodo.records.doi = function(doi, dev) {
  if (doi == null) {
    doi = this.params.doi;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  return this.src.zenodo.records.get('doi:"' + doi + '"', dev);
};

P.src.zenodo.records.title = function(title, dev) {
  if (title == null) {
    title = this.params.title;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  return this.src.zenodo.records.get('title:"' + title + '"', dev);
};

P.src.zenodo.records.format = function(rec) {
  var a, as, f, i, j, len, len1, metadata, ref, ref1, ref2;
  if (rec == null) {
    rec = this.params;
  }
  metadata = {};
  try {
    if (metadata.pdf == null) {
      metadata.pdf = rec.pdf;
    }
  } catch (error) {}
  try {
    if (metadata.url == null) {
      metadata.url = rec.url;
    }
  } catch (error) {}
  if (metadata.doi == null) {
    metadata.doi = rec.doi;
  }
  try {
    if (typeof rec.metadata.publication_date === 'string' && rec.metadata.publication_date.split('-').length === 3) {
      metadata.published = rec.metadata.publication_date;
      try {
        metadata.year = metadata.published.split('-')[0];
      } catch (error) {}
    }
  } catch (error) {}
  try {
    if (metadata.title == null) {
      metadata.title = rec.metadata.title;
    }
  } catch (error) {}
  try {
    if (metadata.journal == null) {
      metadata.journal = rec.metadata.journal.title;
    }
  } catch (error) {}
  try {
    if (metadata.issue == null) {
      metadata.issue = rec.metadata.journal.issue;
    }
  } catch (error) {}
  try {
    if (metadata.page == null) {
      metadata.page = rec.metadata.journal.pages;
    }
  } catch (error) {}
  try {
    if (metadata.volume == null) {
      metadata.volume = rec.metadata.journal.volume;
    }
  } catch (error) {}
  try {
    if (metadata.keyword == null) {
      metadata.keyword = rec.metadata.keywords;
    }
  } catch (error) {}
  try {
    if (metadata.licence == null) {
      metadata.licence = rec.metadata.license.id;
    }
  } catch (error) {}
  try {
    metadata.abstract = rec.metadata.description;
  } catch (error) {}
  try {
    if (rec.metadata.access_right = "open") {
      if (metadata.url == null) {
        metadata.url = (rec.files != null) && rec.files.length && (((ref = rec.files[0].links) != null ? ref.self : void 0) != null) ? rec.files[0].links.self : rec.links.html;
      }
      if (metadata.open == null) {
        metadata.open = metadata.url;
      }
    }
  } catch (error) {}
  try {
    ref1 = rec.files;
    for (i = 0, len = ref1.length; i < len; i++) {
      f = ref1[i];
      if (f.type === 'pdf') {
        if (metadata.pdf == null) {
          metadata.pdf = f.links.self;
        }
        break;
      }
    }
  } catch (error) {}
  try {
    if (metadata.author == null) {
      metadata.author = [];
    }
    ref2 = rec.metadata.creators;
    for (j = 0, len1 = ref2.length; j < len1; j++) {
      a = ref2[j];
      if (typeof a === 'string') {
        a = {
          name: a
        };
      }
      if ((a.name != null) && a.name.toLowerCase() !== 'unknown') {
        as = a.name.split(' ');
        try {
          a.family = as[as.length - 1];
        } catch (error) {}
        try {
          a.given = a.name.replace(a.family, '').trim();
        } catch (error) {}
      }
      if (a.affiliation != null) {
        if (_.isArray(a.affiliation)) {
          a.affiliation = a.affiliation[0];
        }
        if (typeof a.affiliation === 'string') {
          a.affiliation = {
            name: a.affiliation
          };
        }
      }
      metadata.author.push(a);
    }
  } catch (error) {}
  return metadata;
};

P.src.zenodo.deposition.create = async function(metadata, up, token, dev) {
  var base1, data, ref, ref1, ref2, ref3, ref4, rs, url;
  // https://zenodo.org/dev#restapi-rep-meta
  if (dev == null) {
    dev = (ref = this.params.dev) != null ? ref : this.S.dev;
  }
  if (token == null) {
    token = this.params.token;
  }
  if (token == null) {
    token = dev ? (ref1 = this.S.src) != null ? (ref2 = ref1.zenodo) != null ? ref2.sandbox : void 0 : void 0 : (ref3 = this.S.src) != null ? (ref4 = ref3.zenodo) != null ? ref4.token : void 0 : void 0;
  }
  if (metadata == null) {
    metadata = this.params.metadata; // or try to retrieve from oaworks.metadata?
  }
  if ((token == null) || (metadata == null) || (metadata.title == null) || (metadata.description == null)) {
    return false;
  }
  url = 'https://' + (dev ? 'sandbox.' : '') + 'zenodo.org/api/deposit/depositions?access_token=' + token;
  data = {
    metadata: metadata
  };
  if (!data.metadata.upload_type) {
    data.metadata.upload_type = 'publication';
    data.metadata.publication_type = 'article';
  }
  // required field, will blank list work? If not, need object with name: Surname, name(s) and optional affiliation and creator
  if ((base1 = data.metadata).creators == null) {
    base1.creators = [
      {
        name: "Works, Open Access"
      }
    ];
  }
  if (up != null) {
    rs = (await this.fetch(url, {
      method: 'POST',
      body: data
    }));
    if (((rs != null ? rs.id : void 0) != null) && (up.content || up.file)) {
      rs.uploaded = (await this.src.zenodo.deposition.upload(rs.id, up.content, up.file, up.name, up.url, token, dev));
    }
    if (up.publish) {
      rs.published = (await this.src.zenodo.deposition.publish(rs.id, token, dev));
    }
    return rs;
  } else {
    // returns a zenodo deposition resource, which most usefully has an .id parameter (to use to then upload files to)
    return (await this.fetch(url, {
      method: 'POST',
      body: data
    }));
  }
};

P.src.zenodo.deposition.upload = async function(id, content, file, filename, url, token, dev) {
  var ref, ref1, ref2, ref3;
  if (id == null) {
    id = (ref = this.params.upload) != null ? ref : this.params.id;
  }
  if (content == null) {
    content = this.params.content;
  }
  if (filename == null) {
    filename = this.params.filename;
  }
  if (!content && !file) {
    try {
      file = this.request.files[0];
    } catch (error) {}
  }
  if (url && !content && !file) {
    try {
      content = (await this.fetch(url, {
        buffer: true
      }));
    } catch (error) {}
  }
  if (token == null) {
    token = this.params.token;
  }
  if (token == null) {
    token = this.S.dev || dev ? (ref1 = this.S.src.zenodo) != null ? ref1.sandbox : void 0 : (ref2 = this.S.src) != null ? (ref3 = ref2.zenodo) != null ? ref3.token : void 0 : void 0;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  if ((token == null) || (id == null)) {
    return false;
  }
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/deposit/depositions/' + id + '/files?access_token=' + token;
  return this.fetch(url, {
    file: content != null ? content : file,
    filename: filename
  });
};

// NOTE this should not only be run on backend, it should be contacted directly on backend via a DNS pass-through at cloudflare
// because cloudflare will limit the size of files getting POSTed through. Or whatever method calls this one should be directly contacted on backend
P.src.zenodo.deposition.publish = function(id, token, dev) {
  var ref, ref1, ref2, ref3, url;
  // NOTE published things cannot be deteted
  if (id == null) {
    id = (ref = this.params.publish) != null ? ref : this.params.id;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  if (token == null) {
    token = this.params.token;
  }
  if (token == null) {
    token = this.S.dev || dev ? (ref1 = this.S.src.zenodo) != null ? ref1.sandbox : void 0 : (ref2 = this.S.src) != null ? (ref3 = ref2.zenodo) != null ? ref3.token : void 0 : void 0;
  }
  if ((token == null) || (id == null)) {
    return false;
  }
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/deposit/depositions/' + id + '/actions/publish?access_token=' + token;
  return this.fetch(url, {
    method: 'POST'
  });
};

P.src.zenodo.deposition.delete = async function(id, token, dev) {
  var ref, ref1, ref2, url;
  if (id == null) {
    id = (ref = this.params.publish) != null ? ref : this.params.id;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  if (token == null) {
    token = this.params.token;
  }
  if (token == null) {
    token = this.S.dev || dev ? (ref1 = this.S.src.zenodo) != null ? ref1.sandbox : void 0 : (ref2 = this.S.src.zenodo) != null ? ref2.token : void 0;
  }
  if ((token == null) || (id == null)) {
    return false;
  }
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/deposit/depositions/' + id + '?access_token=' + token;
  await this.fetch(url, {
    method: 'DELETE'
  });
  return true;
};

P.blacklist = async function(url) {
  var b, blacklist, i, j, k, len, len1, ref;
  if (url == null) {
    url = this.params.url;
  }
  if (typeof url === 'number') {
    url = url.toString();
  }
  if ((url != null) && (url.length < 4 || url.indexOf('.') === -1)) {
    return false;
  }
  blacklist = [];
  ref = (await this.src.google.sheets("1j1eAnBN-5UoAPLFIFlQCXEnOmXG85RhwT1rKUkrPleI"));
  for (j = 0, len = ref.length; j < len; j++) {
    i = ref[j];
    blacklist.push(i.url.toLowerCase());
  }
  if (url) {
    if (!url.startsWith('http') && url.includes(' ')) {
      return false; // sometimes things like article titles get sent here, no point checking them on the blacklist
    } else {
      for (k = 0, len1 = blacklist.length; k < len1; k++) {
        b = blacklist[k];
        if (url.includes(b.toLowerCase())) {
          return true;
        }
      }
      return false;
    }
  } else {
    return blacklist;
  }
};

P.bug = function() {
  var k, lc, ref, ref1, ref2, ref3, ref4, ref5, subject, text, whoto;
  if (this.params.contact) { // verify humanity
    return '';
  } else {
    whoto = ['help@oa.works'];
    text = '';
    for (k in this.params) {
      text += k + ': ' + JSON.stringify(this.params[k], void 0, 2) + '\n\n';
    }
    subject = '[OAB forms]';
    if (((ref = this.params) != null ? ref.form : void 0) === 'uninstall') { // wrong bug general other
      subject += ' Uninstall notice';
    } else if (((ref1 = this.params) != null ? ref1.form : void 0) === 'wrong') {
      subject += ' Wrong article';
    } else if (((ref2 = this.params) != null ? ref2.form : void 0) === 'bug') {
      subject += ' Bug';
    } else if (((ref3 = this.params) != null ? ref3.form : void 0) === 'general') {
      subject += ' General';
    } else {
      subject += ' Other';
    }
    subject += ' ' + Date.now();
    if ((ref4 = (ref5 = this.params) != null ? ref5.form : void 0) === 'wrong' || ref4 === 'uninstall') {
      whoto.push('help@openaccessbutton.org');
    }
    this.waitUntil(this.mail({
      service: 'openaccessbutton',
      from: 'help@openaccessbutton.org',
      to: whoto,
      subject: subject,
      text: text
    }));
    lc = (this.S.dev ? 'https://dev.openaccessbutton.org' : 'https://openaccessbutton.org') + '/feedback#defaultthanks';
    return {
      status: 302,
      headers: {
        'Content-Type': 'text/plain',
        'Location': lc
      },
      body: lc
    };
  }
};

// https://developers.cloudflare.com/workers/runtime-apis/cache

// this is a cloudflare Cache implementation
// if an alternative has to be used, then write the alternative functions in a 
// different cache implementation, and add a method to swap P.cache to those functions
// yes, this could be done now, but if it never gets used then it's just premature optimisation
// if the cache isn't present this returns undefined and the main API code is written to continue 
// so it's an optional layer anyway
// top level API calls can cache, and any uses of fetch can cache directly too
// other methods can use this cache directly as well if they need to

// NOTE the cloudflare cache is only per region, not global. KV store is global (but only eventually consistent)

// https://community.cloudflare.com/t/how-long-does-the-basic-cloudflare-cdn-cache-things-for/85728
// https://support.cloudflare.com/hc/en-us/articles/218411427-What-does-edge-cache-expire-TTL-mean-#summary-of-page-rules-settings
// https://support.cloudflare.com/hc/en-us/articles/200168276

// https://developers.cloudflare.com/workers/examples/cache-api
P.cache = async function(request, response, age) {
  var ck, cu, h, hp, i, len, ref, rp, rs, url;
  if (typeof age !== 'number') {
    age = typeof this.S.cache === 'number' ? this.S.cache : this.S.dev ? 120 : 43200; // how long should default cache be? here is 2 mins for dev, 12 hours for live
  }
  // age is max age in seconds until removal from cache (note this is not strict, CF could remove for other reasons)
  // request and response needs to be an actual Request and Response objects
  // returns promise wrapping the Response object
  if (this.S.cache === false || this.S.bg === true) { // can change this if a backend cache mechanism is added later (prob not worthwhile)

  } else {
    try {
      if (request == null) {
        request = this.request;
      }
      try {
        url = request.url.toString();
        ref = ['refresh'];
        for (i = 0, len = ref.length; i < len; i++) {
          h = ref[i];
          if (url.indexOf(h + '=') !== -1) {
            hp = new RegExp(h + '=.*?&');
            url = url.replace(hp, '');
          }
          if (url.indexOf('&' + h + '=') !== -1) {
            url = url.split('&' + h + '=')[0];
          }
        }
        cu = new URL(url);
      } catch (error) {}
    } catch (error) {}
    if (request != null) {
      try {
        if (cu == null) {
          cu = new URL(request.url);
        }
        // if request method is POST try changing to GET? and should any headers be removed?
        ck = new Request(cu.toString().replace('?refresh=true', '').replace('&refresh=true', ''), request);
        if ((response == null) || response === '') {
          rs = (await caches.default.match(ck));
          if (response === '') {
            this.waitUntil(caches.default.delete(ck));
          }
          return rs;
        } else {
          // what about things like apikey, refresh and other params, headers not wanted in cache?
          // need to build a request object here, and include a Last-Modified header? or cacheTtl would just let it time out?
          // and what about overriding the method? Always do that here or allow it to be done before here?
          // it has to be a GET for it to be accepted by the CF cache
          // could use just the URL string as key (and then, which query params to consider, if any?)
          // but if using just the URL string how would the refresh timeout be checked?
          response = response.clone(); // body of response can only be read once, so clone it
          rp = new Response(response.body, response);
          rp.headers.append("Cache-Control", "max-age=" + age);
          this.waitUntil(caches.default.put(ck, rp));
        }
      } catch (error) {}
    }
  }
};

P.cache._auth = 'system';

var indexOf = [].indexOf;

if (P.convert == null) {
  P.convert = {};
}

P.convert.json2csv = async function(recs, params) {
  var h, headers, i, j, k, len, len1, newline, nk, quote, rc, rec, records, ref, ref1, ref2, ref3, ref4, ref5, ref6, rs, separator;
  if (recs == null) {
    recs = (ref = this.body) != null ? ref : this.params;
  }
  if (params == null) {
    params = this.params;
  }
  if (params.url) {
    recs = (await this.fetch(params.url));
  }
  if (params.es || ((recs != null ? (ref1 = recs.hits) != null ? ref1.hits : void 0 : void 0) != null)) {
    try {
      recs = recs.hits.hits;
      params.es = true;
    } catch (error) {}
  }
  if (!Array.isArray(recs)) {
    recs = [recs];
  }
  quote = (ref2 = params.quote) != null ? ref2 : '"';
  separator = (ref3 = params.separator) != null ? ref3 : ',';
  newline = (ref4 = params.newline) != null ? ref4 : '\n';
  if (!recs.length) {
    return '';
  } else {
    headers = (ref5 = params.keys) != null ? ref5 : [];
    records = '';
    for (i = 0, len = recs.length; i < len; i++) {
      rec = recs[i];
      if (records.length) {
        records += newline;
      }
      if (params.es !== false && (rec._source || rec.fields)) {
        rs = (ref6 = rec._source) != null ? ref6 : rec.fields;
        rc = {};
// could add controls to alter the order here, or customise key names
        for (nk in rs) {
          if (rc[nk] == null) {
            rc[nk] = rs[nk];
          }
        }
        rec = rc;
      }
      if (params.flatten) {
        rec = (await this.flatten(rec));
      }
      if (params.subset) {
        rec = (await this.dot(rec, params.subset));
      }
      if (!params.keys) {
        for (k in rec) {
          if ((rec[k] != null) && indexOf.call(headers, k) < 0) {
            headers.push(k);
          }
        }
      }
      for (j = 0, len1 = headers.length; j < len1; j++) {
        h = headers[j];
        if (records.length && !records.endsWith(newline)) {
          records += separator;
        }
        records += quote;
        if (rec[h] != null) {
          try {
            if (Array.isArray(rec[h]) && rec[h].length === 1 && Array.isArray(rec[h][0])) {
              rec[h] = rec[h][0];
            }
          } catch (error) {}
          try {
            if (Array.isArray(rec[h]) && rec[h].length && typeof rec[h][0] !== 'object') {
              rec[h] = rec[h].join(',');
            }
          } catch (error) {}
          try {
            if (typeof rec[h] === 'object') {
              rec[h] = JSON.stringify(rec[h]);
            }
          } catch (error) {}
          try {
            if (quote === '"' && rec[h].indexOf(quote) !== -1) { // escape quotes with another quote
              rec[h] = rec[h].replace(/"/g, quote + quote);
            }
          } catch (error) {}
          try {
            //try rec[h] = rec[h].replace /,,/g, separator # TODO change this for a regex of the separator
            rec[h] = rec[h].replace(/\n/g, ' ');
          } catch (error) {}
          try {
            rec[h] = rec[h].replace(/\s\s/g, ' ');
          } catch (error) {}
          try {
            records += rec[h];
          } catch (error) {}
        }
        records += quote;
      }
    }
    return quote + headers.join(quote + separator + quote) + quote + '\n' + records;
  }
};

P.convert.csv2json = async function(csv, params) {
  var h, headers, i, j, len, len1, line, lines, newline, pl, quote, ref, ref1, ref2, ref3, ref4, res, row, separator, vals;
  if (params == null) {
    params = this.params;
  }
  if (csv == null) {
    csv = (ref = this.body) != null ? ref : this.params.csv;
  }
  if (params.url || (typeof csv === 'string' && csv.startsWith('http'))) {
    csv = (await this.fetch((ref1 = params.url) != null ? ref1 : csv));
  }
  res = [];
  if (typeof csv === 'string' && csv.length) {
    quote = (ref2 = params.quote) != null ? ref2 : '"';
    separator = (ref3 = params.separator) != null ? ref3 : ',';
    newline = (ref4 = params.newline) != null ? ref4 : '\n';
    lines = csv.split(newline);
    if (lines.length) {
      headers = lines.shift().split(quote + separator);
      // TODO add handling for flattened object headers eg metadata.author.0.name via a utility for it
      pl = '';
      for (i = 0, len = lines.length; i < len; i++) {
        line = lines[i];
        pl += (pl ? newline : '') + line;
        vals = pl.split(quote + separator);
        if (vals.length === headers.length && (!quote || line.endsWith(quote))) {
          pl = '';
          row = {};
          for (j = 0, len1 = headers.length; j < len1; j++) {
            h = headers[j];
            if (h.startsWith(quote)) {
              h = h.replace(quote, '');
            }
            if (h.endsWith(quote)) {
              h = h.substring(0, h.length - 1);
            }
            if (vals.length) {
              row[h] = vals.shift();
              if (row[h]) {
                if (row[h].startsWith(quote)) {
                  row[h] = row[h].replace(quote, '');
                }
                if (!vals.length && row[h].endsWith(quote)) { // strip the end quote from the last one
                  row[h] = row[h].substring(0, row[h].length - 1);
                }
                try {
                  row[h] = JSON.parse(row[h]);
                } catch (error) {}
              }
            }
          }
          res.push(row);
        }
      }
    }
  }
  return res;
};

P.convert.csv2html = async function(csv, params) {
  var header, headers, i, j, len, len1, len2, line, lines, ln, m, newline, quote, ref, ref1, ref2, ref3, res, separator, v, vn;
  if (csv == null) {
    csv = (ref = this.body) != null ? ref : this.params.csv;
  }
  if (params == null) {
    params = this.params;
  }
  if (params.url || (typeof csv === 'string' && csv.startsWith('http'))) {
    csv = (await this.fetch((ref1 = params.url) != null ? ref1 : csv));
  }
  quote = '"';
  separator = ',';
  newline = '\n';
  csv = csv.replace(/,,/g, separator + quote + quote + separator); // TODO change this for a regex of the separator
  res = '<style>table.paradigm tr:nth-child(even) {background: #eee}table.paradigm tr:nth-child(odd) {background: #fff}</style>\n';
  res += '<table class="paradigm" style="border-collapse: collapse;">\n';
  if (typeof csv === 'string' && csv.length) {
    lines = csv.split(newline);
    if (lines.length) {
      res += '<thead><tr>';
      headers = lines.shift();
      ln = 0;
      ref2 = headers.split(quote + separator + quote);
      for (i = 0, len = ref2.length; i < len; i++) {
        header = ref2[i];
        res += '<th style="padding:2px; border:1px solid #ccc;">' + header.replace(/"/g, '') + '</th>';
        ln += 1;
      }
      res += '</tr></thead>\n<tbody>\n';
      for (j = 0, len1 = lines.length; j < len1; j++) {
        line = lines[j];
        res += '<tr>';
        while (line.indexOf(',"",') !== -1) {
          line = line.replace(',"",', ',"XXX_EMPTY_XXX",');
        }
        while (line.startsWith('"",')) {
          line = line.replace('"",', '"XXX_EMPTY_XXX",');
        }
        while (line.endsWith(',""')) {
          line = line.slice(0, line.length - 3);
        }
        line = line.replace(/""/g, 'XXX_QUOTER_GOES_HERE_XXX'); // TODO change this for a regex of whatever the quote char is
        vn = 0;
        ref3 = line.split(quote + separator + quote);
        for (m = 0, len2 = ref3.length; m < len2; m++) {
          v = ref3[m];
          vn += 1;
          res += '<td style="padding:2px; border:1px solid #ccc;vertical-align:text-top;">';
          v = v.replace(/^"/, '').replace(/"$/, '');
          if (v !== 'XXX_EMPTY_XXX') {
            if (v.indexOf('{') === 0 || v.indexOf('[') === 0) {
              res += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;">...</a><div style="display:none;">';
              res += (await this.convert.json2html(JSON.parse(v.replace(/XXX_QUOTER_GOES_HERE_XXX/g, quote))));
              res += '</div>';
            } else {
              res += v.replace(/XXX_QUOTER_GOES_HERE_XXX/g, quote); // .replace(/\</g, '&lt;').replace(/\>/g, '&gt;')
            }
          }
          res += '</td>'; // add a regex replace of the separator, avoiding escaped instances
        }
        while (vn < ln) {
          res += '<td style="padding:2px; border:1px solid #ccc;vertical-align:text-top;"></td>';
          vn += 1;
        }
        res += '</tr>\n';
      }
      res += '</tbody>\n';
    }
  }
  return res + '</table>';
};

P.convert.json2html = async function(recs, params) {
  var _draw, i, j, key, len, len1, part, parts, pt, ref, ref1, ref2, res;
  if (recs == null) {
    recs = (ref = this.body) != null ? ref : this.params;
  }
  if (params == null) {
    params = this.params;
  }
  if (params.url) {
    recs = (await this.fetch(url));
  }
  if (params.new) {
    if (params.edit == null) {
      params.edit = true;
    }
    recs = {};
    ref1 = (await this.index.keys(this.route.replace(/\//g, '_')));
    for (i = 0, len = ref1.length; i < len; i++) {
      key = ref1[i];
      recs[key] = ''; // could also get mapping types from here, and need to handle nesting eventually
    }
  }
  if (params.subset && !Array.isArray(recs)) {
    parts = params.subset.split('.');
    while (part = parts.shift()) {
      if (typeof recs === 'object' && !Array.isArray(recs) && (recs[part] != null)) {
        recs = recs[part];
      } else {
        break;
      }
    }
  }
  if (Array.isArray(recs) || (((recs != null ? (ref2 = recs.hits) != null ? ref2.hits : void 0 : void 0) != null) && params.es !== false)) {
    if (parts != null) {
      params.subset = parts.join('.');
    }
    return this.convert.csv2html((await this.convert.json2csv(recs, params)));
  } else {
    res = '<div>';
    if (params.flatten) {
      recs = (await this.flatten(recs));
      res += '<input type="hidden" id="options_flatten" value="true">';
    }
    if (params.subset) {
      if (parts.length) {
        for (j = 0, len1 = parts.length; j < len1; j++) {
          pt = parts[j];
          recs = recs[pt];
        }
      }
      res += '<h3>' + params.subset + ':</h3>';
      res += '<input type="hidden" id="options_subset" value="' + params.subset + '">';
    }
    _draw = (rec) => {
      var k, len2, len3, m, n, ok, pk, ref3, ref4, results, rks;
      if (params.edit) { // just for rscvd demo for now
        if (rec.comments == null) {
          rec.comments = '';
        }
      }
      if (params.keys) {
        ref3 = params.keys;
        for (m = 0, len2 = ref3.length; m < len2; m++) {
          pk = ref3[m];
          if (rec[pk] == null) {
            rec[pk] = '';
          }
        }
      }
      results = [];
      for (k in rec) {
        try {
          if (Array.isArray(rec[k]) && rec[k].length === 1 && Array.isArray(rec[k][0])) {
            // for example crossref date-parts are an array in an array, pretty useless, so dump the external array
            rec[k] = rec[k][0];
          }
        } catch (error) {}
        if ((rec[k] != null) && (!Array.isArray(rec[k]) || rec[k].length) && (!params.keys || indexOf.call(params.keys, k) >= 0)) {
          res += '<div style="clear:both; ' + (!params.edit ? 'border:1px solid #ccc; ' : '') + 'margin:-1px 0px;"><div style="float:left;width: 150px; overflow: scroll;"><b><p>' + k + '</p></b></div>';
          res += '<div style="float:left;">';
          res += params.edit ? '<textarea class="PForm" id="' + k + '" style="min-height:80px;width:100%;margin-bottom:5px;">' : '';
          if (Array.isArray(rec[k])) {
            if (typeof rec[k][0] === 'object') {
              ref4 = rec[k];
              for (n = 0, len3 = ref4.length; n < len3; n++) {
                ok = ref4[n];
                _draw(ok);
              }
            } else {
              try {
                rks = rec[k].join(', ');
              } catch (error) {
                try {
                  rks = JSON.stringify(rec[k]);
                } catch (error) {
                  rks = rec[k];
                }
              }
              try {
                res += (params.edit ? '' : '<p>') + rks + (params.edit ? '' : '</p>');
              } catch (error) {}
            }
          } else if (typeof rec[k] === 'object') {
            _draw(rec[k]);
          } else {
            res += (params.edit ? '' : '<p>') + rec[k] + (params.edit ? '' : '</p>');
          }
          res += params.edit ? '</textarea>' : '';
          results.push(res += '</div></div>');
        } else {
          results.push(void 0);
        }
      }
      return results;
    };
    _draw(recs);
    res += '</div>';
    return res;
  }
};

P.convert.json2txt = async function(content) {
  var _extract, ref, strings;
  if (content == null) {
    content = (ref = this.body) != null ? ref : this.params;
  }
  if (this.params.url) {
    content = (await this.fetch(this.params.url));
  }
  strings = [];
  _extract = async function(content) {
    var c, i, len, results, results1;
    if (Array.isArray(content)) {
      results = [];
      for (i = 0, len = content.length; i < len; i++) {
        c = content[i];
        results.push((await _extract(c)));
      }
      return results;
    } else if (typeof content === 'object') {
      results1 = [];
      for (c in content) {
        results1.push((await _extract(content[c])));
      }
      return results1;
    } else if (content) {
      return strings.push(content);
    }
  };
  await _extract(content);
  return strings.join(' ');
};

P.convert._hexMatch = {
  '0': '0000',
  '1': '0001',
  '2': '0010',
  '3': '0011',
  '4': '0100',
  '5': '0101',
  '6': '0110',
  '7': '0111',
  '8': '1000',
  '9': '1001',
  'a': '1010',
  'b': '1011',
  'c': '1100',
  'd': '1101',
  'e': '1110',
  'f': '1111'
};

P.convert.hex2bin = function(ls) {
  var i, l, len, ref, res;
  res = [];
  ref = (!Array.isArray(ls) ? [ls] : ls);
  for (i = 0, len = ref.length; i < len; i++) {
    l = ref[i];
    res.push(P.convert._hexMatch[l.toLowerCase()]);
  }
  return res.join('');
};

P.convert.bin2hex = function(ls) {
  var els, hm, i, k, l, len, pr, res, sls;
  // this needs work...
  if (!Array.isArray(ls)) {
    els = [];
    sls = ls.split('');
    pr = '';
    while (sls.length) {
      pr += sls.shift();
      if (pr.length === 4) {
        els.push(pr);
        pr = '';
      }
    }
    ls = els;
  }
  res = [];
  hm = {};
  for (k in P.convert._hexMatch) {
    hm[P.convert._hexMatch[k]] = k;
  }
  for (i = 0, len = ls.length; i < len; i++) {
    l = ls[i];
    res.push('0x' + hm[l]);
  }
  return new Buffer(res).toString();
};

P.convert.buf2bin = async function(buf) {
  var c, ret;
  if (Buffer.isBuffer(buf)) {
    buf = buf.toString('hex');
  }
  buf = buf.replace(/^0x/, '');
  ret = '';
  c = 0;
  while (c < buf.length) {
    ret += (await P.convert.hex2bin(buf[c]));
    c++;
  }
  return ret;
};

P.convert.stream2txt = function(stream) {
  var chunks;
  chunks = [];
  return new Promise((resolve, reject) => {
    stream.on('data', (chunk) => {
      return chunks.push(Buffer.from(chunk));
    });
    stream.on('error', (err) => {
      return reject(err);
    });
    return stream.on('end', () => {
      return resolve(Buffer.concat(chunks).toString('utf8'));
    });
  });
};

P.convert.xml2json = async function(x) {
  var c, elem, ending, i, k, len, meta, p, pointer, prv, pv, ref, ref1, res, starting, v;
  // TODO parse from buffer (file on disk or stream from url)
  // allow CDATA e.g <![CDATA[<p>your html here</p>]]>
  // track embedded and unescaped html tags e.g https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pmc&id=PMC9206389
  if (x == null) {
    x = (ref = this.params.xml2json) != null ? ref : this.params.url;
  }
  res = {};
  if (typeof x === 'string') {
    if (x.startsWith('http')) {
      x = (await this.fetch(x));
    }
    elem = '';
    pointer = '';
    starting = false;
    ending = false;
    while (c = x[0]) {
      x = x.slice(1);
      if ((c !== '\uFEFF' && c !== '\t' && c !== '\r' && c !== '\n') && (c !== ' ' || (elem.length && !elem.endsWith('>')))) {
        if (elem === '<' && (c !== '/' && c !== '?' && c !== '!')) { // ignore xml and doctype statements - can add later if any use for them is found
          starting = true;
        }
        elem += c;
        if ((elem.endsWith('</') && elem.split('</').length - 1 === elem.split('>').length) || (elem.endsWith('/>') && !elem.split('/>')[0].includes('>'))) {
          ending = true;
        }
        if (c === '>') {
          console.log(pointer);
          if (ending) {
            ending = false;
            elem = elem.split('</')[0];
            if (elem !== '') {
              if (pv = (await this.dot(res, pointer, void 0, void 0, true))) {
                if (Array.isArray(pv)) {
                  if (!pv.length) {
                    pv = [{}];
                  }
                  if (pv[pv.length - 1].$ != null) {
                    if (!Array.isArray(pv[pv.length - 1].$)) {
                      pv[pv.length - 1].$ = [pv[pv.length - 1].$];
                    }
                    pv[pv.length - 1].$.push(elem);
                  } else {
                    pv[pv.length - 1].$ = elem;
                  }
                } else {
                  pv.$ = elem;
                }
                elem = pv;
              } else {
                elem = {
                  $: elem
                };
                try {
                  if (prv = (await this.dot(res, pointer.slice(0, pointer.lastIndexOf('.')), void 0, void 0, true))) {
                    elem._ = prv[pointer.split('.').pop()]._;
                  }
                } catch (error) {}
              }
              if (typeof elem === 'object' && (elem._ == null) && (elem.$ != null)) {
                elem = elem.$;
              }
              await this.dot(res, pointer, elem, void 0, true);
            }
            pointer = pointer.includes('.') ? pointer.slice(0, pointer.lastIndexOf('.')) : '';
          } else if (starting) {
            starting = false;
            meta = {};
            ref1 = elem.replace('<', '').replace('>', '').split(' ');
            for (i = 0, len = ref1.length; i < len; i++) {
              p = ref1[i];
              if (!p.includes('=')) {
                pointer += (pointer && !pointer.endsWith('.') ? '.' : '') + p;
              } else if (p.length) {
                [k, v] = p.split('=');
                meta[k.trim().replace(/"/g, '')] = v.trim().replace(/"/g, '');
              }
            }
            if (pv = (await this.dot(res, pointer, void 0, void 0, true))) {
              if (!Array.isArray(pv)) {
                pv = [pv];
              }
              pv.push(JSON.stringify(meta) !== '{}' ? {
                _: meta
              } : {});
              await this.dot(res, pointer, pv, void 0, true);
            } else if (JSON.stringify(meta) !== '{}') {
              await this.dot(res, pointer + '._', meta, void 0, true);
            }
          }
          elem = '';
        }
      }
    }
  }
  return res;
};

P.dateparts = async function(d) {
  var o, p, part, parts, ref, ref1, ref2, ref3, ref4, ref5, ref6;
  o = {};
  if (d == null) {
    d = (ref = this.params.dateparts) != null ? ref : o.date;
  }
  try {
    if (typeof d === 'object') {
      for (p in d) {
        o[p] = d[p];
      }
      d = (ref1 = o.date) != null ? ref1 : '';
    } else if (d == null) {
      for (p in params) {
        if (o[p] == null) {
          o[p] = this.params[p];
        }
      }
      d = (ref2 = o.date) != null ? ref2 : '';
    }
    // at least year must be present. year can be first or last or singular but not middle. 
    // If only one part assume year. If only two assume month and year.
    if (typeof d === 'number' || (typeof d === 'string' && !d.includes(' ') && !d.includes('/') && !d.includes('-') && d.length > 8 && !d.includes('T'))) {
      d = (await this.date(d));
    }
    if (d.includes('T') && d.includes('-')) {
      d = d.split('T')[0];
    }
    d = d.trim().toLowerCase().replace(', ', ' ').replace(' of ', '').replace('st ', ' ').replace('nd ', ' ').replace('rd ', ' ').replace('th ', ' ');
    // NOTE august could now be augu but going to reduce to first three chars anyway
    d = d.replace(/-/g, ' ').replace(/\//g, ' ');
    if (d.includes(' ')) { // assume some kind of 1 xxx... xxxx format
      for (p in parts = d.split(' ')) {
        part = parts[p];
        if (part.length >= 3) { // month or full year
          if (isNaN(parseInt(part))) {
            o.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf(part.toLowerCase().substr(0, 3));
            o.month = typeof o.month === 'number' && o.month >= 0 ? o.month + 1 : '';
          } else {
            o.year = part;
          }
        } else if (parseInt(part) < 13 && (parts.length === 2 || (parts.length === 3 && p === '1'))) {
          o.month = part;
        } else if (parts.length === 1) {
          o.year = part;
        } else {
          o.day = part;
        }
      }
    }
    o.day = ((ref3 = o.day) != null ? ref3 : '01').toString();
    if (o.day.length === 1) {
      o.day = '0' + o.day;
    }
    if (typeof o.month === 'string' && o.month.length && isNaN(parseInt(o.month))) {
      o.month = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf(o.month.toLowerCase().substr(0, 3));
      o.month = typeof o.month === 'number' && o.month >= 0 ? o.month + 1 : '';
    }
    o.month = ((ref4 = o.month) != null ? ref4 : '01').toString();
    if (o.month.length === 1) {
      o.month = '0' + o.month;
    }
    o.year = o.year.toString();
    if (o.year.length === 2) {
      o.year = (parseInt(o.year) < 30 ? '20' : '19' + o.year);
    }
    if (o.day === '31' && ((ref5 = o.month) === '04' || ref5 === '06' || ref5 === '09' || ref5 === '11')) { // for example pubmed xml was seen to have dates of 31st April, etc
      o.day = '30';
    }
    if (o.month === '02' && (((ref6 = o.day) === '30' || ref6 === '31') || (o.day === '29' && parseInt(o.year) % 4))) {
      o.day = '28';
    }
    o.date = o.year + '-' + o.month + '-' + o.day; // allow for formatting option to be passed in?
    try {
      o.timestamp = (await this.epoch(o.date));
    } catch (error) {}
  } catch (error) {}
  return o;
};

P.dateparts._cache = false;

P.date = function(rt, timed, secs = true, ms = true) {
  var k, pts, ref, ref1, ret;
  if (rt == null) {
    rt = (ref = this.params.date) != null ? ref : Date.now();
  }
  if (timed == null) {
    timed = this.params.time;
  }
  if (typeof rt === 'number' || (typeof rt === 'string' && !rt.includes(' ') && !rt.includes('/') && !rt.includes('-') && rt.length > 8 && !rt.includes('T'))) {
    try {
      ret = new Date(parseInt(rt));
      ret = ret.toISOString();
      if (timed) {
        if (!secs) {
          ret = ret.split(':').slice(0, -1).join(':').replace('T', ' ');
        } else if (!ms) {
          ret = ret.split('.')[0].replace('T', ' ');
        }
      } else {
        ret = ret.split('T')[0];
      }
      return ret;
    } catch (error) {}
  }
  try {
    if (typeof rt === 'number') {
      rt = rt.toString();
    }
    if (Array.isArray(rt) && rt.length === 1 && Array.isArray(rt[0])) {
      rt = rt[0];
    }
    if (typeof rt !== 'string') {
      try {
        for (k in rt) {
          if ((ref1 = typeof rt[k]) !== 'number' && ref1 !== 'string') {
            rt[k] = '01';
          }
        }
        rt = rt.join('-');
      } catch (error) {}
    }
    rt = decodeURIComponent(rt);
    if (rt.includes('T')) {
      rt = rt.split('T')[0];
    }
    rt = rt.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace(/-(\d)$/, "-0$1");
    if (!rt.includes('-')) {
      rt += '-01-01';
    }
    if (rt.split('-').length !== 3) {
      rt += '-01';
    }
    pts = rt.split('-');
    if (pts.length !== 3) {
      rt = void 0;
    }
    if (pts[0].length < pts[2].length) {
      rt = pts.reverse().join('-');
    }
    return rt;
  } catch (error) {

  }
};

P.date._cache = false;

P.datetime = function(secs, ms) {
  var ref, ref1;
  return this.date(this.params.datetime, (ref = this.params.time) != null ? ref : true, (ref1 = secs != null ? secs : this.params.secs) != null ? ref1 : this.params.s, ms != null ? ms : this.params.ms);
};

P.datetime._cache = false;

P.epoch = function(epoch) {
  var add, end, eps, ref, start, subtract;
  if (epoch == null) {
    epoch = this.params.epoch;
  }
  if (typeof epoch === 'number') {
    epoch = epoch.toString();
  }
  if (typeof epoch === 'string' && epoch.includes('/')) {
    eps = epoch.split('/');
    if (eps.length === 3 && eps[2].length === 4) {
      eps.reverse();
    }
    epoch = eps.join('-');
  }
  if (!epoch) {
    return Date.now();
  } else if (epoch.startsWith('+') || epoch.startsWith('-') || (epoch.split('+').length === 2 && epoch.split('+')[0].length > 4) || (epoch.split('-').length === 2 && epoch.split('-')[0].length > 4)) {
    if (epoch.startsWith('+') || epoch.startsWith('-')) {
      epoch = Date.now() + epoch;
    }
    if (epoch.includes('+')) {
      [epoch, add] = epoch.replace('/', '').split('+');
      return (parseInt(epoch) + parseInt(add)).toString();
    } else if (epoch.includes('-')) {
      [epoch, subtract] = epoch.replace('/', '').split('-');
      return (parseInt(epoch) - parseInt(subtract)).toString();
    }
  } else if (epoch.length > 8 && !epoch.includes('-') && !isNaN(parseInt(epoch))) {
    return this.date(epoch, (ref = this.params.time) != null ? ref : true);
  } else {
    if (epoch.length === 4) {
      epoch += '-01';
    }
    if (epoch.split('-').length < 3) {
      epoch += '-01';
    }
    if (!epoch.includes('T')) {
      epoch += 'T';
    }
    if (!epoch.includes(':')) {
      epoch += '00:00';
    }
    if (epoch.split(':').length < 3) {
      epoch += ':00';
    }
    if (!epoch.includes('.')) {
      epoch += '.';
    }
    [start, end] = epoch.split('.');
    end = end.replace('Z', '').replace('z', '');
    while (end.length < 3) {
      end += '0';
    }
    if (!end.includes('Z')) {
      end += 'Z';
    }
    return new Date(start + '.' + end).valueOf();
  }
};

P.epoch._cache = false;

import {
  customAlphabet
} from 'nanoid';

P.uid = function(length) {
  var nanoid, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rs;
  if (length == null) {
    length = this.fn === 'uid' ? (ref = (ref1 = (ref2 = (ref3 = this != null ? (ref4 = this.params) != null ? ref4.len : void 0 : void 0) != null ? ref3 : this != null ? (ref5 = this.params) != null ? ref5.length : void 0 : void 0) != null ? ref2 : this != null ? (ref6 = this.params) != null ? ref6.size : void 0 : void 0) != null ? ref1 : this != null ? (ref7 = this.params) != null ? ref7.uid : void 0 : void 0) != null ? ref : 21 : 21;
  }
  if (typeof length === 'string') {
    rs = parseInt(length);
    length = isNaN(rs) ? void 0 : rs;
  }
  // have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  // are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  // will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  // without uppercases it's only a 1% chance if generating 1000 IDs per second for 131000 years.
  nanoid = customAlphabet((ref8 = this != null ? (ref9 = this.params) != null ? ref9.alphabet : void 0 : void 0) != null ? ref8 : '0123456789abcdefghijklmnopqrstuvwxyz', length);
  return nanoid();
};

P.uid._cache = false;

P.encrypt = async function(content) {
  var cipher, encrypted, ref, ref1, ref2, ref3, ref4;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = (ref3 = this.params.encrypt) != null ? ref3 : this.params.content) != null ? ref2 : this.params.q) != null ? ref1 : this.params) != null ? ref : this.body;
  }
  try {
    if (this.params.url) {
      content = (await this.fetch(this.params.url));
    }
  } catch (error) {}
  if (typeof content !== 'string') {
    content = JSON.stringify(content);
  }
  cipher = crypto.createCipheriv('aes-256-ctr', this.S.encrypt.salt, (ref4 = this.params.iv) != null ? ref4 : this.S.encrypt.iv);
  encrypted = Buffer.concat([cipher.update(content), cipher.final()]);
  return encrypted.toString('hex');
};

P.encrypt._cache = false;

P.encrypt._bg = true; // need to check but presumably createCipheriv and createDecipheriv won't be available on CF worker with crypto.subtle

P.decrypt = async function(content) {
  var decipher, decrypted, iv, ref, ref1, ref2, ref3, ref4;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = (ref3 = this.params.decrypt) != null ? ref3 : this.params.content) != null ? ref2 : this.params.q) != null ? ref1 : this.params) != null ? ref : this.body;
  }
  try {
    if (this.params.url) {
      content = (await this.fetch(this.params.url));
    }
  } catch (error) {}
  if (typeof content === 'object') {
    iv = content.iv;
    content = content.content;
  } else {
    iv = (ref4 = this.params.iv) != null ? ref4 : this.S.encrypt.iv;
  }
  if (typeof content !== 'string') {
    content = JSON.stringify(content);
  }
  //decipher = crypto.createDecipheriv 'aes-256-ctr', @S.encrypt.salt, iv
  //decrypted = Buffer.concat [decipher.update(content), decipher.final()]
  decipher = crypto.createDecipheriv('aes-256-ctr', this.S.encrypt.salt, iv);
  decrypted = Buffer.concat([decipher.update(Buffer.from(content, 'hex')), decipher.final()]);
  return decrypted.toString();
};

P.decrypt._cache = false;

P.decrypt._bg = true;

P.decrypt._auth = '@oa.works';

P.hash = async function(content) {
  var arr, b, buf, j, len, parts, ref, ref1, ref2, ref3;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = (ref3 = this.params.hash) != null ? ref3 : this.params.content) != null ? ref2 : this.params.q) != null ? ref1 : this.params) != null ? ref : this.body;
  }
  try {
    if (this.params.url) {
      content = (await this.fetch(this.params.url));
    }
  } catch (error) {}
  if (typeof content !== 'string') {
    content = JSON.stringify(content);
  }
  try {
    content = new TextEncoder().encode(content);
    buf = (await crypto.subtle.digest("SHA-256", content));
    arr = new Uint8Array(buf);
    parts = [];
    for (j = 0, len = arr.length; j < len; j++) {
      b = arr[j];
      parts.push(('00' + b.toString(16)).slice(-2));
    }
    return parts.join('');
  } catch (error) {
    // the above works on CF worker, but crypto.subtle needs to be replaced with standard crypto module on backend
    // crypto is imported by the server-side main api file
    return crypto.createHash('sha256').update(content, 'utf8').digest('hex'); // md5 would be preferable but web crypto /subtle doesn't support md5
  }
};

P.hashcode = function(content) { // java hash code style
  var hash, i, ref, ref1, ref2, ref3;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = (ref3 = this.params.hashcode) != null ? ref3 : this.params.content) != null ? ref2 : this.params.q) != null ? ref1 : this.params) != null ? ref : this.body;
  }
  if (typeof content !== 'string') {
    content = JSON.stringify(content);
  }
  hash = 0;
  i = 0;
  while (i < content.length) {
    hash = ((hash << 5) - hash) + content.charCodeAt(i);
    hash &= hash;
    i++;
  }
  return hash;
};

P.hashhex = function(content) {
  var n;
  if (content == null) {
    content = this.params.hashhex;
  }
  n = this.hashcode(content);
  if (n < 0) {
    n = 0xFFFFFFFF + n + 1;
  }
  return n.toString(16);
};

P.shorthash = function(content, alphabet) { // as learnt from something I once googled, but can't remember what
  var al, hash, ref, ref1, ref2, ref3, result, spare;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = (ref3 = this.params.shorthash) != null ? ref3 : this.params.content) != null ? ref2 : this.params.q) != null ? ref1 : this.params) != null ? ref : this.body;
  }
  if (typeof content !== 'string') {
    content = JSON.stringify(content);
  }
  hash = this.hashcode(content);
  if (!alphabet) {
    alphabet = '0123456789abcdefghijklmnoqrstuvwxyz'; // keep one char from the usable range to replace negative signs on hashcodes
    spare = 'p';
  } else {
    spare = alphabet.substring(0, 1);
    alphabet = alphabet.replace(spare, '');
  }
  al = alphabet.length;
  result = hash < 0 ? spare : '';
  hash = Math.abs(hash);
  while (hash >= al) {
    result += alphabet[hash % al];
    hash = Math.floor(hash / al);
  }
  return result + (hash > 0 ? alphabet[hash] : '');
};

// https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

// NOTE TODO for getting certain file content, adding encoding: null to headers (or correct encoding required) can be helpful
P.fetch = async function(url, params) {
  var _f, av, base, ct, err, fk, fll, flo, i, j, k, l, len, len1, len2, len3, len4, m, n, name, nu, p, po, ppt, pt, pts, qp, ref, ref1, ref10, ref11, ref12, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, v;
  if ((url == null) && (params == null)) {
    try {
      params = this.copy(this.params);
    } catch (error) {}
  }
  if (typeof url === 'object' && (params == null)) {
    params = url;
    url = params.url;
  }
  if (params == null) {
    params = {};
  }
  if (typeof params === 'number') {
    params = {
      cache: params
    };
  }
  if (typeof params.cache === 'number') { // https://developers.cloudflare.com/workers/examples/cache-using-fetch
    if (params.cf == null) {
      params.cf = {
        cacheEverything: true
      };
    }
    params.cf.cacheTtl = params.cache;
    delete params.cache;
  }
  if (!url && params.url) {
    url = params.url;
    delete params.url;
  }
  if (params.bg === true && typeof S.bg === 'string') {
    params.url = url; // send to bg (e.g. for proxying)
    url = S.bg + '/fetch';
    delete params.bg;
  }
  if (params.username && params.password) {
    params.auth = params.username + ':' + params.password;
    delete params.username;
    delete params.password;
  }
  if (url.split('?')[0].includes('@') && url.includes(':') && url.split('//')[1].split('?')[0].split('@')[0].includes(':')) {
    params.auth = url.split('//')[1].split('@')[0];
    url = url.replace(params.auth + '@', '');
  }
  if (params.auth) {
    if (params.headers == null) {
      params.headers = {};
    }
    params.headers.Authorization = 'Basic ' + Buffer.from(params.auth).toString('base64');
    delete params.auth;
  }
  ref = ['data', 'content', 'json'];
  for (i = 0, len = ref.length; i < len; i++) {
    ct = ref[i];
    if (params[ct] != null) {
      params.body = params[ct];
      delete params[ct];
    }
  }
  if (params.attachment == null) {
    params.attachment = params.attachments;
  }
  if (params.file == null) {
    params.file = params.attachment;
  }
  if (params.file != null) {
    if (params.headers == null) {
      params.headers = {};
    }
    if ((params.body != null) && (params.form == null)) {
      //params.headers['Content-Type'] = 'multipart/form-data'
      params.form = params.body;
    }
    params.body = new FormData();
    if (!Array.isArray(params.file)) {
      if (typeof params.file === 'object' && (params.file.file != null)) {
        fll = [
          {
            file: params.file.file,
            filename: (ref1 = (ref2 = params.file.filename) != null ? ref2 : params.file.name) != null ? ref1 : params.filename
          }
        ];
      } else {
        fll = [
          {
            file: params.file,
            filename: params.filename
          }
        ];
      }
      params.file = fll;
    }
    ref3 = params.file;
    for (j = 0, len1 = ref3.length; j < len1; j++) {
      flo = ref3[j];
      if (((flo != null ? flo.file : void 0) != null) || ((flo != null ? flo.data : void 0) != null)) {
        params.body.append((params.attachment != null ? 'attachment' : 'file'), (ref4 = flo.file) != null ? ref4 : flo.data, (ref5 = (ref6 = (ref7 = flo.filename) != null ? ref7 : flo.name) != null ? ref6 : params.filename) != null ? ref5 : 'file');
      }
    }
    delete params.filename;
    if (params.method == null) {
      params.method = 'POST';
    }
  } else if (params.body != null) {
    if (params.headers == null) {
      params.headers = {};
    }
    if ((params.headers['Content-Type'] == null) && (params.headers['content-type'] == null)) {
      params.headers['Content-Type'] = typeof params.body === 'object' ? 'application/json' : 'text/plain';
    }
    if ((ref8 = typeof params.body) === 'object' || ref8 === 'boolean' || ref8 === 'number') { // or just everything?
      params.body = JSON.stringify(params.body);
    }
    if (params.method == null) {
      params.method = 'POST';
    }
  }
  if (params.form != null) {
    if (params.file != null) {
      if (typeof params.form === 'object') {
        for (fk in params.form) {
          ref9 = (Array.isArray(params.form[fk]) ? params.form[fk] : [params.form[fk]]);
          for (l = 0, len2 = ref9.length; l < len2; l++) {
            av = ref9[l];
            params.body.append(fk, typeof av === 'object' ? JSON.stringify(av) : av);
          }
        }
      }
    } else {
      if (params.headers == null) {
        params.headers = {};
      }
      if ((params.headers['Content-Type'] == null) && (params.headers['content-type'] == null)) {
        params.headers['Content-Type'] = 'application/x-www-form-urlencoded';
      }
      if (typeof params.form === 'object') {
        po = ''; // params object to string x-www-form-urlencoded
        for (p in params.form) {
          if (po !== '') {
            po += '&';
          }
          ref10 = (Array.isArray(params.form[p]) ? params.form[p] : [params.form[p]]);
          for (m = 0, len3 = ref10.length; m < len3; m++) {
            ppt = ref10[m];
            if (ppt != null) {
              if (!po.endsWith('&')) {
                po += '&';
              }
              po += p + '=' + encodeURIComponent((typeof ppt === 'object' ? JSON.stringify(ppt) : ppt));
            }
          }
        }
        params.form = po;
      }
      params.body = params.form;
    }
    delete params.form;
    if (params.method == null) {
      params.method = 'POST';
    }
  }
  delete params.file;
  delete params.attachment;
  delete params.attachments;
  if (typeof url !== 'string') {

  } else {
    if (!url.startsWith('http:') && url.includes('localhost')) { // allow local https connections on backend server without check cert
      try {
        if (params.agent == null) {
          params.agent = new https.Agent({
            rejectUnauthorized: false
          });
        }
      } catch (error) {}
    }
    if (url.includes('?')) {
      pts = url.split('?');
      nu = pts.shift() + '?';
      ref11 = pts.join('?').split('&');
      for (n = 0, len4 = ref11.length; n < len4; n++) {
        qp = ref11[n];
        if (!nu.endsWith('?')) {
          nu += '&';
        }
        [k, v] = qp.split('=');
        if (v == null) {
          v = '';
        }
        if (k) {
          nu += encodeURIComponent(k) + (v ? '=' + (v.includes('%') ? v : encodeURIComponent(v)) : '');
        }
      }
      url = nu;
    }
    if (params.params && JSON.stringify(params.params) !== '{}') {
      if (!url.includes('?')) {
        url += '?';
      }
      ref12 = params.params;
      for (k in ref12) {
        v = ref12[k];
        if (!url.endsWith('&') && !url.endsWith('?')) {
          url += '&';
        }
        if (k) {
          url += encodeURIComponent(k) + '=' + encodeURIComponent(typeof v === 'object' ? JSON.stringify(v) : v);
        }
      }
      delete params.params;
    }
    if (S.system && ((typeof S.bg === 'string' && url.startsWith(S.bg)) || (typeof S.async === 'string' && url.startsWith(S.async)) || (typeof S.kv === 'string' && S.kv.startsWith('http') && url.startsWith(S.kv)))) {
      if (params.headers == null) {
        params.headers = {};
      }
      if ((base = params.headers)[name = 'x-' + S.name.toLowerCase() + '-system'] == null) {
        base[name] = S.system;
      }
      if (!params.headers.Authorization && !params.headers.authorization && !params.headers['x-apikey'] && this.user) {
        params.headers['x-apikey'] = this.user.apikey;
      }
    }
    _f = async() => {
      var buff, hd, len5, o, r, ref13, ref14, ref15, response;
      if (params.stream) {
        delete params.stream;
        // return full response with status, ok, redirected, bodyUsed, size, timeout url, statusText, clone, body, arrayBuffer, blob, json, text, buffer, textConverted 
        return fetch(url, params); // (and response body can be used as stream if desired, or can await text() or json() etc
      } else {
        //console.log(url) if S?.bg is true # extra for finding out unexplained timeout issue
        buff = false;
        if (params.buffer) {
          buff = true;
          delete params.buffer;
        }
        response = (await fetch(url, params));
        try {
          if ((!url.includes('localhost') || ((ref13 = response.status) !== 200 && ref13 !== 404)) && S.dev && S.bg === true) { // status code can be found here
            console.log(response.status + ' ' + url);
          }
          // content type could be read from: response.headers.get('content-type')
          if (params.verbose) {
            if (response.status > 300) {
              console.log(response.body);
            }
            console.log(response.status + ' ' + url);
          }
        } catch (error) {
          console.log('Error logging to console for fetch');
          console.log(response);
        }
        if (buff) {
          r = (await response.buffer());
        } else if ((ref14 = params.method) === 'HEAD') {
          r = {
            status: response.status
          };
          ref15 = [...response.headers];
          for (o = 0, len5 = ref15.length; o < len5; o++) {
            hd = ref15[o];
            r[hd[0]] = hd[1];
          }
        } else {
          try {
            r = (await response.text()); // await response.json() can get json direct, but it will error if the wrong sort of data is provided, so just try it here
          } catch (error) {}
          try {
            if (typeof r === 'string' && (r.startsWith('{') || r.startsWith('['))) {
              r = JSON.parse(r);
            }
          } catch (error) {}
        }
        if (response.status === 404) {

        } else if (response.status >= 400) {
          if (S.dev && S.bg === true) {
            console.log(params, JSON.stringify(r), 'FETCH ERROR', response.status);
          }
          return {
            status: response.status
          };
        } else {
          return r;
        }
      }
    };
    try {
      if (params.timeout && ((this != null ? this._timeout : void 0) != null)) {
        pt = params.timeout === true ? 30000 : params.timeout;
        delete params.timeout;
        res = (await this._timeout(pt, _f()));
      } else {
        res = (await _f());
      }
      try {
        res = res.trim();
        if (res.startsWith('[') || res.startsWith('{')) {
          res = JSON.parse(res);
        }
      } catch (error) {}
      return res;
    } catch (error) {
      err = error;
      if (S.dev && S.bg === true) {
        console.log('ERROR TRYING TO CALL FETCH', url, err, JSON.stringify(err));
      }
      try {
        this.log(err);
      } catch (error) {}
    }
  }
};

P.fetch._auth = 'system';

P._timeout = function(ms, fn) { // where fn is a promise-able function that has been called
  // so call this like res = await @_timeout 5000, @fetch url
  return new Promise((resolve, reject) => {
    var timer;
    timer = setTimeout(() => {
      return reject(new Error('TIMEOUT')); // should this error or just return?
    }, ms);
    return promise.then(value(() => {
      clearTimeout(timer);
      return resolve(value);
    })).catch(reason(() => {
      clearTimeout(timer);
      return reject(reason);
    }));
  });
};

  // TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
  // alias can be set on create, and may be best just to use an alias every time
  // https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html
  // can also use aliases and alternate routes to handle auth to certain subsets of date
  // aliased mappings can also have a filter applied, so only the filter results get returned
var base, base1, ref,
  indexOf = [].indexOf;

if (S.index == null) {
  S.index = {};
}

if ((base = S.index).name == null) {
  base.name = (ref = S.name) != null ? ref : 'Paradigm';
}

if (typeof S.index.name !== 'string') {
  S.index.name = '';
}

S.index.name = S.index.name.toLowerCase().replace(/\s/g, '');

if (typeof S.bg === 'string') {
  if ((base1 = S.index).url == null) {
    base1.url = S.bg + '/index';
  }
}

// route must be a string (or derived from URL params)
// any _ route is a control request (can only come from internal, not via API) e.g. _mapping, _scroll, etc
// a route without /_ and /... is an index (or all indices)
// in which case data can be a record to save (or update) or a query
// if a query, it plus opts must be identifiable as such by P.index.translate
// no data at all is also a query - queries will return the full ES _search result object
// this can be overridden by setting opts to 1, in which case only the _source of the first hit is returned
// to loop over all search results (or a specified max number of results), set opts to -1?
// and provide the foreach param

// if not a query, it's a record which may or may not have an _id (if has _id it could be a save or update)
// a route without /_ but with /... is a record. Anything after the slash must be the ID
// if there is no data the _source (with _id?) of the specific record will be returned
// if there is data it will replace the record (any _id in the data will be removed, it cannot overwrite the route)
// if data is a list it will be bulk loaded to the index

// delete is achieved by setting data to '' (works for either a route without /... to delete the index, or with /... to delete a record)
// delete can only be achieved with '' internally, or by a request method of DELETE or URL param of _delete and suitable auth
// delete by query can also work this way
P.index = async function(route, data, opts, foreach) {
  var c, chk, dni, i, j, len, qr, ref1, ref2, ref3, ref4, ref5, ref6, res, ret, rex, rpl, rqp;
  if (typeof route === 'object') {
    data = route;
    route = void 0;
  }
  if ((route == null) && (data == null) && ((this != null ? this.parts : void 0) != null) && this.parts.length && this.parts[0] === 'index') {
    if (this.parts.length > 1 && (this.parts[1].startsWith('.') || this.parts[1].startsWith('_') || ((ref1 = this.parts[1]) === 'svc' || ref1 === 'src'))) { //or P[@parts[1]]?) #  or @parts[1].startsWith('svc_') or @parts[1].startsWith('src_'))
      return {
        // don't allow direct calls to index if the rest of the params indicate an existing route
        // if not an existing route, a user with necessary auth could create/interact with a specified index
        // for indexes not on a specified route, their config such as auth etc will need to be passed at creation and stored somewhere
        status: 403 // for now this isn't really stopping things, for example svc_crossref_works
      };
    } else {
      if (typeof this.body === 'object') {
        data = this.copy(this.body);
      } else if (typeof this.body === 'string') {
        if (this.body !== '') { // have to specify a DELETE method, or the _delete param on API, not just an empty body
          data = this.body;
        }
      } else {
        data = this.copy(this.params);
      }
      delete data.route;
      delete data.index;
      delete data[this.fn.split('.').pop()];
      delete data._id; // no provision of scripts or index or _id by params - has to be by URL route, or provided directly
      if ((data.script != null) || JSON.stringify(data).toLowerCase().indexOf('<script') !== -1) {
        return void 0;
      }
    }
  }
  if (typeof data === 'object' && !Array.isArray(data)) {
    if (route == null) {
      route = (ref2 = data.route) != null ? ref2 : data.index;
    }
    delete data.route;
    delete data.index;
  }
  if (route == null) {
    if (((this != null ? this.parts : void 0) != null) && this.parts[0] === 'index') { // need custom auth for who can create/remove indexes and records directly?
      if (this.parts.length === 1) {
        res = [];
        for (i in ((await this.index._send('_stats'))).indices) {
          if (!i.startsWith('.') && !i.startsWith('security-')) {
            res.push(i);
          }
        }
        return res;
      } else if (this.parts.length === 2) { // called direct on an index
        route = this.parts[1];
      } else if (this.parts.length > 2) { // called on index/key route
        // most IDs will only be at position 3 but for example using a DOI as an ID would spread it across 3 and 4
        route = this.parts[1] + '/' + this.parts.slice(2).join('_'); // so combine them with an underscore - IDs can't have a slash in them
      }
    } else if ((this != null ? this.fn : void 0) != null) {
      route = this.fn.replace(/\./g, '_'); // if the wrapping function wants data other than that defined by the URL route it was called on, it MUST specify the route manually
      if (this.parts.join('.') !== this.fn) {
        // what if the @parts indicate this is a request for a specific record though, not just an index?
        route += '/' + this.parts.join('_').replace(route + '_', '');
      }
    }
  }
  if (typeof route !== 'string') {
    return void 0;
  }
  if (route.includes('?')) {
    [route, rqp] = route.split('?');
    rqp = '?' + rqp;
  } else {
    rqp = '';
  }
  if (route.endsWith('/')) {
    route = route.replace(/\/$/, '');
  }
  if (typeof data === 'object' && !Array.isArray(data) && data._id) {
    data = (this != null ? this.copy : void 0) != null ? this.copy(data) : P.copy(data);
    dni = data._id.replace(/\//g, '_').toLowerCase();
    if (route.indexOf('/') === -1 && route.indexOf(dni) === -1) {
      route += '/' + dni;
    }
    delete data._id; // ID can't go into the data for ES7.x
    if (JSON.stringify(data) === '{}') { // if only provided an ID in an object and nothing else, try to get the record
      data = void 0;
    }
  }
  route = route.toLowerCase();
  rpl = route.split('/').length;
  if (this.index == null) {
    this.index = P.index; // allow either P.index or a contextualised @index to be used
  }
  if ((((this != null ? this.parts : void 0) != null) && this.parts[0] === 'index' && this.parts[1] === route.split('/')[0] && (this.request.method === 'DELETE' || this.params._delete)) || data === '') {
    // DELETE can happen on index or index/key, needs no additional route parts for index but index/key has to happen on _doc
    // TODO for @params._delete allow a passthrough of data in case it is a delete by query, once _send is updated to handle that if still possible
    ret = (await this.index._send(route.replace('/', '/_doc/') + rqp, ''));
    return void 0; //ret.acknowledged is true or ret.result is 'deleted'
  } else if (rpl === 1) {
    // CREATE can happen on index if index params are provided or empty object is provided
    // https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
    // simplest create would be {} or settings={number_of_shards:1} where 1 is default anyway
    if ((typeof data === 'string' && (data === '' || data.indexOf('\n') !== -1)) || Array.isArray(data)) {
      if (data === '') {
        return this.index._send(route + rqp, data);
      } else {
        return this.index._bulk(route + rqp, data); // bulk create (TODO what about if wanting other bulk actions?)
      }
    } else if ((ref3 = typeof data) === 'object' || ref3 === 'string') {
      if (JSON.stringify(data) !== '{}' && (qr = (await this.index.translate(data, opts)))) {
        return this.index._send(route + '/_search' + rqp, qr);
      } else if (typeof data === 'object') {
        chk = (this != null ? this.copy : void 0) != null ? this.copy(data) : P.copy(data);
        ref4 = ['settings', 'aliases', 'mappings'];
        for (j = 0, len = ref4.length; j < len; j++) {
          c = ref4[j];
          delete chk[c];
        }
        if (JSON.stringify(chk) === '{}') {
          if (!(await this.index._send(route + rqp))) {
            await this.index._send(route + rqp, {
              settings: data.settings,
              aliases: data.aliases,
              mappings: (ref5 = data.mappings) != null ? ref5 : data.mapping // create the index
            });
          }
          return this.index._send(route + '/_search' + rqp); // just do a search
        } else {
          ret = (await this.index._send(route + '/_doc' + rqp, data)); // create a single record without ID (if it came with ID it would have been caught above and converted to route with multiple parts)
          if ((ret != null ? ret.result : void 0) === 'created' && ret._id) {
            return ret._id;
          } else {
            return ret;
          }
        }
      }
    } else {
      return this.index._send(route + '/_search' + rqp);
    }
  } else if (rpl === 2 && ((data == null) || typeof data === 'object' && !Array.isArray(data))) {
    if (!route.startsWith('_') && !route.includes('/_')) {
      // CREATE or overwrite on index/key if data is provided - otherwise just GET the _doc
      // Should @params be able to default to write data on index/key?
      // TODO check how ES7.x accepts update with script in them
      route = route.replace('/', '/_doc/');
    }
    if ((data != null) && JSON.stringify(data) !== '{}') {
      if (typeof data === 'object' && (data.script != null)) {
        route += '_update';
        rqp += (rqp.length ? '&' : '?') + 'retry_on_conflict=2';
      }
      ret = (await this.index._send(route + rqp, data));
      if ((ret != null ? ret.result : void 0) === 'created' && ret._id) {
        return ret._id;
      } else {
        return ret; // or just get the record
      }
    } else {
      ret = (await this.index._send(route + rqp));
      if (typeof ret === 'object' && (ret._source || ret.fields)) {
        rex = (ref6 = ret._source) != null ? ref6 : ret.fields;
        if (rex._id == null) {
          rex._id = ret._id; // if _id can no longer be stored in the _source in ES7.x
        }
        ret = rex;
      }
      return ret;
    }
  }
  return void 0;
};

P.index._auths = 'system';

P.index._caches = false;

P.index.status = async function() {
  var base2, base3, i, j, k, l, len, len1, ref1, ref2, res, s, sh, shards, stats;
  res = {
    status: 'green',
    docs: 0,
    size: 0,
    shards: 0,
    failed: 0
  };
  try {
    stats = (await this.index._send('_nodes/stats/indices/search'));
    for (i in stats.nodes) {
      if (res.scrolls == null) {
        res.scrolls = 0;
      }
      res.scrolls += stats.nodes[i].indices.search.open_contexts;
    }
  } catch (error) {}
  res.indices = {};
  s = (await this.index._send('_stats'));
  shards = (await this.index._send('_cat/shards?format=json'));
  for (i in s.indices) {
    if (!i.startsWith('.') && !i.startsWith('security-')) {
      // is primaries or total better for numbers here?
      res.indices[i] = {
        docs: s.indices[i].primaries.docs.count,
        size: Math.ceil(s.indices[i].primaries.store.size_in_bytes / 1024 / 1024) + 'mb'
      };
      for (j = 0, len = shards.length; j < len; j++) {
        sh = shards[j];
        if (sh.index === i && sh.prirep === 'p') {
          if ((base2 = res.indices[i]).shards == null) {
            base2.shards = 0;
          }
          res.indices[i].shards += 1;
          if ((base3 = res.indices[i]).failed == null) {
            base3.failed = 0;
          }
          if (sh.state === 'UNASSIGNED') {
            res.indices[i].failed += 1;
          }
        }
      }
      res.docs += res.indices[i].docs;
      try {
        res.size += parseInt(res.indices[i].size.replace('mb', ''));
      } catch (error) {}
      res.shards += res.indices[i].shards;
      res.failed += res.indices[i].failed;
    }
  }
  res.size = Math.ceil((res.size / 1000) + 'gb');
  try {
    if ((ref1 = res.cluster.status) !== 'green' && ref1 !== 'yellow') { // accept yellow for single node cluster (or configure ES itself to accept that as green)
      res.status = 'red';
    }
    ref2 = ['cluster_name', 'number_of_nodes', 'number_of_data_nodes', 'unassigned_shards'];
    for (l = 0, len1 = ref2.length; l < len1; l++) {
      k = ref2[l];
      delete res.cluster[k];
    }
  } catch (error) {}
  return res;
};

P.index.keys = async function(route, type) {
  var _keys, keys, mapping, ref1, ref2, ref3;
  // type could most usefully be "text" to show fields that can be suggested on, or long or date (lists of types can be provided)
  // https://www.elastic.co/guide/en/elasticsearch/reference/6.8/mapping-types.html
  if (route == null) {
    route = (ref1 = (ref2 = this.params.index) != null ? ref2 : this.params.keys) != null ? ref1 : this.fn.replace(/\./g, '/');
  }
  route = route.replace('index/', '').replace('/keys', '');
  if (type == null) {
    type = (ref3 = this.params.type) != null ? ref3 : this.params.types;
  }
  if (typeof type === 'string') {
    type = [type];
  }
  keys = type === true ? {} : [];
  mapping = typeof route === 'object' ? route : (await this.index.mapping(route));
  _keys = async(m, depth = '') => {
    var k, ref4, ref5, results;
    if (depth) {
      depth += '.';
    }
    results = [];
    for (k in m) {
      if (m[k].properties != null) {
        results.push((await _keys(m[k].properties, depth + k)));
      } else if (!type || type === true || (ref4 = m[k].type, indexOf.call(type, ref4) >= 0)) {
        if (type === true) {
          results.push(keys[depth + k] = m[k].type);
        } else {
          if (ref5 = depth + k, indexOf.call(keys, ref5) < 0) {
            results.push(keys.push(depth + k));
          } else {
            results.push(void 0);
          }
        }
      } else {
        results.push(void 0);
      }
    }
    return results;
  };
  if (typeof mapping === 'object') {
    await _keys(mapping);
  }
  return keys;
};

P.index.terms = async function(route, key, qry, size = 100, counts = true, order = "count") {
  var cq, j, k, l, len, len1, ords, p, query, ref1, ref2, ref3, ref4, ref5, ref6, ref7, res, ret;
  if (route == null) {
    route = (ref1 = this.params.index) != null ? ref1 : this.fn.replace(/\./g, '/');
  }
  route = route.replace('index/', '').replace('/terms', '');
  if (!key || !qry) {
    if (key == null) {
      key = (ref2 = this.params.terms) != null ? ref2 : this.params.key;
    }
    if ((key == null) && route.indexOf('/') !== -1) {
      [route, key] = route.split('/');
    }
    if (!key) {
      return [];
    }
    cq = this.copy(this.params);
    ref3 = ['index', 'route', 'terms', 'key'];
    for (j = 0, len = ref3.length; j < len; j++) {
      k = ref3[j];
      delete cq[k];
    }
  }
  if (qry != null) {
    qry = (await this.index.translate(qry));
  }
  if (qry == null) {
    qry = (await this.index.translate(cq));
  }
  query = typeof qry === 'object' ? qry : {
    size: 0,
    query: {
      bool: {
        must: [],
        filter: [
          {
            exists: {
              field: key
            }
          }
        ]
      }
    }
  };
  if (typeof qry === 'string') {
    query.query.bool.must.push({
      query_string: {
        query: qry
      }
    });
  }
  if (query.aggregations == null) {
    query.aggregations = {};
  }
  if (query.size == null) {
    query.size = 0;
  }
  if (this.params.size != null) {
    size = this.params.size;
  }
  if (this.params.counts != null) {
    counts = this.params.counts;
  }
  if (this.params.order != null) {
    order = this.params.order;
  }
  // order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
  ords = {
    count: {
      _count: 'desc'
    },
    reverse_count: {
      _count: 'asc'
    },
    term: {
      _key: 'asc'
    },
    reverse_term: {
      _key: 'desc' // convert for ES7.x
    }
  };
  if (typeof order === 'string' && (ords[order] != null)) {
    order = ords[order];
  }
  query.aggregations[key] = {
    terms: {
      field: key + (key.endsWith('.keyword') ? '' : '.keyword'),
      size: size,
      order: order
    }
  };
  ret = (await this.index._send('/' + route + '/_search', query, 'POST'));
  res = [];
  ref7 = (ref4 = ret != null ? (ref5 = ret.aggregations) != null ? (ref6 = ref5[key]) != null ? ref6.buckets : void 0 : void 0 : void 0) != null ? ref4 : [];
  for (l = 0, len1 = ref7.length; l < len1; l++) {
    p = ref7[l];
    res.push(counts ? {
      term: p.key,
      count: p.doc_count
    } : p.key);
  }
  return res;
};

P.index.suggest = async function(route, key, qry, size = 100, include) {
  var ak, j, k, kl, len, ql, rec, ref1, ref2, ref3, ref4, res, seen, tqr;
  if (!key || !qry) {
    if (key == null) {
      key = (ref1 = this.params.suggest) != null ? ref1 : this.params.key;
    }
    if (typeof key === 'string' && key.includes('/')) {
      [key, qry] = key.split('/');
    }
  }
  if (!key) {
    return this.index.keys(route, 'text');
  }
  if (route == null) {
    route = (ref2 = this.params.index) != null ? ref2 : this.fn.replace(/\./g, '/');
  }
  route = route.replace('index/', '').split('/suggest')[0];
  if (include == null) {
    include = this.params.include;
  }
  if (typeof include === 'string') {
    include = include.replace(/,\s/g, ',').split(',');
  }
  if (Array.isArray(include) && indexOf.call(include, key) < 0) {
    include.push(key);
  }
  if (typeof qry === 'string') {
    qry = qry.trim();
    ql = qry.toLowerCase();
    tqr = {
      should: [
        {
          match: {}
        },
        {
          prefix: {}
        },
        {
          query_string: {
            query: key + ':' + qry.split(' ').join(' AND ' + key + ':') + '*'
          }
        }
      ]
    };
    tqr.should[0].match[key] = {
      query: qry,
      boost: 3
    };
    tqr.should[1].prefix[key] = {
      value: qry,
      boost: 2
    };
  }
  res = [];
  seen = [];
  if (include) { // NOTE to include extra vals this has to be a search of records, and it may not find all possible values, whereas the terms option without include will
    ref3 = this.index._for(route, tqr != null ? tqr : qry, {
      sort: key + '.keyword',
      until: size,
      include: (include === true ? [key] : include)
    });
    for await (rec of ref3) {
      if (k = (await this.dot(rec, key))) {
        while (Array.isArray(k) && (ak = k.shift())) {
          if (ak.toLowerCase().includes(ql)) {
            k = ak;
          }
        }
        kl = k.toLowerCase();
        if (indexOf.call(seen, kl) < 0 && (!ql || kl.includes(ql))) {
          res.push(rec);
        }
        seen.push(kl);
      }
    }
  } else {
    ref4 = (await this.index.terms(route, key, tqr != null ? tqr : qry, size, false, 'term'));
    for (j = 0, len = ref4.length; j < len; j++) {
      k = ref4[j];
      kl = k.toLowerCase();
      if (indexOf.call(seen, kl) < 0 && (!ql || kl.includes(ql))) {
        res.push(k);
      }
      seen.push(kl);
    }
  }
  return res;
};

P.index.count = async function(route, qry, key) {
  var cq, j, k, len, qr, ref1, ref2, ref3, ref4, ref5, ref6, ret;
  if (key == null) {
    key = (ref1 = this.params.count) != null ? ref1 : this.params.key;
  }
  if (route == null) {
    route = (ref2 = this.params.index) != null ? ref2 : this.fn.replace(/\./g, '_');
  }
  route = route.replace('index/', '').split('/count')[0];
  if (route.indexOf('/') !== -1) {
    [route, key] = route.split('/');
  }
  cq = this.copy(this.params);
  ref3 = ['index', 'route', 'count', 'key'];
  for (j = 0, len = ref3.length; j < len; j++) {
    k = ref3[j];
    delete cq[k];
  }
  if ((qry == null) && (qr = (await this.index.translate(cq)))) {
    qry = qr;
  }
  if (typeof qry === 'string') {
    qry = (await this.index.translate(qry));
  }
  if (qry == null) {
    qry = {
      query: {
        bool: {
          must: [],
          filter: []
        }
      }
    };
  }
  if (key) {
    if (!key.endsWith('.keyword')) {
      key += '.keyword';
    }
    qry.size = 0;
    qry.aggs = {
      keyed: {
        cardinality: {
          field: key,
          precision_threshold: 40000 // this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
        }
      }
    };
    ret = (await this.index._send('/' + route + '/_search', qry, 'POST'));
    return ret != null ? (ref4 = ret.aggregations) != null ? (ref5 = ref4.keyed) != null ? ref5.value : void 0 : void 0 : void 0;
  } else {
    ret = (await this.index._send('/' + route + '/_search', qry, 'POST'));
    return ret != null ? (ref6 = ret.hits) != null ? ref6.total : void 0 : void 0;
  }
};

P.index.percent = async function(route, qry, key) {
  var count, cq, j, k, len, qr, ref1, ref2, ref3, ref4, ref5, ref6, ret, total;
  if (key == null) {
    key = (ref1 = this.params.count) != null ? ref1 : this.params.key;
  }
  if (route == null) {
    route = (ref2 = this.params.index) != null ? ref2 : this.fn.replace(/\./g, '_');
  }
  route = route.replace('index/', '').split('/count')[0];
  if (route.indexOf('/') !== -1) {
    [route, key] = route.split('/');
  }
  cq = this.copy(this.params);
  ref3 = ['index', 'route', 'count', 'key'];
  for (j = 0, len = ref3.length; j < len; j++) {
    k = ref3[j];
    delete cq[k];
  }
  if ((qry == null) && (qr = (await this.index.translate(cq)))) {
    qry = qr;
  }
  if (typeof qry === 'string') {
    qry = (await this.index.translate(qry));
  }
  if (qry == null) {
    qry = {
      query: {
        bool: {
          must: [],
          filter: []
        }
      }
    };
  }
  total = (await this.index.count(route, '*'));
  count = 0;
  if (key) {
    if (!key.endsWith('.keyword')) {
      key += '.keyword';
    }
    qry.size = 0;
    qry.aggs = {
      keyed: {
        cardinality: {
          field: key,
          precision_threshold: 40000 // this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
        }
      }
    };
    ret = (await this.index._send('/' + route + '/_search', qry, 'POST'));
    count = ret != null ? (ref4 = ret.aggregations) != null ? (ref5 = ref4.keyed) != null ? ref5.value : void 0 : void 0 : void 0;
  } else {
    ret = (await this.index._send('/' + route + '/_search', qry, 'POST'));
    count = ret != null ? (ref6 = ret.hits) != null ? ref6.total : void 0 : void 0;
  }
  return Math.ceil((count / total) * 10000) / 100;
};

P.index.min = async function(route, key, qry, end = 'min') {
  var cq, j, k, len, query, ref1, ref2, ref3, ret;
  if (key == null) {
    key = (ref1 = this.params[end]) != null ? ref1 : this.params.key;
  }
  if (route == null) {
    route = (ref2 = this.params.index) != null ? ref2 : this.fn.replace(/\./g, '/');
  }
  route = route.replace('index/', '').replace('/' + end, '');
  if (route.indexOf('/') !== -1) {
    [route, key] = route.split('/');
  }
  cq = this.copy(this.params);
  ref3 = ['index', 'route', 'min', 'max', 'key', 'sum', 'average'];
  for (j = 0, len = ref3.length; j < len; j++) {
    k = ref3[j];
    delete cq[k];
  }
  if (qry == null) {
    qry = (await this.index.translate(cq));
  }
  query = typeof key === 'object' ? key : qry != null ? qry : {
    query: {
      bool: {
        must: [],
        filter: [
          {
            exists: {
              field: key
            }
          }
        ]
      }
    }
  };
  query.size = 0;
  if (end === 'sum') {
    query.aggs = {
      sum: {
        sum: {
          field: key
        }
      }
    };
  } else if (end === 'average') {
    query.aggs = {
      average: {
        avg: {
          field: key
        }
      }
    };
  } else {
    query.aggs = {};
    if (end === 'min' || end === 'range') {
      query.aggs.min = {
        min: {
          field: key
        }
      };
    }
    if (end === 'max' || end === 'range') {
      query.aggs.max = {
        max: {
          field: key
        }
      };
    }
  }
  ret = (await this.index._send('/' + route + '/_search', query, 'POST'));
  if (end === 'range') {
    return {
      min: ret.aggregations.min.value,
      max: ret.aggregations.max.value
    };
  } else {
    return ret.aggregations[end].value;
  }
};

P.index.max = function(route, key, qry) {
  return this.index.min(route, key, qry, 'max');
};

P.index.range = function(route, key, qry) {
  return this.index.min(route, key, qry, 'range');
};

P.index.sum = function(route, key, qry) {
  return this.index.min(route, key, qry, 'sum');
};

P.index.average = function(route, key, qry) {
  return this.index.min(route, key, qry, 'average');
};

// can be used to put new fields into a mapping such as:
`{
"properties": {
  "assertion": {
    "properties": {
      "label": {
        "type": "text",
        "fields": {
          "keyword": {
            "type": "keyword",
            "ignore_above": 256
          }
        }
      }
    }
  }
}
}`;

P.index.mapping = async function(route, map) {
  var mapped, ret, rtm;
  route = route.replace(/^\//, ''); // remove any leading /
  if (route.indexOf('/') === -1) {
    route = route + '/';
  }
  if (route.indexOf('_mapping') === -1) {
    route = route.replace('/', '/_mapping');
  }
  if (map != null) {
    mapped = (await this.index._send(route, map, 'PUT'));
    console.log(route, 'mapped', mapped);
  }
  ret = (await this.index._send(route));
  rtm = ((await this.keys(ret)))[0];
  return ret[rtm].mappings.properties;
};

// use this like: for await rec from @index._for route, q, opts
// see index._each below for example of how to call this for/yield generator
P.index._for = async function*(route, q, opts, prefix, alias) {
  var counter, max, prs, qy, r, ref1, ref2, ref3, ref4, ref5, res, ret, scroll;
  if (typeof opts === 'number') {
    opts = {
      until: opts
    };
  }
  if (opts != null ? opts.scroll : void 0) { // set this longer, e.g. 10m, if the processing to be done with the records may take longer than a minute
    scroll = opts.scroll;
    if (typeof scroll === 'number' || !scroll.endsWith('m')) {
      scroll += 'm';
    }
    delete opts.scroll;
  } else {
    scroll = '2m';
  }
  if ((opts != null ? opts.until : void 0) || (opts != null ? opts.max : void 0)) {
    max = (ref1 = opts.until) != null ? ref1 : opts.max;
    delete opts.until;
    delete opts.max;
  }
  if (q == null) {
    q = '*';
  }
  qy = (await this.index.translate(q, opts));
  if (qy.from == null) {
    qy.from = 0;
  }
  if (qy.size == null) {
    qy.size = 500;
  }
  if (qy.sort == null) {
    qy.sort = ['_doc']; // performance improved for scrolling sorted on _doc if no other sort was configured
  }
  // use scan/scroll for each, because _pit is only available in "default" ES, which ES means is NOT the open one, so our OSS distro does not include it!
  // https://www.elastic.co/guide/en/elasticsearch/reference/7.10/paginate-search-results.html#search-after
  res = (await this.index._send(route + '/_search?scroll=' + scroll, qy, void 0, prefix, alias));
  if (res != null ? res._scroll_id : void 0) {
    prs = res._scroll_id.replace(/==$/, '');
  }
  if ((res != null ? (ref2 = res.hits) != null ? ref2.total : void 0 : void 0) && ((max == null) || max > res.hits.total)) {
    max = res.hits.total;
  }
  counter = 0;
  while (true) {
    if ((!(res != null ? (ref3 = res.hits) != null ? ref3.hits : void 0 : void 0) || res.hits.hits.length === 0) && (res != null ? res._scroll_id : void 0)) { // get more if possible
      res = (await this.index._send('/_search/scroll?scroll=' + scroll + '&scroll_id=' + res._scroll_id, void 0, void 0, prefix, alias));
      if ((res != null ? res._scroll_id : void 0) !== prs) {
        await this.index._send('/_search/scroll?scroll_id=' + prs, '', void 0, prefix, alias);
        prs = res != null ? res._scroll_id : void 0;
      }
    }
    if (counter !== max && ((res != null ? (ref4 = res.hits) != null ? ref4.hits : void 0 : void 0) != null) && res.hits.hits.length) {
      counter += 1;
      r = res.hits.hits.shift();
      ret = (ref5 = r._source) != null ? ref5 : r.fields;
      if (ret._id == null) {
        ret._id = r._id;
      }
      yield ret;
    } else {
      if (prs) { // don't keep too many old scrolls open (default ES max is 500)
        await this.index._send('/_search/scroll?scroll_id=' + prs, '', void 0, prefix, alias);
      }
      break;
    }
  }
};

P.index._each = async function(route, q, opts, fn, prefix, alias) {
  var action, chk, fr, max_size, processed, qy, rec, ref1, ref2, ref3, sz, updates;
  // Performs a function on each record. If the function should make changes to a record, optionally 
  // avoid many writes by having the function return the record object or the string ID, and specify 
  // an "action" in opts. returned objects can then be bulk "insert" or "update", or string IDs for "remove"
  if ((fn == null) && (opts == null) && typeof q === 'function') {
    fn = q;
    q = '*';
  }
  if ((fn == null) && typeof opts === 'function') {
    fn = opts;
    opts = void 0;
  }
  if (opts == null) {
    opts = {};
  }
  if (typeof opts === 'string') {
    action = opts;
    opts = void 0;
  }
  if (opts != null ? opts.action : void 0) {
    action = opts.action;
    delete opts.action;
  }
  sz = (ref1 = opts.size) != null ? ref1 : (typeof q === 'object' && (q.size != null) ? q.size : 1000);
  if (sz > 50) {
    qy = (await this.index.translate(q, opts));
    qy.size = 1;
    chk = (await this.index._send(route, qy, void 0, prefix, alias));
    if (((chk != null ? (ref2 = chk.hits) != null ? ref2.total : void 0 : void 0) != null) && chk.hits.total !== 0) {
      // try to make query result size not take up more than about 1gb. In a scroll-scan size is per shard, not per result set
      max_size = Math.floor(1000000000 / (Buffer.byteLength(JSON.stringify(chk.hits.hits[0])) * chk._shards.total));
      if (max_size < sz) {
        sz = max_size;
      }
    }
    qy.size = sz;
  }
  processed = 0;
  updates = [];
  ref3 = this.index._for(route, qy != null ? qy : q, opts, prefix, alias);
  for await (rec of ref3) {
    fr = (await fn.call(this, rec));
    processed += 1;
    if ((fr != null) && (typeof fr === 'object' || typeof fr === 'string')) {
      updates.push(fr);
    }
    if (action && updates.length > sz) {
      await this.index._bulk(route, updates, action, void 0, prefix, alias);
      updates = [];
    }
  }
  if (action && updates.length) { // catch any left over
    this.index._bulk(route, updates, action, void 0, prefix, alias);
  }
  if (this.S.dev && this.S.bg === true) {
    return console.log('_each processed ' + processed);
  }
};

P.index._bulk = async function(route, data, action = 'index', bulk = 50000, prefix, alias) {
  var counter, dtp, errorcount, errors, it, j, len, meta, pkg, r, ref1, ref10, ref11, ref12, ref13, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rid, row, rows, rs, rso;
  if (action === true) {
    action = 'index';
  }
  rso = route.split('/')[0];
  dtp = (await this.dot(P, rso.replace(/_/g, '.'))); // need to do this here as well as in _send so it can be set below in each object of the bulk
  if (alias == null) {
    alias = (ref1 = (ref2 = this.params._alias) != null ? ref2 : (ref3 = this.S.alias) != null ? ref3[rso.startsWith(this.S.index.name + '_') ? rso.replace(this.S.index.name + '_', '') : rso] : void 0) != null ? ref1 : dtp != null ? dtp._alias : void 0;
  }
  if (typeof alias === 'string') {
    if (!alias.startsWith('_')) {
      alias = '_' + alias;
    }
    alias = alias.replace(/\//g, '_');
    if (!rso.endsWith(alias)) {
      route = route.replace(rso, rso + alias);
    }
  }
  if (prefix === true) {
    prefix = this.S.index.name;
  }
  if (prefix == null) {
    prefix = (ref4 = dtp != null ? dtp._prefix : void 0) != null ? ref4 : this.S.index.name;
  }
  if (typeof prefix === 'string') {
    if (prefix.length && !prefix.endsWith('_')) {
      prefix += '_';
    }
    if (!route.startsWith(prefix)) {
      route = prefix + route;
    }
  }
  if (this.index == null) {
    this.index = P.index;
  }
  if (typeof data === 'string' && data.indexOf('\n') !== -1) {
    // TODO should this check through the string and make sure it only indexes to the specified route?
    await this.index._send('/_bulk', {
      body: data,
      headers: {
        'Content-Type': 'application/x-ndjson'
      }
    }, void 0, prefix, alias); // new ES 7.x requires this rather than text/plain
    return true;
  } else {
    rows = typeof data === 'object' && !Array.isArray(data) && ((data != null ? (ref5 = data.hits) != null ? ref5.hits : void 0 : void 0) != null) ? data.hits.hits : data;
    if (!Array.isArray(rows)) {
      rows = [rows];
    }
    counter = 0;
    errorcount = 0;
    pkg = '';
    for (r in rows) {
      row = rows[r];
      counter += 1;
      if (typeof row === 'object') {
        rid = (ref6 = (ref7 = row._id) != null ? ref7 : (ref8 = row._source) != null ? ref8._id : void 0) != null ? ref6 : (await this.uid());
        if (typeof rid === 'string') {
          rid = rid.replace(/\//g, '_');
        }
        if (row._source) {
          row = row._source;
        }
        delete row._id; // newer ES 7.x won't accept the _id in the object itself
      }
      meta = {};
      meta[action] = {
        "_index": route
      };
      meta[action]._id = action === 'delete' && ((ref9 = typeof row) === 'string' || ref9 === 'number') ? row : rid; // what if action is delete but can't set an ID?
      pkg += JSON.stringify(meta) + '\n';
      if (action === 'create' || action === 'index') {
        pkg += JSON.stringify(row) + '\n';
      } else if (action === 'update') {
        pkg += JSON.stringify({
          doc: row
        }) + '\n'; // is it worth expecting other kinds of update in bulk import?
      }
      // don't need a second row for deletes
      if (counter === bulk || parseInt(r) === (rows.length - 1) || pkg.length > 70000000) {
        rs = (await this.index._send('/_bulk', {
          body: pkg,
          headers: {
            'Content-Type': 'application/x-ndjson'
          }
        }, void 0, prefix, alias));
        if ((this != null ? (ref10 = this.S) != null ? ref10.dev : void 0 : void 0) && (this != null ? (ref11 = this.S) != null ? ref11.bg : void 0 : void 0) === true && (rs != null ? rs.errors : void 0)) {
          errors = [];
          ref12 = rs.items;
          for (j = 0, len = ref12.length; j < len; j++) {
            it = ref12[j];
            try {
              if ((ref13 = it[action].status) !== 200 && ref13 !== 201) {
                errors.push(it[action]);
                errorcount += 1;
              }
            } catch (error) {
              errorcount += 1;
            }
          }
          try {
            console.log(errors);
          } catch (error) {}
          try {
            console.log((errors.length === 0 ? 'SOME' : errors.length), 'INDEX ERRORS BULK LOADING', rs.items.length);
          } catch (error) {}
        }
        pkg = '';
        counter = 0;
      }
    }
    return rows.length - errorcount;
  }
};

//P.index._refresh = (route) -> return @index._send route.replace(/^\//, '').split('/')[0] + '/_refresh'

// query formats that can be accepted:
//  'A simple string to match on'
//  'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
//  '?q=query params directly as string'
//  {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
//  {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "must_not", "filter", "should" as well)
//  also works for: filter (restrict), must (and), must_not (not), should (or)
//  values can be (singular or lists of) strings, or objects with one key with a string value indicating a term query, or properly structured query parts

//  Keys can use dot notation
//  If opts is true, the query will be adjusted to sort by createdAt descending, so returning the newest first (it sets newest:true, see below)
//  If opts is string 'random' it will convert the query to be a random order
//  If opts is a number it will be assumed to be the size parameter
//  Otherwise opts should be an object (and the above can be provided as keys, "newest", "random")
//  If newest is true the query will have a sort desc on createdAt. If false, sort will be asc
//  If "random" key is provided, "seed" can be provided too if desired, for seeded random queries
//  If "restrict" is provided, should point to list of ES queries to add to the and part of the query filter
//  Any other keys in the options object should be directly attributable to an ES query object

//  For ES 7.x there is no filtered query any more, filter is a value of bool.must
//  Filter acts like a must but without scoring. Whereas normal must does score.
//  must_not does not affect score. Not sure about should
//  Default empty query: {query: {bool: {must: [], filter: []}}, size: 10}
P.index.translate = function(q, opts) {
  var af, ag, b, base2, base3, base4, base5, bm, etp, exc, f, fq, i, inc, j, k, l, len, len1, len2, len3, len4, len5, len6, ls, n, o, ords, pfx, qpts, qry, qs, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rkeys, rs, so, sorts, sq, t, tm, tp, u, v, w, x;
  if ((this != null ? this.route : void 0) && this.route.startsWith('index')) { // return undefined if q isnt a string or object that can become a valid query
    if (q == null) {
      q = this != null ? this.params : void 0;
    }
  }
  if (typeof q === 'string') {
    if (q === '' || q.indexOf('\n') !== -1) { // this would likely be a bulk load string
      return void 0;
    }
  } else {
    if (typeof q !== 'object' || Array.isArray(q)) {
      return void 0;
    }
    ref1 = ['settings', 'aliases', 'mappings', 'index', '_id'];
    for (j = 0, len = ref1.length; j < len; j++) {
      k = ref1[j];
      if (q[k] != null) {
        return void 0;
      }
    }
    qs = false;
    if (q.source) {
      try {
        qs = JSON.parse(decodeURIComponent(q.source));
      } catch (error) {}
    }
    if (JSON.stringify(q) !== '{}' && (q.q == null) && (q.query == null) && qs === false && (q.must == null) && (q.should == null) && (q.must_not == null) && (q.filter == null) && (q.aggs == null) && (q.aggregations == null)) {
      return void 0;
    }
  }
  try {
    if (typeof q === 'object') { // copy objects so don't interfere with what was passed in
      q = this.copy(q);
    }
  } catch (error) {}
  try {
    if (typeof opts === 'object') {
      opts = this.copy(opts);
    }
  } catch (error) {}
  if (opts == null) {
    opts = {};
  }
  if (typeof opts === 'string' || Array.isArray(opts)) {
    opts = {
      fields: opts
    };
  }
  if (opts === 'random') {
    opts = {
      random: true
    };
  }
  if (typeof opts === 'number') {
    opts = {
      size: opts
    };
  }
  if (opts === true) {
    opts = {
      newest: true
    };
  }
  if (opts === false) {
    opts = {
      newest: false
    };
  }
  if (opts.newest != null) {
    opts.sort = {
      createdAt: opts.newest ? 'desc' : 'asc'
    };
    delete opts.newest;
  }
  qry = (ref2 = opts != null ? opts.query : void 0) != null ? ref2 : {};
  if (qry.query == null) {
    qry.query = {};
  }
  if ((base2 = qry.query).bool == null) {
    base2.bool = {
      must: [],
      filter: []
    };
  }
  if (typeof q === 'string') {
    sq = {
      query_string: {
        query: q
      }
    };
    if ((opts != null ? opts.fields : void 0) != null) {
      sq.query_string.fields = typeof opts.fields === 'string' ? opts.fields.split(',') : opts.fields;
      delete opts.fields;
    }
    qry.query.bool.filter.push(sq);
  } else if (typeof q === 'object') {
    if (q.query != null) {
      qry = q; // assume already a query
    } else {
      if (q.source != null) {
        if (typeof q.source === 'string' && typeof qs === 'object') {
          qry = qs;
        } else if (typeof q.source === 'object') {
          qry = q.source;
        }
      } else if (q.q != null) {
        if (typeof q.q === 'object') {
          qry.query = q.q; // if an object assume it's a correct one
        } else {
          q.q = decodeURIComponent(q.q);
          if ((q.prefix != null) && q.q.indexOf(':') !== -1) {
            delete q.prefix;
            pfx = {};
            qpts = q.q.split(':');
            pfx[qpts[0]] = qpts[1];
            qry.query.bool.must.push({
              prefix: pfx // TODO check if prefix can still be used in ES7.x and if it can go in filter instead of must
            });
          } else if (q.fields != null) {
            qry.query.bool.filter.push({
              query_string: {
                query: q.q,
                fields: q.fields.split(',')
              }
            });
            delete q.fields;
          } else {
            qry.query.bool.filter.push({
              query_string: {
                query: q.q
              }
            });
          }
        }
      }
      for (o in q) {
        if (opts[o] == null) {
          opts[o] = q[o];
        }
      }
    }
  }
  // simple convenience catch for old-style queries - NOT complete, only works if they were basic filtered bool queries perhaps with directly translatable facets
  if (((ref3 = qry.query) != null ? (ref4 = ref3.filtered) != null ? (ref5 = ref4.query) != null ? ref5.bool : void 0 : void 0 : void 0) != null) {
    qry.query.bool = qry.query.filtered.query.bool;
    qry.query.bool.filter = qry.query.filtered.filter;
    delete qry.query.filtered;
  }
  if (qry.facets != null) {
    qry.aggregations = JSON.parse(JSON.stringify(qry.facets).replace(/\.exact/g, '.keyword'));
    delete qry.facets;
  }
  if ((qry.query != null) && (qry.query.bool == null) && JSON.stringify(qry.query) !== '{}') {
    qry.query = {
      bool: {
        must: [],
        filter: [qry.query]
      }
    };
  }
  if (qry.query == null) {
    qry.query = {
      bool: {
        must: [],
        filter: []
      }
    };
  }
  if ((base3 = qry.query).bool == null) {
    base3.bool = {
      must: [],
      filter: []
    };
  }
  if ((base4 = qry.query.bool).filter == null) {
    base4.filter = [];
  }
  if (typeof opts.sort === 'string') {
    sorts = []; // https://www.elastic.co/guide/en/elasticsearch/reference/7.x/sort-search-results.html
    ref6 = opts.sort.split(',');
    for (l = 0, len1 = ref6.length; l < len1; l++) {
      so = ref6[l];
      [k, o] = so.split(':');
      if (!o) {
        sorts.push(k.trim());
      } else {
        sorts.push({});
        sorts[sorts.length - 1][k.trim()] = o.trim();
      }
    }
    opts.sort = sorts;
  }
  if (opts.random) {
    fq = {
      function_score: {
        random_score: {}
      }
    };
    if (opts.seed != null) {
      fq.function_score.random_score.seed = seed;
    }
    fq.function_score.query = qry.query;
    qry.query = fq; // TODO check how function_score and random seed work now in ES7.x
    delete opts.random;
    delete opts.seed;
  }
  if (inc = (ref7 = (ref8 = (ref9 = opts._include) != null ? ref9 : opts.include) != null ? ref8 : opts._includes) != null ? ref7 : opts.includes) {
    if (qry._source == null) {
      qry._source = {};
    }
    qry._source.includes = typeof inc === 'string' ? inc.replace(/,\s/g, ',').split(',') : inc;
  }
  if (exc = (ref10 = (ref11 = (ref12 = opts._exclude) != null ? ref12 : opts.exclude) != null ? ref11 : opts._excludes) != null ? ref10 : opts.excludes) {
    if (qry._source == null) {
      qry._source = {};
    }
    qry._source.excludes = typeof exc === 'string' ? exc.replace(/,\s/g, ',').split(',') : exc;
    ref15 = (ref13 = (ref14 = qry._source) != null ? ref14.includes : void 0) != null ? ref13 : [];
    for (n = 0, len2 = ref15.length; n < len2; n++) {
      i = ref15[n];
      qry._source.excludes = qry._source.excludes.filter(function(v) {
        return v !== i;
      });
    }
  }
  ref16 = ['filter', 'restrict', 'must', 'and', 'must_not', 'not', 'should', 'or'];
  for (t = 0, len3 = ref16.length; t < len3; t++) {
    tp = ref16[t];
    if (opts[tp] != null) {
      ls = Array.isArray(opts[tp]) ? opts[tp] : [opts[tp]];
      delete opts[tp];
      etp = tp === 'filter' || tp === 'restrict' || tp === 'must' || tp === 'and' ? 'filter' : tp === 'must_not' || tp === 'not' ? 'must_not' : 'should';
      if ((base5 = qry.query.bool)[etp] == null) {
        base5[etp] = [];
      }
      for (u = 0, len4 = ls.length; u < len4; u++) {
        rs = ls[u];
        if (typeof rs === 'object') {
          rkeys = this.keys(rs);
          if (rkeys.length === 1 && typeof rs[rkeys[0]] !== 'object') {
            rs = {
              term: rs
            };
          }
        } else {
          rs = {
            query_string: {
              query: rs
            }
          };
        }
        qry.query.bool[etp].push(rs);
      }
    }
  }
  if (opts.terms != null) {
    try {
      opts.terms = opts.terms.replace(/,\s/g, ',').split(',');
    } catch (error) {}
    if (qry.aggregations == null) {
      qry.aggregations = {};
    }
    ref17 = opts.terms;
    for (w = 0, len5 = ref17.length; w < len5; w++) {
      tm = ref17[w];
      qry.aggregations[tm] = {
        terms: {
          field: tm + (tm.endsWith('.keyword') ? '' : '.keyword'),
          size: 1000
        }
      };
    }
    delete opts.terms;
  }
  ref18 = ['aggs', 'aggregations'];
  for (x = 0, len6 = ref18.length; x < len6; x++) {
    af = ref18[x];
    if (opts[af] != null) {
      if (qry[af] == null) {
        qry[af] = {};
      }
      for (f in opts[af]) {
        qry[af][f] = opts[af][f];
      }
      delete opts[af];
    }
  }
  for (k in opts) {
    v = opts[k];
    //v = v.replace(/,\s/g, ',').split(',') if k in ['fields'] and typeof v is 'string' and v.indexOf(',') isnt -1
    if ((k === 'from' || k === 'size') && typeof v !== 'number') {
      try {
        v = parseInt(v);
        if (isNaN(v)) {
          v = void 0;
        }
      } catch (error) {}
    }
    if ((v != null) && (k !== 'apikey' && k !== '_' && k !== 'callback' && k !== 'refresh' && k !== 'key' && k !== 'counts' && k !== 'index' && k !== 'search' && k !== 'source' && k !== 'q' && k !== '_alias') && ((ref19 = k.replace('_', '').replace('s', '')) !== 'include' && ref19 !== 'exclude')) {
      // some URL params that may be commonly used in this API along with valid ES URL query params will be removed here by default too
      // this makes it easy to handle them in routes whilst also just passing the whole params here and still get back a valid ES query
      qry[k] = v;
    }
  }
  try {
    // order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
    ords = {
      count: {
        _count: 'desc'
      },
      reverse_count: {
        _count: 'asc'
      },
      term: {
        _key: 'asc'
      },
      reverse_term: {
        _key: 'desc' // convert for ES7.x
      }
    };
    for (ag in qry.aggregations) {
      if (typeof ((ref20 = qry.aggregations[ag].terms) != null ? ref20.order : void 0) === 'string' && (ords[qry.aggregations[ag].terms.order] != null)) {
        qry.aggregations[ag].terms.order = ords[qry.aggregations[ag].terms.order];
      }
    }
  } catch (error) {}
  
  // no filter query or no main query can cause issues on some queries especially if certain aggs/terms are present, so insert some default searches if necessary
  //qry.query = { match_all: {} } if typeof qry is 'object' and qry.query? and JSON.stringify(qry.query) is '{}'
  // clean slashes out of query strings
  if (((ref21 = qry.query) != null ? ref21.bool : void 0) != null) {
    for (bm in qry.query.bool) {
      for (b in qry.query.bool[bm]) {
        if (typeof ((ref22 = qry.query.bool[bm][b].query_string) != null ? ref22.query : void 0) === 'string' && qry.query.bool[bm][b].query_string.query.indexOf('/') !== -1 && qry.query.bool[bm][b].query_string.query.indexOf('"') === -1) {
          qry.query.bool[bm][b].query_string.query = '"' + qry.query.bool[bm][b].query_string.query + '"';
        }
      }
    }
  }
  if ((qry._source != null) && (qry.fields != null)) {
    delete qry._source;
  }
  //console.log JSON.stringify qry
  return qry;
};

P.index.translate._auth = false;

// calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
// call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
P.index._send = async function(route, data, method, prefix, alias) {
  var dtp, opts, provided_scroll_id, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, rqp, rso, url;
  if (route.includes('?')) {
    [route, rqp] = route.split('?');
    rqp = '?' + rqp;
  } else {
    rqp = '';
  }
  route = route.toLowerCase(); // force lowercase on all IDs so that can deal with users giving incorrectly cased IDs for things like DOIs which are defined as case insensitive
  if (route.startsWith('/')) { // gets added back in when combined with the url
    route = route.replace('/', '');
  }
  if (route.endsWith('/')) {
    route = route.replace(/\/$/, '');
  }
  if (method == null) {
    method = data === '' ? 'DELETE' : (data != null) && (route.indexOf('/') === -1 || route.indexOf('/_create') !== -1 || (route.indexOf('/_doc') !== -1 && !route.endsWith('/_doc'))) ? 'PUT' : (data != null) || ((ref1 = route.split('/').pop().split('?')[0]) === '_refresh' || ref1 === '_aliases') ? 'POST' : 'GET';
  }
  if (method === 'DELETE' && route.indexOf('/_all') !== -1) { // nobody can delete all via the API
    // TODO if data is a query that also has a _delete key in it, remove that key and do a delete by query? and should that be bulked? is dbq still allowed in ES7.x?
    return false;
  }
  if (!route.startsWith('http')) { // which it probably doesn't
    if (!route.startsWith('_')) {
      rso = route.split('/')[0];
      dtp = (await this.dot(P, rso.replace(/_/g, '.')));
      if (alias == null) {
        alias = (ref2 = (ref3 = this.params._alias) != null ? ref3 : (ref4 = this.S.alias) != null ? ref4[rso.startsWith(this.S.index.name + '_') ? rso.replace(this.S.index.name + '_', '') : rso] : void 0) != null ? ref2 : dtp != null ? dtp._alias : void 0;
      }
      if (typeof alias === 'string') {
        if (!alias.startsWith('_')) {
          alias = '_' + alias;
        }
        alias = alias.replace(/\//g, '_');
        if (!rso.endsWith(alias)) {
          route = route.replace(rso, rso + alias);
        }
      }
      if (prefix == null) {
        prefix = (ref5 = dtp != null ? dtp._prefix : void 0) != null ? ref5 : this.S.index.name;
      }
      if (prefix === true) {
        prefix = this.S.index.name;
      }
      if (typeof prefix === 'string') {
        if (prefix.length && !prefix.endsWith('_')) {
          prefix += '_';
        }
        if (!route.startsWith(prefix)) { // TODO could allow prefix to be a list of names, and if index name is in the list, alias the index into those namespaces, to share indexes between specific instances rather than just one or global
          route = prefix + route;
        }
      }
    }
    url = (this != null ? (ref6 = this.S) != null ? (ref7 = ref6.index) != null ? ref7.url : void 0 : void 0 : void 0) ? this.S.index.url : (ref8 = S.index) != null ? ref8.url : void 0;
    if (Array.isArray(url)) {
      url = url[Math.floor(Math.random() * url.length)];
    }
    if (typeof url !== 'string') {
      return void 0;
    }
    route = url + '/' + route;
  }
  if (!route.startsWith('http')) {
    console.log('NO INDEX URL AVAILABLE');
    return void 0;
  }
  provided_scroll_id = false;
  if (route.includes('/_search') && typeof data === 'object' && ((data.scroll_id != null) || data.scroll)) {
    if (data.scroll === true) {
      data.scroll = '2m';
    }
    if (typeof data.scroll === 'number' || (typeof data.scroll === 'string' && !data.scroll.endsWith('m'))) {
      data.scroll += 'm';
    }
    route += (route.indexOf('?') === -1 ? '?' : '&') + 'scroll=' + ((ref9 = data.scroll) != null ? ref9 : '2m');
    if (data.scroll_id) {
      provided_scroll_id = data.scroll_id;
      route = route.split('://')[0] + '://' + route.split('://')[1].split('/')[0] + '/_search/scroll' + (route.includes('?') ? '?' + route.split('?')[1] : '');
      route += (route.indexOf('?') === -1 ? '?' : '&') + 'scroll_id=' + data.scroll_id;
      data = void 0;
    } else {
      delete data.scroll_id;
      delete data.scroll;
    }
  }
  route = route += rqp;
  opts = route.indexOf('/_bulk') !== -1 || (typeof data === 'object' && typeof data.headers === 'object') ? data : {
    body: data // fetch requires data to be body
  };
  if (route.indexOf('/_search') !== -1 && (method === 'GET' || method === 'POST')) { // scrolling isn't a new search so ignore a scroll DELETE otherwise adding the param would error
    // avoid hits.total coming back as object in new ES, because it also becomes vague
    // see hits.total https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-7.0.html
    route += (route.indexOf('?') === -1 ? '?' : '&') + 'rest_total_hits_as_int=true';
  }
  if (route.includes('/_doc/') && route.split('/_doc/')[1].includes('%')) { // fix for messy DOIs as IDs like '10.1002_(sici)1097-4644(19960601)61%3A3%253c452%3A%3Aaid-jcb12%253e3.0.co%3B2-l'
    route = route.split('/_doc/')[0] + '/_doc/' + encodeURIComponent(route.split('/_doc/')[1]);
  }
  //if @S.dev and @S.bg is true and not data?.query? and not route.includes('/_doc/') and (method is 'DELETE' or not route.includes '_search/scroll')
  //  console.log 'INDEX', method, route
  //console.log method(JSON.stringify(if Array.isArray(data) and data.length then data[0] else data).substr(0, 3000)) if data

  //opts.retry = 3
  opts.method = method;
  res = (await this.fetch(route, opts));
  //if @S.dev and @S.bg is true
  //  try console.log 'INDEX QUERY FOUND', res.hits.total, res.hits.hits.length
  if ((res == null) || (typeof res === 'object' && typeof res.status === 'number' && res.status >= 400 && res.status <= 600)) {
    // fetch returns undefined for 404, otherwise any other error from 400 is returned like status: 400
    // write a log / send an alert?
    //em = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', method: method, url: url, route: route, opts: opts, error: err.toString()
    //if this?.log? then @log(em) else P.log em
    // do anything for 409 (version mismatch?)
    return void 0;
  } else {
    if (this.S.dev && typeof res === 'object' && (res.hits != null)) {
      try {
        if ((data != null ? data.query : void 0) != null) {
          res.q = data;
        }
      } catch (error) {}
      try {
        if (alias) {
          res._alias = alias;
        }
      } catch (error) {}
    }
    if (res != null ? res._scroll_id : void 0) {
      res._scroll_id = res._scroll_id.replace(/==$/, '');
    }
    if (provided_scroll_id && provided_scroll_id !== (res != null ? res._scroll_id : void 0)) {
      await this.index._send('/_search/scroll?scroll_id=' + provided_scroll_id, '');
    }
    return res;
  }
};

// https://developers.cloudflare.com/workers/runtime-apis/kv
// Keys are always returned in lexicographically sorted order according to their UTF-8 bytes.
// NOTE these need to be awaited when necessary, as the val will be a Promise

// this is here instead of server because it can be useful to deploy a worker to cloudflare
// that does NOT use a KV on the same account it is deployed to, instead it connects 
// via another instance of Paradigm running on another account to a KV on that secondary account.
// e.g. multiple worker instances on multiple accounts sharing one resume token KV collection.
if (typeof S.kv === 'string' && S.kv.startsWith('http') && !global[S.kv]) {
  // kv is a URL back to the worker to access cloudflare kv
  global[S.kv] = {};
  global[S.kv].get = function(key) {
    return P.fetch(S.kv + '/' + key);
  };
  global[S.kv].getWithMetadata = async function(key) {
    var ret;
    ret = (await P.fetch(S.kv + '/' + key));
    return {
      value: ret,
      metadata: {} // can't get the metadata remotely
    };
  };
  global[S.kv].put = function(key, data) {
    return P.fetch(S.kv + '/' + key, {
      body: data
    });
  };
  global[S.kv].delete = function(key) {
    return P.fetch(S.kv + '/' + key, {
      method: 'DELETE'
    });
  };
  global[S.kv].list = function(opts) {
    if (opts == null) {
      opts = {};
    }
    return P.fetch(S.kv + '/list' + (opts.prefix ? '/' + opts.prefix : '') + (opts.cursor ? '?cursor=' + opts.cursor : ''));
  };
}

`if typeof S.kv isnt 'string' and S.kv isnt false
global[S.kv] = {}
global[S.kv].get = (key) ->
  kc = 'kv/' + key.replace /\//g, '_'
  ret = await P.index kc
  if ret.expiresAt and ret.expiresAt < Date.now()
    P.index kc, '' # delete
    return
  else
    try ret.val = JSON.parse ret.val
    return ret.val
global[S.kv].getWithMetadata = (key) ->
  kc = 'kv/' + key.replace /\//g, '_'
  ret = await P.index kc
  try ret.val = JSON.parse ret.val
  try ret.metadata = JSON.parse ret.metadata
  return value: ret.val, metadata: ret.metadata
global[S.kv].put = (key, data) ->
  kc = 'kv/' + key.replace /\//g, '_'
  return await P.index kc, key: key, val: JSON.stringify data
global[S.kv].delete = (key) ->
  kc = 'kv/' + key.replace /\//g, '_'
  return await P.index kc, ''
global[S.kv].list = (opts) ->
  # cursor on real kv isnt a from count, but use that for now
  # need to change this to use each properly on index, as from will only go as far as 10k
  opts ?= {}
  opts.cursor ?= 0
  ret = await P.index 'kv', (if opts.prefix then 'key:' + opts.prefix.replace(/\//g, '_') + '*' else '*'), {sort: {key: {order: 'asc'}}, from: opts.cursor}
  res = keys: []
  try
    res.cursor: opts.cursor + 1000
    if res.cursor >= ret.hits.total
      res.list_complete = true
      delete res.cursor
    for k in ret.hits.hits
      res.keys.push k._source.key
  return res`;

P.kv = async function(key, val, ttle, metadata, type) {
  var i, j, k, len, len1, m, ref, ref1, ref2, ref3, ref4, ref5, ref6, value;
  // val can be string, stream, buffer. The type gets inferred.
  // ONE of expire or ttl can optionally be provided, expiration is seconds since epoch timestamp, ttl is seconds from now until expiry
  // so ttle can be either. If ttle*1000 is greater than Date.now it will be used as expiration timestamp in seconds, otherwise will be used as ttl in seconds
  // ttle can also be true, or an object, to cause a merge of val if val is also an object (true entails retrieving it from storage then merging)
  // metadata and type are not necessary, but included here for completeness
  // metadata can be any JSON object under 1024 bytes
  // type is optional, can be "text", "json", "arrayBuffer" or "stream", and that what the val will be provided as.
  if (key == null) {
    key = (ref = (ref1 = this.params.kv) != null ? ref1 : this.params.key) != null ? ref : this.parts.join('_');
    if (val == null) {
      if (this.request.method === 'DELETE') { //or @params._delete
        val = '';
      } else if (this.body) {
        val = this.body;
      } else if (this.params.val) {
        val = this.params.val;
      } else {
        val = this.params;
        ref2 = ['key', 'kv', 'refresh', 'apikey'];
        for (i = 0, len = ref2.length; i < len; i++) {
          k = ref2[i];
          delete val[k];
        }
        ref3 = this.parts;
        for (j = 0, len1 = ref3.length; j < len1; j++) {
          k = ref3[j];
          delete val[k];
        }
      }
      if (typeof val === 'string' && (val.indexOf('[') === 0 || val.indexOf('{') === 0)) {
        val = JSON.parse(val);
      }
      if ((ref4 = JSON.stringify(val)) === '{}' || ref4 === '[]') {
        val = void 0;
      }
    }
  }
  if (typeof val === 'object' && ((ref5 = JSON.stringify(val)) === '{}' || ref5 === '[]')) {
    val = void 0;
  }
  if (typeof key === 'object' && (val == null)) {
    val = key;
    key = (ref6 = val._id) != null ? ref6 : (await this.uid());
  }
  if ((key != null) && this.S.kv && global[this.S.kv]) {
    if ((val != null) && val !== '') {
      m = {
        metadata: metadata
      };
      if (typeof ttle === 'number') {
        if ((ttle * 1000) > Date.now()) {
          m.expiration = ttle;
        } else {
          m.expirationTtl = ttle;
        }
      }
      if (typeof val === 'object') { // val needs to be string, arrayBuffer, or readableStream
        if (ttle === true) {
          ttle = (await this.kv(key)); // get the current state of the record
        }
        if (typeof ttle === 'object') { // this is an update to be merged in
// handle dot notations?
          for (k in ttle) {
            if (val[k] == null) {
              val[k] = ttle[k];
            }
          }
        }
      }
      this.waitUntil(global[this.S.kv].put(key, (typeof val === 'object' ? JSON.stringify(val) : val), m));
      return val;
    } else {
      ({value, metadata} = (await global[this.S.kv].getWithMetadata(key, type)));
      if (value != null) {
        try {
          value = JSON.parse(value);
        } catch (error) {}
        try {
          metadata = JSON.parse(metadata);
        } catch (error) {}
        if (val === '') {
          this.waitUntil(global[this.S.kv].delete(key)); // remove a key after retrieval
        }
        if (metadata === true) {
          return {
            value: value,
            metadata: metadata
          };
        } else {
          return value;
        }
      }
    }
  }
};

P.kv._auths = 'system';

P.kv._caches = false;

P.kv.list = async function(prefix, cursor) {
  var ref, ref1;
  try {
    if (prefix == null) {
      prefix = (ref = (ref1 = this.params.kv) != null ? ref1 : this.params.prefix) != null ? ref : this.params.list;
    }
  } catch (error) {}
  try {
    if (cursor == null) {
      cursor = this.params.cursor;
    }
  } catch (error) {}
  return (await global[this.S.kv].list({
    prefix: prefix,
    cursor: cursor
  }));
};

// NOTE that count on kv is expensive because it requires listing everything
// so these count/prefixes/clear actions are really only for dev convenience
// not good for production scale
P.kv.count = async function(prefix) {
  var complete, counter, cursor, i, k, len, ls, ref, ref1, ref2;
  counter = 0;
  if (this.S.kv && (global[this.S.kv] != null)) {
    if (prefix == null) {
      prefix = (ref = (ref1 = this.params.kv) != null ? ref1 : this.params.prefix) != null ? ref : this.params.count;
    }
    complete = false;
    cursor = void 0;
    while (!complete) {
      ls = (await global[this.S.kv].list({
        prefix: prefix,
        cursor: cursor
      }));
      cursor = ls.cursor;
      ref2 = ls.keys;
      for (i = 0, len = ref2.length; i < len; i++) {
        k = ref2[i];
        counter += 1;
      }
      complete = ls.list_complete;
    }
  }
  return counter;
};

P.kv.prefixes = async function() {
  var prefixes;
  prefixes = {};
  await this.kv._each(void 0, function(k) {
    var kp;
    kp = k.split('/')[0];
    if (prefixes[kp] == null) {
      prefixes[kp] = 0;
    }
    return prefixes[kp] += 1;
  });
  return prefixes;
};

P.kv.clear = function(prefix) {
  var ref;
  if (this.S.dev) {
    if (prefix == null) {
      prefix = (ref = this.params.clear) != null ? ref : this.params.kv;
    }
    this.waitUntil(this.kv._each(prefix, function(k) {
      return this.waitUntil(global[this.S.kv].delete(k));
    }));
    return true;
  }
};

// NOTE there is no bulk delete option on the bound kv. It can be done via the API 
// but requires the API tokens which aren't shared in the deployed code. Could be 
// done manually via a script on bg. Or have bg iterate calls to frontend until it 
// can no longer count any existing.
// A LOOPING CLEAR AS ABOVE GETS RID OF ABOUT 200 KV ENTRIES BEFORE IT TIMES OUT
P.kv.delete = async function(prefix) {
  var count, ref, ref1, res;
  if (typeof this.S.kv === 'string' && this.S.kv.startsWith('http')) { // which it should if kv is available from bg
    if (prefix == null) {
      prefix = (ref = (ref1 = this.params.kv) != null ? ref1 : this.params.delete) != null ? ref : this.params.prefix;
    }
    count = (await this.fetch(this.S.kv + '/count' + (prefix ? '/' + prefix : '')));
    res = count;
    while (count && count !== '0') {
      if (this.S.dev) {
        console.log(prefix, count);
      }
      await this.fetch(this.S.kv + '/clear' + (prefix ? '/' + prefix : ''));
      await this.sleep(500);
      count = (await this.fetch(this.S.kv + '/count' + (prefix ? '/' + prefix : '')));
    }
    return res;
  }
};

P.kv.delete._bg = true;

P.kv._each = async function(prefix, fn) {
  var complete, counter, cursor, i, k, len, ls, ref, results;
  counter = 0;
  if (this.S.kv && (global[this.S.kv] != null)) {
    if (typeof prefix === 'function' && (fn == null)) {
      fn = prefix;
      prefix = void 0;
    }
    complete = false;
    cursor = void 0;
    results = [];
    while (!complete) {
      ls = (await global[this.S.kv].list({
        prefix: prefix,
        cursor: cursor
      }));
      cursor = ls.cursor;
      ref = ls.keys;
      for (i = 0, len = ref.length; i < len; i++) {
        k = ref[i];
        counter += 1;
        if (typeof fn === 'function') {
          this.waitUntil(fn.call(this, k.name));
        } else if (fn === '') {
          this.waitUntil(global[this.S.kv].delete(k.name));
        } else if (fn != null) {
          this.waitUntil(this.kv(k.name, fn));
        }
      }
      results.push(complete = ls.list_complete);
    }
    return results;
  }
};

var _bg_last_log_batch, _bg_log_batch, _bg_log_batch_timeout;

if (S.log == null) {
  S.log = {};
}

_bg_log_batch = [];

_bg_log_batch_timeout = false;

_bg_last_log_batch = false;

P.log = function(msg, store) {
  var _save_batch, i, j, l, len, len1, p, ref, ref1, ref2;
  _save_batch = async() => {
    var _batch, _last, indexed;
    if (_bg_log_batch_timeout !== false) {
      clearTimeout(_bg_log_batch_timeout);
    }
    _bg_log_batch_timeout = setTimeout(_save_batch, 30000);
    _bg_last_log_batch = Date.now();
    _last = (new Date(_bg_last_log_batch)).toISOString().replace('T', ' ').split('.')[0];
    _batch = [];
    while (_batch.length < 400 && _bg_log_batch.length) {
      _batch.push(_bg_log_batch.shift());
    }
    if (_batch.length) {
      if (this.S.bg === true) {
        console.log('Writing ' + _batch.length + ' logs to index', _batch[0]._id, _batch[_batch.length - 1]._id, _last);
      }
      if (!(indexed = (await this.index('logs', _batch)))) {
        await this.index('logs', {});
        await this.index('logs', _batch);
      }
      return _batch = [];
    } else if (this.S.bg === true) {
      return console.log('Checked log batch but none to save', _last);
    }
  };
  if (this.S.log !== false) {
    if (store !== true) { // an empty call to log stores everything in the _logs list
      store = msg == null;
    }
    if (store !== true && (this._logs.length > 30000 || _bg_log_batch.length > 30000)) {
      store = true;
    }
    if (typeof msg === 'string') {
      if (msg.indexOf('/') !== -1 && msg.indexOf(' ') === -1) {
        msg = {
          fn: msg
        };
      } else {
        msg = {
          msg: msg
        };
      }
    } else if (Array.isArray(msg)) {
      for (i = 0, len = msg.length; i < len; i++) {
        l = msg[i];
        this._logs.push(l);
      }
      msg = void 0;
    }
    if (msg == null) {
      if (this.parts.length === 1 && this.parts[0] === 'log') { // should a remote log be allowed to send to a sub-route URL as an ID? maybe with particular auth?
        if (this.system) {
          _bg_log_batch.push(this.body);
          if (_bg_log_batch_timeout === false) {
            _save_batch();
          }
          return true; // end here, just saving a log received from remote with system credential
        } else {
          // receive a remote log - what permissions should be required?
          msg = typeof this.body === 'object' ? this.body : this.params; // bunch of logs sent in as POST body, or else just params
          if (Array.isArray(msg)) {
            msg = {
              logs: msg
            };
          }
        }
      }
      if (msg == null) {
        msg = {};
      }
      try {
        msg.request = {
          url: this.request.url,
          method: this.request.method
        };
      } catch (error) {}
      try {
        msg.request.body = this.body != null;
      } catch (error) {}
      try {
        msg.request.cf = {
          colo: this.request.cf.colo,
          country: this.request.cf.country
        };
      } catch (error) {}
      try {
        msg.request.headers = this.headers; // just get all headers to see what's useful?
        if (msg.request.headers.cookie) {
          msg.cookie = true;
          delete msg.request.headers.cookie;
        }
      } catch (error) {}
      try {
        if ((msg.fn == null) && (this.fn != null)) {
          //catch
          //try
          //  msg.request.headers = {}
          //  msg.headers.ip = (@headers['x-forwarded-for'] ? @headers['x-real-ip']) if @headers['x-real-ip'] or @headers['x-forwarded-for']
          //  msg.headers['user-agent'] = @headers['user-agent'] if @headers['user-agent']
          //  msg.headers.referer = @headers.referer if @headers.referer
          msg.fn = this.fn;
        }
        if (this.refresh) {
          msg.refresh = this.refresh;
        }
        msg.parts = this.parts;
        if (this.completed) {
          msg.completed = this.completed;
        }
        if (this.cached) {
          msg.cached = this.cached;
        }
      } catch (error) {}
      try {
        // don't stringify the whole obj, allow individual keys, but make them all strings to avoid mapping clashes
        msg.params = {};
        for (p in this.params) {
          msg.params[p] = typeof this.params[p] === 'string' ? this.params[p] : JSON.stringify(this.params[p]);
        }
      } catch (error) {}
      try {
        msg.apikey = this.apikey != null; // only record if apikey was provided or not
      } catch (error) {}
      try {
        if (((ref = this.user) != null ? ref._id : void 0) != null) {
          msg.user = this.user._id;
        }
      } catch (error) {}
      if (this.unauthorised) {
        msg.unauthorised = true;
      }
    }
    if (store) {
      if (!msg.logs) {
        msg.logs = [];
        if (Array.isArray(this != null ? this._logs : void 0) && this._logs.length) {
          ref1 = this._logs;
          for (j = 0, len1 = ref1.length; j < len1; j++) {
            l = ref1[j];
            if (l.alert) {
              //msg.msg ?= l.msg
              if (msg.alert == null) {
                msg.alert = l.alert;
              }
            }
            if (l.notify) {
              if (msg.notify == null) {
                msg.notify = l.notify;
              }
            }
            msg.logs.push(l);
          }
        }
      }
      msg.createdAt = new Date(); //Date.now()
      if (msg.name == null) {
        msg.name = S.name;
      }
      if (msg.version == null) {
        msg.version = S.version;
      }
      msg.base = this.base;
      if (this.domain) {
        msg.domain = this.domain;
      }
      if (this.S.bg === true) {
        msg.bg = true;
      }
      if (this.system === true) {
        msg.system = true;
      }
      if (this.scheduled === true) {
        msg.scheduled = true;
      }
      try {
        msg.started = this.started;
        msg.took = Date.now() - this.started;
      } catch (error) {}
      msg._id = this.rid;
      if (((ref2 = this.S.index) != null ? ref2.url : void 0) != null) {
        if (this.S.bg === true) {
          _bg_log_batch.push(msg);
          if ((typeof this.S.log === 'object' && this.S.log.batch === false) || _bg_log_batch.length > 300 || _bg_last_log_batch === false || Date.now() > (_bg_last_log_batch + 30000)) {
            _save_batch();
          }
        } else if (typeof this.S.bg !== 'string' || (typeof this.S.log === 'object' && this.S.log.batch === false)) {
          _bg_log_batch.push(msg);
          this.waitUntil(_save_batch());
        } else {
          this.waitUntil(this.fetch(this.S.bg + '/log', {
            body: msg
          }));
        }
      } else {
        try {
          this.kv('logs/' + msg._id, msg);
        } catch (error) {
          console.log('Logging unable to save to kv or index');
          consolg.log(msg);
        }
      }
    } else {
      this._logs.push(msg);
    }
  } else if (this.S.dev && this.S.bg === true) {
    console.log('NOT logging', msg);
  }
  return true;
};

P.logs = {
  _index: true,
  _auth: 'system'
};

try {
  S.mail = JSON.parse(SECRETS_MAIL);
} catch (error) {
  S.mail = {};
}

P.mail = async function(opts) {
  var f, fa, i, len, ms, p, parts, pl, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, url;
  if ((ref = S.mail) != null ? ref.disabled : void 0) {
    return {};
  }
  if (typeof opts === 'string') {
    opts = {
      text: opts
    };
  }
  if (opts == null) {
    opts = (ref1 = this.copy(this != null ? this.params : void 0)) != null ? ref1 : {};
  }
  if (opts.template) {
    parts = (await this.template(opts.template, (ref2 = (ref3 = opts.vars) != null ? ref3 : opts.params) != null ? ref2 : opts));
    for (p in parts) {
      opts[p] = parts[p];
    }
    delete opts.template;
    delete opts.vars;
    delete opts.params;
  }
  if (!opts.text && !opts.html) {
    opts.text = (ref4 = (ref5 = (ref6 = (ref7 = opts.content) != null ? ref7 : opts.msg) != null ? ref6 : opts.body) != null ? ref5 : this.body) != null ? ref4 : '';
    if (typeof opts.text === 'object') {
      try {
        opts.text = (await this.convert.json2html(opts.text));
      } catch (error) {
        opts.text = JSON.stringify(opts.text);
      }
    }
  }
  delete opts.content;
  delete opts.body;
  if (!opts.html && typeof opts.text === 'string' && opts.text.indexOf('<') !== -1 && opts.text.indexOf('>') !== -1) {
    opts.html = opts.text;
  }
  // can also take opts.headers
  // also takes opts.attachment, but not required. Should be a list of objects
  ms = (opts.svc || opts.service) && (((ref8 = this.S.svc[(ref9 = opts.svc) != null ? ref9 : opts.service]) != null ? ref8.mail : void 0) != null) ? this.S.svc[(ref10 = opts.svc) != null ? ref10 : opts.service].mail : (ref11 = this != null ? (ref12 = this.S) != null ? ref12.mail : void 0 : void 0) != null ? ref11 : S.mail;
  if (opts.from == null) {
    opts.from = ms.from;
  }
  if (opts.to == null) {
    opts.to = ms.to;
  }
  delete opts.svc;
  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages';
  if (Array.isArray(opts.to)) {
    opts.to = opts.to.join(',');
  }
  if (opts.to) {
    f = (ref13 = this != null ? this.fetch : void 0) != null ? ref13 : P.fetch;
    pl = {
      method: 'POST',
      auth: 'api:' + ms.apikey
    };
    ref14 = ['file', 'files', 'attachment', 'attachments'];
    for (i = 0, len = ref14.length; i < len; i++) {
      fa = ref14[i];
      if (opts[fa] != null) {
        pl[fa] = opts[fa];
        delete opts[fa];
      }
    }
    pl.form = opts;
    return (await f(url, pl));
  } else {
    console.log(opts);
    console.log('NO ADDRESS TO EMAIL TO');
    return {};
  }
};

P.mail._auth = 'system';

P.mail.validate = async function(e, mgkey) {
  var ns, nsp, ref, ref1, v;
  //mgkey ?= @S.mail?.pubkey
  if (e == null) {
    e = this != null ? (ref = this.params) != null ? ref.email : void 0 : void 0;
  }
  if (typeof e === 'string' && e.length && (e.indexOf(' ') === -1 || (e.startsWith('"') && e.split('"@').length === 2))) {
    try {
      if (typeof mgkey === 'string') {
        v = (await this.fetch('https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e) + '&api_key=' + mgkey));
        return (ref1 = v.did_you_mean) != null ? ref1 : v.is_valid;
      }
    } catch (error) {}
    //(?:[a-z0-9!#$%&amp;'*+/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&amp;'*+/=?^_`{|}~-]+)*|"(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21\x23-\x5b\x5d-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])*")@(?:(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?|\[(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?|[a-z0-9-]*[a-z0-9]:(?:[\x01-\x08\x0b\x0c\x0e-\x1f\x21-\x5a\x53-\x7f]|\\[\x01-\x09\x0b\x0c\x0e-\x7f])+)\])
    ns = e.split('@');
    if (ns.length === 2 && ns[0].length && ns[0].length < 65 && ((ns[0].startsWith('"') && ns[0].endsWith('"')) || (ns[0].indexOf(' ') === -1 && ns[0].indexOf(',') === -1 && ns[0].indexOf(':') === -1 && ns[0].indexOf(';') === -1))) {
      if (ns[1].length && ns[1].indexOf(',') === -1 && ns[1].indexOf(' ') === -1) {
        nsp = ns[1].split('.');
        if (nsp.length > 1 && (nsp.length !== 2 || nsp[0] !== 'example')) {
          return true;
        }
      }
    }
  }
  return false;
};

var indexOf = [].indexOf;

P.copy = function(obj) {
  try {
    if (obj == null) {
      obj = this.params;
    }
  } catch (error) {}
  return JSON.parse(JSON.stringify(obj));
};

`P.dot = (obj, key) ->
if typeof obj is 'string' and typeof key is 'object'
  st = obj
  obj = key
  key = st
if not obj? and this?.params?.key?
  obj = @copy @params
  key = obj.key
key = key.split('.') if typeof key is 'string'
try
  res = obj
  res = res[k] for k in key
  return res
catch
  return`;

P.copy._log = false;

P.dot = function(o, k, v, d, ae) { // ae will attempt to recurse into the last object element of an array rather than return undefined for failing to match a key on the list element
  var base, name, oo;
  if (typeof k === 'string') {
    return P.dot(o, k.split('.'), v, d, ae);
  } else if (k.length === 1 && ((v != null) || (d != null))) {
    if (d != null) {
      if (o instanceof Array) {
        o.splice(k[0], 1);
      } else {
        delete o[k[0]];
      }
      return true;
    } else {
      if (ae && Array.isArray(o) && typeof k[0] !== 'number' && isNaN(parseInt(k[0]))) {
        if (!o.length) {
          o = [{}];
        }
        o[o.length - 1][k[0]] = v;
      } else {
        o[k[0]] = v;
      }
      return true;
    }
  } else if (k.length === 0) {
    return o;
  } else {
    if (o[k[0]] == null) {
      if (v != null) {
        o[k[0]] = typeof k[0] === 'number' || !isNaN(parseInt(k[0])) ? [] : {};
        return P.dot(o[k[0]], k.slice(1), v, d, ae);
      } else if (ae && Array.isArray(o) && o.length && (oo = o[o.length - 1] && typeof oo === 'object' && (oo[k[0]] != null))) {
        return P.dot(oo[k[0]], k.slice(1), v, d, ae);
      } else {
        return void 0;
      }
    } else {
      if (ae && Array.isArray(o) && typeof k[0] !== 'number' && isNaN(parseInt(k[0])) && o.length && typeof o[o.length - 1] === 'object') { // and not o[k[0]]? 
        if (v != null) {
          if ((base = o[o.length - 1])[name = k[0]] == null) {
            base[name] = {};
          }
        }
        return P.dot(o[o.length - 1][k[0]], k.slice(1), v, d, ae);
      } else {
        return P.dot(o[k[0]], k.slice(1), v, d, ae);
      }
    }
  }
};

P.dot._log = false;

P.flatten = async function(obj, arrayed) {
  var _flatten, d, i, len, ref, res, results;
  if (arrayed == null) {
    arrayed = (ref = this.params.arrayed) != null ? ref : false; // arrayed puts objects in arrays at keys like author.0.name Whereas not arrayed shoves them all in one author.name (which means some that don't have the value could cause position mismatch in lists)
  }
  if (obj == null) {
    obj = this.params;
    delete obj.arrayed;
  }
  res = {};
  _flatten = async function(obj, key) {
    var av, isnum, k, n, pk, results1, v;
    results1 = [];
    for (k in obj) {
      isnum = false;
      try {
        isnum = !isNaN(parseInt(k));
      } catch (error) {}
      pk = isnum && !arrayed ? key : key ? key + '.' + k : k;
      v = obj[k];
      if (typeof v !== 'object') {
        if (res[pk] != null) {
          if (!Array.isArray(res[pk])) {
            res[pk] = [res[pk]];
          }
          results1.push(res[pk].push(v));
        } else {
          results1.push(res[pk] = v);
        }
      } else if (Array.isArray(v)) {
        if (typeof v[0] === 'object') {
          results1.push((await (async function() {
            var results2;
            results2 = [];
            for (n in v) {
              results2.push((await _flatten(v[n], pk + (arrayed ? '.' + n : ''))));
            }
            return results2;
          })()));
        } else {
          if (res[pk] == null) {
            res[pk] = [];
          }
          if (!Array.isArray(res[pk])) {
            res[pk] = [res[pk]];
          }
          results1.push((function() {
            var i, len, results2;
            results2 = [];
            for (i = 0, len = v.length; i < len; i++) {
              av = v[i];
              results2.push(res[pk].push(av));
            }
            return results2;
          })());
        }
      } else {
        //res[pk] += (if res[pk] then ', ' else '') + v.join ', '
        //res[pk] = v.join ', '
        results1.push((await _flatten(v, pk)));
      }
    }
    return results1;
  };
  if (Array.isArray(obj)) {
    results = [];
    for (i = 0, len = data.length; i < len; i++) {
      d = data[i];
      res = {};
      results.push((await _flatten(d)));
    }
    return results;
  } else {
    await _flatten(obj);
    return res;
  }
};

//P.flatest = () ->
//  res = original: await @src.openalex.works 'doi.keyword:"https://doi.org/10.1016/j.mee.2015.04.018"', 1 #@src.crossref.works '10.1016/j.mee.2015.04.018' #@report.works '10.1016/j.socnet.2021.02.007'
//  res.flat = await @flatten res.original
//  res.arrayed = await @flatten res.original, true
//  return [res.arrayed]
P.keys = function(obj) {
  var k, keys;
  try {
    if (obj == null) {
      obj = this.params;
    }
  } catch (error) {}
  keys = [];
  for (k in obj != null ? obj : {}) {
    if ((obj[k] != null) && indexOf.call(keys, k) < 0) {
      keys.push(k);
    }
  }
  return keys;
};

P.pings = {
  _index: true
};

P.ping = async function() {
  var data, ref, ref1;
  data = this.copy(this.params);
  if (JSON.stringify(data) !== '{}') {
    data.ip = (ref = (ref1 = this.headers['x-forwarded-for']) != null ? ref1 : this.headers['cf-connecting-ip']) != null ? ref : this.headers['x-real-ip'];
    data.forwarded = this.headers['x-forwarded-for'];
    await this.pings(data);
    return true;
  } else {
    return false;
  }
};

// https://jcheminf.springeropen.com/articles/10.1186/1758-2946-3-47
P.scrape = async function(content, doi) {
  var cl, cnts, d, i, j, k, kk, l, len, len1, len2, len3, len4, m, me, meta, mk, mkp, mls, mm, mr, mstr, my, n, o, p, q, ref, ref1, ref2, ref3, ref4, str, ud;
  if (content == null) {
    content = (ref = (ref1 = this.params.scrape) != null ? ref1 : this.params.content) != null ? ref : this.params.url;
  }
  if (doi == null) {
    doi = this.params.doi;
  }
  meta = {
    doi: doi
  };
  if (typeof content === 'string' && content.startsWith('http')) {
    if (!meta.doi) { // quick check to get a DOI if at the end of a URL, as they often are
      mr = new RegExp(/\/(10\.[^ &#]+\/[^ &#]+)$/);
      ud = mr.exec(decodeURIComponent(content));
      if (ud && ud.length > 1 && 9 < ud[1].length && ud[1].length < 45 && ud[1].indexOf('/') !== -1 && ud[1].indexOf('10.') === 0) {
        meta.doi = ud[1];
      }
    }
    //content = await @puppet content
    content = (await this.fetch(content));
  }
  if (typeof content !== 'string') {
    return {};
  }
  if (content.indexOf('<') !== 0 && content.length > 6000) {
    content = content.substring(0, 6000); // we only check the first three or so pages of content (3000 chars per page estimates 500 words per page)
  } else if (content.length > 50000) {
    content = content.substring(0, 50000); // but for apparently html or xml sorts of content, take more to get through all metadata
  }
  if (!meta.doi) {
    try {
      cl = content.toLowerCase();
      if (cl.indexOf('dc.identifier') !== -1) {
        cl = cl.split('dc.identifier')[1].split('content')[1];
        if (cl.indexOf('"') !== -1) {
          cl = cl.split('"')[1];
        }
        if (cl.indexOf("'") !== -1) {
          cl = cl.split("'")[1];
        }
        if (cl.indexOf('10.') === 0 && cl.indexOf('/') !== -1) {
          meta.doi = cl;
        }
      }
    } catch (error) {}
  }
  if (!meta.doi) {
    try {
      if (cl == null) {
        cl = content.toLowerCase();
      }
      if (cl.indexOf('citation_doi') !== -1) {
        cl = cl.split('citation_doi')[1].split('content')[1];
        if (cl.indexOf('"') !== -1) {
          cl = cl.split('"')[1];
        }
        if (cl.indexOf("'") !== -1) {
          cl = cl.split("'")[1];
        }
        if (cl.indexOf('10.') === 0 && cl.indexOf('/') !== -1) {
          meta.doi = cl;
        }
      }
    } catch (error) {}
  }
  if (!meta.doi) { // look for a doi in the first 600 words
    try {
      cnts = 0;
      ref2 = content.split(' ');
      for (j = 0, len = ref2.length; j < len; j++) {
        str = ref2[j];
        cnts += 1;
        if (cnts < 600) {
          str = str.replace(/ /g, '').replace('doi:', '');
          if (str.indexOf('doi.org') !== -1) {
            str = str.split('doi.org')[1];
          }
          if (str.indexOf('/') === 0) {
            str = str.replace('/', '');
          }
          str = str.trim();
          if (str.indexOf('10.') === 0 && str.indexOf('/') !== -1) { // don't use a regex
            meta.doi = str;
            break;
          }
        }
      }
    } catch (error) {}
  }
  if (!meta.doi) {
    try {
      d = (await this.extract({
        content: content,
        matchers: ['/doi[^>;]*?(?:=|:)[^>;]*?(10[.].*?\/.*?)("|\')/gi', '/doi[.]org/(10[.].*?/.*?)("| \')/gi']
      }));
      ref3 = d.matches;
      for (l = 0, len1 = ref3.length; l < len1; l++) {
        n = ref3[l];
        if (!meta.doi && 9 < d.matches[n].result[1].length && d.matches[n].result[1].length < 45) {
          meta.doi = d.matches[n].result[1];
          if (meta.doi.endsWith('.')) {
            meta.doi = meta.doi.substring(0, meta.doi.length - 1);
          }
        }
      }
    } catch (error) {}
  }
  if (meta.doi) { // catch some spacing issues that sometimes come through
    meta.doi = meta.doi.split(' ')[0];
  }
  if (!meta.title) {
    try {
      cl = content.toLowerCase();
      if (cl.indexOf('requestdisplaytitle') !== -1) {
        meta.title = cl.split('requestdisplaytitle').pop().split('>')[1].split('<')[0].trim().replace(/"/g, '');
      } else if (cl.indexOf('dc.title') !== -1) {
        meta.title = cl.split('dc.title')[1].replace(/'/g, '"').split('content=')[1].split('"')[1].trim().replace(/"/g, '');
      } else if (cl.indexOf('eprints.title') !== -1) {
        meta.title = cl.split('eprints.title')[1].replace(/'/g, '"').split('content=')[1].split('"')[1].trim().replace(/"/g, '');
      } else if (cl.indexOf('og:title') !== -1) {
        meta.title = cl.split('og:title')[1].split('content')[1].split('=')[1].replace('/>', '>').split('>')[0].trim().replace(/"/g, '');
        if (meta.title.startsWith("'")) {
          meta.title = meta.title.substring(1, meta.title.length - 1);
        }
      } else if (cl.indexOf('"citation_title" ') !== -1) {
        meta.title = cl.split('"citation_title" ')[1].replace(/ = /, '=').split('content="')[1].split('"')[0].trim().replace(/"/g, '');
      } else if (cl.indexOf('<title') !== -1) {
        meta.title = cl.split('<title')[1].split('>')[1].split('</title')[0].trim().replace(/"/g, '');
      }
    } catch (error) {}
  }
  if (meta.title && meta.title.indexOf('|') !== -1) {
    meta.title = meta.title.split('|')[0].trim();
  }
  if (!meta.year) {
    try {
      k = (await this.extract({
        content: content,
        matchers: ['/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')citation_date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi', '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')dc.date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi', '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')prism.publicationDate(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi'],
        start: '<head',
        end: '</head'
      }));
      mk = k.matches[0].result[1];
      mkp = mk.split('-');
      if (mkp.length === 1) {
        meta.year = mkp[0];
      } else {
        for (o = 0, len2 = mkp.length; o < len2; o++) {
          my = mkp[o];
          if (my.length > 2) {
            meta.year = my;
          }
        }
      }
    } catch (error) {}
  }
  if (!meta.keywords) {
    try {
      k = (await this.extract({
        content: content,
        matchers: ['/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')keywords(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi'],
        start: '<head',
        end: '</head'
      }));
      kk = k.matches[0].result[1];
      if (kk.indexOf(';') !== -1) {
        kk = kk.replace(/; /g, ';').replace(/ ;/g, ';');
        meta.keywords = kk.split(';');
      } else {
        kk = kk.replace(/, /g, ',').replace(/ ,/g, ',');
        meta.keywords = kk.split(',');
      }
    } catch (error) {}
  }
  if (!meta.email) {
    mls = [];
    try {
      m = (await this.extract({
        content: content,
        matchers: ['/mailto:([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi', '/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
      }));
      ref4 = m.matches;
      for (p = 0, len3 = ref4.length; p < len3; p++) {
        i = ref4[p];
        mm = i.result[1].replace('mailto:', '');
        if (mm.endsWith('.')) {
          mm = mm.substring(0, mm.length - 1);
        }
        if (mls.indexOf(mm) === -1) {
          mls.push(mm);
        }
      }
    } catch (error) {}
    mls.sort((function(a, b) {
      return b.length - a.length;
    }));
    mstr = '';
    for (q = 0, len4 = mls.length; q < len4; q++) {
      me = mls[q];
      if (meta.email == null) {
        meta.email = [];
      }
      if (mstr.indexOf(me) === -1) {
        meta.email.push(me);
      }
      mstr += me;
    }
  }
  return meta;
};

P.sleep = function(ms) { // await this when calling it to actually wait
  try {
    if (ms == null) {
      ms = this.params.ms;
    }
  } catch (error) {}
  return new Promise((resolve) => {
    return setTimeout(resolve, ms != null ? ms : 1000);
  });
};

P.sleep._auth = 'root';

P.sleep._log = false;

var indexOf = [].indexOf;

P.template = async function(content, vars) {
  var _rv, cp, cs, i, j, k, key, keyu, kg, kkg, len, len1, pcp, ref, ref1, ref2, ref3, ret, val, vs;
  if (content == null) {
    content = (ref = (ref1 = this.params.content) != null ? ref1 : this.params.template) != null ? ref : this.body;
  }
  if (vars == null) {
    vars = this.params;
  }
  if (this.params.url || content.startsWith('http')) {
    content = (await this.fetch((ref2 = this.params.url) != null ? ref2 : content));
  }
  if (content.indexOf(' ') === -1 && content.indexOf('.') !== -1 && content.length < 100) {
    try {
      cs = (await this.templates(content));
      content = cs.content;
    } catch (error) {}
  }
  ret = {};
  _rv = function(obj, pre = '') {
    var o, ov, results, rg;
    results = [];
    for (o in obj) {
      ov = pre ? pre + '.' + o : o;
      if (typeof obj[o] === 'object' && !Array.isArray(obj[o])) {
        results.push(_rv(obj[o], pre + (pre === '' ? '' : '.') + o));
      } else if (content.toLowerCase().indexOf('{{' + ov + '}}') !== -1) {
        rg = new RegExp('{{' + ov + '}}', 'gi');
        results.push(content = content.replace(rg, (Array.isArray(obj[o]) ? obj[o].join(', ') : (typeof obj[o] === 'string' ? obj[o] : (obj[o] === true ? 'Yes' : (obj[o] === false ? 'No' : ''))))));
      } else {
        results.push(void 0);
      }
    }
    return results;
  };
  _rv(vars); // replace all vars that are in the content
  kg = new RegExp('{{.*?}}', 'gi');
  if (content.indexOf('{{') !== -1) { // retrieve any vars provided IN the content (e.g. a content template can specify a subject for an email to use)
    vs = ['subject', 'from', 'to', 'cc', 'bcc'];
    ref3 = content.toLowerCase().split('{{');
    // the could be vars in content that themselves contain vars, e.g {{subject I am the subject about {{id}} yes I am}}
    // and some of those vars may fail to get filled in. So define the list of possible vars names THEN go through the content with them
    for (i = 0, len = ref3.length; i < len; i++) {
      cp = ref3[i];
      pcp = cp.split('{{')[0].split('}}')[0].split(' ')[0];
      if (indexOf.call(vs, pcp) < 0) {
        vs.push(pcp);
      }
    }
    for (j = 0, len1 = vs.length; j < len1; j++) {
      k = vs[j];
      key = content.toLowerCase().indexOf('{{' + k) !== -1 ? k : void 0;
      if (key) {
        keyu = content.indexOf('{{' + key.toUpperCase()) !== -1 ? key.toUpperCase() : key;
        val = content.split('{{' + keyu)[1];
        if (val.split('}}')[0].indexOf('{{')) { // remove any vars present inside this one that were not able to have their values replaced
          val = val.replace(kg, '');
        }
        val = val.split('}}')[0].trim();
        if (val) {
          ret[key] = val;
        }
        kkg = new RegExp('{{' + keyu + '.*?}}', 'gi');
        content = content.replace(kkg, '');
      }
    }
  }
  if (content.indexOf('{{') !== -1) { // remove any outstanding vars in content that could not be replaced by provided vars
    content = content.replace(kg, '');
  }
  ret.content = content;
  // TODO consider if worth putting markdown formatting back in here, and how big a markdown parser is
  return ret; // an obj of the content plus any vars found within the template
};

P.templates = {
  _key: 'name',
  _sheet: '1Xg-dBpCkVWglditd6gESYRgMtve4CAImXe-321ra2fo/Templates'
};

P.levenshtein = function(a, b, lowercase) {
  var c, cost, i, j, m, minimator, n, o, r, ref, ref1, ref2, ref3;
  if (a == null) {
    a = this != null ? (ref = this.params) != null ? ref.a : void 0 : void 0;
  }
  if (b == null) {
    b = this != null ? (ref1 = this.params) != null ? ref1.b : void 0 : void 0;
  }
  if (lowercase == null) {
    lowercase = (ref2 = this != null ? (ref3 = this.params) != null ? ref3.lowercase : void 0 : void 0) != null ? ref2 : true;
  }
  if (lowercase) {
    a = a.toLowerCase();
    b = b.toLowerCase();
  }
  minimator = function(x, y, z) {
    if (x <= y && x <= z) {
      return x;
    }
    if (y <= x && y <= z) {
      return y;
    }
    return z;
  };
  m = a.length;
  n = b.length;
  if (m < n) {
    c = a;
    a = b;
    b = c;
    o = m;
    m = n;
    n = o;
  }
  r = [[]];
  c = 0;
  while (c < n + 1) {
    r[0][c] = c;
    c++;
  }
  i = 1;
  while (i < m + 1) {
    r[i] = [i];
    j = 1;
    while (j < n + 1) {
      cost = a.charAt(i - 1) === b.charAt(j - 1) ? 0 : 1;
      r[i][j] = minimator(r[i - 1][j] + 1, r[i][j - 1] + 1, r[i - 1][j - 1] + cost);
      j++;
    }
    i++;
  }
  return {
    distance: r[r.length - 1][r[r.length - 1].length - 1],
    length: {
      a: m,
      b: n //, detail: r
    }
  };
};

P.extract = async function(opts) {
  var k, lastslash, len, m, match, mopts, mr, parts, ref, ref1, res, text;
  // opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
  if (opts == null) {
    opts = this.copy(this.params);
  }
  if (opts.url && !opts.content) {
    if (opts.url.indexOf('.pdf') !== -1 || opts.url.indexOf('/pdf') !== -1) {
      if (opts.convert == null) {
        opts.convert = 'pdf';
      }
    } else {
      //opts.content = await @puppet opts.url
      opts.content = (await this.fetch(opts.url));
    }
  }
  if (opts.convert) {
    try {
      text = (await this.convert[opts.convert + '2txt']((ref = opts.url) != null ? ref : opts.content));
    } catch (error) {}
  }
  if (text == null) {
    text = opts.content;
  }
  if (opts.matchers == null) {
    opts.matchers = [opts.match];
  }
  if (opts.start != null) {
    parts = text.split(opts.start);
    text = parts.length > 1 ? parts[1] : parts[0];
  }
  if (opts.end != null) {
    text = text.split(opts.end)[0];
  }
  if (opts.lowercase) {
    text = text.toLowerCase();
  }
  if (opts.ascii) {
    text = text.replace(/[^a-z0-9]/g, '');
  }
  if (opts.spaces === false) {
    text = text.replace(/ /g, '');
  }
  res = {
    length: text.length,
    matched: 0,
    matches: [],
    matchers: opts.matchers,
    text: text
  };
  if (text && typeof text !== 'number') {
    ref1 = (typeof opts.matchers === 'string' ? opts.matchers.split(',') : opts.matchers);
    for (k = 0, len = ref1.length; k < len; k++) {
      match = ref1[k];
      if (typeof match === 'string') {
        mopts = '';
        if (match.indexOf('/') === 0) {
          lastslash = match.lastIndexOf('/');
          if (lastslash + 1 !== match.length) {
            mopts = match.substring(lastslash + 1);
            match = match.substring(1, lastslash);
          }
        } else {
          match = match.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&");
        }
      } else {
        mopts = '';
      }
      if (opts.lowercase) {
        mopts += 'i';
      }
      try {
        mr = new RegExp(match, mopts);
        if (m = mr.exec(text)) {
          res.matched += 1;
          res.matches.push({
            matched: match.toString(),
            result: m
          });
        }
      } catch (error) {}
    }
  }
  return res;
};

P.decode = async function(content) {
  var _decode, c, k, len, re, ref, ref1, ref2, ref3, ref4, ref5, ref6, text;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = this != null ? (ref3 = this.params) != null ? ref3.decode : void 0 : void 0) != null ? ref2 : this != null ? (ref4 = this.params) != null ? ref4.content : void 0 : void 0) != null ? ref1 : this != null ? (ref5 = this.params) != null ? ref5.text : void 0 : void 0) != null ? ref : this != null ? this.body : void 0;
  }
  _decode = function(content) {
    var translate, translator;
    // https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node
    translator = /&(nbsp|amp|quot|lt|gt);/g;
    translate = {
      "nbsp": " ",
      "amp": "&",
      "quot": "\"",
      "lt": "<",
      "gt": ">"
    };
    return content.replace(translator, (function(match, entity) {
      return translate[entity];
    })).replace(/&#(x?[0-9A-Fa-f]+);/gi, (function(match, numStr) {
      var num;
      if (numStr.startsWith('x')) {
        num = parseInt(numStr.replace('x', ''), 16);
      } else {
        num = parseInt(numStr, 10);
      }
      return String.fromCharCode(num);
    }));
  };
  text = (await _decode(content));
  text = text.replace(/\n/g, ' ');
  ref6 = [
    {
      bad: '‘',
      good: "'"
    },
    {
      bad: '’',
      good: "'"
    },
    {
      bad: '´',
      good: "'"
    },
    {
      bad: '“',
      good: '"'
    },
    {
      bad: '”',
      good: '"'
    },
    {
      bad: '–',
      good: '-'
    },
    {
      bad: '-',
      good: '-'
    }
  ];
  for (k = 0, len = ref6.length; k < len; k++) {
    c = ref6[k];
    re = new RegExp(c.bad, 'g');
    text = text.replace(re, c.good);
  }
  try {
    if (text.indexOf('%2') !== -1) {
      text = decodeURIComponent(text);
    }
  } catch (error) {}
  try {
    if (text.indexOf('%2') !== -1) { // some of the data we handle was double encoded, so like %2520, so need two decodes
      text = decodeURIComponent(text);
    }
  } catch (error) {}
  return text;
};


S.built = "Fri Oct 13 2023 02:57:15 GMT+0100";
P.convert.doc2txt = {_bg: true}// added by constructor

P.convert.docx2txt = {_bg: true}// added by constructor

P.convert.pdf2txt = {_bg: true}// added by constructor
