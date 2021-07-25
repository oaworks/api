  // n should be element ID or class name or tag name.
  // Prefix IDs with # and class names with .
  // Scope them to within a specific element by providing that element ID first 
  // (preceded with #), then a space, then the element(s) class name / tag name
  // (ID requests can't be scoped this way because IDs have to be unique within a page anyway)
  // or an element to scope on can be directly provided as third param
var P, ref,
  indexOf = [].indexOf;

P = function(n, fn, sc) {
  var d;
  if (typeof fn === 'function') {
    return P.each(n, fn);
  } else if (n) {
    if (sc == null) {
      [sc, n] = n.split(' ');
    }
    if (n == null) {
      n = sc;
      sc = document;
    }
    d = P[n.startsWith('#') ? 'gebi' : n.startsWith('.') ? 'gebc' : 'gebn'](n, sc);
    if ((d != null) && (n.startsWith('#') || d.length !== 0)) {
      return d;
    } else {
      return void 0;
    }
  }
};

if (P.api == null) {
  P.api = (ref = this.api) != null ? ref : '//' + window.location.host;
}

P.gebi = function(id) {
  return document.getElementById(id.split('#').pop().split(' ')[0]);
};

P.gebc = function(n, sc) {
  var d;
  if (typeof sc === 'string' || n.includes(' ')) {
    sc = P.list(P(sc != null ? sc : n))[0];
  }
  d = (sc != null ? sc : document).getElementsByClassName(n.replace('.', ''));
  if ((d != null) && d.length === 1) {
    return d[0];
  } else {
    return d;
  }
};

P.gebn = function(n, sc) {
  var d;
  n = n.replace(/[<>]/g, '');
  if (n.includes(',')) {
    return P.gebns(n, sc);
  } else {
    if (typeof sc === 'string' || n.includes(' ')) {
      sc = P.list(P(sc != null ? sc : n))[0];
    }
    d = (sc != null ? sc : document).getElementsByTagName(n); // e.g. by the element name, like "div"
    if ((d == null) || d.length === 0) { // otherwise by the "name" attribute matching n
      d = (sc != null ? sc : document).getElementsByName(n);
    }
    if ((d != null) && d.length === 1) {
      return d[0];
    } else {
      return d;
    }
  }
};

P.gebns = function(ns, sc) { // ns could be like "h1, h2, h3, p"
  var d, j, len, len1, m, ref1, ref2, t, tag;
  d = [];
  if (typeof sc === 'string' || ns.includes(' ')) {
    sc = P.list(P(sc != null ? sc : ns))[0];
  }
  ref1 = ns.replace(/, /g, ',').split(',');
  for (j = 0, len = ref1.length; j < len; j++) {
    tag = ref1[j];
    ref2 = (sc != null ? sc : document).getElementsByTagName(tag);
    for (m = 0, len1 = ref2.length; m < len1; m++) {
      t = ref2[m];
      d.push(t);
    }
  }
  d.sort(function(a, b) {
    if (a.sourceIndex) {
      return a.sourceIndex - b.sourceIndex;
    } else {
      return 3 - (a.compareDocumentPosition(b) & 6);
    }
  });
  if (d.length === 1) {
    return d[0];
  } else {
    return d;
  }
};

P.list = function(els) {
  if (typeof els === 'string') {
    els = P(els);
  }
  if ((els != null) && !Array.isArray(els) && !HTMLCollection.prototype.isPrototypeOf(els) && !NodeList.prototype.isPrototypeOf(els)) {
    els = [els];
  }
  return els != null ? els : [];
};

P.each = function(els, k, v, sc) {
  var el, j, len, ref1, results;
  if (typeof els === 'string') {
    els = P(els, void 0, sc);
  }
  ref1 = P.list(els);
  results = [];
  for (j = 0, len = ref1.length; j < len; j++) {
    el = ref1[j];
    if (typeof k === 'function') {
      results.push(k(el));
    } else {
      if ((el != null) && (k != null)) {
        results.push(P.set(el, k, v));
      } else {
        results.push(void 0);
      }
    }
  }
  return results;
};

