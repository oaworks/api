//a library for managing reading writing and saving of records
P._editStyle = '<style>.PChanged { border-color: yellow; box-shadow: 1px 1px 1px 1px yellow; } .PSaved { border-color: green; box-shadow: 1px 1px 1px 1px green; } .PError { border-color: red; box-shadow: 1px 1px 1px 1px red; } </style>';

P._editTimeout;

P._editRecord;

P.edit = function(opts) {
  var _watch, form, pa, pe, pf, ref;
  if (opts == null) {
    opts = {};
  }
  if (pe = P('.PSave')) {
    if (!opts.goto) {
      pa = P.get(pe, 'goto');
      if (pa == null) {
        pa = P.get(pe, 'href');
      }
      if (pa) {
        opts.goto = pa;
      }
      if (!opts.goto) {
        opts.goto = '#PThanks';
        if (opts.clear == null) {
          opts.clear = true;
        }
        if (opts.hide == null) {
          opts.hide = false;
        }
      }
    }
  }
  try {
    if (pf = P('.PForm')) {
      if (Array.isArray(pf) || HTMLCollection.prototype.isPrototypeOf(pf) || NodeList.prototype.isPrototypeOf(pf)) {
        pf = pf[0];
      }
      form = pf.closest('form');
      if (opts.url == null) {
        opts.url = P.get(form, 'action');
      }
      if (opts.method == null) {
        opts.method = P.get(form, 'method');
      }
    }
  } catch (error) {}
  if (opts.url == null) {
    opts.url = window.location.pathname.replace('.html', '');
  }
  if (opts.style !== false) {
    P.append('body', (ref = opts.style) != null ? ref : P._editStyle);
  }
  if (opts.record != null) {
    // could add opts to build or populate here
    P._editRecord = opts.record;
  } else {
    P.save(void 0, false);
  }
  _watch = function(e) {
    var el;
    el = e.target;
    if (P._editTimeout != null) {
      clearTimeout(P._editTimeout);
    }
    P.class(el, 'PError', false);
    P.class(el, 'PSaved', false);
    P.class(el, 'PChanged');
    if (!P('.PSave')) {
      return P._editTimeout = setTimeout((function() {
        return P.save(void 0, opts);
      }), 1500);
    }
  };
  if (P('.PSave')) {
    return P.on('click', '.PSave', function(e) {
      return P.save(void 0, opts, e);
    });
  } else if (opts.watch !== false) {
    P.on('change', '.PForm', _watch);
    return P.on('keyup', '.PForm', _watch);
  }
};

P.save = function(rec, opts, e) { // does this need to be separate?
  var cls;
  if (typeof P.validate !== 'function' || P.validate()) {
    console.log('saving');
    P.show('.PLoading');
    if (e != null) {
      try {
        P.attr(e.target, '_content', P.html(e.target));
        P.html(e.target, 'Submitting...');
      } catch (error) {}
      try {
        e.preventDefault();
      } catch (error) {}
    }
    if (rec == null) {
      if (P._editRecord == null) {
        P._editRecord = {};
      }
      P('.PSaved', function(el) {
        return P.class(el, 'PSaved', false);
      });
      cls = opts === false ? '.PForm' : '.PChanged';
      if (cls === '.PChanged' && !P(cls)) {
        cls = '.PForm';
      }
      P(cls, function(el) {
        var base, key, pv;
        key = P.get(el, 'PKey');
        if (key == null) {
          key = P.get(el, 'id');
        }
        if (el.getAttribute('type') === 'radio') {
          if ((base = P._editRecord)[key] == null) {
            base[key] = [];
          }
          return P._editRecord[key].push(P.get(el));
        } else {
          pv = P.get(el);
          if (pv === null) {
            try {
              return delete P._editRecord[key];
            } catch (error) {}
          } else {
            return P._editRecord[key] = pv;
          }
        }
      });
      rec = P._editRecord;
    }
    if (opts !== false) {
      if (rec._id == null) {
        rec._id = P._newid;
      }
      P.ajax(opts.url, {
        method: opts.method,
        data: rec, // use opts.method and other settings to decide whether to GET or POST or send a form-URL-encoded
        success: function(data) {
          try {
            P.html(e.target, P.attr(e.target, '_content'));
          } catch (error) {}
          P.hide('.PLoading');
          if (!P._newid && window.location.search.indexOf('?new') !== -1 || window.location.search.indexOf('&new') !== -1) {
            P._newid = data._id;
            try {
              window.history.replaceState("", "", window.location.pathname.replace('.html', '/' + data._id + '.html?edit'));
            } catch (error) {}
          }
          P('.PChanged', function(el) {
            P.class(el, 'PChanged', false);
            return P.class(el, 'PSaved');
          });
          if (opts.clear) {
            try {
              P.set('.PForm', '');
            } catch (error) {}
          }
          if (opts.hide && (e != null)) {
            P.hide(e.target.closest('form'));
          }
          if (typeof opts.goto === 'function') {
            return opts.goto();
          } else if (typeof opts.goto === 'string') {
            if (opts.goto.startsWith('#') || opts.goto.startsWith('.') && P(opts.goto)) {
              P.hide('.PSave');
              P.show(opts.goto);
              return setTimeout((function() {
                P.hide(opts.goto);
                return P.show('.PSave');
              }), 10000);
            } else {
              return window.location = opts.goto;
            }
          }
        },
        error: function(data) {
          try {
            P.html(e.target, P.attr(e.target, '_content'));
          } catch (error) {}
          P.hide('.PLoading');
          P.show('.PError');
          return P('.PChanged', function(el) {
            P.class(el, 'PChanged', false);
            return P.class(el, 'PError');
          });
        }
      });
    }
  }
  return false; // always returns false to stop form submitting manually as well
};

P.validate = function(form) {
  var pf, res;
  if ((form == null) && (pf = P('.PForm'))) {
    pf = P.list(pf)[0];
    form = pf.closest('form');
  }
  if (form != null) {
    form = P.list(form)[0];
    res = form.checkValidity();
    return res;
  } else {
    return true;
  }
};
