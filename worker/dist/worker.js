  // global S and P are accessible anywhere, and all files are merged into one on build.
  // NOTE it IS possible for scripts to persist between cloudflare worker requests, but also not guaranteed or intentional
  // so can't rely on them being clean every time, nor rely on them for storing state. Hence every new fetch event builds its own @S and P onto the global
var P, S, SS, _schedule, k,
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
  S.name = 'Paradigm'; // this will also be used as the default name for the KV store
}

if (S.version == null) {
  S.version = '5.5.0'; // the construct script will use this to overwrite any version in the worker and server package.json files
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
    'json' // allow formatted responses in this list
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

  // _wrap - can be set to false so that a function that would otherwise be wrapped won't be

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
  // if _history, and new data was sent, store the POST content rather than just whether or not there was any, so it can be recreated

  // _diff can be true or a list of arguments for the function. It will check to see if a process gives the same result 
  // (compared against a previously stored one). If it doesn't it should log something that then gets 
  // picked up by the alert mechanism

  // _hide can be set to hide a function that should otherwise show up on the routes list, 
  // or _hides can be used to hide a function and anything under it
  // e.g. one that doesn't start with _ but should be hidden for some reason anyway. NOTE this 
  // doesn't stop it being ACCESSIBLE on the API, only hidden, whereas starting it with _ makes it inaccessible

  // TODO add a way for a function to result in a file url on local disk or s3, or perhaps even a URL somewhere else, 
  // and to serve the location redirect as the result. Could be a _file option
  addEventListener('fetch', function(event) {
    if (S.pass !== false) {
      event.passThroughOnException();
    }
    return event.respondWith(P.call(event));
  });
} catch (error) {}

`try
addEventListener 'scheduled', (event) ->
  # https://developers.cloudflare.com/workers/runtime-apis/scheduled-event
  # event.type will always be 'scheduled'. event.scheduledTime ms timestamp of the scheduled time. Can be parsed with new Date(event.scheduledTime)
  event.waitUntil P.call event, true # Fails will be recorded on Cron past events UI. Otherwise will record as success`;

_schedule = {};

P = async function() {
  var _lp, authd, base, base1, base2, base3, bd, cp, cpk, ct, d, du, entry, exclusive, fd, fn, hd, hk, i, j, kp, kpn, l, len, len1, len2, len3, name, o, pf, pk, pkn, pkp, pks, pp, prs, qp, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, resp, rk, shn, si, tp;
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
      kp = qp.split('=');
      if (kp[0].length) { // avoid &&
        if (kp.length === 1 && pkp && (kp[0].startsWith(' ') || kp[0].includes('%'))) {
          this.params[pkp] += '&' + decodeURIComponent(kp[0]);
        } else {
          this.params[kp[0]] = kp.length === 1 ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'true' ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'false' ? false : qp.endsWith('=') ? true : kp[1];
          if (typeof this.params[kp[0]] === 'string' && this.params[kp[0]].replace(/[0-9]/g, '').length === 0 && !this.params[kp[0]].startsWith('0')) {
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
    if (this.headers.accept.includes('/csv') && indexOf.call(this.S.formats, 'csv') >= 0) {
      this.format = 'csv';
    }
  }
  if (this.parts.length && this.parts[this.parts.length - 1].includes('.')) { // format specified in url takes precedence over header
    pf = this.parts[this.parts.length - 1].split('.').pop();
    if (indexOf.call(this.S.formats, pf) >= 0) {
      this.format = pf;
      this.parts[this.parts.length - 1] = this.parts[this.parts.length - 1].replace('.' + pf, '');
    }
  }
  if (typeof this.S.bg === 'string' && Array.isArray(this.S.pass) && this.parts.length && (ref9 = this.parts[0], indexOf.call(this.S.pass, ref9) >= 0)) {
    throw new Error(); // send to backend to handle requests for anything that should be served from folders on disk
  }
  for (d in (ref10 = this.S.domains) != null ? ref10 : {}) {
    if (Array.isArray(this.S.domains[d])) {
      this.S.domains[d] = {
        parts: this.S.domains[d],
        exclusive: false
      };
    }
    if (this.base.includes(d)) {
      exclusive = this.S.domains[d].exclusive; // if exclusive, ONLY routes that match within the defined parts will be served
      if (!exclusive) { // for non-exclusive, only restrict if there IS something to match at or after the defined parts
        pp = [...this.S.domains[d].parts];
        tp = P;
        while (cp = pp.shift()) {
          try {
            tp = tp[cp];
          } catch (error) {}
        }
        if ((tp != null) && ((!this.parts.length && typeof tp === 'function') || (tp[this.parts[0]] != null))) {
          exclusive = true;
        }
      }
      if (exclusive) {
        this.domain = d;
        this.parts = [...this.S.domains[d].parts, ...this.parts];
        break;
      }
    }
  }
  shn = 'x-' + this.S.name.toLowerCase() + '-system';
  if (this.S.name && this.S.system && this.headers[shn] === this.S.system) {
    delete this.headers[shn];
    this.system = true;
  }
  this._logs = []; // place for a running request to dump multiple logs, which will combine and save at the end of the overall request
  this.nolog = false; // if any function sets nolog to true, the log will not be saved.
  if (this.params._nolog) { // the request may also disable logging with a nolog param matching a unique key in settings (e.g. to not log test calls)
    this.nolog = this.S.nolog && this.params._nolog === this.S.nolog;
    delete this.params._nolog;
  }
  this.route = this.parts.join('/');
  this.routes = [];
  this.fn = ''; // the function name that was mapped to by the URL routes in the request will be stored here
  if (this.route === '') { //don't bother doing anything, just serve a direct P._response with the API details
    return P._response.call(this, (ref11 = this.request.method) === 'HEAD' || ref11 === 'OPTIONS' ? '' : {
      name: this.S.name,
      version: this.S.version,
      base: (this.S.dev ? this.base : void 0),
      built: (this.S.dev ? this.S.built : void 0)
    });
  }
  // TODO add a way to identify and iterate multiple functions either parallel or serial, adding to results
  // e.g. split url at // for multi functions. Params parallel gives on obj of named results
  // with merge for one result overwriting as they're received, or if only merge then merge in order
  // auth would need to be present for every stage

  // loop through everything defined on P, wrap and configure all functions, and set them onto @ so they can be called in relation to this fetch event
  // also pick up any URL params provided along the way - anything that doesn't map to a function or an object is considered some sort of param
  // params will be added to @params, keyed to whatever the most recent URL part that DID map to a function was
  // so for example /svc/oaworks/find maps to svc.oaworks.find, and /svc/oaworks/find/10.1234/567890 ALSO maps to it, 
  // and puts the remainder of the route (which is a DOI) into @params.find, so the find function can read it from there
  fn = void 0; // the actual function to run, once it's found (not just the name of it, which is put in @fn)
  prs = [...this.parts];
  pk = void 0;
  pks = [];
  _lp = (p, a, n, hides, auths, wraps, caches) => {
    var base10, base11, base12, base13, base14, base15, base4, base5, base6, base7, base8, base9, fs, ik, len3, nd, o, ref12, ref13, results, sk, uk;
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
      if ((ref12 = typeof p[k]) !== 'function' && ref12 !== 'object') {
        results.push(a[k] = p[k]);
      } else if (p[k] != null) {
        nd = n + (n ? '.' : '') + k;
        if (typeof p[k] === 'object' && !p[k]._index && !p[k]._indexed && !p[k]._sheet && !p[k]._kv && !p[k]._bg) { // index, kv, or bg could be objects that need wrapped
          a[k] = JSON.parse(JSON.stringify(p[k]));
        } else {
          if ((base4 = p[k])._hide == null) {
            base4._hide = (base5 = p[k])._hides != null ? base5._hides : base5._hides = hides;
          }
          if ((base6 = p[k])._auth == null) {
            base6._auth = (base7 = p[k])._auths != null ? base7._auths : base7._auths = auths;
          }
          if (Array.isArray(p[k]._auths) && p[k]._auths.length === 0) { // an empty auth array defaults to group names corresponding to the function subroutes
            p[k]._auths = nd.split('.');
          }
          if (Array.isArray(p[k]._auth) && p[k]._auth.length === 0) { // an empty auth array defaults to group names corresponding to the function subroutes
            p[k]._auth = nd.split('.');
          }
          if ((base8 = p[k])._wrap == null) {
            base8._wrap = (base9 = p[k])._wraps != null ? base9._wraps : base9._wraps = wraps;
          }
          if ((base10 = p[k])._cache == null) {
            base10._cache = (base11 = p[k])._caches != null ? base11._caches : base11._caches = caches;
          }
          if (nd.startsWith('auth')) {
            if ((base12 = p[k])._cache == null) {
              base12._cache = false;
            }
          }
          if (p[k]._sheet) {
            if ((base13 = p[k])._index == null) {
              base13._index = true;
            }
          }
          if (p[k]._index) { // add index functions to index endpoints
            ref13 = ['keys', 'terms', 'suggest', 'count', 'min', 'max', 'range', 'mapping', 'history', '_for', '_each', '_bulk', '_refresh'];
            // of P.index
            for (o = 0, len3 = ref13.length; o < len3; o++) {
              ik = ref13[o];
              if ((base14 = p[k])[ik] == null) {
                base14[ik] = {
                  _indexed: ik,
                  _auth: (ik.startsWith('_') ? 'system' : p[k]._auth)
                };
              }
            }
          }
          for (sk in fs = P.dot(this.S, n)) {
            if (sk.startsWith('_')) { // try to find anything in settings and treat it as an override
              p[k][sk] = fs[sk];
            }
          }
          if (typeof p[k] === 'function' && !p[k]._index && !p[k]._indexed && !p[k]._kv && !p[k]._bg && (!nd.includes('.') || p[k]._wrap === false || nd.split('.').pop().startsWith('_'))) {
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
        if ((base15 = a[k])._name == null) {
          base15._name = nd;
        }
        if (a[k]._schedule && !_schedule[nd] && this.S.bg === true && this.S.cron === false) { // TODO work a way for this to work with cloudflare tasks on worker too, if useful 
          console.log('Adding schedule', a[k]._schedule, nd);
          _schedule[nd] = {
            schedule: a[k]._schedule,
            fn: a[k]
          };
          cron.schedule(a[k]._schedule, async() => {
            var crd;
            _schedule[nd].last = (await this.datetime());
            try {
              if (fn._sheet) {
                this.refresh = true;
              }
              crd = (await _schedule[nd].fn(_schedule[nd].fn._args)); // args can optionally be provided for the scheduled call
              try {
                _schedule[nd].result = JSON.stringify(crd).substr(0, 200);
              } catch (error) {}
              _schedule[nd].success = true;
              console.log('scheduled task result', crd);
            } catch (error) {
              _schedule[nd].success = false;
            }
            if (_schedule[nd].fn._notify !== false) {
              return this.src.google.chat('Scheduled ' + nd(' executed ' + (_schedule[nd].success ? 'successfully' : 'unsuccessfully') + ' at ' + (await this.datetime(void 0, false))));
            }
          });
        }
        if (!k.startsWith('_')) { // underscored methods cannot be accessed from URLs
          if (prs.length && prs[0] === k && this.fn.startsWith(n)) {
            pk = prs.shift();
            this.fn += (this.fn === '' ? '' : '.') + pk;
            if (typeof a[k] === 'function' && !n.includes('._')) { // URL routes can't call _abc functions or ones under them
              fn = a[k];
            }
          }
          if (typeof a[k] === 'function' && !a[k]._hide && nd.replace('svc.', '').replace('src.', '').split('.').length === 1) { //and ((not nd.startsWith('svc') and not nd.startsWith('src')) or nd.split('.').length < 3)
            this.routes.push(nd.replace(/\./g, '/')); // TODO this could check the auth method, and only show things the current user can access, and also search for description / comment? NOTE this is just about visibility, they're still accessible if given right auth (if any)
          }
        }
        if (!Array.isArray(p[k]) && (!k.startsWith('_') || typeof a[k] === 'function')) {
          results.push(_lp(p[k], a[k], nd, hides != null ? hides : p[k]._hides, auths != null ? auths : p[k]._auths, wraps != null ? wraps : p[k]._wraps, caches != null ? caches : p[k]._caches));
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
  if (((ref12 = typeof fn) === 'object' || ref12 === 'function') && fn._bg && typeof this.S.bg === 'string' && this.S.bg.startsWith('http')) {
    throw new Error();
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
    // TODO check the blacklist
    if (authd || this.system) {
      if ((ref13 = this.request.method) === 'HEAD' || ref13 === 'OPTIONS') {
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
  resp = typeof res === 'object' && !Array.isArray(res) && typeof ((ref14 = res.headers) != null ? ref14.append : void 0) === 'function' ? res : (await this._response(res, fn));
  if (this.parts.length && ((ref15 = this.parts[0]) !== 'log' && ref15 !== 'status') && (!this.system || ((ref16 = this.parts[0]) !== 'kv' && ref16 !== 'index')) && ((ref17 = this.request.method) !== 'HEAD' && ref17 !== 'OPTIONS') && (res != null) && res !== '') {
    if (this.completed && fn._cache !== false && resp.status === 200 && (typeof res !== 'object' || Array.isArray(res) || ((ref18 = res.hits) != null ? ref18.total : void 0) !== 0) && (typeof res !== 'number' || !this.refresh)) {
      si = fn._cache; // fn._cache can be a number of seconds for cache to live, so pass it to cache to use if suitable
      if ((si == null) && typeof res === 'object' && !Array.isArray(res) && (((ref19 = res.hits) != null ? ref19.hits : void 0) != null)) { // if this is a search result, cache only 1 minute max if nothing else was set for it
        si = 60;
      }
      this.cache(void 0, resp, si);
    } else if (this.refresh) {
      this.cache(void 0, '');
    }
    if (((ref20 = typeof fn) !== 'object' && ref20 !== 'function') || fn._log !== false) {
      this.log();
    }
  }
  if (!this.completed && !this.cached && !this.unauthorised && this.S.pass !== false && typeof this.S.bg === 'string' && ((ref21 = this.request.method) !== 'HEAD' && ref21 !== 'OPTIONS')) {
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
    if (this.format && ((ref1 = this.format) === 'html' || ref1 === 'csv')) {
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
          ret += '<link href="//fonts.googleapis.com/css?family=Lustria|Noto+Sans|Roboto+Slab|Nixie+One" rel="stylesheet" type="text/css">\n';
          ret += '<link rel="stylesheet" href="/client/pradm.min.css?v=' + this.S.version + '">\n';
          ret += '<script type="text/javascript" src="/client/pradm.min.js?v=' + this.S.version + '"></script>\n';
          ret += '<script type="text/javascript" src="/client/pradmLogin.min.js?v=' + this.S.version + '"></script>\n';
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
    return new Response(res, {
      status: status,
      headers: this.S.headers
    });
  } catch (error) {
    return {
      status: status,
      headers: this.S.headers,
      body: res
    };
  }
};

// API calls this to wrap functions on P, apart from top level functions and ones 
// that start with _ or that indicate no wrapping with _wrap: false
// wrapper settings declared on each P function specify which wrap actions to apply
// _auth and _cache settings on a P function are handled by API BEFORE _wrapper is 
// used, so _auth and _cache are not handled within the wrapper
// the wrapepr logs the function call (whether it was the main API call or subsequent)
P._wrapper = function(f, n) { // the function to wrap and the string name of the function
  return async function() {
    var _as, args, base, bup, c, exists, i, j, len, len1, lg, limited, qrs, qry, rec, ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, rt, sht, started;
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
        if (typeof arguments[0] === 'string' && arguments[0].length && !arguments[0].includes('\n') && arguments[0].length === arguments[0].replace(/[\s\:\*~\?=%"]/g, '').length) {
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
            rec._id = (ref3 = (ref4 = lg.key) != null ? ref4 : rec[f._key]) != null ? ref3 : this.uid();
          }
          if (lg.key == null) {
            lg.key = rec._id;
          }
        } else if (rec.length) {
          for (i = 0, len = rec.length; i < len; i++) {
            c = rec[i];
            if (c._id == null) {
              c._id = (ref5 = c[f._key]) != null ? ref5 : this.uid();
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
          res = (await this.index(rt + (lg.key ? '/' + lg.key : ''), rec != null ? rec : qry));
          if ((res == null) && (!lg.key || (rec == null))) { // this happens if the index does not exist yet, so create it (otherwise res would be a search result object)
            await this.index(rt, typeof f._index !== 'object' ? {} : {
              settings: f._index.settings,
              mappings: (ref6 = f._index.mappings) != null ? ref6 : f._index.mapping,
              aliases: f._index.aliases
            });
            if (rec !== '') {
              res = (await this.index(rt + (lg.key ? '/' + lg.key : ''), rec != null ? rec : (!lg.key ? qry : void 0)));
            }
          }
          if ((res == null) && (rec == null) && lg.key && typeof arguments[0] === 'string' && (qry = (await this.index.translate(arguments[0], arguments[1])))) {
            qrs = (await this.index(rt, qry));
            if ((qrs != null ? (ref7 = qrs.hits) != null ? ref7.total : void 0 : void 0) === 1) {
              ref8 = (await this.keys(qrs.hits.hits[0]._source));
              for (j = 0, len1 = ref8.length; j < len1; j++) {
                k = ref8[j];
                if ((typeof qrs.hits.hits[0]._source[k] === 'string' && arguments[0] === qrs.hits.hits[0]._source[k]) || (Array.isArray(qrs.hits.hits[0]._source[k]) && (ref9 = arguments[0], indexOf.call(qrs.hits.hits[0]._source[k], ref9) >= 0))) {
                  res = qrs.hits.hits[0]._source;
                  if (res._id == null) {
                    res._id = qrs.hits.hits[0]._id;
                  }
                  break;
                }
              }
            }
          }
          if ((qry != null ? qry.size : void 0) === 1 && typeof res === 'object' && (((ref10 = res.hits) != null ? ref10.hits : void 0) != null)) {
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
    // if _history is required, record more about the incoming record change, if that's what happened
    // _history
    if (f._history && typeof rec === 'object' && !Array.isArray(rec) && rec._id) {
      lg.history = rec._id;
      lg.rec = JSON.stringify(rec); // record the incoming rec to record a history of changes to the record
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
        if (typeof f === 'function') { // process the sheet with the function if necessary, then create or empty the index
          sht = (await f.apply(this, [sht]));
        }
        await this.index(rt, '');
        await this.index(rt, typeof f._index !== 'object' ? {} : {
          settings: f._index.settings,
          mappings: (ref11 = f._index.mappings) != null ? ref11 : f._index.mapping,
          aliases: f._index.aliases
        });
        if (arguments.length || JSON.stringify(this.params) !== '{}') {
          await this.index(rt, sht);
        } else {
          this.waitUntil(this.index(rt, sht));
          res = sht.length; // if there are args, don't set the res, so the function can run afterwards if present
        }
      } else {
        res = 0;
      }
      if (this.fn === n && f._notify !== false) {
        this.waitUntil(this.src.google.chat(this.fn + ' refresh done at ' + ((await this.datetime(void 0, false))) + '\n' + JSON.stringify(res)));
      }
    }
    
    // if still nothing happened, and the function defined on P really IS a function
    // (it could also be an index or kv config object with no default function)
    // call the function, either _async if the function indicates it, or directly
    // and record limit settings if present to restrict more runnings of the same function
    // _async, _limit
    if ((res == null) && (!f._index || rec !== '') && typeof f === 'function') {
      _as = async(rt, f, ar, notify) => {
        var ends, id, l, len2, r, ref12, ref13, txt;
        if (f._limit) {
          ends = f._limit === true ? 86400 : f._limit;
          await this.kv('limit/' + n, started + ends, ends); // max limit for one day
        }
        r = (await f.apply(this, ar));
        if (typeof r === 'object' && (f._kv || f._index) && (r.took == null) && (r.hits == null)) {
          if (f._key && Array.isArray(r) && r.length && (r[0]._id == null) && (r[0][f._key] != null)) {
            for (l = 0, len2 = r.length; l < len2; l++) {
              c = r[l];
              if (c._id == null) {
                c._id = c[f._key];
              }
            }
          }
          id = Array.isArray(r) ? '' : '/' + ((ref12 = (ref13 = r[f._key]) != null ? ref13 : r._id) != null ? ref12 : this.uid()).replace(/\//g, '_').toLowerCase();
          if (f._kv && !Array.isArray(r)) {
            this.kv(rt + id, res, f._kv);
          }
          if (f._index) {
            this.waitUntil(this.index(rt + id, r));
          }
        }
        if (f._limit === true) {
          await this.kv('limit/' + n, ''); // where limit is true only delay until function completes, then delete limit record
        }
        if (f._async) {
          this.kv('async/' + this.rid, ((id != null) && !Array.isArray(r) ? rt + id : Array.isArray(r) ? r.length : r), 172800); // lasts 48 hours
          if (this.fn === n && f._notify !== false) {
            txt = this.fn + ' done at ' + ((await this.datetime(void 0, false))) + '\n\n' + JSON.stringify(r) + '\n\n' + this.base + '/' + rt + '?_async=' + this.rid;
            if (notify) {
              this.mail({
                to: notify,
                text: txt
              });
            }
            this.waitUntil(this.src.google.chat(txt));
          }
        }
        return r;
      };
      if (f._async) {
        lg.async = true;
        res = {
          _async: this.rid
        };
        this.waitUntil(_as(rt, f, arguments, this.params.notify));
      } else {
        res = (await _as(rt, f, arguments));
      }
    }
    // if _diff checking is required, save the args and res and the "log" will alert 
    // if there is a difference in the result for the same args
    // _diff
    if (f._diff && (res != null) && !lg.cached && !lg.async) {
      lg.args = JSON.stringify(arguments.length ? arguments : this.fn === n ? this.params : '');
      lg.res = JSON.stringify(res); // what if this is huge? just checksum it?
      try {
        lg.checksum = this.shorthash(lg.res);
      } catch (error) {}
    }
    // _log
    if (f._log !== false) {
      lg.took = Date.now() - started;
      this.log(lg);
    }
    return res;
  };
};

P.command = function() {
  this.format = 'html';
  return '<script type="text/javascript" src="/client/pradmCommand.min.js?v=' + this.S.version + '"></script><body></body><script>P.command();</script>';
};

P.src = {};

P.svc = {};

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
          cookie = JSON.parse(decodeURIComponent(this.cookie).split(((ref2 = (ref3 = S.auth) != null ? (ref4 = ref3.cookie) != null ? ref4.name : void 0 : void 0) != null ? ref2 : 'pradm') + "=")[1].split(';')[0]);
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
      user.resume = this.uid(); // could add extra info to resume object like machine logged in on etc to enable device management
      this.kv('auth/resume/' + user._id + '/' + user.resume, {
        createdAt: Date.now(),
        device: this.device()
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
    ret = '<body class="black">'; // or times to decide when just a normal body? '<body>'
    ret += '<div class="flex" style="margin-top: 10%;"><div class="c6 off3"><h1 id="title" class="centre statement" style="font-size:40px;">' + (this.base ? this.base.replace('bg.', '(bg) ') : this.S.name) + '</h1></div></div>';
    ret += '<div class="flex" style="margin-top: 5%;"><div class="c6 off3">';
    if (this.user == null) {
      ret += '<input autofocus id="PEmail" class="PEmail big shadow" type="text" name="email" placeholder="email">';
      ret += '<input id="PToken" class="PToken big shadow" style="display:none;" type="text" name="token" placeholder="token (check your email)">';
      ret += '<p class="PWelcome" style="display:none;">Welcome back</p>';
      ret += '<p class="PLogout" style="display:none;"><a id="PLogout" class="button action" href="#">logout</a></p>';
    } else {
      if (false) { //key is false # unauthorised
        ret += '<p>You do not have permission to access this resource</p>';
        ret += '<p class="PRequestPermission"><a id="PRequestPermission" class="button action" href="#">Request permission</p>';
        ret += '<p class="PRequestedPermission" style="display:none;">Thanks, you will receive an email once permission has been granted</p>';
      }
      ret += '<p>' + user.email + '</p><p><a id="PLogout" class="button action" href="#">logout</a></p>';
    }
    ret += '<div class="PLoading" style="display:none;"><div class="loading big"></div></div>';
    ret += '</div></div></body>';
    ret += '<script>';
    if (this.fn === 'auth') {
      ret += 'P.afterLogout = function() { location.reload(); }; ';
    }
    if (this.fn !== 'auth' || (this.user != null)) {
      ret += 'P.loginNext = true;';
    }
    ret += '</script>';
    return ret;
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
      from = (ref = (ref1 = S.auth) != null ? ref1.from : void 0) != null ? ref : 'login@example.com';
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


// add a 2FA mechanism to auth (authenticator, sms...)
// https://stackoverflow.com/questions/8529265/google-authenticator-implementation-in-python/8549884#8549884
// https://github.com/google/google-authenticator
// http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/
//P.authenticator = () ->
// TODO if an authenticator app token is provided, check it within the 30s window
// delay responses to 1 per second to stop brute force attacks
// also need to provide the token/qr to initialise the authenticator app with the service
//  return false

// device fingerprinting was available in the old code but no explicit requirement for it so not added here yet
// old code also had xsrf tokens for FORM POSTs, add that back in if relevant
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
  _hides: true,
  _auth: 'system'
};

P.users._get = async function(uid, apikey) {
  var ref, us, user;
  if (apikey) {
    try {
      us = (await this.index('users', 'apikey:"' + apikey + '"'));
      if ((us != null ? (ref = us.hits) != null ? ref.total : void 0 : void 0) === 1) {
        user = us.hits.hits[0]._source;
      }
    } catch (error) {}
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

var indexOf = [].indexOf;

if (P.convert == null) {
  P.convert = {};
}

P.convert.json2csv = async function(recs, params) {
  var h, headers, i, idlink, j, k, len, len1, newline, nk, quote, rc, rec, records, ref, ref1, ref2, ref3, ref4, ref5, ref6, rs, separator;
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
        idlink = true;
        if (!params.keys || indexOf.call(params.keys, '_id') >= 0) {
          rc._id = '<a onclick="this.setAttribute(\'href\', window.location.href.split(\'.html\')[0].split(\'/\').pop() + \'/\' + this.getAttribute(\'href\') )" href="' + rec._id + '.html">' + rec._id + '</a>';
          idlink = false;
        }
// could add controls to alter the order here, or customise key names
        for (nk in rs) {
          if (rc[nk] == null) {
            rc[nk] = rs[nk];
          }
          if (idlink && nk === params.keys[0]) {
            try {
              rc[nk] = '<a onclick="this.setAttribute(\'href\', window.location.href.split(\'.html\')[0].split(\'/\').pop() + \'/\' + this.getAttribute(\'href\') )" href="' + rec._id + '.html">' + rs[nk] + '</a>';
            } catch (error) {}
            idlink = false;
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
    if (params.search) {
      return '<script type="text/javascript" src="/client/pradmSearch.min.js"></script><script>P.search()</script>';
    } else {
      if (parts != null) {
        params.subset = parts.join('.');
      }
      return this.convert.csv2html((await this.convert.json2csv(recs, params)));
    }
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
    if (params.edit) {
      res = '<script type="text/javascript" src="/client/pradm.min.js"></script><script type="text/javascript" src="/client/pradmEdit.min.js"></script>' + res;
      res += '<script type="text/javascript">P.edit()</script>';
    }
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

`P.convert.table2csv = (content) ->
  d = P.convert.table2json content, opts
  return P.convert.json2csv d

P.convert.table2json = () ->
  return @convert.json2csv await @convert.table2csv

P.convert.html2txt = (content) -> # or xml2txt
  text = html2txt.fromString(content, {wordwrap: 130})
  return text
P.convert.xml2txt = (content) ->
  return @convert.html2txt content

P.convert.xml2json = (content) ->
  # TODO needs to handle attributes etc
  return ''`;

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

P.convert.buf2bin = function(buf) {
  var c, ret;
  if (Buffer.isBuffer(buf)) {
    buf = buf.toString('hex');
  }
  buf = buf.replace(/^0x/, '');
  ret = '';
  c = 0;
  while (c < buf.length) {
    ret += P.convert.hex2bin(buf[c]);
    c++;
  }
  return ret;
};

P.convert._mimes = {
  '.aac': 'audio/aac', // AAC audio	
  '.abw': 'application/x-abiword', // AbiWord document
  '.arc': 'application/x-freearc', // Archive document (multiple files embedded)
  '.avi': 'video/x-msvideo', // AVI: Audio Video Interleave
  '.azw': 'application/vnd.amazon.ebook', // Amazon Kindle eBook format
  '.bin': 'application/octet-stream', // Any kind of binary data
  '.bmp': 'image/bmp', // Windows OS/2 Bitmap Graphics
  '.bz': 'application/x-bzip', // BZip archive
  '.bz2': 'application/x-bzip2', // BZip2 archive
  '.csh': 'application/x-csh', // C-Shell script
  '.css': 'text/css', // Cascading Style Sheets (CSS)
  '.csv': 'text/csv', // Comma-separated values (CSV)
  '.doc': 'application/msword', // Microsoft Word
  '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // Microsoft Word (OpenXML)
  '.eot': 'application/vnd.ms-fontobject', // MS Embedded OpenType fonts
  '.epub': 'application/epub+zip', // Electronic publication (EPUB)
  '.gz': 'application/gzip', // GZip Compressed Archive
  '.gif': 'image/gif', // Graphics Interchange Format (GIF)
  '.htm': 'text/html', // HyperText Markup Language (HTML)
  '.ico': 'image/vnd.microsoft.icon', // Icon format
  '.ics': 'text/calendar', // iCalendar format
  '.jar': 'application/java-archive', // Java Archive (JAR)
  '.jpg': 'image/jpeg', // JPEG images
  '.js': 'text/javascript', // JavaScript
  '.json': 'application/json', // JSON format
  '.jsonld': 'application/ld+json', // JSON-LD format
  '.mid': 'audio/midi', // Musical Instrument Digital Interface (MIDI) audio/x-midi
  '.mjs': 'text/javascript', // JavaScript module
  '.mp3': 'audio/mpeg', // MP3 audio
  '.mpeg': 'video/mpeg', // MPEG Video
  '.mpkg': 'application/vnd.apple.installer+xml', // Apple Installer Package
  '.odp': 'application/vnd.oasis.opendocument.presentation', // OpenDocument presentation document
  '.ods': 'application/vnd.oasis.opendocument.spreadsheet', // OpenDocument spreadsheet document
  '.odt': 'application/vnd.oasis.opendocument.text', // OpenDocument text document
  '.oga': 'audio/ogg', // OGG audio
  '.ogv': 'video/ogg', // OGG video
  '.ogx': 'application/ogg', // OGG
  '.opus': 'audio/opus', // Opus audio
  '.otf': 'font/otf', // OpenType font
  '.png': 'image/png', // Portable Network Graphics
  '.pdf': 'application/pdf', // Adobe Portable Document Format (PDF)
  '.php': 'application/php', // Hypertext Preprocessor (Personal Home Page)
  '.ppt': 'application/vnd.ms-powerpoint', // Microsoft PowerPoint
  '.pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation', // Microsoft PowerPoint (OpenXML)
  '.py': 'text/plain',
  '.rar': 'application/vnd.rar', // RAR archive
  '.rb': 'text/plain',
  '.rtf': 'application/rtf', // Rich Text Format (RTF)
  '.sh': 'application/x-sh', // Bourne shell script
  '.svg': 'image/svg+xml', // Scalable Vector Graphics (SVG)
  '.swf': 'application/x-shockwave-flash', // Small web format (SWF) or Adobe Flash document
  '.tar': 'application/x-tar', // Tape Archive (TAR)
  '.tif': 'image/tiff', // Tagged Image File Format (TIFF)
  '.ts': 'video/mp2t', // MPEG transport stream
  '.ttf': 'font/ttf', // TrueType Font
  '.txt': 'text/plain', // Text, (generally ASCII or ISO 8859-n)
  '.vsd': 'application/vnd.visio', // Microsoft Visio
  '.wav': 'audio/wav', // Waveform Audio Format
  '.weba': 'audio/webm', // WEBM audio
  '.webm': 'video/webm', // WEBM video
  '.webp': 'image/webp', // WEBP image
  '.woff': 'font/woff', // Web Open Font Format (WOFF)
  '.woff2': 'font/woff2', // Web Open Font Format (WOFF)
  '.xhtml': 'application/xhtml+xml', // XHTML
  '.xls': 'application/vnd.ms-excel', // Microsoft Excel
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', // Microsoft Excel (OpenXML)
  '.xml': 'application/xml', // XML
  '.xul': 'application/vnd.mozilla.xul+xml', // XUL
  '.zip': 'application/zip', // ZIP archive
  '.3gp': 'video/3gpp', // 3GPP audio/video container audio/3gpp if it doesn't contain video
  '.3g2': 'video/3gpp2', // 3GPP2 audio/video container audio/3gpp2 if it doesn't contain video
  '.7z': 'application/x-7z-compressed' // 7-zip archive
};

P.convert.mime = function(fn) {
  var mime, ref, ref1, ref2, tp;
  if (fn == null) {
    fn = (ref = (ref1 = (ref2 = this.params.fn) != null ? ref2 : this.params.mime) != null ? ref1 : this.params.filename) != null ? ref : this.params.file;
  }
  // plus some programming languages with text/plain, useful for filtering on filenames
  tp = (fn.indexOf('.') === -1 ? fn : fn.substr(fn.lastIndexOf('.') + 1)).toLowerCase();
  if (tp === 'html') {
    tp = 'htm';
  }
  if (tp === 'jpeg') {
    tp = 'jpg';
  }
  if (tp === 'tiff') {
    tp = 'tif';
  }
  if (tp === 'midi') {
    tp = 'mid';
  }
  mime = P.convert._mimes['.' + tp];
  if (typeof mime === 'string') {
    return mime;
  } else {
    return false;
  }
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

//import xml2js from 'xml2js'
`P.convert.xml2json = (content) ->
_clean = (val, k) ->
  if Array.isArray val
    vv = []
    for v in val
      if typeof v isnt 'string' or v.replace(/ /g,'').replace(/\n/g,'') isnt ''
        cv = await _clean v, k
        vv.push cv
    val = if vv.length then if vv.length is 1 and typeof vv[0] is 'string' then vv[0] else vv else ''
  else if typeof val is 'object'
    keys = await @keys val
    if keys.length is 1 and (keys[0].toLowerCase() is k.toLowerCase() or (k.toLowerCase().split('').pop() is 's' and keys[0].toLowerCase() is k.toLowerCase().slice(0, -1)))
      val = await _clean val[keys[0]], k, clean
    else if val.$?.key? and val._? and keys.length is 2
      nv = {}
      nv[val.$.key] = val._
      val = nv
    else if val.$? and _.keys(val.$).length is 1
      sk = _.keys(val.$)[0]
      val[sk] = val.$[sk]
      delete val.$
    else if val.$? and typeof val.$ is 'object'
      unique = true
      for dk of val.$
        unique = dk not in keys
      if unique
        for dkk of val.$
          val[dkk] = val.$[dkk]
        delete val.$
    ak = await @keys val
    if ak.length is 1 and typeof val[ak[0]] is 'string' and val[ak[0]].toLowerCase() is k.toLowerCase()
      val = ''
    else
      for o of val
        val[o] = await _clean val[o], o
        if o is '_' and typeof val[o] is 'string' and not val.value?
          if ak.length is 1 and '_' not in ak and val[ak[0]].toLowerCase() is k.toLowerCase()
            return val._
          else
            val.value = val._
            delete val._
  return val

content = await @fetch(content) if content.startsWith 'http'
parser = new xml2js.Parser()
return new Promse (resolve, reject) =>
  parser.parseString content, (err, result) =>
    recs = []
    for row in (if Array.isArray(result) then result else if result then [result] else [])
      for k of row
        row[k] = await _clean row[k], k
      recs.push row
    resolve if recs.length is 1 then recs[0] else recs`;

// write examples of how to do various things here
if (S.example == null) {
  S.example = {};
}

S.example.example = 3;

P.example = function() {
  var res;
  res = {
    name: S.name,
    version: S.version,
    built: S.built
  };
  try {
    res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0];
  } catch (error) {}
  try {
    res.fn = this.fn;
  } catch (error) {}
  if (S.dev) {
    try {
      if (res.headers == null) {
        res.headers = this.headers;
      }
    } catch (error) {}
    try {
      if (res.parts == null) {
        res.parts = this.parts;
      }
    } catch (error) {}
    try {
      if (res.params == null) {
        res.params = this.params;
      }
    } catch (error) {}
    try {
      if (res.opts == null) {
        res.opts = this.opts;
      }
    } catch (error) {}
  }
  return res;
};

P.example._hides = true;

P.example.idx = {
  _index: true
};

P.example.restricted = function() {
  return {
    hello: this.user._id
  };
};

P.example.restricted._auth = true;

P.example.deep = async function() {
  var res;
  res = {
    example: 'deep',
    deeper: (await this.example.deep.deeper())
  };
  try {
    res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0];
  } catch (error) {}
  try {
    res.fn = this.fn;
  } catch (error) {}
  return res;
};

P.example.deep.deeper = async function() {
  var res;
  res = {
    hello: 'deeper'
  };
  try {
    res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0];
  } catch (error) {}
  try {
    res.fn = this.fn;
  } catch (error) {}
  try {
    res.deepest = (await this.example.deep.deeper.deepest());
  } catch (error) {}
  return res;
};

P.example.deep.deeper.deepest = function() {
  var res;
  res = {
    hello: 'deepest'
  };
  try {
    res.caller = (new Error()).stack.split("\n")[3].split('FetchEvent.')[1].split(' ')[0];
  } catch (error) {}
  try {
    res.fn = this.fn;
  } catch (error) {}
  return res;
};

P.example.inbetween = function() {
  // call a url like example/thing/inbetween and this should give you thing
  console.log(typeof this.params.example);
  return this.params;
};

P.example.cron = function() {
  var dn;
  dn = Date.now();
  console.log('cron example fn', dn);
  return dn;
};

P.example.cron._schedule = '* * * * *'; // every minute default

P.example.cron._notify = false;

// https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch

// NOTE TODO for getting certain file content, adding encoding: null to headers (or correct encoding required) can be helpful
P.fetch = async function(url, params) {
  var _f, base, ct, err, i, j, k, len, len1, name, nu, pt, pts, qp, ref, ref1, ref2, ref3, res, v;
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
  if (url.split('//')[1].split('@')[0].indexOf(':') !== -1) {
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
  if (params.body != null) {
    if (params.headers == null) {
      params.headers = {};
    }
    if ((params.headers['Content-Type'] == null) && (params.headers['content-type'] == null)) {
      params.headers['Content-Type'] = typeof params.body === 'object' ? 'application/json' : 'text/plain';
    }
    if ((ref1 = typeof params.body) === 'object' || ref1 === 'boolean' || ref1 === 'number') { // or just everything?
      params.body = JSON.stringify(params.body);
    }
    if (params.method == null) {
      params.method = 'POST';
    }
  }
  if (params.form != null) {
    // note, to send form and more data, form-data would be needed
    if (params.headers == null) {
      params.headers = {};
    }
    if ((params.headers['Content-Type'] == null) && (params.headers['content-type'] == null)) {
      params.headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    if (typeof params.form === 'object') {
      try {
        params.form = (await this.form(params.form));
      } catch (error) {}
    }
    params.body = params.form;
    delete params.form;
    if (params.method == null) {
      params.method = 'POST';
    }
  }
  if (typeof url !== 'string') {

  } else {
    if (url.includes('localhost')) { // allow local https connections on backend server without check cert
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
      ref2 = pts.join('?').split('&');
      for (j = 0, len1 = ref2.length; j < len1; j++) {
        qp = ref2[j];
        if (!nu.endsWith('?')) {
          nu += '&';
        }
        [k, v] = qp.split('=');
        if (v == null) {
          v = '';
        }
        if (k) {
          nu += encodeURIComponent(k) + (v ? '=' + (v.indexOf('%') !== -1 ? v : encodeURIComponent(v)) : '');
        }
      }
      url = nu;
    }
    if (params.params && JSON.stringify(params.params) !== '{}') {
      if (url.indexOf('?') === -1) {
        url += '?';
      }
      ref3 = params.params;
      for (k in ref3) {
        v = ref3[k];
        if (!url.endsWith('&') && !url.endsWith('?')) {
          url += '&';
        }
        if (k) {
          url += encodeURIComponent(k) + '=' + encodeURIComponent(typeof v === 'object' ? JSON.stringify(v) : v);
        }
      }
      delete params.params;
    }
    if (S.system && ((typeof S.bg === 'string' && url.startsWith(S.bg)) || (typeof S.kv === 'string' && S.kv.startsWith('http') && url.startsWith(S.kv)))) {
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
      var r, response;
      if (params.stream) {
        delete params.stream;
        // return full response with status, ok, redirected, bodyUsed, size, timeout url, statusText, clone, body, arrayBuffer, blob, json, text, buffer, textConverted 
        return fetch(url, params); // (and response body can be used as stream if desired, or can await text() or json() etc
      } else {
        response = (await fetch(url, params));
        if ((!url.includes('localhost') || response.status !== 200) && S.dev && S.bg === true) { // status code can be found here
          console.log(response.status + ' ' + url);
        }
        // content type could be read from: response.headers.get('content-type')
        r = (await response.text()); // await response.json() can get json direct, but it will error if the wrong sort of data is provided, so just try it here
        try {
          if (typeof r === 'string' && (r.indexOf('{') === 0 || r.indexOf('[') === 0)) {
            r = JSON.parse(r);
          }
        } catch (error) {}
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
      if (params.timeout && ((this != null ? this._timeout : void 0) != null)) { // should timeout be here at all or could/should @retry be used to handle that?
        pt = params.timeout === true ? 30000 : params.timeout;
        delete params.timeout;
        res = (await this._timeout(pt, _f()));
      } else {
        res = (await _f());
      }
      try {
        res = res.trim();
        if (res.indexOf('[') === 0 || res.indexOf('{') === 0) {
          res = JSON.parse(res);
        }
      } catch (error) {}
      return res;
    } catch (error) {
      err = error;
      if (S.dev && S.bg === true) {
        console.log(err, JSON.stringify(err), 'ERROR TRYING TO CALL FETCH');
      }
      try {
        this.log(err);
      } catch (error) {}
    }
  }
};

`limiting = (fetcher, retries=1) ->
  # notice if someone else is limiting us, and how long to wait for
  while retries
    retries--
    response = await fetcher()
    switch (response.status) ->
      default:
        return response
      case 403:
      case 429:
        # header names differ by API we're hitting, these examples are for github. 
        # It's the timestamp of when the rate limit window would reset, generalise this
        # e.g. look for any header containing ratelimit? or rate? then see if it's a big
        # number which would be a timestamp (and check if need *1000 for unix to ms version) 
        # or a small number which is probably ms to wait
        resets = parseInt response.headers.get "x-ratelimit-reset"
        ms = if isNaN(resets) then 0 else new Date(resets * 1000).getTime() - Date.now()
        if ms is 0
          # this one is like a count of ms to wait?
          remaining = parseInt response.headers.get "x-ratelimit-remaining"
          ms = remaining if not isNaN remaining

        if ms <= 0
          return response
        else
          await new Promise resolve => setTimeout resolve, ms`;

P.fetch._auth = 'system';

P.fetch._hide = true;

var _bg_last_log_batch, _bg_log_batch, _bg_log_batch_timeout;

if (S.log == null) {
  S.log = {};
}

_bg_log_batch = [];

_bg_log_batch_timeout = false;

_bg_last_log_batch = false;

P.log = async function(msg, store) {
  var _save_batch, i, j, l, len, len1, p, prev, prevs, ref, ref1, ref2;
  _save_batch = async() => {
    var _batch, _last, indexed;
    if (_bg_log_batch_timeout !== false) {
      // TODO may be worth generalising this into index functionality and having an option to bulk any index
      // then index calls that are writing data should route to the bg /index functions instead of 
      // direct to the index, so that they can be temporarily stored and handled in bulk (only suitable for when they can be lost too)
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
  if (this.S.log !== false && this.nolog !== true) {
    if (store !== true) { // an empty call to log stores everything in the _logs list
      store = msg == null;
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
    } else if (typeof msg === 'object' && msg.res && msg.args) { // this indicates the fn had _diff true
      // find a previous log for the same thing and if it's different add a diff: true to the log of this one. Or diff: false if same, to track that it was diffed
      try {
        prevs = (await this.index('logs', 'args:"' + msg.args + '"')); // TODO what if it was a diff on a main log event though? do all log events have child log events now? check. and check what args/params should be compared for diff
        prev = prevs.hits.hits[0]._source;
        msg.diff = msg.checksum && prev.checksum ? msg.checksum !== prev.checksum : msg.res !== prev.res;
      } catch (error) {}
    }
    // if msg.diff, send an email alert? Or have schedule pick up on those later?
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

P.log._hide = true;

P.logs = {
  _index: true,
  _hide: true,
  _auth: 'system'
};

// a user should be able to set a list of endpoints they want to receive notifications for
// could also wildcard* match
// note if there are lots of notifications, may need to group them
// user won't need auth for the endpoint because it won't give any info about the result - just that it happened?
// or if results are wanted, auth for the endpoint would be necessary
// notifications from this will go to a google chat bot webhook
// notifications will be triggered by log analysis, a scheduled job will need to check through them
`P.log.monitor = (opts) ->
  opts ?= @params
  if (opts.email or opts.chat) and opts.q
    opts.q = JSON.stringify(opts.q) if typeof opts.q isnt 'string'
    opts.frequency ?= 60
    # also can provide an opts.name as a nice name for the monitor instead if just the query
    return opts
  return
P.log.monitor = _index: true
P.log.monitor._schedule = () ->
  notify = {}
  chat = []
  counter = 0
  await @index.each 'log_monitor', '*', (rec) ->
    if not rec.notified or rec.notified + (rec.frequency * 60000) < @started
      rec.notified = @started
      @waitUntil @index 'log_monitor/' + rec._id, @copy rec
      q = if typeof rec.q is 'string' and rec.q.startsWith('{') then JSON.parse(rec.q) else rec.q
      q = await @index.translate q, { newest: true, restrict: [{query_string: {query: 'createdAt:>' + (@started - (rec.frequency * 60000))}}]}
      count = await @index.count 'logs', undefined, q
      if count
        counter += count
        rec.dq = q
        rec.count = count
        if rec.email
          notify.email ?= []
          notify.email.push rec
        if rec.chat
          chat.push rec

  for e of notify
    txt = ''
    for n in notify[e]
      txt += 'https://bg' + (if @S.dev then 'b' else '') + '.lvatn.com/log?q=' + JSON.stringify(n.dq) + '\n\n'
    @waitUntil @mail.send
      to: notify[e].email
      subject: notify[e].length + ' of your monitors have ' + rec.count + ' new alerts'
      text: txt
  
  if chat.length
    txt = chat.length + ' monitor notifications:'
    for c in chat
      txt += '\nhttps://bg' + (if @S.dev then 'b' else '') + '.lvatn.com/log?q=' + JSON.stringify(c.dq)
    @waitUntil @src.google.chat txt
  
  return counter`;

`P.add 'mail/feedback/:token',
  get: () ->
    try
      from = this.queryParams.from ? P.settings.mail?.feedback?[this.urlParams.token]?.from ? "sysadmin@cottagelabs.com"
      to = P.settings.mail?.feedback?[this.urlParams.token]?.to
      service = P.settings.mail?.feedback?[this.urlParams.token]?.service
      subject = P.settings.mail?.feedback?[this.urlParams.token]?.subject ? "Feedback"
    if to?
      P.mail.send
        service: service
        from: from
        to: to
        subject: subject
        text: this.queryParams.content
    return {}


level/loglevel
group (default to whatever is after svc or src, or just part 0)
notify/alert

P.log = (opts, fn, lvl='debug') ->

    loglevels = ['all', 'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'off']
    loglevel = P.settings.log?.level ? 'all'
    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level
      if opts.notify and P.settings.log?.notify
        try
          os = @copy opts
        catch
          os = opts
        Meteor.setTimeout (() -> P.notify os), 100

      for o of opts
        if not opts[o]?
          delete opts[o]
        else if typeof opts[o] isnt 'string' and not _.isArray opts[o]
          try
            opts[o] = JSON.stringify opts[o]
          catch
            try
              opts[o] = opts[o].toString()
            catch
              delete opts[o]

      if loglevels.indexOf(loglevel) <= loglevels.indexOf 'debug'
        console.log opts.msg if opts.msg

  if typeof notify is 'string'
    if note.indexOf '@' isnt -1
      note = to: note

  if typeof note is 'object'
    note.text ?= note.msg ? opts.msg
    note.subject ?= P.settings.name ? 'API log message'
    note.from ?= P.settings.log?.from ? 'alert@cottagelabs.com'
    note.to ?= P.settings.log?.to ? 'mark@cottagelabs.com'
    P.mail.send note




P.ping = (url,shortid) ->
  return false if not url?
  url = 'http://' + url if url.indexOf('http') isnt 0
  if (not shortid? or shortid is 'random') and spre = pings.find {url:url,redirect:true}
    return spre._id
  else
    obj = {url:url,redirect:true}
    if shortid? and shortid isnt 'random'
      while already = pings.get shortid
        shortid += Random.hexString(2)
      obj._id = shortid
    return pings.insert obj

# craft an img link and put it in an email, if the email is viewed as html it will load the URL of the img,
# which actually hits this route, and allows us to record stuff about the event

# so for example for oabutton where this was first created for, an image url like this could be created,
# with whatever params are required to be saved, in addition to the nonce.
# On receipt the pinger will grab IP and try to retrieve location data from that too:
# <img src="https://api.cottagelabs.com/ping/p.png?n=<CURRENTNONCE>service=oabutton&id=<USERID>">

P.ping.png = () ->
  if not P.settings.ping?.nonce? or this.queryParams.n is P.settings.ping.nonce
    data = this.queryParams
    delete data.n
    data.ip = this.request.headers['x-forwarded-for'] ? this.request.headers['cf-connecting-ip'] ? this.request.headers['x-real-ip']
    data.forwarded = this.request.headers['x-forwarded-for']
    try
      res = HTTP.call 'GET', 'http://ipinfo.io/' + data.ip + (if P.settings?.use?.ipinfo?.token? then '?token=' + P.settings.use.ipinfo.token else '')
      info = JSON.parse res.content
      data[k] = info[k] for k of info
      if data.loc
        try
          latlon = data.loc.split(',')
          data.lat = latlon[0]
          data.lon = latlon[1]
    pings.insert data
  img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8BQDwAEgAF/posBPQAAAABJRU5ErkJggg==', 'base64');
  if this.queryParams.red
    img = new Buffer('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=', 'base64')
  this.response.writeHead 200,
    'Content-disposition': "inline; filename=ping.png"
    'Content-type': 'image/png'
    'Content-length': img.length
    'Access-Control-Allow-Origin': '*'

    this.response.end img

P.add 'ping/:shortid',
  get: () ->
    if this.urlParams.shortid is 'random' and this.queryParams.url
      # may want to disbale this eventually as it makes it easy to flood the server, if auth is added on other routes
      return P.ping this.queryParams.url, this.urlParams.shortid
    else if exists = pings.get(this.urlParams.shortid) and exists.url?
        count = exists.count ? 0
        count += 1
        pings.update exists._id, {count:count}
        return
          statusCode: 302
          headers:
            'Content-Type': 'text/plain'
            'Location': exists.url
          body: 'Location: ' + exists.url
    else return 404
  put:
    authRequired: true
    action: () ->
      # certain user groups can overwrite a shortlink
      # TODO: overwrite a short link ID that already exists, or error out
  post: () ->
    return P.ping (this.request.body.url ? this.queryParams.url), this.urlParams.shortid
  delete:
    #authRequired: true
    action: () ->
      if exists = pings.get this.urlParams.shortid
        pings.remove exists._id
        return true
      else
        return 404`;

try {
  S.mail = JSON.parse(SECRETS_MAIL);
} catch (error) {
  S.mail = {};
}

P.mail = async function(opts) {
  var f, fo, ms, p, parts, ref, ref1, ref10, ref11, ref12, ref13, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, url;
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
  // also takes opts.attachments, but not required. Should be a list of objects
  // how do attachments work if not on mail_url, can they be sent by API?
  // https://github.com/nodemailer/mailcomposer/blob/v4.0.1/README.md#attachments
  // could use mailgun-js, but prefer to just send direct to API
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
  f = (ref13 = this != null ? this.fetch : void 0) != null ? ref13 : P.fetch;
  fo = (await this.form(opts));
  return (await f(url, {
    method: 'POST',
    form: fo,
    auth: 'api:' + ms.apikey
  }));
};

P.mail._hide = true;

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

var base, base1, base2;

if (S.mail == null) {
  S.mail = {};
}

if ((base = S.mail).from == null) {
  base.from = "system@oa.works";
}

if ((base1 = S.mail).to == null) {
  base1.to = "mark@oa.works";
}

if ((base2 = S.src).google == null) {
  base2.google = {};
}

try {
  S.src.google.secrets = JSON.parse(SECRETS_GOOGLE);
} catch (error) {}

P.status = async function() {
  var i, j, k, len, len1, ref, ref1, ref2, res, ss;
  res = {
    name: S.name,
    version: S.version,
    built: S.built
  };
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
    if ((ref2 = this.user) != null ? ref2.email : void 0) {
      res.user = this.user.email;
    }
  }
  
  // maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  // maybe some useful info from the recent logs too
  return res;
};

`
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

  return sr`;

var indexOf = [].indexOf;

P.tdm = {};

P.tdm.occurrence = function(content, sub, overlap) {
  var n, pos, ref, ref1, ref2, ref3, ref4, ref5, ref6, step;
  if (content == null) {
    content = (ref = this != null ? (ref1 = this.params) != null ? ref1.content : void 0 : void 0) != null ? ref : this != null ? (ref2 = this.params) != null ? ref2.url : void 0 : void 0;
  }
  if (content.indexOf('http') === 0) {
    content = this.fetch(content);
  }
  if (sub == null) {
    sub = (ref3 = this != null ? (ref4 = this.params) != null ? ref4.sub : void 0 : void 0) != null ? ref3 : this != null ? (ref5 = this.params) != null ? ref5.q : void 0 : void 0;
  }
  if (overlap == null) {
    overlap = this != null ? (ref6 = this.params) != null ? ref6.overlap : void 0 : void 0;
  }
  content += "";
  sub += "";
  if (sub.length <= 0) {
    return content.length + 1;
  }
  n = 0;
  pos = 0;
  step = overlap ? 1 : sub.length;
  while (true) {
    pos = content.indexOf(sub, pos);
    if (pos >= 0) {
      ++n;
      pos += step;
    } else {
      break;
    }
  }
  return n;
};

P.tdm.levenshtein = function(a, b, lowercase) {
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


// https://en.wikipedia.org/wiki/Hamming_distance#Algorithm_example
// this is faster than levenshtein but not always so useful
// this works slightly better with perceptual hashes, or anything where just need to know how many changes to make to become the same
// for example the levenshtein difference between 1234567890 and 0123456789 is 2
// whereas the hamming distance is 10
P.tdm.hamming = function(a, b, lowercase) {
  var c, diff, k, long, moves, pc, pos, ref, ref1, ref2, ref3, short, sl, ss;
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
  if (a.length < b.length) {
    short = a;
    long = b;
  } else {
    short = b;
    long = a;
  }
  pos = long.indexOf(short);
  ss = short.split('');
  sl = long.split('');
  if (sl.length > ss.length) {
    diff = sl.length - ss.length;
    if (0 < pos) {
      pc = 0;
      while (pc < pos) {
        ss.unshift('');
        pc++;
        diff--;
      }
    }
    c = 0;
    while (c < diff) {
      ss.push('');
      c++;
    }
  }
  moves = 0;
  for (k in sl) {
    if (ss[k] !== sl[k]) {
      moves++;
    }
  }
  return moves;
};

P.tdm.extract = async function(opts) {
  var l, lastslash, len, m, match, mopts, mr, parts, ref, ref1, res, text;
  // opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
  //opts ?= @params
  if (opts.url && !opts.content) {
    if (opts.url.indexOf('.pdf') !== -1 || opts.url.indexOf('/pdf') !== -1) {
      if (opts.convert == null) {
        opts.convert = 'pdf';
      }
    } else {
      opts.content = (await this.puppet(opts.url));
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
    for (l = 0, len = ref1.length; l < len; l++) {
      match = ref1[l];
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

P.tdm.emails = function(opts = {}) {
  var checked, emails, ex, l, len, len1, p, pm, pmr, ref, ref1, ref2, ref3, ref4, ref5;
  opts.matchers = ['/([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi', '/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi'];
  emails = [];
  checked = [];
  ex = P.tdm.extract(opts);
  ref = ex.matches;
  for (l = 0, len = ref.length; l < len; l++) {
    pm = ref[l];
    ref1 = pm.result;
    for (p = 0, len1 = ref1.length; p < len1; p++) {
      pmr = ref1[p];
      if (indexOf.call(checked, pmr) < 0) {
        if (typeof (((ref2 = P.mail) != null ? ref2.validate : void 0) != null) !== 'function' || P.mail.validate(pmr, (ref3 = P.settings.service) != null ? (ref4 = ref3.openaccessbutton) != null ? (ref5 = ref4.mail) != null ? ref5.pubkey : void 0 : void 0 : void 0).is_valid) {
          emails.push(pmr);
        }
      }
      checked.push(pmr);
    }
  }
  return emails;
};

P.tdm.stopwords = function(stops, more, gramstops = true) {
  var g, l, len, len1, m, p;
  
  // removed wordpos option from this
  if (stops == null) {
    stops = ['purl', 'w3', 'http', 'https', 'ref', 'html', 'www', 'ref', 'cite', 'url', 'title', 'date', 'nbsp', 'doi', 'fig', 'figure', 'supplemental', 'year', 'time', 'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec', 'keywords', 'revised', 'accepted', 'file', 'attribution', 'org', 'com', 'id', 'wp', 'main', 'website', 'blogs', 'media', 'people', 'years', 'made', 'location', 'its', 'asterisk', 'called', 'xp', 'er', 'image', 'jpeg', 'jpg', 'png', 'php', 'object', 'false', 'true', 'article', 'chapter', 'book', 'caps', 'isbn', 'scale', 'axis', 'accessed', 'email', 'e-mail', 'story', 'first1', 'first2', 'last1', 'last2', 'general', 'list', 'accessdate', 'view_news', 'd0', 'dq', 'sfnref', 'onepage', 'sfn', 'authorlink'];
  }
  gramstops = ["apos", "as", "able", "about", "above", "according", "accordingly", "across", "actually", "after", "afterwards", "again", "against", "aint", "all", "allow", "allows", "almost", "alone", "along", "already", "also", "although", "always", "am", "among", "amongst", "an", "and", "another", "any", "anybody", "anyhow", "anyone", "anything", "anyway", "anyways", "anywhere", "apart", "appear", "appreciate", "appropriate", "are", "arent", "around", "as", "aside", "ask", "asking", "associated", "at", "available", "away", "awfully", "be", "became", "because", "become", "becomes", "becoming", "been", "before", "beforehand", "behind", "being", "believe", "below", "beside", "besides", "best", "better", "between", "beyond", "both", "brief", "but", "by", "cmon", "cs", "came", "can", "cant", "cannot", "cant", "cause", "causes", "certain", "certainly", "changes", "clearly", "co", "com", "come", "comes", "concerning", "consequently", "consider", "considering", "contain", "containing", "contains", "corresponding", "could", "couldnt", "course", "currently", "definitely", "described", "despite", "did", "didnt", "different", "do", "does", "doesnt", "doing", "dont", "done", "down", "downwards", "during", "each", "edu", "eg", "eight", "either", "else", "elsewhere", "enough", "entirely", "especially", "et", "etc", "even", "ever", "every", "everybody", "everyone", "everything", "everywhere", "ex", "exactly", "example", "except", "far", "few", "fifth", "first", "five", "followed", "following", "follows", "for", "former", "formerly", "forth", "four", "from", "further", "furthermore", "get", "gets", "getting", "given", "gives", "go", "goes", "going", "gone", "got", "gotten", "greetings", "had", "hadnt", "happens", "hardly", "has", "hasnt", "have", "havent", "having", "he", "hes", "hello", "help", "hence", "her", "here", "heres", "hereafter", "hereby", "herein", "hereupon", "hers", "herself", "hi", "him", "himself", "his", "hither", "hopefully", "how", "howbeit", "however", "i", "I", "id", "ill", "im", "ive", "ie", "if", "ignored", "immediate", "in", "inasmuch", "inc", "indeed", "indicate", "indicated", "indicates", "inner", "insofar", "instead", "into", "inward", "is", "isnt", "it", "itd", "itll", "its", "itself", "just", "keep", "keeps", "kept", "know", "knows", "known", "last", "lately", "later", "latter", "latterly", "least", "less", "lest", "let", "lets", "like", "liked", "likely", "little", "look", "looking", "looks", "ltd", "mainly", "many", "may", "maybe", "me", "mean", "meanwhile", "merely", "might", "more", "moreover", "most", "mostly", "much", "must", "my", "myself", "name", "namely", "nd", "near", "nearly", "necessary", "need", "needs", "neither", "never", "nevertheless", "new", "next", "nine", "no", "nobody", "non", "none", "noone", "nor", "normally", "not", "nothing", "now", "nowhere", "obviously", "of", "off", "often", "oh", "ok", "okay", "old", "on", "once", "one", "ones", "only", "onto", "or", "other", "others", "otherwise", "ought", "our", "ours", "ourselves", "out", "outside", "over", "overall", "own", "particular", "particularly", "per", "perhaps", "placed", "please", "plus", "possible", "presumably", "probably", "provides", "que", "quite", "qv", "rather", "rd", "re", "really", "reasonably", "regarding", "regardless", "regards", "relatively", "respectively", "right", "said", "same", "saw", "say", "saying", "says", "second", "secondly", "see", "seeing", "seem", "seemed", "seeming", "seems", "seen", "self", "selves", "sensible", "sent", "serious", "seriously", "seven", "several", "shall", "she", "should", "shouldnt", "since", "six", "so", "some", "somebody", "somehow", "someone", "something", "sometime", "sometimes", "somewhat", "somewhere", "soon", "sorry", "specified", "specify", "specifying", "still", "sub", "such", "sup", "sure", "ts", "take", "taken", "tell", "tends", "th", "than", "thank", "thanks", "thanx", "that", "thats", "thats", "the", "their", "theirs", "them", "themselves", "then", "thence", "there", "theres", "thereafter", "thereby", "therefore", "therein", "theres", "thereupon", "these", "they", "theyd", "theyll", "theyre", "theyve", "think", "third", "this", "thorough", "thoroughly", "those", "though", "three", "through", "throughout", "thru", "thus", "to", "together", "too", "took", "toward", "towards", "tried", "tries", "truly", "try", "trying", "twice", "two", "un", "under", "unfortunately", "unless", "unlikely", "until", "unto", "up", "upon", "us", "use", "used", "useful", "uses", "using", "usually", "value", "various", "very", "via", "viz", "vs", "want", "wants", "was", "wasnt", "way", "we", "wed", "well", "weve", "welcome", "well", "went", "were", "werent", "what", "whats", "whatever", "when", "whence", "whenever", "where", "wheres", "whereafter", "whereas", "whereby", "wherein", "whereupon", "wherever", "whether", "which", "while", "whither", "who", "whos", "whoever", "whole", "whom", "whose", "why", "will", "willing", "wish", "with", "within", "without", "wont", "wonder", "would", "would", "wouldnt", "yes", "yet", "you", "youd", "youll", "youre", "youve", "your", "yours", "yourself", "yourselves", "zero"];
  if (gramstops) {
    for (l = 0, len = gramstops.length; l < len; l++) {
      g = gramstops[l];
      if (indexOf.call(stops, g) < 0) {
        stops.push(g);
      }
    }
  }
  if (more) {
    if (typeof more === 'string') {
      more = more.split(',');
    }
    for (p = 0, len1 = more.length; p < len1; p++) {
      m = more[p];
      if (indexOf.call(stops, m) < 0) {
        stops.push(m);
      }
    }
  }
  return stops;
};

// note that new wordpos can be used in browser and can preload word files or get them on demand
// try this from within CF and see if it works fast enough - it'll be about 7MB compressed data to 
// preload all, or on demand may introduce some lag
// https://github.com/moos/wordpos-web

var indexOf = [].indexOf;

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

P.hash = async function(content) {
  var arr, b, buf, j, len1, parts, ref, ref1, ref2, ref3;
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
    for (j = 0, len1 = arr.length; j < len1; j++) {
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

P.sleep._hide = true;

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

P.form = function(params) {
  var j, len1, p, po, ppt, ref;
  // return params object x-www-form-urlencoded
  if (params == null) {
    params = this.params;
  }
  po = '';
  for (p in params) {
    if (po !== '') {
      po += '&';
    }
    ref = (Array.isArray(params[p]) ? params[p] : [params[p]]);
    for (j = 0, len1 = ref.length; j < len1; j++) {
      ppt = ref[j];
      if (ppt != null) {
        if (!po.endsWith('&')) {
          po += '&';
        }
        po += p + '=' + encodeURIComponent((typeof ppt === 'object' ? JSON.stringify(ppt) : ppt));
      }
    }
  }
  return po;
};

P.decode = async function(content) {
  var _decode, c, j, len1, re, ref, ref1, ref2, ref3, text;
  if (content == null) {
    content = (ref = (ref1 = (ref2 = this.params.decode) != null ? ref2 : this.params.content) != null ? ref1 : this.params.text) != null ? ref : this.body;
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
    })).replace(/&#(\d+);/gi, (function(match, numStr) {
      var num;
      num = parseInt(numStr, 10);
      return String.fromCharCode(num);
    }));
  };
  text = (await _decode(content));
  text = text.replace(/\n/g, ' ');
  ref3 = [
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
  for (j = 0, len1 = ref3.length; j < len1; j++) {
    c = ref3[j];
    re = new RegExp(c.bad, 'g');
    text = text.replace(re, c.good);
  }
  if (text.indexOf('%2') !== -1) {
    text = decodeURIComponent(text);
  }
  if (text.indexOf('%2') !== -1) { // some of the data we handle was double encoded, so like %2520, so need two decodes
    text = decodeURIComponent(text);
  }
  return text;
};

P.copy = function(obj) {
  try {
    if (obj == null) {
      obj = this.params;
    }
  } catch (error) {}
  return JSON.parse(JSON.stringify(obj));
};

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

P.dot = function(obj, key) {
  var j, k, len1, ref, res, st;
  // TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if (typeof obj === 'string' && typeof key === 'object') {
    st = obj;
    obj = key;
    key = st;
  }
  if ((obj == null) && ((this != null ? (ref = this.params) != null ? ref.key : void 0 : void 0) != null)) {
    obj = this.copy(this.params);
    key = obj.key;
  }
  if (typeof key === 'string') {
    key = key.split('.');
  }
  try {
    res = obj;
    for (j = 0, len1 = key.length; j < len1; j++) {
      k = key[j];
      res = res[k];
    }
    return res;
  } catch (error) {

  }
};

P.flatten = async function(obj) {
  var _flatten, d, j, len1, res, results;
  if (obj == null) {
    obj = this.params;
  }
  res = {};
  _flatten = async function(obj, key) {
    var k, n, pk, results1, v;
    results1 = [];
    for (k in obj) {
      pk = key ? key + '.' + k : k;
      v = obj[k];
      if (typeof v === 'string') {
        results1.push(res[pk] = v);
      } else if (Array.isArray(v)) {
        if (typeof v[0] === 'object') {
          results1.push((await (async function() {
            var results2;
            results2 = [];
            for (n in v) {
              results2.push((await _flatten(v[n], pk + '.' + n)));
            }
            return results2;
          })()));
        } else {
          results1.push(res[pk] = v.join(', '));
        }
      } else {
        results1.push((await _flatten(v, pk)));
      }
    }
    return results1;
  };
  if (Array.isArray(obj)) {
    results = [];
    for (j = 0, len1 = data.length; j < len1; j++) {
      d = data[j];
      res = {};
      results.push((await _flatten(d)));
    }
    return results;
  } else {
    await _flatten(obj);
    return res;
  }
};

P.template = async function(content, vars) {
  var _rv, cp, cs, j, k, key, keyu, kg, kkg, l, len1, len2, pcp, ref, ref1, ref2, ref3, ret, val, vs;
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
      cs = (await this._templates(content));
      content = cs.content;
    } catch (error) {}
  }
  ret = {};
  _rv = function(obj, pre = '') {
    var o, ov, results1, rg;
    results1 = [];
    for (o in obj) {
      ov = pre ? pre + '.' + o : o;
      if (typeof obj[o] === 'object' && !Array.isArray(obj[o])) {
        results1.push(_rv(obj[o], pre + (pre === '' ? '' : '.') + o));
      } else if (content.toLowerCase().indexOf('{{' + ov + '}}') !== -1) {
        rg = new RegExp('{{' + ov + '}}', 'gi');
        results1.push(content = content.replace(rg, (Array.isArray(obj[o]) ? obj[o].join(', ') : (typeof obj[o] === 'string' ? obj[o] : (obj[o] === true ? 'Yes' : (obj[o] === false ? 'No' : ''))))));
      } else {
        results1.push(void 0);
      }
    }
    return results1;
  };
  _rv(vars); // replace all vars that are in the content
  kg = new RegExp('{{.*?}}', 'gi');
  if (content.indexOf('{{') !== -1) { // retrieve any vars provided IN the content (e.g. a content template can specify a subject for an email to use)
    vs = ['subject', 'from', 'to', 'cc', 'bcc'];
    ref3 = content.toLowerCase().split('{{');
    // the could be vars in content that themselves contain vars, e.g {{subject I am the subject about {{id}} yes I am}}
    // and some of those vars may fail to get filled in. So define the list of possible vars names THEN go through the content with them
    for (j = 0, len1 = ref3.length; j < len1; j++) {
      cp = ref3[j];
      pcp = cp.split('{{')[0].split('}}')[0].split(' ')[0];
      if (indexOf.call(vs, pcp) < 0) {
        vs.push(pcp);
      }
    }
    for (l = 0, len2 = vs.length; l < len2; l++) {
      k = vs[l];
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


//P._templates = _index: true # an index to store templates in - although generally should be handled at the individual function/service level
P.device = function() {
  var cf, res;
  // make a simple device hash, not enough to uniquely identify a user, 
  // but useful for discerning user across devices, so can help user manage
  // login across devices and possibly identify unexpected usage
  // use user-agent and accept headers, possibly others, and could use geo-ip too (see server utilities file)
  res = {};
  try {
    cf = this.request.cf;
    res.colo = cf.colo;
    res.city = cf.city;
    res.lat = cf.latitude;
    res.lon = cf.longitude;
  } catch (error) {}
  res.ip = this.headers.ip;
  res.country = this.headers['cf-ipcountry'];
  res.accept = this.headers['accept'];
  res['accept-language'] = this.headers['accept-language'];
  res['user-agent'] = this.headers['user-agent'];
  res['user-agent-hash'] = this.hashhex(this.headers['user-agent']);
  return res;
};

P.device._cache = false;

P.date = function(rt, timed, secs = true, ms = true) {
  var k, pts, ref, ref1, ret;
  if (rt == null) {
    rt = (ref = this.params.date) != null ? ref : Date.now();
  }
  if (timed == null) {
    timed = this.params.time;
  }
  if (typeof rt === 'number' || (typeof rt === 'string' && rt.indexOf(' ') === -1 && rt.indexOf('/') === -1 && rt.indexOf('-') === -1 && rt.length > 8 && rt.indexOf('T') === -1)) {
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
    if (rt.indexOf('T') !== -1) {
      rt = rt.split('T')[0];
    }
    rt = rt.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace(/-(\d)$/, "-0$1");
    if (rt.indexOf('-') === -1) {
      rt += '-01';
    }
    pts = rt.split('-');
    if (pts.length !== 3) {
      rt += '-01';
      pts = rt.split('-');
    }
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
  var add, end, ref, start, subtract;
  if (epoch == null) {
    epoch = this.params.epoch;
  }
  if (typeof epoch === 'number') {
    epoch = epoch.toString();
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
    if (epoch.indexOf('T') === -1) {
      epoch += 'T';
    }
    if (epoch.indexOf(':') === -1) {
      epoch += '00:00';
    }
    if (epoch.split(':').length < 3) {
      epoch += ':00';
    }
    if (epoch.indexOf('.') === -1) {
      epoch += '.';
    }
    [start, end] = epoch.split('.');
    end = end.replace('Z', '').replace('z', '');
    while (end.length < 3) {
      end += '0';
    }
    if (end.indexOf('Z') === -1) {
      end += 'Z';
    }
    return new Date(start + '.' + end).valueOf();
  }
};

P.epoch._cache = false;

P.subroutes = async function(top) {
  var _lp, subroutes;
  subroutes = [];
  _lp = (p, n, _hide) => {
    var k, nd, ref, results1;
    results1 = [];
    for (k in p) {
      if ((ref = typeof p[k]) === 'function' || ref === 'object') {
        nd = (n != null ? n : '') + (n ? '.' : '') + k;
        if (!k.startsWith('_') && (typeof p[k] === 'function' || p[k]._index || p[k]._kv || p[k]._sheet) && !p[k]._hide && !p[k]._hides && !_hide) {
          subroutes.push(nd.replace(/\./g, '/'));
        }
        if (!Array.isArray(p[k]) && !k.startsWith('_')) {
          results1.push(_lp(p[k], nd, _hide != null ? _hide : p[k]._hides));
        } else {
          results1.push(void 0);
        }
      } else {
        results1.push(void 0);
      }
    }
    return results1;
  };
  if (typeof top === 'string') {
    top = top.replace(/\//g, '.');
  }
  _lp(typeof top === 'string' ? (await this.dot(P, top)) : top != null ? top : P);
  return subroutes;
};

`P.limit = (fn, ms=300) ->
  p = 0
  t = null

  lim = () ->
    n = Date.now()
    r = ms - (n - p)
    args = arguments
    if r <= 0 or r > ms
      if t
        clearTimeout t
        t = null
      p = n
      res = fn.apply this, args
    else
      t ?= setTimeout () =>
        p = Date.now()
        res = fn.apply this, args
      , r
    return res

  lim.stop = () -> clearTimeout t
  return lim`;

`P.retry = (fn, params=[], opts={}) ->
  # params should be a list of params for the fn
  params = [params] if not Array.isArray params
  opts.retry ?= 3
  opts.pause ?= 500
  opts.increment ?= true
  # can provide a function in opts.check to check the result each time, and an opts.timeout to timeout each loop

  while opts.retry > 0
    res = undefined
    _wrap = () ->
      try
        res = await fn.apply this, params
    if typeof opts.timeout is 'number'
      await Promise.race [_wrap.call(this), P.sleep(opts.timeout)]
    else
      _wrap.call this
    if typeof opts.check is 'function'
      retry = await opts.check res, retry
      if retry is true
        return res
      else if retry is false
        retry -= 1
      else if typeof retry isnt 'number'
        retry = 0
    else if res? and res isnt false
      return res
    else
      retry -= 1

    if typeof opts.pause is 'number' and opts.pause isnt 0
      await P.sleep opts.pause
      if opts.increment is true
        opts.pause = opts.pause * 2
      else if typeof opts.increment is 'number'
        opts.pause += opts.increment
    
  return

  # an example of how retry may be used? TODO test this
  opts = retry: 3 # and can set pause, increment, check, timeout if desired (see above)
  res = @retry.call this, _f, [url, params], opts # where _f is the function to retry
`;

P.passphrase = function(len, lowercase) {
  var ref, ref1, ref2, ref3, w, wl, words;
  if (len == null) {
    len = (ref = (ref1 = this.params.passphrase) != null ? ref1 : this.params.len) != null ? ref : 4;
  }
  if (lowercase == null) {
    lowercase = (ref2 = (ref3 = this.params.lowercase) != null ? ref3 : this.params.lower) != null ? ref2 : false;
  }
  words = [];
  wl = P._passphrase_words.length;
  while (words.length < len) {
    w = P._passphrase_words[Math.floor(Math.random() * wl)];
    words.push(lowercase ? w : w.substring(0, 1).toUpperCase() + w.substring(1));
  }
  return words.join('');
};

P.passphrase._cache = false;

// the original xkcd password generator word list of 1949 common English words
// https://preshing.com/20110811/xkcd-password-generator/
// https://xkcd.com/936/
P._passphrase_words = ["ability", "able", "aboard", "about", "above", "accept", "accident", "according", "account", "accurate", "acres", "across", "act", "action", "active", "activity", "actual", "actually", "add", "addition", "additional", "adjective", "adult", "adventure", "advice", "affect", "afraid", "after", "afternoon", "again", "against", "age", "ago", "agree", "ahead", "aid", "air", "airplane", "alike", "alive", "all", "allow", "almost", "alone", "along", "aloud", "alphabet", "already", "also", "although", "am", "among", "amount", "ancient", "angle", "angry", "animal", "announced", "another", "answer", "ants", "any", "anybody", "anyone", "anything", "anyway", "anywhere", "apart", "apartment", "appearance", "apple", "applied", "appropriate", "are", "area", "arm", "army", "around", "arrange", "arrangement", "arrive", "arrow", "art", "article", "as", "aside", "ask", "asleep", "at", "ate", "atmosphere", "atom", "atomic", "attached", "attack", "attempt", "attention", "audience", "author", "automobile", "available", "average", "avoid", "aware", "away", "baby", "back", "bad", "badly", "bag", "balance", "ball", "balloon", "band", "bank", "bar", "bare", "bark", "barn", "base", "baseball", "basic", "basis", "basket", "bat", "battle", "be", "bean", "bear", "beat", "beautiful", "beauty", "became", "because", "become", "becoming", "bee", "been", "before", "began", "beginning", "begun", "behavior", "behind", "being", "believed", "bell", "belong", "below", "belt", "bend", "beneath", "bent", "beside", "best", "bet", "better", "between", "beyond", "bicycle", "bigger", "biggest", "bill", "birds", "birth", "birthday", "bit", "bite", "black", "blank", "blanket", "blew", "blind", "block", "blood", "blow", "blue", "board", "boat", "body", "bone", "book", "border", "born", "both", "bottle", "bottom", "bound", "bow", "bowl", "box", "boy", "brain", "branch", "brass", "brave", "bread", "break", "breakfast", "breath", "breathe", "breathing", "breeze", "brick", "bridge", "brief", "bright", "bring", "broad", "broke", "broken", "brother", "brought", "brown", "brush", "buffalo", "build", "building", "built", "buried", "burn", "burst", "bus", "bush", "business", "busy", "but", "butter", "buy", "by", "cabin", "cage", "cake", "call", "calm", "came", "camera", "camp", "can", "canal", "cannot", "cap", "capital", "captain", "captured", "car", "carbon", "card", "care", "careful", "carefully", "carried", "carry", "case", "cast", "castle", "cat", "catch", "cattle", "caught", "cause", "cave", "cell", "cent", "center", "central", "century", "certain", "certainly", "chain", "chair", "chamber", "chance", "change", "changing", "chapter", "character", "characteristic", "charge", "chart", "check", "cheese", "chemical", "chest", "chicken", "chief", "child", "children", "choice", "choose", "chose", "chosen", "church", "circle", "circus", "citizen", "city", "class", "classroom", "claws", "clay", "clean", "clear", "clearly", "climate", "climb", "clock", "close", "closely", "closer", "cloth", "clothes", "clothing", "cloud", "club", "coach", "coal", "coast", "coat", "coffee", "cold", "collect", "college", "colony", "color", "column", "combination", "combine", "come", "comfortable", "coming", "command", "common", "community", "company", "compare", "compass", "complete", "completely", "complex", "composed", "composition", "compound", "concerned", "condition", "congress", "connected", "consider", "consist", "consonant", "constantly", "construction", "contain", "continent", "continued", "contrast", "control", "conversation", "cook", "cookies", "cool", "copper", "copy", "corn", "corner", "correct", "correctly", "cost", "cotton", "could", "count", "country", "couple", "courage", "course", "court", "cover", "cow", "cowboy", "crack", "cream", "create", "creature", "crew", "crop", "cross", "crowd", "cry", "cup", "curious", "current", "curve", "customs", "cut", "cutting", "daily", "damage", "dance", "danger", "dangerous", "dark", "darkness", "date", "daughter", "dawn", "day", "dead", "deal", "dear", "death", "decide", "declared", "deep", "deeply", "deer", "definition", "degree", "depend", "depth", "describe", "desert", "design", "desk", "detail", "determine", "develop", "development", "diagram", "diameter", "did", "die", "differ", "difference", "different", "difficult", "difficulty", "dig", "dinner", "direct", "direction", "directly", "dirt", "dirty", "disappear", "discover", "discovery", "discuss", "discussion", "disease", "dish", "distance", "distant", "divide", "division", "do", "doctor", "does", "dog", "doing", "doll", "dollar", "done", "donkey", "door", "dot", "double", "doubt", "down", "dozen", "draw", "drawn", "dream", "dress", "drew", "dried", "drink", "drive", "driven", "driver", "driving", "drop", "dropped", "drove", "dry", "duck", "due", "dug", "dull", "during", "dust", "duty", "each", "eager", "ear", "earlier", "early", "earn", "earth", "easier", "easily", "east", "easy", "eat", "eaten", "edge", "education", "effect", "effort", "egg", "eight", "either", "electric", "electricity", "element", "elephant", "eleven", "else", "empty", "end", "enemy", "energy", "engine", "engineer", "enjoy", "enough", "enter", "entire", "entirely", "environment", "equal", "equally", "equator", "equipment", "escape", "especially", "essential", "establish", "even", "evening", "event", "eventually", "ever", "every", "everybody", "everyone", "everything", "everywhere", "evidence", "exact", "exactly", "examine", "example", "excellent", "except", "exchange", "excited", "excitement", "exciting", "exclaimed", "exercise", "exist", "expect", "experience", "experiment", "explain", "explanation", "explore", "express", "expression", "extra", "eye", "face", "facing", "fact", "factor", "factory", "failed", "fair", "fairly", "fall", "fallen", "familiar", "family", "famous", "far", "farm", "farmer", "farther", "fast", "fastened", "faster", "fat", "father", "favorite", "fear", "feathers", "feature", "fed", "feed", "feel", "feet", "fell", "fellow", "felt", "fence", "few", "fewer", "field", "fierce", "fifteen", "fifth", "fifty", "fight", "fighting", "figure", "fill", "film", "final", "finally", "find", "fine", "finest", "finger", "finish", "fire", "fireplace", "firm", "first", "fish", "five", "fix", "flag", "flame", "flat", "flew", "flies", "flight", "floating", "floor", "flow", "flower", "fly", "fog", "folks", "follow", "food", "foot", "football", "for", "force", "foreign", "forest", "forget", "forgot", "forgotten", "form", "former", "fort", "forth", "forty", "forward", "fought", "found", "four", "fourth", "fox", "frame", "free", "freedom", "frequently", "fresh", "friend", "friendly", "frighten", "frog", "from", "front", "frozen", "fruit", "fuel", "full", "fully", "fun", "function", "funny", "fur", "furniture", "further", "future", "gain", "game", "garage", "garden", "gas", "gasoline", "gate", "gather", "gave", "general", "generally", "gentle", "gently", "get", "getting", "giant", "gift", "girl", "give", "given", "giving", "glad", "glass", "globe", "go", "goes", "gold", "golden", "gone", "good", "goose", "got", "government", "grabbed", "grade", "gradually", "grain", "grandfather", "grandmother", "graph", "grass", "gravity", "gray", "great", "greater", "greatest", "greatly", "green", "grew", "ground", "group", "grow", "grown", "growth", "guard", "guess", "guide", "gulf", "gun", "habit", "had", "hair", "half", "halfway", "hall", "hand", "handle", "handsome", "hang", "happen", "happened", "happily", "happy", "harbor", "hard", "harder", "hardly", "has", "hat", "have", "having", "hay", "he", "headed", "heading", "health", "heard", "hearing", "heart", "heat", "heavy", "height", "held", "hello", "help", "helpful", "her", "herd", "here", "herself", "hidden", "hide", "high", "higher", "highest", "highway", "hill", "him", "himself", "his", "history", "hit", "hold", "hole", "hollow", "home", "honor", "hope", "horn", "horse", "hospital", "hot", "hour", "house", "how", "however", "huge", "human", "hundred", "hung", "hungry", "hunt", "hunter", "hurried", "hurry", "hurt", "husband", "ice", "idea", "identity", "if", "ill", "image", "imagine", "immediately", "importance", "important", "impossible", "improve", "in", "inch", "include", "including", "income", "increase", "indeed", "independent", "indicate", "individual", "industrial", "industry", "influence", "information", "inside", "instance", "instant", "instead", "instrument", "interest", "interior", "into", "introduced", "invented", "involved", "iron", "is", "island", "it", "its", "itself", "jack", "jar", "jet", "job", "join", "joined", "journey", "joy", "judge", "jump", "jungle", "just", "keep", "kept", "key", "kids", "kill", "kind", "kitchen", "knew", "knife", "know", "knowledge", "known", "label", "labor", "lack", "lady", "laid", "lake", "lamp", "land", "language", "large", "larger", "largest", "last", "late", "later", "laugh", "law", "lay", "layers", "lead", "leader", "leaf", "learn", "least", "leather", "leave", "leaving", "led", "left", "leg", "length", "lesson", "let", "letter", "level", "library", "lie", "life", "lift", "light", "like", "likely", "limited", "line", "lion", "lips", "liquid", "list", "listen", "little", "live", "living", "load", "local", "locate", "location", "log", "lonely", "long", "longer", "look", "loose", "lose", "loss", "lost", "lot", "loud", "love", "lovely", "low", "lower", "luck", "lucky", "lunch", "lungs", "lying", "machine", "machinery", "mad", "made", "magic", "magnet", "mail", "main", "mainly", "major", "make", "making", "man", "managed", "manner", "manufacturing", "many", "map", "mark", "market", "married", "mass", "massage", "master", "material", "mathematics", "matter", "may", "maybe", "me", "meal", "mean", "means", "meant", "measure", "meat", "medicine", "meet", "melted", "member", "memory", "men", "mental", "merely", "met", "metal", "method", "mice", "middle", "might", "mighty", "mile", "military", "milk", "mill", "mind", "mine", "minerals", "minute", "mirror", "missing", "mission", "mistake", "mix", "mixture", "model", "modern", "molecular", "moment", "money", "monkey", "month", "mood", "moon", "more", "morning", "most", "mostly", "mother", "motion", "motor", "mountain", "mouse", "mouth", "move", "movement", "movie", "moving", "mud", "muscle", "music", "musical", "must", "my", "myself", "mysterious", "nails", "name", "nation", "national", "native", "natural", "naturally", "nature", "near", "nearby", "nearer", "nearest", "nearly", "necessary", "neck", "needed", "needle", "needs", "negative", "neighbor", "neighborhood", "nervous", "nest", "never", "new", "news", "newspaper", "next", "nice", "night", "nine", "no", "nobody", "nodded", "noise", "none", "noon", "nor", "north", "nose", "not", "note", "noted", "nothing", "notice", "noun", "now", "number", "numeral", "nuts", "object", "observe", "obtain", "occasionally", "occur", "ocean", "of", "off", "offer", "office", "officer", "official", "oil", "old", "older", "oldest", "on", "once", "one", "only", "onto", "open", "operation", "opinion", "opportunity", "opposite", "or", "orange", "orbit", "order", "ordinary", "organization", "organized", "origin", "original", "other", "ought", "our", "ourselves", "out", "outer", "outline", "outside", "over", "own", "owner", "oxygen", "pack", "package", "page", "paid", "pain", "paint", "pair", "palace", "pale", "pan", "paper", "paragraph", "parallel", "parent", "park", "part", "particles", "particular", "particularly", "partly", "parts", "party", "pass", "passage", "past", "path", "pattern", "pay", "peace", "pen", "pencil", "people", "per", "percent", "perfect", "perfectly", "perhaps", "period", "person", "personal", "pet", "phrase", "physical", "piano", "pick", "picture", "pictured", "pie", "piece", "pig", "pile", "pilot", "pine", "pink", "pipe", "pitch", "place", "plain", "plan", "plane", "planet", "planned", "planning", "plant", "plastic", "plate", "plates", "play", "pleasant", "please", "pleasure", "plenty", "plural", "plus", "pocket", "poem", "poet", "poetry", "point", "pole", "police", "policeman", "political", "pond", "pony", "pool", "poor", "popular", "population", "porch", "port", "position", "positive", "possible", "possibly", "post", "pot", "potatoes", "pound", "pour", "powder", "power", "powerful", "practical", "practice", "prepare", "present", "president", "press", "pressure", "pretty", "prevent", "previous", "price", "pride", "primitive", "principal", "principle", "printed", "private", "prize", "probably", "problem", "process", "produce", "product", "production", "program", "progress", "promised", "proper", "properly", "property", "protection", "proud", "prove", "provide", "public", "pull", "pupil", "pure", "purple", "purpose", "push", "put", "putting", "quarter", "queen", "question", "quick", "quickly", "quiet", "quietly", "quite", "rabbit", "race", "radio", "railroad", "rain", "raise", "ran", "ranch", "range", "rapidly", "rate", "rather", "raw", "rays", "reach", "read", "reader", "ready", "real", "realize", "rear", "reason", "recall", "receive", "recent", "recently", "recognize", "record", "red", "refer", "refused", "region", "regular", "related", "relationship", "religious", "remain", "remarkable", "remember", "remove", "repeat", "replace", "replied", "report", "represent", "require", "research", "respect", "rest", "result", "return", "review", "rhyme", "rhythm", "rice", "rich", "ride", "riding", "right", "ring", "rise", "rising", "river", "road", "roar", "rock", "rocket", "rocky", "rod", "roll", "roof", "room", "root", "rope", "rose", "rough", "round", "route", "row", "rubbed", "rubber", "rule", "ruler", "run", "running", "rush", "sad", "saddle", "safe", "safety", "said", "sail", "sale", "salmon", "salt", "same", "sand", "sang", "sat", "satellites", "satisfied", "save", "saved", "saw", "say", "scale", "scared", "scene", "school", "science", "scientific", "scientist", "score", "screen", "sea", "search", "season", "seat", "second", "secret", "section", "see", "seed", "seeing", "seems", "seen", "seldom", "select", "selection", "sell", "send", "sense", "sent", "sentence", "separate", "series", "serious", "serve", "service", "sets", "setting", "settle", "settlers", "seven", "several", "shade", "shadow", "shake", "shaking", "shall", "shallow", "shape", "share", "sharp", "she", "sheep", "sheet", "shelf", "shells", "shelter", "shine", "shinning", "ship", "shirt", "shoe", "shoot", "shop", "shore", "short", "shorter", "shot", "should", "shoulder", "shout", "show", "shown", "shut", "sick", "sides", "sight", "sign", "signal", "silence", "silent", "silk", "silly", "silver", "similar", "simple", "simplest", "simply", "since", "sing", "single", "sink", "sister", "sit", "sitting", "situation", "six", "size", "skill", "skin", "sky", "slabs", "slave", "sleep", "slept", "slide", "slight", "slightly", "slip", "slipped", "slope", "slow", "slowly", "small", "smaller", "smallest", "smell", "smile", "smoke", "smooth", "snake", "snow", "so", "soap", "social", "society", "soft", "softly", "soil", "solar", "sold", "soldier", "solid", "solution", "solve", "some", "somebody", "somehow", "someone", "something", "sometime", "somewhere", "son", "song", "soon", "sort", "sound", "source", "south", "southern", "space", "speak", "special", "species", "specific", "speech", "speed", "spell", "spend", "spent", "spider", "spin", "spirit", "spite", "split", "spoken", "sport", "spread", "spring", "square", "stage", "stairs", "stand", "standard", "star", "stared", "start", "state", "statement", "station", "stay", "steady", "steam", "steel", "steep", "stems", "step", "stepped", "stick", "stiff", "still", "stock", "stomach", "stone", "stood", "stop", "stopped", "store", "storm", "story", "stove", "straight", "strange", "stranger", "straw", "stream", "street", "strength", "stretch", "strike", "string", "strip", "strong", "stronger", "struck", "structure", "struggle", "stuck", "student", "studied", "studying", "subject", "substance", "success", "successful", "such", "sudden", "suddenly", "sugar", "suggest", "suit", "sum", "summer", "sun", "sunlight", "supper", "supply", "support", "suppose", "sure", "surface", "surprise", "surrounded", "swam", "sweet", "swept", "swim", "swimming", "swing", "swung", "syllable", "symbol", "system", "table", "tail", "take", "taken", "tales", "talk", "tall", "tank", "tape", "task", "taste", "taught", "tax", "tea", "teach", "teacher", "team", "tears", "teeth", "telephone", "television", "tell", "temperature", "ten", "tent", "term", "terrible", "test", "than", "thank", "that", "thee", "them", "themselves", "then", "theory", "there", "therefore", "these", "they", "thick", "thin", "thing", "think", "third", "thirty", "this", "those", "thou", "though", "thought", "thousand", "thread", "three", "threw", "throat", "through", "throughout", "throw", "thrown", "thumb", "thus", "thy", "tide", "tie", "tight", "tightly", "till", "time", "tin", "tiny", "tip", "tired", "title", "to", "tobacco", "today", "together", "told", "tomorrow", "tone", "tongue", "tonight", "too", "took", "tool", "top", "topic", "torn", "total", "touch", "toward", "tower", "town", "toy", "trace", "track", "trade", "traffic", "trail", "train", "transportation", "trap", "travel", "treated", "tree", "triangle", "tribe", "trick", "tried", "trip", "troops", "tropical", "trouble", "truck", "trunk", "truth", "try", "tube", "tune", "turn", "twelve", "twenty", "twice", "two", "type", "typical", "uncle", "under", "underline", "understanding", "unhappy", "union", "unit", "universe", "unknown", "unless", "until", "unusual", "up", "upon", "upper", "upward", "us", "use", "useful", "using", "usual", "usually", "valley", "valuable", "value", "vapor", "variety", "various", "vast", "vegetable", "verb", "vertical", "very", "vessels", "victory", "view", "village", "visit", "visitor", "voice", "volume", "vote", "vowel", "voyage", "wagon", "wait", "walk", "wall", "want", "war", "warm", "warn", "was", "wash", "waste", "watch", "water", "wave", "way", "we", "weak", "wealth", "wear", "weather", "week", "weigh", "weight", "welcome", "well", "went", "were", "west", "western", "wet", "whale", "what", "whatever", "wheat", "wheel", "when", "whenever", "where", "wherever", "whether", "which", "while", "whispered", "whistle", "white", "who", "whole", "whom", "whose", "why", "wide", "widely", "wife", "wild", "will", "willing", "win", "wind", "window", "wing", "winter", "wire", "wise", "wish", "with", "within", "without", "wolf", "women", "won", "wonder", "wonderful", "wood", "wooden", "wool", "word", "wore", "work", "worker", "world", "worried", "worry", "worse", "worth", "would", "wrapped", "write", "writer", "writing", "written", "wrong", "wrote", "yard", "year", "yellow", "yes", "yesterday", "yet", "you", "young", "younger", "your", "yourself", "youth", "zero", "zoo"];

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

P.cache._hide = true;

P.cache._auth = 'system';

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
    dni = data._id.replace(/\//g, '_');
    if (route.indexOf('/') === -1 && route.indexOf(dni) === -1) {
      route += '/' + dni;
    }
    delete data._id; // ID can't go into the data for ES7.x
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

P.index._hides = true;

P.index._wraps = false;

P.index._caches = false;

P.index.status = async function() {
  var base2, i, j, k, l, len, len1, ref1, ref2, res, s, sh, shards;
  res = {
    status: 'green'
  };
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
        }
      }
    }
  }
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
    if (include) {
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
  ref3 = ['index', 'route', 'min', 'max', 'key'];
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

P.index.mapping = async function(route) {
  var ret;
  route = route.replace(/^\//, ''); // remove any leading /
  if (route.indexOf('/') === -1) {
    route = route + '/';
  }
  if (route.indexOf('_mapping') === -1) {
    route = route.replace('/', '/_mapping');
  }
  ret = (await this.index._send(route));
  return ret[route.replace('/_mapping', '').replace(/\//g, '_').replace(/^_/, '')].mappings.properties;
};

P.index.history = function(route, key) {
  var ref1;
  try {
    // TODO get the history of a record by a query of the log
    if (key == null) {
      key = (ref1 = this.params.history) != null ? ref1 : this.params.index;
    }
  } catch (error) {}
  return [];
};

// use this like: for await rec from @index._for route, q, opts
// see index._each below for example of how to call this for/yield generator
P.index._for = async function*(route, q, opts) {
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
  res = (await this.index._send(route + '/_search?scroll=' + scroll, qy));
  if (res != null ? res._scroll_id : void 0) {
    prs = res._scroll_id.replace(/==$/, '');
  }
  if ((res != null ? (ref2 = res.hits) != null ? ref2.total : void 0 : void 0) && ((max == null) || max > res.hits.total)) {
    max = res.hits.total;
  }
  counter = 0;
  while (true) {
    if ((!(res != null ? (ref3 = res.hits) != null ? ref3.hits : void 0 : void 0) || res.hits.hits.length === 0) && (res != null ? res._scroll_id : void 0)) { // get more if possible
      res = (await this.index._send('/_search/scroll?scroll=' + scroll + '&scroll_id=' + res._scroll_id));
      if ((res != null ? res._scroll_id : void 0) !== prs) {
        await this.index._send('/_search/scroll?scroll_id=' + prs, '');
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
        await this.index._send('/_search/scroll?scroll_id=' + prs, '');
      }
      break;
    }
  }
};

P.index._each = async function(route, q, opts, fn) {
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
    chk = (await this.index._send(route, qy));
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
  ref3 = this.index._for(route, qy != null ? qy : q, opts);
  for await (rec of ref3) {
    fr = (await fn.call(this, rec));
    processed += 1;
    if ((fr != null) && (typeof fr === 'object' || typeof fr === 'string')) {
      updates.push(fr);
    }
    if (action && updates.length > sz) {
      await this.index._bulk(route, updates, action);
      updates = [];
    }
  }
  if (action && updates.length) { // catch any left over
    this.index._bulk(route, updates, action);
  }
  if (this.S.dev && this.S.bg === true) {
    return console.log('_each processed ' + processed);
  }
};

P.index._bulk = async function(route, data, action = 'index', bulk = 50000) {
  var counter, errorcount, errors, it, j, len, meta, pkg, prefix, r, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rid, row, rows, rs;
  if (action === true) {
    action = 'index';
  }
  prefix = (await this.dot(P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'));
  if (prefix !== false) { // need to do this here as well as in _send so it can be set below in each object of the bulk
    route = this.S.index.name + '_' + route;
  }
  if (this.index == null) {
    this.index = P.index;
  }
  if (typeof data === 'string' && data.indexOf('\n') !== -1) {
    // TODO should this check through the string and make sure it only indexes to the specified route?
    await this.index._send('/_bulk', {
      body: data,
      headers: {
        'Content-Type': 'application/x-ndjson' // new ES 7.x requires this rather than text/plain
      }
    });
    return true;
  } else {
    rows = typeof data === 'object' && !Array.isArray(data) && ((data != null ? (ref1 = data.hits) != null ? ref1.hits : void 0 : void 0) != null) ? data.hits.hits : data;
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
        rid = (ref2 = (ref3 = row._id) != null ? ref3 : (ref4 = row._source) != null ? ref4._id : void 0) != null ? ref2 : (await this.uid());
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
      meta[action]._id = action === 'delete' && ((ref5 = typeof row) === 'string' || ref5 === 'number') ? row : rid; // what if action is delete but can't set an ID?
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
        }));
        if ((this != null ? (ref6 = this.S) != null ? ref6.dev : void 0 : void 0) && (this != null ? (ref7 = this.S) != null ? ref7.bg : void 0 : void 0) === true && (rs != null ? rs.errors : void 0)) {
          errors = [];
          ref8 = rs.items;
          for (j = 0, len = ref8.length; j < len; j++) {
            it = ref8[j];
            try {
              if ((ref9 = it[action].status) !== 200 && ref9 !== 201) {
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
  var af, ag, b, base2, base3, base4, base5, bm, etp, exc, f, fq, i, inc, j, k, l, len, len1, len2, len3, len4, len5, len6, ls, n, o, ords, pfx, qpts, qry, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rkeys, rs, so, sorts, sq, t, tm, tp, u, v, w, x;
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
    if (JSON.stringify(q) !== '{}' && (q.q == null) && (q.query == null) && (q.source == null) && (q.must == null) && (q.should == null) && (q.must_not == null) && (q.filter == null) && (q.aggs == null) && (q.aggregations == null)) {
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
        if (typeof q.source === 'string') {
          try {
            qry = JSON.parse(decodeURIComponent(q.source));
          } catch (error) {}
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
  if ((qry.query != null) && (qry.query.bool == null) && JSON.stringify(qry.query !== '{}')) {
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
    if ((v != null) && (k !== 'apikey' && k !== '_' && k !== 'callback' && k !== 'refresh' && k !== 'key' && k !== 'counts' && k !== 'index' && k !== 'search' && k !== 'source' && k !== 'q') && ((ref19 = k.replace('_', '').replace('s', '')) !== 'include' && ref19 !== 'exclude')) {
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
P.index._send = async function(route, data, method) {
  var opts, prefix, ref1, ref2, ref3, ref4, res, rqp, url;
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
    if (this.S.index.name && !route.startsWith(this.S.index.name) && !route.startsWith('_')) {
      prefix = (await this.dot(P, (route.split('/')[0]).replace(/_/g, '.') + '._prefix'));
      // TODO could allow prefix to be a list of names, and if index name is in the list, alias the index into those namespaces, to share indexes between specific instances rather than just one or global
      if (prefix !== false) {
        route = (typeof prefix === 'string' ? prefix : this.S.index.name) + '_' + route;
      }
    }
    url = (this != null ? (ref2 = this.S) != null ? (ref3 = ref2.index) != null ? ref3.url : void 0 : void 0 : void 0) ? this.S.index.url : (ref4 = S.index) != null ? ref4.url : void 0;
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
  route = route += rqp;
  opts = route.indexOf('/_bulk') !== -1 || typeof (data != null ? data.headers : void 0) === 'object' ? data : {
    body: data // fetch requires data to be body
  };
  if (route.indexOf('/_search') !== -1 && (method === 'GET' || method === 'POST')) { // scrolling isn't a new search so ignore a scroll DELETE otherwise adding the param would error
    // avoid hits.total coming back as object in new ES, because it also becomes vague
    // see hits.total https://www.elastic.co/guide/en/elasticsearch/reference/current/breaking-changes-7.0.html
    route += (route.indexOf('?') === -1 ? '?' : '&') + 'rest_total_hits_as_int=true';
  }
  if (this.S.dev && this.S.bg === true && ((data != null ? data.query : void 0) == null) && !route.includes('/_doc/') && (method === 'DELETE' || !route.includes('_search/scroll'))) {
    console.log('INDEX', method, route);
  }
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
    try {
      if (this.S.dev && ((data != null ? data.query : void 0) != null)) {
        res.q = data;
      }
    } catch (error) {}
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

P.kv._hides = true;

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

// BASE provide a search endpoint, but must register our IP to use it first
// limited to non-commercial and 1 query per second, contact them for more options
// register here: https://www.base-search.net/about/en/contact.php (registered)
// docs here:
// http://www.base-search.net/about/download/base_interface.pdf
P.src.base = {};

P.src.base.doi = async function(doi) {
  //return @src.base.get doi
  return (await this.fetch('https://dev.api.cottagelabs.com/use/base/doi/' + doi));
};

P.src.base.title = async function(title) {
  var ct, ret;
  title = title.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036F]/g, '').replace(/ß/g, 'ss');
  ret = (await this.src.base.get('dctitle:"' + title + '"'));
  if (((ret != null ? ret.dctitle : void 0) != null) || (ret.title != null)) {
    if (ret.title == null) {
      ret.title = ret.dctitle;
    }
    if (ret.title) {
      ct = ret.title.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036F]/g, '').replace(/ß/g, 'ss');
      if (ct && ct.length <= title.length * 1.2 && ct.length >= title.length * .8 && title.replace(/ /g, '').indexOf(ct.replace(' ', '').replace(' ', '').replace(' ', '').split(' ')[0]) !== -1) {
        return ret;
      }
    }
  }
};

P.src.base.get = async function(qry) {
  var ref, res;
  res = (await this.src.base.search(qry));
  if (res != null ? (ref = res.data) != null ? ref.length : void 0 : void 0) {
    return res.data[0];
  } else {
    return void 0;
  }
};

P.src.base.search = async function(qry = '*', from, size) {
  var res, url;
  if (qry.indexOf('"') === -1 && qry.indexOf(' ') !== -1) {
    // it uses offset and hits (default 10) for from and size, and accepts solr query syntax
    // string terms, "" to be next to each other, otherwise ANDed, can accept OR, and * or ? wildcards, brackets to group, - to negate
    //proxy = @S.proxy # need to route through the proxy so requests come from registered IP
    //return undefined if not proxy
    qry = qry.replace(/ /g, '+');
  }
  url = 'https://api.base-search.net/cgi-bin/BaseHttpSearchInterface.fcgi?func=PerformSearch&format=json&query=' + qry;
  if (from) { // max 1000
    url += '&offset=' + from;
  }
  if (size) { // max 125
    url += '&hits=' + size;
  }
  url += '&sortBy=dcdate+desc';
  try {
    // add bg true to this as well, or proxy
    res = (await this.fetch(url)); //, {timeout:timeout,npmRequestOptions:{proxy:proxy}}
    res = JSON.parse(res).response;
    res.data = res.docs;
    delete res.docs;
    res.total = res.numFound;
    return res;
  } catch (error) {}
};

// https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
// http://api.crossref.org/works/10.1016/j.paid.2009.02.013
var indexOf = [].indexOf;

P.src.crossref = function() {
  return 'Crossref API wrapper';
};

P.src.crossref.journals = async function(issn) {
  var ref, ref1, res;
  if (issn == null) {
    issn = (ref = this.params.journals) != null ? ref : this.params.issn;
  }
  res = (await this.fetch('https://api.crossref.org/journals/' + issn, {
    headers: {
      'User-Agent': this.S.name + '; mailto:' + ((ref1 = this.S.mail) != null ? ref1.to : void 0)
    }
  }));
  return res != null ? res.message : void 0;
};

//P.src.crossref.journals._index = true
//P.src.crossref.journals._key = 'ISSN'
//P.src.crossref.journals._prefix = false
P.src.crossref.journals.doi = async function(issn) {
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

P.src.crossref.works = async function(doi) {
  var ref, ref1, ref2, ref3, ref4, res, url;
  if (doi == null) {
    doi = (ref = (ref1 = (ref2 = this.params.works) != null ? ref2 : this.params.doi) != null ? ref1 : this.params.title) != null ? ref : this.params.q;
  }
  if (typeof doi === 'string') {
    if (doi.indexOf('10.') !== 0) {
      res = (await this.src.crossref.works.title(doi));
    } else {
      if (doi.indexOf('http') === 0) {
        // a search of an index of works - and remainder of route is a DOI to return one record
        doi = doi.split('//')[1];
      }
      if (doi.indexOf('10.') !== 0 && doi.indexOf('/10.') !== -1) {
        doi = '10.' + doi.split('/10.')[1];
      }
      url = 'https://api.crossref.org/works/' + doi;
      res = (await this.fetch(url, {
        headers: {
          'User-Agent': this.S.name + '; mailto:' + ((ref3 = this.S.mail) != null ? ref3.to : void 0)
        }
      }));
    }
    if ((res != null ? (ref4 = res.message) != null ? ref4.DOI : void 0 : void 0) != null) {
      return this.src.crossref.works._format(res.message);
    }
  }
};

//P.src.crossref.works._kv = false
P.src.crossref.works._index = {
  settings: {
    number_of_shards: 9
  }
};

P.src.crossref.works._key = 'DOI';

P.src.crossref.works._prefix = false;

// TODO this really should be handled by the main crossref.works function, then 
// the wrapper should query in advance, like it does, but then be able to tell 
// the difference between an actual query and an attempt to get a specific record
P.src.crossref.works.title = function(title) {
  var i, j, len, len1, ltitle, qr, r, ref, ref1, ref2, ref3, ref4, rem, res, rt, st, t;
  if (title == null) {
    title = (ref = this.params.title) != null ? ref : this.params.q;
  }
  qr = 'title:"' + title + '"';
  if (title.split(' ').length > 2) {
    qr += ' OR (';
    ref1 = title.split(' ');
    for (i = 0, len = ref1.length; i < len; i++) {
      t = ref1[i];
      if (!qr.endsWith('(')) {
        qr += ' AND ';
      }
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")';
    }
    qr += ')';
  }
  rem = this.src.crossref.works(qr);
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
  ref4 = (ref2 = rem != null ? (ref3 = rem.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
  for (j = 0, len1 = ref4.length; j < len1; j++) {
    r = ref4[j];
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
  var a, au, i, j, l, len, len1, len2, m, ref, ref1, ref2, ref3, ref4, ref5, ref6;
  if (rec.abstract) {
    rec.abstract = rec.abstract.replace(/<.*?>/g, '').replace(/^ABSTRACT/, '');
  }
  if (rec._id == null) {
    rec._id = rec.DOI.replace(/\//g, '_');
  }
  ref1 = (ref = rec.assertion) != null ? ref : [];
  for (i = 0, len = ref1.length; i < len; i++) {
    a = ref1[i];
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
  for (j = 0, len1 = ref3.length; j < len1; j++) {
    l = ref3[j];
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
  for (m = 0, len2 = ref5.length; m < len2; m++) {
    au = ref5[m];
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
  var i, len, p, pp, ppe, ppp, ref, ref1, rp;
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
    for (i = 0, len = ref.length; i < len; i++) {
      p = ref[i];
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

P.src.crossref.works.published._hide = true;

P.src.crossref.works.search = async function(qrystr, from, size, filter, start, end, sort, order) {
  var filtered, fp, k, ky, qry, ref, ref1, ref2, ref3, ref4, ref5, res, url;
  if (qrystr == null) {
    qrystr = (ref = (ref1 = this.params.q) != null ? ref1 : this.params.search) != null ? ref : this.params;
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
    order = (ref2 = this.params.order) != null ? ref2 : 'asc';
  }
  if (start) {
    filtered = (ref3 = filter != null ? filter : sort) != null ? ref3 : 'created'; // can be published, indexed, deposited, created. indexed catches the most changes but can be very large and takes a long time
    if (typeof start !== 'string' || start.indexOf('-') === -1) { // should be like 2021-01-31
      start = (await this.date(start));
    }
    filter = (filter ? filter + ',' : '') + 'from-' + filtered.replace('lished', '').replace('xed', 'x').replace('ited', 'it') + '-date:' + start;
  }
  if (end) {
    if (filtered == null) {
      filtered = (ref4 = filter != null ? filter : sort) != null ? ref4 : 'created';
    }
    if (typeof end !== 'string' || end.indexOf('-') === -1) {
      end = (await this.date(end));
    }
    filter = (filter ? filter + ',' : '') + 'until-' + filtered.replace('lished', '').replace('xed', 'x').replace('ited', 'it') + '-date:' + end;
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
  if ((filter != null) && filter !== '') {
    url += 'filter=' + encodeURIComponent(filter) + '&';
  }
  url = url.replace('?&', '?').replace(/&$/, ''); // tidy any params coming immediately after the start of search query param signifier, as it makes crossref error out
  try {
    res = (await this.fetch(url, {
      headers: {
        'User-Agent': this.S.name + '; mailto:' + ((ref5 = this.S.mail) != null ? ref5.to : void 0)
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

P.src.doaj = {};

P.src.doaj.journals = async function(issn) {
  var ref, res;
  if (issn == null) {
    issn = (ref = this.params.journals) != null ? ref : this.params.issn;
  }
  if (issn) {
    try {
      res = (await this.fetch('https://doaj.org/api/v2/search/journals/' + issn));
      return res.results[0];
    } catch (error) {}
  }
};

P.src.doaj.articles = async function(qry) {
  var op, ref, res, title, url;
  url = 'https://doaj.org/api/v1/search/articles';
  try {
    title = this.params.title.toLowerCase().replace(/(<([^>]+)>)/g, '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
  } catch (error) {}
  if (title || typeof qry === 'string') {
    if (qry.startsWith('10.')) {
      qry += 'doi:';
    }
    url += (ref = '/' + title) != null ? ref : qry;
  } else {
    url += '?';
    for (op in params) {
      url += op + '=' + params[op] + '&';
    }
  }
  res = (await this.fetch(url)); // note for DOAJ this needs a 300ms limiter
  return res.results;
};

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
P.src.epmc = {
  _index: true,
  _prefix: false,
  _key: 'id' // id will be the pubmed ID from the looks of it
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
  await this.sleep(200);
  res = (await this.fetch(url));
  ret.total = res.hitCount;
  ret.data = (ref3 = (ref4 = res.resultList) != null ? ref4.result : void 0) != null ? ref3 : [];
  ret.cursor = res.nextCursorMark;
  if (ret.data.length) {
    this.waitUntil(this.src.epmc(ret.data));
  }
  return ret;
};

P.src.epmc.doi = async function(ident) {
  var res;
  if (ident == null) {
    ident = this.params.doi;
  }
  if (res = (await this.src.epmc('doi:"' + ident + '"', 1))) {
    return res;
  } else {
    res = (await this.src.epmc.search('DOI:' + ident));
    if (res.total) {
      return res.data[0];
    } else {
      return void 0;
    }
  }
};

P.src.epmc.doi._hide = true;

P.src.epmc.pmid = async function(ident) {
  var res;
  if (ident == null) {
    ident = this.params.pmid;
  }
  if (res = (await this.src.epmc('pmid:"' + ident + '"', 1))) {
    return res;
  } else {
    res = (await this.src.epmc.search('EXT_ID:' + ident + ' AND SRC:MED'));
    if (res.total) {
      return res.data[0];
    } else {
      return void 0;
    }
  }
};

P.src.epmc.pmc = async function(ident) {
  var ref, res;
  if (ident == null) {
    ident = (ref = this.params.pmc) != null ? ref : this.params.pmcid;
  }
  ident = 'PMC' + ident.toLowerCase().replace('pmc', '');
  if (res = (await this.src.epmc('pmcid:"' + ident + '"', 1))) {
    return res;
  } else {
    res = (await this.src.epmc.search('PMCID:' + ident));
    if (res.total) {
      return res.data[0];
    } else {
      return void 0;
    }
  }
};

P.src.epmc.title = async function(title) {
  var res;
  if (title == null) {
    title = this.params.title;
  }
  try {
    title = title.toLowerCase().replace(/(<([^>]+)>)/g, '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
  } catch (error) {}
  if (res = (await this.src.epmc('title:"' + title + '"', 1))) {
    return res;
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
  var lics, pg, ref, ref1, ref2, ref3, url;
  if (pmcid == null) {
    pmcid = (ref = (ref1 = this.params.licence) != null ? ref1 : this.params.pmcid) != null ? ref : this.params.epmc;
  }
  if (pmcid) {
    pmcid = 'PMC' + pmcid.toLowerCase().replace('pmc', '');
  }
  if (refresh == null) {
    refresh = this.refresh;
  }
  if (pmcid && (rec == null)) {
    rec = (await this.src.epmc.pmc(pmcid));
  }
  if (rec || fulltext) {
    if (((rec != null ? rec.calculated_licence : void 0) != null) && !refresh) {
      return rec.calculated_licence;
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
        if (((ref2 = this.svc.lantern) != null ? ref2.licence : void 0) != null) {
          if (typeof fulltext === 'string' && fulltext.startsWith('<')) {
            lics = (await this.svc.lantern.licence(void 0, fulltext, '<permissions>', '</permissions>'));
            if ((lics != null ? lics.licence : void 0) != null) {
              lics.source = 'epmc_xml_permissions';
            }
          }
          if ((lics != null ? lics.licence : void 0) == null) {
            lics = (await this.svc.lantern.licence(void 0, fulltext));
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
        if (pmcid && (((ref3 = this.svc.lantern) != null ? ref3.licence : void 0) != null) && (((lics != null ? lics.licence : void 0) == null) || (lics != null ? lics.licence : void 0) === 'non-standard-licence')) {
          await this.sleep(1000);
          url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc', '');
          if (pg = (await this.puppet(url))) {
            try {
              lics = (await this.svc.lantern.licence(void 0, pg));
            } catch (error) {}
            if ((lics != null ? lics.licence : void 0) != null) {
              lics.source = 'epmc_html';
            }
          }
        }
      }
    }
    if ((lics != null ? lics.licence : void 0) != null) {
      rec.calculated_licence = lics;
      await this.src.epmc(rec.id, rec);
      return lics;
    }
  }
};

P.src.epmc.xml = async function(pmcid, rec) {
  var ft, ref, ref1;
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
        await this.sleep(200);
        ft = (await this.fetch('https://www.ebi.ac.uk/europepmc/webservices/rest/' + pmcid + '/fullTextXML'));
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

P.src.epmc.aam = async function(pmcid, rec, fulltext) {
  var pg, ref, ref1, s1, s2, s3, s4;
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
        await this.sleep(2000);
        pg = (await this.puppet('https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc', '')));
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

  // https://search.fatcat.wiki/fatcat_release_v03b/_search?q=doi:%2210.1007/s00276-005-0333-8%22
  // that used to work, but they've moved the index now, and it doesn't seem to. Althought the main 
  // ES base is still there - just can't get it to respond without finding the index name. 
  // However, developments on querying the releases gives us a possible solution:
`P.src.fatcat = (doi) ->
doi ?= @params.fatcat ? @params.doi
try
  res = await @fetch 'https://api.fatcat.wiki/v0/release/lookup?expand=files&hide=abstracts,refs&doi=' + doi
  return res
return`;
// is there also a title search? Or only IDs? title= doesn't work. Can explore more later.

// we could index this as we get them if that turns out to be useful
// to begin with, normal caching should be sufficient.
` for example:
10.1088/0264-9381/19/7/380
has a files section, containing:
[
   {
     "release_ids":["3j36alui7fcwncbc4xdaklywb4"],
     "mimetype":"application/pdf",
     "urls":[
       {"url":"http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"web"},
       {"url":"https://web.archive.org/web/20091024040004/http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"webarchive"},
       {"url":"https://web.archive.org/web/20040827040202/http://www.gravity.uwa.edu.au:80/amaldi/papers/Landry.pdf","rel":"webarchive"},
       {"url":"https://web.archive.org/web/20050624182645/http://www.gravity.uwa.edu.au/amaldi/papers/Landry.pdf","rel":"webarchive"},
       {"url":"https://web.archive.org/web/20050601001748/http://www.gravity.uwa.edu.au:80/amaldi/papers/Landry.pdf","rel":"webarchive"}
     ],
     "state":"active"
     ...
   },
   ...
 ]`;


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

`P.src.google.sheets = (opts) ->
  # expects a google sheet ID or a URL to a google sheets feed in json format
  # NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
  opts ?= this?.params ? {}
  opts = {sheetid: opts} if typeof opts is 'string'
  if (opts.sheets? or opts.sheet?) and not opts.sheetid?
    opts.sheetid = opts.sheet ? opts.sheets
    delete opts.sheet
    delete opts.sheets
  values = []
  if not opts.sheetid
    return values
  else if opts.sheetid.indexOf('http') is 0
    url = opts.sheetid
  else
    if opts.sheetid.indexOf('/spreadsheets/d/') isnt -1
      opts.sheetid = opts.sheetid.split('/spreadsheets/d/')[1].split('/')[0] 
    else if opts.sheetid.split('/').length is 2
      [opts.sheetid, opts.sheet] = opts.sheetid.split '/'
    opts.sheet ?= 'default' # or else a number, starting from 1, indicating which sheet in the overall sheet to access
    url = 'https://spreadsheets.google.com/feeds/list/' + opts.sheetid + '/' + opts.sheet + '/public/values?alt=json'

  g = await @fetch url, headers: 'Cache-Control': 'no-cache'
  for l of g.feed.entry
    val = {}
    for k of g.feed.entry[l]
      try val[k.replace('gsx$','')] = g.feed.entry[l][k].$t if k.indexOf('gsx$') is 0 and g.feed.entry[l][k].$t? and g.feed.entry[l][k].$t isnt ''
    keys = @keys val
    values.push(val) if keys.length > 1 or (keys.length and val[keys[0]] not in ['Loading...','#REF!'])

  g = undefined
  return values`;

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
  } else if (opts.sheetid.startsWith('http')) {
    url = opts.sheetid;
  } else {
    if (opts.sheetid.includes('/spreadsheets/')) {
      sid = opts.sheetid.split('/spreadsheets/')[1].split('/')[0];
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
      toprow = g.values.shift(); // NOTE there is NO WAY to identify column headers any more it seems, certainly not from this response format. Just pop them off the values list
      for (i = 0, len = toprow.length; i < len; i++) {
        hd = toprow[i];
        headers.push(hd.toLowerCase().replace(/[^a-z0-9]/g, ''));
      }
    }
    values = [];
    ref6 = g.values;
    for (j = 0, len1 = ref6.length; j < len1; j++) {
      l = ref6[j];
      val = {};
      for (h in headers) {
        try {
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

//P.src.google.sheets._async = true

// https://developers.google.com/hangouts/chat
// NOTE this will need oauth configuration for a full bot. For now just a web hook
// https://developers.google.com/hangouts/chat/how-tos/webhooks	
// pradm dev "pradm alert" google chat webhook
P.src.google.chat = function(params, url) {
  var data, headers, ref, ref1, ref2, ref3, ref4;
  try {
    if (typeof params === 'string') {
      params = {
        text: params
      };
    }
    if (params == null) {
      params = this.params;
    }
    headers = {
      "Content-Type": 'application/json; charset=UTF-8' // any other possible headers?
    };
    data = {
      method: 'POST',
      headers: headers,
      body: {
        text: decodeURIComponent((ref = (ref1 = (ref2 = params.text) != null ? ref2 : params.msg) != null ? ref1 : params.body) != null ? ref : '')
      }
    };
    if (url == null) {
      url = (ref3 = this.S.src.google) != null ? (ref4 = ref3.secrets) != null ? ref4.chat : void 0 : void 0; // should url be allowed on params? doesn't strictly need to be secret, the key and token it uses only work for the webhook
    }
    if (data.body.text && (url != null)) {
      return this.fetch(url, data);
    }
  } catch (error) {}
};

`# docs:
# https://developers.google.com/places/web-service/autocomplete
# example:
# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>


# https://developers.google.com/knowledge-graph/
# https://developers.google.com/knowledge-graph/reference/rest/v1/
API.use.google.knowledge.retrieve = (mid,types) ->
  exists = API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve'
  return exists if exists
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=1&ids=' + mid
  if types
    types = types.join('&types=') if typeof types isnt 'string' # are multiple types done by comma separation or key repetition?
    u += '&types=' + types
  ret = {}
  try
    res = API.http.proxy 'GET', u, true
    ret = res.data.itemListElement[0].result
    ret.score = res.data.itemListElement[0].resultScore
  if not _.isEmpty ret
    API.http.cache {mid:mid,types:types}, 'google_knowledge_retrieve', ret
  return ret

API.use.google.knowledge.search = (qry,limit=10,refresh=604800000) -> # default 7 day cache
  u = 'https://kgsearch.googleapis.com/v1/entities:search?key=' + API.settings.use.google.serverkey + '&limit=' + limit + '&query=' + encodeURIComponent qry
  API.log 'Searching google knowledge for ' + qry

  checksum = API.job.sign qry
  exists = API.http.cache checksum, 'google_knowledge_search', undefined, refresh
  return exists if exists

  res = API.http.proxy('GET',u,true).data
  try API.http.cache checksum, 'google_knowledge_search', res
  return res

API.use.google.knowledge.find = (qry) ->
  res = API.use.google.knowledge.search qry
  try
    return res.itemListElement[0].result #could add an if resultScore > ???
  catch
    return

# https://cloud.google.com/natural-language/docs/getting-started
# https://cloud.google.com/natural-language/docs/basics
API.use.google.cloud.language = (content, actions=['entities','sentiment'], auth) ->
  actions = actions.split(',') if typeof actions is 'string'
  return {} if not content?
  checksum = API.job.sign content, actions
  exists = API.http.cache checksum, 'google_language'
  return exists if exists

  lurl = 'https://language.googleapis.com/v1/documents:analyzeEntities?key=' + API.settings.use.google.serverkey
  document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}
  result = {}
  if 'entities' in actions
    try result.entities = API.http.proxy('POST',lurl,{data:document,headers:{'Content-Type':'application/json'}},true).data.entities
  if 'sentiment' in actions
    try result.sentiment = API.http.proxy('POST',lurl.replace('analyzeEntities','analyzeSentiment'),{data:document,headers:{'Content-Type':'application/json'}},true).data
  API.http.cache(checksum, 'google_language', result) if not _.isEmpty result
  return result

# https://cloud.google.com/translate/docs/quickstart
API.use.google.cloud.translate = (q, source, target='en', format='text') ->
  # ISO source and target language codes
  # https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
  return {} if not q?
  checksum = API.job.sign q, {source: source, target: target, format: format}
  exists = API.http.cache checksum, 'google_translate'
  return exists if exists
  lurl = 'https://translation.googleapis.com/language/translate/v2?key=' + API.settings.use.google.serverkey
  result = API.http.proxy('POST', lurl, {data:{q:q, source:source, target:target, format:format}, headers:{'Content-Type':'application/json'}},true)
  if result?.data?.data?.translations
    res = result.data.data.translations[0].translatedText
    API.http.cache(checksum, 'google_language', res) if res.length
    return res
    #return result.data.data
  else
    return {}

API.use.google.places.autocomplete = (qry,location,radius) ->
  url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=' + qry + '&key=' + API.settings.use.google.serverkey
  url += '&location=' + location + '&radius=' + (radius ? '10000') if location?
  try
    return API.http.proxy('GET',url,true).data
  catch err
  return {status:'error', error: err}

API.use.google.places.place = (id,qry,location,radius) ->
  if not id?
    try
      results = API.use.google.places.autocomplete qry,location,radius
      id = results.predictions[0].place_id
    catch err
      return {status:'error', error: err}
  url = 'https://maps.googleapis.com/maps/api/place/details/json?placeid=' + id + '&key=' + API.settings.use.google.serverkey
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.places.url = (qry) ->
  try
    results = API.use.google.places.place undefined,qry
    return {data: {url:results.result.website.replace('://','______').split('/')[0].replace('______','://')}}
  catch err
    return {status:'error', error: err}

API.use.google.places.nearby = (params={}) ->
  url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?'
  params.key ?= API.settings.use.google.serverkey
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.places.search = (params) ->
  url = 'https://maps.googleapis.com/maps/api/place/textsearch/json?'
  params.key ?= API.settings.use.google.serverkey
  url += (if p is 'q' then 'input' else p) + '=' + params[p] + '&' for p of params
  try
    return API.http.proxy('GET',url,true).data
  catch err
    return {status:'error', error: err}

API.use.google.sheets.api = {}
# https://developers.google.com/sheets/api/reference/rest
API.use.google.sheets.api.get = (sheetid, opts={}) ->
  opts = {stale:opts} if typeof opts is 'number'
  opts.stale ?= 3600000
  opts.key ?= API.settings.use.google.serverkey
  try
    sheetid = sheetid.split('/spreadsheets/d/')[1].split('/')[0] if sheetid.indexOf('/spreadsheets/d/') isnt -1
    url = 'https://sheets.googleapis.com/v4/spreadsheets/' + sheetid
    url += '/values/' + opts.start + ':' + opts.end if opts.start and opts.end
    url += '?key=' + opts.key
    API.log 'Getting google sheet via API ' + url
    g = HTTP.call 'GET', url
    return g.data ? g
  catch err
    return err

# auth for sheets interactions that makes changes is complex, requiring oauth and an email account to be registered to the sheet, it seems
# https://developers.google.com/sheets/api/guides/authorizing
# https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/append
# https://developers.google.com/identity/protocols/oauth2
# https://developers.google.com/sheets/api/quickstart/nodejs#step_3_set_up_the_sample
# https://cloud.google.com/apigee/docs/api-platform/security/oauth/access-tokens
# https://docs.wso2.com/display/IntegrationCloud/Get+Credentials+for+Google+Spreadsheet
# https://help.gooddata.com/doc/en/building-on-gooddata-platform/data-preparation-and-distribution/additional-data-load-reference/data-load-tutorials/load-data-from-google-spreadsheets-via-google-api
# https://isd-soft.com/tech_blog/accessing-google-apis-using-service-account-node-js/
API.use.google.sheets.api.values = (sheetid, opts={}) ->
  opts.start ?= 'A1'
  if not opts.end?
    sheet = if typeof sheetid is 'object' then sheetid else API.use.google.sheets.api.get sheetid, opts
    opts.sheet ?= 0 # could also be the ID or title of a sheet in the sheet... if so iterate them to find the matching one
    rows = sheet.sheets[opts.sheet].properties.gridProperties.rowCount
    cols = sheet.sheets[opts.sheet].properties.gridProperties.columnCount
    opts.end = ''
    ls = Math.floor cols/26
    opts.end += (ls + 9).toString(36).toUpperCase() if ls isnt 0
    opts.end += (cols + 9-ls).toString(36).toUpperCase()
    opts.end += rows
  values = []
  try
    keys = false
    res = API.use.google.sheets.api.get sheetid, opts
    opts.keys ?= 0 # always assume keys? where to tell which row to get them from? 0-indexed or 1-indexed or named?
    keys = opts.keys if Array.isArray opts.keys
    for s in res.values
      if opts.keys? and keys is false
        keys = s
      else
        obj = {}
        for k of keys
          try
            obj[keys[k]] = s[k] if s[k] isnt ''
        values.push(obj) if not _.isEmpty obj
    return values
	`;

// Docs: https://europepmc.org/GristAPI
// Fields you can search by: https://europepmc.org/GristAPI#API

// Example, get info by grant ID: http://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=gid:088130&resultType=core&format=json
// Use case: To get the name of a Principal Investigator, call @src.grist(the_grant_id).data.Person
// Will return {FamilyName: "Friston", GivenName: "Karl", Initials: "KJ", Title: "Prof"}
P.src.grist = async function(qrystr, from) {
  var ref, ref1, res, url;
  // note in Grist API one of the params is resultType, in EPMC REST API the same param is resulttype .
  if (qrystr == null) {
    qrystr = this.params.grist;
  }
  if (qrystr.indexOf('gid:') !== 0 && qrystr.indexOf(' ') === -1 && parseInt(qrystr)) {
    qrystr = 'gid:' + qrystr; // check the qrystr to decide if this should be added or not
  }
  url = 'https://www.ebi.ac.uk/europepmc/GristAPI/rest/get/query=' + encodeURIComponent(qrystr) + '&resultType=core&format=json';
  if (from != null) {
    url += '&page=' + (Math.floor(from / 25) + 1);
  }
  res = (await this.fetch(url));
  return {
    total: res.HitCount,
    data: (ref = (ref1 = res.RecordList) != null ? ref1.Record : void 0) != null ? ref : {}
  };
};

var base;

if ((base = S.src).microsoft == null) {
  base.microsoft = {};
}

try {
  S.src.microsoft.secrets = JSON.parse(SECRETS_MICROSOFT);
} catch (error) {}

P.src.microsoft = {};

// https://docs.microsoft.com/en-gb/rest/api/cognitiveservices/bing-web-api-v7-reference#endpoints
// annoyingly Bing search API does not provide exactly the same results as the actual Bing UI.
// and it seems the bing UI is sometimes more accurate
P.src.microsoft.bing = async function(q, key) {
  var ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, res, url;
  if (q == null) {
    q = (ref = (ref1 = this != null ? (ref2 = this.params) != null ? ref2.bing : void 0 : void 0) != null ? ref1 : this != null ? (ref3 = this.params) != null ? ref3.q : void 0 : void 0) != null ? ref : this != null ? (ref4 = this.params) != null ? ref4.query : void 0 : void 0;
  }
  if (key == null) {
    key = (ref5 = S.src.microsoft) != null ? (ref6 = ref5.secrets) != null ? (ref7 = ref6.bing) != null ? ref7.key : void 0 : void 0 : void 0;
  }
  url = 'https://api.cognitive.microsoft.com/bing/v7.0/search?mkt=en-GB&count=20&q=' + q;
  res = (await this.fetch(url, {
    headers: {
      'Ocp-Apim-Subscription-Key': key
    },
    cache: 259200 // cache for 3 days
  }));
  if (res != null ? (ref8 = res.webPages) != null ? ref8.value : void 0 : void 0) {
    return {
      total: res.data.webPages.totalEstimatedMatches,
      data: res.data.webPages.value
    };
  } else {
    return {
      total: 0,
      data: []
    };
  }
};

P.src.microsoft.graph = {
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 9
    }
  }
};

P.src.microsoft.graph.journal = {
  _prefix: false,
  _index: true
};

P.src.microsoft.graph.author = {
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 9
    }
  }
};

P.src.microsoft.graph.affiliation = {
  _prefix: false,
  _index: true
};

P.src.microsoft.graph.urls = {
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 6
    }
  }
};

P.src.microsoft.graph.abstract = {
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 6
    }
  }
};

P.src.microsoft.graph.relation = {
  _prefix: false,
  _index: {
    settings: {
      number_of_shards: 12
    }
  }
};

P.src.microsoft.graph.paper = async function(q) { // can be a search or a record to get urls and relations for
  var base1, base2, i, j, k, len, len1, len2, puo, r, ref, ref1, ref2, ref3, ref4, ref5, ref6, res, rr, rres, ur, url_source_types, urlres;
  url_source_types = { // defined by MAG
    '1': 'html',
    '2': 'text',
    '3': 'pdf',
    '4': 'doc',
    '5': 'ppt',
    '6': 'xls',
    '8': 'rtf',
    '12': 'xml',
    '13': 'rss',
    '20': 'swf',
    '27': 'ics',
    '31': 'pub',
    '33': 'ods',
    '34': 'odp',
    '35': 'odt',
    '36': 'zip',
    '40': 'mp3'
  };
  if (this.params.title && !q) {
    return this.src.microsoft.graph.paper.title();
  }
  q = (ref = (ref1 = this.params.q) != null ? ref1 : this.params.paper) != null ? ref : this.params;
  res = typeof q === 'object' && q.PaperId && q.Rank ? q : (await this.src.microsoft.graph(q));
  ref4 = (ref2 = res != null ? (ref3 = res.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : (res ? [res] : []);
  for (i = 0, len = ref4.length; i < len; i++) {
    r = ref4[i];
    try {
      //if ma = await @src.microsoft.graph.abstract r._source.PaperId, 1
      //  r._source.abstract = ma
      urlres = (await this.src.microsoft.graph.urls('PaperId:"' + r._source.PaperId + '"')); // don't bother for-looping these because result size should be low, and saves on creating and deleting a scrol context for every one
      ref5 = urlres.hits.hits;
      for (j = 0, len1 = ref5.length; j < len1; j++) {
        ur = ref5[j];
        if ((base1 = r._source).url == null) {
          base1.url = [];
        }
        puo = {
          url: ur._source.SourceUrl,
          language: ur._source.LanguageCode
        };
        try {
          puo.type = url_source_types[ur._source.SourceType.toString()];
        } catch (error) {}
        r._source.url.push(puo);
      }
    } catch (error) {}
    try {
      rres = (await this.src.microsoft.graph.relation('PaperId:"' + r._source.PaperId + '"', 100)); // 100 authors should be enough...
      ref6 = rres.hits.hits;
      for (k = 0, len2 = ref6.length; k < len2; k++) {
        rr = ref6[k];
        if (rr._source.AuthorId) { // which it seems they all do, along with OriginalAuthor and OriginalAffiliation
          if ((base2 = r._source).author == null) {
            base2.author = [];
          }
          r._source.author.push({
            name: rr._source.OriginalAuthor,
            sequence: rr._source.AuthorSequenceNumber,
            id: rr._source.AuthorId,
            affiliation: {
              name: rr._source.OriginalAffiliation,
              id: rr._source.AffiliationId
            }
          });
        }
      }
    } catch (error) {}
  }
  return res;
};

P.src.microsoft.graph.title = async function(q) {
  var longest, lvs, ref, ref1, ref2, ref3, res, rt, title;
  if (q == null) {
    q = (ref = this.params.title) != null ? ref : this.params.q;
  }
  if (typeof q === 'string') {
    title = q.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim(); // MAG PaperTitle is lowercased. OriginalTitle isnt
    res = (await this.src.microsoft.graph('PaperTitle:"' + title + '"', 1));
    if (res != null ? (ref1 = res.hits) != null ? ref1.hits : void 0 : void 0) {
      res = (ref2 = res.hits.hits[0]) != null ? ref2._source : void 0;
    }
    if (res != null ? res.PaperTitle : void 0) {
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
      if (typeof (this != null ? (ref3 = this.tdm) != null ? ref3.levenshtein : void 0 : void 0) === 'function') {
        lvs = (await this.tdm.levenshtein(title, rt, false));
        longest = lvs.length.a > lvs.length.b ? lvs.length.a : lvs.length.b;
        if (lvs.distance < 2 || longest / lvs.distance > 10) {
          return this.src.microsoft.graph.paper(res);
        }
      } else if (title.length < (rt.length * 1.2) && (title.length > rt.length * .8)) {
        return this.src.microsoft.graph.paper(res);
      }
    }
  }
};

var base;

if ((base = S.src).oadoi == null) {
  base.oadoi = {};
}

try {
  S.src.oadoi = JSON.parse(SECRETS_OADOI);
} catch (error) {}

P.src.oadoi = async function(doi) {
  var ref, ref1, ref2, url;
  if (doi == null) {
    doi = (ref = (ref1 = this.params) != null ? ref1.oadoi : void 0) != null ? ref : (ref2 = this.params) != null ? ref2.doi : void 0;
  }
  if (typeof doi === 'string' && doi.startsWith('10.')) {
    await this.sleep(900);
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to;
    return this.fetch(url);
  } else {

  }
};

P.src.oadoi._index = {
  settings: {
    number_of_shards: 9
  }
};

P.src.oadoi._key = 'doi';

P.src.oadoi._prefix = false;

P.src.oadoi.hybrid = async function(issns) {
  var closed, hybrid, q, ref, ref1, ref2;
  // there is a concern OADOI sometimes says a journal is closed on a particular 
  // record when it is actually a hybrid. So check if at least 1% of records for 
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
    q = 'journal_issns:"' + issns.join('" OR journals_issns:"') + '"';
    closed = (await this.src.oadoi.count(q + ' AND oa_status:"closed"'));
    if (q.includes(' OR ')) {
      q = '(' + q + ')';
    }
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

P.src.pubmed.pmc = async function(pmc) {
  var found;
  if (pmc == null) {
    pmc = this.params.pmc;
  }
  if (pmc && (found = (await this.src.pubmed('identifier.pmc:"PMC' + pmc.toString().toLowerCase().replace('pmc', '') + '"', 1)))) {
    return found;
  }
};

P.src.pubmed.entrez = {};

P.src.pubmed.entrez.summary = async function(qk, webenv, id) {
  var frec, i, ii, j, k, len, len1, len2, md, rec, recs, ref1, ref2, ref3, res, si, sio, url;
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
    res = (await this.fetch(url));
    md = (await this.convert.xml2json(res));
    recs = [];
    ref1 = md.eSummaryResult.DocSum;
    for (i = 0, len = ref1.length; i < len; i++) {
      rec = ref1[i];
      frec = {
        id: rec.Id[0]
      };
      ref2 = rec.Item;
      for (j = 0, len1 = ref2.length; j < len1; j++) {
        ii = ref2[j];
        if (ii.$.Type === 'List') {
          frec[ii.$.Name] = [];
          if (ii.Item != null) {
            ref3 = ii.Item;
            for (k = 0, len2 = ref3.length; k < len2; k++) {
              si = ref3[k];
              sio = {};
              sio[si.$.Name] = si._;
              frec[ii.$.Name].push(sio);
            }
          }
        } else {
          frec[ii.$.Name] = ii._;
        }
      }
      recs.push(frec);
      if ((id == null) || id.indexOf(',') === -1) {
        return recs[0];
        break;
      }
    }
    return recs;
  } catch (error) {

  }
};

P.src.pubmed.entrez.pmid = async function(pmid) {
  var res, result, url;
  url = 'https://eutils.ncbi.nlm.nih.gov/entrez/eutils/epost.fcgi?db=pubmed&id=' + pmid;
  try {
    res = (await this.fetch(url));
    result = (await this.convert.xml2json(res));
    return this.src.pubmed.entrez.summary(result.ePostResult.QueryKey[0], result.ePostResult.WebEnv[0]);
  } catch (error) {

  }
};

P.src.pubmed.search = async function(str, full, size = 10, ids = false) {
  var i, id, j, k, l, len, len1, len2, len3, pg, rec, ref1, ref2, res, result, uid, url, urlids;
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
        pg = (await this.src.pubmed.pmid(uid)); // should rate limit this to 300ms
        res.data.push(pg);
        if (res.data.length === size) {
          break;
        }
      }
    } else {
      urlids = [];
      for (j = 0, len1 = ids.length; j < len1; j++) {
        id = ids[j];
        if (res.data.length === size) {
          break;
        }
        urlids.push(id);
        if (urlids.length === 40) {
          ref1 = (await this.src.pubmed.entrez.summary(void 0, void 0, urlids));
          for (k = 0, len2 = ref1.length; k < len2; k++) {
            rec = ref1[k];
            res.data.push((await this.src.pubmed.format(rec)));
            if (res.data.length === size) {
              break;
            }
          }
          urlids = [];
        }
      }
      if (urlids.length) {
        ref2 = (await this.src.pubmed.entrez.summary(void 0, void 0, urlids));
        for (l = 0, len3 = ref2.length; l < len3; l++) {
          rec = ref2[l];
          res.data.push((await this.src.pubmed.format(rec)));
          if (res.data.length === size) {
            break;
          }
        }
      }
    }
    return res;
  } catch (error) {

  }
};

P.src.pubmed.pmid = async function(pmid) {
  var res, url;
  try {
    url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml';
    res = (await this.fetch(url));
    if (res.indexOf('<') === 0) {
      return this.src.pubmed.format((await this.decode(res.split('<pre>')[1].split('</pre>')[0].replace('\n', ''))));
    }
  } catch (error) {}
  try {
    return this.src.pubmed.format((await this.src.pubmed.entrez.pmid(pmid)));
  } catch (error) {}
};

P.src.pubmed.aheadofprint = async function(pmid) {
  var res;
  try {
    res = (await this.fetch('https://www.ncbi.nlm.nih.gov/pubmed/' + pmid + '?report=xml'));
    return res.indexOf('PublicationStatus&gt;aheadofprint&lt;/PublicationStatus') !== -1;
  } catch (error) {

  }
};

P.src.pubmed.format = async function(rec, metadata = {}) {
  var a, ai, an, ar, frec, i, ii, j, k, l, len, len1, len2, len3, len4, len5, len6, len7, m, mc, n, o, p, pd, pid, q, rc, ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rf, si, sio;
  if (typeof rec === 'string' && rec.indexOf('<') === 0) {
    rec = (await this.convert.xml2json(rec));
  }
  if ((((ref1 = rec.eSummaryResult) != null ? ref1.DocSum : void 0) != null) || rec.ArticleIds) {
    frec = {};
    if (((ref2 = rec.eSummaryResult) != null ? ref2.DocSum : void 0) != null) {
      rec = md.eSummaryResult.DocSum[0];
      ref3 = rec.Item;
      for (i = 0, len = ref3.length; i < len; i++) {
        ii = ref3[i];
        if (ii.$.Type === 'List') {
          frec[ii.$.Name] = [];
          if (ii.Item != null) {
            ref4 = ii.Item;
            for (j = 0, len1 = ref4.length; j < len1; j++) {
              si = ref4[j];
              sio = {};
              sio[si.$.Name] = si._;
              frec[ii.$.Name].push(sio);
            }
          }
        } else {
          frec[ii.$.Name] = ii._;
        }
      }
    } else {
      frec = rec;
    }
    try {
      if (metadata.pmid == null) {
        metadata.pmid = rec.Id[0];
      }
    } catch (error) {}
    try {
      if (metadata.pmid == null) {
        metadata.pmid = rec.id;
      }
    } catch (error) {}
    try {
      if (metadata.title == null) {
        metadata.title = frec.Title;
      }
    } catch (error) {}
    try {
      if (metadata.issn == null) {
        metadata.issn = frec.ISSN;
      }
    } catch (error) {}
    try {
      if (metadata.essn == null) {
        metadata.essn = frec.ESSN;
      }
    } catch (error) {}
    try {
      if (metadata.doi == null) {
        metadata.doi = frec.DOI;
      }
    } catch (error) {}
    try {
      if (metadata.journal == null) {
        metadata.journal = frec.FullJournalName;
      }
    } catch (error) {}
    try {
      if (metadata.journal_short == null) {
        metadata.journal_short = frec.Source;
      }
    } catch (error) {}
    try {
      if (metadata.volume == null) {
        metadata.volume = frec.Volume;
      }
    } catch (error) {}
    try {
      if (metadata.issue == null) {
        metadata.issue = frec.Issue;
      }
    } catch (error) {}
    try {
      if (metadata.page == null) {
        metadata.page = frec.Pages; //like 13-29 how to handle this
      }
    } catch (error) {}
    try {
      if (metadata.year == null) {
        metadata.year = frec[frec.PubDate ? 'PubDate' : 'EPubDate'].split(' ')[0];
      }
    } catch (error) {}
    try {
      p = frec[frec.PubDate ? 'PubDate' : 'EPubDate'].split(' ');
      if (metadata.published == null) {
        metadata.published = p[0] + '-' + (['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf(p[1].toLowerCase()) + 1) + '-' + (p.length === 3 ? p[2] : '01');
      }
    } catch (error) {}
    if (frec.AuthorList != null) {
      if (metadata.author == null) {
        metadata.author = [];
      }
      ref5 = frec.AuthorList;
      for (k = 0, len2 = ref5.length; k < len2; k++) {
        a = ref5[k];
        try {
          a.family = a.Author.split(' ')[0];
          a.given = a.Author.replace(a.family + ' ', '');
          a.name = a.given + ' ' + a.family;
          metadata.author.push(a);
        } catch (error) {}
      }
    }
    if ((frec.ArticleIds != null) && (metadata.pmcid == null)) {
      ref6 = frec.ArticleIds;
      for (l = 0, len3 = ref6.length; l < len3; l++) {
        ai = ref6[l];
        if (ai.pmc) { // pmcid or pmc? replace PMC in the value? it will be present
          if (metadata.pmcid == null) {
            metadata.pmcid = ai.pmc;
          }
          break;
        }
      }
    }
  } else if (rec.PubmedArticle != null) {
    rec = rec.PubmedArticle;
    mc = rec.MedlineCitation[0];
    try {
      if (metadata.pmid == null) {
        metadata.pmid = mc.PMID[0]._;
      }
    } catch (error) {}
    try {
      if (metadata.title == null) {
        metadata.title = mc.Article[0].ArticleTitle[0];
      }
    } catch (error) {}
    try {
      if (metadata.issn == null) {
        metadata.issn = mc.Article[0].Journal[0].ISSN[0]._;
      }
    } catch (error) {}
    try {
      if (metadata.journal == null) {
        metadata.journal = mc.Article[0].Journal[0].Title[0];
      }
    } catch (error) {}
    try {
      if (metadata.journal_short == null) {
        metadata.journal_short = mc.Article[0].Journal[0].ISOAbbreviation[0];
      }
    } catch (error) {}
    try {
      pd = mc.Article[0].Journal[0].JournalIssue[0].PubDate[0];
      try {
        if (metadata.year == null) {
          metadata.year = pd.Year[0];
        }
      } catch (error) {}
      try {
        if (metadata.published == null) {
          metadata.published = pd.Year[0] + '-' + (pd.Month ? ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf(pd.Month[0].toLowerCase()) + 1 : '01') + '-' + (pd.Day ? pd.Day[0] : '01');
        }
      } catch (error) {}
    } catch (error) {}
    try {
      if (metadata.author == null) {
        metadata.author = [];
      }
      ref7 = mc.Article[0].AuthorList[0].Author;
      for (m = 0, len4 = ref7.length; m < len4; m++) {
        ar = ref7[m];
        a = {};
        a.family = ar.LastName[0];
        a.given = ar.ForeName[0];
        a.name = (a.given ? a.given + ' ' : '') + ((ref8 = a.family) != null ? ref8 : '');
        try {
          a.affiliation = ar.AffiliationInfo[0].Affiliation[0];
        } catch (error) {}
        if (a.affiliation != null) {
          if (Array.isArray(a.affiliation)) {
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
    try {
      ref9 = rec.PubmedData[0].ArticleIdList[0].ArticleId;
      for (n = 0, len5 = ref9.length; n < len5; n++) {
        pid = ref9[n];
        if (pid.$.IdType === 'doi') {
          if (metadata.doi == null) {
            metadata.doi = pid._;
          }
          break;
        }
      }
    } catch (error) {}
    try {
      if (metadata.reference == null) {
        metadata.reference = [];
      }
      ref10 = rec.PubmedData[0].ReferenceList[0].Reference;
      for (o = 0, len6 = ref10.length; o < len6; o++) {
        ref = ref10[o];
        rc = ref.Citation[0];
        rf = {};
        if (rc.indexOf('doi.org/') !== -1) {
          rf.doi = rc.split('doi.org/')[1].trim();
        }
        try {
          rf.author = [];
          ref11 = rc.split('. ')[0].split(', ');
          for (q = 0, len7 = ref11.length; q < len7; q++) {
            an = ref11[q];
            rf.author.push({
              name: an
            });
          }
        } catch (error) {}
        try {
          rf.title = rc.split('. ')[1].split('?')[0].trim();
        } catch (error) {}
        try {
          rf.journal = rc.replace(/\?/g, '.').split('. ')[2].trim();
        } catch (error) {}
        try {
          rf.url = 'http' + rc.split('http')[1].split(' ')[0];
          if (rf.url.indexOf('doi.org') !== -1) {
            delete rf.url;
          }
        } catch (error) {}
        if (JSON.stringify(rf) !== '{}') {
          metadata.reference.push(rf);
        }
      }
    } catch (error) {}
  }
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
  return metadata;
};

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

try {
  S.src.sherpa = JSON.parse(SECRETS_SHERPA);
} catch (error) {}

P.src.sherpa = {};

P.src.sherpa.opendoar = {
  _index: true,
  _prefix: false
};

// https://v2.sherpa.ac.uk/api/object-retrieval.html
P.src.sherpa.opendoar.import = async function() {
  var counter, i, len, offset, rec, recs, ref, res;
  await this.src.sherpa.opendoar('');
  recs = [];
  counter = 0;
  offset = 0;
  while (res = (await this.fetch('https://v2.sherpa.ac.uk/cgi/retrieve?api-key=' + this.S.src.sherpa.apikey + '&item-type=repository&format=Json&offset=' + offset))) {
    if (((typeof res !== "undefined" && res !== null ? res.items : void 0) == null) || !res.items.length) {
      break;
    }
    console.log(offset, counter, res.items.length);
    offset += 100; // opendoar returns 100 at a time by default, and that is also the max
    ref = res.items;
    for (i = 0, len = ref.length; i < len; i++) {
      rec = ref[i];
      counter += 1;
      recs.push(rec);
      if (recs.length === 10000) {
        await this.src.sherpa.opendoar(recs);
        recs = [];
      }
    }
  }
  if (recs.length) {
    await this.src.sherpa.opendoar(recs);
  }
  return counter;
};

P.src.sherpa.opendoar.import._hide = true;

P.src.sherpa.opendoar.import._async = true;

var _got_props,
  indexOf = [].indexOf;

P.src.wikidata = async function(qid) {
  var i, len, q, recs, ref, ref1, res, t, w;
  if (qid == null) {
    qid = (ref = (ref1 = this.params.wikidata) != null ? ref1 : this.params.url) != null ? ref : this.params.wikipedia;
  }
  if (typeof qid === 'string') {
    if (qid.includes('wiki/')) {
      t = qid.split('wiki/').pop();
      qid = void 0;
      try {
        w = (await this.src.wikipedia.lookup({
          title: t
        }));
        qid = w.data.pageprops.wikibase_item;
      } catch (error) {}
    }
    if (qid) {
      res = (await this.fetch('https://www.wikidata.org/wiki/Special:EntityData/' + qid + '.json'));
      qid = res.entities[qid];
    }
  }
  if (Array.isArray(qid)) {
    recs = [];
    for (i = 0, len = qid.length; i < len; i++) {
      q = qid[i];
      recs.push((await this.src.wikidata._format(q)));
    }
    return recs;
  } else if (typeof qid === 'object') {
    return this.src.wikidata._format(qid);
  } else {

  }
};

P.src.wikidata._index = {
  settings: {
    number_of_shards: 9
  }
};

P.src.wikidata._prefix = false;

P.src.wikidata._format = async function(rec) {
  var al, als, ds, i, j, k, l, len, len1, len2, len3, len4, m, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, s, sl, sn, sw;
  //rec.type = rec.type # was this meant to come from somewhere else
  rec._id = rec.id;
  rec.qid = rec.id;
  rec.createdAt = Date.now();
  rec.label = (ref = rec.labels) != null ? (ref1 = ref.en) != null ? ref1.value : void 0 : void 0; // is an english label required?
  delete rec.labels;
  sl = {};
  ref3 = (ref2 = rec.sitelinks) != null ? ref2 : [];
  for (i = 0, len = ref3.length; i < len; i++) {
    sw = ref3[i];
    if (indexOf.call(sw, 'enwiki') >= 0) {
      sl[sw] = rec.sitelinks[sw];
    }
  }
  rec.sitelinks = sl;
  rec.description = (ref4 = rec.descriptions) != null ? (ref5 = ref4.en) != null ? ref5.value : void 0 : void 0;
  delete rec.descriptions;
  rec.alias = [];
  ref7 = (ref6 = rec.aliases) != null ? ref6 : [];
  for (j = 0, len1 = ref7.length; j < len1; j++) {
    als = ref7[j];
    ref8 = rec.aliases[als];
    for (k = 0, len2 = ref8.length; k < len2; k++) {
      al = ref8[k];
      rec.alias.push(al);
    }
  }
  delete rec.aliases;
  rec.snaks = [];
  ref10 = (ref9 = rec.claims) != null ? ref9 : [];
  for (l = 0, len3 = ref10.length; l < len3; l++) {
    s = ref10[l];
    ref11 = rec.claims[s];
    for (m = 0, len4 = ref11.length; m < len4; m++) {
      sn = ref11[m];
      ds = (await this.src.wikidata.desnak(sn.mainsnak));
      if (JSON.stringify(ds) !== '{}') {
        rec.snaks.push(ds);
      }
      if (rec.image == null) {
        rec.image = ds.imgurl;
      }
    }
  }
  delete rec.claims;
  try {
    rec.wikipedia = (ref12 = (ref13 = rec.sitelinks) != null ? (ref14 = ref13.enwiki) != null ? ref14.url : void 0 : void 0) != null ? ref12 : 'https://en.wikipedia.org/wiki/' + rec.sitelinks.enwiki.title.replace(/ /g, '_');
  } catch (error) {}
  try {
    rec.wid = (ref15 = rec.sitelinks) != null ? (ref16 = ref15.enwiki) != null ? ref16.url.split('wiki/').pop() : void 0 : void 0;
  } catch (error) {}
  return rec;
};

P.src.wikidata.desnak = async function(ms) {
  var ansk, i, img, j, k, l, len, len1, len2, len3, len4, len5, len6, m, mds, n, o, q, qk, r, ref, ref1, ref10, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, sk, skid, snak;
  if (ms == null) {
    ms = this.params;
  }
  if (typeof ms !== 'object' || (((ref = ms.datavalue) != null ? ref.value : void 0) == null)) {
    return {};
  }
  snak = {
    qualifiers: [],
    references: [],
    property: ms.property // like PS30
  };
  try {
    snak['key'] = ((await this.src.wikidata.property(snak.property))).label;
  } catch (error) {}
  if (typeof ms.datavalue.value !== 'object') {
    snak.value = ms.datavalue.value; // an actual value
    if (ms.datatype === 'url') {
      snak.url = snak.value;
    }
  } else if (ms.datavalue.value.latitude) {
    snak.location = {
      latitude: ms.datavalue.value.latitude,
      longitude: ms.datavalue.value.longitude,
      precision: ms.datavalue.value.precision
    };
    snak.value = snak.location.latitude + (snak.location.longitude ? ',' + snak.location.longitude : '');
    if (ms.datavalue.value.globe != null) {
      snak.globe = ms.datavalue.value.globe.split('/').pop(); // like Q2 is earth, could be dereferenced later
    }
  } else if (ms.datavalue.value.amount) {
    ref1 = ['amount', 'upperBound', 'lowerBound'];
    for (i = 0, len = ref1.length; i < len; i++) {
      sk = ref1[i];
      snak[sk] = ms.datavalue.value[sk].toString();
    }
    snak.value = snak.amount;
    if (ms.datavalue.value.unit) { // like Q712226 is square kilometer, later deref
      snak.unit = ms.datavalue.value.unit.split('/').pop();
    }
  } else if (ms.datavalue.value.time) {
    ref2 = ['time', 'timezone', 'before', 'after', 'precision'];
    for (j = 0, len1 = ref2.length; j < len1; j++) {
      sk = ref2[j];
      snak[sk] = ms.datavalue.value[sk].toString();
    }
    snak.value = snak.time;
  } else if (ms.datavalue.value.id) {
    snak.qid = ms.datavalue.value.id; // like Q32, so needs later dereference and value set in snak.value (it would take too long and may run before the record to dereference exists anyway)
  }
  ref4 = (ref3 = ms.qualifiers) != null ? ref3 : [];
  //try
  //  v = await @src.wikidata snak.qid
  //  snak.value = v?.label
  for (k = 0, len2 = ref4.length; k < len2; k++) {
    q = ref4[k];
    ref5 = ms.qualifiers[q];
    for (l = 0, len3 = ref5.length; l < len3; l++) {
      qk = ref5[l];
      snak.qualifiers.push((await this.src.wikidata.desnak(qk)));
    }
  }
  ref7 = (ref6 = ms.references) != null ? ref6 : [];
  for (m = 0, len4 = ref7.length; m < len4; m++) {
    r = ref7[m];
    ref8 = r['snaks-order'];
    for (n = 0, len5 = ref8.length; n < len5; n++) {
      skid = ref8[n];
      ref9 = r.snaks[skid];
      for (o = 0, len6 = ref9.length; o < len6; o++) {
        ansk = ref9[o];
        snak.references.push((await this.src.wikidata.desnak(ansk)));
      }
    }
  }
  if (snak.key === 'image' || (typeof snak.value === 'string' && ((ref10 = snak.value.toLowerCase().split('.').pop()) === 'bmp' || ref10 === 'gif' || ref10 === 'jpg' || ref10 === 'jpeg' || ref10 === 'png' || ref10 === 'svg' || ref10 === 'tif' || ref10 === 'webp'))) {
    if (snak.value.startsWith('http')) {
      snak.imgurl = snak.value;
    } else {
      snak.imgurl = 'https://upload.wikimedia.org/wikipedia/commons/';
      img = snak.value.replace(/\s/g, '_');
      mds = crypto.createHash('md5').update(img, 'utf8').digest('hex'); // base64
      snak.imgurl += mds.charAt(0) + '/' + mds.charAt(0) + mds.charAt(1) + '/' + encodeURIComponent(img);
    }
  }
  if (!snak.value && !snak.qid) {
    return {};
  } else {
    return snak;
  }
};

_got_props = {};

P.src.wikidata.properties = async function() {
  var content, i, len, parts, prop, row, rows, tb;
  if (!this.refresh && JSON.stringify(_got_props) !== '{}') {
    return _got_props;
  } else {
    _got_props = {};
    try {
      if (content = (await this.fetch('https://www.wikidata.org/wiki/Wikidata:Database_reports/List_of_properties/all'))) {
        tb = content.split('<table class="wikitable sortable">')[1].split('</table>')[0];
        rows = tb.split('</tr>');
        rows.shift(); // the first row is headers
        for (i = 0, len = rows.length; i < len; i++) {
          row = rows[i];
          try {
            prop = {};
            parts = row.split('</td>');
            try {
              prop.pid = parts[0].replace('</a>', '').split('>').pop().trim().replace('\n', '');
            } catch (error) {}
            try {
              prop.label = parts[1].replace('</a>', '').split('>').pop().trim().replace('\n', '');
            } catch (error) {}
            try {
              prop.desc = parts[2].replace('</a>', '').split('>').pop().trim().replace('\n', '');
            } catch (error) {}
            try {
              prop.alias = parts[3].replace('</a>', '').split('>').pop().replace(/, or/g, ',').replace(/, /g, ',').trim().replace('\n', '').split(',');
            } catch (error) {}
            try {
              prop.type = parts[4].replace('</a>', '').split('>').pop().trim().replace('\n', '');
            } catch (error) {}
            try {
              prop.count = parts[5].replace('</a>', '').split('>').pop().replace(/,/g, '').trim().replace('\n', '');
            } catch (error) {}
            if (typeof prop.pid === 'string' && prop.pid.length && prop.pid.startsWith('P')) {
              _got_props[prop.pid] = prop;
            }
          } catch (error) {}
        }
      }
    } catch (error) {}
    return _got_props;
  }
};

P.src.wikidata.property = async function(prop) {
  var firsts, p, partials, pls, props, q, qf;
  if (prop == null) {
    prop = this.params.property;
  }
  if (typeof prop !== 'string') {
    return void 0;
  }
  props = (await this.src.wikidata.properties());
  if (props[prop]) {
    return props[prop];
  } else {
    q = prop.toLowerCase();
    qf = q.split(' ')[0];
    partials = [];
    firsts = [];
    for (p in props) {
      pls = props[p].label.toLowerCase();
      if (pls === q) {
        return props[p];
      } else if (pls.indexOf(q) !== -1) {
        partials.push(props[p]);
      } else if (pls.indexOf(qf) !== -1) {
        firsts.push(props[p]);
      }
    }
    return partials.concat(firsts);
  }
};

P.src.wikidata.property.terms = async function(prop, size = 100, counts = true, alphabetical = false) {
  var i, j, key, len, len1, loops, lp, max, out, qr, qv, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, res, snak, sz, t, terms;
  if (prop == null) {
    prop = (ref = this.params.terms) != null ? ref : this.params.property;
  }
  terms = {};
  loops = false;
  key = false;
  max = 0;
  lp = 0;
  sz = size < 1000 ? size : 1000;
  qr = 'snaks.property.exact:' + prop;
  while (this.keys(terms).length < size && (loops === false || lp < loops)) {
    res = (await this.src.wikidata({
      q: qr,
      size: sz,
      from: sz * lp
    }));
    if ((res != null ? (ref1 = res.hits) != null ? ref1.total : void 0 : void 0) != null) {
      max = res.hits.total;
    }
    loops = (res != null ? (ref2 = res.hits) != null ? ref2.total : void 0 : void 0) == null ? 0 : Math.floor(res.hits.total / sz);
    ref5 = (ref3 = res != null ? (ref4 = res.hits) != null ? ref4.hits : void 0 : void 0) != null ? ref3 : [];
    for (i = 0, len = ref5.length; i < len; i++) {
      rec = ref5[i];
      ref8 = (ref6 = (ref7 = rec._source) != null ? ref7.snaks : void 0) != null ? ref6 : [];
      for (j = 0, len1 = ref8.length; j < len1; j++) {
        snak = ref8[j];
        if (snak.property === prop) {
          if ((snak.key != null) && key === false) {
            key = snak.key;
          }
          if ((snak.value == null) && (snak.qid != null)) {
            qv = (await this.src.wikidata(snak.qid));
            if (qv != null) {
              snak.value = qv.label;
            }
          }
          if (snak.value != null) {
            if (terms[snak.value] == null) {
              terms[snak.value] = 0;
              if ((snak.qid != null) && qr.split('AND NOT').length < 100) { //what is max amount of NOT terms?
                qr += ' AND NOT snaks.qid.exact:' + snak.qid;
              }
            }
            terms[snak.value] += 1;
          }
        }
      }
    }
    lp += 1;
  }
  out = [];
  for (t in terms) {
    out.push({
      term: t,
      count: terms[t]
    });
  }
  if (alphabetical) {
    out = out.sort(function(a, b) {
      if (a.term.toLowerCase().replace(/ /g, '') > b.term.toLowerCase().replace(/ /g, '')) {
        return 1;
      } else {
        return -1;
      }
    });
  } else {
    out = out.sort(function(a, b) {
      if (b.count > a.count) {
        return 1;
      } else {
        return -1;
      }
    });
  }
  if (counts) {
    return {
      property: key,
      total: max,
      terms: out
    };
  } else {
    return out.map(x(() => {
      return x.term;
    }));
  }
};

P.src.wikidata._flatten = async function(rec) {
  var c, i, len, ref, res;
  res = {};
  ref = rec.snaks;
  for (i = 0, len = ref.length; i < len; i++) {
    c = ref[i];
    if (!c.value && c.qid) {
      c.value = ((await this.src.wikidata(_c.qid))).label;
    }
    if (!c.value && c.property) {
      c.value = ((await this.src.wikidata.property(c))).label;
    }
    if (res[c.key]) {
      if (!Array.isArray(res[c.key])) {
        res[c.key] = [res[c.key]];
      }
      res[c.key].push(c.value);
    } else {
      res[c.key] = c.value;
    }
  }
  return res;
};

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
  var url;
  // it does have sort but does not seem to parse direction yet, so not much use sorting on publication_date
  // does not seem to do paging or cursors yet either - but size works
  if (q == null) {
    q = this.params;
  }
  if (dev == null) {
    dev = this.params.dev;
  }
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/records?size=' + size + '&q=' + q; // just do simple string queries for now
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

P.src.zenodo.records.format = async function(rec) {
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
    metadata.abstract = (await this.convert.html2txt(rec.metadata.description));
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
  var base, data, ref, ref1, ref2, ref3, rs, url;
  // https://zenodo.org/dev#restapi-rep-meta
  if (dev == null) {
    dev = this.params.dev;
  }
  if (token == null) {
    token = this.params.token;
  }
  if (token == null) {
    token = this.S.dev || dev ? (ref = this.S.src) != null ? (ref1 = ref.zenodo) != null ? ref1.sandbox : void 0 : void 0 : (ref2 = this.S.src) != null ? (ref3 = ref2.zenodo) != null ? ref3.token : void 0 : void 0;
  }
  if (metadata == null) {
    metadata = this.params.metadata; // or try to retrieve from oaworks.metadata?
  }
  if ((token == null) || (metadata == null) || (metadata.title == null) || (metadata.description == null)) {
    return false;
  }
  url = 'https://' + (this.S.dev || dev ? 'sandbox.' : '') + 'zenodo.org/api/deposit/depositions?access_token=' + token;
  data = {
    metadata: metadata
  };
  if (!data.metadata.upload_type) {
    data.metadata.upload_type = 'publication';
    data.metadata.publication_type = 'article';
  }
  // required field, will blank list work? If not, need object with name: Surname, name(s) and optional affiliation and creator
  if ((base = data.metadata).creators == null) {
    base.creators = [
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
      rs.uploaded = (await this.src.zenodo.deposition.upload(rs.id, up.content, up.file, up.name, up.url, token));
    }
    if (up.publish) {
      rs.published = (await this.src.zenodo.deposition.publish(rs.id, token));
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

P.src.zenodo.deposition.upload = async function(id, content, file, name, url, token, dev) {
  var ref, ref1, ref2, ref3;
  if (id == null) {
    id = (ref = this.params.upload) != null ? ref : this.params.id;
  }
  if (content == null) {
    content = this.params.content;
  }
  if (name == null) {
    name = this.params.name;
  }
  if (!content && !file) {
    try {
      file = this.request.files[0];
    } catch (error) {}
  }
  if (url && !content && !file) {
    try {
      content = (await this.fetch(url));
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
    method: 'POST',
    body: content != null ? content : file
  }, {
    name: name // TODO how to send file and params such as name - make fetch do multipart
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

P.svc.hanzi = {
  _index: true,
  _hides: true
};

P.svc.hanzi.collect = async function() {
  var c, counter, i, j, k, keys, len, len1, len2, p, page, pager, rec, ref, ref1, ref2, row, rows, ti, url, val, vc;
  //url = 'http://hanzidb.org/character-list/hsk'
  url = 'http://hanzidb.org/character-list/general-standard';
  counter = 0;
  pager = 0;
  this.svc.hanzi('');
  while (pager < 82) { //27
    pager += 1;
    console.log(pager, counter);
    if (pager > 1) {
      url = url.split('?')[0] + '?page=' + pager;
    }
    page = (await this.fetch(url));
    rows = page.split('<table>')[1].split('</table>')[0].split('</tr>');
    rows.shift(); // drop the first row of headers (thead and tbody were not used, so just ignore first row)
    keys = [
      'character',
      'pinyin',
      'definition',
      'radical',
      'strokes',
      'HSK',
      'standard',
      'frequency' // url, radical_url, radical_base, radical_float
    ];
    for (i = 0, len = rows.length; i < len; i++) {
      row = rows[i];
      rec = {
        type: ['character'],
        page: url
      };
      vc = 0;
      ref = row.replace('<tr>', '').replace('</td></td>', '</td>').split('</td>');
      for (j = 0, len1 = ref.length; j < len1; j++) {
        val = ref[j];
        val = val.replace('<td>', '');
        if (typeof val === 'string' && val.includes('</span>')) {
          val = val.replace('</span>', '').split('>')[1];
        } else if (typeof val === 'string' && val.includes('</a>')) {
          if (vc === 0) {
            val = val.replace('</a>', '').split('>')[1];
          } else {
            try {
              rec.radical_float = parseFloat(val.split('>').pop().replace('&nbsp;', ''));
            } catch (error) {}
            try {
              rec.radical_base = parseInt(rec.radical_float.toString().split('.')[0]);
            } catch (error) {}
            val = val.split('</a>')[0].split('>').pop();
            try {
              rec.radical_url = 'http://hanzidb.org/character/' + val;
            } catch (error) {}
          }
        }
        try {
          val = val.replace('&nbsp;', '');
        } catch (error) {}
        try {
          val = val.trim();
        } catch (error) {}
        try {
          if (typeof val === 'string' && val.replace(/[0-9]/g, '').length === 0) {
            p = parseInt(val);
            if (!isNaN(p)) {
              val = p;
            }
          }
        } catch (error) {}
        if (val && ((ref1 = typeof val) === 'number' || ref1 === 'string')) {
          rec[keys[vc]] = val;
        }
        vc += 1;
      }
      if (rec.definition && rec.definition.includes('KangXi radical')) {
        rec.type.push('radical');
      }
      if (rec.definition && rec.definition.includes('heavenly stem')) {
        rec.type.push('stem');
      }
      try {
        rec.url = 'http://hanzidb.org/character/' + rec.character;
      } catch (error) {}
      rec.ascii = '';
      rec.tones = [];
      if (rec.pinyin) {
        ref2 = [...rec.pinyin.normalize('NFD')];
        for (k = 0, len2 = ref2.length; k < len2; k++) {
          c = ref2[k];
          ti = ['', 772, 769, 780, 768].indexOf(c.codePointAt(0));
          if (ti && ti > 0) {
            rec.tones.push(ti);
          }
          if (c.replace(/[a-zA-Z]/g, '').length === 0) {
            rec.ascii += c;
          }
        }
      }
      if (rec.character != null) {
        this.svc.hanzi(rec);
      } else {
        console.log(rec);
      }
      counter += 1;
    }
  }
  return counter;
};

P.svc.hanzi.collect._async = true;

// TODO add a lookup for the page about the character, where can extract some sample words and more info

// TODO get all 214 radicals. https://hsk.academy/en/learn/the-chinese-radicals

// https://www.unicode.org/charts/unihan.html

// TODO try extracting every particle from a character, not just the radical (first) particle (may need image analysis of the characters)
// https://www.researchgate.net/publication/265175086_RadicalLocator_A_software_tool_for_identifying_the_radicals_in_Chinese_characters
// https://apple.stackexchange.com/questions/127534/convert-single-unicode-character-to-png-image

// direct keyboard entry method for hanzi characters (instead of pinyin method)
// https://en.wikipedia.org/wiki/Wubi_method
`<td><a href="/character/师">师</a></td>
<td><span style="color:#990000;">shī</span></td>
<td><span class="smmr">teacher, master, specialist</span></td>
<td><a href="/character/巾" title="Kangxi radical 50">巾</a>&nbsp;50.3</td>
<td>6</td>
<td>1</td>
<td>0413</td>
</td>
<td>333</td></tr>`;

P.svc.lantern = async function(jid) {
  var i, job, ref, ref1, ref2, ref3, text;
  if (jid == null) {
    jid = (ref = this.params.lantern) != null ? ref : this.params.job;
  }
  if (jid && jid.startsWith('10.')) {
    jid = void 0;
  }
  if (jid != null) {
    job = (await this.svc.lantern.job(jid));
    job.progress = (await this.svc.lantern.progress(job));
    return job;
  } else {
    if (this.params.doi || this.params.lantern || this.params.pmid || this.params.pmc || this.params.pmcid || this.body) {
      job = {};
      if (job.email == null) {
        job.email = this.params.email;
      }
      job._id = this.uid();
      if (this.body) {
        if (typeof this.body === 'object' && !Array.isArray(this.body) && this.body.list) {
          job.processes = this.body.list;
          if (job.name == null) {
            job.name = this.body.name;
          }
        } else {
          job.processes = this.body;
        }
      } else {
        job.processes = [];
        if (this.params.doi || this.params.lantern) {
          job.processes.push({
            doi: (ref1 = this.params.doi) != null ? ref1 : this.params.lantern
          });
        }
        if (this.params.pmid) {
          job.processes.push({
            pmid: this.params.pmid
          });
        }
        if (this.params.pmcid || this.params.pmc) {
          job.processes.push({
            pmcid: (ref2 = this.params.pmcid) != null ? ref2 : this.params.pmc
          });
        }
        if (job.name == null) {
          job.name = this.params.name;
        }
      }
      this.svc.lantern.job(job);
      for (i in job.processes) {
        this.svc.lantern.process(job.processes[i], parseInt(i) === job.processes.length - 1 ? job : void 0);
      }
      if (job.email) {
        text = 'Dear ' + job.email + '\n\nWe\'ve just started processing a batch of identifiers for you, and you can see the progress of the job here:\n\n';
        text += 'https://compliance.cottagelabs.com#' + job._id;
        text += '\n\nIf you didn\'t submit this request yourself, it probably means that another service is running ';
        text += 'it on your behalf, so this is just to keep you informed about what\'s happening with your account; ';
        text += 'you don\'t need to do anything else.\n\nYou\'ll get another email when your job has completed.\n\n';
        this.mail({
          from: 'Lantern <lantern@cottagelabs.com>',
          to: job.email,
          subject: 'Compliance: job ' + ((ref3 = job.name) != null ? ref3 : job._id) + ' submitted successfully',
          text: text
        });
      }
      return job;
    } else {
      return {
        name: 'Lantern',
        version: this.S.version,
        base: this.S.dev ? this.base : void 0,
        built: this.S.built
      };
    }
  }
};

P.svc.lantern.job = {
  _index: true
};

P.svc.lantern.result = {
  _index: true
};

P.svc.lantern.results = async function(jid) {
  var fields, fname, grnt, j, job, jr, k, len, len1, len2, len3, len4, len5, len6, m, n, o, p, pr, printname, proc, q, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, result, results, rgc, rr, tpn;
  if (jid == null) {
    jid = (ref = (ref1 = this.params.lantern) != null ? ref1 : this.params.results) != null ? ref : this.params.job;
  }
  job = typeof jid === 'object' ? jid : (await this.svc.lantern.job(jid));
  jr = [];
  ref2 = job.processes;
  for (j = 0, len = ref2.length; j < len; j++) {
    proc = ref2[j];
    if (res = (await this.svc.lantern.result(proc._id))) {
      jr.push(res);
    }
  }
  if (this.format !== 'csv') {
    return jr;
  } else {
    fields = ["pmcid", "pmid", "doi", "title", "journal_title", "pure_oa", "issn", "eissn", "publication_date", "electronic_publication_date", "publisher", "publisher_licence", "licence", "epmc_licence", "licence_source", "epmc_licence_source", "in_epmc", "epmc_xml", "aam", "open_access", "ahead_of_print", "romeo_colour", "preprint_embargo", "preprint_self_archiving", "postprint_embargo", "postprint_self_archiving", "publisher_copy_embargo", "publisher_copy_self_archiving", "authors", "in_base", "repositories", "repository_urls", "repository_fulltext_urls", "repository_oai_ids", "confidence", "compliance_wellcome_standard", "compliance_wellcome_deluxe"];
    results = [];
    for (k = 0, len1 = job.length; k < len1; k++) {
      res = job[k];
      result = {};
      for (m = 0, len2 = fields.length; m < len2; m++) {
        fname = fields[m];
        printname = (ref3 = (ref4 = P.svc.lantern._fields[fname]) != null ? ref4.short_name : void 0) != null ? ref3 : fname;
        if (fname === 'authors') {
          result.printname = '';
          ref5 = res.authors;
          for (n = 0, len3 = ref5.length; n < len3; n++) {
            r = ref5[n];
            if (r.fullName) {
              result.printname += (result.printname ? '\r\n' : '') + r.fullName;
            }
          }
        } else if (fname === 'repositories' || fname === 'repository_urls' || fname === 'repository_fulltext_urls' || fname === 'repository_oai_ids') {
          result[printname] = '';
          if (res.repositories != null) {
            ref6 = res.repositories;
            for (o = 0, len4 = ref6.length; o < len4; o++) {
              rr = ref6[o];
              if (rr.name) {
                if (result[printname]) {
                  result[printname] += '\r\n';
                }
                if (fname === 'repositories') {
                  result[printname] += (ref7 = rr.name) != null ? ref7 : '';
                } else if (fname === 'repository_urls') {
                  result[printname] += (ref8 = rr.url) != null ? ref8 : '';
                } else if (fname === 'repository_fulltext_urls') {
                  result[printname] += rr.fulltexts != null ? rr.fulltexts.join() : '';
                } else if (fname === 'repository_oai_ids') {
                  result[printname] += (ref9 = rr.oai) != null ? ref9 : '';
                }
              }
            }
          }
        } else if (fname === 'pmcid' && res.pmcid) {
          if (res.pmcid.toLowerCase().indexOf('pmc') !== 0) {
            res.pmcid = 'PMC' + res.pmcid;
          }
          result[printname] = res.pmcid;
        } else if (res[fname] === true) {
          result[printname] = 'TRUE';
        } else if (res[fname] === false) {
          result[printname] = 'FALSE';
        } else if ((res[fname] == null) || res[fname] === 'unknown') {
          result[printname] = 'Unknown';
        } else {
          result[printname] = res[fname];
        }
      }
      if (res.grants != null) {
        rgc = 0;
        ref10 = res.grants;
        for (p = 0, len5 = ref10.length; p < len5; p++) {
          grnt = ref10[p];
          rgc += 1;
          result[((ref12 = (ref13 = P.svc.lantern._fields.grant) != null ? ref13.short_name : void 0) != null ? ref12 : 'grant').split(' ')[0] + ' ' + rgc] = (ref11 = grnt.grantId) != null ? ref11 : '';
          result[((ref15 = (ref16 = P.svc.lantern._fields.agency) != null ? ref16.short_name : void 0) != null ? ref15 : 'agency').split(' ')[0] + ' ' + rgc] = (ref14 = grnt.agency) != null ? ref14 : '';
          result[((ref18 = (ref19 = P.svc.lantern._fields.pi) != null ? ref19.short_name : void 0) != null ? ref18 : 'pi').split(' ')[0] + ' ' + rgc] = (ref17 = grnt.PI) != null ? ref17 : (grnt.grantId || grnt.agency ? 'Unknown' : '');
        }
      }
      tpn = (ref20 = (ref21 = P.svc.lantern._fields['provenance']) != null ? ref21.short_name : void 0) != null ? ref20 : 'provenance';
      result[tpn] = '';
      ref23 = (ref22 = res.provenance) != null ? ref22 : [];
      for (q = 0, len6 = ref23.length; q < len6; q++) {
        pr = ref23[q];
        result[tpn] += result[tpn] ? '\r\n' : '';
        result[tpn] += pr;
      }
      results.push(result);
    }
    return results;
  }
};

P.svc.lantern.progress = async function(jid) {
  var job, ref, ref1, results;
  if (jid == null) {
    jid = (ref = (ref1 = this.params.lantern) != null ? ref1 : this.params.progress) != null ? ref : this.params.job;
  }
  job = typeof jid === 'object' ? jid : (await this.svc.lantern.job(jid));
  results = (await this.svc.lantern.results(job));
  return Math.ceil((results.length / job.processes.length) * 10000) / 100;
};

P.svc.lantern.licence = async function(url, content, start, end) {
  var j, l, len, lh, lic, lics, match, ref, ref1, ref2, ref3, urlmatch, urlmatcher;
  if (url == null) {
    url = this.params.url;
  }
  if (url != null) {
    url = url.replace(/(^\s*)|(\s*$)/g, '');
  }
  if (content == null) {
    content = (ref = this.params.content) != null ? ref : this.body;
  }
  try {
    if (content == null) {
      content = (await this.puppet(url));
    }
  } catch (error) {}
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
    if (content.length > 1000000) {
      lic.large = true;
      content = content.substring(0, 500000) + content.substring(content.length - 500000, content.length);
    }
    lics = (await this.svc.lantern.licences('*', 10000));
    ref3 = (ref1 = lics != null ? (ref2 = lics.hits) != null ? ref2.hits : void 0 : void 0) != null ? ref1 : [];
    for (j = 0, len = ref3.length; j < len; j++) {
      lh = ref3[j];
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

P.svc.lantern.licences = {
  _sheet: '1yJOpE_YMdDxCKaK0DqWoCJDdq8Ep1b-_J1xYVKGsiYI',
  _prefix: false
};

P.svc.lantern.process = async function(proc, last) {
  var _formatepmcdate, aam, base, crossref, diss, doaj, domain, efd, epmc_compliance_lic, epmc_lics, eupmc, extrainfo, fd, fofxml, gr, grants, gres, grid, j, job, k, km, len, len1, len2, len3, len4, lic, m, msg, n, o, oa, pid, pm, ps, pu, publisher_licence_check_ran, rc, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref3, ref4, ref5, ref6, ref7, ref8, ref9, repos, res, result, result_invalid_date_of_electronic_publication, st, text, xml;
  _formatepmcdate = function(date) {
    var dateparts, dp, dy, mth, ref, ref1;
    try {
      date = date.replace(/\//g, '-');
      if (date.includes('-')) {
        if (date.length < 11) {
          dp = date.split('-');
          if (dp.length === 3) {
            if (date.indexOf('-') < 4) {
              return dp[2] + '-' + dp[1] + '-' + dp[0] + 'T00:00:00Z';
            } else {
              return date + 'T00:00:00Z';
            }
          } else if (dp.length === 2) {
            if (date.indexOf('-') < 4) {
              return dp[1] + dp[0] + date + '-01T00:00:00Z';
            } else {
              return date + '-01T00:00:00Z';
            }
          }
        }
        return date;
      } else {
        dateparts = date.replace(/  /g, ' ').split(' ');
        mth = parseInt((ref = dateparts[1]) != null ? ref : 1);
        if (isNaN(mth)) {
          try {
            mth = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'].indexOf(mth.toLowerCase().substr(0, 3));
          } catch (error) {}
        }
        if (mth == null) {
          mth = '01';
        }
        dy = (ref1 = dateparts[2]) != null ? ref1 : '01';
        return dateparts[0] + '-' + (mth.toString().length === 1 ? '0' : '') + mth + '-' + (dy.toString().length === 1 ? '0' : '') + dy + 'T00:00:00Z';
      }
    } catch (error) {

    }
  };
  if (proc == null) {
    proc = {
      doi: this.params.doi,
      pmid: this.params.pmid,
      pmcid: this.params.pmcid
    };
  }
  ref = ['DOI', 'PMID', 'PMCID', 'TITLE'];
  for (j = 0, len = ref.length; j < len; j++) {
    pu = ref[j];
    if (proc[pu]) {
      proc[pu.toLowerCase()] = proc[pu];
    }
  }
  if (proc.doi == null) {
    proc.doi = proc.DOI;
  }
  if (proc.pmid == null) {
    proc.pmid = proc.PMID;
  }
  if (proc.pmcid == null) {
    proc.pmcid = (ref1 = (ref2 = proc.PMCID) != null ? ref2 : proc.PMC) != null ? ref1 : proc.pmc;
  }
  if (proc.title == null) {
    proc.title = (ref3 = (ref4 = proc['article title']) != null ? ref4 : proc['Article title']) != null ? ref3 : proc['Article Title'];
  }
  if (proc.title) {
    proc.title = proc.title.replace(/\s\s+/g, ' ').trim();
  }
  if (proc.pmcid) {
    proc.pmcid = proc.pmcid.replace(/[^0-9]/g, '');
  }
  if (proc.pmid) {
    proc.pmid = proc.pmid.replace(/[^0-9]/g, '');
  }
  if (proc.doi) {
    proc.doi = decodeURIComponent(proc.doi.replace(/ /g, ''));
  }
  if (proc._id == null) {
    proc._id = proc.doi ? proc.doi.replace(/\//g, '_') : (ref5 = (ref6 = proc.pmcid) != null ? ref6 : proc.pmid) != null ? ref5 : (await this.uid());
  }
  result = {
    _id: proc._id,
    pmcid: proc.pmcid,
    pmid: proc.pmid,
    doi: proc.doi,
    title: proc.title,
    journal_title: void 0,
    pure_oa: false, // set to true if found in doaj
    issn: void 0,
    eissn: void 0,
    publication_date: void 0,
    electronic_publication_date: void 0,
    publisher: void 0,
    publisher_licence: void 0,
    licence: 'unknown', // what sort of licence this has - should be a string like "cc-by"
    epmc_licence: 'unknown', // the licence in EPMC, should be a string like "cc-by"
    licence_source: 'unknown', // where the licence info came from
    epmc_licence_source: 'unknown', // where the EPMC licence info came from (fulltext xml, EPMC splash page, etc.)
    in_epmc: false, // set to true if found
    epmc_xml: false, // set to true if oa and in epmc and can retrieve fulltext xml from eupmc rest API url
    aam: false, // set to true if is an eupmc author manuscript
    open_access: false, // set to true if eupmc or other source says is oa
    ahead_of_print: void 0, // if pubmed returns a date for this, it will be a date
    preprint_embargo: 'unknown',
    preprint_self_archiving: 'unknown',
    postprint_embargo: 'unknown',
    postprint_self_archiving: 'unknown',
    publisher_copy_embargo: 'unknown',
    publisher_copy_self_archiving: 'unknown',
    authors: [], // eupmc author list if available
    in_base: 'unknown',
    repositories: [], // where BASE says it is
    grants: [], // a list of grants, probably from eupmc for now
    confidence: 0, // 1 if matched on ID, 0.9 if title to 1 result, 0.7 if title to multiple results, 0 if unknown article
    provenance: []
  };
  ref7 = ['pmcid', 'pmid', 'doi', 'title'];
  // search eupmc by (in order) pmcid, pmid, doi, title
  for (k = 0, len1 = ref7.length; k < len1; k++) {
    st = ref7[k];
    if (proc[st]) {
      if (res = (await this.src.epmc[st === 'pmcid' ? 'pmc' : st](proc[st]))) {
        eupmc = res;
        result.confidence = st !== 'title' ? 1 : res.title.toLowerCase() === proc[st].toLowerCase() ? 1 : 0.9;
        break;
      } else if (st === 'title' && (res = (await this.src.epmc('title:' + proc[st])))) {
        if (((res != null ? res.data : void 0) != null) && res.data.length) {
          eupmc = res.data[0];
          result.confidence = 0.7;
        }
      }
    }
  }
  if (eupmc != null) {
    if (eupmc.pmcid && result.pmcid !== eupmc.pmcid) {
      result.pmcid = eupmc.pmcid;
      result.provenance.push('Added PMCID from EUPMC');
    }
    if (eupmc.pmid && result.pmid !== eupmc.pmid) {
      result.pmid = eupmc.pmid;
      result.provenance.push('Added PMID from EUPMC');
    }
    if (eupmc.doi && result.doi !== eupmc.doi) {
      result.doi = eupmc.doi;
      result.provenance.push('Added DOI from EUPMC');
    }
    if (eupmc.title && !result.title) {
      result.title = eupmc.title;
      result.provenance.push('Added article title from EUPMC');
    }
    if (eupmc.inEPMC === 'Y') {
      result.in_epmc = true;
      result.provenance.push('Confirmed fulltext is in EUPMC');
    }
    if (eupmc.isOpenAccess === 'Y') {
      result.open_access = true;
      result.provenance.push('Confirmed is open access from EUPMC');
    } else {
      result.provenance.push('This article is not open access according to EUPMC, but since 6th March 2020 we take this to mean only that the publisher did not indicate to EUPMC that it can be included in their Open Access subset - it may well still be an OA article.');
    }
    if ((ref8 = eupmc.journalInfo) != null ? ref8.journal : void 0) {
      if (eupmc.journalInfo.journal.title) {
        result.journal_title = eupmc.journalInfo.journal.title;
        result.provenance.push('Added journal title from EUPMC');
      }
      if (eupmc.journalInfo.journal.issn) {
        result.issn = eupmc.journalInfo.journal.issn;
        result.provenance.push('Added issn from EUPMC');
      }
      if (eupmc.journalInfo.journal.essn) {
        result.eissn = eupmc.journalInfo.journal.essn;
        if (result.eissn && (!result.issn || result.issn.indexOf(result.eissn) === -1)) {
          result.issn = (result.issn ? result.issn + ', ' : '') + result.eissn;
        }
        result.provenance.push('Added eissn from EUPMC');
      }
    }
    if ((ref9 = eupmc.grantsList) != null ? ref9.grant : void 0) {
      result.grants = eupmc.grantsList.grant;
      result.provenance.push('Added grants data from EUPMC');
    }
    if ((ref10 = eupmc.journalInfo) != null ? ref10.dateOfPublication : void 0) {
      if (fd = (await _formatepmcdate(eupmc.journalInfo.dateOfPublication))) {
        result.publication_date = fd;
        result.provenance.push('Added date of publication from EUPMC');
      } else {
        result._invalid_date_of_publication = eupmc.journalInfo.dateOfPublication;
        result.provenance.push('Could not add invalid date of publication from EUPMC (' + result._invalid_date_of_publication + ')');
      }
    }
    if (eupmc.electronicPublicationDate) {
      if (efd = (await _formatepmcdate(eupmc.electronicPublicationDate))) {
        result.electronic_publication_date = efd;
        result.provenance.push('Added electronic publication date from EUPMC');
      } else {
        result_invalid_date_of_electronic_publication = eupmc.electronicPublicationDate;
        result.provenance.push('Could not add invalid electronic publication date from EUPMC (' + result_invalid_date_of_electronic_publication + ')');
      }
    }
    if (result.pmcid) { // removed need for being open_access or in_epmc (as according to epmc)
      result.provenance.push('Checking if XML is available from EUPMC (since 6th March 2020 this is always done for any article we have a PMCID for, regardless of other EUPMC API values).');
      xml = (await this.src.epmc.xml(result.pmcid));
      if (xml === 404) {
        fofxml = 'Not found in EUPMC when trying to fetch full text XML.';
        fofxml += ' (We do this for any item we have a PMCID for since 6th March 2020, even if EUPMC indicates not in their open access category and/or fulltext not in EUPMC.';
        result.provenance.push(fofxml);
      } else if (typeof xml === 'string' && xml.indexOf('<') === 0) {
        result.epmc_xml = true;
        result.provenance.push('Confirmed fulltext XML is available from EUPMC');
      } else if (xml != null) {
        result.provenance.push('Encountered an error while retrieving the EUPMC full text XML. One possible reason is EUPMC being temporarily unavailable.');
      }
    }
    if (lic = (await this.src.epmc.licence(result.pmcid, eupmc, xml))) {
      result.licence = lic.licence;
      result.epmc_licence = lic.licence;
      result.licence_source = lic.source;
      result.epmc_licence_source = lic.source;
      extrainfo = '';
      if (lic.match) {
        extrainfo += ' If licence statements contain URLs we will try to find those in addition to ';
        extrainfo += 'searching for the statement\'s text. The match in this case was: \'' + lic.match.replace(/<.*?>/gi, '') + '\' .';
      }
      result.provenance.push('Added EPMC licence (' + result.epmc_licence + ') from ' + lic.source + '.' + extrainfo);
    } else {
      result.provenance.push('Could not find licence via EUPMC');
    }
    if ((ref11 = eupmc.authorList) != null ? ref11.author : void 0) {
      result.authors = eupmc.authorList.author;
      result.provenance.push('Added author list from EUPMC');
    }
    if (result.in_epmc) {
      aam = (await this.src.epmc.aam(result.pmcid, eupmc));
      if (aam.aam === false) {
        result.aam = false;
        result.provenance.push('Checked author manuscript status in EUPMC, found no evidence of being one');
      } else if (aam.aam === true) {
        result.aam = true;
        result.provenance.push('Checked author manuscript status in EUPMC, found in ' + aam.info);
      } else if (aam.info.indexOf('404') !== -1) {
        result.aam = false;
        result.provenance.push('Unable to locate Author Manuscript information in EUPMC - could not find the article in EUPMC.');
      } else if (aam.info.indexOf('error') !== -1) {
        result.aam = 'unknown';
        result.provenance.push('Error accessing EUPMC while trying to locate Author Manuscript information. EUPMC could be temporarily unavailable.');
      } else if (aam.info.indexOf('blocking') !== -1) {
        result.aam = 'unknown';
        result.provenance.push('Error accessing EUPMC while trying to locate Author Manuscript information - EUPMC is blocking access.');
      } else {
        result.aam = 'unknown';
      }
    }
  } else {
    result.provenance.push('Unable to locate article in EPMC.');
  }
  if (!result.doi && !result.pmid && !result.pmcid) {
    result.provenance.push('Unable to obtain DOI, PMID or PMCID for this article. Compliance information may be severely limited.');
  }
  if (result.doi) {
    crossref = (await this.src.crossref.works(result.doi));
    if (crossref != null) {
      if (!result.confidence) {
        result.confidence = 1;
      }
      result.publisher = crossref.publisher;
      result.provenance.push('Added publisher name from Crossref');
      if (!result.issn && (crossref.issn || ((crossref.ISSN != null) && crossref.ISSN.length > 0))) {
        result.issn = (ref12 = crossref.issn) != null ? ref12 : crossref.ISSN[0];
        result.provenance.push('Added ISSN from Crossref');
      }
      if (!result.journal_title && (crossref.journal || ((crossref['container-title'] != null) && crossref['container-title'].length > 0))) {
        result.journal_title = (ref13 = crossref.journal) != null ? ref13 : crossref['container-title'][0];
        result.provenance.push('Added journal title from Crossref');
      }
      if (!result.authors && crossref.author) {
        result.authors = crossref.author;
        result.provenance.push('Added author list from Crossref');
      }
      if (!result.title && (crossref.title != null) && crossref.title.length > 0) {
        result.title = Array.isArray(crossref.title) ? crossref.title[0] : crossref.title;
        result.provenance.push('Added article title from Crossref');
      }
    } else {
      result.provenance.push('Unable to obtain information about this article from Crossref.');
    }
    base = (await this.src.base.doi(result.doi));
    if ((base != null ? base.dclink : void 0) != null) {
      result.in_base = true;
      result.provenance.push('Found DOI in BASE');
      try {
        domain = base.dclink.split('://')[1].split('/')[0];
        repos = (await this.src.sherpa.opendoar('repository_metadata.url:*' + domain('*')));
        rc = repos != null ? (ref14 = repos.hits) != null ? (ref15 = ref14.hits) != null ? (ref16 = ref15[0]) != null ? (ref17 = ref16._source) != null ? ref17.repository_metadata : void 0 : void 0 : void 0 : void 0 : void 0;
        if (typeof (rc != null ? rc.url : void 0) === 'string' && rc.url.toLowerCase().includes(domain.toLowerCase())) {
          result.repositories.push({
            fulltexts: [base.dclink],
            url: rc.url,
            name: rc.name[0].name,
            oai: rc.oai_url
          });
          result.provenance.push('Added repo base URL from OpenDOAR');
        } else {
          result.provenance.push('Searched OpenDOAR but could not find repo and/or URL');
        }
      } catch (error) {
        result.provenance.push('Tried but failed to search OpenDOAR for repo base URL');
      }
      if (!result.repositories.length) {
        result.repositories.push({
          filltexts: [base.dclink]
        });
      }
      if (!result.title && base.dctitle) {
        result.title = base.dctitle;
        result.provenance.push('Added title from BASE');
      }
    } else {
      result.in_base = false;
      result.provenance.push('Could not find DOI in BASE');
    }
  } else {
    result.provenance.push('Not attempting Crossref / BASE lookups - do not have DOI for article.');
  }
  if ((result.grants != null) && result.grants.length > 0) {
    grants = [];
    ref18 = result.grants;
    for (m = 0, len2 = ref18.length; m < len2; m++) {
      gr = ref18[m];
      if (gr.grantId) {
        grid = gr.grantId;
        if (gr.agency && gr.agency.toLowerCase().indexOf('wellcome') !== -1) {
          grid = grid.split('/')[0];
        }
        gres = (await this.src.grist(grid));
        if (gres.total && gres.total > 0 && gres.data.Person) {
          ps = gres.data.Person;
          pid = '';
          if (ps.Title) {
            pid += ps.Title + ' ';
          }
          if (ps.GivenName) {
            pid += ps.GivenName + ' ';
          }
          if (!ps.GivenName && ps.Initials) {
            pid += ps.Initials + ' ';
          }
          if (ps.FamilyName) {
            pid += ps.FamilyName;
          }
          gr.PI = pid;
          result.provenance.push('Found Grant PI for ' + grid + ' via Grist API');
        } else {
          result.provenance.push('Tried but failed to find Grant PI via Grist API');
        }
      } else {
        gr.grantId = 'unknown';
      }
      if (gr.agency && gr.agency.toLowerCase().indexOf('wellcome') !== -1) {
        grants.unshift(gr);
      } else {
        grants.push(gr);
      }
    }
    result.grants = grants;
  } else {
    result.provenance.push('Not attempting Grist API grant lookups since no grants data was obtained from EUPMC.');
  }
  if (result.pmid && !result.in_epmc) {
    result.ahead_of_print = (await this.src.pubmed.aheadofprint(result.pmid));
    if (result.ahead_of_print !== false) {
      result.provenance.push('Checked ahead of print status on pubmed, date found ' + result.ahead_of_print);
    } else {
      result.provenance.push('Checked ahead of print status on pubmed, no date found');
    }
  } else {
    msg = 'Not checking ahead of print status on pubmed.';
    if (!result.pmid) {
      msg += ' We don\'t have the article\'s PMID.';
    }
    if (result.in_epmc) {
      msg += ' The article is already in EUPMC.';
    }
    result.provenance.push(msg);
  }
  if (result.issn) {
    ref19 = result.issn.split(',');
    for (n = 0, len3 = ref19.length; n < len3; n++) {
      diss = ref19[n];
      doaj = (await this.src.doaj.journals(diss));
      if (doaj != null) {
        result.pure_oa = true;
        result.provenance.push('Confirmed journal is listed in DOAJ');
        if (result.publisher == null) {
          result.publisher = (ref20 = doaj.bibjson) != null ? (ref21 = ref20.publisher) != null ? ref21.name : void 0 : void 0;
        }
        if (result.journal_title == null) {
          result.journal_title = (ref22 = doaj.bibjson) != null ? ref22.title : void 0;
        }
        break;
      }
    }
    if (result.pure_oa !== true) {
      result.provenance.push('Could not find journal in DOAJ');
    }
  }
  if (!result.issn) {
    result.provenance.push('Not attempting to add any data from OA.Works - don\'t have a journal ISSN to use for lookup.');
  } else if (this.svc.oaworks == null) {
    result.provenance.push('Not attempting to add any data from OA.Works, it is not available.');
  } else if (oa = (await this.svc.oaworks.find({
    issn: result.issn,
    permissions: true
  }))) {
    if (!result.journal_title) {
      if (((ref23 = oa.metadata) != null ? ref23.journal : void 0) != null) {
        result.journal_title = oa.metadata.journal;
        result.provenance.push('Added journal title Open Access Button');
      } else {
        result.provenance.push('Tried, but could not add journal title from Open Access Button.');
      }
    }
    if (!result.publisher) {
      if (((ref24 = oa.metadata) != null ? ref24.publisher : void 0) != null) {
        result.publisher = oa.metadata.publisher;
        result.provenance.push('Added publisher from Open Access Button');
      } else {
        result.provenance.push('Tried, but could not add publisher from Open Access Button.');
      }
    }
    if ((((ref25 = oa.permissions) != null ? ref25.all_permissions : void 0) != null) && oa.permissions.all_permissions.length) {
      ref26 = oa.permissions.all_permissions;
      for (o = 0, len4 = ref26.length; o < len4; o++) {
        pm = ref26[o];
        km = pm.version === 'submittedVersion' ? 'preprint' : pm.version === 'acceptedVersion' ? 'postprint' : pm.version === 'publishedVersion' ? 'publisher_copy' : void 0;
        if (km != null) {
          result[km + '_embargo'] = (pm.embargo_months ? pm.embargo_months + ' months' : '') + (pm.embargo_end ? ' ending ' + pm.embargo_end : '');
          result[km + '_self_archiving'] = pm.deposit_statement;
        }
      }
      result.provenance.push('Added embargo and archiving data from Open Access Button');
    } else {
      result.provenance.push('No embargo and archiving data available from Open Access Button');
    }
  } else {
    result.provenance.push('Unable to add any data from Open Access Button.');
  }
  publisher_licence_check_ran = false;
  if (!result.licence || ((ref27 = result.licence) !== 'cc-by' && ref27 !== 'cc-zero')) {
    publisher_licence_check_ran = true;
    lic = (await this.svc.lantern.licence('https://doi.org/' + result.doi));
    if (lic.licence && lic.licence !== 'unknown') {
      result.licence = lic.licence;
      result.licence_source = 'publisher_splash_page';
      result.publisher_licence = lic.licence;
      extrainfo = '';
      if (lic.match) {
        extrainfo += ' If licence statements contain URLs we will try to find those in addition to ' + 'searching for the statement\'s text. The match in this case was: \'' + lic.match.replace(/<.*?>/gi, '') + '\' .';
      }
      result.provenance.push('Added licence (' + result.publisher_licence + ') via article publisher splash page lookup.' + extrainfo);
    } else {
      result.publisher_licence = 'unknown';
      result.provenance.push('Unable to retrieve licence data via article publisher splash page lookup.');
      if (lic.large) {
        result.provenance.push('Retrieved content was very long, so was contracted to 500,000 chars from start and end to process');
      }
    }
  } else {
    result.provenance.push('Not attempting to retrieve licence data via article publisher splash page lookup.');
    publisher_licence_check_ran = false;
  }
  if (!publisher_licence_check_ran && result.publisher_licence !== 'unknown') {
    result.publisher_licence = "not applicable";
  }
  if (result.publisher_licence == null) {
    result.publisher_licence = 'unknown';
  }
  if ((result.epmc_licence != null) && result.epmc_licence !== 'unknown' && !result.epmc_licence.startsWith('cc-')) {
    result.epmc_licence = 'non-standard-licence';
  }
  if ((result.publisher_licence != null) && result.publisher_licence !== 'unknown' && result.publisher_licence !== "not applicable" && !result.publisher_licence.startsWith('cc-')) {
    result.publisher_licence = 'non-standard-licence';
  }
  epmc_compliance_lic = result.epmc_licence ? result.epmc_licence.toLowerCase().replace(/ /g, '').replace(/-/g, '') : '';
  epmc_lics = epmc_compliance_lic === 'ccby' || epmc_compliance_lic === 'cc0' || epmc_compliance_lic === 'cczero';
  result.compliance_wellcome_standard = result.in_epmc && (result.aam || epmc_lics);
  result.compliance_wellcome_deluxe = result.in_epmc && result.aam;
  if (result.in_epmc && epmc_lics && result.open_access) {
    result.compliance_wellcome_deluxe = true;
  }
  this.svc.lantern.result(result);
  if (last) { // last is the job ID
    job = typeof last === 'object' ? last : (await this.svc.lantern.job(last));
    if (job != null ? job.email : void 0) {
      text = 'Dear ' + job.email + '\n\nWe\'ve just finished processing a batch of identifiers for you, and you can download the final results here:\n\n';
      text += 'https://compliance.cottagelabs.com#' + job._id + '\n\nIf you didn\'t submit the original request yourself, it probably means ';
      text += 'that another service was running it on your behalf, so this is just to keep you informed about what\'s happening with your account; you don\'t need to do anything else.';
      this.mail({
        from: 'Lantern <lantern@cottagelabs.com>',
        to: job.email,
        subject: 'Compliance: job ' + ((ref28 = job.name) != null ? ref28 : job._id) + ' completed successfully',
        text: text
      });
    }
  }
  return result;
};

P.svc.lantern._fields = {
  "pmcid": {
    "short_name": "PMCID"
  },
  "pmid": {
    "short_name": "PMID"
  },
  "doi": {
    "short_name": "DOI"
  },
  "title": {
    "short_name": "Article title"
  },
  "journal_title": {
    "short_name": "Journal title"
  },
  "pure_oa": {
    "short_name": "Pure Open Access"
  },
  "issn": {
    "short_name": "ISSN"
  },
  "eissn": {
    "short_name": "EISSN"
  },
  "publication_date": {
    "short_name": "Publication Date"
  },
  "electronic_publication_date": {
    "short_name": "Electronic Publication Date"
  },
  "publisher": {
    "short_name": "Publisher"
  },
  "publisher_licence": {
    "short_name": "Publisher Licence"
  },
  "epmc_licence": {
    "short_name": "EPMC Licence"
  },
  "epmc_licence_source": {
    "short_name": "EPMC Licence Source"
  },
  "licence_source": {
    "short_name": "Licence Source"
  },
  "licence": {
    "short_name": "Licence"
  },
  "in_epmc": {
    "short_name": "Fulltext in EPMC?"
  },
  "epmc_xml": {
    "short_name": "XML Fulltext?"
  },
  "aam": {
    "short_name": "AAM?"
  },
  "open_access": {
    "short_name": "Open Access"
  },
  "ahead_of_print": {
    "short_name": "Ahead of Print?"
  },
  "romeo_colour": {
    "short_name": "Sherpa Romeo Colour"
  },
  "preprint_embargo": {
    "short_name": "Preprint Embargo"
  },
  "preprint_self_archiving": {
    "short_name": "Preprint Self-Archiving Policy"
  },
  "postprint_embargo": {
    "short_name": "Postprint Embargo"
  },
  "postprint_self_archiving": {
    "short_name": "Postprint Self-Archiving Policy"
  },
  "publisher_copy_embargo": {
    "short_name": "Publisher's Copy Embargo"
  },
  "publisher_copy_self_archiving": {
    "short_name": "Publisher's Copy Self-Archiving Policy"
  },
  "authors": {
    "short_name": "Author(s)"
  },
  "in_base": {
    "short_name": "In BASE?"
  },
  "repositories": {
    "short_name": "Archived Repositories"
  },
  "repository_urls": {
    "short_name": "Repository URLs"
  },
  "repository_oai_ids": {
    "short_name": "Repository OAI IDs"
  },
  "repository_fulltext_urls": {
    "short_name": "Repository Fulltext URLs"
  },
  "grant": {
    "short_name": "Grant {X}"
  },
  "agency": {
    "short_name": "Agency {X}"
  },
  "pi": {
    "short_name": "PI {X}"
  },
  "confidence": {
    "short_name": "Correct Article Confidence"
  },
  "compliance_wellcome_standard": {
    "short_name": "Compliance Wellcome Standard"
  },
  "compliance_wellcome_deluxe": {
    "short_name": "Compliance Wellcome Deluxe"
  },
  "provenance": {
    "short_name": "Provenance"
  }
};

try {
  S.svc.oaworks = JSON.parse(SECRETS_OAWORKS);
} catch (error) {
  S.svc.oaworks = {};
}

P.svc.oaworks = async function() {
  var hd, j, len, ref, ref1, rts;
  if (JSON.stringify(this.params) !== '{}') {
    return {
      status: 404
    };
  } else {
    rts = (await this.subroutes('svc.oaworks'));
    ref = ['bug', 'blacklist', 'deposits', 'journal', 'journal/load'];
    for (j = 0, len = ref.length; j < len; j++) {
      hd = ref[j];
      rts.splice(rts.indexOf(hd), 1);
    }
    return {
      name: 'OA.Works Paradigm API',
      version: this.S.version,
      base: this.S.dev ? this.base : void 0,
      built: this.S.dev ? this.S.built : void 0,
      user: ((ref1 = this.user) != null ? ref1.email : void 0) ? this.user.email : void 0,
      routes: rts
    };
  }
};

P.svc.oaworks.templates = {
  _key: 'name',
  _sheet: '16Qm8n3Rmx3QyttFpSGj81_7T6ehfLAtYRSvmDf3pAzg/1',
  _hide: true
};

P.svc.oaworks.bug = async function() {
  var k, lc, ref, ref1, ref2, ref3, ref4, ref5, subject, text, whoto;
  if (this.params.contact) { // verify humanity
    return '';
  } else {
    whoto = ['help@oa.works'];
    text = '';
    for (k in this.params) {
      text += k + ': ' + JSON.stringify(this.params[k], void 0, 2) + '\n\n';
    }
    text = (await this.tdm.clean(text));
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
      whoto.push('natalia@oa.works');
    }
    this.waitUntil(this.mail({
      service: 'openaccessbutton',
      from: 'help@oa.works',
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

P.svc.oaworks.blacklist = async function(url) {
  var b, blacklist, i, j, l, len, len1, ref, ref1, ref2, ref3;
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
  ref3 = (await this.src.google.sheets((ref = this.S.svc.oaworks) != null ? (ref1 = ref.google) != null ? (ref2 = ref1.sheets) != null ? ref2.blacklist : void 0 : void 0 : void 0));
  for (j = 0, len = ref3.length; j < len; j++) {
    i = ref3[j];
    blacklist.push(i.url.toLowerCase());
  }
  if (url) {
    if (!url.startsWith('http') && url.includes(' ')) {
      return false; // sometimes things like article titles get sent here, no point checking them on the blacklist
    } else {
      for (l = 0, len1 = blacklist.length; l < len1; l++) {
        b = blacklist[l];
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

// get the big deal data from a sheet and expose it in a website
// https://docs.google.com/spreadsheets/d/e/2PACX-1vQ4frfBvvPOKKFhArpV7cRUG0aAbfGRy214y-xlDG_CsW7kNbL-e8tuRvh8y37F4xc8wjO6FK8SD6UT/pubhtml
// https://docs.google.com/spreadsheets/d/1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs/edit
P.svc.oaworks.deal = {
  _index: true,
  _hides: true,
  _prefix: false
};

P.svc.oaworks.deal.institution = {
  _index: true,
  _prefix: false
};

P.svc.oaworks.deal.import = async function() {
  var i, institutions, insts, j, len, name, rdc, rec, recs;
  recs = (await this.src.google.sheets('1dPG7Xxvk4qnPajTu9jG_uNuz2R5jvjfeaKI-ylX4NXs'));
  institutions = {};
  for (j = 0, len = recs.length; j < len; j++) {
    rec = recs[j];
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
  await this.svc.oaworks.deal('');
  await this.svc.oaworks.deal.institution('');
  await this.svc.oaworks.deal(recs);
  await this.svc.oaworks.deal.institution(insts);
  return {
    retrieved: recs.length,
    institutions: insts.length
  };
};

// need listing of deposits and deposited for each user ID
// and/or given a uid, find the most recent URL that this users uid submitted a deposit for
// need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
// make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)

// NOTE to receive files cloudflare should be setup to DNS route this directly to backend, and any calls to it should call that dns subdomain
// because otherwise cloudflare will limit file upload size (100mb by default, and enterprise plans required for more)
// however also busboy is required, so needs to be a direct call to backend
var indexOf = [].indexOf;

P.svc.oaworks.deposits = {
  _index: true // store a record of all deposits
};

P.svc.oaworks.deposit = async function(params, file, dev) {
  var a, arch, as, at, author, bcc, ccm, com, creators, dep, description, ed, exists, i, improved, in_zenodo, j, k, len, len1, len2, len3, len4, m, meta, ml, n, o, perms, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref4, ref5, ref6, ref7, ref8, ref9, tk, tmpl, tos, uc, z, zn;
  if (params == null) {
    params = this.copy(this.params);
  }
  if (this.request.files) { // TODO check where these will end up - will they only work on bg with busboy?
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
  dep = {};
  ref = ['embedded', 'demo', 'pilot', 'live', 'email', 'plugin'];
  for (i = 0, len = ref.length; i < len; i++) {
    k = ref[i];
    dep[k] = params[k];
  }
  if (dep.pilot) {
    dep.pilot = Date.now();
  }
  if (dep.live === true) {
    dep.live = Date.now();
  }
  dep.name = (ref1 = file != null ? file.filename : void 0) != null ? ref1 : file != null ? file.name : void 0;
  if (params.from !== 'anonymous') {
    dep.from = params.from;
  }
  if (params.confirmed) {
    // if confirmed is true the submitter has confirmed this is the right file (and decode saves it as a "true" string, not bool, so doesn't clash in ES). If confirmed is the checksum this is a resubmit by an admin
    dep.confirmed = decodeURIComponent(params.confirmed);
  }
  dep.doi = (ref2 = params.doi) != null ? ref2 : (ref3 = params.metadata) != null ? ref3.doi : void 0;
  if ((params.metadata == null) && params.doi) {
    params.metadata = (await this.svc.oaworks.metadata(params.doi));
  }
  uc = params.config; // should exist but may not
  if (typeof params.config === 'string') {
    uc = JSON.parse(params.config);
  }
  if (!params.config && params.from) {
    uc = (await this.fetch('https://' + (dev ? 'dev.' : '') + 'api.cottagelabs.com/service/oab/deposit/config?uid=' + params.from));
  }
  perms = (await this.svc.oaworks.permissions((ref4 = params.metadata) != null ? ref4 : params.doi)); // SYP only works on DOI so far, so deposit only works if permissions can work, which requires a DOI if about a specific article
  arch = (await this.svc.oaworks.archivable(file, void 0, (dep.confirmed && dep.confirmed !== true ? dep.confirmed : void 0), params.metadata));
  if ((arch != null ? arch.archivable : void 0) && (!dep.confirmed || dep.confirmed === arch.checksum)) { // if the depositor confirms we don't deposit, we manually review - only deposit on admin confirmation (but on dev allow it)
    zn = {
      content: file.data,
      name: arch.name
    };
    zn.publish = ((ref5 = this.S.svc.oaworks) != null ? (ref6 = ref5.deposit) != null ? ref6.zenodo : void 0 : void 0) === true;
    creators = [];
    ref9 = (ref7 = (ref8 = params.metadata) != null ? ref8.author : void 0) != null ? ref7 : [];
    for (j = 0, len1 = ref9.length; j < len1; j++) {
      a = ref9[j];
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
    description += (ref10 = (ref11 = perms.best_permission) != null ? ref11.deposit_statement : void 0) != null ? ref10 : (params.metadata.doi != null ? 'The publisher\'s final version of this work can be found at https://doi.org/' + d.metadata.doi : '');
    description = description.trim();
    if (description.lastIndexOf('.') !== description.length - 1) {
      description += '.';
    }
    if (description.length) {
      description += ' ';
    }
    description += '<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.';
    meta = {
      title: (ref12 = params.metadata.title) != null ? ref12 : 'Unknown',
      description: description.trim(),
      creators: creators,
      version: arch.version === 'preprint' ? 'Submitted Version' : arch.version === 'postprint' ? 'Accepted Version' : arch.version === 'publisher pdf' ? 'Published Version' : 'Accepted Version',
      journal_title: params.metadata.journal,
      journal_volume: params.metadata.volume,
      journal_issue: params.metadata.issue,
      journal_pages: params.metadata.page
    };
    if (params.doi) {
      in_zenodo = (await this.src.zenodo.records.doi(params.doi));
      if (in_zenodo && dep.confirmed !== arch.checksum && !dev) {
        dep.zenodo = {
          already: in_zenodo.id // we don't put it in again although we could with doi as related field - but leave for review for now
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
    meta.license = (ref13 = (ref14 = perms.best_permission) != null ? ref14.licence : void 0) != null ? ref13 : 'cc-by'; // zenodo also accepts other-closed and other-nc, possibly more
    if (meta.license.indexOf('other') !== -1 && meta.license.indexOf('closed') !== -1) {
      meta.license = 'other-closed';
    }
    if (meta.license.indexOf('other') !== -1 && meta.license.indexOf('non') !== -1 && meta.license.indexOf('commercial') !== -1) {
      meta.license = 'other-nc';
    }
    if (meta.license.toLowerCase().indexOf('cc') === 0 && isNaN(parseInt(meta.license.substring(meta.license.length - 1)))) {
      meta.license += '-4.0';
    }
    try {
      if (((ref15 = perms.best_permission) != null ? ref15.embargo_end : void 0) && moment(perms.best_permission.embargo_end, 'YYYY-MM-DD').valueOf() > Date.now()) {
        meta['access_right'] = 'embargoed';
        meta['embargo_date'] = perms.best_permission.embargo_end; // check date format required by zenodo
        dep.embargo = perms.best_permission.embargo_end;
      }
    } catch (error) {}
    try {
      if ((params.metadata.published != null) && typeof params.metadata.published === 'string') {
        meta['publication_date'] = params.metadata.published;
      }
    } catch (error) {}
    if (uc) {
      if ((uc.community_ID != null) && (uc.community == null)) {
        uc.community = uc.community_ID;
      }
      if (uc.community) {
        if (uc.communities == null) {
          uc.communities = [];
        }
        ref16 = (typeof uc.community === 'string' ? uc.community.split(',') : uc.community);
        for (m = 0, len2 = ref16.length; m < len2; m++) {
          ccm = ref16[m];
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
        meta['communities'] = [];
        ref17 = uc.communities;
        for (n = 0, len3 = ref17.length; n < len3; n++) {
          com = ref17[n];
          meta.communities.push(typeof com === 'string' ? {
            identifier: com
          } : com);
        }
      }
    }
    if (tk = (dev || dep.demo ? (ref18 = this.S.svc.oaworks) != null ? (ref19 = ref18.zenodo) != null ? ref19.sandbox : void 0 : void 0 : (ref20 = this.S.svc.oaworks) != null ? (ref21 = ref20.zenodo) != null ? ref21.token : void 0 : void 0)) {
      if (!((ref22 = dep.zenodo) != null ? ref22.already : void 0)) {
        z = (await this.src.zenodo.deposition.create(meta, zn, tk));
        if (z.id) {
          dep.zenodo = {
            id: z.id,
            url: 'https://' + (dev || dep.demo ? 'sandbox.' : '') + 'zenodo.org/record/' + z.id,
            doi: ((ref23 = z.metadata) != null ? (ref24 = ref23.prereserve_doi) != null ? ref24.doi : void 0 : void 0) != null ? z.metadata.prereserve_doi.doi : void 0,
            file: (ref25 = (ref26 = z.uploaded) != null ? (ref27 = ref26.links) != null ? ref27.download : void 0 : void 0) != null ? ref25 : (ref28 = z.uploaded) != null ? (ref29 = ref28.links) != null ? ref29.download : void 0 : void 0
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
  dep.version = arch != null ? arch.version : void 0;
  if (!dep.type && params.from && (!dep.embedded || (dep.embedded.indexOf('oa.works') === -1 && dep.embedded.indexOf('openaccessbutton.org') === -1 && dep.embedded.indexOf('shareyourpaper.org') === -1))) {
    dep.type = params.redeposit ? 'redeposit' : file ? 'forward' : 'dark';
  }
  if (dep.doi && !dep.error) {
    if (dep.type == null) {
      dep.type = 'review';
    }
    dep.url = typeof params.redeposit === 'string' ? params.redeposit : params.url ? params.url : void 0;
    if (!(exists = (await this.svc.oaworks.deposits('doi:"' + dep.doi + '"' + (dep.from ? ' AND from:"' + dep.from + '"' : ''))))) {
      dep.createdAt = Date.now();
      this.waitUntil(this.svc.oaworks.deposits(dep));
    } else {
      improved = false;
      if (dep.name && !exists.name) {
        improved = true;
        exists.name = dep.name;
      }
      if (dep.confirmed && (!exists.confirmed || (exists.confirmed === 'true' && dep.confirmed !== 'true'))) {
        improved = true;
        exists.confirmed = dep.confirmed;
      }
      if (typeof exists.type === 'string') {
        exists.type = [exists.type];
      }
      if (ref30 = dep.type, indexOf.call(exists.type, ref30) < 0) {
        improved = true;
        exists.type.push(dep.type);
      }
      if ((dep.zenodo != null) && (dep.zenodo.already == null) && !exists.zenodo) {
        improved = true;
        exists.zenodo = dep.zenodo;
      }
      if (improved) {
        exists.updatedAt = Date.now();
        if (exists.duplicate == null) {
          exists.duplicate = 0;
        }
        exists.duplicate += 1;
        this.waitUntil(this.svc.oaworks.deposits(exists));
      }
      dep.duplicate = (ref31 = exists.duplicate) != null ? ref31 : 1;
    }
    if ((dep.type !== 'review' || (file != null)) && (arch != null ? arch.archivable : void 0) !== false && !dep.duplicate) { // so when true or when undefined if no file is given
      bcc = ['joe@oa.works'];
      tos = [];
      if (typeof (uc != null ? uc.owner : void 0) === 'string' && uc.owner.indexOf('@') !== -1) {
        tos.push(uc.owner);
      } else if (uc.email) {
        tos.push(uc.email);
      }
      if (tos.length === 0) {
        tos = this.copy(bcc);
        bcc = [];
      }
      ed = this.copy(dep);
      ed.metadata = (ref32 = params.metadata) != null ? ref32 : {};
      as = [];
      ref34 = (ref33 = ed.metadata.author) != null ? ref33 : [];
      for (o = 0, len4 = ref34.length; o < len4; o++) {
        author = ref34[o];
        if (author.family) {
          as.push((author.given ? author.given + ' ' : '') + author.family);
        }
      }
      ed.metadata.author = as;
      ed.adminlink = (ed.embedded ? ed.embedded : 'https://shareyourpaper.org' + (ed.metadata.doi ? '/' + ed.metadata.doi : ''));
      ed.adminlink += ed.adminlink.includes('?') ? '&' : '?';
      if ((arch != null ? arch.checksum : void 0) != null) {
        ed.confirmed = encodeURIComponent(arch.checksum);
        ed.adminlink += 'confirmed=' + ed.confirmed + '&';
      }
      ed.adminlink += 'email=' + ed.email;
      tmpl = (await this.svc.oaworks.templates(dep.type + '_deposit.html'));
      tmpl = tmpl.content;
      ml = {
        from: 'deposits@oa.works',
        to: tos,
        template: tmpl,
        vars: ed,
        subject: (ref35 = sub.subject) != null ? ref35 : dep.type + ' deposit',
        html: sub.content
      };
      if (bcc && bcc.length) { // passing undefined to mail seems to cause errors, so only set if definitely exists
        ml.bcc = bcc;
      }
      if (file) {
        ml.attachments = [
          {
            filename: (ref36 = file.filename) != null ? ref36 : file.name,
            content: file.data
          }
        ];
      }
      this.waitUntil(this.mail(ml));
    }
  }
  return dep;
};

P.svc.oaworks.deposit._bg = true;

P.svc.oaworks.archivable = async function(file, url, confirmed, meta = {}) {
  var _clean, a, af, an, authorsfound, content, contentsmall, f, fd, ft, i, inc, j, l, len, len1, len2, lowercontentsmall, lowercontentstart, ls, m, matched, re, ref, ref1, ref10, ref11, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, sc, wtm, wts;
  if (this.request.files) { // TODO check where these will end up - will they only work on bg with busboy?
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
    if (file.data) {
      if (f.format === 'pdf') {
        try {
          content = (await this.convert.pdf2txt(file.data));
        } catch (error) {}
      }
      if ((content == null) && (f.format != null) && (this.convert[f.format + '2txt'] != null)) {
        try {
          content = (await this.convert[f.format + '2txt'](file.data));
        } catch (error) {}
      }
      if (content == null) {
        content = (await this.convert.file2txt(file.data, {
          name: file.name
        }));
      }
      if (content == null) {
        fd = file.data;
        if (typeof file.data !== 'string') {
          try {
            fd = file.data.toString();
          } catch (error) {}
        }
        try {
          if (fd.startsWith('<html')) {
            content = (await this.convert.html2txt(fd));
          } else if (file.data.startsWith('<xml')) {
            content = (await this.convert.xml2txt(fd));
          }
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
      f.error = (ref = file.error) != null ? ref : 'Could not extract any content';
    }
  } else {
    _clean = function(str) {
      return str.toLowerCase().replace(/[^a-z0-9\/\.]+/g, "").replace(/\s\s+/g, ' ').trim();
    };
    contentsmall = content.length < 20000 ? content : content.substring(0, 6000) + content.substring(content.length - 6000, content.length);
    lowercontentsmall = contentsmall.toLowerCase();
    lowercontentstart = _clean(lowercontentsmall.length < 6000 ? lowercontentsmall : lowercontentsmall.substring(0, 6000));
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
      f.same_paper_evidence.doi_match = meta.doi && lowercontentstart.indexOf(_clean(meta.doi)) !== -1 ? true : false; // should have the doi in it near the front
    } catch (error) {}
    try {
      //if content and not f.same_paper_evidence.doi_match and not meta.title?
      //  meta = API.service.oab.metadata undefined, meta, content # get at least title again if not already tried to get it, and could not find doi in the file
      f.same_paper_evidence.title_match = meta.title && lowercontentstart.replace(/\./g, '').includes(_clean(meta.title.replace(/ /g, '').replace(/\./g, ''))) ? true : false;
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
        ref1 = meta.author;
        for (i = 0, len = ref1.length; i < len; i++) {
          a = ref1[i];
          if (f.same_paper_evidence.author_match === true) {
            break;
          } else {
            try {
              an = ((ref2 = (ref3 = (ref4 = (ref5 = a.last) != null ? ref5 : a.lastname) != null ? ref4 : a.family) != null ? ref3 : a.surname) != null ? ref2 : a.name).trim().split(',')[0].split(' ')[0];
              af = ((ref6 = (ref7 = (ref8 = a.first) != null ? ref8 : a.firstname) != null ? ref7 : a.given) != null ? ref6 : a.name).trim().split(',')[0].split(' ')[0];
              inc = lowercontentstart.indexOf(_clean(an));
              if (an.length > 2 && af.length > 0 && inc !== -1 && lowercontentstart.substring(inc - 20, inc + an.length + 20).includes(_clean(af))) {
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
      ref9 = ['doc', 'tex', 'pdf', 'htm', 'xml', 'txt', 'rtf', 'odf', 'odt', 'page'];
      for (j = 0, len1 = ref9.length; j < len1; j++) {
        ft = ref9[j];
        if (f.format.indexOf(ft) !== -1) {
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
      ref10 = (await this.src.google.sheets((this.S.dev ? '1XA29lqVPCJ2FQ6siLywahxBTLFaDCZKaN5qUeoTuApg' : '10DNDmOG19shNnuw6cwtCpK-sBnexRCCtD4WnxJx_DPQ')));
      // dev https://docs.google.com/spreadsheets/d/1XA29lqVPCJ2FQ6siLywahxBTLFaDCZKaN5qUeoTuApg/edit#gid=0
      // live https://docs.google.com/spreadsheets/d/10DNDmOG19shNnuw6cwtCpK-sBnexRCCtD4WnxJx_DPQ/edit#gid=0
      for (m = 0, len2 = ref10.length; m < len2; m++) {
        l = ref10[m];
        try {
          f.version_evidence.strings_checked += 1;
          wts = l.whattosearch;
          if (wts.includes('<<') && wts.includes('>>')) {
            wtm = wts.split('<<')[1].split('>>')[0];
            if (meta[wtm.toLowerCase()] != null) {
              wts = wts.replace('<<' + wtm + '>>', meta[wtm.toLowerCase()]);
            }
          }
          matched = false;
          if (l.howtosearch === 'string') {
            matched = (l.wheretosearch === 'file' && contentsmall.indexOf(wts) !== -1) || (l.wheretosearch !== 'file' && (((meta.title != null) && meta.title.indexOf(wts) !== -1) || ((f.name != null) && f.name.indexOf(wts) !== -1))) ? true : false;
          } else {
            re = new RegExp(wts, 'gium');
            matched = (l.wheretosearch === 'file' && lowercontentsmall.match(re) !== null) || (l.wheretosearch !== 'file' && (((meta.title != null) && meta.title.match(re) !== null) || ((f.name != null) && f.name.match(re) !== null))) ? true : false;
          }
          if (matched) {
            sc = (ref11 = l.score) != null ? ref11 : l.score_value;
            if (typeof sc === 'string') {
              try {
                sc = parseInt(sc);
              } catch (error) {}
            }
            if (typeof sc !== 'number') {
              sc = 1;
            }
            if (l.whatitindicates === 'publisher pdf') {
              f.version_evidence.score += sc;
            } else {
              f.version_evidence.score -= sc;
            }
            f.version_evidence.strings_matched.push({
              indicates: l.whatitindicates,
              found: l.howtosearch + ' ' + wts,
              in: l.wheretosearch,
              score_value: sc
            });
          }
        } catch (error) {}
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
      ls = (await this.svc.lantern.licence(void 0, void 0, lowercontentsmall)); // check lantern for licence info in the file content
      if ((ls != null ? ls.licence : void 0) != null) {
        f.licence = ls.licence;
        f.licence_evidence = {
          string_match: ls.match
        };
      }
      f.lantern = ls;
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
        f.archivable_reason = 'Since the file is not a PDF, we assume it is a Postprint.';
      }
      if (!f.archivable && (f.licence != null) && f.licence.toLowerCase().startsWith('cc')) {
        f.archivable = true;
        f.archivable_reason = 'It appears this file contains a ' + f.lantern.licence + ' licence statement. Under this licence the article can be archived';
      }
      if (!f.archivable) {
        if (f.version === 'publishedVersion') {
          f.archivable_reason = 'The file given is a Publisher PDF, and only postprints are allowed';
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
  return f;
};

var indexOf = [].indexOf;

P.svc.oaworks.metadata = async function(doi) {
  var res;
  res = (await this.svc.oaworks.find(doi)); // may not be a DOI, but most likely thing
  return res != null ? res.metadata : void 0;
};

P.svc.oaworks.find = async function(options, metadata = {}, content) {
  var _ill, _metadata, _permissions, _searches, bct, bong, dd, dps, i, len, mct, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, ref8, res, uo;
  res = {};
  _metadata = async(input) => {
    var ct, k;
    ct = (await this.svc.oaworks.citation(input));
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
    options = {
      doi: options
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
    if (options.find.indexOf('10.') === 0 && options.find.indexOf('/') !== -1) {
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
    if (options.url.indexOf('/10.') !== -1) {
      // we don't use a regex to try to pattern match a DOI because people often make mistakes typing them, so instead try to find one
      // in ways that may still match even with different expressions (as long as the DOI portion itself is still correct after extraction we can match it)
      dd = '10.' + options.url.split('/10.')[1].split('&')[0].split('#')[0];
      if (dd.indexOf('/') !== -1 && dd.split('/')[0].length > 6 && dd.length > 8) {
        dps = dd.split('/');
        if (dps.length > 2) {
          dd = dps.join('/');
        }
        if (metadata.doi == null) {
          metadata.doi = dd;
        }
      }
    }
    if (options.url.replace('doi:', '').replace('doi.org/', '').trim().indexOf('10.') === 0) {
      if (metadata.doi == null) {
        metadata.doi = options.url.replace('doi:', '').replace('doi.org/', '').trim();
      }
      options.url = 'https://doi.org/' + metadata.doi;
    } else if (options.url.toLowerCase().indexOf('pmc') === 0) {
      if (metadata.pmcid == null) {
        metadata.pmcid = options.url.toLowerCase().replace('pmcid', '').replace('pmc', '');
      }
      options.url = 'http://europepmc.org/articles/PMC' + metadata.pmcid;
    } else if (options.url.replace(/pmid/i, '').replace(':', '').length < 10 && options.url.indexOf('.') === -1 && !isNaN(parseInt(options.url.replace(/pmid/i, '').replace(':', '').trim()))) {
      if (metadata.pmid == null) {
        metadata.pmid = options.url.replace(/pmid/i, '').replace(':', '').trim();
      }
      options.url = 'https://www.ncbi.nlm.nih.gov/pubmed/' + metadata.pmid;
    } else if ((metadata.title == null) && options.url.indexOf('http') !== 0) {
      if (options.url.indexOf('{') !== -1 || ((ref2 = options.url.replace('...', '').match(/\./gi)) != null ? ref2 : []).length > 3 || ((ref3 = options.url.match(/\(/gi)) != null ? ref3 : []).length > 2) {
        options.citation = options.url;
      } else {
        metadata.title = options.url;
      }
    }
    if (options.url.indexOf('http') !== 0 || options.url.indexOf('.') === -1) {
      delete options.url;
    }
  }
  if (typeof options.title === 'string' && (options.title.indexOf('{') !== -1 || ((ref4 = options.title.replace('...', '').match(/\./gi)) != null ? ref4 : []).length > 3 || ((ref5 = options.title.match(/\(/gi)) != null ? ref5 : []).length > 2)) {
    options.citation = options.title; // titles that look like citations
    delete options.title;
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
  if (typeof metadata.doi !== 'string' || metadata.doi.indexOf('10.') !== 0) {
    delete metadata.doi;
  }
  // switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if (!metadata.title && content && typeof options.url === 'string' && (options.url.indexOf('alma.exlibrisgroup.com') !== -1 || options.url.indexOf('/exlibristest') !== -1)) {
    delete options.url;
  }
  if (options.demo != null) {
    // set a demo tag in certain cases
    // e.g. for instantill/shareyourpaper/other demos - dev and live demo accounts
    res.demo = options.demo;
  }
  if ((metadata.doi === '10.1234/567890' || ((metadata.doi != null) && metadata.doi.indexOf('10.1234/oab-syp-') === 0)) || metadata.title === 'Engineering a Powerfully Simple Interlibrary Loan Experience with InstantILL' || ((ref7 = options.from) === 'qZooaHWRz9NLFNcgR' || ref7 === 'eZwJ83xp3oZDaec86')) {
    if (res.demo == null) {
      res.demo = true;
    }
  }
  if (res.demo) { // don't save things coming from the demo accounts into the catalogue later
    if (res.test == null) {
      res.test = true;
    }
  }
  _searches = async() => {
    var _crd, _fatcat, _oad, cr, epmc, mag, ref8, scraped;
    if (((content != null) || (options.url != null)) && !(metadata.doi || (metadata.pmid != null) || (metadata.pmcid != null) || (metadata.title != null))) {
      scraped = (await this.svc.oaworks.scrape(content != null ? content : options.url));
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
        if (!metadata.doi) {
          mag = (await this.src.microsoft.graph(metadata.title));
          if (mag != null ? mag.PaperTitle : void 0) {
            await _metadata(mag);
          }
        }
        if (!metadata.doi && (epmc == null)) { // run this only if we don't find in our own stores
          epmc = (await this.src.epmc.title(metadata.title));
          await _metadata(epmc);
        }
      }
    }
    if (metadata.doi) {
      _fatcat = async() => {
        var f, fat, fu, i, j, len, len1, ref10, ref9;
        fat = (await this.src.fatcat(metadata.doi));
        if ((fat != null ? fat.files : void 0) != null) {
          ref9 = fat.files;
          for (i = 0, len = ref9.length; i < len; i++) {
            f = ref9[i];
            // there are also hashes and revision IDs, but without knowing details about which is most recent just grab the first
            // looks like the URLs are timestamped, and looks like first is most recent, so let's just assume that.
            if (f.mimetype.toLowerCase().indexOf('pdf') !== -1 && f.state === 'active') { // presumably worth knowing...
              ref10 = f.urls;
              for (j = 0, len1 = ref10.length; j < len1; j++) {
                fu = ref10[j];
                if (fu.url && fu.rel === 'webarchive') { // would we want the web or the webarchive version?
                  res.url = fu.url;
                  break;
                }
              }
            }
          }
        }
        return true;
      };
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
      await Promise.all([
        _oad(),
        _crd() // _fatcat(), 
      ]);
    }
    return true;
  };
  await _searches();
  // if nothing useful can be found and still only have title try using bing - or drop this ability?
  // TODO what to do if this finds anything? re-call the whole find?
  if (!metadata.doi && !content && !options.url && (typeof epmc === "undefined" || epmc === null) && metadata.title && metadata.title.length > 8 && metadata.title.split(' ').length > 1) {
    try {
      mct = unidecode(metadata.title.toLowerCase()).replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
      bong = (await this.src.microsoft.bing.search(mct));
      if (bong != null ? bong.data : void 0) {
        bct = unidecode(bong.data[0].name.toLowerCase()).replace('(pdf)', '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
        if (mct.replace(/ /g, '').indexOf(bct.replace(/ /g, '')) === 0) { //and not await @svc.oaworks.blacklist bong.data[0].url
          // if the URL is usable and tidy bing title is a partial match to the start of the provided title, try using it
          options.url = bong.data[0].url.replace(/"/g, '');
          if (typeof options.url === 'string' && options.url.indexOf('pubmed.ncbi') !== -1) {
            metadata.pmid = options.url.replace(/\/$/, '').split('/').pop();
          }
          if (typeof options.url === 'string' && options.url.indexOf('/10.') !== -1) {
            if (metadata.doi == null) {
              metadata.doi = '10.' + options.url.split('/10.')[1];
            }
          }
        }
      }
      if (metadata.doi || metadata.pmid || options.url) {
        await _searches(); // run again if anything more useful found
      }
    } catch (error) {}
  }
  _ill = async() => {
    var ref8;
    if ((metadata.doi || (metadata.title && metadata.title.length > 8 && metadata.title.split(' ').length > 1)) && (options.from || (options.config != null)) && (options.plugin === 'instantill' || options.ill === true)) {
      try {
        if (res.ill == null) {
          res.ill = {
            subscription: (await this.svc.oaworks.ill.subscription((ref8 = options.config) != null ? ref8 : options.from, metadata))
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
        res.permissions = (await this.svc.oaworks.permissions(metadata, (ref8 = options.config) != null ? ref8.ror : void 0, false));
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
P.svc.oaworks.citation = function(citation) {
  var a, aff, ak, au, bt, cf, clc, cn, i, j, k, key, l, len, len1, len2, len3, len4, len5, len6, len7, len8, len9, m, mn, n, o, p, pt, pts, q, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref38, ref39, ref4, ref40, ref41, ref42, ref43, ref44, ref45, ref46, ref47, ref48, ref49, ref5, ref50, ref51, ref52, ref53, ref54, ref55, ref56, ref57, ref6, ref7, ref8, ref9, res, rmn, rt, s, sy, t, u, v;
  res = {};
  try {
    if (citation == null) {
      citation = (ref = this.params.citation) != null ? ref : this.params;
    }
  } catch (error) {}
  if (typeof citation === 'string' && (citation.indexOf('{') === 0 || citation.indexOf('[') === 0)) {
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
    try {
      if (res.abstract) {
        res.abstract = this.convert.html2txt(res.abstract).replace(/\n/g, ' ').replace('Abstract ', '');
      }
    } catch (error) {}
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
            res.published = rt.indexOf('T') !== -1 ? rt.split('T')[0] : rt;
            res.published = res.published.replace(/\//g, '-').replace(/-(\d)-/g, "-0$1-").replace(/-(\d)$/, "-0$1");
            if (res.published.indexOf('-') === -1) {
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
          if (a.label === 'OPEN ACCESS' && a.URL && a.URL.indexOf('creativecommons') !== -1) {
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
          if (l.URL && l.URL.indexOf('creativecommons') !== -1 && (!res.licence || res.licence.indexOf('creativecommons') === -1)) {
            if (res.licence == null) {
              res.licence = l.URL;
            }
          }
        }
      }
    }
    if (typeof res.licence === 'string' && res.licence.indexOf('/licenses/') !== -1) {
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
        if (((ref56 = cf.availabilityCode.toLowerCase()) === 'oa' || ref56 === 'f') && (!res.url || (cf.documentStyle === 'pdf' && res.url.indexOf('pdf') === -1))) {
          res.url = cf.url;
        }
      }
    }
  } else if (typeof citation === 'string') {
    try {
      citation = citation.replace(/citation\:/gi, '').trim();
      if (citation.indexOf('title') !== -1) {
        citation = citation.split('title')[1].trim();
      }
      citation = citation.replace(/^"/, '').replace(/^'/, '').replace(/"$/, '').replace(/'$/, '');
      if (citation.indexOf('doi:') !== -1) {
        res.doi = citation.split('doi:')[1].split(',')[0].split(' ')[0].trim();
      }
      if (citation.indexOf('doi.org/') !== -1) {
        res.doi = citation.split('doi.org/')[1].split(',')[0].split(' ')[0].trim();
      }
      if (!res.doi && citation.indexOf('http') !== -1) {
        res.url = 'http' + citation.split('http')[1].split(' ')[0].trim();
      }
      try {
        if (citation.indexOf('|') !== -1 || citation.indexOf('}') !== -1) {
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
          if (res.title.indexOf('(') === -1 || res.title.indexOf(')') < res.title.indexOf('(')) {
            res.title = res.title.replace(')', '');
          }
          if (res.title.indexOf('.') < 3) {
            res.title = res.title.replace('.', '');
          }
          if (res.title.indexOf(',') < 3) {
            res.title = res.title.replace(',', '');
          }
          res.title = res.title.trim();
          if (res.title.indexOf('.') !== -1) {
            res.title = res.title.split('.')[0];
          } else if (res.title.indexOf(',') !== -1) {
            res.title = res.title.split(',')[0];
          }
        }
      } catch (error) {}
      if (res.title) {
        try {
          bt = citation.split(res.title)[0];
          if (res.year && bt.indexOf(res.year) !== -1) {
            bt = bt.split(res.year)[0];
          }
          if (res.url && bt.indexOf(res.url) > 0) {
            bt = bt.split(res.url)[0];
          }
          if (res.url && bt.indexOf(res.url) === 0) {
            bt = bt.replace(res.url);
          }
          if (res.doi && bt.indexOf(res.doi) === 0) {
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
            if (bt.indexOf(',') !== -1) {
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
          if (res.url && rmn.indexOf(res.url) !== -1) {
            rmn = rmn.replace(res.url);
          }
          if (res.doi && rmn.indexOf(res.doi) !== -1) {
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
            if (rmn.indexOf(',') !== -1) {
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
          if (res.url && rmn.indexOf(res.url) !== -1) {
            rmn = rmn.replace(res.url);
          }
          if (res.doi && rmn.indexOf(res.doi) !== -1) {
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
            if (rmn.indexOf('retrieved') !== -1) {
              rmn = rmn.split('retrieved')[0];
            }
            if (rmn.indexOf('Retrieved') !== -1) {
              rmn = rmn.split('Retrieved')[0];
            }
            res.volume = rmn;
            if (res.volume.indexOf('(') !== -1) {
              res.volume = res.volume.split('(')[0];
              res.volume = res.volume.trim();
              try {
                res.issue = rmn.split('(')[1].split(')')[0];
                res.issue = res.issue.trim();
              } catch (error) {}
            }
            if (res.volume.indexOf(',') !== -1) {
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
              if (res.issue.indexOf(',') !== -1) {
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
                if (rmn.indexOf('retriev') !== -1) {
                  rmn = rmn.split('retriev')[0];
                }
                if (rmn.indexOf('Retriev') !== -1) {
                  rmn = rmn.split('Retriev')[0];
                }
                if (res.url && rmn.indexOf(res.url) !== -1) {
                  rmn = rmn.split(res.url)[0];
                }
                if (res.doi && rmn.indexOf(res.doi) !== -1) {
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
      if (!res.author && citation.indexOf('et al') !== -1) {
        cn = citation.split('et al')[0].trim();
        if (citation.indexOf(cn) === 0) {
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
          if (clc.indexOf('vol') !== -1) {
            res.volume = clc.split('vol')[1].split(',')[0].split('(')[0].split('.')[0].split(' ')[0].trim();
          }
          if (!res.issue && clc.indexOf('iss') !== -1) {
            res.issue = clc.split('iss')[1].split(',')[0].split('.')[0].split(' ')[0].trim();
          }
          if (!res.pages && clc.indexOf('page') !== -1) {
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
P.svc.oaworks.availability = async function(params, v2) {
  var afnd, base, qry, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref3, ref4, ref5, ref6, ref7, ref8, ref9, request, resp, rq;
  if (params == null) {
    params = this.copy(this.params);
  }
  delete this.params.dom;
  if (params.availability) {
    if (params.availability.startsWith('10.') && params.availability.indexOf('/') !== -1) {
      params.doi = params.availability;
    } else if (params.availability.indexOf(' ') !== -1) {
      params.title = params.availability;
    } else {
      params.id = params.availability;
    }
    delete params.availability;
  }
  if (Array.isArray(params.url)) {
    params.url = params.url[0];
  }
  if (!params.test && params.url && false) { //await @svc.oaworks.blacklist params.url
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
      afnd.v2 = (await this.svc.oaworks.find(params));
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

P.svc.oaworks.availability._hide = true;

// this should default to a search of ILLs as well... with a restrict
// restrict = @auth.role('openaccessbutton.admin') and this.queryParams.all then [] else [{term:{from:@user?._id}}]
var indexOf = [].indexOf;

P.svc.oaworks.ill = async function(opts) { // only worked on POST with optional auth
  var a, atidy, ats, authors, config, first, i, j, len, len1, m, o, ordered, r, ref, ref1, ref2, ref3, ref4, su, tmpl, vars;
  if (opts == null) {
    opts = this.copy(this.params);
    if (opts.ill) {
      opts.doi = opts.ill;
      delete opts.ill;
    }
  }
  if (opts.metadata == null) {
    opts.metadata = (await this.svc.oaworks.metadata(opts));
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
  tmpl = (await this.svc.oaworks.templates('instantill_create.html'));
  tmpl = tmpl.content;
  if (!opts.forwarded && !opts.resolved && (config.email || opts.email)) {
    this.mail({
      svc: 'oaworks',
      vars: vars,
      template: tmpl,
      to: (ref4 = config.email) != null ? ref4 : opts.email,
      from: "InstantILL <InstantILL@openaccessbutton.org>",
      subject: "ILL request " + opts._id
    });
  }
  tmpl = tmpl.replace(/Dear.*?\,/, 'Dear Joe, here is a copy of what was just sent:');
  this.waitUntil(this.mail({
    svc: 'oaworks',
    vars: vars,
    template: tmpl,
    from: "InstantILL <InstantILL@openaccessbutton.org>",
    subject: "ILL CREATED " + opts._id,
    to: 'mark@cottagelabs.com' // ['joe@openaccessbutton.org']
  }));
  return opts;
};

P.svc.oaworks.ill._index = true;

P.svc.oaworks.ill.collect = async function(params) {
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

P.svc.oaworks.ill.collect._hide = true;

P.svc.oaworks.ill.openurl = async function(config, meta) {
  var author, d, defaults, i, k, len, nfield, ref, ref1, ref2, url, v;
  // Will eventually redirect after reading openurl params passed here, somehow. 
  // For now a POST of metadata here by a user with an open url registered will build their openurl
  if (config == null) {
    config = (ref = this.params.config) != null ? ref : {};
  }
  if (meta == null) {
    meta = (ref1 = this.params.meta) != null ? ref1 : (await this.svc.oaworks.metadata());
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

P.svc.oaworks.ill.subscription = async function(config, meta) {
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
      console.log(config.doi);
      meta = (await this.svc.oaworks.metadata(config.doi));
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
    openurl = (await this.svc.oaworks.ill.openurl(config, meta));
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
          pg = url.indexOf('.xml.serialssolutions') !== -1 || url.indexOf('sfx.response_type=simplexml') !== -1 || url.indexOf('response_type=xml') !== -1 ? (await this.fetch(url)) : (await this.puppet(url));
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
                  return res;
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
                  return res;
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
                return res;
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
                  return res;
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
            //  return res
            if (spg.indexOf('ss_noresults') === -1) {
              try {
                surl = url.split('?')[0] + '?ShowSupressedLinks' + pg.split('?ShowSupressedLinks')[1].split('">')[0];
                npg = (await this.puppet(surl)); // would this still need proxy?
                if (npg.indexOf('ArticleCL') !== -1 && npg.split('DatabaseCL')[0].indexOf('href="./log') !== -1) {
                  res.url = surl.split('?')[0] + npg.split('ArticleCL')[1].split('DatabaseCL')[0].split('href="')[1].split('">')[0].replace(/&amp;/g, '&');
                  res.findings.serials = res.url;
                  if (res.url != null) {
                    if (res.url.indexOf('getitnow') === -1) {
                      res.found = 'serials';
                      return res;
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
            return res;
          }
        }
      }
    }
  }
  return res;
};

var indexOf = [].indexOf;

P.svc.oaworks.permissions = async function(meta, ror, getmeta, oadoi, crossref) { // oadoi and crossref are just ways for other functions to pass in oadoi or crossref record objects to save looking them up again
  var _format, _getmeta, _score, af, altoa, doa, fz, haddoi, i, inisn, issns, j, key, l, len, len1, len2, len3, len4, len5, len6, len7, len8, longest, lvs, m, msgs, n, o, overall_policy_restriction, p, pb, perms, pisoa, ps, qr, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref4, ref5, ref6, ref7, ref8, ref9, ro, rors, rp, rr, rs, rw, t, tr, u, v, vl, w, wp;
  overall_policy_restriction = false;
  haddoi = false;
  _format = async function(rec) {
    var a, d, em, eph, fst, i, j, len, len1, len2, m, ph, pt, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, swaps;
    if (haddoi && rec.embargo_months && (meta.published || meta.year)) {
      em = new Date(Date.parse((ref = meta.published) != null ? ref : meta.year + '-01-01'));
      em = new Date(em.setMonth(em.getMonth() + rec.embargo_months));
      rec.embargo_end = em.toISOString().split('T')[0];
    }
    if (rec.embargo_end === '') {
      delete rec.embargo_end;
    }
    rec.copyright_name = rec.copyright_owner === 'publisher' ? (typeof rec.issuer.parent_policy === 'string' ? rec.issuer.parent_policy : typeof rec.issuer.id === 'string' ? rec.issuer.id : rec.issuer.id[0]) : (ref1 = rec.copyright_owner) === 'journal' || ref1 === 'affiliation' ? (ref2 = meta.journal) != null ? ref2 : '' : (haddoi && rec.copyright_owner && rec.copyright_owner.toLowerCase().includes('author')) && (meta.author != null) && meta.author.length && (meta.author[0].name || meta.author[0].family) ? ((ref3 = meta.author[0].name) != null ? ref3 : meta.author[0].family) + (meta.author.length > 1 ? ' et al' : '') : '';
    if (((ref4 = rec.copyright_name) === 'publisher' || ref4 === 'journal') && (crossref || meta.doi || ((ref5 = rec.provenance) != null ? ref5.example : void 0))) {
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
      rec.meta.source = 'https://' + (S.dev ? 'dev.api.cottagelabs.com/svc/oaworks/permissions/' : 'api.openaccessbutton.org/permissions/') + (rec.issuer.type ? rec.issuer.type + '/' : '') + rec._id;
    }
    if (typeof ((ref13 = rec.issuer) != null ? ref13.has_policy : void 0) === 'string' && ((ref14 = rec.issuer.has_policy.toLowerCase().trim()) === 'not publisher' || ref14 === 'takedown')) {
      // find out if this should be enacted if it is the case for any permission, or only the best permission
      overall_policy_restriction = rec.issuer.has_policy;
    }
    ref15 = ['_id', 'permission_required', 'createdAt', 'updatedAt', 'created_date', 'updated_date'];
    for (m = 0, len2 = ref15.length; m < len2; m++) {
      d = ref15[m];
      delete rec[d];
    }
    try {
      delete rec.issuer.updatedAt;
    } catch (error) {}
    return rec;
  };
  _score = (rec) => {
    var ref, ref1, ref2, ref3, ref4, ref5, score;
    score = rec.can_archive ? 1000 : 0;
    if (((ref = rec.provenance) != null ? ref.oa_evidence : void 0) === 'In DOAJ') {
      score += 1000;
    }
    if (rec.requirements != null) {
      // TODO what about cases where the requirement is met?
      // and HOW is requirement met? we search ROR against issuer, but how does that match with author affiliation?
      // should we even be searching for permissions by ROR, or only using it to calculate the ones we find by some other means?
      // and if it is not met then is can_archive worth anything?
      score -= 10;
    } else {
      score += rec.version === 'publishedVersion' ? 200 : rec.version === 'acceptedVersion' ? 100 : 0;
    }
    if ((rec.licences != null) && rec.licences.length) {
      score -= 5;
    }
    score += ((ref1 = rec.issuer) != null ? ref1.type : void 0) === 'journal' ? 5 : ((ref2 = rec.issuer) != null ? ref2.type : void 0) === 'publisher' ? 4 : ((ref3 = rec.issuer) != null ? ref3.type : void 0) === 'university' ? 3 : (ref4 = (ref5 = rec.issuer) != null ? ref5.type : void 0, indexOf.call('article', ref4) >= 0) ? 2 : 0;
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
  if ((meta != null ? meta.permissions : void 0) != null) {
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
  if (JSON.stringify(meta) === '{}' || (meta.issn && !JSON.stringify(meta.issn).includes('-')) || (meta.doi && (typeof meta.doi !== 'string' || !meta.doi.startsWith('10.') || !meta.doi.includes('/')))) {
    return {
      body: 'No valid DOI, ISSN, or ROR provided',
      status: 404
    };
  }
  
  // NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  // we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = async() => {
    var mk, psm, ref, results, rsm;
    psm = this.copy(meta);
    if (JSON.stringify(psm) !== '{}') {
      results = [];
      for (mk in rsm = (ref = crossref != null ? crossref : (await this.svc.oaworks.metadata(meta.doi))) != null ? ref : {}) {
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
        meta.doi = (await this.src.crossref.journals.doi(issns));
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
    rs = (await this.svc.oaworks.permissions.affiliations('issuer.id:"' + meta.ror.join('" OR issuer.id:"') + '"'));
    if (!(rs != null ? (ref4 = rs.hits) != null ? ref4.total : void 0 : void 0)) { // look up the ROR, get the ISO 3166-1 alpha-2 code, search affiliations for that
      try {
        rw = (await this.src.ror(meta.ror.length === 1 ? meta.ror[0] : 'id:"' + meta.ror.join(" OR id:") + '"'));
        if ((ref5 = rw.hits) != null ? ref5.total : void 0) {
          rw = rw.hits.hits[0]._source;
        }
        if (rw.country.country_code) {
          rs = (await this.svc.oaworks.permissions.affiliations('issuer.id:"' + rw.country.country_code + '"'));
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
  if (issns.length) {
    qr = issns.length ? 'issuer.id:"' + issns.join('" OR issuer.id:"') + '"' : '';
    ps = (await this.svc.oaworks.permissions.journals(qr));
    ref11 = (ref9 = ps != null ? (ref10 = ps.hits) != null ? ref10.hits : void 0 : void 0) != null ? ref9 : [];
    for (m = 0, len2 = ref11.length; m < len2; m++) {
      p = ref11[m];
      rp = (await _format(p._source));
      rp.score = (await _score(rp));
      perms.all_permissions.push(rp);
    }
  }
  if (issns.length) {
    af = (await this.svc.oaworks.journal('ISSN:"' + issns.join('" OR ISSN:"') + '"', 1));
  }
  if (meta.publisher) {
    qr = 'issuer.id:"' + meta.publisher + '"'; // how exact/fuzzy can this be
    ps = (await this.svc.oaworks.permissions.publishers(qr));
    ref14 = (ref12 = ps != null ? (ref13 = ps.hits) != null ? ref13.hits : void 0 : void 0) != null ? ref12 : [];
    for (n = 0, len3 = ref14.length; n < len3; n++) {
      p = ref14[n];
      rp = (await _format(p._source));
      rp.score = (await _score(rp));
      perms.all_permissions.push(rp);
    }
    if (af == null) {
      af = (await this.svc.oaworks.journal('publisher:"' + meta.publisher + '"', 1));
      if (af == null) {
        fz = (await this.svc.oaworks.journal('publisher:"' + meta.publisher.split(' ').join('" AND publisher:"') + '"', 1));
        if ((fz != null ? fz.publisher : void 0) === meta.publisher) {
          af = fz;
        } else if (fz != null ? fz.publisher : void 0) {
          lvs = (await this.tdm.levenshtein(fz.publisher, meta.publisher));
          longest = lvs.length.a > lvs.length.b ? lvs.length.a : lvs.length.b;
          if (lvs.distance < 5 || longest / lvs.distance > 10) {
            af = fz;
          }
        }
      }
    }
  }
  if ((af != null ? af.publisher : void 0) && !af.indoaj) {
    pisoa = ((await this.svc.oaworks.permissions.publishers.oa(af.publisher))).oa;
  }
  if ((af != null ? af.indoaj : void 0) || pisoa) {
    altoa = {
      can_archive: true,
      version: 'publishedVersion',
      versions: ['publishedVersion'],
      licence: void 0,
      licence_terms: "",
      licences: [],
      locations: ['institutional repository'],
      embargo_months: void 0,
      issuer: {
        type: 'journal',
        has_policy: 'yes',
        id: af.issn
      },
      meta: {
        creator: ['joe+doaj@openaccessbutton.org'],
        contributors: ['joe+doaj@openaccessbutton.org'],
        monitoring: 'Automatic'
      }
    };
    try {
      altoa.licence = (ref15 = af.doaj.bibjson.license[0].type) != null ? ref15 : af.license[0].type; // could have doaj licence info
    } catch (error) {}
    if (af.indoaj) {
      altoa.embargo_months = 0;
      altoa.provenance = {
        oa_evidence: 'In DOAJ'
      };
    } else if (pisoa) {
      altoa.meta.creator = ['joe+oapublisher@openaccessbutton.org'];
      altoa.meta.contributors = ['joe+oapublisher@openaccessbutton.org'];
      altoa.provenance = {
        oa_evidence: 'OA publisher' // does this mean embargo_months should be zero too?
      };
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
    if (altoa.licence) {
      altoa.licences = [
        {
          type: altoa.licence,
          terms: ""
        }
      ];
    }
    altoa.score = (await _score(altoa));
    perms.all_permissions.push(altoa);
  }
  if (meta.doi) {
    if (oadoi == null) {
      oadoi = (await this.src.oadoi(meta.doi));
    }
    if (haddoi && (oadoi != null ? (ref16 = oadoi.best_oa_location) != null ? ref16.license : void 0 : void 0) && oadoi.best_oa_location.license.includes('cc')) { //  (haddoi or oadoi?.journal_is_oa)
      doa = {
        can_archive: true,
        version: oadoi.best_oa_location.version,
        versions: [],
        licence: oadoi.best_oa_location.license,
        licence_terms: "",
        licences: [],
        locations: ['institutional repository'],
        issuer: {
          type: 'article',
          has_policy: 'yes',
          id: meta.doi
        },
        meta: {
          creator: ['support@unpaywall.org'],
          contributors: ['support@unpaywall.org'],
          monitoring: 'Automatic',
          updated: oadoi.best_oa_location.updated
        },
        provenance: {
          oa_evidence: oadoi.best_oa_location.evidence
        }
      };
      if (typeof doa.licence === 'string') {
        doa.licences = [
          {
            type: doa.licence,
            terms: ""
          }
        ];
      }
      if (doa.version) {
        doa.versions = (ref17 = doa.version) === 'submittedVersion' || ref17 === 'preprint' ? ['submittedVersion'] : (ref18 = doa.version) === 'acceptedVersion' || ref18 === 'postprint' ? ['submittedVersion', 'acceptedVersion'] : ['submittedVersion', 'acceptedVersion', 'publishedVersion'];
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
    ref19 = perms.all_permissions;
    // note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for (o = 0, len4 = ref19.length; o < len4; o++) {
      wp = ref19[o];
      if (((ref20 = wp.issuer) != null ? ref20.type : void 0) === 'journal' && !wp.issuer.journal_oa_type) {
        wp.issuer.journal_oa_type = (await this.svc.oaworks.permissions.journals.oa.type(issns != null ? issns : wp.issuer.id, af, oadoi, crossref));
      }
      if (!((ref21 = wp.provenance) != null ? ref21.enforcement_from : void 0)) {
        perms.best_permission = this.copy(wp);
        break;
      } else if (!meta.published || Date.parse(meta.published) > Date.parse(wp.provenance.enforcement_from.split('/').reverse().join('-'))) {
        // NOTE Date.parse would try to work on format 31/01/2020 but reads it in American, so would think 31 is a month and is too big
        // but 2020-01-31 is treated in ISO so the 31 will be the day. So, given that we use DD/MM/YYYY, split on / then reverse then join on - to get a better parse
        perms.best_permission = this.copy(wp);
        break;
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
      for (t = 0, len5 = rors.length; t < len5; t++) {
        ro = rors[t];
        if (((ref22 = ro.issuer) != null ? ref22.type : void 0) === 'journal' && !ro.issuer.journal_oa_type) {
          ro.issuer.journal_oa_type = (await this.svc.oaworks.permissions.journals.oa.type(issns != null ? issns : ro.issuer.id, af, oadoi, crossref));
        }
        perms.all_permissions.push(ro);
        if (((ref23 = perms.best_permission) != null ? ref23.author_affiliation_requirement : void 0) == null) {
          if (perms.best_permission != null) {
            if (!((ref24 = ro.provenance) != null ? ref24.enforcement_from : void 0) || !meta.published || Date.parse(meta.published) > Date.parse(ro.provenance.enforcement_from.split('/').reverse().join('-'))) {
              pb = this.copy(perms.best_permission);
              ref25 = ['licences', 'versions', 'locations'];
              for (u = 0, len6 = ref25.length; u < len6; u++) {
                key = ref25[u];
                ref26 = ro[key];
                for (v = 0, len7 = ref26.length; v < len7; v++) {
                  vl = ref26[v];
                  if (pb[key] == null) {
                    pb[key] = [];
                  }
                  if (indexOf.call(pb[key], vl) < 0) {
                    pb[key].push(vl);
                  }
                }
              }
              ref28 = (ref27 = pb.licences) != null ? ref27 : [];
              for (w = 0, len8 = ref28.length; w < len8; w++) {
                l = ref28[w];
                if ((pb.licence == null) || l.type.length < pb.licence.length) {
                  pb.licence = l.type;
                }
              }
              pb.version = indexOf.call(pb.versions, 'publishedVersion') >= 0 || indexOf.call(pb.versions, 'publisher pdf') >= 0 ? 'publishedVersion' : indexOf.call(pb.versions, 'acceptedVersion') >= 0 || indexOf.call(pb.versions, 'postprint') >= 0 ? 'acceptedVersion' : 'submittedVersion';
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
      'not publisher': 'Please find another DOI for this article as this is provided as this doesn’t allow us to find required information like who published it'
    };
    return {
      body: typeof overall_policy_restriction !== 'string' ? overall_policy_restriction : (ref29 = msgs[overall_policy_restriction.toLowerCase()]) != null ? ref29 : overall_policy_restriction,
      status: 501
    };
  } else {
    if (this.params.metadata === true || getmeta === true) {
      perms.metadata = meta;
    }
    return perms;
  }
};

// the original sheet, now split into three separate ones, but keep a note in case of use for testing: 
// https://docs.google.com/spreadsheets/d/1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A/edit
P.svc.oaworks.permissions.journals = function(recs) {
  return this.svc.oaworks.permissions._format(recs);
};

P.svc.oaworks.permissions.journals._sheet = '19pDvOY5pge-C0yDSObnkMqqlMJgct3iIjPI2rMPLQEc/Export';

P.svc.oaworks.permissions.journals._prefix = false;

P.svc.oaworks.permissions.publishers = function(recs) {
  return this.svc.oaworks.permissions._format(recs);
};

P.svc.oaworks.permissions.publishers._sheet = '1tmEfeJ6RCTCQjcCht-FI7FH-04z7MPSKdUnm0UpAxWM/Export';

P.svc.oaworks.permissions.publishers._prefix = false;

P.svc.oaworks.permissions.affiliations = function(recs) {
  return this.svc.oaworks.permissions._format(recs);
};

P.svc.oaworks.permissions.affiliations._sheet = '1J4WhZjPsAjpoogsj7wSTQGJPguo7TiSe0uNcrvyd_OM/Export';

P.svc.oaworks.permissions.affiliations._prefix = false;

P.svc.oaworks.permissions.journals.oa = async function(issn, oadoi) {
  var ex, jr, ref, ref1, ref2, ret;
  try {
    // NOTE it is still to be decided what licence is acceptable to be counted as OA on the crossref index. For now it's anything CC, including NC
    if (issn == null) {
      issn = (ref = (ref1 = this.params.journal) != null ? ref1 : this.params.issn) != null ? ref : this.params.oa;
    }
  } catch (error) {}
  ret = {};
  if (issn) {
    ret.articles = (await this.src.crossref.works.count('type:"journal-article" AND ISSN:"' + issn + '"'));
    ret.open = (await this.src.crossref.works.count('type:"journal-article" AND ISSN:"' + issn + '" AND is_oa:true')); // could add AND NOT licence:nc
    if (ret.articles === ret.open) {
      ret.oa = true;
    }
    if (jr = (await this.svc.oaworks.journal('ISSN:"' + issn + '" AND indoaj:true', 1))) {
      ret.open = ret.articles;
      ret.doaj = true;
      ret.oa = true;
    }
    if (ex = (await this.src.crossref.journals.doi(issn))) {
      if (oadoi == null) {
        oadoi = (await this.src.oadoi(ex, 1));
      }
      if (oadoi != null) {
        delete ret.oa;
        ret.open = ret.articles;
        ret.oadoi = true;
        ret.oa = (oadoi != null ? (ref2 = oadoi.best_oa_location) != null ? ref2.license : void 0 : void 0) && oadoi.best_oa_location.license.includes('cc'); // oadoi.journal_is_oa
      } else {
        ret.oa = false;
      }
    }
  }
  return ret;
};

P.svc.oaworks.permissions.journals.oa.type = async function(issns, jrnl, oadoi, crossref) {
  var js, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7;
  if (typeof issns === 'string' && issns.startsWith('10.')) {
    if (oadoi == null) {
      oadoi = (await this.src.oadoi(issns));
    }
    if (crossref == null) {
      crossref = (await this.src.crossref.works(issns));
    }
    issns = void 0;
  }
  if (issns == null) {
    issns = (ref = (ref1 = (ref2 = (ref3 = (ref4 = oadoi != null ? oadoi.journal_issns : void 0) != null ? ref4 : crossref != null ? crossref.ISSN : void 0) != null ? ref3 : this.params.journals) != null ? ref2 : this.params.status) != null ? ref1 : this.params.issn) != null ? ref : this.params.issns;
  }
  if (typeof issns === 'string') {
    issns = issns.split(',');
  }
  js = 'unknown';
  if (((crossref != null ? crossref.type : void 0) != null) && crossref.type !== 'journal-article') {
    js = 'not applicable';
  } else if (!(crossref != null ? crossref.type : void 0) || crossref.type === 'journal-article') {
    js = (oadoi != null ? oadoi.oa_status : void 0) === 'gold' ? 'gold' : (oadoi != null ? oadoi.oa_status : void 0) === 'bronze' ? 'closed' : (oadoi != null ? oadoi.oa_status : void 0) === 'hybrid' ? 'hybrid' : '';
    if ((oadoi != null ? oadoi.journal_is_oa : void 0) || (oadoi != null ? oadoi.journal_is_in_doaj : void 0)) { // double check for gold
      js = 'gold';
    }
    if (issns) {
      if (js === 'closed' && (await this.src.oadoi.hybrid(issns))) {
        // check if it really is closed because sometimes OADOI says it is for one particular DOI but really it isn't
        js = 'hybrid';
      }
      // check if it is a known transformative or diamond journal
      if (jrnl == null) {
        jrnl = (await this.svc.oaworks.journal('ISSN:"' + issns.join('" OR ISSN:"') + '"', 1));
      }
      if (jrnl != null ? jrnl.tj : void 0) {
        js = 'transformative';
      } else if ((jrnl != null ? (ref5 = jrnl.doaj) != null ? (ref6 = ref5.bibjson) != null ? (ref7 = ref6.apc) != null ? ref7.has_apc : void 0 : void 0 : void 0 : void 0) === false) {
        js = 'diamond';
      }
    }
  }
  return js;
};

P.svc.oaworks.permissions.publishers.oa = async function(publisher) {
  var c, dt, q, ref, ret;
  try {
    if (publisher == null) {
      publisher = (ref = this.params.publisher) != null ? ref : this.params.oa;
    }
  } catch (error) {}
  q = 'publisher:"' + publisher.replace(/&/g, '') + '" AND NOT doaj.bibjson.discontinued_date:* AND NOT doaj.bibjson.is_replaced_by:* AND (';
  dt = parseInt(((await this.date())).split('-')[0]);
  c = dt - 2; // how many years back to check for continuance
  while (dt > c) {
    q += (q.endsWith('(') ? '' : ' OR ') + 'years:' + dt;
    dt -= 1;
  }
  q += ')';
  ret = {
    journals: (await this.svc.oaworks.journal.count(q)),
    open: (await this.svc.oaworks.journal.count(q + ' AND indoaj:true'))
  };
  ret.percent = Math.ceil((ret.open / ret.journals) * 100);
  ret.oa = ret.journals && ret.journals === ret.open;
  return ret;
};

P.svc.oaworks.permissions._format = async function(recs = []) {
  var af, an, cids, dt, i, j, k, keys, kn, l, lc, len, len1, len2, len3, len4, len5, m, n, name, nd, nid, nk, nps, nr, nv, o, rcs, ready, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, s, st, t;
  if (typeof recs === 'object' && !Array.isArray(recs)) {
    recs = [recs];
  }
  keys = {
    versionsarchivable: 'versions',
    permissionsrequestcontactemail: 'permissions_contact',
    archivinglocationsallowed: 'locations',
    license: 'licence',
    licencesallowed: 'licences',
    postprintembargo: 'embargo_months',
    depositstatementrequired: 'deposit_statement',
    copyrightowner: 'copyright_owner', // can be journal, publisher, affiliation or author
    publicnotes: 'notes',
    authoraffiliationrolerequirement: 'requirements.role',
    authoraffiliationrequirement: 'requirements.affiliation',
    authoraffiliationdepartmentrequirement: 'requirements.departmental_affiliation',
    iffundedby: 'requirements.funder',
    fundingproportionrequired: 'requirements.funding_proportion',
    subjectcoverage: 'requirements.subject',
    haspolicy: 'issuer.has_policy',
    permissiontype: 'issuer.type',
    parentpolicy: 'issuer.parent_policy',
    contributedby: 'meta.contributors',
    recordlastupdated: 'meta.updated',
    reviewers: 'meta.reviewer',
    addedby: 'meta.creator',
    monitoringtype: 'meta.monitoring',
    policyfulltext: 'provenance.archiving_policy',
    policylandingpage: 'provenance.archiving_policy_splash',
    publishingagreement: 'provenance.sample_publishing_agreement',
    publishingagreementsplash: 'provenance.sample_publishing_splash',
    rights: 'provenance.author_rights',
    embargolist: 'provenance.embargo_list',
    policyfaq: 'provenance.faq',
    miscsource: 'provenance.misc_source',
    enforcementdate: 'provenance.enforcement_from',
    example: 'provenance.example'
  };
  ready = [];
  for (i = 0, len = recs.length; i < len; i++) {
    rec = recs[i];
    nr = {
      can_archive: false,
      version: void 0,
      versions: void 0,
      licence: void 0,
      licence_terms: void 0,
      licences: void 0,
      locations: void 0,
      embargo_months: void 0,
      embargo_end: void 0,
      deposit_statement: void 0,
      permission_required: void 0,
      permissions_contact: void 0,
      copyright_owner: void 0,
      copyright_name: void 0,
      copyright_year: void 0,
      notes: void 0,
      requirements: void 0,
      issuer: {},
      meta: {},
      provenance: void 0
    };
    try {
      rec.recordlastupdated = rec.recordlastupdated.trim();
      if (rec.recordlastupdated.includes(',')) {
        nd = false;
        ref = rec.recordlastupdated.split(',');
        for (j = 0, len1 = ref.length; j < len1; j++) {
          dt = ref[j];
          if (nd === false || Date.parse(dt.trim().split('/').reverse().join('-')) > Date.parse(nd.split('/').reverse().join('-'))) {
            nd = dt.trim();
          }
        }
        if (nd !== false) {
          rec.recordlastupdated = nd;
        }
      }
      nr.meta.updated = rec.recordlastupdated;
    } catch (error) {}
    if (nr.meta.updated != null) {
      nr.meta.updatedAt = Date.parse(nr.meta.updated.split('/').reverse().join('-'));
    }
    // the google feed import will lowercase these key names and remove whitespace, question marks, brackets too, but not dashes
    nr.issuer.id = typeof rec.id === 'string' && rec.id.includes(',') ? rec.id.split(',') : rec.id;
    if (nr.issuer.id != null) {
      if (typeof nr.issuer.id !== 'string') {
        cids = [];
        ref1 = nr.issuer.id;
        for (m = 0, len2 = ref1.length; m < len2; m++) {
          nid = ref1[m];
          nid = nid.trim();
          if (nr.issuer.type === 'journal' && nid.includes('-') && !nid.includes(' ')) {
            nid = nid.toUpperCase();
            if (af = (await this.svc.oaworks.journal('ISSN:"' + nid + '"', 1))) {
              ref2 = af.issn;
              for (n = 0, len3 = ref2.length; n < len3; n++) {
                an = ref2[n];
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
      } else if (nr.issuer.id.startsWith('10.') && nr.issuer.id.includes('/') && !nr.issuer.id.includes(' ')) {
        nr.DOI = nr.issuer.id;
      }
    }
    nr.permission_required = typeof rec.haspolicy === 'string' && rec.haspolicy.toLowerCase().includes('permission required');
    for (k in rec) {
      if (keys[k] && (rec[k] != null) && rec[k].length !== 0) {
        nk = keys[k];
        nv = void 0;
        if (k === 'postprintembargo') { // Post-Print Embargo - empty or number of months like 0, 12, 24
          kn = parseInt(rec[k].trim());
          if (kn && typeof kn === 'number') {
            nv = kn;
          }
          if (nv != null) {
            nr.embargo_end = ''; // just to allow neat output later - can't be calculated until compared to a particular article
          }
        } else if (k === 'journal' || k === 'versionsarchivable' || k === 'archivinglocationsallowed' || k === 'licencesallowed' || k === 'policyfulltext' || k === 'contributedby' || k === 'addedby' || k === 'reviewers' || k === 'iffundedby') {
          nv = [];
          ref3 = rcs = rec[k].trim().split(',');
          for (o = 0, len4 = ref3.length; o < len4; o++) {
            s = ref3[o];
            st = s.trim();
            if (k === 'licencesallowed') {
              if (st.toLowerCase() !== 'unclear') {
                lc = {
                  type: st.toLowerCase()
                };
                try {
                  lc.terms = rec.licenceterms.split(',')[rcs.indexOf(s)].trim(); // these don't seem to exist any more...
                } catch (error) {}
                nv.push(lc);
              }
            } else {
              if (k === 'versionsarchivable') {
                st = st.toLowerCase();
                if (st === 'preprint') {
                  st = 'submittedVersion';
                }
                if (st === 'postprint') {
                  st = 'acceptedVersion';
                }
                if (st === 'publisher pdf') {
                  st = 'publishedVersion';
                }
              }
              if (st.length && indexOf.call(nv, st) < 0) {
                nv.push(k === 'archivinglocationsallowed' ? st.toLowerCase() : st);
              }
            }
          }
        } else if (k !== 'recordlastupdated') {
          nv = rec[k].trim();
        }
        if (typeof nv === 'string' && (((ref4 = nv.toLowerCase()) === 'yes' || ref4 === 'no') || (k === 'haspolicy' || k === 'permissiontype' || k === 'copyrightowner'))) {
          nv = nv.toLowerCase();
        }
        if ((k === 'copyrightowner' || k === 'license') && nv === 'unclear') {
          nv = '';
        }
        if (nv != null) {
          if (nk.includes('.')) {
            nps = nk.split('.');
            if (nr[name = nps[0]] == null) {
              nr[name] = {};
            }
            nr[nps[0]][[nps[1]]] = nv;
          } else {
            nr[nk] = nv;
          }
        }
      }
    }
    if (nr.licences == null) {
      nr.licences = [];
    }
    if (!nr.licence) {
      ref5 = nr.licences;
      for (t = 0, len5 = ref5.length; t < len5; t++) {
        l = ref5[t];
        if ((nr.licence == null) || l.type.length < nr.licence.length) {
          nr.licence = l.type;
          nr.licence_terms = l.terms;
        }
      }
    }
    if (nr.versions == null) {
      nr.versions = [];
    }
    if (nr.versions.length) {
      nr.can_archive = true;
      nr.version = indexOf.call(nr.versions, 'acceptedVersion') >= 0 || indexOf.call(nr.versions, 'postprint') >= 0 ? 'acceptedVersion' : indexOf.call(nr.versions, 'publishedVersion') >= 0 || indexOf.call(nr.versions, 'publisher pdf') >= 0 ? 'publishedVersion' : 'submittedVersion';
    }
    if (nr.copyright_owner == null) {
      nr.copyright_owner = (ref6 = (ref7 = nr.issuer) != null ? ref7.type : void 0) != null ? ref6 : '';
    }
    if (nr.copyright_name == null) {
      nr.copyright_name = '';
    }
    if (nr.copyright_year == null) {
      nr.copyright_year = ''; // the year of publication, to be added at result stage
    }
    if (!JSON.stringify(nr) !== '{}') {
      ready.push(nr);
    }
  }
  if (ready.length === 1) {
    return ready[0];
  } else {
    return ready;
  }
};

`P.svc.oaworks.journal = (q) ->
try
  if not q? and @params.journal or @params.issn
    q = 'ISSN:"' + (@params.journal ? @params.issn) + '"'
console.log 'running journal remote lookup', q
try
  res = await @fetch 'https://api.jct.cottagelabs.com/journal?q=' + q
  return res.hits.hits[0]._source
catch
  return`;

P.svc.oaworks.journal = {
  _index: true,
  _prefix: false
};

//P.svc.oaworks.journal._prefix = false
P.svc.oaworks.journal.load = async function() {
  var batch, batchsize, counter, from, i, len, r, ref, res, size, total;
  counter = 0;
  total = false;
  batchsize = 20000; // how many records to batch upload at a time
  batch = []; // batch of json records to upload
  from = 0;
  size = 5000;
  await this.svc.oaworks.journal('');
  while (total === false || counter < total) {
    // this is a fallback to JCT until a local custom process for journal indexing is added
    res = (await this.fetch('https://api.jct.cottagelabs.com/journal?q=*&from=' + from + '&size=' + size));
    if (total === false) {
      total = res.hits.total;
    }
    ref = res.hits.hits;
    for (i = 0, len = ref.length; i < len; i++) {
      r = ref[i];
      counter += 1;
      batch.push(r._source);
      if (batch.length >= batchsize) {
        await this.svc.oaworks.journal(batch);
        batch = [];
      }
    }
    from += size;
  }
  if (batch.length) {
    await this.svc.oaworks.journal(batch);
  }
  return counter;
};

P.svc.oaworks.journal.load._bg = true;

P.svc.oaworks.journal.load._async = true;

P.svc.oaworks.journal.load._auth = 'root';

var indexOf = [].indexOf;

P.svc.oaworks.report = function() {
  this.format = 'html';
  return '<script type="text/javascript" src="/client/pradmSuggest.min.js?v=' + this.S.version + '"></script> <script src="/client/svc/oaworks/report.min.js"></script>';
};

P.svc.oaworks.report.supplements = {
  _index: true,
  _prefix: false,
  _key: 'DOI'
};

P.svc.oaworks.report.check = async function(ror, reload) {
  var _from_crossref, alternates, base, base1, base2, base3, base4, batch, best_initial, best_name, best_score, counter, cr, d, dois, epmc, ex, fields, fq, h, header, headers, i, i1, j1, js, k, key, keys, l, len, len1, len10, len11, len2, len3, len4, len5, len6, len7, len8, len9, lic, loc, lvs, m, matchers, matches, max, mf, mt, n, o, oadoi, ok, out, pp, pubmed, q, r, ra, ran, rcc, rd, rec, recs, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref4, ref5, ref6, ref7, ref8, ref9, ren, res, row, rows, rr, s, score, sheets, sr, started, t, took, ts, u, v, val, w, y, z;
  if (reload == null) {
    reload = (ref = (ref1 = this.params.check) != null ? ref1 : this.params.reload) != null ? ref : this.params.sheet;
  }
  started = (await this.epoch());
  ts = (await this.datetime(false).replace(/[-T\: ]/g, '_'));
  console.log('OA check running', ts, reload);
  _from_crossref = async(cr) => {
    var a, aff, an, crf, f, fid, fidc, i, l, len, len1, len2, len3, len4, len5, n, o, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, t, u, x;
    cr.published = (await this.src.crossref.works.published(cr));
    try {
      cr.year = cr.published.split('-')[0];
    } catch (error) {}
    try {
      cr.year = parseInt(cr.year);
    } catch (error) {}
    try {
      crf = {
        DOI: cr.DOI.toLowerCase(),
        title: (ref2 = cr.title) != null ? ref2[0] : void 0,
        journal: (ref3 = cr['container-title']) != null ? ref3[0] : void 0,
        ISSN: cr.ISSN,
        publisher: cr.publisher,
        crossref_published: cr.published,
        crossref_year: cr.year,
        citations: cr['reference-count'],
        crossref_is_oa: cr.is_oa
      };
      try {
        crf.title = crf.title.replace(/\n/g, '').replace(/\s\s+/g, ' ');
      } catch (error) {}
      crf.funder_grant_ids = [];
      crf.funder_name = [];
      ref5 = (ref4 = cr.funder) != null ? ref4 : [];
      for (i = 0, len = ref5.length; i < len; i++) {
        f = ref5[i];
        if (f.DOI === '10.13039/100000865' || (f.name && f.name.toLowerCase().includes('gates'))) {
          if (f.name.toLowerCase() === 'bank of canada') {
            f.name = 'Bill and Melinda Gates Foundation';
          }
          if (ref6 = f.name, indexOf.call(crf.funder_name, ref6) < 0) {
            crf.funder_name.push(f.name);
          }
          ref8 = (ref7 = f.award) != null ? ref7 : [];
          for (l = 0, len1 = ref8.length; l < len1; l++) {
            fid = ref8[l];
            ref9 = fid.split(',');
            for (n = 0, len2 = ref9.length; n < len2; n++) {
              fidc = ref9[n];
              fidc = fidc.trim();
              if (indexOf.call(crf.funder_grant_ids, fidc) < 0) {
                crf.funder_grant_ids.push(fidc);
              }
            }
          }
        }
      }
      crf.author_names = [];
      crf.author_affiliation = [];
      ref11 = (ref10 = cr.author) != null ? ref10 : [];
      for (o = 0, len3 = ref11.length; o < len3; o++) {
        a = ref11[o];
        an = (ref12 = a.name) != null ? ref12 : (a.given ? a.given + ' ' : '') + ((ref13 = a.family) != null ? ref13 : '');
        if (an) {
          crf.author_names.push(an);
        }
        ref15 = (ref14 = a.affiliation) != null ? ref14 : [];
        for (t = 0, len4 = ref15.length; t < len4; t++) {
          aff = ref15[t];
          if (aff.name && aff.name.toLowerCase().includes('gates') && (ref16 = aff.name, indexOf.call(crf.author_affiliation, ref16) < 0)) {
            crf.author_affiliation.push(aff.name);
          }
        }
      }
      crf.crossref = cr;
      ref17 = ['assertion', 'reference', 'relation'];
      for (u = 0, len5 = ref17.length; u < len5; u++) {
        x = ref17[u];
        delete crf.crossref[x];
      }
      return crf;
    } catch (error) {
      console.log('from crossref parse error', JSON.stringify(cr));
    }
  };
  recs = {};
  if (!reload) {
    out = '/home/cloo/static/report/OAreport_' + ts + '.csv';
    q = 'funder.award:OPP* OR funder.award:INV*'; // query and matchers should be read from a config somewhere depending on ror
    if (!q.includes('journal-article')) {
      q = 'type:"journal-article" AND (' + q + ')';
    }
    matchers = [
      /Melinda\sGates\sFoundation/g, // about 100
      /BMGF/g,
      /Gates\sCambridge\sTrust/g, // about 20
      ///investment\s?id\s?\d{5}/gi, # didn't match anything
      /IID\s?\d{5}/gi,
      /OPPG[HD]\s?\d{4}/g, // about 20
      /OPP\s?1\s?\d{6}/g, // matches the most at about ~1100
      /OPP\s?[45]\s?\d{4}/g, // about 30
      /INV\‐\d{6}/g // 1
    ];
    ref2 = this.index._for('src_crossref_works', q);
    for await (rec of ref2) {
      rec.DOI = rec.DOI.toLowerCase();
      ex = (await this.tdm.extract({
        content: JSON.stringify(rec),
        matchers: matchers
      }));
      if (ex.matched) {
        recs[rec.DOI] = (await _from_crossref(rec));
        recs[rec.DOI].matches = [];
        ref3 = ex.matches;
        for (i = 0, len = ref3.length; i < len; i++) {
          mt = ref3[i];
          if (mt.matched || mt.result) {
            recs[rec.DOI].matches.push({
              matcher: mt.matched,
              matched: mt.result.join(',')
            });
          }
        }
      }
    }
    
    // NOTE funders in crossref can be assigned a "DOI" as an ID, so get the crossref funders data too and use that to search for them as well. 
    // There ARE examples of funders in works listed with or without DOI, or listed with DOI and no funder.name. There are even some with funder.DOI
    // and a WRONG funder.name, but evidence of being correct such as a Gates one having Gates DOI but wrong name but a Gates-formatted grant ID e.g 10.1002/uog.18811
    fq = '"10.13039/100000865" OR "gates foundation" OR "gates cambridge trust"';
    fields = ['funder.DOI', 'funder.name', 'author.affiliation.name'];
    ref4 = this.index._for('src_crossref_works', fq, {
      fields: fields
    });
    // the RORs for gates and gates cambridge trust are 0456r8d26 and 033sn5p83 but neither appear anywhere in crossref
    for await (rec of ref4) {
      if (rec.type === 'journal-article') {
        matches = [];
        js = JSON.stringify(rec);
        if (js.includes('10.13039/100000865')) {
          matches.push({
            field: 'funder.DOI',
            matched: '10.13039/100000865'
          });
        }
        if (js.includes('gates foundation')) {
          matches.push({
            field: 'funder.name',
            matched: 'gates foundation'
          });
        }
        if (js.includes('gates cambridge trust')) {
          matches.push({
            field: 'funder.name',
            matched: 'gates cambridge trust'
          });
        }
        rec.DOI = rec.DOI.toLowerCase();
        if (recs[rec.DOI]) {
          for (l = 0, len1 = matches.length; l < len1; l++) {
            mf = matches[l];
            recs[rec.DOI].matches.push(mf);
          }
          if ((base = recs[rec.DOI]).duplicate == null) {
            base.duplicate = 0;
          }
          recs[rec.DOI].duplicate += 1;
        } else {
          recs[rec.DOI] = (await _from_crossref(rec));
          recs[rec.DOI].matches = matches;
        }
      }
    }
  }
  sheets = { // https://docs.google.com/spreadsheets/d/.../edit
    finance: '1xD-5e8TTEpgRL1iCJVOEnSYiddC-K0npkCWCaqx2--4',
    oasupport: '180562eXtmMANfIlioclUrQDaUSWkTOz7igOymfnv2pg',
    staff: '1EZI0iNAXnJ-qbIJFGmtplHWP03NVT7hhf0ICazI0YXw',
    grants: '1lDNHAwH-8x89fgLK-JLs9bBv2cdHsJRnb1Pj86QYWZI',
    names: '1ZowZub-nwOHJrzP7IbhbdoydOAmBRxLysejw38Xt32Y',
    emails: '1U3YXF1DLhGvP4PgqxNQuHOSR99RWuwVeMmdTAmSM45U',
    lens: '1XulUi2Bk3QNsJLekx0PpNb6REhrwQi6Q9M1x_KIUH_0',
    chronos: '1SxIFu4SoROqinOXAZMepOE0d1oxAZgC8LR_nTRi4vpU'
  };
  if (reload) {
    if (sr = sheets[reload]) {
      sheets = {};
      sheets[reload] = sr;
    } else {
      for (sr in sheets) {
        if (sheets[sr] === reload) {
          sheets = {};
          sheets[sr] = reload;
          break;
        }
      }
    }
  }
  for (s in sheets) {
    rows = (await this.src.google.sheets({
      sheetid: sheets[s],
      sheet: 'Export',
      headers: false // just get rows because headers are in different places, and want to simplify them as well
    }));
    //if s is 'finance'
    //  rows.shift()
    //  rows.shift() # get rid of junk rows at top
    headers = [];
    ref5 = rows.shift();
    // get headers
    for (n = 0, len2 = ref5.length; n < len2; n++) {
      header = ref5[n];
      headers.push(header.toLowerCase().trim().replace(/ /g, '_').replace('?', ''));
    }
    for (o = 0, len3 = rows.length; o < len3; o++) {
      row = rows[o];
      rec = {};
      for (h in headers) {
        rec[headers[h].toLowerCase()] = !row[h] ? void 0 : (ref6 = row[h].trim().toLowerCase()) === 'true' || ref6 === 'yes' ? true : (ref7 = row[h].trim().toLowerCase()) === 'false' || ref7 === 'no' ? false : (ref8 = headers[h].toLowerCase()) === 'grant_id' || ref8 === 'ror' ? row[h].replace(/\//g, ',').replace(/ /g, '').split(',') : row[h];
      }
      if (rec.doi && typeof rec.doi === 'string') {
        rd = rec.doi.split(',')[0].toLowerCase().replace(/\.$/, '').replace(/\s/, '').split(' ')[0].split('?')[0].trim(); // some appeared to be lists of DOIs which is no use e.g. 10.1128/msphere.01330-20, 10.1128/msphere.00490-21
        if (rd.startsWith('10.') && rd.includes('/') && rd.length > 6) {
          if (reload) {
            recs[rd] = (await this.svc.oaworks.report.supplements(rd));
            if (recs[rd] == null) {
              if (recs[rd] == null) {
                recs[rd] = (await this.src.crossref.works(rd));
              }
              if (recs[rd] != null) {
                recs[rd] = (await _from_crossref(recs[rd]));
              } else {
                recs[rd] = {};
              }
            }
            for (k in rec) {
              recs[rd][k] = rec[k];
            }
          } else if (recs[rd] != null) {
            if ((base1 = recs[rd]).duplicate == null) {
              base1.duplicate = 0;
            }
            recs[rd].duplicate += 1;
          } else if (cr = (await this.src.crossref.works(rd))) {
            recs[rd] = (await _from_crossref(cr));
          } else {
            recs[rd] = {
              DOI: rd,
              in_crossref: false
            };
            if (!(await this.fetch('https://doi.org/' + rd))) {
              recs[rd].doi_resolves = false;
            }
          }
          try {
            if ((base2 = recs[rd]).sheets == null) {
              base2.sheets = [];
            }
            if (indexOf.call(recs[rd].sheets, s) < 0) {
              recs[rd].sheets.push(s);
            }
            if ((base3 = recs[rd]).ror == null) {
              base3.ror = [];
            }
            ref10 = (ref9 = rec.ror) != null ? ref9 : ['0456r8d26'];
            for (t = 0, len4 = ref10.length; t < len4; t++) {
              rr = ref10[t];
              if (indexOf.call(recs[rd].ror, rr) < 0) {
                recs[rd].ror.push(rr);
              }
            }
            for (r in rec) {
              if (r === 'apc_cost') {
                try {
                  ra = parseInt(rec[r]);
                } catch (error) {
                  ra = 0;
                }
                if ((base4 = recs[rd])[r] == null) {
                  base4[r] = 0;
                }
                recs[rd][r] += ra;
              } else if (recs[rd][r] != null) {
                if (recs[rd][r]) {
                  if (!Array.isArray(recs[rd][r])) {
                    recs[rd][r] = [recs[rd][r]];
                  }
                } else {
                  recs[rd][r] = [];
                }
                if ((rec[r] != null) && (typeof rec[r] !== 'string' || rec[r].trim().length) && (ref11 = rec[r], indexOf.call(recs[rd][r], ref11) < 0)) {
                  recs[rd][r].push(rec[r]);
                }
              } else if ((rec[r] != null) && rec[r] !== '') {
                recs[rd][r] = rec[r];
              }
            }
          } catch (error) {
            console.log('sheet fields merge error', rd);
          }
        } else {
          console.log('bad doi', rd);
        }
      }
    }
  }
  dois = (await this.keys(recs).length);
  console.log(dois);
  if (!reload) {
    alternates = { // {}
      title: 'Paper title',
      journal: 'Journal Title',
      publisher: 'Publisher name',
      published: 'Published date',
      year: 'Published year'
    };
    keys = this.params.keys ? this.params.keys.split(',') : [
      "DOI",
      "PMCID",
      "in_oadoi",
      "in_crossref",
      "doi_resolves",
      "compliant",
      "can_archive",
      "journal_oa_type",
      "crossref_is_oa",
      "oadoi_is_oa",
      "is_oa",
      "oadoi_oa_status",
      "best_oa_location_url",
      "best_oa_location_url_for_pdf",
      "has_repository_copy",
      "repository_license",
      "repository_url_for_pdf",
      "repository_url",
      "repository_url_in_pmc",
      "repository_version",
      "publisher_license",
      "publisher_url_for_pdf",
      "publisher_version",
      "epmc_licence",
      "epmc_licence_source",
      "title",
      "journal",
      "ISSN",
      "publisher",
      "published",
      "crossref_published",
      "oadoi_published",
      "year",
      "crossref_year",
      "oadoi_year",
      "author_names",
      "author_affiliation",
      "funder_name",
      "funder_grant_ids",
      
      // keys examples from OAreport Gates live: https://docs.google.com/spreadsheets/d/1Ufh_xs3NQjzbPRgwlFnHxK5nY2cjn4SsnCqvVnY4Nk8/edit#gid=1145124691
      "grant_id",
      "invoice_date",
      "invoice_number",
      // and others suggested by Joe, to be sourced from sheets inputs if not already known:
      "apc_cost",
      "oawork_finance_internal_id",
      "type",
      "to",
      "status",
      "sent",
      "last_contact",
      "last_heard_from",
      "completed",
      "follow_up_due",
      "follow_ups_sent",
      "author_name",
      "email",
      "author_email_name",
      "citations",
      "sheets",
      "matches_targets",
      "matches_found"
    ];
    for (u = 0, len5 = keys.length; u < len5; u++) {
      key = keys[u];
      await fs.appendFile(out, (key !== 'DOI' ? ',"' : '"') + ((ref12 = alternates[key]) != null ? ref12 : key) + '"');
    }
  }
  batch = [];
  counter = 0;
  max = (ref13 = this.params.max) != null ? ref13 : 0;
  for (d in recs) {
    if (max && counter > max) {
      break;
    }
    counter += 1;
    res = recs[d];
    if (res == null) { // check cos there was one from chronos that ended up with no record e.g. 10.1016/j.vaccine.2017.05.087pmcid:
      console.log(d);
    } else {
      if (oadoi = (await this.src.oadoi(res.DOI))) {
        res.oadoi = oadoi;
        res.journal_oa_type = (await this.svc.oaworks.permissions.journals.oa.type(void 0, void 0, oadoi, res.crossref));
        ref15 = (ref14 = oadoi.oa_locations) != null ? ref14 : [];
        for (v = 0, len6 = ref15.length; v < len6; v++) {
          loc = ref15[v];
          if (loc.host_type === 'publisher') {
            if (res.publisher_license == null) {
              res.publisher_license = loc.license;
            }
            if (res.publisher_url_for_pdf == null) {
              res.publisher_url_for_pdf = loc.url_for_pdf;
            }
            if (res.publisher_version == null) {
              res.publisher_version = loc.version;
            }
          }
          if (loc.host_type === 'repository') {
            if (loc.url && loc.url.toLowerCase().includes('pmc')) {
              if (!res.PMCID && !res.pmcid) {
                try {
                  pp = loc.url.toLowerCase().split('pmc')[1].split('/')[0].split('?')[0].split('#')[0];
                  if (pp.length && pp.replace(/[^0-9]/g, '').length === pp.length && !isNaN(parseInt(pp))) {
                    res.PMCID = 'PMC' + pp;
                  }
                } catch (error) {}
              }
              if (loc.license && !res.epmc_licence) {
                res.epmc_licence = loc.license;
                res.epmc_licence_source = 'oadoi EPMC repository oa_location';
              }
            }
            if (!res.repository_url || !res.repository_url.includes('pmc')) {
              ref16 = ['license', 'url_for_pdf', 'url', 'version'];
              for (w = 0, len7 = ref16.length; w < len7; w++) {
                ok = ref16[w];
                if (loc[ok]) {
                  res['repository_' + ok] = loc[ok];
                }
              }
            }
          }
        }
        if (res.repository_url && res.repository_url.toLowerCase().includes('pmc')) {
          res.repository_url_in_pmc = true;
        }
        res.best_oa_location_url = (ref17 = oadoi.best_oa_location) != null ? ref17.url : void 0;
        res.best_oa_location_url_for_pdf = (ref18 = oadoi.best_oa_location) != null ? ref18.url_for_pdf : void 0;
        res.oadoi_is_oa = oadoi.is_oa;
        res.is_oa = res.oadoi_is_oa || res.crossref_is_oa;
        res.oadoi_oa_status = oadoi.oa_status;
        res.has_repository_copy = oadoi.has_repository_copy;
        if (res.title == null) {
          res.title = oadoi.title;
        }
        if (res.journal == null) {
          res.journal = oadoi.journal_name;
        }
        if (oadoi.journal_issns) {
          if (res.ISSN == null) {
            res.ISSN = oadoi.journal_issns.split(',');
          }
        }
        if (res.publisher == null) {
          res.publisher = oadoi.publisher;
        }
        res.oadoi_published = oadoi.published_date;
        res.oadoi_year = oadoi.year;
      } else {
        res.in_oadoi = false;
      }
      if (res.year == null) {
        res.year = (ref19 = res.oadoi_year) != null ? ref19 : res.crossref_year;
      }
      if (res.published == null) {
        res.published = (ref20 = res.oadoi_published) != null ? ref20 : res.crossref_published;
      }
      if (((ref21 = oadoi != null ? (ref22 = oadoi.best_oa_location) != null ? ref22.license : void 0 : void 0) != null ? ref21 : '').includes('cc') || (oadoi != null ? oadoi.journal_is_in_doaj : void 0)) {
        res.can_archive = true;
      } else {
        rcc = this.copy((ref23 = res.crossref) != null ? ref23 : {});
        rcc.doi = rcc.DOI;
        res.permissions = (await this.svc.oaworks.permissions(rcc, void 0, void 0, oadoi, (JSON.stringify(rcc) === '{}' ? void 0 : rcc)));
        res.can_archive = (ref24 = res.permissions) != null ? (ref25 = ref24.best_permission) != null ? ref25.can_archive : void 0 : void 0;
      }
      res.compliant = (await this.svc.oaworks.report.compliant(res));
      epmc = void 0;
      pubmed = void 0;
      if (!res.PMCID) {
        if (res.pmcid && (!Array.isArray(res.pmcid) || res.pmcid.length)) { // may be present from sheets?
          res.PMCID = 'PMC' + res.pmcid.toString().toLowerCase().replace('pmc', '');
          if (Array.isArray(res.PMCID)) {
            res.PMCID = res.PMCID[0];
          }
        } else if (pubmed = (await this.src.pubmed.doi(res.DOI))) {
          if ((ref26 = pubmed.identifier) != null ? ref26.pmc : void 0) {
            res.PMCID = pubmed.identifier.pmc;
            res.PMCID = 'PMC' + res.PMCID.toLowerCase().replace('pmc', '');
          }
        } else if (res.repository_url_in_pmc && (epmc = (await this.src.epmc.doi(res.DOI)))) {
          res.PMCID = epmc.pmcid;
        }
      }
      if (res.PMCID && res.repository_url_in_pmc && !res.epmc_licence) {
        lic = (await this.src.epmc.licence(res.PMCID, epmc));
        res.epmc_licence = lic != null ? lic.licence : void 0;
        res.epmc_licence_source = lic != null ? lic.source : void 0;
      }
      if (res.author_names && res.email) {
        if (res.author_names.length === 1) {
          res.author_email_name = 'Dr. ' + res.author_names[0].split(' ').pop();
        } else {
          ren = (typeof res.email === 'string' ? res.email : res.email[0]).split('@')[0].toLowerCase().replace(/[^a-z]/g, '');
          best_initial = '';
          best_name = '';
          best_score = 1000000;
          ref27 = res.author_names;
          for (y = 0, len8 = ref27.length; y < len8; y++) {
            ran = ref27[y];
            lvs = (await this.tdm.levenshtein(ren, ran.toLowerCase().replace(/[^a-z]/g, '')));
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
          if (best_score < .7) {
            res.author_email_name = 'Dr. ' + best_name.split(' ').pop();
          }
          if (!res.author_email_name && best_initial) {
            res.author_email_name = best_initial;
          }
        }
      }
      batch.push(res);
      if (!reload) {
        await fs.appendFile(out, '\n');
        for (z = 0, len9 = keys.length; z < len9; z++) {
          k = keys[z];
          val = res[k] == null ? '' : Array.isArray(res[k]) ? res[k].join(',') : typeof res[k] === 'object' ? JSON.stringify(res[k]) : res[k];
          if (k === 'matches_targets') {
            ref29 = (ref28 = res.matches) != null ? ref28 : [];
            for (i1 = 0, len10 = ref29.length; i1 < len10; i1++) {
              m = ref29[i1];
              if (m.field || m.matcher) {
                val += (val ? ',' : '') + ((ref30 = m.field) != null ? ref30 : m.matcher);
              }
            }
          } else if (k === 'matches_found') {
            ref32 = (ref31 = res.matches) != null ? ref31 : [];
            for (j1 = 0, len11 = ref32.length; j1 < len11; j1++) {
              m = ref32[j1];
              val += (val ? ',' : '') + m.matched;
            }
          }
          await fs.appendFile(out, (k !== 'DOI' ? ',"' : '"') + val.toString().replace(/"/g, '').replace(/\n/g, '').replace(/\s\s+/g, ' ') + '"');
        }
      }
      if (batch.length % 100 === 0) {
        console.log('Gates OA checking', batch.length, dois);
      }
    }
  }
  if (!reload) {
    await this.svc.oaworks.report.supplements(''); // change this to a delete of only those that are relevant to the source files of the org being checked
  }
  await this.svc.oaworks.report.supplements(batch);
  took = Math.ceil((((await this.epoch())) - started) / 60000);
  console.log('OA check done after ' + took + ' minutes', reload);
  if (!reload) {
    this.mail({
      to: 'mark@oa.works',
      subject: 'Gates OA check done ' + batch.length + ' in ' + took + ' minutes',
      text: 'https://static.oa.works/report/' + ts
    });
  }
  return batch.length;
};

P.svc.oaworks.report._hides = true;

P.svc.oaworks.report.check._bg = true;

P.svc.oaworks.report.check._async = true;

P.svc.oaworks.report.check._notify = false;

P.svc.oaworks.report.compliant = function(rec, ror) {
  var ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, robl;
  // compare with https://docs.google.com/spreadsheets/d/1oanKC96Jbel7S8Hhy0muMHzRvOIUzer1dZu7FlXhqaE/edit#gid=1000508628
  // and https://docs.google.com/spreadsheets/d/1-7bVmmpVfaa8biZO2GdVsjOJTPGEpjL4h9oAXjJonVw/edit#gid=1048310661
  // source for TJs from JCT sheet is https://docs.google.com/spreadsheets/d/e/2PACX-1vT2SPOjVU4CKhP7FHOgaf0aRsjSOt-ApwLOy44swojTDFsWlZAIZViC0gdbmxJaEWxdJSnUmNoAnoo9/pub?gid=0&single=true&output=csv
  // there are 2281. But it's not clear how we used that data for anything other than display in the sheet
  robl = ((ref = (ref1 = rec.oadoi) != null ? (ref2 = ref1.best_oa_location) != null ? ref2.license : void 0 : void 0) != null ? ref : '').toLowerCase().replace(/-/g, '');
  if (((ref3 = rec.publisher) === 'Cold Spring Harbor Laboratory' || ref3 === 'Research Square') || ((ref4 = rec.journal) === 'Data in Brief') || rec.DOI.startsWith('10.2139/ssrn') || rec.DOI.startsWith('10.21203/rs') || rec.DOI.startsWith('10.31234/osf.io/')) {
    return 'n/a'; // not peer reviewed, so compliant is not applicable
  } else if (rec.journal_oa_type && ((ref5 = rec.journal_oa_type) !== 'closed' && ref5 !== 'green') && (robl.includes('ccby') || robl.includes('cc0') || robl.includes('pd') || (robl.includes('public') && robl.includes('domain')))) {
    if (!rec.repository_url_in_pmc) { // what repos count as approved?
      return 'expected';
    } else {
      return 'yes';
    }
  } else if ((rec.journal_oa_type == null) || !robl || !((ref6 = rec.oadoi) != null ? (ref7 = ref6.best_oa_location) != null ? ref7.url : void 0 : void 0)) {
    return 'unknown';
  } else {
    return 'no';
  }
};

P.svc.oaworks.report.compliance = async function(ror) {
  var compliant, papers, pc, ref, ref1;
  if (ror == null) {
    ror = (ref = (ref1 = this.params.report) != null ? ref1 : this.params.compliance) != null ? ref : this.params.ror;
  }
  papers = (await this.svc.oaworks.report.supplements.count());
  compliant = (await this.svc.oaworks.report.supplements.count('compliant:yes'));
  pc = Math.ceil((compliant / papers) * 1000) / 10;
  if (pc > 100) {
    return 100;
  } else {
    return pc;
  }
};

P.svc.oaworks.report.rating = async function(ror) {
  var filter, opens, papers, pc, ref, ref1;
  if (ror == null) {
    ror = (ref = (ref1 = this.params.report) != null ? ref1 : this.params.rating) != null ? ref : this.params.ror;
  }
  if (ror) {
    if (typeof ror !== 'object') {
      ror = (await this.src.ror(ror));
    }
    filter = 'type:"journal-article" AND ("' + ror.name + '" OR "' + ror._id + '")';
    papers = (await this.src.crossref.works.count(filter));
    opens = (await this.src.crossref.works.count(filter + ' AND is_oa:true'));
  } else {
    papers = (await this.svc.oaworks.report.supplements.count());
    opens = (await this.svc.oaworks.report.supplements.count('is_oa:true'));
  }
  pc = Math.ceil((opens / papers) * 1000) / 10;
  if (pc > 100) {
    return 100;
  } else {
    return pc;
  }
};

P.svc.oaworks.report.citations = async function(filter) {
  var counts, rec, ref, ref1, ref2, ror;
  counts = {
    papers: 0,
    citations: 0,
    oa: {
      papers: 0,
      citations: 0
    },
    closed: {
      papers: 0,
      citations: 0
    }
  };
  if (typeof filter === 'object') {
    filter = filter._id;
  }
  ror = (ref = this.params.report) != null ? ref : this.params.citations;
  if (typeof filter === 'string' && filter.length < 10 && !filter.includes(' ')) {
    ror = filter;
  }
  if (ror) {
    filter = 'type:"journal-article"' + (ror ? ' AND ("' + ror.name + '" OR "' + ror._id + '")' : '');
  }
  if (ror === '0456r8d26') {
    ref1 = this.index._for('svc_oaworks_gates_oachecks', 'citations:*', {
      include: ['citations', 'is_oa']
    });
    for await (rec of ref1) {
      counts.papers += 1;
      counts.citations += rec.citations;
      counts[rec.is_oa ? 'oa' : 'closed'].papers += 1;
      counts[rec.is_oa ? 'oa' : 'closed'].citations += rec.citations;
    }
  } else if (filter) {
    ref2 = this.index._for('src_crossref_works', filter + ' AND reference-count:*', {
      include: ['reference-count', 'is_oa']
    });
    for await (rec of ref2) {
      counts.papers += 1;
      counts.citations += rec['reference-count'];
      counts[rec.is_oa ? 'oa' : 'closed'].papers += 1;
      counts[rec.is_oa ? 'oa' : 'closed'].citations += rec['reference-count'];
    }
  }
  counts.oa.average = Math.ceil(counts.oa.citations / counts.oa.papers);
  counts.closed.average = Math.ceil(counts.closed.citations / counts.closed.papers);
  if (counts.oa.average > counts.closed.average) {
    counts.oa_extra_percent = Math.ceil(((counts.oa.average - counts.closed.average) / counts.closed.average) * 100);
  }
  return counts;
};

P.svc.oaworks.report.publishers = async function(filter) {
  var filteroa, i, l, len, len1, name, opub, p, pub, publist, pubs, ref, ref1;
  if (filter || !(publist = P.svc.oaworks.report._publishers)) { // allow to cache the result for a while...
    pubs = {};
    ref = (await this.src.crossref.works.terms('publisher', filter, 200));
    for (i = 0, len = ref.length; i < len; i++) {
      pub = ref[i];
      pubs[pub.term] = {
        papers: pub.count
      };
    }
    if (filter == null) {
      filter = '';
    }
    if (filter.includes(' OR ') && !filter.includes(')')) {
      filter = '(' + filter + ')';
    }
    filteroa = (filter ? filter + ' AND ' : '') + 'is_oa:true';
    ref1 = (await this.src.crossref.works.terms('publisher', filteroa, 200));
    for (l = 0, len1 = ref1.length; l < len1; l++) {
      opub = ref1[l];
      if (pubs[name = opub.term] == null) {
        pubs[name] = {};
      }
      pubs[opub.term].open = opub.count;
    }
    publist = [];
    for (p in pubs) {
      pubs[p].name = p;
      if ((pubs[p].open != null) && (pubs[p].papers == null)) {
        pubs[p].papers = (await this.src.crossref.works.count(filter + (filter ? ' AND ' : '') + ' publisher.keyword:"' + p + '"'));
      }
      if (pubs[p].papers && (pubs[p].open == null)) {
        pubs[p].open = (await this.src.crossref.works.count(filteroa + ' AND publisher.keyword:"' + p + '"'));
      }
      pubs[p].rating = pubs[p].open && pubs[p].papers ? pubs[p].open / pubs[p].papers : 0;
      pubs[p].percent = Math.ceil(pubs[p].rating * 1000) / 10;
      if (pubs[p].percent > 100) {
        pubs[p].percent = 100;
      }
      if (pubs[p].papers && pubs[p].rating) {
        publist.push(pubs[p]);
      }
    }
    
    //publist.sort (a, b) => return b.rating - a.rating
    publist.sort((a, b) => {
      return b.rating - a.rating || b.open - a.open;
    });
    P.svc.oaworks.report._publishers = publist;
  }
  return publist;
};

P.svc.oaworks.report.journals = async function() {
  var i, j, jrnl, jrnlist, jrnls, l, len, len1, name, oj, ref, ref1;
  if (!(jrnlist = P.svc.oaworks.report._journals)) {
    jrnls = {};
    ref = (await this.src.crossref.works.terms('container-title', void 0, 200));
    for (i = 0, len = ref.length; i < len; i++) {
      jrnl = ref[i];
      jrnls[jrnl.term] = {
        papers: jrnl.count
      };
    }
    ref1 = (await this.src.crossref.works.terms('container-title', 'is_oa:true', 200));
    for (l = 0, len1 = ref1.length; l < len1; l++) {
      oj = ref1[l];
      if (jrnls[name = oj.term] == null) {
        jrnls[name] = {};
      }
      jrnls[oj.term].open = oj.count;
    }
    jrnlist = [];
    for (j in jrnls) {
      jrnls[j].name = j;
      if ((jrnls[j].open != null) && (jrnls[j].papers == null)) {
        jrnls[j].papers = (await this.src.crossref.works.count('container-title.keyword:"' + j + '"'));
      }
      if (jrnls[j].papers && (jrnls[j].open == null)) {
        jrnls[j].open = (await this.src.crossref.works.count('is_oa:true AND container-title.keyword:"' + j + '"'));
      }
      jrnls[j].rating = jrnls[j].open && jrnls[j].papers ? jrnls[j].open / jrnls[j].papers : 0;
      jrnls[j].percent = Math.ceil(jrnls[j].rating * 1000) / 10;
      if (jrnls[j].percent > 100) {
        jrnls[j].percent = 100;
      }
      if (jrnls[j].papers && jrnls[j].rating) {
        jrnlist.push(jrnls[j]);
      }
    }
    
    //jrnlist.sort (a, b) => return b.rating - a.rating
    jrnlist.sort((a, b) => {
      return b.rating - a.rating || b.open - a.open;
    });
    P.svc.oaworks.report._journals = jrnlist;
  }
  return jrnlist;
};

P.svc.oaworks.report.compare = async function() {
  var cr, crs, paper, pubmednotcrossref, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, res, seen;
  res = {
    crossref: (await this.src.crossref.works.count('(funder.DOI:"10.13039/100000865" OR funder.name:"gates foundation" OR funder.name:"gates cambridge trust" OR author.affiliation.name:"melinda gates" OR author.affiliation.name:"gates cambridge trust")')),
    pubmed: (await this.src.pubmed.count('grant.agency:"melinda gates" OR grant.agency:"gates cambridge trust" OR author.affiliation:"melinda gates" OR author.affiliation:"gates cambridge trust"')), // what about gates international research scholar? Or things like "gates institute for..." Also just the phrase in any field matches another ~204 mostly in abstract or title, but not necessarily Gates-funded articles, just ABOUT gates work
    pubmednodoi: 0,
    pubmednotcrossref: 0,
    pubmednotepmc: 0,
    mag: 0,
    magnodoi: 0,
    magnodoimatchedtitle: 0,
    magnotcrossref: 0,
    magnotcrossrefviatitle: 0,
    magnotcrossrefnotpubmed: 0
  };
  pubmednotcrossref = [];
  ref = this.index._for('src_pubmed', 'grant.agency:"melinda gates" OR grant.agency:"gates cambridge trust" OR author.affiliation:"melinda gates" OR author.affiliation:"gates cambridge trust"');
  for await (rec of ref) {
    if (!((ref1 = rec.identifier) != null ? ref1.pmc : void 0)) {
      res.pubmednotepmc += 1;
    }
    if ((ref2 = rec.identifier) != null ? ref2.doi : void 0) {
      if (cr = (await this.src.crossref.works(rec.identifier.doi))) {
        crs = JSON.stringify(cr).toLowerCase();
        if (!crs.includes('10.13039/100000865') && !crs.includes('gates foundation') && !crs.includes('gates cambridge trust')) {
          res.pubmednotcrossref += 1;
          pubmednotcrossref.push(rec.identifier.doi);
        }
      } else {
        res.pubmednotcrossref += 1;
        pubmednotcrossref.push(rec.identifier.doi);
      }
    } else {
      res.pubmednodoi += 1;
    }
  }
  seen = [];
  ref3 = this.index._for('src_microsoft_graph_relation', 'OriginalAffiliation:"melinda gates"');
  for await (rec of ref3) {
    if (ref4 = rec.PaperId, indexOf.call(seen, ref4) < 0) {
      seen.push(rec.PaperId);
      res.mag += 1;
      paper = (await this.src.microsoft.graph(rec.PaperId));
      if (paper.Doi) {
        if (cr = (await this.src.crossref.works(paper.Doi))) {
          crs = JSON.stringify(cr).toLowerCase();
          if (!crs.includes('10.13039/100000865') && !crs.includes('gates foundation') && !crs.includes('gates cambridge trust')) {
            res.magnotcrossref += 1;
            if (ref5 = paper.Doi, indexOf.call(pubmednotcrossref, ref5) < 0) {
              res.magnotcrossrefnotpubmed += 1;
            }
          }
        } else {
          res.magnotcrossref += 1;
          if (ref6 = paper.Doi, indexOf.call(pubmednotcrossref, ref6) < 0) {
            res.magnotcrossrefnotpubmed += 1;
          }
        }
      } else {
        res.magnodoi += 1;
        if (paper.PaperTitle && (cr = (await this.src.crossref.works('title:"' + paper.PaperTitle + '"')))) {
          if ((cr != null ? (ref7 = cr.hits) != null ? ref7.total : void 0 : void 0) !== 0) {
            res.magnodoimatchedtitle += 1;
            cr = cr.hits.hits[0]._source;
            crs = JSON.stringify(cr).toLowerCase();
            if (!crs.includes('10.13039/100000865') && !crs.includes('gates foundation') && !crs.includes('gates cambridge trust')) {
              res.magnotcrossref += 1;
              res.magnotcrossrefviatitle += 1;
            }
          } else {
            res.magnotcrossrefnotpubmed += 1;
          }
        }
      }
    }
  }
  return res;
};

// https://jcheminf.springeropen.com/articles/10.1186/1758-2946-3-47
P.svc.oaworks.scrape = async function(content, doi) {
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
    content = (await this.puppet(content));
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
  }
  if (!meta.doi) {
    try {
      d = (await this.tdm.extract({
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
  }
  if (meta.title && meta.title.indexOf('|') !== -1) {
    meta.title = meta.title.split('|')[0].trim();
  }
  if (!meta.year) {
    try {
      k = (await this.tdm.extract({
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
      k = (await this.tdm.extract({
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
      m = (await this.tdm.extract({
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

P.svc.oaworks.scrape._hide = true;


var indexOf = [].indexOf;

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
  _hide: true,
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
    resolves = (await this.svc.oaworks.ill.subscription({
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
  this.nolog = true;
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


S.built = "Tue Nov 09 2021 05:00:17 GMT+0000";
P.puppet = {_bg: true}// added by constructor

P.puppet._auth = 'system';// added by constructor

P.puppet._hide = true;// added by constructor

P.src.crossref.load = {_bg: true}// added by constructor

P.src.crossref.load._async = true;// added by constructor

P.src.crossref.load._auth = 'root';// added by constructor

P.src.crossref.changes = {_bg: true}// added by constructor

P.src.crossref.changes._async = true;// added by constructor

P.src.crossref.changes._auth = 'root';// added by constructor

P.src.crossref.changes._notify = false;// added by constructor

P.src.microsoft.load = {_bg: true}// added by constructor

P.src.microsoft.load._async = true;// added by constructor

P.src.microsoft.load._auth = 'root';// added by constructor

P.src.oadoi.load = {_bg: true}// added by constructor

P.src.oadoi.load._async = true;// added by constructor

P.src.oadoi.load._auth = 'root';// added by constructor

P.src.oadoi.changes = {_bg: true}// added by constructor

P.src.oadoi.changes._async = true;// added by constructor

P.src.oadoi.changes._auth = 'root';// added by constructor

P.src.oadoi.changes._notify = false;// added by constructor

P.src.oadoi.local = {_bg: true}// added by constructor

P.src.oadoi.local._auth = 'root';// added by constructor

P.src.pubmed.load = {_bg: true}// added by constructor

P.src.pubmed.load._async = true;// added by constructor

P.src.pubmed.load._auth = 'root';// added by constructor

P.src.pubmed.changes = {_bg: true}// added by constructor

P.src.pubmed.changes._async = true;// added by constructor

P.src.pubmed.changes._auth = 'root';// added by constructor

P.src.pubmed.changes._notify = false;// added by constructor

P.src.ror.load = {_bg: true}// added by constructor

P.src.ror.load._async = true;// added by constructor

P.src.ror.load._auth = 'root';// added by constructor

P.src.wikidata.load = {_bg: true}// added by constructor

P.src.wikidata.load._async = true;// added by constructor

P.src.wikidata.load._auth = 'root';// added by constructor