P.show = function(els, h, a) {
  return P.each(els, function(el) {
    var w;
    if (h) {
      el.innerHTML = (a ? el.innerHTML : '') + h + (a === false ? el.innerHTML : '');
    }
    w = P.get(el, 'Pdisplay');
    if (typeof w !== 'string' || w === 'none') { // TODO should be inline in which cases...
      w = 'block';
    }
    return el.style.display = w;
  });
};

P.hide = function(els) {
  return P.each(els, function(el) {
    if (el.style.display !== 'none') {
      P.set(el, 'Pdisplay', el.style.display);
    }
    return el.style.display = 'none';
  });
};

P.toggle = function(els) {
  return P.each(els, function(el) {
    return P[el.style.display === 'none' ? 'show' : 'hide'](el);
  });
};

P.focus = function(els) {
  return P.each(els, function(el) {
    return el.focus();
  });
};

P.blur = function(els) {
  return P.each(els, function(el) {
    return el.blur();
  });
};

P.get = function(els, a) {
  var r;
  r = void 0;
  P.each(els, function(el) {
    var ref1, ref2;
    if (r == null) {
      if (a != null) {
        try {
          return r = el.getAttribute(a);
        } catch (error) {}
      } else {
        if ((ref1 = el.getAttribute('type')) === 'radio' || ref1 === 'checkbox') {
          try {
            r = P.checked(el);
          } catch (error) {}
        }
        if ((r == null) && ((ref2 = el.getAttribute('type')) !== 'radio' && ref2 !== 'checkbox')) {
          try {
            r = el.value;
          } catch (error) {}
        }
        if (typeof r === 'string' && !r.length) {
          return r = void 0;
        }
      }
    }
  });
  return r;
};

P.val = P.get;

P.set = function(els, a, v) {
  return P.each(els, function(el) {
    if (v != null) {
      return el.setAttribute(a, v);
    } else if (a === true) {
      return P.check(el);
    } else if (a === false) {
      return P.uncheck(el);
    } else {
      return el.value = a;
    }
  });
};

P.attr = function(els, a, v) {
  return P[v != null ? 'set' : 'get'](els, a, v);
};

P.checked = function(els) {
  var r;
  r = void 0;
  P.each(els, function(el) {
    var ref1;
    if (r == null) {
      if (el instanceof HTMLInputElement) {
        if (el.getAttribute('type') === 'checkbox') {
          return r = el.checked;
        } else if (el.getAttribute('type') === 'radio') {
          return r = el.checked ? (ref1 = el.value) != null ? ref1 : true : false;
        }
      } else {
        return r = false;
      }
    }
  });
  return r;
};

P.check = function(els) {
  return P.each(els, function(el) {
    try {
      return el.checked = true; // will work for radio buttons as well
    } catch (error) {}
  });
};

P.uncheck = function(els) {
  return P.each(els, function(el) {
    try {
      return el.checked = false;
    } catch (error) {}
  });
};

P.html = function(els, h, a, s) {
  var r;
  r = '';
  P.each(els, function(el) {
    if (typeof h === 'string') {
      el.innerHTML = (a ? el.innerHTML : '') + h + (a === false ? el.innerHTML : '');
    }
    r += el.innerHTML;
    if (s) {
      return P.show(el);
    }
  });
  return r;
};

P.prepend = function(els, h) {
  return P.html(els, h, false);
};

P.append = function(els, h) {
  return P.html(els, h, true);
};

P.remove = function(els) {
  return P.each(els, function(el) {
    return el.parentNode.removeChild(el);
  });
};

P.classes = function(els, cls, d) {
  var r;
  r = [];
  if (cls) {
    cls = cls.replace(/^\./, '');
  }
  P.each(els, function(el) {
    var c, cc, j, len, ref1, ref2, results;
    c = (ref1 = el.getAttribute('class')) != null ? ref1 : '';
    if (cls) {
      if (d != null) {
        c = c.replace(cls, '').trim().replace(/\s\s/g, ' ');
      } else if (c.indexOf(cls) === -1) {
        c += (c.length ? ' ' : '') + cls;
      }
      el.setAttribute('class', c);
    }
    ref2 = c.split(' ');
    results = [];
    for (j = 0, len = ref2.length; j < len; j++) {
      cc = ref2[j];
      if (indexOf.call(r, c) < 0) {
        results.push(r.push(cc));
      } else {
        results.push(void 0);
      }
    }
    return results;
  });
  return r;
};

