// limit, cron/job/batch (note workers now has a schedule ability too. explore that but consider vendor lock-in)

// _auth - if true an authorised user is required. If a string or a list, an authorised user with that role is required. always try to find user even if auth is not required, so that user is optionally available
// _cache - can be false or a number of seconds for how long the cache value is valid) (pass refresh param with incoming request to override a cache) (note below, if cache is required for test, should everything just always be cached but then just not checked if _cache is false?
// _kv - if true store the result in CF workers KV, and check for it on new requests - like a cache, but global, with 1s eventual consistency whereas cache is regional
// _index - if true send the result to an index. Or can be an object of index initialisation settings, mappings, aliases
// _key - optional which key, if not default _id, to use from a function result object to save it as - along with the function route which will be derived if not provided
// _sheet - if true get a sheet ID from settings for the given endpoint, if string then it is the sheet ID. If present it implies _index:true if _index is not set

// _.async (start the function but don't wait for it to finish, get an ID to query its result later?)
// _.retry (a number of times to retry, or a retry settings obj see below)
// _.history (if true save a copy of every change and the request that changed somewhere. Or enough just to save the requests and replay them?)
var P, S;

try {
  S = JSON.parse(SECRETS_SETTINGS); // from CF variable this will need parsed, so just default to passing them as strings and parsing them
} catch (error) {}

if (S == null) {
  S = {};
}

if (S.name == null) {
  S.name = 'N2';
}

if (S.version == null) {
  S.version = '5.2.6';
}

if (S.env == null) {
  S.env = 'dev';
}

if (S.dev == null) {
  S.dev = S.env === 'dev';
}

// TODO replace bg with a proper bg endpoint for workers to send to (or fail open)
// once bg goes into permanent settings, the background server starter shouod remove it and replace it with true or nothing
if (S.headers == null) {
  S.headers = {};
}

//  'Access-Control-Allow-Methods': 'HEAD, GET, PUT, POST, DELETE, OPTIONS'
//  'Access-Control-Allow-Origin': '*'
//  'Access-Control-Allow-Headers': 'X-apikey, X-id, Origin, X-Requested-With, Content-Type, Content-Disposition, Accept, DNT, Keep-Alive, User-Agent, If-Modified-Since, Cache-Control'
if (S.svc == null) {
  S.svc = {};
}

if (S.src == null) {
  S.src = {};
}

try {
  addEventListener('fetch', function(event) {
    //event.passThroughOnException() # let exceptions happen and pass request through to the origin
    return event.respondWith(P.call(event));
  });
} catch (error) {}

'try\naddEventListener \'scheduled\', (event) ->\n  https://developers.cloudflare.com/workers/runtime-apis/scheduled-event\n  TODO need to configure this to run when the schedule calls. What to run on schedule?\n  event.type will always be \'scheduled\'\n  event.scheduledTime ms timestamp of the scheduled time. Can be parsed with new Date(event.scheduledTime)\n  event.waitUntil should be passed a promise. The first to fail will be recorded as fail on Cron past events UI. Otherwise will record as success\n  event.waitUntil P.call event';

