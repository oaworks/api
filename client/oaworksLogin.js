var _OALogin;

_OALogin = function(n) {
  var d;
  if (n.startsWith('#')) {
    d = document.getElementById(n);
  } else {
    d = document.getElementsByClassName(n.replace(/^\./, '').replace(/\s\./g, ' ').trim());
    if ((d != null) && d.length === 1) {
      d = d[0];
    }
  }
  if ((d != null) && (n.startsWith('#') || d.length !== 0)) {
    return d;
  } else {
    return void 0;
  }
};

_OALogin.each = function(els, k) {
  var el, i, len, ref, results;
  if (typeof els === 'string') {
    els = _OALogin(els);
  }
  if ((els != null) && !Array.isArray(els) && !HTMLCollection.prototype.isPrototypeOf(els) && !NodeList.prototype.isPrototypeOf(els)) {
    els = [els];
  }
  ref = els != null ? els : [];
  results = [];
  for (i = 0, len = ref.length; i < len; i++) {
    el = ref[i];
    results.push(k(el));
  }
  return results;
};

_OALogin.show = function(els, h, a) {
  return _OALogin.each(els, function(el) {
    var w;
    if (h) {
      el.innerHTML = (a ? el.innerHTML : '') + h + (a === false ? el.innerHTML : '');
    }
    w = el.getAttribute('OALoginDisplay');
    if (typeof w !== 'string' || w === 'none') { // TODO should be inline in which cases...
      w = 'block';
    }
    return el.style.display = w;
  });
};

_OALogin.hide = function(els) {
  return _OALogin.each(els, function(el) {
    if (el.style.display !== 'none') {
      el.setAttribute('OALoginDisplay', el.style.display);
    }
    return el.style.display = 'none';
  });
};

_OALogin.ajax = function(url, opts) {
  var base, base1, h, loaded, ref, ref1, ref2, xhr;
  if (typeof url === 'object') {
    opts = url;
    url = void 0;
  }
  if (url == null) {
    url = (ref = opts.url) != null ? ref : '';
  }
  if (url === '' || (url.startsWith('/') && !url.startsWith('//'))) {
    url = '//' + window.location.host + url;
  }
  if (opts == null) {
    opts = {};
  }
  if (opts.headers == null) {
    opts.headers = {};
  }
  if (typeof opts.method === 'string') {
    opts.method = opts.method.toUpperCase();
  }
  if (opts.data != null) {
    opts.method = 'POST';
    if (typeof opts.data === 'object' && typeof opts.data.append !== 'function') { // a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify(opts.data);
      if ((base = opts.headers)['Content-type'] == null) {
        base['Content-type'] = 'application/json';
      }
    }
  }
  try {
    //url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching?
    if (!opts.headers.Authorization && !opts.headers.authorization && !opts.headers.apikey && !opts.headers['x-apikey']) {
      if (opts.username && opts.password) {
        if ((base1 = opts.headers).Authorization == null) {
          base1.Authorization = "Basic " + btoa(opts.username + ":" + opts.password);
        }
      } else if (opts.apikey || opts['x-apikey']) {
        opts.headers.apikey = (ref1 = opts.apikey) != null ? ref1 : opts['x-apikey'];
      }
    }
  } catch (error) {}
  xhr = new XMLHttpRequest();
  xhr.open((ref2 = opts.method) != null ? ref2 : 'GET', url);
  for (h in opts.headers) {
    xhr.setRequestHeader(h, opts.headers[h]);
  }
  loaded = false;
  xhr.onload = function() {
    var err, x;
    loaded = true;
    try {
      if (xhr.status > 199 && xhr.status < 400) {
        x = xhr.response;
        try {
          x = JSON.parse(x);
        } catch (error) {}
        try {
          return opts.success(x, xhr);
        } catch (error) {}
      } else {
        try {
          return opts.error(xhr);
        } catch (error) {}
      }
    } catch (error) {
      err = error;
      try {
        console.log(err);
      } catch (error) {}
      try {
        return opts.error(xhr);
      } catch (error) {}
    }
  };
  xhr.onerror = function(err) {
    try {
      return opts.error(err, xhr);
    } catch (error) {}
  };
  xhr.onloadend = function() {
    var ref3;
    try {
      if (((ref3 = xhr.status) === 404) && !loaded) {
        return opts.error(xhr);
      }
    } catch (error) {}
  };
  try {
    return xhr.send(opts.data);
  } catch (error) {}
};