P.class = P.classes;

P.has = function(els, cls) {
  var r;
  r = false;
  P.each(els, function(el) {
    var ref1;
    if ((ref1 = cls.replace(/^\./, ''), indexOf.call(P.classes(el), ref1) >= 0) || (!cls.startsWith('.') && el.getAttribute(cls))) {
      return r = true;
    }
  });
  return r;
};

P.css = function(els, k, v) {
  var r;
  r = void 0;
  P.each(els, function(el) {
    var j, len, p, pk, pv, ref1, ref2, sk, ss, style;
    style = {};
    ref2 = ((ref1 = P.get(el, 'style')) != null ? ref1 : '').split(';');
    for (j = 0, len = ref2.length; j < len; j++) {
      p = ref2[j];
      [pk, pv] = p.split(':');
      style[pk] = pk === k && (v != null) ? v : pv;
    }
    if (r == null) {
      r = k != null ? style[k] : style;
    }
    if (v != null) {
      ss = '';
      for (sk in style) {
        if (style[sk] != null) {
          ss += (ss !== '' ? ';' : '') + sk + ':' + style[sk];
        }
      }
      return P.set(el, 'style', ss);
    }
  });
  return r;
};

P.clone = function(el, c) {
  var n;
  if (typeof el === 'string') {
    el = P(el);
  }
  el = P.list(el)[0];
  if (c) {
    n = el.cloneNode(true);
  } else {
    n = el.cloneNode(false);
    while (el.hasChildNodes()) {
      n.appendChild(el.firstChild);
    }
  }
  el.parentNode.replaceChild(n, el);
  return n;
};

P.siblings = function(els) {
  var r;
  r = [];
  P.each(els, function(el) {
    var results, s;
    s = el.parentNode.firstChild;
    results = [];
    while (s) {
      if (s.nodeType === 1 && s !== el) {
        r.push(s);
      }
      results.push(s = s.nextSibling);
    }
    return results;
  });
  return r;
};


// end of functions that act on elements
P.on = function(a, id, fn, l, sc) {
  var base, base1, name, wfn;
  if (a === 'enter') {
    a = 'keyup';
    wfn = function(e) {
      if (e.keyCode === 13) {
        return fn(e);
      }
    };
  } else {
    wfn = fn;
  }
  if (a === 'scroll') {
    if (l == null) {
      l = 300;
    }
  }
  if (l === true) {
    l = 300;
  }
  if (l) {
    wfn = P.limit(wfn);
  }
  if (P._ons == null) {
    P._ons = {};
  }
  if (P._ons[a] == null) {
    P._ons[a] = {};
    if (id.includes(' ')) {
      [sc, id] = id.split(' ');
    }
    if ((sc != null) && typeof sc === 'string') {
      sc = P.list(P(sc))[0];
    }
    (sc != null ? sc : document).addEventListener(a, function(e) {
      var f, i, ids, j, len, results, s;
      ids = P.classes(e.target);
      for (i in ids) {
        ids[i] = '.' + ids[i];
      }
      if (e.target.id) {
        ids.push('#' + e.target.id);
      }
      try {
        ids.push(e.target.tagName.toLowerCase());
      } catch (error) {}
      results = [];
      for (j = 0, len = ids.length; j < len; j++) {
        s = ids[j];
        if (P._ons[a][s] != null) {
          for (f in P._ons[a][s]) {
            P._ons[a][s][f](e);
          }
          break;
        } else {
          results.push(void 0);
        }
      }
      return results;
    });
  }
  if ((base = P._ons[a])[id] == null) {
    base[id] = {};
  }
  return (base1 = P._ons[a][id])[name = fn.toString().toLowerCase().replace('function', '').replace(/[^a-z0-9]/g, '')] != null ? base1[name] : base1[name] = wfn;
};

