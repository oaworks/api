  // n should be element ID or class name or tag name.
  // Prefix IDs with # and class names with .
  // Scope them to within a specific element by providing that element ID first 
  // (preceded with #), then a space, then the element(s) class name / tag name
  // (ID requests can't be scoped this way because IDs have to be unique within a page anyway)
  // or an element to scope on can be directly provided as third param
var P,
  indexOf = [].indexOf;

P = function(n, fn, sc) {
  var d;
  if (typeof fn === 'function') {
    return P.each(n, fn, void 0, sc);
  } else if (n) {
    if (n.startsWith('#') && n.includes(' ')) {
      sc = n.split(' ')[0];
      n = n.replace(sc + ' ', '');
      sc = P.gebi(sc);
    }
    d = P[n.startsWith('#') ? 'gebi' : n.startsWith('.') ? 'gebc' : 'gebn'](n, sc);
    if ((d != null) && (n.startsWith('#') || d.length !== 0)) {
      return d;
    } else {
      return void 0;
    }
  }
};

P.gebi = function(id) {
  return document.getElementById(id.split('#').pop().split(' ')[0]);
};

P.gebc = function(n, sc) {
  var d;
  if (typeof sc === 'string' || (n.startsWith('#') && n.includes(' '))) {
    if (sc == null) {
      sc = P.list(P(sc != null ? sc : n))[0];
    }
  }
  d = (sc != null ? sc : document).getElementsByClassName(n.replace(/^\./, '').replace(/\s\./g, ' ').trim());
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
    if (typeof sc === 'string' || (n.startsWith('#') && n.includes(' '))) {
      if (sc == null) {
        sc = P.list(P(sc != null ? sc : n))[0];
      }
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
  var d, i, j, len, len1, ref, ref1, t, tag;
  d = [];
  if (typeof sc === 'string' || (ns.startsWith('#') && ns.includes(' '))) {
    if (sc == null) {
      sc = P.list(P(sc != null ? sc : ns))[0];
    }
  }
  ref = ns.replace(/, /g, ',').split(',');
  for (i = 0, len = ref.length; i < len; i++) {
    tag = ref[i];
    ref1 = (sc != null ? sc : document).getElementsByTagName(tag);
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      t = ref1[j];
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
  var el, i, len, ref, results;
  if (typeof els === 'string') {
    els = P(els, void 0, sc);
  }
  ref = P.list(els);
  results = [];
  for (i = 0, len = ref.length; i < len; i++) {
    el = ref[i];
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
    var ref, ref1;
    if (r == null) {
      if (a != null) {
        try {
          return r = el.getAttribute(a);
        } catch (error) {}
      } else {
        if ((ref = el.getAttribute('type')) === 'radio' || ref === 'checkbox') {
          try {
            r = P.checked(el);
          } catch (error) {}
        }
        if ((r == null) && ((ref1 = el.getAttribute('type')) !== 'radio' && ref1 !== 'checkbox')) {
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
    var ref;
    if (r == null) {
      if (el instanceof HTMLInputElement) {
        if (el.getAttribute('type') === 'checkbox') {
          return r = el.checked;
        } else if (el.getAttribute('type') === 'radio') {
          return r = el.checked ? (ref = el.value) != null ? ref : true : false;
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
    var c, cc, i, len, ref, ref1, results;
    c = (ref = el.getAttribute('class')) != null ? ref : '';
    if (cls) {
      if (d != null) {
        c = c.replace(cls, '').trim().replace(/\s\s/g, ' ');
      } else if (c.indexOf(cls) === -1) {
        c += (c.length ? ' ' : '') + cls;
      }
      el.setAttribute('class', c);
    }
    ref1 = c.split(' ');
    results = [];
    for (i = 0, len = ref1.length; i < len; i++) {
      cc = ref1[i];
      if (indexOf.call(r, cc) < 0) {
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
    var ref;
    if ((ref = cls.replace(/^\./, ''), indexOf.call(P.classes(el), ref) >= 0) || (!cls.startsWith('.') && el.getAttribute(cls))) {
      return r = true;
    }
  });
  return r;
};

P.css = function(els, k, v) {
  var r;
  r = void 0;
  P.each(els, function(el) {
    var i, len, p, pk, pv, ref, ref1, sk, ss, style;
    style = {};
    ref1 = ((ref = P.get(el, 'style')) != null ? ref : '').split(';');
    for (i = 0, len = ref1.length; i < len; i++) {
      p = ref1[i];
      [pk, pv] = p.split(':');
      style[pk] = pk === k && (v != null) ? v : pv;
    }
    if (r == null) {
      r = k != null ? style[k] : style;
    }
    if (v != null) {
      style[k] = v;
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
P.mobile = function() { // try to tell if on a mobile device
  if (/(android|bb\d+|meego).+mobile|avantgo|bada\/|blackberry|blazer|compal|elaine|fennec|hiptop|iemobile|ip(hone|od)|ipad|iris|kindle|Android|Silk|lge |maemo|midp|mmp|netfront|opera m(ob|in)i|palm( os)?|phone|p(ixi|re)\/|plucker|pocket|psp|series(4|6)0|symbian|treo|up\.(browser|link)|vodafone|wap|windows (ce|phone)|xda|xiino/i.test(navigator.userAgent) || /1207|6310|6590|3gso|4thp|50[1-6]i|770s|802s|a wa|abac|ac(er|oo|s\-)|ai(ko|rn)|al(av|ca|co)|amoi|an(ex|ny|yw)|aptu|ar(ch|go)|as(te|us)|attw|au(di|\-m|r |s )|avan|be(ck|ll|nq)|bi(lb|rd)|bl(ac|az)|br(e|v)w|bumb|bw\-(n|u)|c55\/|capi|ccwa|cdm\-|cell|chtm|cldc|cmd\-|co(mp|nd)|craw|da(it|ll|ng)|dbte|dc\-s|devi|dica|dmob|do(c|p)o|ds(12|\-d)|el(49|ai)|em(l2|ul)|er(ic|k0)|esl8|ez([4-7]0|os|wa|ze)|fetc|fly(\-|_)|g1 u|g560|gene|gf\-5|g\-mo|go(\.w|od)|gr(ad|un)|haie|hcit|hd\-(m|p|t)|hei\-|hi(pt|ta)|hp( i|ip)|hs\-c|ht(c(\-| |_|a|g|p|s|t)|tp)|hu(aw|tc)|i\-(20|go|ma)|i230|iac( |\-|\/)|ibro|idea|ig01|ikom|im1k|inno|ipaq|iris|ja(t|v)a|jbro|jemu|jigs|kddi|keji|kgt( |\/)|klon|kpt |kwc\-|kyo(c|k)|le(no|xi)|lg( g|\/(k|l|u)|50|54|\-[a-w])|libw|lynx|m1\-w|m3ga|m50\/|ma(te|ui|xo)|mc(01|21|ca)|m\-cr|me(rc|ri)|mi(o8|oa|ts)|mmef|mo(01|02|bi|de|do|t(\-| |o|v)|zz)|mt(50|p1|v )|mwbp|mywa|n10[0-2]|n20[2-3]|n30(0|2)|n50(0|2|5)|n7(0(0|1)|10)|ne((c|m)\-|on|tf|wf|wg|wt)|nok(6|i)|nzph|o2im|op(ti|wv)|oran|owg1|p800|pan(a|d|t)|pdxg|pg(13|\-([1-8]|c))|phil|pire|pl(ay|uc)|pn\-2|po(ck|rt|se)|prox|psio|pt\-g|qa\-a|qc(07|12|21|32|60|\-[2-7]|i\-)|qtek|r380|r600|raks|rim9|ro(ve|zo)|s55\/|sa(ge|ma|mm|ms|ny|va)|sc(01|h\-|oo|p\-)|sdk\/|se(c(\-|0|1)|47|mc|nd|ri)|sgh\-|shar|sie(\-|m)|sk\-0|sl(45|id)|sm(al|ar|b3|it|t5)|so(ft|ny)|sp(01|h\-|v\-|v )|sy(01|mb)|t2(18|50)|t6(00|10|18)|ta(gt|lk)|tcl\-|tdg\-|tel(i|m)|tim\-|t\-mo|to(pl|sh)|ts(70|m\-|m3|m5)|tx\-9|up(\.b|g1|si)|utst|v400|v750|veri|vi(rg|te)|vk(40|5[0-3]|\-v)|vm40|voda|vulc|vx(52|53|60|61|70|80|81|83|85|98)|w3c(\-| )|webc|whit|wi(g |nc|nw)|wmlb|wonu|x700|yas\-|your|zeto|zte\-/i.test(navigator.userAgent.substr(0, 4))) {
    return true;
  } else {
    return false;
  }
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
        o[k[0]] = typeof k[0] === 'number' || !isNaN(parseInt(k[0])) ? [] : {};
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
  var i, k, kv, len, r, ref, v;
  r = {};
  ref = window.location.href.slice(window.location.href.indexOf('?') + 1).split('&');
  for (i = 0, len = ref.length; i < len; i++) {
    kv = ref[i];
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
  //else if P.account?.resume # if paradigm creds are available, but not sending to a paradigm URL (which would include cookies if available) try the resume key
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

P.cookie = function(n, vs, opts) {
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

P.on = function(a, id, fn, l, sc) {
  var base, base1, base2, name, nl, wfn;
  if (typeof fn === 'number' && typeof l === 'function') {
    nl = fn;
    fn = l;
    l = nl;
  }
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
  if (a === 'scroll' || a === 'keyup') {
    if (l == null) {
      l = 300;
    }
  }
  if (l === true) {
    l = 300;
  }
  if (l) {
    wfn = P.limit(wfn, l);
  }
  if (id.startsWith('#') && id.includes(' ')) {
    sc = id.split(' ')[0].replace('#', '');
    id = id.split(' ');
    id.shift();
    id = id.join(' ');
  } else {
    sc = '_doc';
  }
  if (P._ons == null) {
    P._ons = {};
  }
  if ((base = P._ons)[sc] == null) {
    base[sc] = {};
  }
  if (P._ons[sc][a] == null) {
    P._ons[sc][a] = {};
    (sc === '_doc' ? document : P.list(P('#' + sc))[0]).addEventListener(a, function(e) {
      var _bids, f, i, ids, len, pn, results, s;
      ids = [];
      _bids = function(et) {
        var etnl, i, len, pc, ref, ref1, ref2;
        ref = P.classes(et);
        for (i = 0, len = ref.length; i < len; i++) {
          pc = ref[i];
          if (ref1 = '.' + pc, indexOf.call(ids, ref1) < 0) {
            ids.push('.' + pc);
          }
        }
        if (et.id && (ref2 = '#' + et.id, indexOf.call(ids, ref2) < 0)) {
          ids.push('#' + et.id);
        }
        try {
          etnl = et.tagName.toLowerCase();
          if (indexOf.call(ids, etnl) < 0) {
            return ids.push(etnl);
          }
        } catch (error) {}
      };
      _bids(e.target);
      if (a === 'click') { // catch bubbling from clicks on child elements for example - are there other actions this is worth doing for?
        pn = e.target.parentNode;
        while (pn) {
          if (document.body === pn) {
            pn = void 0;
          } else {
            _bids(pn);
            pn = pn.parentNode;
          }
        }
      }
      results = [];
      for (i = 0, len = ids.length; i < len; i++) {
        s = ids[i];
        if (P._ons[sc][a][s] != null) {
          for (f in P._ons[sc][a][s]) {
            P._ons[sc][a][s][f](e);
          }
          break;
        } else {
          results.push(void 0);
        }
      }
      return results;
    });
  }
  if ((base1 = P._ons[sc][a])[id] == null) {
    base1[id] = {};
  }
  return (base2 = P._ons[sc][a][id])[name = fn.toString().toLowerCase().replace('function', '').replace(/[^a-z0-9]/g, '')] != null ? base2[name] : base2[name] = wfn;
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
