var indexOf = [].indexOf;

if (this.pradm == null) {
  this.pradm = {};
}

if (pradm.api == null) {
  pradm.api = '//' + window.location.host;
}

pradm.gebi = function(id) {
  return document.getElementById(id.replace('#', ''));
};

pradm.gebc = function(cls) {
  return document.getElementsByClassName(cls.replace('.', ''));
};

pradm.gebn = function(n) {
  var r;
  r = document.getElementsByTagName(n.replace('<', '').replace('>', '')); // e.g. by the element name, like "div"
  if (r != null) {
    return r;
  } else {
    return document.getElementsByName(n); // otherwise by the "name" attribute matching n
  }
};

pradm._gany = function(str) {
  return pradm[str.startsWith('#') ? 'gebi' : str.startsWith('.') ? 'gebc' : 'gebn'](str);
};

pradm.each = function(elems, key, val) {
  var elem, i, isid, len, results;
  if (typeof elems === 'string') {
    isid = elems.startsWith('#');
    elems = pradm._gany(elems);
    if (isid) {
      elems = [elems];
    }
  }
  if (elems != null) {
    results = [];
    for (i = 0, len = elems.length; i < len; i++) {
      elem = elems[i];
      if (elem != null) {
        if (typeof key === 'function') {
          results.push(key(elem));
        } else {
          results.push(pradm.set(elem, key, val));
        }
      } else {
        results.push(void 0);
      }
    }
    return results;
  }
};

pradm.listen = function(action, els, fn) {
  return pradm.each(els, function(el) {
    var wfn;
    if (action === 'enter') {
      action = 'keyup';
      wfn = function(e) {
        if (e.keyCode === 13) {
          return fn(e);
        }
      };
    } else {
      wfn = fn;
    }
    //el = pradm.clone el # gets rid of all listeners so we don't end up with dups - but note, gets rid of ALL. TODO use a wrapper to manage these independently
    if (!pradm.has(el, 'listen_' + action)) {
      pradm.class(el, 'listen_' + action);
      return el.addEventListener(action, function(e) {
        return wfn(e);
      });
    }
  });
};

pradm.show = function(els, html, append) {
  return pradm.each(els, function(el) {
    var was;
    if (typeof html === 'string') {
      el.innerHTML = (append ? el.innerHTML : '') + html;
    }
    was = pradm.get(el, 'pradm_display');
    if (typeof was !== 'string' || was === 'none') { // TODO should be inline in which cases...
      was = 'block';
    }
    return el.style.display = was;
  });
};

pradm.hide = function(els) {
  return pradm.each(els, function(el) {
    if (el.style.display !== 'none') {
      pradm.set(el, 'pradm_display', el.style.display);
    }
    return el.style.display = 'none';
  });
};

pradm.focus = function(els) {
  return pradm.each(els, function(el) {
    return el.focus();
  });
};

pradm.blur = function(els) {
  return pradm.each(els, function(el) {
    return el.blur();
  });
};

pradm.get = function(el, attr) {
  var ref, res;
  if (typeof el === 'string') {
    el = pradm._gany(el);
  }
  if (Array.isArray(el)) {
    el = el[0];
  }
  if (attr == null) {
    try {
      res = pradm.checked(el);
    } catch (error) {}
    try {
      if ((res == null) && ((ref = el.getAttribute('type')) !== 'radio' && ref !== 'checkbox')) {
        res = el.value;
      }
    } catch (error) {}
    if (typeof res === 'string' && !res.length) {
      res = void 0;
    }
  }
  try {
    if (res == null) {
      res = el.getAttribute(attr);
    }
  } catch (error) {}
  return res;
};

pradm.set = function(el, attr, val) {
  if (typeof el === 'string') {
    el = pradm._gany(el);
  }
  if (Array.isArray(el)) {
    el = el[0];
  }
  try {
    return el.setAttribute(attr, val);
  } catch (error) {}
};

pradm.checked = function(el) {
  if (el instanceof HTMLInputElement) {
    if (el.getAttribute('type') === 'checkbox') {
      return el.checked;
    } else if (el.getAttribute('type') === 'radio') {
      if (el.checked && el.value) {
        return el.value;
      } else {
        return void 0;
      }
    }
  } else {
    return void 0;
  }
};

pradm.html = function(els, html, append, show) {
  var ref, rs;
  rs = [];
  pradm.each(els, function(el) {
    if (typeof html === 'string') {
      el.innerHTML = (append ? el.innerHTML : '') + html;
    }
    rs.push(el.innerHTML);
    if (show) {
      return pradm.show(el);
    }
  });
  if (rs.length === 1) {
    return (ref = rs[0]) != null ? ref : '';
  } else if (rs.length) {
    return rs;
  } else {
    return '';
  }
};