_OALogin.cookie = function(n, vs, opts) {
  var c, d, domained, dt, i, len, ref, ref1, t;
  if (n === '' || n === false || typeof n === 'object') {
    vs = n;
    n = void 0;
  }
  if (n == null) {
    n = 'pradm';
  }
  if (vs != null) {
    if (opts == null) {
      opts = {};
    }
    if (opts.domain) {
      domained = true;
    } else {
      domained = false;
      opts.domain = '.' + window.location.host;
      if (opts.domain.startsWith('.bg.')) {
        opts.domain = opts.domain.replace('.bg.', '.');
      }
    }
    t = n + '=';
    if (vs) {
      t += encodeURIComponent(JSON.stringify(vs)); // so if values is false or '' this will effectively remove the cookie
    } else {
      opts.expires = -1;
    }
    d = (ref = opts.expires) != null ? ref : 180;
    if (typeof d === 'number') {
      d = new Date();
      d.setDate(d.getDate() + opts.expires);
    }
    if (d instanceof Date) {
      t += '; expires=' + new Date(d).toUTCString();
    }
    if (typeof opts.domain === 'string' && opts.domain !== '') {
      t += '; domain=' + opts.domain;
    }
    t += '; path=' + (typeof opts.path === 'string' && opts.path !== '' ? opts.path : '/');
    if (opts.secure !== false) { // default to secure
      t += '; secure';
    }
    if (opts.httponly) {
      t += '; HttpOnly';
    }
    document.cookie = t;
    if (opts.expires === -1 && opts.domain && !domained) {
      dt = t.split('; domain=')[0];
      document.cookie = dt;
    }
    return t;
  } else {
    ref1 = document.cookie.split(';');
    for (i = 0, len = ref1.length; i < len; i++) {
      c = ref1[i];
      while (c.charAt(0) === ' ') {
        c = c.substring(1);
      }
      if (c.indexOf(n + '=') !== -1) {
        return JSON.parse(decodeURIComponent(c.substring(n.length + 1, c.length)));
      }
    }
    return false; // even if values is false or '', so can remove this way
  }
};

_OALogin.account = void 0; // set to the account object once retrieved

_OALogin.token = function(e) {
  var email, opts;
  try {
    e.preventDefault();
  } catch (error) {}
  _OALogin.cookie(false);
  // TODO add a validation of the email val if email not already set?
  if (!(email = document.getElementById('#OALoginEmail').value)) {
    document.getElementById('#OALoginEmail').focus();
    return;
  }
  _OALogin.hide('.OALoginEmail');
  _OALogin.show('.OALoading');
  _OALogin.show('.OALoginToken');
  opts = {
    success: function(data) {
      _OALogin.hide('.OALoading');
      document.getElementById('#OALoginToken').focus();
      return _OALogin._loggingin = setInterval(function() {
        if (_OALogin.loggedin()) {
          return _OALogin.loginSuccess();
        }
      }, 2000);
    },
    data: {
      email: email,
      url: window.location.protocol + '//' + window.location.host + window.location.pathname
    }
  };
  return _OALogin.ajax('/auth/token', opts);
};

_OALogin.loginSuccess = function(data) {
  if (_OALogin._loggingin) {
    clearInterval(_OALogin._loggingin);
    delete _OALogin._loggingin;
  }
  _OALogin.hide('.OALogin');
  _OALogin.hide('.OALoading');
  _OALogin.hide('.OALoginToken');
  if (typeof data === 'object') {
    _OALogin.account = data;
    _OALogin.cookie(data);
  }
  if (!_OALogin.loginNext && window.location.search.indexOf('next=') !== -1) {
    _OALogin.loginNext = decodeURIComponent(window.location.search.split('next=')[1].split('&')[0]);
  } else if (!_OALogin.loginNext && window.location.search.startsWith('?next')) {
    _OALogin.loginNext = true;
  }
  if (_OALogin.loginNext) {
    if (_OALogin.loginNext === true) {
      return location.reload();
    } else {
      return window.location = _OALogin.loginNext;
    }
  } else {
    try {
      _OALogin.show('.OALoginLogout');
      document.getElementById('#OALoginLogout').addEventListener('click', _OALogin.logout);
    } catch (error) {}
    try {
      if (typeof _OALogin.afterLogin === 'function') {
        return _OALogin.afterLogin();
      }
    } catch (error) {}
  }
};