P.dot = function(o, k, v, d) {
  if (typeof k === 'string') {
    return P.dot(o, k.split('.'), v, d);
  } else if (k.length === 1 && ((v != null) || (d != null))) {
    if (d != null) {
      if (o instanceof Array) {
        o.splice(k[0], 1);
      } else {
        delete o[k[0]];
      }
      return true;
    } else {
      o[k[0]] = v;
      return true;
    }
  } else if (k.length === 0) {
    return o;
  } else {
    if (o[k[0]] == null) {
      if (v != null) {
        o[k[0]] = isNaN(parseInt(k[0])) ? {} : [];
        return P.dot(o[k[0]], k.slice(1), v, d);
      } else {
        return void 0;
      }
    } else {
      return P.dot(o[k[0]], k.slice(1), v, d);
    }
  }
};

P.keys = function(o) {
  var k, r;
  r = [];
  for (k in o) {
    r.push(k);
  }
  return r;
};

P.params = function(p) {
  var j, k, kv, len, r, ref1, v;
  r = {};
  ref1 = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
  for (j = 0, len = ref1.length; j < len; j++) {
    kv = ref1[j];
    [k, v] = kv.split('=');
    if (k) {
      if (typeof v === 'string') {
        try {
          v = decodeURIComponent(v);
        } catch (error) {}
        v = unescape(v.replace(/%22/gi, '"')); // just in case of weird old encoders that sent odd params
        try {
          v = JSON.parse(v);
        } catch (error) {}
      }
      r[k] = v != null ? v : true;
    }
  }
  if (p) {
    return r[p];
  } else {
    return r;
  }
};

P.ajax = function(url, opts) {
  var base, base1, h, loaded, ref1, ref2, ref3, xhr;
  if (typeof url === 'object') {
    opts = url;
    url = void 0;
  }
  if (url == null) {
    url = (ref1 = opts.url) != null ? ref1 : '';
  }
  if (url === '' || (url.startsWith('/') && !url.startsWith('//'))) {
    url = P.api + url;
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
        opts.headers.apikey = (ref2 = opts.apikey) != null ? ref2 : opts['x-apikey'];
      }
    }
  } catch (error) {}
  //else if P.account?.resume # if paradigm creds are available, but not sending to a paradigm URL (which would include cookies if available) try the resume key
  xhr = new XMLHttpRequest();
  xhr.open((ref3 = opts.method) != null ? ref3 : 'GET', url);
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
    var ref4;
    try {
      if (((ref4 = xhr.status) === 404) && !loaded) {
        return opts.error(xhr);
      }
    } catch (error) {}
  };
  try {
    return xhr.send(opts.data);
  } catch (error) {}
};

P.cookie = function(n, vs, opts) {
  var c, d, domained, dt, j, len, ref1, ref2, t;
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
      if (opts.domain.startsWith('.bg.')) { // a convenience for Paradigm bg servers
        opts.domain = opts.domain.replace('.bg.', '.');
      }
    }
    t = n + '=';
    if (vs) {
      t += encodeURIComponent(JSON.stringify(vs)); // so if values is false or '' this will effectively remove the cookie
    } else {
      opts.expires = -1;
    }
    d = (ref1 = opts.expires) != null ? ref1 : 180;
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
    ref2 = document.cookie.split(';');
    for (j = 0, len = ref2.length; j < len; j++) {
      c = ref2[j];
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

P.limit = function(fn, w) {
  var lim, p, t;
  if (w == null) {
    w = 300;
  }
  p = 0;
  t = null;
  lim = function() {
    var args, n, r, res;
    n = Date.now();
    r = w - (n - p);
    args = arguments;
    if (r <= 0 || r > w) {
      if (t) {
        clearTimeout(t);
        t = null;
      }
      p = n;
      res = fn.apply(this, args);
    } else {
      if (t == null) {
        t = setTimeout(() => {
          p = Date.now();
          return res = fn.apply(this, args);
        }, r);
      }
    }
    return res;
  };
  lim.stop = function() {
    return clearTimeout(t);
  };
  return lim;
};

P.ready = function(fn) {
  return document.addEventListener('DOMContentLoaded', fn);
};

P.scroll = function(fn) {
  fn = P.limit(fn);
  return window.addEventListener('scroll', function(e) {
    return fn(e);
  });
};

if (P('.Pscroll')) { // a convenience for nice UI visuals
  P.scroll();
}