pradm.append = function(els, html) {
  return pradm.html(els, html, true);
};

pradm.remove = function(els) {
  return pradm.each(els, function(el) {
    return el.parentNode.removeChild(el);
  });
};

pradm.class = function(el, cls, remove) {
  var classes;
  classes = el.getAttribute('class');
  if (classes == null) {
    classes = '';
  }
  if (typeof cls === 'string') {
    if (remove === false) {
      classes = classes.replace(cls, '').trim().replace(/  /g, ' ');
    } else if (classes.indexOf(cls) === -1) {
      if (classes.length) {
        classes += ' ';
      }
      classes += cls;
    }
    el.setAttribute('class', classes);
  }
  return classes.split(' ');
};

pradm.classes = function(els) {
  return pradm.class(els);
};

pradm.has = function(el, cls) {
  var classes;
  classes = pradm.classes(el);
  if (cls.startsWith('.')) {
    cls = cls.replace('.');
  }
  if (indexOf.call(classes, cls) >= 0) {
    return true;
  } else {
    if (el.getAttribute(cls)) {
      return true;
    } else {
      return false;
    }
  }
};

pradm.css = function(els, key, val) {
  var rs;
  rs = [];
  pradm.each(els, function(el) {
    var i, k, len, p, ps, ref, s, ss, style;
    s = pradm.get(el, 'style');
    if (s == null) {
      s = '';
    }
    style = {};
    ref = s.split(';');
    for (i = 0, len = ref.length; i < len; i++) {
      p = ref[i];
      ps = p.split(':');
      if (ps.length === 2) {
        style[ps[0].trim()] = ps[1].trim();
      }
    }
    if ((key == null) || (style[key] != null)) {
      rs.push(key != null ? style[key] : style);
    }
    if (val != null) {
      style[key] = val;
    }
    ss = '';
    for (k in style) {
      if (ss !== '') {
        ss += ';';
      }
      ss += k + ':' + style[k];
    }
    return pradm.set(el, 'style', ss);
  });
  if (val == null) {
    if (rs.length === 1) {
      return rs[0];
    } else {
      return rs;
    }
  }
};

pradm.clone = function(el, children) {
  var n;
  if (children) {
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

pradm.dot = function(obj, key, value, del) {
  if (typeof key === 'string') {
    return pradm.dot(obj, key.split('.'), value, del);
  } else if (key.length === 1 && ((value != null) || (del != null))) {
    if (del === true || value === '$DELETE') {
      if (obj instanceof Array) {
        obj.splice(key[0], 1);
      } else {
        delete obj[key[0]];
      }
      return true;
    } else {
      obj[key[0]] = value; // TODO see below re. should this allow writing into multiple sub-objects of a list?
      return true;
    }
  } else if (key.length === 0) {
    return obj;
  } else {
    if (obj[key[0]] == null) {
      if (false) {

      // check in case obj is a list of objects, and key[0] exists in those objects
      // if so, return a list of those values.
      // Keep order of the list? e.g for objects not containing the key, output undefined in the list space where value would have gone?
      // and can this recurse further? If the recovered items are lists or objecst themselves, go further into them?
      // if so, how would that be represented? and is it possible for this to work at all with value assignment?
      } else if (value != null) {
        obj[key[0]] = isNaN(parseInt(key[0])) ? {} : [];
        return pradm.dot(obj[key[0]], key.slice(1), value, del);
      } else {
        return void 0;
      }
    } else {
      return pradm.dot(obj[key[0]], key.slice(1), value, del);
    }
  }
};

pradm.ajax = function(url, opts) {
  var base, h, ref, ref1, xhr;
  console.log(url);
  if (typeof url === 'object') {
    opts = url;
    url = void 0;
  }
  if (url == null) {
    url = (ref = opts.url) != null ? ref : '';
  }
  if (url === '' || (url.startsWith('/' && !url.startsWith('//')))) {
    url = pradm.api + url;
  }
  if (opts == null) {
    opts = {};
  }
  if (opts.headers == null) {
    opts.headers = {};
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
  //url += (if url.indexOf('?') is -1 then '?' else '&') + '_=' + Date.now() # set a random header to break caching?
  xhr = new XMLHttpRequest();
  console.log(url);
  xhr.open((ref1 = opts.method) != null ? ref1 : 'GET', url);
  for (h in opts.headers) {
    xhr.setRequestHeader(h, opts.headers[h]);
  }
  xhr.send(opts.data);
  xhr.onload = function() { // worth checking xhr.status is 200?
    var err, x;
    try {
      x = xhr.response;
      try {
        x = JSON.parse(x);
      } catch (error) {}
      try {
        return opts.success(x, xhr);
      } catch (error) {}
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
  return xhr.onerror = function(err) {
    try {
      return opts.error(err);
    } catch (error) {}
  };
};