_OALogin.loginError = function(err, xhr) {
  console.log('Login error');
  console.log(err); // and log an error to backend somewhere...
  console.log(xhr);
  if (_OALogin._loggingin) {
    clearInterval(_OALogin._loggingin);
    delete _OALogin._loggingin;
  }
  _OALogin.cookie(false);
  _OALogin.account = void 0;
  _OALogin.hide('.OALoading');
  _OALogin.hide('.OALoginToken');
  document.getElementById('#OALoginEmail').value = '';
  document.getElementById('#OALoginEmail').setAttribute('placeholder', 'error, enter your email to try again');
  _OALogin.show('.OALoginEmail');
  return _OALogin.show('.OALogin');
};

_OALogin.login = function(e) {
  var account, opts, pt;
  try {
    e.preventDefault();
  } catch (error) {}
  opts = {
    success: _OALogin.loginSuccess,
    error: _OALogin.loginError,
    data: {}
  };
  pt = document.getElementById('#OALoginToken').value;
  if (window.location.hash.replace('#', '').length === 8) {
    opts.data.token = window.location.hash.replace('#', '');
    try {
      window.history.pushState("", "", window.location.pathname);
    } catch (error) {}
  } else if (typeof pt === 'string' && pt.length === 8) {
    opts.data.token = pt;
  } else if (account = _OALogin.loggedin()) {
    opts.data.email = account.email;
    opts.data.resume = account.resume;
  }
  if ((opts.data.email && opts.data.resume) || opts.data.hash || opts.data.token) {
    _OALogin.hide('.OALoginEmail');
    _OALogin.hide('.OALoginToken');
    _OALogin.show('.OALoading');
    return _OALogin.ajax('/auth', opts);
  }
};

_OALogin.loggedin = function() {
  var p;
  if (p = _OALogin.cookie()) {
    if (typeof p === 'object' && JSON.stringify(p) !== '{}') {
      _OALogin.account = p;
    }
  }
  return _OALogin.account;
};

_OALogin.logout = function(e) {
  var account;
  try {
    e.preventDefault();
  } catch (error) {}
  _OALogin.show('.OALoading');
  if (account = _OALogin.loggedin()) {
    return _OALogin.ajax('/auth/logout?apikey=' + account.apikey, {
      success: function() {
        _OALogin.account = void 0;
        _OALogin.cookie(false);
        _OALogin.hide('.OALoading'); // just in case anything made this visible
        if (_OALogin.loginNext === true) {
          return location.reload();
        } else if (_OALogin.loginNext) {
          return window.location = _OALogin.loginNext;
        } else if (typeof _OALogin.afterLogout === 'function') {
          try {
            return _OALogin.afterLogout();
          } catch (error) {}
        }
      }
    });
  }
};

document.addEventListener('DOMContentLoaded', function() {
  var loggedin;
  try {
    document.getElementById('#OALoginEmail').addEventListener('keyup', function(e) {
      if (e.keyCode === 13) {
        return _OALogin.token(e);
      }
    });
  } catch (error) {}
  try {
    document.getElementById('#OALoginToken').addEventListener('keyup', function(e) {
      if (document.getElementById('#OALoginToken').value.length === 8) {
        return _OALogin.login();
      }
    });
  } catch (error) {}
  loggedin = _OALogin.loggedin();
  if (loggedin || (typeof window.location.hash === 'string' && window.location.hash && window.location.hash.replace('#', '').length === 8)) {
    if (loggedin) { // don't go to next if already logged in
      _OALogin.loginNext = void 0;
    }
    return _OALogin.login(); // will it be worth doing this on every page load, or only those with a login token hash?
  }
});