P = async function() {
  var _lp, _racer, _return, _save, authd, base, base1, fn, hd, i, j, kp, kpn, len, len1, name, pk, prs, qp, ref, ref1, ref10, ref11, ref12, ref13, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, res, resp;
  this.started = Date.now(); // not strictly accurate in a workers environment, but handy nevertheless
  try {
    if (S.dev && S.bg !== true) { // handy for CF edit UI debug to see if code has updated yet
      console.log(S.version);
    }
  } catch (error) {}
  try {
    // this header is defined later because the built date is added to the end of the file by the deploy script, so it's not known until now
    if ((base = S.headers)[name = 'X-' + S.name] == null) {
      base[name] = (S.version ? 'v' + S.version : '') + (S.env ? ' ' + S.env : '') + (S.built ? ' built ' + S.built : '');
    }
  } catch (error) {}
  this.S = JSON.parse(JSON.stringify(S));
  this.params = {};
  // note may need to remove apikey param - but if removing, how does that affect the fact that request is an actual immutable Request object?
  // it probably would appear to change, but may still be in there, then may get saved in cache etc which prob isn't wanted
  // unless results SHOULD differ by apikey? Probably on any route where that is the case, caching should be disabled
  if ((this.request.url != null) && this.request.url.indexOf('?') !== -1) {
    ref = this.request.url.split('?')[1].split('&');
    for (i = 0, len = ref.length; i < len; i++) {
      qp = ref[i];
      kp = qp.split('=');
      this.params[kp[0]] = kp.length === 1 ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'true' ? true : typeof kp[1] === 'string' && kp[1].toLowerCase() === 'false' ? false : qp.endsWith('=') ? true : kp[1];
      if (typeof this.params[kp[0]] === 'string' && this.params[kp[0]].replace(/[0-9]/g, '').length === 0 && !this.params[kp[0]].startsWith('0')) {
        kpn = parseInt(this.params[kp[0]]);
        if (!isNaN(kpn)) {
          this.params[kp[0]] = kpn;
        }
      }
      if (typeof this.params[kp[0]] === 'string' && (this.params[kp[0]].startsWith('[') || this.params[kp[0]].startsWith('{'))) {
        try {
          this.params[kp[0]] = JSON.parse(this.params[kp[0]]);
        } catch (error) {}
      }
    }
  }
  try {
    if (this.request.body.startsWith('{') || this.request.body.startsWith('[')) {
      this.body = JSON.parse(this.request.body);
    }
    if (typeof this.body === 'object' && !Array.isArray(this.body)) {
      for (qp in this.body) {
        if ((base1 = this.params)[qp] == null) {
          base1[qp] = this.body[qp];
        }
      }
    }
  } catch (error) {}
  try {
    if (this.body == null) {
      this.body = this.request.body;
    }
  } catch (error) {}
  if (this.params.refresh) {
    this.refresh = this.params.refresh;
    delete this.params.refresh;
  }
  try {
    this.headers = {};
    ref1 = [...this.request.headers];
    // request headers is an immutable Headers instance, not a normal object, so would appear empty unless using get/set, so parse it out here
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      hd = ref1[j];
      this.headers[hd[0]] = hd[1];
    }
  } catch (error) {
    this.headers = this.request.headers; // backend server passes a normal object
    if (typeof this.waitUntil !== 'function') {
      this.waitUntil = function(fn) {
        console.log('waitUntil');
        return true;
      };
    }
  }
  try {
    this.rid = this.headers['cf-ray'].slice(0, -4);
  } catch (error) {}
  try {
    // how / when to remove various auth headers before logging / matching cache?
    // e.g apikey, id, resume, token, access_token, email?
    this.id = (ref2 = (ref3 = (ref4 = (ref5 = this.headers['x-id']) != null ? ref5 : this.headers.id) != null ? ref4 : this.headers._id) != null ? ref3 : this.params._id) != null ? ref2 : this.params.id;
  } catch (error) {}
  try {
    this.apikey = (ref6 = (ref7 = (ref8 = this.headers['x-apikey']) != null ? ref8 : this.headers.apikey) != null ? ref7 : this.params.apikey) != null ? ref6 : this.params.apiKey;
  } catch (error) {}
  if (this.params.apikey) {
    delete this.params.apikey;
  }
  try {
    this.cookie = this.headers.cookie;
  } catch (error) {}
  if (this.request.url.indexOf('http://') !== 0 && this.request.url.indexOf('https://') !== 0) {
    // in case there's a url param with them as well, check if they're at the start
    // there's no base to the URL passed on the backend server, so here the @base isn't shifted from the parts list
    this.url = this.request.url.split('?')[0].replace(/^\//, '').replace(/\/$/, '');
    this.parts = this.url.length ? this.url.split('/') : [];
  } else {
    this.url = this.request.url.split('?')[0].replace(/\/$/, '').split('://')[1];
    this.parts = this.url.split('/');
    this.base = this.parts.shift();
  }
  this.route = this.parts.join('/');
  this._logs = []; // place for a running request to dump multiple logs, which will combine and save at the end of the overall request
  if (this.route === '') {
    return P._response.call(this, (ref9 = this.request.method) === 'HEAD' || ref9 === 'OPTIONS' ? '' : {
      name: this.S.name,
      version: this.S.version,
      env: this.S.env,
      built: (this.S.dev ? this.S.built : void 0)
    });
  }
  this.routes = {};
  this.fn = '';
  _save = async(k, r, f) => {
    var indexed;
    if (f._kv) { //_kv should be set for things that MUST be in the kv - they won't be removed, but will be copied to index if _index is also true
      this.kv(k, r, (typeof f._kv === 'number' ? f._kv : void 0));
    }
    if (f._index && (f._kv === false || this.S.kv === false || this.S.index.immediate === true)) { // all indexing is bulked through kv unless _kv is false or overall kv is disabled in settings, or immediate indexing is true
      if (!(indexed = (await this.index(k, r)))) { // later, the _schedule should automatically move anything in kv that matches an indexed endpoint
        // try creating it - if already done it just returns a 404 anyway
        if (!(indexed = (await this.index(k.split('/')[0], (typeof f._index !== 'object' ? {} : {
          settings: f._index.settings,
          mappings: f._index.mappings,
          aliases: f._index.aliases
        }))))) {
          return this.log({
            fn: r.split('/')[0].replace(/\_/g, '.'),
            msg: 'Could not save/create index',
            level: 'error'
          });
        } else {
          return this.index(k, r);
        }
      }
    }
  };
  _return = (fn, n) => {
    var _wrapped, wp;
    if (fn._sheet) {
      // if fn._sheet is true, look for corresponding sheet value in setttings? Don't do it where fn._sheet is defined in case settings get overridden?
      if (fn._index == null) {
        fn._index = true;
      }
    }
    wp = fn._index || fn._kv || (fn._bg && this.S.bg !== true); // what about _async?
    if (!wp && typeof fn === 'object' && !Array.isArray(fn) && typeof fn[this.request.method] !== 'function') {
      return JSON.parse(JSON.stringify(fn));
    } else if (!wp && !fn._kv && typeof fn !== 'function') {
      return fn;
    } else if (!wp && !fn._kv && n.indexOf('.') === -1 || n.split('.').pop().indexOf('_') === 0) { // don't wrap top-level or underscored methods
      return fn.bind(this);
    } else {
      _wrapped = async function() {
        var bgd, bu, bup, chd, key, lg, ref10, ref11, ref12, ref13, res, rt, st;
        st = Date.now(); // again, not necessarily going to be accurate in a workers environment
        rt = n.replace(/\./g, '_');
        chd = false;
        key = false;
        bgd = false;
        if ((!fn._bg || this.S.bg === true) && fn._index && ((this.fn === n && this.index._q(this.params)) || (this.fn !== n && (arguments.length === 1 && this.index._q(arguments[0]))) || (arguments.length === 2 && this.index._q(arguments[1])))) {
          res = this.index((arguments.length === 2 ? (ref10 = arguments[0]) != null ? ref10 : rt : rt), (arguments.length === 2 ? arguments[1] : arguments.length === 1 ? arguments[1] : this.params));
        }
        // TODO what about a kv direct read or write? should that be handled here too?
        if ((res == null) && !this.refresh && (((ref11 = this.request.method) === 'GET') || this.fn !== n) && (this.fn === n || arguments.length === 1) && (fn._kv || fn._index)) {
          // look for a pre-made answer if only a key was passed in, or if on the main fn with no data incoming
          // NOTE cache is regional, kv is global but 1s eventually consistent (although KV lookup from same region is immediately consistent)
          // NOTE also cache is not handled in this wrapper, it's handled before or directly in fetch calls - cache here means an already computed result available in index or kv
          // if cache, kv, or index is not configured, they'll all return undefined anyway so this will not block
          if (fn._kv) {
            res = (await this.kv(arguments.length ? rt + '/' + arguments[0].replace(/\//g, '_').replace(rt + '_', '') : void 0));
            if (res != null) {
              chd = 'kv'; // record if responding with cached result to whichever fn is currently running
            }
          }
          if (fn._index && (res == null)) {
            res = (await this.index(arguments.length ? rt + '/' + arguments[0].replace(/\//g, '_').replace(rt + '_', '') : void 0));
            if (res != null) {
              chd = 'index';
            }
          }
        }
        if (chd && this.fn.startsWith(n)) { // record whether or not the main function result was cached in index or kv
          this.cached = chd;
        }
        if ((res == null) && (fn._bg || fn._sheet) && typeof this.S.bg === 'string' && this.S.bg.indexOf('http') === 0) {
          bu = this.S.bg + '/' + n.replace(/\./g, '/') + (arguments.length && typeof arguments[0] === 'string' ? arguments[0] : '');
          bup = arguments.length && typeof arguments[0] === 'object' ? {
            method: 'POST',
            body: arguments[0]
          } : n === fn ? {
            method: 'POST',
            body: this.params
          } : {};
          if (this.S.name && this.S.system) {
            bup.headers = {};
            bup.headers['x-' + S.name + '-system'] = this.S.system;
          }
          try {
            res = (await this.fetch(bu, bup)); // does the worker timeout at 15s even if just waiting, not CPU time? test to find out. If so, race this and async it if necessary
            bgd = true;
          } catch (error) {}
        }
        if (res == null) {
          // if it's an index function with a sheet setting, or a sheet param has been provided, what to do by default?
          if (typeof fn === 'function') { // it could also be an index or kv config object with no default function
            res = (await ((ref12 = fn[this.request.method]) != null ? ref12 : fn).apply(this, arguments));
          }
          if ((res == null) && fn._sheet) { // this should happen on background where possible, because above will have routed to bg if it was available
            res = (await this.src.google.sheets(fn._sheet));
          }
          if (res != null) {
            if (fn._kv || fn._index) {
              try {
                key = (ref13 = res[fn._key]) != null ? ref13 : res._id;
                key = Array.isArray(key) ? key[0] : typeof key !== 'string' ? void 0 : key;
                key = key.replace(/\//g, '_').replace(rt + '_', rt + '/'); // anything else to reasonably strip?
                if (key.indexOf(rt) !== 0) {
                  key = rt + '/' + key;
                }
              } catch (error) {}
              if (key === false) {
                key = rt + '/' + this.uid();
              }
              key = key.toLowerCase(); // uid gen and index enforce this anyway, but to keep neat for logs, do here too
              this.waitUntil(_save(key, res, this.copy(fn)));
            }
          } else if (!arguments.length || arguments[0] === rt) {
            if (fn._index) {
              res = (await this.index(...arguments)); // just return a search endpoint - TODO may restrict this to a count depending on auth
            } else if (fn._kv) {
              res = ''; // return blank to indicate kv is present, because kv listing or counting is an expensive operation
            }
          }
        }
        //if n isnt @fn # main fn will log at the end - or should each part log as well anyway?
        lg = {
          fn: n,
          cached: (chd ? chd : void 0),
          bg: (bg ? bg : void 0),
          key: (key ? key : chd && arguments.length ? arguments[0].toLowerCase() : void 0)
        };
        //try lg.result = if key then undefined else if chd then (if arguments.length then arguments[0] else undefined) else undefined
        //JSON.stringify res # is it worth storing the whole result here? only if history? or always?
        // if fn._diff, need to decide when or how often to do a diff check and alert
        if (fn._index || fn._kv) {
          try {
            if (arguments.length) {
              lg.args = JSON.stringify([...arguments]);
            }
          } catch (error) {}
          try {
            lg.result = res != null;
          } catch (error) {}
        }
        try {
          lg.took = Date.now() - st;
        } catch (error) {}
        //try lg.args = JSON.stringify [...arguments]
        this.log(lg);
        return res;
      };
      return _wrapped.bind(this);
    }
  };
  // TODO decide if it's worth also having named params in object names such as _name_
  // TODO add a way to iterate mutliple functions either parallel or serial, adding to results
  // e.g. split url at // for multi functions. Params parallel gives on obj of named results
  // with merge for one result overwriting as they're received, or if only merge then merge in order
  // auth would need to be present for every stage
  fn = void 0;
  prs = [...this.parts];
  pk = void 0;
  _lp = (p, a, n) => {
    var k, ref10, ref11, results, wk;
    wk = false;
    if ((n === '' || (pk && ('.' + n).endsWith('.' + pk + '.'))) && prs.length) {
      if ((ref10 = typeof p[prs[0]]) === 'function' || ref10 === 'object') {
        this.fn += (this.fn === '' ? '' : '.') + prs[0];
        pk = prs.shift();
        wk = pk;
      } else if (pk) {
        this.params[pk] = this.params[pk] ? this.params[pk] + '/' + prs[0] : prs[0];
        prs.shift();
      }
    }
    results = [];
    for (k in p) {
      a[k] = _return(p[k], n + k);
      if ((ref11 = typeof a[k]) === 'function' || ref11 === 'object') {
        if (typeof a[k] === 'function') {
          if (!k.startsWith('_')) {
            if (k === wk && n.indexOf('._') === -1) { // URL routes can't call _abc functions or ones under them
              fn = a[k];
            }
            this.routes[n + k] = ''; // TODO this should read from the auth method, and also search top of function for description comment?
          }
        }
        if (!Array.isArray(p[k]) && (!k.startsWith('_') || typeof p[k] === 'function')) {
          results.push(_lp(p[k], a[k], n + k + '.'));
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
  // if no function found, fall back to server? - fail open setting may be good enough
  // check the blacklist
  res = void 0;
  if (typeof fn === 'function') {
    if (this.S.name && this.S.system && this.headers['x-' + S.name + '-system'] === this.S.system) {
      authd = true; // would this be sufficient or could original user be required too
    } else {
      authd = this.auth(); // check auth even if no function?
      if (typeof authd === 'object' && authd._id && authd.email) {
        this.user = authd;
      }
      if (typeof fn._auth === 'function') {
        authd = (await fn._auth());
      } else if (fn._auth === true && (this.user != null)) { // just need a logged in user if true
        authd = true;
      } else if (fn._auth) { // which should be a string... comma-separated, or a list
        // how to default to a list of the role groups corresponding to the URL route? empty list?
        authd = (await this.auth.role(fn._auth)); // _auth should be true or name of required group.role
      } else {
        authd = true;
      }
    }
    if (authd) { // auth needs to be checked whether the item is cached or not.
      // OR cache could use auth creds as part of the key?
      // but then what about where the result can be the same but served to different people? very likely, so better to auth first every time anyway
      if ((ref10 = this.request.method) === 'HEAD' || ref10 === 'OPTIONS') {
        res = '';
      } else if (fn._cache !== false && !this.refresh && ((ref11 = this.request.method) === 'GET') && (res = (await this._cache()))) { // this will return empty if nothing relevant was ever put in there anyway
        // how about POSTs that are obviously queries? how about caching of responses to logged in users, by param or header?
        this.cached = 'cache';
        resp = new Response(res.body, res); // no need to catch this for backend execution because cache functionwill never find anything on backend anyway
        resp.headers.append('x-' + this.S.name + '-cached', 'cache'); // this would leave any prior "index" value, for example. Or use .set to overwrite
        resp.headers.delete('x-' + this.S.name + '-took');
        this.log();
        return resp;
      } else if (this.S.bg === true) { // we're on the background server, no need to race a timeout
        res = (await fn());
        this.completed = true;
      } else {
        // if function set to bg, just pass through? if function times out, pass through? or fail?
        // or only put bg functions in bg code and pass through any routes to unknown functions?
        // but remember bg should be able to run everything if necessary
        _racer = async() => {
          res = (await fn());
          return this.completed = true;
        };
        await Promise.race([
          _racer(),
          this.sleep(14500) // race against time. CF worker will abort after 15s anyway so this has to be lower than that
        ]);
        // on timeout could call bg server, but may be better to have notifications, and processes that time out should just be moved to bg code anyway
        if (!this.completed) {
          res = {
            status: 408
          };
        }
      }
    } else {
      // Random delay for https://en.wikipedia.org/wiki/Timing_attack https://www.owasp.org/index.php/Blocking_Brute_Force_Attacks#Finding_Other_Countermeasures
      await this.sleep(200 * (1 + Math.random()));
      res = {
        status: 401
      };
    }
  }
  if (this.url.replace('.ico', '').replace('.gif', '').replace('.png', '').endsWith('/favicon')) {
    if (res == null) {
      res = '';
    }
  }
  resp = (await this._response(res));
  if (this.parts.length && ((ref12 = this.parts[0]) !== 'log' && ref12 !== 'status') && ((ref13 = this.request.method) !== 'HEAD' && ref13 !== 'OPTIONS') && (res != null) && res !== '') {
    if ((fn != null) && fn._cache !== false && this.completed && resp.status === 200) {
      this._cache(void 0, resp, fn._cache); //.clone() # need to clone here? or is at cache enough? Has to be cached before being read and returned
    }
    this.log(); // logging from the top level here should save the log to kv - don't log if unlog is present and its value matches a secret key?
  }
  return resp;
};

P._response = function(res) {
  var base, base1, h, keys, ref, status;
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
  if (this.S.headers['Content-Type'] == null) {
    try {
      res = JSON.stringify(res, '', 2);
    } catch (error) {}
    this.S.headers['Content-Type'] = 'application/json; charset=UTF-8';
  }
  try {
    if ((base1 = this.S.headers)['Content-Length'] == null) {
      base1['Content-Length'] = Buffer.byteLength(res);
    }
  } catch (error) {}
  try {
    this.S.headers['x-' + this.S.name + '-took'] = Date.now() - this.started;
  } catch (error) {}
  try {
    if (this.cached) {
      this.S.headers['x-' + this.S.name + '-cached'] = this.cached;
    }
  } catch (error) {}
  try {
    // TODO add formatting if the URL ended with .csv or something like that (or header requested particular format)
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

P.src = {};

P.svc = {};

// curl -X GET "https://api.lvatn.com/auth" -H "x-id:YOURUSERIDHERE" -H "x-apikey:YOURAPIKEYHERE"
// curl -X GET "https://api.lvatn.com/auth?apikey=YOURAPIKEYHERE"

// store user record object in kv as user/:UID (value is stringified json object)
// store a map of email(s) to UID user/email/:EMAIL (or email hash) (value is a UID)
// and store a map of API keys as well, user/apikey/:KEY (value is user ID) (could have more than one, and have ones that give different permissions)
// store a login token at auth/token/:TOKEN (value is email, or maybe email hash) (autoexpire login tokens at 15mins 900s)
// and store a resume token at auth/resume/:UID/:RESUMETOKEN (value is a timestamp) (autoexpire resume tokens at about six months 15768000s, but rotate them on non-cookie use)
var indexOf = [].indexOf;

P.auth = async function(key, val) {
  var cookie, eml, ref, ref1, ref2, ref3, ref4, ref5, restok, resume, uid, upd, user;
  try {
    if (this.S.name && this.S.system && this.headers['x-' + S.name + '-system'] === this.S.system) {
      // TODO add a check for a system header that the workers can pass to indicate they're already authorised
      // should this be here and/or in roles, or in the main api file? and what does it return?
      return true;
    }
  } catch (error) {}
  
  //if key? and val?
  // if at least key provided directly, just look up the user
  // if params.auth, someone looking up the URL route for this acc. Who would have the right to see that?
  if (typeof key === 'string') {
    return (await this.kv('user/' + key));
  }
  
  // TODO ensure this only does kv lookups (which cost money) when the necessary values are available
  // that way it can maybe just run on every request without impact if nothing provided
  if ((this.params.access_token == null) || !(user = (await this.oauth()))) {
    if (this.params.token && (eml = (await this.kv('auth/token/' + this.params.token, '')))) { // true causes delete after found
      if (uid = (await this.kv('user/email/' + eml))) {
        user = (await this.kv('user/' + uid)); // get the user record if it already exists
      }
      if (user == null) {
        user = (await this.auth._insert(eml)); // create the user record if not existing, as this is the first token login attempt for this email address
      }
    }
    if (!user && this.apikey) {
      if (uid = (await this.kv('user/apikey/' + this.apikey))) {
        user = (await this.kv('user/' + uid)); // no user creation if apikey doesn't match here - only create on login token above 
      }
    }
    if (!user && ((this.params.resume != null) || this.cookie)) { // accept resume on a header too?
      uid = this.id;
      if (!uid && (this.params.email != null)) { // accept resume with email instead of id?
        uid = (await this.kv('user/email/' + this.params.email));
      }
      if (!(resume = this.params.resume)) { // login by resume token if provided in param or cookie
        // check where is cookie?
        try {
          cookie = JSON.parse(decodeURIComponent(this.cookie).split(((ref = (ref1 = (ref2 = S.auth) != null ? (ref3 = ref2.cookie) != null ? ref3.name : void 0 : void 0) != null ? ref1 : S.name) != null ? ref : 'n2') + "=")[1].split(';')[0]);
          resume = cookie.resume;
          uid = cookie.id;
        } catch (error) {}
      }
      if ((resume != null) && (uid != null) && (restok = (await this.kv('auth/resume/' + uid + '/' + resume, (this.params.resume ? '' : void 0))))) { // delete if not a cookie resume
        user = (await this.kv('user/' + uid));
      }
    }
  }
  if (typeof user === 'object' && user._id) {
    // if 2fa is enabled, request a second form of ID (see below about implementing 2fa)

    // record the user login timestamp, and if login came from a service the user does not yet have a role in, add the service user role
    // who can add the service param?
    if (this.params.service && (((ref4 = user.roles) != null ? ref4[this.params.service] : void 0) == null)) {
      upd = {};
      upd.roles = (ref5 = user.roles) != null ? ref5 : {};
      upd.roles[this.params.service] = 'user';
      this.kv('user/' + user._id, upd, user); // record the user login time?
    }
    if ((this.params.resume != null) || (this.params.token != null)) {
      // if a fresh login or resume token was used explicitly, provide a new resume token
      user.resume = this.uid();
      this.kv('auth/resume/' + user._id + '/' + user.resume, Date.now(), 7890000); //15768000 # resume token lasts three months
    }
  }
  
  //if @auth.role 'root', @user
  //  lg = msg: 'Root login from ' + @request.headers['x-forwarded-for'] + ' ' + @request.headers['cf-connecting-ip'] + ' ' + @request.headers['x-real-ip']
  //  lg.notify = subject: lg.msg
  //  @log lg

  // if this is called with no variables, and no defaults, provide a count of users?
  // but then if logged in and on this route, what does it provide? the user account?
  return user;
};

P.auth.token = async function(email, from, subject, text, html, template, url) {
  var ref, ref1, ref2, ref3, ref4, ref5, ref6, sent, token;
  if (email == null) {
    email = (ref = this.params.email) != null ? ref : '';
  }
  if (from == null) {
    from = (ref1 = (ref2 = S.auth) != null ? ref2.from : void 0) != null ? ref1 : 'nobody@example.com';
  }
  if (subject == null) {
    subject = (ref3 = (ref4 = S.auth) != null ? ref4.subject : void 0) != null ? ref3 : 'Please complete your login';
  }
  token = this.uid(8);
  if (url == null) {
    url = ((ref5 = (ref6 = this.params.url) != null ? ref6 : this.request.url) != null ? ref5 : 'https://example.com').split('?')[0].replace('/token', '') + '?token=' + token;
  }
  this.kv('auth/token/' + token, email, 900); // create a token that expires in 15 minutes
  if (from && email) {
    // see old code for an attempt to add a gmail login button - if that has simplified since then, add it now
    sent = (await this.mail.send({
      from: from,
      to: email,
      subject: subject,
      text: text != null ? text : 'Your login code is:\r\n\r\n{{TOKEN}}\r\n\r\nor use this link:\r\n\r\n{{URL}}\r\n\r\nnote: this single-use code is only valid for 15 minutes.',
      html: html != null ? html : '<html><body><p>Your login code is:</p><p><b>{{TOKEN}}</b></p><p>or click on this link</p><p><a href=\"{{URL}}\">{{URL}}</a></p><p>note: this single-use code is only valid for 15 minutes.</p></body></html>',
      //template: template
      params: {
        token: token,
        url: url
      }
    }));
    return sent; //sent?.data?.id ? sent?.id ? email
  } else {
    return token;
  }
};

// auth/role/:grl/:uid
// any logged in user can find out if any other user is in a role
P.auth.role = function(grl, uid) {
  var cascade, g, group, i, j, len, len1, ref, ref1, ref2, ref3, ref4, ri, rl, role, user;
  if (grl == null) {
    grl = this.params.role;
  }
  if ((grl == null) && typeof ((ref = this.opts) != null ? ref.auth : void 0) === 'string') {
    grl = this.opts.auth;
  }
  if (uid == null) {
    uid = this.user;
  }
  if (typeof grl === 'string' && grl.indexOf('/') !== -1) {
    if (uid == null) {
      uid = grl.split('/').pop();
      grl = grl.replace('/' + uid, '');
    }
  }
  user = (uid != null) && uid !== ((ref1 = this.user) != null ? ref1._id : void 0) ? this.user(uid) : this.user;
  if ((user != null ? user.roles : void 0) == null) {
    return false;
  }
  if (typeof grl === 'string') {
    grl = [grl];
  }
  for (i = 0, len = grl.length; i < len; i++) {
    g = grl[i];
    g = g.replace('/', '.');
    [group, role] = g.split('.');
    if (role == null) {
      role = group;
      group = '__global__';
    }
    if (group === user.id) { // user is owner on their own group
      return 'owner';
    }
    if (indexOf.call((ref2 = user.roles.__global__) != null ? ref2 : [], 'root') >= 0) {
      return 'root';
    }
    if (indexOf.call((ref3 = user.roles[group]) != null ? ref3 : [], role) >= 0) {
      return role;
    }
    if (user.roles[group] != null) {
      cascade = ['root', 'service', 'owner', 'super', 'admin', 'auth', 'bulk', 'delete', 'remove', 'create', 'insert', 'publish', 'put', 'draft', 'post', 'edit', 'update', 'user', 'get', 'read', 'info', 'public'];
      if (0 < (ri = cascade.indexOf(role))) {
        ref4 = cascade.splice(0, ri);
        for (j = 0, len1 = ref4.length; j < len1; j++) {
          rl = ref4[j];
          if (indexOf.call(user.roles[group], rl) >= 0) {
            return rl;
          }
        }
      }
    }
  }
  return false;
};

P.auth.roles = async function(user, grl, keep) {
  var base, group, ref, ref1, ref2, role;
  if (user == null) {
    user = (ref = this.user) != null ? ref : this.params.roles;
  }
  if (typeof user === 'string') {
    user = (await this.kv('user/' + user));
  }
  // what about one logged in user acting on the roles route of another?
  [group, role] = grl.split('.');
  if (role == null) {
    role = group;
    group = '__global__';
  }
  if ((ref1 = indexOf.call((ref2 = user.roles) != null ? ref2[group] : void 0, role) >= 0) != null ? ref1 : []) {
    if (keep != null) {
      user.roles[group].splice(user.roles[group].indexOf(role), 1);
      return this.kv('user/' + user._id, user);
    }
  } else {
    if ((base = user.roles)[group] == null) {
      base[group] = [];
    }
    user.roles.group.push(role);
    return this.kv('user/' + user._id, user);
  }
};

P.auth.logout = function(user) { // how about triggering a logout on a different user account
  if (user == null) {
    user = this.user;
  }
  if (user != null) {
    return this.kv('auth/resume/' + (typeof user === 'string' ? user : user._id), '');
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
P.oauth = async function(token, cid) {
  var ref, ref1, ref10, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, ret, sets, uid, user, validate;
  // https://developers.google.com/identity/protocols/OAuth2UserAgent#validatetoken
  sets = {};
  if (token == null) {
    token = this.params.access_token;
  }
  if (token) {
    try {
      // we did also have facebook oauth in here, still in old code, but decided to drop it unless explicitly required again
      validate = (await this.http.post('https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=' + token));
      if (cid == null) {
        cid = (ref = (ref1 = S.svc[(ref2 = this.params.service) != null ? ref2 : 'z']) != null ? (ref3 = ref1.google) != null ? (ref4 = ref3.oauth) != null ? (ref5 = ref4.client) != null ? ref5.id : void 0 : void 0 : void 0 : void 0) != null ? ref : (ref6 = S.use) != null ? (ref7 = ref6.google) != null ? (ref8 = ref7.oauth) != null ? (ref9 = ref8.client) != null ? ref9.id : void 0 : void 0 : void 0 : void 0;
      }
      if ((cid != null) && ((ref10 = validate.data) != null ? ref10.aud : void 0) === cid) {
        ret = (await this.http.get('https://www.googleapis.com/oauth2/v2/userinfo?access_token=' + token));
        if (uid = (await this.kv('user/email/' + ret.data.email))) {
          if (!(user = (await this.kv('user/' + uid)))) {
            user = (await this.auth._insert(ret.data.email));
          }
        }
        if (user.google == null) {
          sets.google = {
            id: ret.data.id
          };
        }
        if (ret.data.name) {
          if (!user.name) {
            sets.name = ret.data.name;
          }
        } else if (ret.data.given_name && !user.name) {
          sets.name = ret.data.given_name;
          if (ret.data.family_name) {
            sets.name += ' ' + ret.data.family_name;
          }
        }
        if (!user.avatar && ret.data.picture) {
          sets.avatar = ret.data.picture;
        }
      }
    } catch (error) {}
  }
  if ((user != null) && JSON.stringify(sets) !== '{}') {
    user = (await this.user.update(user.id, sets));
  }
  return user;
};

// the Oauth URL that would trigger something like this would be like:
// grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true'
// grl += '&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile'
// grl += '&state=' + state + '&redirect_uri=' + noddy.oauthRedirectUri + '&client_id=' + noddy.oauthGoogleClientId
// state would be something like Math.random().toString(36).substring(2,8) and would be sent and also kept for checking against the response
// the response from oauth login page would go back to current page and have a # with access_token= and state=
// NOTE as it is after a # these would only be available on a browser, as servers don't get the # part of a URL
// if the states match, send the access_token into the above method and if it validates then we can login the user
P.auth._insert = async function(key, val) {
  var em, first, ref, ref1, res, u, user;
  if (typeof key === 'string' && (val != null)) {
    if (val === '') {
      if (key.startsWith('user/')) {
        key = key.replace('user/', '');
      }
      user = ((ref = this.user) != null ? ref._id : void 0) === key ? this.user : (await this.kv('user/' + key));
      try {
        this.auth.logout(key);
      } catch (error) {}
      try {
        if (user.apikey != null) {
          this.kv('user/apikey/' + user.apikey, '-');
        }
      } catch (error) {}
      try {
        if (user.email != null) {
          this.kv('user/email/' + user.email, '-');
        }
      } catch (error) {}
      return this.kv('user/' + key, '');
    }
  } else {
    if (typeof key === 'string' && key.indexOf('@') !== -1 && key.indexOf('.') !== -1) { // put this through a validator, either/both a regex and a service
      //else # update the user with the provided val
      em = key;
    }
    if ((key == null) && (this != null ? (ref1 = this.user) != null ? ref1._id : void 0 : void 0)) {
      key = 'user/' + this.user._id;
    }
    if (key.indexOf('@') !== -1) {
      key = (await this.kv('user/email/' + key));
    }
    res = (await this.kv('user/' + key));
    if (res == null) {
      if (em) {
        u = {
          email: em.trim(), //store email here or not?
          apikey: this.uid(), // store the apikey here or not?
          profile: {}
        };
        first = false; // if no other user accounts yet
        u.roles = first ? {
          __global__: ['root']
        } : {};
        u.createdAt = Date.now();
        u._id = this.uid();
        this.kv('user/apikey/' + apikey, u._id);
        this.kv('user/email/' + email, u._id); // or hash of email
        this.kv('user/' + u._id, u);
        return u;
      } else {
        return void 0;
      }
    } else {
      return void 0;
    }
  }
};

P.auth._update = async function(r, user) {
  var a, nu, p;
  if (user == null) {
    user = r.auth; // what about update a user other than the logged in one?
  }
  if (r.param && (nu = this.auth(r.param))) {
    a = ''; // does the currently authorised user have permission to update the user being queried? if so, set user to nu
  }
  if (JSON.stringify(r.params) !== '{}') {
    if (user.profile == null) {
      user.profile = {};
    }
    // normal user can update profile values
    for (p in r.params) {
      user.profile[p] = pr[p];
    }
    await this.kv('user/' + user.id, user);
    return true; // or return the updated user object?
  } else {
    return false;
  }
};

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
    env: S.env,
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
      if (res.request == null) {
        res.request = this.request;
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
    request: this.request,
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

// https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch
P.fetch = async function(url, params) {
  var _f, ct, i, len, ref, ref1, res;
  // TODO if asked to fetch a URL that is the same as the @url this worker served on, then needs to switch to a bg call if bg URL available
  if (typeof url === 'object' && (params == null)) {
    params = url;
    url = params.url;
  }
  try {
    if (params == null) {
      params = this.copy(this.params);
    }
  } catch (error) {}
  if (params == null) {
    params = {};
  }
  if (!url && params.url) {
    url = params.url;
    delete params.url;
  }
  // if params is provided, and headers is in it, may want to merge with some default headers
  // see below for other things that can be set
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
    params.headers['Authorization'] = 'Basic ' + Buffer.from(params.auth).toString('base64'); // should be fine on node
    delete params.auth;
  }
  ref = ['data', 'content', 'json'];
  // where else might body content reasonably be?
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
  }
  console.log(url);
  if (typeof url !== 'string') {
    return false;
  } else {
    // if on the background server and not a worker, it will need node-fetch installed or an alternative to fetch must be used here
    _f = async() => {
      var r, response, verbose;
      if (params.verbose) {
        verbose = true;
        delete params.verbose;
      } else {
        verbose = false;
      }
      try {
        if (url.indexOf('localhost') !== -1) {
          // allow local https connections on backend server without check cert
          if (params.agent == null) {
            params.agent = new https.Agent({
              rejectUnauthorized: false
            });
          }
        }
      } catch (error) {}
      response = (await fetch(url, params));
      console.log(response.status); // status code can be found here
      if (verbose) {
        return response;
      } else {
        // json() # what if there is no json or text? how to tell? what other types are there? will json also always be presented as text?
        // what if the method is a POST, or the response is a stream?
        // does it make any difference if it can all be found in text() and converted here anyway?
        ct = response.headers.get('content-type');
        if (typeof ct === 'string' && ct.toLowerCase().indexOf('json') !== -1) {
          r = (await response.json());
        } else {
          r = (await response.text());
        }
        if (response.status === 404) {
          return void 0;
        } else if (response.status >= 400) {
          console.log(r);
          return {
            status: response.status
          };
        } else {
          return r;
        }
      }
    };
    'if params.timeout\n  params.retry ?= 1\n  params.timeout = 30000 if params.timeout is true\nif params.retry\n  params.retry = 3 if params.retry is true\n  opts = retry: params.retry\n  delete params.retry\n  for rk in [\'pause\', \'increment\', \'check\', \'timeout\']\n    if params[rk]?\n      opts[rk] = params[rk]\n      delete params[rk]\n  res = @retry.call this, _f, [url, params], opts\nelse';
    res = (await _f());
    try {
      res = res.trim();
      if (res.indexOf('[') === 0 || res.indexOf('{') === 0) {
        res = JSON.parse(res);
      }
    } catch (error) {}
    return res;
  }
};

'# https://stackoverflow.com/questions/46946380/fetch-api-request-timeout/46946573#46946573\ntimeout = (ms, promise) ->\n  return new Promise (resolve, reject) =>\n    timer = setTimeout () =>\n      reject new Error \'TIMEOUT\'\n    , ms\n    promise\n      .then value =>\n        clearTimeout timer\n        resolve value\n      .catch reason =>\n        clearTimeout timer\n        reject reason\n\ntimeout 1000, fetch \'/hello\'\n  .then (response) ->\n    r = response # do something with response\n  .catch (error) ->\n    e = error # do something with error\n    \n\nP.proxy = (url, params={}) ->\n  if typeof url is \'object\'\n    params = url\n    url = undefined\n  params.proxy ?= S.proxy\n  return P.fetch url, params\n\n\n  response = await fetch(url, # how to set timeout on fetch\n    method: method\n    body: body\n    #cf:\n    #  mirage: true\n    #  polish: "lossy"\n    #  cacheTtl: ttl ?= 300\n    #  cacheTtlByStatus:\n    #    "200-299": ttl\n    #    "300-399": 120\n    #    "400-499": 60\n    #    "500-599": 0\n    headers:\n      "Content-Type": type\n      "User-Agent": "n2/4.0.1")\n\n# Send a Http request and get a Buffer response.\nexport buffer = (url, {body, ttl, base64} = {}) ->\n  base64 ?= true\n  request(url,\n    ttl: ttl,\n    body: body\n    parser: ((response) ->\n      response = await response.arrayBuffer()\n      if base64\n        response = response.asBase64()\n      response))';

if (S.log == null) {
  S.log = {};
}

// it would also be good to log every fetch, and what was sent with it too, although if it was a big file or something like that, then not that
// what about a param to pass to avoid logging?
P.log = function(msg) {
  var i, j, l, len, len1, ref, ref1, ref2, store;
  store = msg == null; // an empty call to log stores everything in the _logs list
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
      // receive a remote log
      msg = typeof this.body === 'object' ? {
        logs: this.body
      } : this.params; // bunch of logs sent in as POST body, or else just params
      if (msg.fn == null) {
        msg.fn = this.params.log; // the fn, if any, would be in params.log (because @fn would just be log)
      }
    }
    if (msg == null) {
      msg = {};
    }
    try {
      msg.request = {
        url: this.request.url,
        method: this.request.method,
        body: this.request.bodyUsed
      };
    } catch (error) {}
    try {
      msg.request.cf = {
        colo: this.request.cf.colo,
        country: this.request.cf.country
      };
    } catch (error) {}
    try {
      msg.request.headers = {
        ip: this.headers['x-real-ip'],
        'user-agent': this.headers['user-agent'],
        referer: this.headers.referer
      };
    } catch (error) {}
    try {
      if (msg.fn == null) {
        msg.fn = this.fn;
      }
      msg.params = this.params;
      msg.refresh = this.refresh;
      msg.parts = this.parts;
      msg.completed = this.completed;
      msg.cached = this.cached;
    } catch (error) {}
    try {
      msg.apikey = (this.headers.apikey != null) || (this.headers['x-apikey'] != null);
    } catch (error) {}
    try {
      msg.user = (ref = this.user) != null ? ref._id : void 0;
    } catch (error) {}
  }
  if (store) {
    if (msg.logs == null) {
      msg.logs = [];
    }
    if (Array.isArray(this != null ? this._logs : void 0) && this._logs.length) {
      ref1 = this._logs;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        l = ref1[j];
        //msg.msg ?= l.msg
        if (msg.alert == null) {
          msg.alert = l.alert;
        }
        if (msg.notify == null) {
          msg.notify = l.notify;
        }
        msg.logs.push(l);
      }
    }
    if (msg.createdAt == null) {
      msg.createdAt = Date.now();
    }
    if (msg.name == null) {
      msg.name = S.name;
    }
    if (msg.version == null) {
      msg.version = S.version;
    }
    if (msg.env == null) {
      msg.env = S.env;
    }
    try {
      msg.started = this.started;
      msg.took = Date.now() - this.started;
    } catch (error) {}
    msg._id = 'log/' + ((ref2 = this.rid) != null ? ref2 : this.uid());
    this.kv(msg);
  } else {
    this._logs.push(msg);
  }
  if (S.log === false || S.bg === true) { // is this useful?
    console.log('Server not logging:');
    return console.log(msg);
  }
};

P.log.schedule = function() {
  // this should become _schedule but for now is not so I can manually trigger it for testing
  // define what to do on a scheduled trigger
  // grab every log in the kv store and throw them to the index
  // but for now, just delete them
  return this.kv._each('log', '');
};

'P.add \'mail/feedback/:token\',\n  get: () ->\n    try\n      from = this.queryParams.from ? P.settings.mail?.feedback?[this.urlParams.token]?.from ? "sysadmin@cottagelabs.com"\n      to = P.settings.mail?.feedback?[this.urlParams.token]?.to\n      service = P.settings.mail?.feedback?[this.urlParams.token]?.service\n      subject = P.settings.mail?.feedback?[this.urlParams.token]?.subject ? "Feedback"\n    if to?\n      P.mail.send\n        service: service\n        from: from\n        to: to\n        subject: subject\n        text: this.queryParams.content\n    return {}\n\n\nlevel/loglevel\ngroup (default to whatever is after svc or src, or just part 0)\nnotify/alert\n\nP.log = (opts, fn, lvl=\'debug\') ->\n\n    loglevels = [\'all\', \'trace\', \'debug\', \'info\', \'warn\', \'error\', \'fatal\', \'off\']\n    loglevel = P.settings.log?.level ? \'all\'\n    if loglevels.indexOf(loglevel) <= loglevels.indexOf opts.level\n      if opts.notify and P.settings.log?.notify\n        try\n          os = @copy opts\n        catch\n          os = opts\n        Meteor.setTimeout (() -> P.notify os), 100\n\n      for o of opts\n        if not opts[o]?\n          delete opts[o]\n        else if typeof opts[o] isnt \'string\' and not _.isArray opts[o]\n          try\n            opts[o] = JSON.stringify opts[o]\n          catch\n            try\n              opts[o] = opts[o].toString()\n            catch\n              delete opts[o]\n\n      if loglevels.indexOf(loglevel) <= loglevels.indexOf \'debug\'\n        console.log opts.msg if opts.msg\n\n  if typeof notify is \'string\'\n    if note.indexOf \'@\' isnt -1\n      note = to: note\n\n  if typeof note is \'object\'\n    note.text ?= note.msg ? opts.msg\n    note.subject ?= P.settings.name ? \'API log message\'\n    note.from ?= P.settings.log?.from ? \'alert@cottagelabs.com\'\n    note.to ?= P.settings.log?.to ? \'mark@cottagelabs.com\'\n    P.mail.send note\n\n\n\n\nP.ping = (url,shortid) ->\n  return false if not url?\n  url = \'http://\' + url if url.indexOf(\'http\') isnt 0\n  if (not shortid? or shortid is \'random\') and spre = pings.find {url:url,redirect:true}\n    return spre._id\n  else\n    obj = {url:url,redirect:true}\n    if shortid? and shortid isnt \'random\'\n      while already = pings.get shortid\n        shortid += Random.hexString(2)\n      obj._id = shortid\n    return pings.insert obj\n\n# craft an img link and put it in an email, if the email is viewed as html it will load the URL of the img,\n# which actually hits this route, and allows us to record stuff about the event\n\n# so for example for oabutton where this was first created for, an image url like this could be created,\n# with whatever params are required to be saved, in addition to the nonce.\n# On receipt the pinger will grab IP and try to retrieve location data from that too:\n# <img src="https://api.cottagelabs.com/ping/p.png?n=<CURRENTNONCE>service=oabutton&id=<USERID>">\n\nP.ping.png = () ->\n  if not P.settings.ping?.nonce? or this.queryParams.n is P.settings.ping.nonce\n    data = this.queryParams\n    delete data.n\n    data.ip = this.request.headers[\'x-forwarded-for\'] ? this.request.headers[\'cf-connecting-ip\'] ? this.request.headers[\'x-real-ip\']\n    data.forwarded = this.request.headers[\'x-forwarded-for\']\n    try\n      res = HTTP.call \'GET\', \'http://ipinfo.io/\' + data.ip + (if P.settings?.use?.ipinfo?.token? then \'?token=\' + P.settings.use.ipinfo.token else \'\')\n      info = JSON.parse res.content\n      data[k] = info[k] for k of info\n      if data.loc\n        try\n          latlon = data.loc.split(\',\')\n          data.lat = latlon[0]\n          data.lon = latlon[1]\n    pings.insert data\n  img = new Buffer(\'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP4z8BQDwAEgAF/posBPQAAAABJRU5ErkJggg==\', \'base64\');\n  if this.queryParams.red\n    img = new Buffer(\'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=\', \'base64\')\n  this.response.writeHead 200,\n    \'Content-disposition\': "inline; filename=ping.png"\n    \'Content-type\': \'image/png\'\n    \'Content-length\': img.length\n    \'Access-Control-Allow-Origin\': \'*\'\n\n    this.response.end img\n\nP.add \'ping/:shortid\',\n  get: () ->\n    if this.urlParams.shortid is \'random\' and this.queryParams.url\n      # may want to disbale this eventually as it makes it easy to flood the server, if auth is added on other routes\n      return P.ping this.queryParams.url, this.urlParams.shortid\n    else if exists = pings.get(this.urlParams.shortid) and exists.url?\n        count = exists.count ? 0\n        count += 1\n        pings.update exists._id, {count:count}\n        return\n          statusCode: 302\n          headers:\n            \'Content-Type\': \'text/plain\'\n            \'Location\': exists.url\n          body: \'Location: \' + exists.url\n    else return 404\n  put:\n    authRequired: true\n    action: () ->\n      # certain user groups can overwrite a shortlink\n      # TODO: overwrite a short link ID that already exists, or error out\n  post: () ->\n    return P.ping (this.request.body.url ? this.queryParams.url), this.urlParams.shortid\n  delete:\n    #authRequired: true\n    action: () ->\n      if exists = pings.get this.urlParams.shortid\n        pings.remove exists._id\n        return true\n      else\n        return 404';

P.mail = async function(opts) {
  var f, i, len, ms, o, p, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, s, url;
  if ((ref = S.mail) != null ? ref.disabled : void 0) {
    return {};
  }
  if ((opts == null) && (((this != null ? this.params : void 0) != null) || ((this != null ? this.opts : void 0) != null))) {
    opts = (ref1 = this != null ? this.params : void 0) != null ? ref1 : {};
    for (o in this.params) {
      opts[o] = this.params[o];
    }
  }
  if (!opts.text && !opts.html) {
    opts.text = (ref2 = (ref3 = opts.content) != null ? ref3 : opts.body) != null ? ref2 : "";
  }
  delete opts.content;
  try {
    ref4 = ['subject', 'text', 'html', 'template'];
    for (i = 0, len = ref4.length; i < len; i++) {
      s = ref4[i];
      if (opts[s] != null) {
        for (p in opts.params) {
          opts[s] = opts[s].replace('{{' + p.toUpperCase() + '}}', opts.params[p]);
        }
      }
    }
  } catch (error) {}
  // this should be stand-alone called method somewhere...
  // should be case insensitive, and remove multiples, not just first occurrence
  // and do a delete of any template values that could not be replaced

  // can also take opts.headers

  // also takes opts.attachments, but not required. Should be a list of objects as per
  // how do attachments work if not on mail_url, can they be sent by API?
  // https://github.com/nodemailer/mailcomposer/blob/v4.0.1/README.md#attachments
  ms = (opts.svc != null) && (((ref5 = S.svc) != null ? (ref6 = ref5[opts.svc]) != null ? ref6.mail : void 0 : void 0) != null) ? S.svc[opts.svc].mail : S.mail;
  if (opts.from == null) {
    opts.from = ms.from;
  }
  if (opts.to == null) {
    opts.to = ms.to;
  }
  delete opts.svc;
  delete opts.template; // what to actually do with this now...
  delete opts.params;
  url = 'https://api.mailgun.net/v3/' + ms.domain + '/messages';
  if (Array.isArray(opts.to)) {
    opts.to = opts.to.join(',');
  }
  f = (ref7 = this != null ? this.fetch : void 0) != null ? ref7 : P.fetch;
  return (await f(url, {
    method: 'POST',
    body: opts,
    headers: {
      auth: 'api:' + ms.apikey
    }
  }));
};

P.mail.validate = async function(e, apikey) {
  var f, ref, ref1, ref2;
  if (apikey == null) {
    apikey = (ref = S.mail) != null ? ref.pubkey : void 0;
  }
  if (e == null) {
    e = this != null ? (ref1 = this.params) != null ? ref1.email : void 0 : void 0;
  }
  if (typeof e === 'string' && typeof apikey === 'string') {
    // also add a simple regex validator if mailgun validation is not available - and cache the validations
    f = (ref2 = this != null ? this.fetch : void 0) != null ? ref2 : P.fetch;
    return (await f('https://api.mailgun.net/v3/address/validate?syntax_only=false&address=' + encodeURIComponent(e.params.email) + '&api_key=' + apikey));
  }
};

P.puppet = {
  _bg: true
};

var base, base1, base2;

if (S.mail == null) {
  S.mail = {};
}

if ((base = S.mail).from == null) {
  base.from = "alert@cottagelabs.com";
}

if ((base1 = S.mail).to == null) {
  base1.to = "mark@cottagelabs.com";
}

if ((base2 = S.src).google == null) {
  base2.google = {};
}

try {
  S.src.google.secrets = JSON.parse(SECRETS_GOOGLE);
} catch (error) {}

P.status = function() {
  var i, k, len, ref, res;
  res = {
    name: S.name,
    version: S.version,
    env: S.env,
    built: S.built
  };
  if (S.dev) {
    ref = ['id', 'request', 'params', 'parts', 'opts', 'headers', 'cookie', 'user', 'fn', 'routes'];
    for (i = 0, len = ref.length; i < len; i++) {
      k = ref[i];
      if (this.S.bg !== true || k !== 'request') {
        try {
          if (res[k] == null) {
            res[k] = this[k];
          }
        } catch (error) {}
      }
    }
  }
  // add an uncached check that the backend is responding, and whether or not an index/kv is available, and whether on a worker or a backend
  // if index is available get some info about it - from index.status
  // if there are status endpoints further down the stack, call them all too if a certain param is passed
  // maybe useful things like how many accounts, how many queued jobs etc - prob just get those from status endpoints on the stack
  // maybe some useful info from the recent logs too
  return res;
};

var indexOf = [].indexOf;

P.tdm = {};

P.tdm.clean = function(text) {
  var _bad_chars, c, l, len, re, ref, ref1, ref2, ref3, ref4;
  if (text == null) {
    text = (ref = (ref1 = this != null ? (ref2 = this.params) != null ? ref2.clean : void 0 : void 0) != null ? ref1 : this != null ? (ref3 = this.params) != null ? ref3.text : void 0 : void 0) != null ? ref : this != null ? (ref4 = this.params) != null ? ref4.q : void 0 : void 0;
  }
  _bad_chars = [
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
  for (l = 0, len = _bad_chars.length; l < len; l++) {
    c = _bad_chars[l];
    re = new RegExp(c.bad, 'g');
    text = text.replace(re, c.good);
  }
  return text;
};

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

P.tdm.extract = function(opts) {
  var l, lastslash, len, m, match, mopts, mr, parts, ref, ref1, res, text;
  // opts expects url,content,matchers (a list, or singular "match" string),start,end,convert,format,lowercase,ascii
  if (opts.url && !opts.content) {
    if (opts.url.indexOf('.pdf') !== -1 || opts.url.indexOf('/pdf') !== -1) {
      if (opts.convert == null) {
        opts.convert = 'pdf';
      }
    } else {
      opts.content = P.http.puppeteer(opts.url, true);
    }
  }
  try {
    text = opts.convert ? P.convert.run((ref = opts.url) != null ? ref : opts.content, opts.convert, 'txt') : opts.content;
  } catch (error) {
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
    ref1 = opts.matchers;
    for (l = 0, len = ref1.length; l < len; l++) {
      match = ref1[l];
      mopts = 'g';
      if (opts.lowercase) {
        mopts += 'i';
      }
      if (match.indexOf('/') === 0) {
        lastslash = match.lastIndexOf('/');
        if (lastslash + 1 !== match.length) {
          mopts = match.substring(lastslash + 1);
          match = match.substring(1, lastslash);
        }
      } else {
        match = match.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&");
      }
      m;
      mr = new RegExp(match, mopts);
      while (m = mr.exec(text)) {
        res.matched += 1;
        res.matches.push({
          matched: match,
          result: m
        });
      }
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

var indexOf = [].indexOf;

import {
  customAlphabet
} from 'nanoid';

P.uid = function(r) {
  var nanoid, ref, ref1, ref2, ref3, ref4;
  // have to use only lowercase for IDs, because other IDs we receive from users such as DOIs
  // are often provided in upper OR lowercase forms, and they are case-insensitive, so all IDs
  // will be normalised to lowercase. This increases the chance of an ID collision, but still, 
  // without uppercases it's only a 1% chance if generating 100) IDs per second for 131000 years.
  nanoid = customAlphabet((ref = this.params.alphabet) != null ? ref : '0123456789abcdefghijklmnopqrstuvwxyz-', (ref1 = (ref2 = (ref3 = (ref4 = this.params.len) != null ? ref4 : this.params.length) != null ? ref3 : this.params.size) != null ? ref2 : this.params.uid) != null ? ref1 : 21);
  return nanoid();
};

P.uid._cache = false;

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

P.hash = async function(msg) {
  var arr, b, buf, i, len, parts, ref, ref1, ref2;
  try {
    if (msg == null) {
      msg = (ref = (ref1 = (ref2 = this.params.hash) != null ? ref2 : this.request.body) != null ? ref1 : this.params.q) != null ? ref : this.params;
    }
  } catch (error) {}
  if (typeof msg !== 'string') {
    msg = JSON.stringify(msg);
  }
  msg = new TextEncoder().encode(msg);
  buf = (await crypto.subtle.digest("SHA-256", msg));
  arr = new Uint8Array(buf);
  parts = [];
  for (i = 0, len = arr.length; i < len; i++) {
    b = arr[i];
    parts.push(('00' + b.toString(16)).slice(-2));
  }
  return parts.join('');
};

// the above works on CF worker, but crypto.subtle probably needs to be replaced with standard crypto module on backend
// the below is a possible example, but note will need to use same params that generate the same result
'P.hash = (str, lowercase=false, uri=true, encoding=\'utf8\', digest) -> # alternatively base64, but can cause problems if later used in URLs\nstr = str.toLowerCase() if lowercase is true\nstr = encodeURIComponent(str) if uri is true\nhash = crypto.createHash(\'md5\').update(str, encoding)\nreturn if digest is \'hex\' then hash.digest(\'hex\') else hash.digest(\'base64\').replace(/\//g,\'_\').replace(/\+/g,\'-\')';

P.dot = function(obj, key) {
  var i, k, len, ref, st;
  // TODO can add back in a way to pass in values or deletions if necessary, and traversing lists too
  if (typeof obj === 'string' && typeof key === 'object') {
    st = obj;
    obj = key;
    key = st;
  }
  if (obj != null) {
    obj = this.copy(obj);
  }
  if ((obj == null) && ((this != null ? (ref = this.params) != null ? ref.key : void 0 : void 0) != null)) {
    obj = this.copy(this.params);
    key = obj.key;
    delete obj.key;
  }
  if (typeof key === 'string') {
    key = key.split('.');
  }
  for (i = 0, len = key.length; i < len; i++) {
    k = key[i];
    obj = obj[k];
  }
  return obj;
};

'P.retry = (fn, params=[], opts={}) ->\n  # params should be a list of params for the fn\n  params = [params] if not Array.isArray params\n  opts.retry ?= 3\n  opts.pause ?= 500\n  opts.increment ?= true\n  # can provide a function in opts.check to check the result each time, and an opts.timeout to timeout each loop\n\n  while opts.retry > 0\n    res = undefined\n    _wrap = () ->\n      try\n        res = await fn.apply this, params\n    if typeof opts.timeout is \'number\'\n      await Promise.race [_wrap.call(this), P.sleep(opts.timeout)]\n    else\n      _wrap.call this\n    if typeof opts.check is \'function\'\n      retry = await opts.check res, retry\n      if retry is true\n        return res\n      else if retry is false\n        retry -= 1\n      else if typeof retry isnt \'number\'\n        retry = 0\n    else if res? and res isnt false\n      return res\n    else\n      retry -= 1\n\n    if typeof opts.pause is \'number\' and opts.pause isnt 0\n      await P.sleep opts.pause\n      if opts.increment is true\n        opts.pause = opts.pause * 2\n      else if typeof opts.increment is \'number\'\n        opts.pause += opts.increment\n    \n  return undefined';

'# see https://github.com/arlac77/fetch-rate-limit-util/blob/master/src/rate-limit-util.mjs\nMIN_WAIT_MSECS = 1000 # wait at least this long\nMAX_RETRIES = 5 # only retry max this many times\n\n/**\n * @param {Integer} millisecondsToWait\n * @param {Integer} rateLimitRemaining parsed from "x-ratelimit-remaining" header\n * @param {Integer} nthTry how often have we retried the request already\n * @param {Object} response as returned from fetch\n * @return {Integer} milliseconds to wait for next try or < 0 to deliver current response\n */\ndefaultWaitDecide = (millisecondsToWait, rateLimitRemaining, nthTry, response) ->\n  return if nthTry > MAX_RETRIES then -1 else millisecondsToWait + MIN_WAIT_MSECS\n\nrateLimitHandler = (fetcher, waitDecide = defaultWaitDecide) ->\n  i = 0\n  while true\n    response = await fetcher()\n\n    switch (response.status) ->\n      default:\n        return response\n\n      case 403:\n      case 429:\n        # this differs by API we\'re hitting, example was for github. \n        # It\'s the timestamp of when the rate limit window would reset, generalise this\n        rateLimitReset = parseInt response.headers.get "x-ratelimit-reset"\n\n        millisecondsToWait = if isNaN(rateLimitReset) then 0 else new Date(rateLimitReset * 1000).getTime() - Date.now()\n\n        millisecondsToWait = waitDecide(millisecondsToWait, parseInt(response.headers.get("x-ratelimit-remaining")), i, response)\n        if millisecondsToWait <= 0\n          return response\n        else\n          await new Promise resolve => setTimeout resolve, millisecondsToWait\n    i++';

'P.decode = (content) ->\n  _decode = (content) ->\n    # https://stackoverflow.com/questions/44195322/a-plain-javascript-way-to-decode-html-entities-works-on-both-browsers-and-node\n    translator = /&(nbsp|amp|quot|lt|gt);/g\n    translate = {\n      "nbsp":" ",\n      "amp" : "&",\n      "quot": "\"",\n      "lt"  : "<",\n      "gt"  : ">"\n    }\n    return content.replace(translator, ((match, entity) ->\n      return translate[entity]\n    )).replace(/&#(\d+);/gi, ((match, numStr) ->\n      num = parseInt(numStr, 10)\n      return String.fromCharCode(num)\n    ))\n  return _decode(content).replace(/\n/g,\'\')\n\nP.str = (r) ->\n  str = \'\'\n  _str = (rp) ->\n    if typeof rp is \'string\'\n      return rp\n    else if rp is true\n      return \'true\'\n    else if rp is false\n      return \'false\'\n    else if typeof rp is \'function\'\n      return rp.toString()\n    else if Array.isArray rp\n      cr = []\n      cr.push(_str a) for a in rp\n      return JSON.stringify cr.sort()\n    else if typeof rp is \'object\'\n      nob = \'\'\n      keys = []\n      keys.push(k) for k of rp\n      for k in keys.sort()\n        if nob.length is 0\n          nob = \'{\'\n        else\n          nob += \',\'\n        nob += \'"\' + o + \'":"\' + _str(rp[o]) + \'"\' for o of rp\n      return nob + \'}\'\n  str += _str r\n  return str\n\nP.flatten = (data) ->\n  res = {}\n  _flatten = (obj, key) ->\n    for k of obj\n      pk = if key then key + \'.\' + k else k\n      v = obj[k]\n      if typeof v is \'string\'\n        res[pk] = v\n      else if Array.isArray v\n        if typeof v[0] is \'object\'\n          for n of v\n            _flatten v[n], pk + \'.\' + n\n        else\n          res[pk] = v.join(\', \')\n      else\n        _flatten v, pk\n  if Array.isArray data\n    results = []\n    for d in data\n      res = {}\n      results.push _flatten d\n    return results\n  else\n    _flatten data\n    return res\n';

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
P._cache = async function(request, response, age) {
  var ck, cu, h, hp, i, len, ref, rp, rs, url;
  if (typeof age !== 'number') {
    age = typeof this.S.cache === 'number' ? this.S.cache : this.S.dev ? 300 : 3600; // how long should default cache be?
  }
  // age is max age in seconds until removal from cache (note this is not strict, CF could remove for other reasons)
  // request and response needs to be an actual Request and Response objects
  // returns promise wrapping the Response object
  if (this.S.cache === false || this.S.bg === true) { // can change this if a backend cache mechanism is added later (prob not worthwhile)
    return void 0;
  } else {
    try {
      if (request == null) {
        request = this.request;
      }
      try {
        url = request.url.toString();
        ref = ['refresh'];
        // should caches be keyed to apikey? what about headers? Do they affect caching?
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
        ck = new Request(cu.toString(), request);
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
          return this.waitUntil(caches.default.put(ck, rp));
        }
      } catch (error) {
        return void 0;
      }
    } else {
      return void 0;
    }
  }
};

  // TODO be able to receive bulk json lists or formatted bulk strings. Need to stick the useful default values into each
  // those would be createdAt, created_date (in default templates format for ES 7.1) and user ID of the action?

  // TODO if history true, saving any change should be preceded by saving a copy to a history index, with a note of the user making the change
  // could automatically save every change to a history index. Can put all history records into the same index?
  // as long as the change is stored as a text string it wouldn't matter, as uuids won't clash anyway, and just record the source index
  // perhaps separate histories into timestamped indexes? which es7 uses "data streams" for...

  // TODO if also sheet param, sync from sheet at some interval
  // so then don't accept changes on the API? Or merge them somehow? That would require developing the google src further
  // to begin, prob just refuse edits if sheet - manage sheet here or at higher leve, or in a sheet function?

  // TODO add alias handling, particularly so that complete new imports can be built in a separate index then just repoint the alias
  // alias can be set on create, and may be best just to use an alias every time
  // https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-aliases.html

  // TODO can also use aliases and alternate routes to handle auth to certain subsets of date
  // aliased mappings can also have a filter applied, so only the filtered results get returned

  // TODO if index isn't available use a lunr file if possible as a fallback?

  // TOD if index SHOULD be available but fails, write to kv if that's available? But don't end up in a loop...
  // anything found by _schedule in kv that isn't set to _kv will get written to index once it becomes available
var base, ref,
  indexOf = [].indexOf;

if (S.index == null) {
  S.index = {};
}

if ((base = S.index).name == null) {
  base.name = (ref = S.name) != null ? ref : 'n2';
}

// need at least an S.index.url here as well
P.index = async function(route, data) {
  var c, chk, dni, ind, j, len, ref1, ref2, ref3, ref4, ret, rex, rpl;
  console.log(route);
  console.log(data);
  if (!route && (data == null) && ((this != null ? this.parts : void 0) != null) && this.parts.length && this.parts[0] === 'index') {
    if (this.parts.length > 1 && (this.parts[1].startsWith('.') || this.parts[1].startsWith('_') || ((ref1 = this.parts[1]) === 'svc' || ref1 === 'src') || (P[this.parts[1]] != null))) {
      return {
        // don't allow direct calls to index if the rest of the params indicate an existing route
        // if not an existing route, a user with necessary auth could create/interact with a specified index
        // for indexes not on a specified route, their config such as auth etc will need to be passed at creation and stored somewhere
        status: 403 // for now this isn't really stopping things, for example svc_crossref_works
      };
    }
  }
  if (typeof route === 'object') {
    data = route;
    route = void 0;
  }
  if (!route && (data == null)) { // only take data from incoming if directly on the index route
    if (typeof this.body === 'object') {
      data = this.copy(this.body);
    } else if (typeof this.body === 'string') {
      data = this.body;
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
  if (typeof data === 'object' && !Array.isArray(data)) {
    if (route == null) {
      route = (ref2 = data.route) != null ? ref2 : data.index;
    }
    delete data.route;
    delete data.index;
  }
  if (!route) {
    if (this.parts[0] === 'index') { // need custom auth for who can create/remove indexes and records directly?
      if (this.parts.length === 1) {
        return (await this.index._indices());
      } else if (this.parts.length === 2) { // called direct on an index
        route = this.parts[1];
      } else if (this.parts.length > 2) { // called on index/key route
        // most IDs will only be at position 3 but for example using a DOI as an ID would spread it across 3 and 4
        route = this.parts[1] + '/' + this.parts.slice(2).join('_'); // so combine them with an underscore - IDs can't have a slash in them
      }
    } else {
      // auth should not matter here because providing route or data means the function is being handled elsehwere, which should deal with auth
      route = this.fn.replace(/\./g, '_'); // if the wrapping function wants data other than that defined by the URL route it was called on, it MUST specify the route manually
      if (this.parts.join('.') !== this.fn) {
        // what if the @parts indicate this is a request for a specific record though, not just an index?
        route += '/' + this.parts.join('_').replace(route + '_', '');
      }
    }
  }
  if (typeof data === 'object' && !Array.isArray(data) && data._id) {
    dni = data._id.replace(/\//g, '_');
    if (route.indexOf('/') === -1 && route.indexOf(dni) === -1) {
      route += '/' + data._id;
    }
    delete data._id; // ID can't go into the data for ES7.x
  }
  route = route.toLowerCase();
  rpl = route.split('/').length;
  if ((this.parts[0] === 'index' && (this.request.method === 'DELETE' || this.params._delete)) || data === '') {
    // DELETE can happen on index or index/key, needs no additional route parts for index but index/key has to happen on _doc
    // TODO for @params._delete allow a passthrough of data in case it is a delete by query, once _submit is updated to handle that if still possible
    ret = (await this.index._submit(route.replace('/', '/_doc/'), ''));
    return void 0; //ret.acknowledged is true or ret.result is 'deleted'
  } else if (rpl === 1) {
    // CREATE can happen on index if index params are provided or empty object is provided
    // https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-create-index.html
    // simplest create would be {} or settings={number_of_shards:1} where 1 is default anyway
    if (typeof data === 'string' && data.indexOf('\n') === -1) {
      try {
        data = this.index.translate(data);
      } catch (error) {}
    }
    if (typeof data === 'string' || Array.isArray(data)) {
      return this.index._bulk(route, data); // bulk create (TODO what about if wanting other bulk actions?)
    } else if (typeof data === 'object') {
      if (this.index._q(data)) {
        return this.index._submit(route + '/_search', this.index.translate(data));
      } else {
        chk = this.copy(data);
        ref3 = ['settings', 'aliases', 'mappings'];
        for (j = 0, len = ref3.length; j < len; j++) {
          c = ref3[j];
          delete chk[c];
        }
        if (JSON.stringify(chk) === '{}') {
          if (!(await this.index._submit(route))) {
            ind = !this.index._q(data) ? {
              settings: data.settings,
              aliases: data.aliases,
              mappings: data.mappings
            } : {};
            await this.index._submit(route, ind); // create the index
          }
          return this.index._submit(route + '/_search'); // just do a search
        } else {
          return this.index._submit(route + '/_doc', data); // create a single record without ID (if it came with ID it would have been caught above and converted to route with multiple parts)
        }
      }
    } else {
      return this.index._submit(route + '/_search');
    }
  } else if (rpl === 2 && ((data == null) || typeof data === 'object' && !Array.isArray(data))) {
    // CREATE or overwrite on index/key if data is provided - otherwise just GET the _doc
    // Should @params be able to default to write data on index/key?
    // TODO check how ES7.x accepts update with script in them
    if ((data != null) && JSON.stringify(data) !== '{}') {
      route = data.script != null ? route + '/_update?retry_on_conflict=2' : route.replace('/', '/_create/'); // does PUT create work if it already exists? or PUT _doc? or POST _create?
      return this.index._submit(route, data); // or just get the record
    } else {
      ret = (await this.index._submit(route.replace('/', '/_doc/')));
      if (typeof ret === 'object' && (ret._source || ret.fields)) {
        rex = (ref4 = ret._source) != null ? ref4 : ret.fields;
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

// calling this should be given a correct URL route for ES7.x, domain part of the URL is optional though.
// call the above to have the route constructed. method is optional and will be inferred if possible (may be removed)
// what about namespacing to env? do here or above, or neither?
P.index._submit = async function(route, data, method, deletes = true) { // deletes is true in dev, but remove or add auth control for live
  var opts, ref1, ref2, ref3, ref4, ref5, res, url;
  console.log(route);
  console.log(data);
  route = route.toLowerCase(); // force lowercase on all IDs so that can deal with users giving incorrectly cased IDs for things like DOIs which are defined as case insensitive
  if (route.indexOf('/') === 0) { // gets added back in when combined with the url
    route = route.replace('/', '');
  }
  if (method == null) {
    method = route === '/_pit' || data === '' ? 'DELETE' : (data != null) && (route.indexOf('/') === -1 || route.indexOf('/_create') !== -1 || (route.indexOf('/_doc') !== -1 && !route.endsWith('/_doc'))) ? 'PUT' : (data != null) || ((ref1 = route.split('/').pop().split('?')[0]) === '_refresh' || ref1 === '_pit' || ref1 === '_aliases') ? 'POST' : 'GET';
  }
  // TODO if data is a query that also has a _delete key in it, remove that key and do a delete by query? and should that be bulked? is dbq still allowed in ES7.x?
  console.log(method);
  if (method === 'DELETE' && (deletes !== true || route.indexOf('/_all') !== -1)) { // nobody can delete all via the API
    return false;
  }
  if (!route.startsWith('http')) { // which it probably doesn't
    url = (this != null ? (ref2 = this.S) != null ? (ref3 = ref2.index) != null ? ref3.url : void 0 : void 0 : void 0) ? this.S.index.url : (ref4 = S.index) != null ? ref4.url : void 0;
    if (Array.isArray(url)) {
      url = url[Math.floor(Math.random() * url.length)];
    }
    if (typeof url !== 'string') {
      return void 0;
    }
    route = url + '/' + route;
  }
  //if dev and route.indexOf('_dev') is -1 and route.indexOf('/_') isnt 0
  //  rpd = route.split '/'
  //  rpd[1] += '_dev'
  //  rpd[1] = rpd[1].replace(',','_dev,')
  //  route = rpd.join '/'
  opts = route.indexOf('/_bulk') !== -1 || typeof (data != null ? data.headers : void 0) === 'object' ? data : {
    body: data // fetch requires data to be body
  };
  
  //opts.retry = 3
  opts.method = method;
  res = (this != null ? this.fetch : void 0) != null ? (await this.fetch(route, opts)) : (await P.fetch(route, opts)); // is it worth having P. as opposed to @ options?
  if ((res == null) || (typeof res === 'object' && typeof res.status === 'number' && res.status >= 400 && res.status <= 600)) {
    // fetch returns undefined for 404, otherwise any other error from 400 is returned like status: 400
    // write a log / send an alert?
    //em = level: 'debug', msg: 'ES error, but may be OK, 404 for empty lookup, for example', method: method, url: url, route: route, opts: opts, error: err.toString()
    //if this?.log? then @log(em) else P.log em
    // do anything for 409 (version mismatch?)
    return void 0;
  } else {
    try {
      if (this.S.dev && ((opts != null ? (ref5 = opts.body) != null ? ref5.query : void 0 : void 0) != null)) {
        res.q = opts.body;
      }
    } catch (error) {}
    return res;
  }
};

P.index._mapping = async function(route) {
  if (typeof route !== 'string') {
    return false;
  }
  route = route.replace(/^\//, ''); // remove any leading /
  if (route.indexOf('/') === -1) {
    route = route + '/';
  }
  if (route.indexOf('_mapping') === -1) {
    route = route.replace('/', '/_mapping');
  }
  return (await this.index._submit(route));
};

P.index.keys = function(route) {
  var _keys, keys;
  keys = [];
  try {
    _keys = function(mapping, depth = '') {
      var k, ref1, results;
      if (mapping == null) {
        mapping = typeof route === 'object' ? route : this.index._mapping(route);
      }
      if (mapping.properties != null) {
        if (depth.length) {
          depth += '.';
        }
        results = [];
        for (k in mapping.properties) {
          if (ref1 = depth + k, indexOf.call(keys, ref1) < 0) {
            keys.push(depth + k);
          }
          if (mapping.properties[k].properties != null) {
            results.push(_keys(mapping.properties[k], depth + k));
          } else {
            results.push(void 0);
          }
        }
        return results;
      }
    };
    _keys();
  } catch (error) {}
  return keys;
};

P.index.terms = function(route, key, qry, size = 1000, counts = false, order = "count") {
  var err, query, ret;
  // TODO check how to specify if terms facet (which needs to update to agg) needs to be on .keyword rather than just key (like how .exact used to be used)
  query = typeof qry === 'object' ? qry : {
    query: {
      "filtered": {
        "filter": {
          "exists": {
            "field": key
          }
        }
      }
    },
    size: 0,
    facets: {}
  };
  if (typeof qry === 'string') {
    query.filtered.query = {
      query_string: {
        query: qry
      }
    };
  }
  if (query.facets == null) {
    query.facets = {};
  }
  // order: (default) count is highest count first, reverse_count is lowest first. term is ordered alphabetical by term, reverse_term is reverse alpha
  query.facets[key] = {
    terms: {
      field: key,
      size: size,
      order: order
    }
  };
  try {
    ret = this.index._submit('/' + route + '/_search', query, 'POST');
    if ((ret != null ? ret.facets : void 0) == null) {
      return [];
    } else {
      if (counts) {
        return ret.facets[key].terms;
      } else {
        return _.pluck(ret.facets[key].terms, 'term');
      }
    }
  } catch (error) {
    err = error;
    return [];
  }
};

P.index.count = function(route, key, query) {
  var ref1, ref2, ref3, ref4, ref5, ref6;
  if (query == null) {
    query = {
      query: {
        "filtered": {
          "filter": {
            "bool": {
              "must": []
            }
          }
        }
      }
    };
  }
  if (key != null) {
    query.size = 0;
    query.aggs = {
      "keycard": {
        "cardinality": {
          "field": key,
          "precision_threshold": 40000 // this is high precision and will be very memory-expensive in high cardinality keys, with lots of different values going in to memory
        }
      }
    };
    return (ref1 = this.index._submit('/' + route + '/_search', query, 'POST')) != null ? (ref2 = ref1.aggregations) != null ? (ref3 = ref2.keycard) != null ? ref3.value : void 0 : void 0 : void 0;
  } else {
    return (ref4 = this.index._submit('/' + route + '/_search', query, 'POST')) != null ? (ref5 = ref4.hits) != null ? (ref6 = ref5.total) != null ? ref6.value : void 0 : void 0 : void 0;
  }
};

P.index.min = function(route, key, qry) {
  var query, ret;
  query = typeof key === 'object' ? key : qry != null ? qry : {
    query: {
      "filtered": {
        "filter": {
          "exists": {
            "field": key
          }
        }
      }
    }
  };
  query.size = 0;
  query.aggs = {
    "min": {
      "min": {
        "field": key
      }
    }
  };
  ret = this.index._submit('/' + route + '/_search', query, 'POST');
  return ret.aggregations.min.value;
};

P.index.max = function(route, key, qry) {
  var query, ret;
  query = typeof key === 'object' ? key : qry != null ? qry : {
    query: {
      "filtered": {
        "filter": {
          "exists": {
            "field": key
          }
        }
      }
    }
  };
  query.size = 0;
  query.aggs = {
    "max": {
      "max": {
        "field": key
      }
    }
  };
  ret = this.index._submit('/' + route + '/_search', query, 'POST');
  return ret.aggregations.max.value;
};

P.index.range = function(route, key, qry) {
  var query, ret;
  query = typeof key === 'object' ? key : qry != null ? qry : {
    query: {
      "filtered": {
        "filter": {
          "exists": {
            "field": key
          }
        }
      }
    }
  };
  query.size = 0;
  query.aggs = {
    "min": {
      "min": {
        "field": key
      }
    },
    "max": {
      "max": {
        "field": key
      }
    }
  };
  ret = this.index._submit('/' + route + '/_search', query, 'POST');
  return {
    min: ret.aggregations.min.value,
    max: ret.aggregations.max.value
  };
};

// previously used scan/scroll for each, but now use pit and search_after
// can still manually make scan/scroll calls if desired, see:
//  scan, scroll='10m'
//  if scan is true
//    route += (if route.indexOf('?') is -1 then '?' else '&')
//    if not data? or (typeof data is 'object' and not data.sort?) or (typeof data is 'string' and data.indexOf('sort=') is -1)
//      route += 'search_type=scan&'
//    route += 'scroll=' + scroll
//  else if scan?
//    route = '/_search/scroll?scroll_id=' + scan + (if action isnt 'DELETE' then '&scroll=' + scroll else '')
P.index._each = function(route, q, opts, fn) {
  var action, fr, h, j, ka, len, pit, processed, qy, ref1, ref2, ref3, ref4, res, total, updates;
  // use search_after for each
  // https://www.elastic.co/guide/en/elasticsearch/reference/7.10/paginate-search-results.html#search-after
  // each executes the function for each record. If the function makes changes to a record and saves those changes, 
  // this can cause many writes to the collection. So, instead, that sort of function could return something
  // and if the action has also been specified then all the returned values will be used to do a bulk write to the collection index.
  // suitable returns would be entire records for insert, record update objects for update, or record IDs for remove
  // this does not allow different actions for different records that are operated on - so has to be bulks of the same action
  if (fn === void 0 && opts === void 0 && typeof q === 'function') {
    fn = q;
    q = '*';
  }
  if (fn === void 0 && typeof opts === 'function') {
    fn = opts;
    opts = void 0;
  }
  if (opts == null) {
    opts = {};
  }
  if (opts.keep_alive != null) {
    ka = opts.keep_alive;
    delete opts.keep_alive;
  } else {
    ka = '5m';
  }
  if (opts.action) {
    action = opts.action;
    delete opts.action;
  } else {
    action = false;
  }
  qy = P.index.translate(q, opts);
  qy.from = 0; // from has to be 0 for search_after
  if (qy.size == null) {
    qy.size = 1000; // 10000 is max and would be fine for small records...
  }
  pit = this.index(route + '/_pit?keep_alive=' + ka).id; // here route should be index name
  qy.pit = {
    id: pit,
    keep_alive: ka // this gives a point in time ID that will be kept alive for given time, so changes don't ruin the result order
  };
  // note sort should contain a tie-breaker on a record unique value, so check even if there is a sort
  // also what if there is no createdAt field? what to sort on?
  if (qy.sort == null) {
    qy.sort = [
      {
        createdAt: 'asc'
      }
    ];
  }
  processed = 0;
  updates = [];
  total = false;
  while (((res != null ? (ref4 = res.hits) != null ? ref4.hits : void 0 : void 0) != null) && (total === false || processed < total)) {
    res = this.index(route, qy);
    if (total === false) {
      total = res.hits.total.value;
    }
    ref1 = res.hits.hits;
    for (j = 0, len = ref1.length; j < len; j++) {
      h = ref1[j];
      processed += 1;
      fn = fn.bind(this);
      fr = fn((ref2 = (ref3 = h._source) != null ? ref3 : h.fields) != null ? ref2 : {
        _id: h._id
      });
      if ((fr != null) && (typeof fr === 'object' || typeof fr === 'string')) {
        updates.push(fr);
      }
      qy.search_after = h.sort;
    }
    qy.pit.id = res.pit_id;
  }
  if (action && updates.length) { // TODO should prob do this during the while loop above, once updates reaches some number
    this.index._bulk(route, updates, action);
  }
  return this.index._submit('/_pit', {
    id: pit // delete the pit
  });
};

P.index._bulk = async function(route, data, action = 'index', bulk = 50000) {
  var counter, meta, pkg, r, ref1, row, rows;
  // https://www.elastic.co/guide/en/elasticsearch/reference/1.4/docs-bulk.html
  // https://www.elastic.co/guide/en/elasticsearch/reference/1.4/docs-update.html
  //url = url[Math.floor(Math.random()*url.length)] if Array.isArray url
  //route += '_dev' if dev and route.indexOf('_dev') is -1
  // TODO need a check somewhere that incoming bulk data is about the relevant index - not bulking data to a different index than the one authorised on the route
  if (typeof data === 'string' && data.indexOf('\n') !== -1) {
    await this.index._submit('/_bulk', {
      content: data,
      headers: {
        'Content-Type': 'text/plain'
      }
    });
    return true;
  } else {
    rows = typeof data === 'object' && !Array.isArray(data) && ((data != null ? (ref1 = data.hits) != null ? ref1.hits : void 0 : void 0) != null) ? data.hits.hits : data;
    if (!Array.isArray(rows)) {
      rows = [rows];
    }
    counter = 0;
    pkg = '';
    for (r in rows) {
      counter += 1;
      row = rows[r];
      if (typeof row === 'object' && (row._id == null)) { // TODO any other default fields that should be added? createdAt?
        //row._index += '_dev' if typeof row isnt 'string' and row._index? and row._index.indexOf('_dev') is -1 and dev
        row._id = this.uid();
      }
      meta = {};
      meta[action] = {
        "_index": (typeof row !== 'string' && (row._index != null) ? row._index : route)
      };
      meta[action]._id = action === 'delete' && typeof row === 'string' ? row : row._id; // what if action is delete but can't set an ID?
      pkg += JSON.stringify(meta) + '\n';
      if (action === 'create' || action === 'index') {
        pkg += JSON.stringify(row._source ? row._source : row) + '\n';
      } else if (action === 'update') {
        if (row._id != null) {
          delete row._id;
        }
        pkg += JSON.stringify({
          doc: row
        }) + '\n'; // is it worth expecting other kinds of update in bulk import?
      }
      // don't need a second row for deletes
      if (counter === bulk || parseInt(r) === (rows.length - 1) || pkg.length > 70000000) {
        await this.index._submit('/_bulk', {
          content: pkg,
          headers: {
            'Content-Type': 'text/plain'
          }
        });
        pkg = '';
        counter = 0;
      }
    }
    return rows.length;
  }
};

P.index._indices = async function(verbose = false) {
  var base1, i, j, len, res, s, sh, shards;
  res = verbose ? {} : [];
  s = (await this.index._submit('_stats'));
  shards = !verbose ? [] : (await this.index._submit('_cat/shards?format=json'));
  for (i in s.indices) {
    if (indexOf.call([], i) < 0 && !i.startsWith('.') && !i.startsWith('security-')) {
      if (verbose) {
        // is primaries or total better for numbers here?
        res[i] = {
          docs: s.indices[i].primaries.docs.count,
          size: Math.ceil(s.indices[i].primaries.store.size_in_bytes / 1024 / 1024)
        };
        for (j = 0, len = shards.length; j < len; j++) {
          sh = shards[j];
          if (sh.index === i && sh.prirep === 'p') {
            if ((base1 = res[i]).shards == null) {
              base1.shards = 0;
            }
            res[i].shards += 1;
          }
        }
      } else {
        res.push(i);
      }
    }
  }
  return res;
};

P.index.status = async function() {
  var j, k, len, ref1, ref2, res;
  res = {
    status: 'green'
  };
  res.indices = (await this.index._indices(true));
  try {
    if ((ref1 = res.cluster.status) !== 'green' && ref1 !== 'yellow') { // accept yellow for single node cluster (or configure ES itself to accept that as green)
      res.status = 'red';
    }
    ref2 = ['cluster_name', 'number_of_nodes', 'number_of_data_nodes', 'unassigned_shards'];
    for (j = 0, len = ref2.length; j < len; j++) {
      k = ref2[j];
      delete res.cluster[k];
    }
  } catch (error) {}
  return res;
};

// helper to identify strings or objects that likely should be interpreted as queries
P.index._q = function(q, rt) { // could this be a query as opposed to an _id or index/_id string
  var c, j, k, l, len, len1, ref1, ref2;
  if (typeof q === 'object' && !Array.isArray(q)) {
    ref1 = ['settings', 'aliases', 'mappings', 'index'];
    for (j = 0, len = ref1.length; j < len; j++) {
      k = ref1[j];
      if (q[k]) {
        return false;
      }
    }
    if ((q.q != null) || (q.query != null)) {
      return true; // q or query COULD be valid values of an object, in which case don't pass such objects to ambiguous locations such as the first param of an index function
    }
  } else if (typeof q === 'string' && q.indexOf('\n') === -1) { // newlines indicates a bulk load string
    if (typeof rt === 'string' && q.toLowerCase().startsWith(rt.toLowerCase())) {
      return false; // handy check for a string that is probably an index route, just to save manually checking elsewhere
    } else if (q.startsWith('?') || q.startsWith('q=')) { // like an incoming URL query params string
      return true;
    } else if (q.length < 8 || (q.indexOf('/') !== -1 ? q.split('/').pop() : q).length > 34) { // no _id would be shorter than 8 or longer than 34
      return true;
    } else {
      ref2 = [' ', ':', '*', '~', '(', ')', '?'];
      // none of these are present in an ID
      for (l = 0, len1 = ref2.length; l < len1; l++) {
        c = ref2[l];
        if (q.indexOf(c) !== -1) {
          return true;
        }
      }
    }
  }
  return false;
};

/* query formats that can be accepted:
  'A simple string to match on'
  'statement:"A more complex" AND difficult string' - which will be used as is to ES as a query string
  '?q=query params directly as string'
  {"q":"object of query params"} - must contain at least q or source as keys to be identified as such
  {"must": []} - a list of must queries, in full ES syntax, which will be dropped into the query filter (works for "should" as well)
  {"object":"of key/value pairs, all of which must match"} - so this is an AND terms match/ If keys do not point to strings, they will be assumed to be named ES queries that can drop into the bool
  ["list","of strings to OR match on"] - this is an OR query strings match UNLESS strings contain : then mapped to terms matches
  [{"list":"of objects to OR match"}] - so a set of OR terms matches. If objects are not key: string they are assumed to be full ES queries that can drop into the bool

  Keys can use dot notation

  Options that can be included:
  If options is true, the query will be adjusted to sort by createdAt descending, so returning the newest first (it sets newest:true, see below)
  If options is string 'random' it will convert the query to be a random order
  If options is a number it will be assumed to be the size parameter
  Otherwise options should be an object (and the above can be provided as keys, "newest", "random")
  If newest is true the query will have a sort desc on createdAt. If false, sort will be asc
  If "random" key is provided, "seed" can be provided too if desired, for seeded random queries
  If "restrict" is provided, should point to list of ES queries to add to the and part of the query filter
  Any other keys in the options object should be directly attributable to an ES query object
  TODO can add more conveniences for passing options in here, such as simplified terms, etc.

  Default query looks like:
  {query: {filtered: {query: {match_all: {}}, filter: {bool: {must: []}}}}, size: 10}
*/
P.index.translate = function(q, opts = {}) {
  var _structure, a, af, b, base1, base2, base3, bm, dk, exc, excludes, f, fm, fq, i, i1, inc, includes, j, j1, k, l, len, len1, len10, len2, len3, len4, len5, len6, len7, len8, len9, m, n, nos, nr, o, ok, os, p, pfx, ps, qobj, qpts, qry, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref3, ref4, ref5, ref6, ref7, ref8, ref9, rs, sr, t, tgt, tm, tobj, u, v, w, x, y, z;
  if (q == null) {
    q = this != null ? this.params : void 0;
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
  qry = (ref1 = opts != null ? opts.query : void 0) != null ? ref1 : {};
  if (qry.query == null) {
    qry.query = {};
  }
  _structure = function(sq) {
    var base1, base2, base3, base4, ms;
    if ((sq.query == null) || (sq.query.filtered == null)) {
      sq.query = {
        filtered: {
          query: sq.query,
          filter: {}
        }
      };
    }
    if ((base1 = sq.query.filtered).filter == null) {
      base1.filter = {};
    }
    if ((base2 = sq.query.filtered.filter).bool == null) {
      base2.bool = {};
    }
    if ((base3 = sq.query.filtered.filter.bool).must == null) {
      base3.must = [];
    }
    if (sq.query.filtered.query.bool == null) {
      ms = [];
      if (JSON.stringify(sq.query.filtered.query) !== '{}') {
        ms.push(sq.query.filtered.query);
      }
      sq.query.filtered.query = {
        bool: {
          must: ms
        }
      };
    }
    if ((base4 = sq.query.filtered.query.bool).must == null) {
      base4.must = [];
    }
    return sq;
  };
  qry = _structure(qry);
  if (typeof q === 'object') {
    ref2 = ['apikey', '_', 'callback', 'refresh', 'key', 'counts', 'index'];
    for (j = 0, len = ref2.length; j < len; j++) {
      dk = ref2[j];
      delete q[dk];
    }
    ref3 = ['random', 'seed'];
    // is this necessary or is the general push of things other than q to opts good enough?
    for (l = 0, len1 = ref3.length; l < len1; l++) {
      ok = ref3[l];
      opts[ok] = q[ok];
      delete q[ok];
    }
    // some URL params that may be commonly used in this API along with valid ES URL query params will be removed here by default too
    // this makes it easy to handle them in routes whilst also just passing the whole queryParams object into this translation method and still get back a valid ES query
    if (JSON.stringify(q).indexOf('[') === 0) {
      qry.query.filtered.filter.bool.should = [];
      for (n = 0, len2 = q.length; n < len2; n++) {
        m = q[n];
        if (typeof m === 'object' && (m != null)) {
          for (k in m) {
            if (typeof m[k] === 'string') {
              tobj = {
                term: {}
              };
              tobj.term[k];
              qry.query.filtered.filter.bool.should.push(tobj);
            } else if ((ref4 = typeof m[k]) === 'number' || ref4 === 'boolean') {
              qry.query.filtered.query.bool.should.push({
                query_string: {
                  query: k + ':' + m[k]
                }
              });
            } else if (m[k] != null) {
              qry.query.filtered.filter.bool.should.push(m[k]);
            }
          }
        } else if (typeof m === 'string') {
          if ((base1 = qry.query.filtered.query.bool).should == null) {
            base1.should = [];
          }
          qry.query.filtered.query.bool.should.push({
            query_string: {
              query: m
            }
          });
        }
      }
    } else if (q.query != null) {
      qry = q; // assume already a query
    } else if (q.source != null) {
      if (typeof q.source === 'string') {
        qry = JSON.parse(q.source);
      }
      if (typeof q.source === 'object') {
        qry = q.source;
      }
      if (opts == null) {
        opts = {};
      }
      for (o in q) {
        if (o !== 'source') {
          if (opts[o] == null) {
            opts[o] = q[o];
          }
        }
      }
    } else if (q.q != null) {
      if ((q.prefix != null) && q.q.indexOf(':') !== -1) {
        delete q.prefix;
        pfx = {};
        qpts = q.q.split(':');
        pfx[qpts[0]] = qpts[1];
        qry.query.filtered.query.bool.must.push({
          prefix: pfx
        });
      } else {
        qry.query.filtered.query.bool.must.push({
          query_string: {
            query: q.q
          }
        });
      }
      if (opts == null) {
        opts = {};
      }
      for (o in q) {
        if (o !== 'q') {
          if (opts[o] == null) {
            opts[o] = q[o];
          }
        }
      }
    } else {
      if (q.must != null) {
        qry.query.filtered.filter.bool.must = q.must;
      }
      if (q.should != null) {
        qry.query.filtered.filter.bool.should = q.should;
      }
      if (q.must_not != null) {
        qry.query.filtered.filter.bool.must_not = q.must_not;
      }
      // an object where every key is assumed to be an AND term search if string, or a named search object to go in to ES
      for (y in q) {
        if ((y === 'fields') || (y === 'sort' && typeof q[y] === 'string' && q[y].indexOf(':') !== -1) || ((y === 'from' || y === 'size') && (typeof q[y] === 'number' || !isNaN(parseInt(q[y]))))) {
          if (opts == null) {
            opts = {};
          }
          opts[y] = q[y];
        } else if (y !== 'must' && y !== 'must_not' && y !== 'should') {
          if (typeof q[y] === 'string') {
            tobj = {
              term: {}
            };
            tobj.term[y] = q[y];
            qry.query.filtered.filter.bool.must.push(tobj);
          } else if ((ref5 = typeof q[y]) === 'number' || ref5 === 'boolean') {
            qry.query.filtered.query.bool.must.push({
              query_string: {
                query: y + ':' + q[y]
              }
            });
          } else if (typeof q[y] === 'object') {
            qobj = {};
            qobj[y] = q[y];
            qry.query.filtered.filter.bool.must.push(qobj);
          } else if (q[y] != null) {
            qry.query.filtered.filter.bool.must.push(q[y]);
          }
        }
      }
    }
  } else if (typeof q === 'string') {
    if (q.indexOf('?') === 0) {
      qry = q; // assume URL query params and just use them as such?
    } else if (q != null) {
      if (q === '') {
        q = '*';
      }
      qry.query.filtered.query.bool.must.push({
        query_string: {
          query: q
        }
      });
    }
  }
  qry = _structure(qry); // do this again to make sure valid structure is present after above changes, and before going through opts which require expected structure
  if (opts != null) {
    if (opts.newest === true) {
      delete opts.newest;
      opts.sort = {
        createdAt: {
          order: 'desc'
        }
      };
    } else if (opts.newest === false) {
      delete opts.newest;
      opts.sort = {
        createdAt: {
          order: 'asc'
        }
      };
    }
    delete opts._; // delete anything that may have come from query params but are not handled by ES
    delete opts.apikey;
    if (opts.fields && typeof opts.fields === 'string' && opts.fields.indexOf(',') !== -1) {
      opts.fields = opts.fields.split(',');
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
      if (qry.query.filtered) {
        fq.function_score.query = qry.query.filtered.query;
        qry.query.filtered.query = fq;
      } else {
        fq.function_score.query = qry.query;
        qry.query = fq;
      }
      delete opts.random;
      delete opts.seed;
    }
    if ((opts._include != null) || (opts.include != null) || (opts._includes != null) || (opts.includes != null) || (opts._exclude != null) || (opts.exclude != null) || (opts._excludes != null) || (opts.excludes != null)) {
      if (qry._source == null) {
        qry._source = {};
      }
      inc = opts._include != null ? '_include' : opts.include != null ? 'include' : opts._includes != null ? '_includes' : 'includes';
      includes = opts[inc];
      if (includes != null) {
        if (typeof includes === 'string') {
          includes = includes.split(',');
        }
        qry._source.includes = includes;
        delete opts[inc];
      }
      exc = opts._exclude != null ? '_exclude' : opts.exclude != null ? 'exclude' : opts._excludes != null ? '_excludes' : 'excludes';
      excludes = opts[exc];
      if (excludes != null) {
        if (typeof excludes === 'string') {
          excludes = excludes.split(',');
        }
        ref6 = includes != null ? includes : [];
        for (p = 0, len3 = ref6.length; p < len3; p++) {
          i = ref6[p];
          if (indexOf.call(excludes, i) >= 0) {
            delete excludes[i];
          }
        }
        qry._source.excludes = excludes;
        delete opts[exc];
      }
    }
    if (opts.and != null) {
      ref7 = opts.and;
      for (t = 0, len4 = ref7.length; t < len4; t++) {
        a = ref7[t];
        qry.query.filtered.filter.bool.must.push(a);
      }
      delete opts.and;
    }
    if (opts.sort != null) {
      if (typeof opts.sort === 'string' && opts.sort.indexOf(',') !== -1) {
        if (opts.sort.indexOf(':') !== -1) {
          os = [];
          ref8 = opts.sort.split(',');
          for (u = 0, len5 = ref8.length; u < len5; u++) {
            ps = ref8[u];
            nos = {};
            nos[ps.split(':')[0]] = {
              order: ps.split(':')[1]
            };
            os.push(nos);
          }
          opts.sort = os;
        } else {
          opts.sort = opts.sort.split(',');
        }
      }
      if (typeof opts.sort === 'string' && opts.sort.indexOf(':') !== -1) {
        os = {};
        os[opts.sort.split(':')[0]] = {
          order: opts.sort.split(':')[1]
        };
        opts.sort = os;
      }
    }
    if (opts.restrict != null) {
      ref9 = opts.restrict;
      for (w = 0, len6 = ref9.length; w < len6; w++) {
        rs = ref9[w];
        qry.query.filtered.filter.bool.must.push(rs);
      }
      delete opts.restrict;
    }
    if ((opts.not != null) || (opts.must_not != null)) {
      tgt = opts.not != null ? 'not' : 'must_not';
      if (Array.isArray(opts[tgt])) {
        qry.query.filtered.filter.bool.must_not = opts[tgt];
      } else {
        if ((base2 = qry.query.filtered.filter.bool).must_not == null) {
          base2.must_not = [];
        }
        ref10 = opts[tgt];
        for (x = 0, len7 = ref10.length; x < len7; x++) {
          nr = ref10[x];
          qry.query.filtered.filter.bool.must_not.push(nr);
        }
      }
      delete opts[tgt];
    }
    if (opts.should != null) {
      if (Array.isArray(opts.should)) {
        qry.query.filtered.filter.bool.should = opts.should;
      } else {
        if ((base3 = qry.query.filtered.filter.bool).should == null) {
          base3.should = [];
        }
        ref11 = opts.should;
        for (z = 0, len8 = ref11.length; z < len8; z++) {
          sr = ref11[z];
          qry.query.filtered.filter.bool.should.push(sr);
        }
      }
      delete opts.should;
    }
    if (opts.all != null) {
      // TODO newer ES doesn't allow more than 10k by default, need to do scan/scroll or whatever the new equivalent is
      qry.size = 1000000; // just a simple way to try to get "all" records - although passing size would be a better solution, and works anyway
      delete opts.all;
    }
    if (opts.terms != null) {
      try {
        opts.terms = opts.terms.split(',');
      } catch (error) {}
      if (qry.facets == null) {
        qry.facets = {};
      }
      ref12 = opts.terms;
      for (i1 = 0, len9 = ref12.length; i1 < len9; i1++) {
        tm = ref12[i1];
        qry.facets[tm] = {
          terms: {
            field: tm,
            size: 1000
          }
        };
      }
      delete opts.terms;
    }
    ref13 = ['facets', 'aggs', 'aggregations'];
    for (j1 = 0, len10 = ref13.length; j1 < len10; j1++) {
      af = ref13[j1];
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
      qry[k] = v;
    }
  }
  if (typeof qry === 'object' && (((ref14 = qry.query) != null ? (ref15 = ref14.filtered) != null ? ref15.query : void 0 : void 0) != null) && JSON.stringify(qry.query.filtered.query) === '{}') {
    // no filter query or no main query can cause issues on some queries especially if certain aggs/terms are present, so insert some default searches if necessary
    qry.query.filtered.query = {
      match_all: {}
    };
  }
  //qry.query.filtered.query.bool.must = [{"match_all":{}}] if typeof qry is 'object' and qry.query?.filtered?.query?.bool?.must? and qry.query.filtered.query.bool.must.length is 0 and not qry.query.filtered.query.bool.must_not? and not qry.query.filtered.query.bool.should and (qry.aggregations? or qry.aggs? or qry.facets?)
  // clean slashes out of query strings
  if (((ref16 = qry.query) != null ? (ref17 = ref16.filtered) != null ? (ref18 = ref17.query) != null ? ref18.bool : void 0 : void 0 : void 0) != null) {
    for (bm in qry.query.filtered.query.bool) {
      for (b in qry.query.filtered.query.bool[bm]) {
        if (typeof ((ref19 = qry.query.filtered.query.bool[bm][b].query_string) != null ? ref19.query : void 0) === 'string' && qry.query.filtered.query.bool[bm][b].query_string.query.indexOf('/') !== -1) {
          qry.query.filtered.query.bool[bm][b].query_string.query = qry.query.filtered.query.bool[bm][b].query_string.query.replace(/\//g, '\\/');
        }
      }
    }
  }
  if (((ref20 = qry.query) != null ? (ref21 = ref20.filtered) != null ? (ref22 = ref21.filter) != null ? ref22.bool : void 0 : void 0 : void 0) != null) {
    for (fm in qry.query.filtered.filter.bool) {
      for (f in qry.query.filtered.filter.bool[fm]) {
        if ((((ref23 = qry.query.filtered.filter.bool[fm][f].query_string) != null ? ref23.query : void 0) != null) && qry.query.filtered.filter.bool[fm][f].query_string.query.indexOf('/') !== -1) {
          qry.query.filtered.filter.bool[fm][f].query_string.query = qry.query.filtered.filter.bool[fm][f].query_string.query.replace(/\//g, '\\/');
        }
      }
    }
  }
  if ((qry._source != null) && (qry.fields != null)) {
    delete qry._source;
  }
  return qry;
};

// https://developers.cloudflare.com/workers/runtime-apis/kv
// Keys are always returned in lexicographically sorted order according to their UTF-8 bytes.
// NOTE these need to be awaited when necessary, as the val will be a Promise

// should it be possible to call kv context from background at all?
// if ONLY on background with no worker, something needs to be able to write to kv, or a stand-in of kv

// if no kv, use an ES index if available as a simple kv store
// later can also write in a redis fallback here#
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
      if (this.request.method === 'DELETE' || this.params._delete) { // TODO this is for easy dev, take out or auth restrict later
        val = '';
      } else if (this.body != null) {
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
    val = '';
  }
  if (typeof key === 'object' && (val == null)) {
    val = key;
    key = (ref6 = val._id) != null ? ref6 : (await this.uid());
  }
  if ((key != null) && this.S.kv && (global[this.S.kv] != null)) {
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
  } else {
    return void 0;
  }
};

// NOTE that count on kv is expensive because it requires listing everything
P.kv.count = async function(prefix) {
  var complete, counter, cursor, i, k, len, ls, ref, ref1;
  counter = 0;
  if (this.S.kv && (global[this.S.kv] != null)) {
    if (prefix == null) {
      prefix = (ref = this.params.kv) != null ? ref : this.params.prefix;
    }
    complete = false;
    while (!complete) {
      ls = (await global[this.S.kv].list({
        prefix: prefix,
        cursor: cursor
      }));
      cursor = ls.cursor;
      ref1 = ls.keys;
      for (i = 0, len = ref1.length; i < len; i++) {
        k = ref1[i];
        counter += 1;
      }
      complete = ls.list_complete;
    }
  }
  return counter;
};

P.kv._each = async function(prefix, fn, size) {
  var complete, counter, cursor, i, k, len, ls, ref, res, rs;
  res = [];
  if (this.S.kv && (global[this.S.kv] != null)) {
    complete = false;
    counter = 0;
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
        if (fn === '') {
          this.waitUntil(this.kv(k.name, ''));
        } else if (typeof fn === 'function') {
          res.push((await fn.call(this, k.name)));
        } else if (fn != null) {
          this.waitUntil(this.kv(k.name, fn));
        } else {
          rs = (await this.kv(k.name));
          if (rs != null) {
            if (rs.id == null) {
              rs.id = k.name;
            }
          }
          res.push(rs);
        }
      }
      complete = size && counter === size ? true : ls.list_complete;
    }
  }
  return res;
};

  // https://github.com/CrossRef/rest-api-doc/blob/master/rest_api.md
  // http://api.crossref.org/works/10.1016/j.paid.2009.02.013
var _xref_hdr, ref,
  indexOf = [].indexOf;

_xref_hdr = {
  'User-Agent': S.name + '; mailto:' + ((ref = S.mail) != null ? ref.to : void 0)
};

P.src.crossref = {};

P.src.crossref.journals = async function(issn) {
  var ref1, ref2, ref3, res, url;
  // by being an index, should default to a search of the index, then run this query if not present, which should get saved to the index
  if (issn == null) {
    issn = (ref1 = this != null ? (ref2 = this.params) != null ? ref2.journals : void 0 : void 0) != null ? ref1 : this != null ? (ref3 = this.params) != null ? ref3.issn : void 0 : void 0;
  }
  //url = 'https://api.crossref.org/journals?query=' + issn
  url = 'https://dev.lvatn.com/use/crossref/journals/' + issn;
  res = (await this.fetch(url)); //, {headers: _xref_hdr} # TODO check how headers get sent by fetch
  //return if res?.message?['total-results']? and res.message['total-results'].length then res.message['total-results'][0] else undefined
  if ((res != null ? res.ISSN : void 0) != null) {
    return res;
  } else {
    return void 0;
  }
};

P.src.crossref.journals._index = true;

P.src.crossref.journals._key = 'ISSN';

P.src.crossref.works = async function(doi) {
  var rec, ref1, ref2, ref3, ref4, ref5, res, url;
  if ((this != null ? (ref1 = this.params) != null ? ref1.title : void 0 : void 0) || (typeof doi === 'object' && (doi.title != null)) || (typeof doi === 'string' && doi.indexOf('10.') !== 0)) {
    res = this.src.crossref.works._title((this != null ? (ref2 = this.params) != null ? ref2.title : void 0 : void 0) ? this.params.title : typeof doi === 'object' ? doi.title : doi);
  } else {
    // a search of an index of works - and remainder of route is a DOI to return one record
    if (doi == null) {
      doi = (ref3 = this != null ? (ref4 = this.params) != null ? ref4.works : void 0 : void 0) != null ? ref3 : this != null ? (ref5 = this.params) != null ? ref5.doi : void 0 : void 0;
    }
    if (typeof doi === 'string') {
      if (doi.indexOf('http') === 0) {
        doi = doi.split('://')[1];
      }
      if (doi.indexOf('10.') !== 0 && doi.indexOf('/10.') !== -1) {
        doi = '10.' + doi.split('/10.')[1];
      }
      
      // for now just get from old system instead of crossref
      //url = 'https://api.crossref.org/works/' + doi
      url = 'https://dev.lvatn.com/use/crossref/works/' + doi;
      res = (await this.fetch(url)); //, {headers: _xref_hdr}
    }
  }
  if ((res != null ? res.DOI : void 0) != null) {
    rec = res; //res.data.message
    delete rec.relation;
    delete rec.reference; // is there anything worth doing with these? In some cases they are extremely long, enough to cause problems in the index
    delete rec.abstract;
    //if typeof rec.abstract is 'string' and this?.convert?.html2txt?
    //  rec.abstract = @convert.html2txt rec.abstract
    return rec;
  } else {
    return void 0; //res?.message?.DOI?
  }
};

P.src.crossref.works._kv = false;

P.src.crossref.works._index = {
  settings: {
    number_of_shards: 9
  }
};

P.src.crossref.works._key = 'DOI';

P.src.crossref.works._title = async function(title) {
  var f, i, j, k, len, len1, ltitle, matches, possible, qr, r, rec, ref1, ref2, ref3, ref4, ref5, ref6, res, rt, st, t, url;
  if (title == null) {
    title = this.params.title;
  }
  if (typeof title !== 'string') {
    return void 0;
  }
  qr = 'title.exact:"' + title + '"';
  if (title.indexOf(' ') !== -1) {
    qr += ' OR (';
    f = true;
    ref1 = title.split(' ');
    for (i = 0, len = ref1.length; i < len; i++) {
      t = ref1[i];
      if (t.length > 2) {
        if (f === true) {
          f = false;
        } else {
          qr += ' AND ';
        }
      }
      qr += '(title:"' + t + '" OR subtitle:"' + t + '")';
    }
    qr += ')';
  }
  url = 'https://dev.lvatn.com/use/crossref/works?q=' + qr;
  res = (await this.fetch(url));
  //res = @src.crossref.works qr
  possible = false;
  ltitle = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
  ref4 = (ref2 = res != null ? (ref3 = res.hits) != null ? ref3.hits : void 0 : void 0) != null ? ref2 : [];
  for (j = 0, len1 = ref4.length; j < len1; j++) {
    r = ref4[j];
    rec = r._source;
    rt = (typeof rec.title === 'string' ? rec.title : rec.title[0]).toLowerCase();
    if (rec.subtitle != null) {
      st = (typeof rec.subtitle === 'string' ? rec.subtitle : rec.subtitle[0]).toLowerCase();
      if (typeof st === 'string' && st.length && indexOf.call(rt, st) < 0) {
        rt += ' ' + st;
      }
    }
    rt = rt.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
    if ((ltitle.indexOf(rt) !== -1 || rt.indexOf(ltitle) !== -1) && ltitle.length / rt.length > 0.7 && ltitle.length / rt.length < 1.3) {
      matches = true;
      for (k in metadata) {
        if ((k !== 'citation' && k !== 'title') && ((ref5 = typeof metadata[k]) === 'string' || ref5 === 'number')) {
          matches = (fr[k] == null) || ((ref6 = typeof fr[k]) !== 'string' && ref6 !== 'number') || fr[k].toLowerCase() === metadata[k].toLowerCase();
        }
      }
      if (matches) {
        if (rec.type === 'journal-article') {
          if (format) {
            return API.use.crossref.works.format(rec);
          } else {
            return rec;
          }
        } else if (possible === false || possible.type !== 'journal-article' && rec.type === 'journal-article') {
          possible = rec;
        }
      }
    }
  }
  if (possible === false) {
    return void 0;
  } else {
    return possible;
  }
};

// and need the code that builds the index and keeps it up to date
// and someting to trigger a load each day for example
// probably requires a cron schedule to read some kind of setting or KV of last-updated indexes, and their update schedule
// doing the regular index update will probably be a long-running job, so needs to be triggered but run on the backend machine

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
P.src.epmc = async function(qrystr, from, size) {
  var ref, ref1, res, ret, url;
  if (qrystr.indexOf('10.') === 0 && qrystr.indexOf(' ') === -1 && qrystr.split('/').length === 2) {
    qrystr = 'DOI:' + qrystr;
  }
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=' + qrystr + '%20sort_date:y&resulttype=core&format=json';
  if (size != null) {
    url += '&pageSize=' + size; //can handle 1000, have not tried more, docs do not say
  }
  if (from != null) {
    url += '&cursorMark=' + from; // used to be a from pager, but now uses a cursor
  }
  ret = {};
  res = (await this.fetch(url));
  ret.total = res.hitCount;
  ret.data = (ref = (ref1 = res.resultList) != null ? ref1.result : void 0) != null ? ref : [];
  ret.cursor = res.nextCursorMark;
  return ret;
};

P.src.epmc.pmid = function(ident) {
  var res;
  res = this.src.epmc('EXT_ID:' + ident + ' AND SRC:MED');
  if (res.total) {
    return res.data[0];
  } else {
    return void 0;
  }
};

P.src.epmc.pmc = function(ident) {
  var res;
  res = this.src.epmc('PMCID:PMC' + ident.toLowerCase().replace('pmc', ''));
  if (res.total) {
    return res.data[0];
  } else {
    return void 0;
  }
};

P.src.epmc.title = function(title) {
  var res;
  try {
    title = title.toLowerCase().replace(/(<([^>]+)>)/g, '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
  } catch (error) {}
  res = this.src.epmc('title:"' + title + '"');
  if (res.total) {
    return res.data[0];
  } else {
    return void 0;
  }
};

P.src.epmc.licence = function(pmcid, rec, fulltext) {
  maybe_licence;
  var licanywhere, licinapi, licinperms, licsplash, maybe_licence, pg, res, url;
  if (pmcid && !rec) {
    res = this.src.epmc('PMC' + pmcid.toLowerCase().replace('pmc', ''));
  }
  if ((res != null ? res.total : void 0) > 0 || rec || fulltext) {
    if (rec == null) {
      rec = res.data[0];
    }
    if (!pmcid && rec) {
      pmcid = rec.pmcid;
    }
    if (rec.license) {
      licinapi = {
        licence: rec.license,
        source: 'epmc_api'
      };
      if (licinapi.licence.indexOf('cc') === 0) {
        licinapi.licence = licinapi.licence.replace(/ /g, '-');
      }
      return licinapi;
    }
    if (!fulltext && pmcid) {
      fulltext = this.src.epmc.xml(pmcid);
    }
    if (fulltext !== 404 && typeof fulltext === 'string' && fulltext.indexOf('<') === 0 && (this.svc.lantern != null)) {
      licinperms = this.svc.lantern.licence(void 0, void 0, fulltext, '<permissions>', '</permissions>');
      if (licinperms.licence != null) {
        licinperms.source = 'epmc_xml_permissions';
        return licinperms;
      }
      licanywhere = this.svc.lantern.licence(void 0, void 0, fulltext);
      if (licanywhere.licence != null) {
        licanywhere.source = 'epmc_xml_outside_permissions';
        return licanywhere;
      }
      if (fulltext.indexOf('<permissions>') !== -1) {
        maybe_licence = {
          licence: 'non-standard-licence',
          source: 'epmc_xml_permissions'
        };
      }
    }
    if (false) { //pmcid and not noui and @svc?.lantern?.licence?
      // TODO need a way to rate limit and run puppeteer
      url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc', '');
      pg = P.job.limit(3000, 'P.http.puppeteer', [url], "EPMCUI");
      if (typeof pg === 'string') {
        try {
          licsplash = P.service.lantern.licence(url, false, pg);
        } catch (error) {}
        if ((licsplash != null ? licsplash.licence : void 0) != null) {
          licsplash.source = 'epmc_html';
          return licsplash;
        }
      }
    }
    return maybe_licence != null ? maybe_licence : false;
  } else {
    return false;
  }
};

P.src.epmc.xml = async function(pmcid) {
  var r, url;
  if (pmcid) {
    pmcid = pmcid.toLowerCase().replace('pmc', '');
  }
  url = 'https://www.ebi.ac.uk/europepmc/webservices/rest/PMC' + pmcid + '/fullTextXML';
  r = (await this.fetch(url));
  return r.content;
};

P.src.epmc.aam = function(pmcid, rec, fulltext, noui) {
  var pg, resp, s1, s2, s3, s4, url;
  if (typeof fulltext === 'string' && fulltext.indexOf('pub-id-type=\'manuscript\'') !== -1 && fulltext.indexOf('pub-id-type="manuscript"') !== -1) {
    return {
      aam: true,
      info: 'fulltext'
    };
  } else {
    // if EPMC API authMan / epmcAuthMan / nihAuthMan become reliable we can use those instead
    //rec = @src.epmc.search('PMC' + pmcid.toLowerCase().replace('pmc',''))?.data?[0] if pmcid and not rec
    if (pmcid == null) {
      pmcid = rec != null ? rec.pmcid : void 0;
    }
    if (pmcid) {
      fulltext = this.src.epmc.xml(pmcid);
      if (typeof fulltext === 'string' && fulltext.indexOf('pub-id-type=\'manuscript\'') !== -1 && fulltext.indexOf('pub-id-type="manuscript"') !== -1) {
        resp = {
          aam: true,
          info: 'fulltext'
        };
        return resp;
      } else if (false) { //not noui
        url = 'https://europepmc.org/articles/PMC' + pmcid.toLowerCase().replace('pmc', '');
        pg = P.job.limit(3000, 'P.http.puppeteer', [url], "EPMCUI");
        if (pg === 404) {
          resp = {
            aam: false,
            info: 'not in EPMC (404)'
          };
          return resp;
        } else if (pg === 403) {
          return {
            info: 'EPMC blocking access, AAM status unknown'
          };
        } else if (typeof pg === 'string') {
          s1 = 'Author Manuscript; Accepted for publication in peer reviewed journal';
          s2 = 'Author manuscript; available in PMC';
          s3 = 'logo-nihpa.gif';
          s4 = 'logo-wtpa2.gif';
          if (pg.indexOf(s1) !== -1 || pg.indexOf(s2) !== -1 || pg.indexOf(s3) !== -1 || pg.indexOf(s4) !== -1) {
            resp = {
              aam: true,
              info: 'splashpage'
            };
            return resp;
          } else {
            resp = {
              aam: false,
              info: 'EPMC splashpage checked, no indicator found'
            };
            return resp;
          }
        } else if (pg != null) {
          return {
            info: 'EPMC was accessed but aam could not be decided from what was returned'
          };
        } else {
          return {
            info: 'EPMC was accessed nothing was returned, so aam check could not be performed'
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
    id = (ref3 = S.src.google) != null ? (ref4 = ref3.secrets) != null ? (ref5 = ref4.search) != null ? ref5.id : void 0 : void 0 : void 0;
  }
  if (key == null) {
    key = (ref6 = S.src.google) != null ? (ref7 = ref6.secrets) != null ? (ref8 = ref7.search) != null ? ref8.key : void 0 : void 0 : void 0;
  }
  if (q && id && key) {
    url = 'https://www.googleapis.com/customsearch/v1?key=' + key + '&cx=' + id + '&q=' + q;
    return (await this.fetch(url));
  } else {
    return {};
  }
};

P.src.google.sheets = async function(opts) {
  var g, k, l, ref, ref1, url, val, values;
  // expects a google sheet ID or a URL to a google sheets feed in json format
  // NOTE the sheet must be published for this to work, should have the data in sheet 1, and should have columns of data with key names in row 1
  if (opts == null) {
    opts = (ref = this != null ? this.params : void 0) != null ? ref : {};
  }
  if (typeof opts === 'string') {
    opts = {
      sheetid: opts
    };
  }
  if (((opts.sheets != null) || (opts.sheet != null)) && (opts.sheetid == null)) {
    opts.sheetid = (ref1 = opts.sheet) != null ? ref1 : opts.sheets;
    delete opts.sheet;
    delete opts.sheets;
  }
  values = [];
  if (!opts.sheetid) {
    return values;
  } else if (opts.sheetid.indexOf('http') === 0) {
    url = opts.sheetid;
  } else {
    if (opts.sheetid.indexOf('/spreadsheets/d/') !== -1) {
      opts.sheetid = opts.sheetid.split('/spreadsheets/d/')[1].split('/')[0];
    }
    if (opts.sheet == null) {
      opts.sheet = 'default'; // or else a number, starting from 1, indicating which sheet in the overall sheet to access
    }
    url = 'https://spreadsheets.google.com/feeds/list/' + opts.sheetid + '/' + opts.sheet + '/public/values?alt=json';
  }
  g = (await this.fetch(url));
  for (l in g.feed.entry) {
    val = {};
    for (k in g.feed.entry[l]) {
      try {
        if (k.indexOf('gsx$') === 0) {
          val[k.replace('gsx$', '')] = g.feed.entry[l][k].$t;
        }
      } catch (error) {}
    }
    values.push(val);
  }
  return values;
};

P.src.google.sheets._bg = true;

// https://developers.google.com/hangouts/chat
// NOTE this will need oauth configuration for a full bot. For now just a web hook
// https://developers.google.com/hangouts/chat/how-tos/webhooks	
// pradm dev "pradm alert" google chat webhook
P.src.google.chat = function(params, url) {
  var data, headers, ref, ref1, ref2, ref3, ref4;
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
  } else {
    return void 0;
  }
};

'# docs:\n# https://developers.google.com/places/web-service/autocomplete\n# example:\n# https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Aberdeen%20Asset%20Management%20PLC&key=<OURKEY>\n\n\n# TODO add old deprecated google finance API, if useful for anything. Runs 15 mins delay\n# see http://finance.google.com/finance/info?client=ig&q=NASDAQ:AAPL\n# which runs pages lik https://finance.yahoo.com/quote/AAPL/profile\n\n\n# https://developers.google.com/knowledge-graph/\n# https://developers.google.com/knowledge-graph/reference/rest/v1/\nAPI.use.google.knowledge.retrieve = (mid,types) ->\n	exists = API.http.cache {mid:mid,types:types}, \'google_knowledge_retrieve\'\n	return exists if exists\n	u = \'https://kgsearch.googleapis.com/v1/entities:search?key=\' + API.settings.use.google.serverkey + \'&limit=1&ids=\' + mid\n	if types\n		types = types.join(\'&types=\') if typeof types isnt \'string\' # are multiple types done by comma separation or key repetition?\n		u += \'&types=\' + types\n	ret = {}\n	try\n		res = API.http.proxy \'GET\', u, true\n		ret = res.data.itemListElement[0].result\n		ret.score = res.data.itemListElement[0].resultScore\n	if not _.isEmpty ret\n		API.http.cache {mid:mid,types:types}, \'google_knowledge_retrieve\', ret\n	return ret\n\nAPI.use.google.knowledge.search = (qry,limit=10,refresh=604800000) -> # default 7 day cache\n	u = \'https://kgsearch.googleapis.com/v1/entities:search?key=\' + API.settings.use.google.serverkey + \'&limit=\' + limit + \'&query=\' + encodeURIComponent qry\n	API.log \'Searching google knowledge for \' + qry\n\n	checksum = API.job.sign qry\n	exists = API.http.cache checksum, \'google_knowledge_search\', undefined, refresh\n	return exists if exists\n\n	res = API.http.proxy(\'GET\',u,true).data\n	try API.http.cache checksum, \'google_knowledge_search\', res\n	return res\n\nAPI.use.google.knowledge.find = (qry) ->\n	res = API.use.google.knowledge.search qry\n	try\n		return res.itemListElement[0].result #could add an if resultScore > ???\n	catch\n		return undefined\n\n# https://cloud.google.com/natural-language/docs/getting-started\n# https://cloud.google.com/natural-language/docs/basics\nAPI.use.google.cloud.language = (content, actions=[\'entities\',\'sentiment\'], auth) ->\n	actions = actions.split(\',\') if typeof actions is \'string\'\n	return {} if not content?\n	checksum = API.job.sign content, actions\n	exists = API.http.cache checksum, \'google_language\'\n	return exists if exists\n\n	lurl = \'https://language.googleapis.com/v1/documents:analyzeEntities?key=\' + API.settings.use.google.serverkey\n	document = {document: {type: "PLAIN_TEXT",content:content},encodingType:"UTF8"}\n	result = {}\n	if \'entities\' in actions\n		try result.entities = API.http.proxy(\'POST\',lurl,{data:document,headers:{\'Content-Type\':\'application/json\'}},true).data.entities\n	if \'sentiment\' in actions\n		try result.sentiment = API.http.proxy(\'POST\',lurl.replace(\'analyzeEntities\',\'analyzeSentiment\'),{data:document,headers:{\'Content-Type\':\'application/json\'}},true).data\n	API.http.cache(checksum, \'google_language\', result) if not _.isEmpty result\n	return result\n\n# https://cloud.google.com/translate/docs/quickstart\nAPI.use.google.cloud.translate = (q, source, target=\'en\', format=\'text\') ->\n	# ISO source and target language codes\n	# https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes\n	return {} if not q?\n	checksum = API.job.sign q, {source: source, target: target, format: format}\n	exists = API.http.cache checksum, \'google_translate\'\n	return exists if exists\n	lurl = \'https://translation.googleapis.com/language/translate/v2?key=\' + API.settings.use.google.serverkey\n	result = API.http.proxy(\'POST\', lurl, {data:{q:q, source:source, target:target, format:format}, headers:{\'Content-Type\':\'application/json\'}},true)\n	if result?.data?.data?.translations\n		res = result.data.data.translations[0].translatedText\n		API.http.cache(checksum, \'google_language\', res) if res.length\n		return res\n		#return result.data.data\n	else\n		return {}\n\n\n\nAPI.use.google.places.autocomplete = (qry,location,radius) ->\n	url = \'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=\' + qry + \'&key=\' + API.settings.use.google.serverkey\n	url += \'&location=\' + location + \'&radius=\' + (radius ? \'10000\') if location?\n	try\n		return API.http.proxy(\'GET\',url,true).data\n	catch err\n		return {status:\'error\', error: err}\n\nAPI.use.google.places.place = (id,qry,location,radius) ->\n	if not id?\n		try\n			results = API.use.google.places.autocomplete qry,location,radius\n			id = results.predictions[0].place_id\n		catch err\n			return {status:\'error\', error: err}\n	url = \'https://maps.googleapis.com/maps/api/place/details/json?placeid=\' + id + \'&key=\' + API.settings.use.google.serverkey\n	try\n		return API.http.proxy(\'GET\',url,true).data\n	catch err\n		return {status:\'error\', error: err}\n\nAPI.use.google.places.url = (qry) ->\n	try\n		results = API.use.google.places.place undefined,qry\n		return {data: {url:results.result.website.replace(\'://\',\'______\').split(\'/\')[0].replace(\'______\',\'://\')}}\n	catch err\n		return {status:\'error\', error: err}\n\nAPI.use.google.places.nearby = (params={}) ->\n	url = \'https://maps.googleapis.com/maps/api/place/nearbysearch/json?\'\n	params.key ?= API.settings.use.google.serverkey\n	url += (if p is \'q\' then \'input\' else p) + \'=\' + params[p] + \'&\' for p of params\n	try\n		return API.http.proxy(\'GET\',url,true).data\n	catch err\n		return {status:\'error\', error: err}\n\nAPI.use.google.places.search = (params) ->\n	url = \'https://maps.googleapis.com/maps/api/place/textsearch/json?\'\n	params.key ?= API.settings.use.google.serverkey\n	url += (if p is \'q\' then \'input\' else p) + \'=\' + params[p] + \'&\' for p of params\n	try\n		return API.http.proxy(\'GET\',url,true).data\n	catch err\n		return {status:\'error\', error: err}\n\n\n\nAPI.use.google.sheets.api = {}\n# https://developers.google.com/sheets/api/reference/rest\nAPI.use.google.sheets.api.get = (sheetid, opts={}) ->\n	opts = {stale:opts} if typeof opts is \'number\'\n	opts.stale ?= 3600000\n	opts.key ?= API.settings.use.google.serverkey\n	try\n		sheetid = sheetid.split(\'/spreadsheets/d/\')[1].split(\'/\')[0] if sheetid.indexOf(\'/spreadsheets/d/\') isnt -1\n		url = \'https://sheets.googleapis.com/v4/spreadsheets/\' + sheetid\n		url += \'/values/\' + opts.start + \':\' + opts.end if opts.start and opts.end\n		url += \'?key=\' + opts.key\n		API.log \'Getting google sheet via API \' + url\n		g = HTTP.call \'GET\', url\n		return g.data ? g\n	catch err\n		return err\n\n# auth for sheets interactions that makes changes is complex, requiring oauth and an email account to be registered to the sheet, it seems\n# https://developers.google.com/sheets/api/guides/authorizing\n# https://developers.google.com/sheets/api/reference/rest/v4/spreadsheets.values/append\n# https://developers.google.com/identity/protocols/oauth2\n# https://developers.google.com/sheets/api/quickstart/nodejs#step_3_set_up_the_sample\n# https://cloud.google.com/apigee/docs/api-platform/security/oauth/access-tokens\n# https://docs.wso2.com/display/IntegrationCloud/Get+Credentials+for+Google+Spreadsheet\n# https://help.gooddata.com/doc/en/building-on-gooddata-platform/data-preparation-and-distribution/additional-data-load-reference/data-load-tutorials/load-data-from-google-spreadsheets-via-google-api\n# https://isd-soft.com/tech_blog/accessing-google-apis-using-service-account-node-js/\nAPI.use.google.sheets.api.values = (sheetid, opts={}) ->\n	opts.start ?= \'A1\'\n	if not opts.end?\n		sheet = if typeof sheetid is \'object\' then sheetid else API.use.google.sheets.api.get sheetid, opts\n		opts.sheet ?= 0 # could also be the ID or title of a sheet in the sheet... if so iterate them to find the matching one\n		rows = sheet.sheets[opts.sheet].properties.gridProperties.rowCount\n		cols = sheet.sheets[opts.sheet].properties.gridProperties.columnCount\n		opts.end = \'\'\n		ls = Math.floor cols/26\n		opts.end += (ls + 9).toString(36).toUpperCase() if ls isnt 0\n		opts.end += (cols + 9-ls).toString(36).toUpperCase()\n		opts.end += rows\n	values = []\n	try\n		keys = false\n		res = API.use.google.sheets.api.get sheetid, opts\n		opts.keys ?= 0 # always assume keys? where to tell which row to get them from? 0-indexed or 1-indexed or named?\n		keys = opts.keys if Array.isArray opts.keys\n		for s in res.values\n			if opts.keys? and keys is false\n				keys = s\n			else\n				obj = {}\n				for k of keys\n					try\n						obj[keys[k]] = s[k] if s[k] isnt \'\'\n				values.push(obj) if not _.isEmpty obj\n	return values\n	';

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
      'Ocp-Apim-Subscription-Key': key // TODO check how to pass the key header with fetch - and set a long cache time on it
    }
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

// https://docs.microsoft.com/en-us/academic-services/graph/reference-data-schema
// We get files via MS Azure dump and run an import script. Fields we get are:
// 'journal': ['JournalId', 'Rank', 'NormalizedName', 'DisplayName', 'Issn', 'Publisher', 'Webpage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
// 'author': ['AuthorId', 'Rank', 'NormalizedName', 'DisplayName', 'LastKnownAffiliationId', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'CreatedDate'],
// 'paper': ['PaperId', 'Rank', 'Doi', 'DocType', 'PaperTitle', 'OriginalTitle', 'BookTitle', 'Year', 'Date', 'OnlineDate', 'Publisher', 'JournalId', 'ConferenceSeriesId', 'ConferenceInstanceId', 'Volume', 'Issue', 'FirstPage', 'LastPage', 'ReferenceCount', 'CitationCount', 'EstimatedCitation', 'OriginalVenue', 'FamilyId', 'FamilyRank', 'CreatedDate'],
// 'affiliation': ['AffiliationId', 'Rank', 'NormalizedName', 'DisplayName', 'GridId', 'OfficialPage', 'Wikipage', 'PaperCount', 'PaperFamilyCount', 'CitationCount', 'Iso3166Code', 'Latitude', 'Longitude', 'CreatedDate'],
// 'relation': ['PaperId', 'AuthorId', 'AffiliationId', 'AuthorSequenceNumber', 'OriginalAuthor', 'OriginalAffiliation']
// of about 49k journals about 9 are dups, 37k have ISSN. 32k were already known from other soruces. Of about 250m papers, about 99m have DOIs
P.src.microsoft.graph = function(q) {
  var _append, longest, lvs, paper, ref, ref1, ref2, ref3, res, rt, title;
  // NOTE: although there are about 250m papers only about 90m have JournalId - the rest could be books, etc. Import them all?
  _append = function(rec) {
    var j;
    if (rec.JournalId && (j = this.src.microsoft.graph.journal(rec.JournalId))) {
      rec.journal = j;
    }
    //if ma = @src.microsoft.graph.abstract rec.PaperId
    //  rec.abstract = ma
    //rec.relation = @src.microsoft.graph._relations rec.PaperId, false, false
    return rec;
  };
  if (q == null) {
    q = (ref = (ref1 = (ref2 = this.params.graph) != null ? ref2 : this.params.doi) != null ? ref1 : this.params.title) != null ? ref : this.params;
  }
  if (typeof q === 'number') { // an MS ID like 2517073914 may turn up as number, if so convert to string
    q = q.toString();
  }
  if (typeof q === 'string' && q.indexOf('/') !== -1 && q.indexOf('10.') === 0 && (paper = this.src.microsoft.graph.paper('Doi.exact:"' + q + '"'))) {
    return _append(paper);
  } else if (typeof q === 'string' && q.indexOf(' ') === -1 && q.length === 10 && (paper = this.src.microsoft.graph.paper(q))) {
    return _append(paper);
  } else if (typeof q === 'string' && q.indexOf(' ') !== -1) {
    title = title.toLowerCase().replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim(); // MAG PaperTitle is lowercased. OriginalTitle isnt
    if (res = this.src.microsoft.graph.paper('PaperTitle:"' + title + '"')) {
      rt = res.PaperTitle.replace(/['".,\/\^&\*;:!\?#\$%{}=\-\+_`~()]/g, ' ').replace(/\s{2,}/g, ' ').trim();
      if (typeof (this != null ? (ref3 = this.tdm) != null ? ref3.levenshtein : void 0 : void 0) === 'function') {
        lvs = this.tdm.levenshtein(title, rt, false);
        longest = lvs.length.a > lvs.length.b ? lvs.length.a : lvs.length.b;
        if (lvs.distance < 2 || longest / lvs.distance > 10) {
          //res.relation = await @src.microsoft.graph._relations res.PaperId
          return res;
        }
      } else if (title.length < (rt.length * 1.2) && (title.length > rt.length * .8)) {
        //res.relation = await @src.microsoft.graph._relations res.PaperId
        return res;
      }
    }
    return void 0;
  } else {
    return this.src.microsoft.graph.paper(q);
  }
};

P.src.microsoft.graph.paper = async function(q) {
  var res, url;
  try {
    // for now just get from old index
    url = 'https://dev.lvatn.com/use/microsoft/graph/paper/?q=' + q;
    res = (await this.fetch(url));
    return res.hits.hits[0]._source;
  } catch (error) {
    return void 0;
  }
};

P.src.microsoft.graph.journal = async function(q) {
  var url;
  try {
    // for now just get from old index
    url = 'https://dev.lvatn.com/use/microsoft/graph/journal/' + q;
    return (await this.fetch(url));
  } catch (error) {
    return void 0;
  }
};

'P.src.microsoft.graph.paper = _index: true # TODO check how API init will pick up an index that has no main function\nP.src.microsoft.graph.journal = _index: true\nP.src.microsoft.graph.author = _index: true\nP.src.microsoft.graph.affiliation = _index: true\nP.src.microsoft.graph.abstract = _index: true\nP.src.microsoft.graph.relation = _index: true';

'P.src.microsoft.graph._relations = (q, papers=true, authors=true, affiliations=true) ->\n # [\'PaperId\', \'AuthorId\', \'AffiliationId\', \'AuthorSequenceNumber\', \'OriginalAuthor\', \'OriginalAffiliation\']\n # context could be paper, author, affiliation\n  results = []\n  _append = (recs) ->\n    res = []\n    recs = [recs] if not Array.isArray recs\n    for rec in recs\n      rec.paper = await @src.microsoft.graph.paper(rec.PaperId) if rec.PaperId and papers\n      rec.author = await @src.microsoft.graph.author(rec.AuthorId) if rec.AuthorId and authors\n      rec.affiliation = await @src.microsoft.graph.affiliation(rec.AffiliationId ? rec.LastKnownAffiliationId) if (rec.AffiliationId or rec.LastKnownAffiliationId) and affiliations\n      if rec.GridId or rec.affiliation?.GridId\n        try rec.ror = await @src.wikidata.grid2ror rec.GridId ? rec.affiliation?.GridId\n      res.push rec\n      results.push rec\n    return res\n\n  if typeof q is \'string\' and rel = await @src.microsoft.graph.relation q\n    return _append rel\n  \n  count = 0\n  if typeof q is \'string\' and cn = @src.microsoft.graph.relation.count \'PaperId.exact:"\' + q + \'"\'\n    count += cn\n    _append(@src.microsoft.graph.relation.fetch(\'PaperId.exact:"\' + q + \'"\')) if cn < 10\n  else if typeof q is \'string\' and cn = @src.microsoft.graph.relation.count \'AuthorId.exact:"\' + q + \'"\'\n    count += cn\n    _append(@src.microsoft.graph.relation.fetch(\'AuthorId.exact:"\' + q + \'"\')) if cn < 10\n  else if typeof q is \'string\' and cn = @src.microsoft.graph.relation.count \'AffiliationId.exact:"\' + q + \'"\'\n    count += cn\n    _append(@src.microsoft.graph.relation.fetch(\'AffiliationId.exact:"\' + q + \'"\')) if cn < 10\n\n  return results';

P.src.oadoi = function(doi) {
  var ref, ref1, ref2, url;
  if (doi == null) {
    doi = (ref = this != null ? (ref1 = this.params) != null ? ref1.oadoi : void 0 : void 0) != null ? ref : this != null ? (ref2 = this.params) != null ? ref2.doi : void 0 : void 0;
  }
  if (typeof doi === 'string' && doi.startsWith('10.')) {
    url = 'https://api.oadoi.org/v2/' + doi + '?email=' + S.mail.to;
    return this.fetch(url);
  } else {
    return void 0;
  }
};

P.src.oadoi._index = true;

P.src.oadoi._kv = false;

P.src.oadoi._key = 'doi';

try {
  S.svc.oaworks = JSON.parse(SECRETS_OAWORKS);
} catch (error) {
  S.svc.oaworks = {};
}

P.svc.oaworks = function() {
  return {
    name: 'OA.works API'
  };
};

// email templates - convert to a read from a sheet instead of currently in the repo
// oab status and stats
// make all request admin via sheet somehow
'P.svc.oaworks.bug = () ->\n  if (@body?.contact? and @body.contact.length) or (@body?.email? and @svc.oaworks.validate(@body.email) isnt true)\n    return \'\'\n  else\n    whoto = [\'help@openaccessbutton.org\']\n    text = \'\'\n    for k of @body\n      text += k + \': \' + JSON.stringify(@body[k],undefined,2) + \'\n\n\'\n    text = @tdm.clean text\n    subject = \'[OAB forms]\'\n    if @body?.form is \'uninstall\' # wrong bug general other\n      subject += \' Uninstall notice\'\n    else if @body?.form is \'wrong\'\n      subject += \' Wrong article\'\n    else if @body?.form is \'bug\'\n      subject += \' Bug\'\n    else if @body?.form is \'general\'\n      subject += \' General\'\n    else\n      subject += \' Other\'\n    subject += \' \' + Date.now()\n    try\n      if @body?.form in [\'wrong\',\'uninstall\']\n        whoto.push \'natalia.norori@openaccessbutton.org\'\n    @mail {\n      service: \'openaccessbutton\',\n      from: \'natalia.norori@openaccessbutton.org\',\n      to: whoto,\n      subject: subject,\n      text: text\n    }\n    return {\n      status: 302,\n      headers: {\n        \'Content-Type\': \'text/plain\',\n        \'Location\': (if @S.dev then \'https://dev.openaccessbutton.org\' else \'https://openaccessbutton.org\') + \'/feedback#defaultthanks\'\n      },\n      body: \'Location: \' + (if @S.dev then \'https://dev.openaccessbutton.org\' else \'https://openaccessbutton.org\') + \'/feedback#defaultthanks\'\n    }\n\n\nP.svc.oaworks.blacklist = (url) ->\n  url = url.toString() if typeof url is \'number\'\n  return false if url? and (url.length < 4 or url.indexOf(\'.\') is -1)\n  bl = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.blacklist, stale\n  blacklist = []\n  blacklist.push(i.url) for i in bl\n  if url\n    if url.indexOf(\'http\') isnt 0 and url.indexOf(\' \') isnt -1\n      return false # sometimes article titles get sent here, no point checking them on the blacklist\n    else\n      for b in blacklist\n        return true if url.indexOf(b) isnt -1\n      return false\n  else\n    return blacklist\n\n\nAPI.service.oab.validate = (email, domain, verify=true) ->\n  bad = [\'eric@talkwithcustomer.com\']\n  if typeof email isnt \'string\' or email.indexOf(\',\') isnt -1 or email in bad\n    return false\n  else if email.indexOf(\'@openaccessbutton.org\') isnt -1 or email.indexOf(\'@email.ghostinspector.com\') isnt -1 #or email in []\n    return true\n  else\n    v = @mail.validate email, @S.svc.oaworks.mail.pubkey\n    if v.is_valid and (not verify or v.mailbox_verification in [true,\'true\'])\n      return true\n    else if v.did_you_mean\n      return v.did_you_mean\n    else\n      return false\n\n\n# LIVE: https://docs.google.com/spreadsheets/d/1Te9zcQtBLq2Vx81JUE9R42fjptFGXY6jybXBCt85dcs/edit#gid=0\n# Develop: https://docs.google.com/spreadsheets/d/1AaY7hS0D9jtLgVsGO4cJuLn_-CzNQg0yCreC3PP3UU0/edit#gid=0\nP.svc.oaworks.redirect = (url) ->\n  return false if await @svc.oaworks.blacklist(url) is true # ignore anything on the usual URL blacklist\n  list = await @src.google.sheets @S.svc.oaworks?.google?.sheets?.redirect, 360000\n  for listing in list\n    if listing.redirect and url.replace(\'http://\',\'\').replace(\'https://\',\'\').split(\'#\')[0] is listing.redirect.replace(\'http://\',\'\').replace(\'https://\',\'\').split(\'#\')[0]\n      # we have an exact alternative for this url\n      return listing.redirect\n    else if typeof url is \'string\' and url.indexOf(listing.domain.replace(\'http://\',\'\').replace(\'https://\',\'\').split(\'/\')[0]) isnt -1\n      url = url.replace(\'http://\',\'https://\') if listing.domain.indexOf(\'https://\') is 0\n      listing.domain = listing.domain.replace(\'http://\',\'https://\') if url.indexOf(\'https://\') is 0\n      if (listing.fulltext and listing.splash and listing.identifier) or listing.element\n        source = url\n        if listing.fulltext\n          # switch the url by comparing the fulltext and splash examples, and converting the url in the same way\n          parts = listing.splash.split listing.identifier\n          if url.indexOf(parts[0]) is 0 # can only successfully replace if the incoming url starts with the same as the start of the splash url\n            diff = url.replace parts[0], \'\'\n            diff = diff.replace(parts[1],\'\') if parts.length > 1\n            url = listing.fulltext.replace listing.identifier, diff\n        else if listing.element and url.indexOf(\'.pdf\') is -1\n          try\n            content = await @fetch url # should really be a puppeteer render\n            url = content.toLowerCase().split(listing.element.toLowerCase())[1].split(\'"\')[0].split("\'")[0].split(\'>\')[0]\n        return false if (not url? or url.length < 6 or url is source) and listing.blacklist is "yes"\n      else if listing.loginwall and url.indexOf(listing.loginwall.replace(\'http://\',\'\').replace(\'https://\',\'\')) isnt -1\n        # this url is on the login wall of the repo in question, so it is no use\n        return false\n      else if listing.blacklist is "yes"\n        return false\n  if typeof url is \'string\'\n    # some URLs can be confirmed as resolvable but we also hit a captcha response and end up serving that to the user\n    # we introduced this because of issue https://github.com/OAButton/discussion/issues/1257\n    # and for example https://www.tandfonline.com/doi/pdf/10.1080/17521740701702115?needAccess=true\n    # ends up as https://www.tandfonline.com/action/captchaChallenge?redirectUri=%2Fdoi%2Fpdf%2F10.1080%2F17521740701702115%3FneedAccess%3Dtrue\n    for avoid in [\'captcha\',\'challenge\']\n      return undefined if url.toLowerCase().indexOf(avoid) isnt -1\n  return url';

// need listing of deposits and deposited for each user ID
// and/or given a uid, find the most recent URL that this users uid submitted a deposit for
// need to handle old/new user configs somehow - just store all the old ones and let the UI pick them up
// make sure all users submit the config with the incoming query (for those that still don't, temporarily copy them from old imported ones)
'P.svc.oaworks.deposit = (options={}, files) ->\n  # so need some metadata in options.metadata\n\n  d.deposit ?= []\n  dep = {createdAt: Date.now(), zenodo: {}}\n  dep.embedded = options.embedded if options.embedded\n  dep.demo = options.demo if options.demo\n  dep.pilot = options.pilot if options.pilot\n  if typeof dep.pilot is \'boolean\' or dep.pilot in [\'true\',\'false\'] # catch possible old erros with live/pilot values\n    dep.pilot = if dep.pilot is true or dep.pilot is \'true\' then Date.now() else undefined\n  dep.live = options.live if options.live\n  if typeof dep.live is \'boolean\' or dep.live in [\'true\',\'false\']\n    dep.live = if dep.live is true or dep.live is \'true\' then Date.now() else undefined\n  dep.name = (files[0].filename ? files[0].name) if files? and files.length\n  dep.email = options.email if options.email\n  dep.from = options.from if options.from and options.from isnt \'anonymous\' # should it still be possible to deposit anonymously?\n  dep.plugin = options.plugin if options.plugin\n  dep.confirmed = decodeURIComponent(options.confirmed) if options.confirmed\n\n  uc = options.config # should exist but may not\n\n  perms = @svc.oaworks.permissions d, files, undefined, dep.confirmed # if confirmed is true the submitter has confirmed this is the right file. If confirmed is the checksum this is a resubmit by an admin\n  if perms.file?.archivable and ((dep.confirmed? and dep.confirmed is perms.file.checksum) or not dep.confirmed) # if the depositor confirms we don\'t deposit, we manually review - only deposit on admin confirmation (but on dev allow it)\n    zn = {}\n    zn.content = files[0].data\n    zn.name = perms.file.name\n    zn.publish = @S.svc.oaworks?.deposit?.zenodo is true\n    creators = []\n    try\n      for a in d.metadata.author\n        if a.family?\n          at = {name: a.family + (if a.given then \', \' + a.given else \'\')}\n          try at.orcid = a.ORCID.split(\'/\').pop() if a.ORCID\n          try at.affiliation = a.affiliation.name if typeof a.affiliation is \'object\' and a.affiliation.name?\n          creators.push at \n    creators = [{name:\'Unknown\'}] if creators.length is 0\n    description = if d.metadata.abstract then d.metadata.abstract + \'<br><br>\' else \'\'\n    description += perms.best_permission?.deposit_statement ? (if d.metadata.doi? then \'The publisher\'s final version of this work can be found at https://doi.org/\' + d.metadata.doi else \'\')\n    description = description.trim()\n    description += \'.\' if description.lastIndexOf(\'.\') isnt description.length-1\n    description += \' \' if description.length\n    description += \'<br><br>Deposited by shareyourpaper.org and openaccessbutton.org. We\'ve taken reasonable steps to ensure this content doesn\'t violate copyright. However, if you think it does you can request a takedown by emailing help@openaccessbutton.org.\'\n    meta =\n      title: d.metadata.title ? \'Unknown\',\n      description: description.trim(),\n      creators: creators,\n      version: if perms.file.version is \'preprint\' then \'Submitted Version\' else if perms.file.version is \'postprint\' then \'Accepted Version\' else if perms.file.version is \'publisher pdf\' then \'Published Version\' else \'Accepted Version\',\n      journal_title: d.metadata.journal\n      journal_volume: d.metadata.volume\n      journal_issue: d.metadata.issue\n      journal_pages: d.metadata.page\n    meta.keywords = d.metadata.keyword if _.isArray(d.metadata.keyword) and d.metadata.keyword.length and typeof d.metadata.keyword[0] is \'string\'\n    if d.metadata.doi?\n      in_zenodo = @src.zenodo.records.doi d.metadata.doi\n      if in_zenodo and dep.confirmed isnt perms.file.checksum and not @S.dev\n        dep.zenodo.already = in_zenodo.id # we don\'t put it in again although we could with doi as related field - but leave for review for now\n      else if in_zenodo\n        meta[\'related_identifiers\'] = [{relation: (if meta.version is \'postprint\' or meta.version is \'AAM\' or meta.version is \'preprint\' then \'isPreviousVersionOf\' else \'isIdenticalTo\'), identifier: d.metadata.doi}]\n      else\n        meta.doi = d.metadata.doi\n    else if @S.svc.oaworks.zenodo?.prereserve_doi\n      meta.prereserve_doi = true\n    meta[\'access_right\'] = \'open\'\n    meta.license = perms.best_permission?.licence ? \'cc-by\' # zenodo also accepts other-closed and other-nc, possibly more\n    meta.license = \'other-closed\' if meta.license.indexOf(\'other\') isnt -1 and meta.license.indexOf(\'closed\') isnt -1\n    meta.license = \'other-nc\' if meta.license.indexOf(\'other\') isnt -1 and meta.license.indexOf(\'non\') isnt -1 and meta.license.indexOf(\'commercial\') isnt -1\n    meta.license += \'-4.0\' if meta.license.toLowerCase().indexOf(\'cc\') is 0 and isNaN(parseInt(meta.license.substring(meta.license.length-1)))\n    try\n      if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,\'YYYY-MM-DD\').valueOf() > Date.now()\n        meta[\'access_right\'] = \'embargoed\'\n        meta[\'embargo_date\'] = perms.best_permission.embargo_end # check date format required by zenodo\n    try meta[\'publication_date\'] = d.metadata.published if d.metadata.published? and typeof d.metadata.published is \'string\'\n    if uc\n      uc.community = uc.community_ID if uc.community_ID? and not uc.community?\n      if uc.community\n        uc.communities ?= []\n        uc.communities.push({identifier: ccm}) for ccm in (if typeof uc.community is \'string\' then uc.community.split(\',\') else uc.community)\n      if uc.community? or uc.communities?\n        uc.communities ?= uc.community\n        uc.communities = [uc.communities] if not Array.isArray uc.communities\n        meta[\'communities\'] = []\n        meta.communities.push(if typeof com is \'string\' then {identifier: com} else com) for com in uc.communities\n    tk = if @S.dev or dep.demo then @S.svc.oaworks?.zenodo?.sandbox else @S.svc.oaworks?.zenodo?.token\n    if tk\n      if not dep.zenodo.already\n        z = @src.zenodo.deposition.create meta, zn, tk\n        if z.id\n          dep.zenodo.id = z.id\n          dep.zenodo.url = \'https://\' + (if @S.dev or dep.demo then \'sandbox.\' else \'\') + \'zenodo.org/record/\' + z.id\n          dep.zenodo.doi = z.metadata.prereserve_doi.doi if z.metadata?.prereserve_doi?.doi?\n          dep.zenodo.file = z.uploaded?.links?.download ? z.uploaded?.links?.download\n        else\n          dep.error = \'Deposit to Zenodo failed\'\n          try dep.error += \': \' + JSON.stringify z\n    else\n      dep.error = \'No Zenodo credentials available\'\n  dep.version = perms.file.version if perms.file?.version?\n  if dep.zenodo.id\n    if perms.best_permission?.embargo_end and moment(perms.best_permission.embargo_end,\'YYYY-MM-DD\').valueOf() > Date.now()\n      dep.embargo = perms.best_permission.embargo_end\n    dep.type = \'zenodo\'\n  else if dep.error? and dep.error.toLowerCase().indexOf(\'zenodo\') isnt -1\n    dep.type = \'review\'\n  else if options.from and (not dep.embedded or (dep.embedded.indexOf(\'openaccessbutton.org\') is -1 and dep.embedded.indexOf(\'shareyourpaper.org\') is -1))\n    dep.type = if options.redeposit then \'redeposit\' else if files? and files.length then \'forward\' else \'dark\'\n  else\n    dep.type = \'review\'\n  # save the deposit record somewhere for later review\n\n  bcc = [\'joe@righttoresearch.org\',\'natalia.norori@openaccessbutton.org\']\n  tos = []\n  if typeof uc?.owner is \'string\' and uc.owner.indexOf(\'@\') isnt -1\n    tos.push uc.owner\n  else if dep.from and iacc = API.accounts.retrieve dep.from\n    try tos.push iacc.email ? iacc.emails[0].address # the institutional user may set a config value to use as the contact email address but for now it is the account address\n  if tos.length is 0\n    tos = _.clone bcc\n    bcc = []\n\n  dep.permissions = perms\n  dep.url = if typeof options.redeposit is \'string\' then options.redeposit else if d.url then d.url else undefined\n\n  ed = @copy dep\n  if ed.metadata?.author?\n    as = []\n    for author in ed.metadata.author\n      if author.family\n        as.push (if author.given then author.given + \' \' else \'\') + author.family\n    ed.metadata.author = as\n  ed.adminlink = (if ed.embedded then ed.embedded else \'https://shareyourpaper.org\' + (if ed.metadata?.doi? then \'/\' + ed.metadata.doi else \'\'))\n  ed.adminlink += if ed.adminlink.indexOf(\'?\') is -1 then \'?\' else \'&\'\n  if perms?.file?.checksum?\n    ed.confirmed = encodeURIComponent perms.file.checksum\n    ed.adminlink += \'confirmed=\' + ed.confirmed + \'&\'\n  ed.adminlink += \'email=\' + ed.email\n  tmpl = API.mail.template dep.type + \'_deposit.html\'\n  sub = API.service.oab.substitute tmpl.content, ed\n  if perms.file?.archivable isnt false # so when true or when undefined if no file is given\n    ml =\n      from: \'deposits@openaccessbutton.org\'\n      to: tos\n      subject: (sub.subject ? dep.type + \' deposit\')\n      html: sub.content\n    ml.bcc = bcc if bcc.length # passing undefined to mail seems to cause errors, so only set if definitely exists\n    ml.attachments = [{filename: (files[0].filename ? files[0].name), content: files[0].data}] if _.isArray(files) and files.length\n    @mail ml\n\n  dep.z = z if @S.dev and dep.zenodo.id? and dep.zenodo.id isnt \'EXAMPLE\'\n  \n  if dep.embargo\n    try dep.embargo_UI = moment(dep.embargo).format "Do MMMM YYYY"\n  return dep\n';


P.svc.oaworks.metadata = async function() {
  var res;
  res = (await this.svc.oaworks.find());
  return res.metadata;
};

P.svc.oaworks.find = async function(options, metadata = {}, content) {
  var _ill, _metadata, _permissions, _searches, bct, bong, dd, dps, i, len, mct, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, res, uo;
  res = {};
  _metadata = async(input) => {
    var ct, k, results;
    results = [];
    for (k in ct = (await this.svc.oaworks.citation(input))) {
      if (k === 'url' || k === 'paywall') {
        results.push(res[k] != null ? res[k] : res[k] = ct[k]);
      } else {
        results.push(metadata[k] != null ? metadata[k] : metadata[k] = ct[k]);
      }
    }
    return results;
  };
  try {
    if (options == null) {
      options = this.copy(this.params);
    }
  } catch (error) {}
  if (options == null) {
    options = {};
  }
  if (options.doi == null) {
    options.doi = options.find;
  }
  if (content == null) {
    content = (ref = options.dom) != null ? ref : this.request.body;
  }
  if (options.q || options.id) {
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
  if (options.title && (options.title.indexOf('{') !== -1 || ((ref4 = options.title.replace('...', '').match(/\./gi)) != null ? ref4 : []).length > 3 || ((ref5 = options.title.match(/\(/gi)) != null ? ref5 : []).length > 2)) {
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
    metadata.doi = metadata.doi.split(' ')[0].replace('http://', '').replace('https://', '').replace('doi.org/', '').replace('doi:', '').trim();
  } catch (error) {}
  if (typeof metadata.doi !== 'string' || metadata.doi.indexOf('10.') !== 0) {
    delete metadata.doi;
  }
  // switch exlibris URLs for titles, which the scraper knows how to extract, because the exlibris url would always be the same
  if (!metadata.title && content && typeof options.url === 'string' && (options.url.indexOf('alma.exlibrisgroup.com') !== -1 || options.url.indexOf('/exlibristest') !== -1)) {
    delete options.url;
  }
  _searches = async() => {
    var _crd, _crt, _mst, _oad, _pmt, epmc, ref7;
    if (((content != null) || (options.url != null)) && !(metadata.doi || (metadata.pmid != null) || (metadata.pmcid != null) || (metadata.title != null))) {
      await _metadata((await this.svc.oaworks.scrape(content != null ? content : options.url)));
    }
    if (!metadata.doi) {
      if (metadata.pmid || metadata.pmcid) {
        epmc = (await this.src.epmc[metadata.pmcid ? 'pmc' : 'pmid']((ref7 = metadata.pmcid) != null ? ref7 : metadata.pmid));
        await _metadata(epmc);
      }
      if (metadata.title && !metadata.doi) {
        _crt = async() => {
          if (!metadata.doi) {
            await _metadata((await this.src.crossref.works(metadata.title)));
          }
          return true;
        };
        _mst = async() => {
          if (!metadata.doi) {
            await _metadata((await this.src.microsoft.graph(metadata.title)));
          }
          return true;
        };
        _pmt = async() => {
          if ((epmc == null) && !metadata.doi) {
            await _metadata((await this.src.epmc.title(metadata.title)));
          }
          return true;
        };
        await Promise.all([_crt(), _mst(), _pmt()]);
      }
    }
    if (metadata.doi) {
      _oad = async() => {
        var oad;
        oad = (await this.src.oadoi(metadata.doi));
        if ((oad != null ? oad.doi : void 0) === metadata.doi) {
          await _metadata(oad);
        }
        return true;
      };
      _crd = async() => {
        var cr;
        cr = (await this.src.crossref.works(metadata.doi));
        if (!(cr != null ? cr.type : void 0)) {
          res.doi_not_in_crossref = metadata.doi;
          if (typeof options.url === 'string' && options.url.indexOf('doi.org/' + metadata.doi) !== -1) {
            delete options.url;
          }
          delete metadata.doi;
        } else {
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
  // TODO what to do if this finds anything? re-call the whole find?
  if (metadata.title && !metadata.doi && !content && !options.url && (typeof epmc === "undefined" || epmc === null)) {
    try {
      mct = unidecode(metadata.title.toLowerCase()).replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
      bong = (await this.src.microsoft.bing.search(mct));
      if (((bong != null ? bong.data : void 0) != null) && bong.data.length) {
        bct = unidecode(bong.data[0].name.toLowerCase()).replace('(pdf)', '').replace(/[^a-z0-9 ]+/g, " ").replace(/\s\s+/g, ' ');
        if (mct.replace(/ /g, '').indexOf(bct.replace(/ /g, '')) === 0 && !(await this.svc.oaworks.blacklist(bong.data[0].url))) {
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
    var ref10, ref7, ref8, ref9;
    if ((metadata.doi || metadata.title) && ((options.from != null) || (options.config != null)) && (options.plugin === 'instantill' || options.ill === true)) {
      if (res.ill == null) {
        res.ill = {};
      }
      try {
        res.ill.terms = (ref7 = (ref8 = options.config) != null ? ref8.terms : void 0) != null ? ref7 : (await this.svc.oaworks.ill.terms(options.from));
      } catch (error) {}
      try {
        res.ill.openurl = (await this.svc.oaworks.ill.openurl((ref9 = options.config) != null ? ref9 : options.from, metadata));
      } catch (error) {}
      try {
        res.ill.subscription = (await this.svc.oaworks.ill.subscription((ref10 = options.config) != null ? ref10 : options.from, metadata, res.refresh));
      } catch (error) {}
    }
    return true;
  };
  _permissions = async() => {
    var ref7;
    if (metadata.doi && (options.permissions || options.plugin === 'shareyourpaper')) { // don't get permissions by default now that the permissions check could take longer
      if (res.permissions == null) {
        res.permissions = (await this.svc.oaworks.permissions(metadata, (ref7 = options.config) != null ? ref7 : options.from));
      }
    }
    return true;
  };
  await Promise.all([_ill(), _permissions()]);
  ref7 = ['title', 'journal', 'year', 'doi'];
  // certain user-provided search values are allowed to override any that we could find ourselves, and we note that we got these from the user
  // is it worth keeping this in the backend or just have the embed handle it now that embed handles redirects to ill requests?
  // is this ONLY relevant to ILL? or anything else?
  for (i = 0, len = ref7.length; i < len; i++) {
    uo = ref7[i];
    if (options[uo] && options[uo] !== metadata[uo]) {
      metadata[uo] = options[uo];
    }
  }
  res.metadata = metadata;
  return res;
};

// Yi-Jeng Chen. (2016). Young Children's Collaboration on the Computer with Friends and Acquaintances. Journal of Educational Technology & Society, 19(1), 158-170. Retrieved November 19, 2020, from http://www.jstor.org/stable/jeductechsoci.19.1.158
// Baker, T. S., Eisenberg, D., & Eiserling, F. (1977). Ribulose Bisphosphate Carboxylase: A Two-Layered, Square-Shaped Molecule of Symmetry 422. Science, 196(4287), 293-295. doi:10.1126/science.196.4287.293
P.svc.oaworks.citation = function(citation) {
  var a, ak, bt, clc, cn, d, i, j, key, l, len, len1, len2, len3, len4, len5, len6, len7, m, ms, n, o, p, pbl, pt, pts, q, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref28, ref29, ref3, ref30, ref31, ref32, ref33, ref34, ref35, ref36, ref37, ref4, ref5, ref6, ref7, ref8, ref9, res, rmn, rp, rt, s, sy, t;
  res = {};
  try {
    if (citation == null) {
      citation = (ref = this.params.citation) != null ? ref : this.params;
    }
  } catch (error) {}
  if (typeof citation === 'string' && (citation.indexOf('{') === 0 || citation.indexOf('[') === 0)) {
    try {
      citation = JSON.parse(options.citation);
    } catch (error) {}
  }
  if (typeof citation === 'object') {
    if (res.doi == null) {
      res.doi = (ref1 = citation.DOI) != null ? ref1 : citation.doi;
    }
    try {
      if (res.type == null) {
        res.type = (ref2 = citation.type) != null ? ref2 : citation.genre;
      }
    } catch (error) {}
    if (res.issn == null) {
      res.issn = (ref3 = (ref4 = (ref5 = citation.ISSN) != null ? ref5 : citation.issn) != null ? ref4 : (ref6 = citation.journalInfo) != null ? (ref7 = ref6.journal) != null ? ref7.issn : void 0 : void 0) != null ? ref3 : (ref8 = citation.journal) != null ? ref8.issn : void 0;
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
      res.title = (ref9 = citation.dctitle) != null ? ref9 : (ref10 = citation.bibjson) != null ? ref10.title : void 0;
    }
    if ((ref11 = citation.title) !== 404 && ref11 !== '404') {
      if (res.title == null) {
        res.title = citation.title;
      }
    }
    if (res.title) {
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
    if (res.journal == null) {
      res.journal = (ref12 = (ref13 = citation.journal_name) != null ? ref13 : (ref14 = citation.journalInfo) != null ? (ref15 = ref14.journal) != null ? ref15.title : void 0 : void 0) != null ? ref12 : (ref16 = citation.journal) != null ? ref16.title : void 0;
    }
    if (citation.journal) {
      res.journal = citation.journal.split('(')[0].trim();
    }
    if (res.publisher == null) {
      res.publisher = citation.publisher;
    }
    try {
      if (citation.issue != null) {
        if (res.issue == null) {
          res.issue = citation.issue;
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
      if (citation.page != null) {
        if (res.page == null) {
          res.page = citation.page.toString();
        }
      }
    } catch (error) {}
    ref17 = ['title', 'journal'];
    for (i = 0, len = ref17.length; i < len; i++) {
      key = ref17[i];
      if (!res[key] && typeof citation[key] === 'string' && (citation[key].charAt(0).toUpperCase() !== citation[key].charAt(0) || citation[key].toUpperCase() === citation.key || citation[key].toLowerCase() === citation.key)) {
        res[key] = citation[key].charAt(0).toUpperCase() + citation[key].slice(1);
      }
    }
    if ((res.year == null) && ((citation.year != null) || (citation.published != null) || (citation.published_date != null))) {
      try {
        ref22 = ((ref20 = (ref21 = citation.year) != null ? ref21 : citation.published) != null ? ref20 : citation.published_date).split(((ref18 = (ref19 = citation.year) != null ? ref19 : citation.published) != null ? ref18 : citation.published_date).indexOf('/') !== -1 ? '/' : '-');
        for (j = 0, len1 = ref22.length; j < len1; j++) {
          ms = ref22[j];
          if (ms.length === 4) {
            if (res.year == null) {
              res.year = ms;
            }
          }
        }
      } catch (error) {}
      try {
        if (typeof res.year !== 'number' && (res.year.length !== 4 || res.year.replace(/[0-9]/gi, '').length !== 0)) {
          delete res.year;
        }
      } catch (error) {}
      if (typeof res.year === 'number') {
        res.year = res.year.toString();
      }
    }
    if ((res.year == null) && (res.published == null)) {
      ref23 = ['published-print', 'journal-issue.published-print', 'issued', 'published-online', 'created', 'deposited', 'indexed'];
      for (n = 0, len2 = ref23.length; n < len2; n++) {
        p = ref23[n];
        try {
          if (rt = (ref24 = citation[p]) != null ? ref24 : (ref25 = citation['journal-issue']) != null ? ref25[p.replace('journal-issue.', '')] : void 0) {
            if (typeof rt['date-time'] === 'string' && rt['date-time'].indexOf('T') !== -1 && rt['date-time'].split('T')[0].split('-').length === 3) {
              if (res.published == null) {
                res.published = rt['date-time'].split('T')[0];
              }
              if (res.year == null) {
                res.year = res.published.split('-')[0];
              }
              break;
            } else if ((rt['date-parts'] != null) && rt['date-parts'].length && Array.isArray(rt['date-parts'][0]) && rt['date-parts'][0].length) {
              rp = rt['date-parts'][0];
              pbl = rp[0].toString();
              if (pbl.length > 2) { // needs to be a year
                if (res.year == null) {
                  res.year = pbl;
                }
                if (rp.length === 1) {
                  pbl += '-01-01';
                } else {
                  m = false;
                  d = false;
                  if (!isNaN(parseInt(rp[1])) && parseInt(rp[1]) > 12) {
                    d = rp[1].toString();
                  } else {
                    m = rp[1].toString();
                  }
                  if (rp.length === 2) {
                    if (d !== false) {
                      m = rp[2].toString();
                    } else {
                      d = rp[2].toString();
                    }
                  }
                  m = m === false ? '01' : m.length === 1 ? '0' + m : m;
                  d = d === false ? '01' : d.length === 1 ? '0' + d : d;
                  pbl += '-' + m + '-' + d;
                }
                if (res.published == null) {
                  res.published = pbl;
                }
                break;
              }
            }
          }
        } catch (error) {}
      }
    }
    try {
      if ((res.author == null) && ((citation.author != null) || (citation.z_authors != null))) {
        if (res.author == null) {
          res.author = [];
        }
        ref27 = (ref26 = citation.author) != null ? ref26 : citation.z_authors;
        // what formats do we want for authors? how much metadata about them?
        for (o = 0, len3 = ref27.length; o < len3; o++) {
          a = ref27[o];
          if (typeof a === 'string') {
            res.author.push({
              name: a
            });
          } else {
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
            res.author.push(a);
          }
        }
      }
    } catch (error) {}
    try {
      if (((ref28 = citation.best_oa_location) != null ? ref28.license : void 0) && ((ref29 = citation.best_oa_location) != null ? ref29.license : void 0) !== null) {
        //for i of citation # should we grab everything else too? probably not
        //  res[i] ?= citation[i] if typeof citation[i] is 'string' or Array.isArray citation[i]
        if (res.licence == null) {
          res.licence = citation.best_oa_location.license;
        }
      }
    } catch (error) {}
    if (Array.isArray(citation.assertion)) {
      ref30 = citation.assertion;
      for (q = 0, len4 = ref30.length; q < len4; q++) {
        a = ref30[q];
        if (a.label === 'OPEN ACCESS' && a.URL && a.URL.indexOf('creativecommons') !== -1) {
          if (res.licence == null) {
            res.licence = a.URL; // and if the record has a URL, it can be used as an open URL rather than a paywall URL, or the DOI can be used
          }
        }
      }
    }
    if (Array.isArray(citation.license)) {
      ref32 = (ref31 = citation.license) != null ? ref31 : [];
      for (r = 0, len5 = ref32.length; r < len5; r++) {
        l = ref32[r];
        if (l.URL && l.URL.indexOf('creativecommons') !== -1 && (!rec.licence || rec.licence.indexOf('creativecommons') === -1)) {
          if (res.licence == null) {
            res.licence = l.URL;
          }
        }
      }
    }
    if (typeof citation.license === 'string') {
      if (res.licence == null) {
        res.licence = citation.license;
      }
    }
    if (typeof res.licence === 'string' && res.licence.indexOf('/licenses/') !== -1) {
      res.licence = 'cc-' + rec.licence.split('/licenses/')[1].replace(/$\//, '').replace(/\//g, '-');
    }
    // if there is a URL to use but not open, store it as res.paywall
    if (res.url == null) {
      res.url = (ref33 = (ref34 = (ref35 = citation.best_oa_location) != null ? ref35.url_for_pdf : void 0) != null ? ref34 : (ref36 = citation.best_oa_location) != null ? ref36.url : void 0) != null ? ref33 : citation.url; // is this always an open URL? check the sources, and check where else the open URL could be. Should it be blacklist checked and dereferenced?
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
        for (s = 0, len6 = pts.length; s < len6; s++) {
          pt = pts[s];
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
              ref37 = bt.split(',');
              for (t = 0, len7 = ref37.length; t < len7; t++) {
                ak = ref37[t];
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
  return res;
};

'there would be an index called svc_oaworks_find (possibly namespaced to service name and env, or global)\nmay also want to allow explicit naming of the index, not the same as the route\nso the usual index operations have to be available under P.svc.oaworks.find\nat /find we should serve the index of find results\n\nwhen .find is called, we need to know whether it is:\n  an attempt to get back one specific find (e.g. it was already previously run so the result exists)\n    so url params could do this - e.g. pass /find/10.1234/567890 or /find/id/1234 or /find/title/blah blah\n    and may want to check kv as well if set for this endpoint\n    check kv would entail:\n      look up the full url (with params?)\n      or look up a provided ID\n      \n  an attempt to run find\n    which could run if the above lookup returns nothing (or more than one?)\n    or if refresh is true, always run\n    so find needs a .run to fall back to (and if doesn\'t have one, nothing populates the index on a fail to find)\n    after .run:\n      save to index \n      index should also save a history if configured to do so\n      and save to kv if set to do so\n        would it be possible to also set multiple routes to point to one kv result?\n        like if a find on /find/10.1234/567890 should also be findable by /find/pmid/12345678\n      \n  an attempt to search finds\n    when there is no provided url params, and no query params that could be used to get back one specific one\n    or when there is a definitive search param provided, such as q or query or source?\n    \n{\n  env: may want to specify the env we are in (defaults to infer from Settings). Or false to be global to any env\n  index: false \'optional_index_name\' # optional, otherwise inferred from the url route - or could be false while kv is true\n  history: false # if true, on every edit, save a copy of the previous state of the record (requires index)\n  kv: false # whether or not to also store in the kv layer (default false). prob not worth using kv AND cache\n  cache: false # cache the results of the fetch requests to the index. could be true or false or a number for how long to cache\n  # also need a way to record the user ID of whoever caused a historic change, if available\n}\n\nwhat goes into the log as the recorded response for this sort of route?';

// this should default to a search of ILLs as well... with a restrict
// restrict = @auth.role('openaccessbutton.admin', @user) and this.queryParams.all then [] else [{term:{from:@user?._id}}]
var indexOf = [].indexOf;

P.svc.oaworks.ill = async function() { // only worked on POST with optional auth
  var a, atidy, ats, authors, base, config, eml, first, i, j, len, len1, m, meta, o, opts, ordered, r, ref, ref1, ref2, ref3, ref4, su, txt, user, vars;
  opts = this.params;
  if (this.user) {
    if (opts.from == null) {
      opts.from = this.user._id;
    }
    opts.api = true;
  }
  opts = (await this.tdm.clean(opts));
  // opts should include a key called metadata at this point containing all metadata known about the object
  // but if not, and if needed for the below stages, it is looked up again
  if (opts.metadata == null) {
    opts.metadata = {};
  }
  meta = this.svc.oaworks.metadata(opts);
  for (m in meta) {
    if ((base = opts.metadata)[m] == null) {
      base[m] = meta[m];
    }
  }
  if (opts.pilot === true) {
    opts.pilot = Date.now();
  }
  if (opts.live === true) {
    opts.live = Date.now();
  }
  if (opts.library === 'imperial') {
    // TODO for now we are just going to send an email when a user creates an ILL
    // until we have a script endpoint at the library to hit
    // library POST URL: https://www.imperial.ac.uk/library/dynamic/oabutton/oabutton3.php
    if (!opts.forwarded && !opts.resolved) {
      this.mail({
        service: 'openaccessbutton',
        from: 'natalia.norori@openaccessbutton.org',
        to: ['joe@righttoresearch.org', 's.barron@imperial.ac.uk'],
        subject: 'EXAMPLE ILL TRIGGER',
        text: JSON.stringify(opts, void 0, 2)
      });
      //@mail {template:{filename:'imperial_confirmation_example.txt'}, to:opts.id}
      this.waitUntil(this.fetch('https://www.imperial.ac.uk/library/dynamic/oabutton/oabutton3.php', {
        body: opts,
        method: 'POST'
      }));
    }
    return opts; //oab_ill.insert opts # TODO this needs to save into an ill index somewhere. will _index: true be enough for this?
  } else if ((opts.from != null) || (opts.config != null)) {
    if (opts.from !== 'anonymous') {
      user = this.auth(opts.from);
    }
    if ((user != null) || (opts.config != null)) {
      config = opts.config; //? get the old user config from old system data
      if (config.requests) {
        if (config.requests_off == null) {
          config.requests_off = config.requests;
        }
      }
      if (opts.config != null) {
        delete opts.config;
      }
      vars = {};
      vars.name = (ref = user != null ? (ref1 = user.profile) != null ? ref1.firstname : void 0 : void 0) != null ? ref : 'librarian';
      vars.details = '';
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
            vars.details += authors + '</p>';
            vars[r] = ats;
          } else if (['started', 'ended', 'took'].indexOf(r) === -1) {
            vars.details += '<p>' + r + ':<br>' + opts[r] + '</p>';
          }
        }
      }
      if (config.requests_off) {
        //vars.details += '<p>' + o + ':<br>' + opts[o] + '</p>'
        opts.requests_off = true;
      }
      if (opts.author != null) {
        delete opts.author; // remove author metadata due to messy provisions causing save issues
      }
      if (((ref3 = opts.metadata) != null ? ref3.author : void 0) != null) {
        delete opts.metadata.author;
      }
      //vars.illid = oab_ill.insert opts # TODO need to save an ILL record here
      vars.details += '<p>Open access button ILL ID:<br>' + vars.illid + '</p>';
      eml = config.email && config.email.length ? config.email : (user != null ? user.email : void 0) ? user != null ? user.email : void 0 : false;
      // such as https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=in%3A&si0qs=0021-9231&si1in=au%3A&si1op=AND&si2in=kw%3A&si2op=AND&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch
      // could be provided as: (unless other params are mandatory) 
      // https://ambslibrary.share.worldcat.org/wms/cmnd/nd/discover/items/search?si0qs=0021-9231
      if (config.search && config.search.length && (opts.issn || opts.journal)) {
        if (config.search.indexOf('worldcat') !== -1) {
          su = config.search.split('?')[0] + '?ai0id=level3&ai0type=scope&offset=1&pageSize=10&si0in=';
          su += opts.issn != null ? 'in%3A' : 'ti%3A';
          su += '&si0qs=' + ((ref4 = opts.issn) != null ? ref4 : opts.journal);
          su += '&sortDirection=descending&sortKey=librarycount&applicationId=nd&requestType=search&searchType=advancedsearch&eventSource=df-advancedsearch';
        } else {
          su = config.search;
          su += opts.issn ? opts.issn : opts.journal;
        }
        vars.details += '<p>Search URL:<br><a href="' + su + '">' + su + '</a></p>';
        vars.worldcatsearchurl = su;
      }
      if (!opts.forwarded && !opts.resolved && eml) {
        this.svc.oaworks.mail({
          vars: vars,
          template: {
            filename: 'instantill_create.html'
          },
          to: eml,
          from: "InstantILL <InstantILL@openaccessbutton.org>",
          subject: "ILL request " + vars.illid
        });
      }
      // send msg to mark and joe for testing (can be removed later)
      txt = vars.details;
      delete vars.details;
      txt += '<br><br>' + JSON.stringify(vars, void 0, 2);
      this.mail({
        service: 'openaccessbutton',
        from: 'InstantILL <InstantILL@openaccessbutton.org>',
        to: ['mark@cottagelabs.com', 'joe@righttoresearch.org'],
        subject: 'ILL CREATED',
        html: txt,
        text: txt
      });
      return vars.illid;
    } else {
      return {
        status: 401
      };
    }
  } else {
    return {
      status: 404
    };
  }
};

P.svc.oaworks.ill.collect = function() {
  var q, sid, url;
  sid = this.params.collect; // end of the url is an SID
  // example AKfycbwPq7xWoTLwnqZHv7gJAwtsHRkreJ1hMJVeeplxDG_MipdIamU6
  url = 'https://script.google.com/macros/s/' + sid + '/exec?';
  for (q in this.params) {
    if (q !== 'collect') {
      url += q + '=' + this.params[q] + '&';
    }
  }
  url += 'uuid=' + this.uid();
  this.waitUntil(this.fetch(url));
  return true;
};

P.svc.oaworks.ill.openurl = async function() {
  var author, config, d, defaults, i, k, len, m, nfield, opts, ref, ref1, uid, url, v;
  // Will eventually redirect after reading openurl params passed here, somehow. 
  // For now a POST of metadata here by a user with an open url registered will build their openurl
  opts = this.params;
  if (opts.config != null) {
    if (opts.uid == null) {
      opts.uid = opts.config;
    }
    delete opts.config;
  }
  if (opts.metadata != null) {
    for (m in opts.metadata) {
      if (opts[m] == null) {
        opts[m] = opts.metadata[m];
      }
    }
    delete opts.metadata;
  }
  if (!opts.uid && (this.user == null)) {
    return {
      status: 404
    };
  } else {
    opts = (await this.tdm.clean(opts));
    uid = (ref = opts.uid) != null ? ref : this.user._id;
    config = typeof uid === 'object' ? uid : void 0;
    if (config == null) {
      config = {};
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
    if (withoutbase !== true && !config.ill_form) { // support redirect base url for legacy config
      return '';
    }
    // add iupui / openURL defaults to config
    defaults = {
      sid: 'sid',
      title: 'atitle', // this is what iupui needs (title is also acceptable, but would clash with using title for journal title, which we set below, as iupui do that
      doi: 'rft_id', // don't know yet what this should be
      //pmid: 'pmid' # same as iupui ill url format
      pmcid: 'pmcid', // don't know yet what this should be
      //aufirst: 'aufirst' # this is what iupui needs
      //aulast: 'aulast' # this is what iupui needs
      author: 'aulast', // author should actually be au, but aulast works even if contains the whole author, using aufirst just concatenates
      journal: 'title', // this is what iupui needs
      //issn: 'issn' # same as iupui ill url format
      //volume: 'volume' # same as iupui ill url format
      //issue: 'issue' # same as iupui ill url format
      //spage: 'spage' # this is what iupui needs
      //epage: 'epage' # this is what iupui needs
      page: 'pages', // iupui uses the spage and epage for start and end pages, but pages is allowed in openurl, check if this will work for iupui
      published: 'date', // this is what iupui needs, but in format 1991-07-01 - date format may be a problem
      year: 'rft.year' // this is what IUPUI uses
    };
    // IUPUI also has a month field, but there is nothing to match to that
    for (d in defaults) {
      if (!config[d]) {
        config[d] = defaults[d];
      }
    }
    url = config.ill_form ? config.ill_form : '';
    url += url.indexOf('?') === -1 ? '?' : '&';
    if (config.ill_added_params) {
      url += config.ill_added_params.replace('?', '') + '&';
    }
    url += config.sid + '=InstantILL&';
    for (k in meta) {
      v = false;
      if (k === 'author') {
        try {
          // need to check if config has aufirst and aulast or something similar, then need to use those instead, 
          // if we have author name parts
          if (typeof meta.author === 'string') {
            v = meta.author;
          } else if (Array.isArray(meta.author)) {
            v = '';
            ref1 = meta.author;
            for (i = 0, len = ref1.length; i < len; i++) {
              author = ref1[i];
              if (v.length) {
                v += ', ';
              }
              if (typeof author === 'string') {
                v += author;
              } else if (author.family) {
                v += author.family + (author.given ? ', ' + author.given : '');
              }
            }
          } else {
            if (meta.author.family) {
              v = meta.author.family + (meta.author.given ? ', ' + meta.author.given : '');
            } else {
              v = JSON.stringify(meta.author);
            }
          }
        } catch (error1) {}
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
  }
};

P.svc.oaworks.ill.subscription = async function(uid, meta) {
  var config, do_serialssolutions_xml, do_sfx_xml, err, error, fnd, npg, openurl, pg, ref, ref1, ref2, ref3, ref4, res, s, spg, sub, subtype, surl, tid, url, user;
  if (uid == null) {
    uid = (ref = this.user) != null ? ref : this.params.uid;
  }
  if (meta == null) {
    meta = JSON.parse(JSON.stringify(this.params));
    delete meta.uid;
  }
  do_serialssolutions_xml = true;
  do_sfx_xml = true;
  res = {
    findings: {},
    lookups: [],
    error: [],
    contents: []
  };
  if (typeof uid === 'string') {
    res.uid = uid;
    user = this.auth(uid);
    config = user != null ? (ref1 = user.service) != null ? (ref2 = ref1.openaccessbutton) != null ? (ref3 = ref2.ill) != null ? ref3.config : void 0 : void 0 : void 0 : void 0;
  } else {
    config = uid;
  }
  if ((config != null ? config.subscription : void 0) != null) {
    if (config.ill_redirect_params) {
      if (config.ill_added_params == null) {
        config.ill_added_params = config.ill_redirect_params;
      }
    }
    // need to get their subscriptions link from their config - and need to know how to build the query string for it
    openurl = this.svc.oaworks.ill.openurl(config, meta, true);
    if (config.ill_added_params) {
      openurl = openurl.replace(config.ill_added_params.replace('?', ''), '');
    }
    if (openurl.indexOf('?') !== -1) {
      openurl = openurl.split('?')[1];
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
        subtype = (ref4 = config.subscription_type[s]) != null ? ref4 : 'unknown';
      }
      sub = sub.trim();
      if (sub) {
        if ((subtype === 'serialssolutions' || sub.indexOf('serialssolutions') !== -1) && sub.indexOf('.xml.') === -1 && do_serialssolutions_xml === true) {
          tid = sub.split('.search')[0];
          if (tid.indexOf('//') !== -1) {
            tid = tid.split('//')[1];
          }
          //bs = if sub.indexOf('://') isnt -1 then sub.split('://')[0] else 'http' # always use htto because https on the xml endpoint fails
          sub = 'http://' + tid + '.openurl.xml.serialssolutions.com/openurlxml?version=1.0&genre=article&';
        } else if ((subtype === 'sfx' || sub.indexOf('sfx.') !== -1) && sub.indexOf('sfx.response_type=simplexml') === -1 && do_sfx_xml === true) {
          sub += (sub.indexOf('?') === -1 ? '?' : '&') + 'sfx.response_type=simplexml';
        }
        url = sub + (sub.indexOf('?') === -1 ? '?' : '&') + openurl;
        if (url.indexOf('snc.idm.oclc.org/login?url=') !== -1) {
          url = url.split('snc.idm.oclc.org/login?url=')[1];
        }
        url = url.replace('cache=true', '');
        if (subtype === 'sfx' || sub.indexOf('sfx.') !== -1 && url.indexOf('=10.') !== -1) {
          url = url.replace('=10.', '=doi:10.');
        }
        // need to use the proxy as some subscriptions endpoints need a registered IP address, and ours is registered for some of them already
        // but having a problem passing proxy details through, so ignore for now
        // BUT AGAIN eds definitely does NOT work without puppeteer so going to have to use that again for now and figure out the proxy problem later
        //pg = API.http.puppeteer url #, undefined, API.settings.proxy
        // then get that link
        // then in that link find various content, depending on what kind of service it is

        // try doing without puppeteer and see how that goes
        pg = '';
        spg = '';
        error = false;
        res.lookups.push(url);
        try {
          //pg = HTTP.call('GET', url, {timeout:15000, npmRequestOptions:{proxy:API.settings.proxy}}).content
          pg = url.indexOf('.xml.serialssolutions') !== -1 || url.indexOf('sfx.response_type=simplexml') !== -1 ? (await this.fetch(url)) : (await this.puppet(url)); //, undefined, API.settings.proxy
          spg = pg.indexOf('<body') !== -1 ? pg.toLowerCase().split('<body')[1].split('</body')[0] : pg;
          res.contents.push(spg);
        } catch (error1) {
          err = error1;
          error = true;
        }
        //res.u ?= []
        //res.u.push url
        //res.pg = pg

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
          if (do_sfx_xml) {
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
            }
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
        // does not appear to need proxy or password
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
          if (do_serialssolutions_xml === true) {
            if (spg.indexOf('<ssopenurl:url type="article">') !== -1) {
              fnd = spg.split('<ssopenurl:url type="article">')[1].split('</ssopenurl:url>')[0].trim(); // this gets us something that has an empty accountid param - do we need that for it to work?
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
            }
          } else {
            // disable journal matching for now until we have time to get it more accurate - some things get journal links but are not subscribed
            //else if spg.indexOf('<ssopenurl:result format="journal">') isnt -1
            //  # we assume if there is a journal result but not a URL that it means the institution has a journal subscription but we don't have a link
            //  res.journal = true
            //  res.found = 'serials'
            //  API.http.cache(sig, 'oab_ill_subs', res)
            //  return res
            if (spg.indexOf('ss_noresults') === -1) {
              try {
                surl = url.split('?')[0] + '?ShowSupressedLinks' + pg.split('?ShowSupressedLinks')[1].split('">')[0];
                //npg = API.http.puppeteer surl #, undefined, API.settings.proxy
                npg = this.fetch(surl, {
                  timeout: 15000,
                  npmRequestOptions: {
                    proxy: S.proxy
                  }
                });
                if (npg.indexOf('ArticleCL') !== -1 && npg.split('DatabaseCL')[0].indexOf('href="./log') !== -1) {
                  res.url = surl.split('?')[0] + npg.split('ArticleCL')[1].split('DatabaseCL')[0].split('href="')[1].split('">')[0];
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
        }
      }
    }
  }
  return res;
};

var indexOf = [].indexOf;

P.svc.oaworks.permissions = async function(meta, roruid, getmeta) {
  var _getmeta, _prep, _score, af, altoa, an, cr, cwd, doa, fz, haddoi, i, inisn, inp, issns, j, key, l, len, len1, len10, len2, len3, len4, len5, len6, len7, len8, len9, longest, lvs, m, msgs, n, o, oadoi, overall_policy_restriction, p, pb, perms, pisoa, ps, q, qr, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref3, ref4, ref5, ref6, ref7, ref8, ref9, ro, rors, rp, rr, rs, rwd, sn, snak, snkd, t, tr, u, uc, v, vl, w, wp;
  overall_policy_restriction = false;
  cr = false;
  haddoi = false;
  if (meta == null) {
    meta = this.copy(this.params);
  }
  if ((meta != null ? meta.permissions : void 0) != null) {
    if (meta.permissions.startsWith('journal/')) {
      meta.issn = meta.permissions.replace('journal/', '');
    } else if (meta.permissions.startsWith('affiliation/')) {
      meta.ror = meta.permissions.replace('affiliation/', '');
    } else if (meta.permissions.startsWith('publisher/')) {
      meta.publisher = meta.permissions.replace('publisher/', '');
    } else if (meta.permissions.indexOf('10.') === 0 && meta.permissions.indexOf('/') !== -1) {
      meta.doi = meta.permissions;
    } else if (meta.permissions.indexOf('-') !== 0 && meta.permissions.length < 10 && meta.permissions.length > 6) {
      meta.issn = meta.permissions;
    } else {
      meta.publisher = meta.permissions; // but could be a ROR?
    }
    delete meta.permissions;
  }
  _prep = async function(rec) {
    var a, d, em, eph, fst, i, j, len, len1, len2, m, ph, pt, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, swaps;
    if (haddoi && rec.embargo_months && (meta.published || meta.year)) {
      em = moment((ref = meta.published) != null ? ref : meta.year + '-01-01');
      em = em.add(rec.embargo_months, 'months');
      rec.embargo_end = em.format("YYYY-MM-DD");
    }
    if (rec.embargo_end === '') {
      delete rec.embargo_end;
    }
    rec.copyright_name = rec.copyright_owner === 'publisher' ? (typeof rec.issuer.parent_policy === 'string' ? rec.issuer.parent_policy : typeof rec.issuer.id === 'string' ? rec.issuer.id : rec.issuer.id[0]) : (ref1 = rec.copyright_owner) === 'journal' || ref1 === 'affiliation' ? (ref2 = meta.journal) != null ? ref2 : '' : (rec.copyright_owner && rec.copyright_owner.toLowerCase().indexOf('author') !== -1) && (meta.author != null) && meta.author.length && (meta.author[0].name || meta.author[0].family) ? ((ref3 = meta.author[0].name) != null ? ref3 : meta.author[0].family) + (meta.author.length > 1 ? ' et al' : '') : '';
    if (((ref4 = rec.copyright_name) === 'publisher' || ref4 === 'journal') && (cr || meta.doi || ((ref5 = rec.provenance) != null ? ref5.example : void 0))) {
      if (cr === false) {
        cr = (await this.src.crossref.works((ref6 = meta.doi) != null ? ref6 : rec.provenance.example));
      }
      if (((cr != null ? cr.assertion : void 0) != null) && cr.assertion.length) {
        ref7 = cr.assertion;
        for (i = 0, len = ref7.length; i < len; i++) {
          a = ref7[i];
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
    }
    if (haddoi && rec.copyright_year === '' && meta.year) {
      rec.copyright_year = meta.year;
    }
    if (rec.copyright_year === '') {
      delete rec.copyright_year;
    }
    if (haddoi && (rec.deposit_statement != null) && rec.deposit_statement.indexOf('<<') !== -1) {
      fst = '';
      ref8 = rec.deposit_statement.split('<<');
      for (j = 0, len1 = ref8.length; j < len1; j++) {
        pt = ref8[j];
        if (fst === '' && pt.indexOf('>>') === -1) {
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
              fst += ((ref9 = meta.author[0].name) != null ? ref9 : meta.author[0].family) + (meta.author.length > 1 ? ' et al' : '');
            } catch (error) {}
          } else {
            fst += (ref10 = (ref11 = meta[ph]) != null ? ref11 : rec[ph]) != null ? ref10 : '';
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
    if (typeof ((ref12 = rec.issuer) != null ? ref12.has_policy : void 0) === 'string' && ((ref13 = rec.issuer.has_policy.toLowerCase().trim()) === 'not publisher' || ref13 === 'takedown')) {
      // find out if this should be enacted if it is the case for any permission, or only the best permission
      overall_policy_restriction = rec.issuer.has_policy;
    }
    ref14 = ['_id', 'permission_required', 'createdAt', 'updatedAt', 'created_date', 'updated_date'];
    for (m = 0, len2 = ref14.length; m < len2; m++) {
      d = ref14[m];
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
    if (rec.embargo_months && rec.embargo_months >= 36 && (!rec.embargo_end || moment(rec.embargo_end, "YYYY-MM-DD").isBefore(moment()))) {
      score -= 25;
    }
    return score;
  };
  inp = {};
  if (typeof meta === 'string') {
    meta = meta.indexOf('10.') === 0 ? {
      doi: meta
    } : {
      issn: meta
    };
  }
  if (meta.meta != null) {
    delete meta.meta; // just used to pass in a false to getmeta
  }
  if (meta.metadata != null) {
    inp = meta;
    meta = meta.metadata; // if passed a catalogue object
  }
  if (meta.affiliation) {
    meta.ror = meta.affiliation;
    delete meta.affiliation;
  }
  if (meta.journal && meta.journal.indexOf(' ') === -1) {
    meta.issn = meta.journal;
    delete meta.journal;
  }
  if (meta.publisher && meta.publisher.indexOf(' ') === -1 && meta.publisher.indexOf(',') === -1 && !oab_permissions.find('issuer.type.exact:"publisher" AND issuer.id:"' + meta.publisher + '"')) {
    // it is possible this may actually be a ror, so switch to ror just in case - if it still matches nothing, no loss
    meta.ror = meta.publisher;
    delete meta.publisher;
  }
  issns = Array.isArray(meta.issn) ? meta.issn : []; // only if directly passed a list of ISSNs for the same article, accept them as the ISSNs list to use
  if (typeof meta.issn === 'string' && meta.issn.indexOf(',') !== -1) {
    meta.issn = meta.issn.split(',');
  }
  if (typeof meta.ror === 'string' && meta.ror.indexOf(',') !== -1) {
    meta.ror = meta.ror.split(',');
  }
  if (!meta.ror) {
    uc = typeof roruid === 'object' ? roruid : typeof roruid === 'string' ? this.svc.oaworks.deposit.config(roruid) : void 0;
    if ((typeof uc === 'object' && (uc.ror != null)) || typeof roruid === 'string') {
      meta.ror = (ref = uc != null ? uc.ror : void 0) != null ? ref : roruid;
    }
  }
  if (JSON.stringify(meta) === '{}' || (meta.issn && JSON.stringify(meta.issn).indexOf('-') === -1) || (meta.doi && (typeof meta.doi !== 'string' || meta.doi.indexOf('10.') !== 0 || meta.doi.indexOf('/') === -1))) {
    return {
      body: 'No valid DOI, ISSN, or ROR provided',
      statusCode: 404
    };
  }
  
  // NOTE later will want to find affiliations related to the authors of the paper, but for now only act on affiliation provided as a ror
  // we now always try to get the metadata because joe wants to serve a 501 if the doi is not a journal article
  _getmeta = () => {
    var mk, psm, results, rsm;
    psm = this.copy(meta);
    delete psm.ror;
    if (JSON.stringify(psm) !== '{}') {
      rsm = this.svc.oaworks.metadata({
        metadata: ['crossref_type', 'issn', 'publisher', 'published', 'year', 'author', 'ror']
      }, psm);
      results = [];
      for (mk in rsm) {
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
  af = false;
  if (meta.issn) {
    if (typeof meta.issn === 'string') {
      meta.issn = [meta.issn];
    }
    if (!issns.length) { // they're already meta.issn in this case anyway
      ref1 = meta.issn;
      for (i = 0, len = ref1.length; i < len; i++) {
        inisn = ref1[i];
        if (indexOf.call(issns, inisn) < 0) { // check just in case
          issns.push(inisn);
        }
      }
    }
    if (!issns.length || !meta.publisher || !meta.doi) {
      if (af = academic_journal.find('issn.exact:"' + issns.join('" OR issn.exact:"') + '"')) {
        if (meta.publisher == null) {
          meta.publisher = af.publisher;
        }
        ref2 = (typeof af.issn === 'string' ? [af.issn] : af.issn);
        for (j = 0, len1 = ref2.length; j < len1; j++) {
          an = ref2[j];
          if (indexOf.call(issns, an) < 0) { // check again
            issns.push(an);
          }
        }
        if (meta.doi == null) {
          meta.doi = af.doi;
        }
      }
    }
    try {
      if (meta.doi == null) {
        meta.doi = (await this.src.crossref.journals.doi(issns)); // temporary until wider crossref update completed
      }
    } catch (error) {
      if (meta.doi == null) {
        meta.doi = (await this.src.crossref.journals.dois.example(issns));
      }
    }
    if (!haddoi && meta.doi) {
      await _getmeta();
    }
  }
  if (haddoi && ((ref3 = meta.crossref_type) !== 'journal-article')) {
    return {
      body: 'DOI is not a journal article',
      status: 501
    };
  }
  if (meta.publisher && meta.publisher.indexOf('(') !== -1 && meta.publisher.lastIndexOf(')') > (meta.publisher.length * .7)) {
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
      meta.citation += 'p' + ((ref4 = meta.page) != null ? ref4 : meta.pages);
    }
    if (meta.year || meta.published) {
      meta.citation += ' (' + ((ref5 = meta.year) != null ? ref5 : meta.published).split('-')[0] + ')';
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
    rs = oab_permissions.search('issuer.id.exact:"' + meta.ror.join('" OR issuer.id.exact:"') + '"');
    if (!(rs != null ? (ref6 = rs.hits) != null ? ref6.total : void 0 : void 0)) {
      // look up the ROR in wikidata - if found, get the qid from the P17 country snak, look up that country qid
      // get the P297 ISO 3166-1 alpha-2 code, search affiliations for that
      if (rwd = wikidata_record.find('snaks.property.exact:"P6782" AND snaks.property.exact:"P17" AND (snaks.value.exact:"' + meta.ror.join(" OR snaks.value.exact:") + '")')) {
        snkd = false;
        ref7 = rwd.snaks;
        for (m = 0, len2 = ref7.length; m < len2; m++) {
          snak = ref7[m];
          if (snkd) {
            break;
          } else if (snak.property === 'P17') {
            if (cwd = wikidata_record.get(snak.qid)) {
              ref8 = cwd.snaks;
              for (n = 0, len3 = ref8.length; n < len3; n++) {
                sn = ref8[n];
                if (sn.property === 'P297') {
                  snkd = true;
                  rs = oab_permissions.search('issuer.id.exact:"' + sn.value + '"');
                  break;
                }
              }
            }
          }
        }
      }
    }
    ref11 = (ref9 = rs != null ? (ref10 = rs.hits) != null ? ref10.hits : void 0 : void 0) != null ? ref9 : [];
    for (o = 0, len4 = ref11.length; o < len4; o++) {
      rr = ref11[o];
      tr = _prep(rr._source);
      tr.score = _score(tr);
      rors.push(tr);
    }
  }
  if (issns.length || meta.publisher) {
    qr = issns.length ? 'issuer.id.exact:"' + issns.join('" OR issuer.id.exact:"') + '"' : '';
    if (meta.publisher) {
      if (qr !== '') {
        qr += ' OR ';
      }
      qr += 'issuer.id:"' + meta.publisher + '"'; // how exact/fuzzy can this be
    }
    ps = oab_permissions.search(qr);
    if (((ps != null ? (ref12 = ps.hits) != null ? ref12.hits : void 0 : void 0) != null) && ps.hits.hits.length) {
      ref13 = ps.hits.hits;
      for (q = 0, len5 = ref13.length; q < len5; q++) {
        p = ref13[q];
        rp = _prep(p._source);
        rp.score = _score(rp);
        perms.all_permissions.push(rp);
      }
    }
  }
  if (perms.all_permissions.length === 0 && meta.publisher && !meta.doi && !issns.length) {
    af = academic_journal.find('publisher:"' + meta.publisher + '"');
    if (af == null) {
      fz = academic_journal.find('publisher:"' + meta.publisher.split(' ').join(' AND publisher:"') + '"');
      if (fz.publisher === meta.publisher) {
        af = fz;
      } else {
        lvs = this.tdm.levenshtein(fz.publisher, meta.publisher, true);
        longest = lvs.length.a > lvs.length.b ? lvs.length.a : lvs.length.b;
        if (lvs.distance < 5 || longest / lvs.distance > 10) {
          af = fz;
        }
      }
    }
    if (typeof af === 'object' && af.is_oa) {
      pisoa = academic_journal.count('publisher:"' + af.publisher + '"') === academic_journal.count('publisher:"' + af.publisher + '" AND is_oa:true');
    }
    if (!af.is_oa || !pisoa) {
      af = false;
    }
  }
  if (typeof af === 'object' && af.is_oa !== false) {
    if ((af.is_oa == null) && (indexOf.call(af.src, 'doaj') >= 0 || af.wikidata_in_doaj)) {
      af.is_oa = true;
    }
    if (af.is_oa) {
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
        altoa.licence = af.license[0].type; // could have doaj licence info
      } catch (error) {}
      if (altoa.licence == null) {
        altoa.licence = af.licence; // wikidata licence
      }
      if (indexOf.call(af.src, 'doaj') >= 0 || af.wikidata_in_doaj) {
        altoa.embargo_months = 0;
        altoa.provenance = {
          oa_evidence: 'In DOAJ'
        };
      }
      if (typeof altoa.licence === 'string') {
        altoa.licence = altoa.licence.toLowerCase().trim();
        if (altoa.licence.indexOf('cc') === 0) {
          altoa.licence = altoa.licence.replace(/ /g, '-');
        } else if (altoa.licence.indexOf('creative') !== -1) {
          altoa.licence = altoa.licence.indexOf('0') !== -1 || altoa.licence.indexOf('zero') !== -1 ? 'cc0' : altoa.licence.indexOf('share') !== -1 ? 'ccbysa' : altoa.licence.indexOf('derivative') !== -1 ? 'ccbynd' : 'ccby';
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
      altoa.score = _score(altoa);
      perms.all_permissions.push(altoa);
    }
  }
  if (haddoi && meta.doi && (oadoi = (await this.src.oadoi(meta.doi)))) {
    // use oadoi for specific doi
    if ((oadoi != null ? (ref14 = oadoi.best_oa_location) != null ? ref14.license : void 0 : void 0) && oadoi.best_oa_location.license.indexOf('cc') !== -1) {
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
        doa.versions = (ref15 = doa.version) === 'submittedVersion' || ref15 === 'preprint' ? ['submittedVersion'] : (ref16 = doa.version) === 'acceptedVersion' || ref16 === 'postprint' ? ['submittedVersion', 'acceptedVersion'] : ['submittedVersion', 'acceptedVersion', 'publishedVersion'];
      }
      doa.score = _score(doa);
      perms.all_permissions.push(doa);
    }
  }
  // sort rors by score, and sort alts by score, then combine
  if (perms.all_permissions.length) {
    perms.all_permissions.sort((a, b) => {
      if (a.score > b.score) {
        return 1;
      } else {
        return -1;
      }
    });
    ref17 = perms.all_permissions;
    // note if enforcement_from is after published date, don't apply the permission. If no date, the permission applies to everything
    for (r = 0, len6 = ref17.length; r < len6; r++) {
      wp = ref17[r];
      if (!((ref18 = wp.provenance) != null ? ref18.enforcement_from : void 0)) {
        perms.best_permission = this.copy(wp);
        break;
      } else if (!meta.published || moment(meta.published, 'YYYY-MM-DD').isAfter(moment(wp.provenance.enforcement_from, 'DD/MM/YYYY'))) {
        perms.best_permission = this.copy(wp);
        break;
      }
    }
    if (rors.length) {
      rors.sort((a, b) => {
        if (a.score > b.score) {
          return 1;
        } else {
          return -1;
        }
      });
      // check this gives the order in the direction we want, else reverse it
      for (t = 0, len7 = rors.length; t < len7; t++) {
        ro = rors[t];
        perms.all_permissions.push(ro);
        if (((ref19 = perms.best_permission) != null ? ref19.author_affiliation_requirement : void 0) == null) {
          if (perms.best_permission != null) {
            if (!((ref20 = ro.provenance) != null ? ref20.enforcement_from : void 0) || !meta.published || moment(meta.published, 'YYYY-MM-DD').isAfter(moment(ro.provenance.enforcement_from, 'DD/MM/YYYY'))) {
              pb = this.copy(perms.best_permission);
              ref21 = ['licences', 'versions', 'locations'];
              for (u = 0, len8 = ref21.length; u < len8; u++) {
                key = ref21[u];
                ref22 = ro[key];
                for (v = 0, len9 = ref22.length; v < len9; v++) {
                  vl = ref22[v];
                  if (pb[key] == null) {
                    pb[key] = [];
                  }
                  if (indexOf.call(pb[key], vl) < 0) {
                    pb[key].push(vl);
                  }
                }
              }
              ref24 = (ref23 = pb.licences) != null ? ref23 : [];
              for (w = 0, len10 = ref24.length; w < len10; w++) {
                l = ref24[w];
                if ((pb.licence == null) || l.type.length < pb.licence.length) {
                  pb.licence = l.type;
                }
              }
              pb.version = indexOf.call(pb.versions, 'publishedVersion') >= 0 || indexOf.call(pb.versions, 'publisher pdf') >= 0 ? 'publishedVersion' : indexOf.call(pb.versions, 'acceptedVersion') >= 0 || indexOf.call(pb.versions, 'postprint') >= 0 ? 'acceptedVersion' : 'submittedVersion';
              if (pb.embargo_end) {
                if (ro.embargo_end) {
                  if (moment(ro.embargo_end, "YYYY-MM-DD").isBefore(moment(pb.embargo_end, "YYYY-MM-DD"))) {
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
      body: typeof overall_policy_restriction !== 'string' ? overall_policy_restriction : (ref25 = msgs[overall_policy_restriction.toLowerCase()]) != null ? ref25 : overall_policy_restriction,
      status: 501
    };
  } else {
    return perms;
  }
};

// https://docs.google.com/spreadsheets/d/1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A/edit
P.svc.oaworks.permission = function(recs = []) {
  var af, an, cids, dt, i, inaj, j, k, keys, kn, l, lc, len, len1, len2, len3, len4, len5, m, n, name, nd, nid, nk, nps, nr, nv, o, q, rcs, ready, rec, ref, ref1, ref2, ref3, ref4, ref5, ref6, ref7, s, st;
  keys = {
    versionsarchivable: 'versions',
    permissionsrequestcontactemail: 'permissions_contact',
    archivinglocationsallowed: 'locations',
    license: 'licence',
    licencesallowed: 'licences',
    'post-printembargo': 'embargo_months',
    depositstatementrequired: 'deposit_statement',
    copyrightowner: 'copyright_owner', // can be journal, publisher, affiliation or author
    publicnotes: 'notes',
    authoraffiliationrolerequirement: 'requirements.role',
    authoraffiliationrequirement: 'requirements.affiliation',
    authoraffiliationdepartmentrequirement: 'requirements.departmental_affiliation',
    iffundedby: 'requirements.funder',
    fundingproportionrequired: 'requirements.funding_proportion',
    subjectcoverage: 'requirements.subject',
    has_policy: 'issuer.has_policy',
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
      if (rec.recordlastupdated.indexOf(',') !== -1) {
        nd = false;
        ref = rec.recordlastupdated.split(',');
        for (j = 0, len1 = ref.length; j < len1; j++) {
          dt = ref[j];
          if (nd === false || moment(dt.trim(), 'DD/MM/YYYY').isAfter(moment(nd, 'DD/MM/YYYY'))) {
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
      nr.meta.updatedAt = moment(nr.meta.updated, 'DD/MM/YYYY').valueOf();
    }
    // the google feed import will lowercase these key names and remove whitespace, question marks, brackets too, but not dashes
    nr.issuer.id = rec.id.indexOf(',') !== -1 ? rec.id.split(',') : rec.id;
    if (typeof nr.issuer.id !== 'string') {
      cids = [];
      inaj = false;
      ref1 = nr.issuer.id;
      for (m = 0, len2 = ref1.length; m < len2; m++) {
        nid = ref1[m];
        nid = nid.trim();
        if (nr.issuer.type === 'journal' && nid.indexOf('-') !== -1 && nid.indexOf(' ') === -1) {
          nid = nid.toUpperCase();
          if (af = academic_journal.find('issn.exact:"' + nid + '"')) {
            inaj = true;
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
    }
    nr.permission_required = (rec.has_policy != null) && rec.has_policy.toLowerCase().indexOf('permission required') !== -1;
    for (k in rec) {
      if (keys[k] && (rec[k] != null) && rec[k].length !== 0) {
        nk = keys[k];
        nv = void 0;
        if (k === 'post-printembargo') { // Post-Print Embargo - empty or number of months like 0, 12, 24
          try {
            kn = parseInt(rec[k].trim());
            if (typeof kn === 'number' && !isNaN(kn && kn !== 0)) {
              nv = kn;
            }
            if (nv != null) {
              nr.embargo_end = ''; // just to allow neat output later - can't be calculated until compared to a particular article
            }
          } catch (error) {}
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
          if (nk.indexOf('.') !== -1) {
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
    // Archived Full Text Link - a URL to a web archive link of the full text policy link (ever multiple?)
    // Record First Added - date like 12/07/2017
    // Post-publication Pre-print Update Allowed - string like No, Yes, could be empty (turn these to booleans?)
    // Can Authors Opt Out - seems to be all empty, could presumably be Yes or No
    if (nr.licences == null) {
      nr.licences = [];
    }
    if (!nr.licence) {
      ref5 = nr.licences;
      for (q = 0, len5 = ref5.length; q < len5; q++) {
        l = ref5[q];
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
  // TODO if there is a provenance.example DOI look up the metadata for it and find the journal ISSN. 
  // then have a search for ISSN be able to find that. Otherwise, we have coverage by publisher that 
  // contains no journal info, so no way to go from ISSN to the stored record
  if (ready.length) {
    oab_permissions.remove('*');
    oab_permissions.insert(ready);
  }
  return ready.length;
};

P.svc.oaworks.permission._sheet = '1qBb0RV1XgO3xOQMdHJBAf3HCJlUgsXqDVauWAtxde4A';

'API.add \'service/oab/request/:rid\',\n  post:\n    roleRequired:\'openaccessbutton.user\',\n    action: () ->\n      if r = oab_request.get this.urlParams.rid\n        n = {}\n        if not r.user? and not r.story? and this.request.body.story\n          n.story = this.request.body.story\n          n.user = id: this.user._id, email: this.user.emails[0].address, username: (this.user.profile?.firstname ? this.user.username ? this.user.emails[0].address)\n          n.user.firstname = this.user.profile?.firstname\n          n.user.lastname = this.user.profile?.lastname\n          n.user.affiliation = this.user.service?.openaccessbutton?.profile?.affiliation\n          n.user.profession = this.user.service?.openaccessbutton?.profile?.profession\n          n.count = 1 if not r.count? or r.count is 0\n        if API.accounts.auth \'openaccessbutton.admin\', this.user\n          n.test ?= this.request.body.test if this.request.body.test? and this.request.body.test isnt r.test\n          n.status ?= this.request.body.status if this.request.body.status? and this.request.body.status isnt r.status\n          n.rating ?= this.request.body.rating if this.request.body.rating? and this.request.body.rating isnt r.rating\n          n.name ?= this.request.body.name if this.request.body.name? and this.request.body.name isnt r.name\n          n.email ?= this.request.body.email if this.request.body.email? and this.request.body.email isnt r.email\n          n.author_affiliation ?= this.request.body.author_affiliation if this.request.body.author_affiliation? and this.request.body.author_affiliation isnt r.author_affiliation\n          n.story ?= this.request.body.story if this.request.body.story? and this.request.body.story isnt r.story\n          n.journal ?= this.request.body.journal if this.request.body.journal? and this.request.body.journal isnt r.journal\n          n.notes = this.request.body.notes if this.request.body.notes? and this.request.body.notes isnt r.notes\n          n.access_right = this.request.body.access_right if this.request.body.access_right? and this.request.body.access_right isnt r.access_right\n          n.embargo_date = this.request.body.embargo_date if this.request.body.embargo_date? and this.request.body.embargo_date isnt r.embargo_date\n          n.access_conditions = this.request.body.access_conditions if this.request.body.access_conditions? and this.request.body.access_conditions isnt r.access_conditions\n          n.license = this.request.body.license if this.request.body.license? and this.request.body.license isnt r.license\n          if this.request.body.received?.description? and (not r.received? or this.request.body.received.description isnt r.received.description)\n            n.received = if r.received? then r.received else {}\n            n.received.description = this.request.body.received.description\n        n.email = this.request.body.email if this.request.body.email? and ( API.accounts.auth(\'openaccessbutton.admin\',this.user) || not r.status? || r.status is \'help\' || r.status is \'moderate\' || r.status is \'refused\' )\n        n.story = this.request.body.story if r.user? and this.userId is r.user.id and this.request.body.story? and this.request.body.story isnt r.story\n        n.url ?= this.request.body.url if this.request.body.url? and this.request.body.url isnt r.url\n        n.title ?= this.request.body.title if this.request.body.title? and this.request.body.title isnt r.title\n        n.doi ?= this.request.body.doi if this.request.body.doi? and this.request.body.doi isnt r.doi\n        if n.story\n          res = oab_request.search \'rating:1 AND story.exact:"\' + n.story + \'"\'\n          if res.hits.total\n            nres = oab_request.search \'rating:0 AND story.exact:"\' + n.story + \'"\'\n            n.rating = 1 if nres.hits.total is 0\n        if not n.status?\n          if (not r.title and not n.title) || (not r.email and not n.email) || (not r.story and not n.story)\n            n.status = \'help\' if r.status isnt \'help\'\n          else if r.status is \'help\' and ( (r.title or n.title) and (r.email or n.email) and (r.story or n.story) )\n            n.status = \'moderate\'\n        if n.title? and typeof n.title is \'string\'\n          try n.title = n.title.charAt(0).toUpperCase() + n.title.slice(1)\n        if n.journal? and typeof n.journal is \'string\'\n          try n.journal = n.journal.charAt(0).toUpperCase() + n.journal.slice(1)\n        if not n.doi? and not r.doi? and r.url? and r.url.indexOf(\'10.\') isnt -1 and r.url.split(\'10.\')[1].indexOf(\'/\') isnt -1\n          n.doi = \'10.\' + r.url.split(\'10.\')[1]\n          r.doi = n.doi\n        if (r.doi or r.url) and not r.title and not n.title\n          try\n            cr = if r.doi then API.service.oab.metadata(undefined, {doi: r.doi}) else API.service.oab.metadata {url: r.url}\n            for c of cr\n              n[c] ?= cr[c] if not r[c]?\n        r.author_affiliation = n.author_affiliation if n.author_affiliation?\n        if n.crossref_type? and n.crossref_type isnt \'journal-article\'\n          n.status = \'closed\'\n          n.closed_on_update = true\n          n.closed_on_update_reason = \'notarticle\'\n        if (not r.email and not n.email) and r.author and r.author.length and (r.author[0].affiliation? or r.author_affiliation)\n          try\n            email = API.use.hunter.email {company: (r.author_affiliation ? r.author[0].affiliation[0].name), first_name: r.author[0].family, last_name: r.author[0].given}, API.settings.service.openaccessbutton.hunter.api_key\n            if email?.email?\n              n.email = email.email\n        oab_request.update(r._id,n) if JSON.stringify(n) isnt \'{}\'\n        if (r.user?.email? or n.user?.email?) and (not r.user or (not r.story? and n.story))\n          try\n            tmpl = API.mail.template \'initiator_confirmation.html\'\n            sub = API.service.oab.substitute tmpl.content, {_id: r._id, url: (r.url ? n.url), title:(r.title ? n.title ? r.url) }\n            API.mail.send\n              service: \'openaccessbutton\',\n              from: sub.from ? API.settings.service.openaccessbutton.mail.from\n              to: n.user?.email ? r.user.email\n              subject: sub.subject ? \'New request created \' + r._id\n              html: sub.content\n        return oab_request.get r._id\n      else\n        return 404\n  delete:\n    roleRequired:\'openaccessbutton.user\'\n    action: () ->\n      r = oab_request.get this.urlParams.rid\n      oab_request.remove(this.urlParams.rid) if API.accounts.auth(\'openaccessbutton.admin\',this.user) or this.userId is r.user.id\n      return {}';
/*
to create a request the url and type are required, What about story?
{
  url: "url of item request is about",
  story: "the story of why this request / support, if supplied",
  email: "email address of person to contact to request",
  count: "the count of how many people support this request",
  createdAt: "date request was created",
  status: "help OR moderate OR progress OR hold OR refused OR received OR closed",
  receiver: "unique ID that the receive endpoint will use to accept one-time submission of content",
  title: "article title",
  doi: "article doi",
  user: {
    id: "user ID of user who created request",
    username: "username of user who created request",
    email: "email of user who created request"
  }
}
*/
'P.svc.oaworks.request = (req, uacc, fast, notify=true) ->\n  dom\n  if req.dom\n    dom = req.dom\n    delete req.dom\n  return false if JSON.stringify(req).indexOf(\'<script\') isnt -1\n  req = @tdm.clean req\n  req.type ?= \'article\'\n  req.url = req.url[0] if _.isArray req.url\n  req.doi = req.url if not req.doi? and req.url? and req.url.indexOf(\'10.\') isnt -1 and req.url.split(\'10.\')[1].indexOf(\'/\') isnt -1\n  req.doi = \'10.\' + req.doi.split(\'10.\')[1].split(\'?\')[0].split(\'#\')[0] if req.doi? and req.doi.indexOf(\'10.\') isnt 0\n  req.doi = decodeURIComponent(req.doi) if req.doi\n  if req.url? and req.url.indexOf(\'eu.alma.exlibrisgroup.com\') isnt -1\n    req.url += (if req.url.indexOf(\'?\') is -1 then \'?\' else \'&\') + \'oabLibris=\' + Random.id()\n    if req.title? and typeof req.title is \'string\' and req.title.length > 0 and texist = oab_request.find {title:req.title,type:req.type}\n      texist.cache = true\n      return texist\n  else if req.doi or req.title or req.url\n    eq = {type: req.type}\n    if req.doi\n      eq.doi = req.doi\n    else if req.title\n      eq.title = req.title\n    else\n      eq.url = req.url\n    if exists = oab_request.find eq\n      exists.cache = true\n      return exists\n  return false if not req.test and @svc.oaworks.blacklist req.url\n\n  rid = if req._id and oab_request.get(req._id) then req._id else oab_request.insert {url:req.url,type:req.type,_id:req._id}\n  user = if uacc then (if typeof uacc is \'string\' then API.accounts.retrieve(uacc) else uacc) else undefined\n  send_confirmation = false\n  if not req.user? and user and req.story\n    send_confirmation = true\n    un = user.profile?.firstname ? user.username ? user.emails[0].address\n    req.user =\n      id: user._id\n      username: un\n      email: user.emails[0].address\n      firstname: user.profile?.firstname\n      lastname: user.profile?.lastname\n      affiliation: user.service?.openaccessbutton?.profile?.affiliation\n      profession: user.service?.openaccessbutton?.profile?.profession\n  req.count ?= if req.story then 1 else 0\n\n  if not req.doi or not req.title or not req.email\n    try\n      cr = @svc.oaworks.metadata {url: req.url}, {doi: req.doi}\n      for c of cr\n        if c is \'email\'\n          for e in cr.email\n            isauthor = false\n            if cr?.author?\n              for a in cr.author\n                isauthor = a.family and e.toLowerCase().indexOf(a.family.toLowerCase()) isnt -1\n            if isauthor and @mail.validate(e, @S.svc.oaworks.mail?.pubkey).is_valid\n              req.email = e\n              break\n        else\n          req[c] ?= cr[c]\n  if _.isArray(req.author) and not req.author_affiliation\n    for author in req.author\n      try\n        if req.email.toLowerCase().indexOf(author.family) isnt -1\n          req.author_affiliation = author.affiliation[0].name\n          break\n  req.keywords ?= []\n  req.title ?= \'\'\n  req.doi ?= \'\'\n  req.author = []\n  req.journal = \'\'\n  req.issn = \'\'\n  req.publisher = \'\'\n  if not req.email and req.author_affiliation\n    try\n      for author in req.author\n        if author.affiliation[0].name is req.author_affiliation\n          # it would be possible to lookup ORCID here if the author has one in the crossref data, but that would only get us an email for people who make it public\n          # previous analysis showed that this is rare. So not doing it yet\n          email = @src.hunter.email {company: req.author_affiliation, first_name: author.family, last_name: author.given}, @S.svc.oaworks.hunter.api_key\n          if email?.email?\n            req.email = email.email\n            break\n\n  if req.story\n    res = oab_request.search \'rating:1 AND story.exact:"\' + req.story + \'"\'\n    if res.hits.total\n      nres = oab_request.search \'rating:0 AND story.exact:"\' + req.story + \'"\'\n      req.rating = 1 if nres.hits.total is 0\n\n  req.status ?= if not req.story or not req.title or not req.email or not req.user? then "help" else "moderate"\n  if req.year\n    try\n      req.year = parseInt(req.year) if typeof req.year is \'string\'\n      if req.year < 2000\n        req.status = \'closed\'\n        req.closed_on_create = true\n        req.closed_on_create_reason = \'pre2000\'\n    try\n      if fast and (new Date()).getFullYear() - req.year > 5 # only doing these on fast means only doing them via UI for now\n        req.status = \'closed\'\n        req.closed_on_create = true\n        req.closed_on_create_reason = \'gt5\'\n  if fast and not req.doi? and req.status isnt \'closed\'\n    req.status = \'closed\'\n    req.closed_on_create = true\n    req.closed_on_create_reason = \'nodoi\'\n  if fast and req.crossref_type? and req.crossref_type isnt \'journal-article\' and req.status isnt \'closed\'\n    req.status = \'closed\'\n    req.closed_on_create = true\n    req.closed_on_create_reason = \'notarticle\'\n\n  req.receiver = @uid()\n  req._id = rid\n  if req.title? and typeof req.title is \'string\'\n    try req.title = req.title.charAt(0).toUpperCase() + req.title.slice(1)\n  if req.journal? and typeof req.journal is \'string\'\n    try req.journal = req.journal.charAt(0).toUpperCase() + req.journal.slice(1)\n  oab_request.update rid, req\n  if (fast and req.user?.email?) or send_confirmation\n    try\n      tmpl = API.mail.template \'initiator_confirmation.html\'\n      sub = API.service.oab.substitute tmpl.content, {_id: req._id, url: req.url, title:(req.title ? req.url) }\n      @mail\n        service: \'openaccessbutton\',\n        from: sub.from ? @S.svc.oaworks.mail.from\n        to: req.user.email\n        subject: sub.subject ? \'New request created \' + req._id\n        html: sub.content\n  if req.story # and notify\n    # for now still send if not notify, but remove Natalia (Joe requested it this way, so he still gets them on bulk creates, but Natalia does not)\n    addrs = @S.svc.oaworks.notify.request\n    if not notify and typeof addrs isnt \'string\' and \'natalia.norori@openaccessbutton.org\' in addrs\n      addrs.splice(addrs.indexOf(\'natalia.norori@openaccessbutton.org\'),1)\n    @mail\n      service: \'openaccessbutton\'\n      from: \'natalia.norori@openaccessbutton.org\'\n      to: addrs\n      subject: \'New request created \' + req._id\n      text: (if @S.dev then \'https://dev.openaccessbutton.org/request/\' else \'https://openaccessbutton.org/request/\') + req._id\n  return req';


// https://jcheminf.springeropen.com/articles/10.1186/1758-2946-3-47
P.svc.oaworks.scrape = async function(content, doi) {
  var cl, cnts, d, i, j, k, kk, l, len, len1, len2, len3, len4, m, me, meta, mk, mkp, mls, mm, mr, mstr, my, n, o, p, q, ref, ref1, ref2, str, ud;
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
    //if content.indexOf('.pdf') isnt -1
    //  try content = await @convert.pdf2txt url
    //try content ?= await @puppet url
    if (content == null) {
      content = (await this.fetch(url));
    }
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
    ref = content.split(' ');
    for (j = 0, len = ref.length; j < len; j++) {
      str = ref[j];
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
      d = this.tdm.extract({
        content: content,
        matchers: ['/doi[^>;]*?(?:=|:)[^>;]*?(10[.].*?\/.*?)("|\')/gi', '/doi[.]org/(10[.].*?/.*?)("| \')/gi']
      });
      ref1 = d.matches;
      for (l = 0, len1 = ref1.length; l < len1; l++) {
        n = ref1[l];
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
      k = this.tdm.extract({
        content: content,
        matchers: ['/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')citation_date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi', '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')dc.date(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi', '/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')prism.publicationDate(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi'],
        start: '<head',
        end: '</head'
      });
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
      k = this.tdm.extract({
        content: content,
        matchers: ['/meta[^>;"\']*?name[^>;"\']*?= *?(?:"|\')keywords(?:"|\')[^>;"\']*?content[^>;"\']*?= *?(?:"|\')(.*?)(?:"|\')/gi'],
        start: '<head',
        end: '</head'
      });
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
      m = this.tdm.extract({
        content: content,
        matchers: ['/mailto:([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)/gi', '/(?: |>|"|\')([^ \'">{}/]*?@[^ \'"{}<>]*?[.][a-z.]{2,}?)(?: |<|"|\')/gi']
      });
      ref2 = m.matches;
      for (p = 0, len3 = ref2.length; p < len3; p++) {
        i = ref2[p];
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
    meta.email = [];
    for (q = 0, len4 = mls.length; q < len4; q++) {
      me = mls[q];
      if (mstr.indexOf(me) === -1) {
        meta.email.push(me);
      }
      mstr += me;
    }
  }
  return meta;
};


S.built = "Mon Mar 08 2021 05:10:31 GMT+0000";