P.search = function(opts) {
  var p, pp;
  if (opts == null) {
    opts = {};
  }
  if (opts.msg == null) {
    opts.msg = 'search...'; // the first placeholder message displayed in the PSearch box
  }
  if (opts.url == null) {
    opts.url = window.location.href.split('?')[0].replace('.html', ''); // provide a search endpoint URL compatible with 7.x versions of ES
  }
  // note that if the query response is going to be different, other rewrites will be needed too
  if (opts.default == null) {
    opts.default = {
      query: {
        bool: {
          must: [],
          filter: []
        }
      }
    };
  }
  // opts.size can be defined separately to save writing the whole default query, defaults to 10
  // opts.sort can be any ES sort format
  // or opts.random can be true to convert the query to a constant_score random sort query with seed for paging (opts.seed can optionally be provided too)
  // opts.aggregations can be defined separate from default query to save having to rewrite the whole thing
  if (opts.query == null) {
    opts.query = true; // this could be false to not run a query at startup, or can be defined if the startup query should be different from default
  }
  if (opts.operator == null) {
    opts.operator = "AND"; // query operator param for the search box query params
  }
  if (opts.fuzzy == null) {
    opts.fuzzy = "*"; // fuzzify the search box query params if they are simple strings. Can be * or ~ or if false the query will not be fuzzified
  }
  if (opts.pushstate == null) {
    opts.pushstate = true; // try pushing query state to browser URL bar or not
  }
  if (opts.sticky == null) {
    opts.sticky = true; // if sticky, the search bar should stick to the top when scrolling up
  }
  if (opts.scroll == null) {
    opts.scroll = true; // when results are scrolled to bottom retrieve the next set of results
  }
  // opts.method can be set to POST to force an ajax POST, otherwise query will be a GET with ?source= stringified query
  opts.table = true; // or could be list of keys such as ['DOI', 'title', 'year', 'ISSN'] or object of keys pointing to display names, or false for non-tabular default layout
  P.search.opts = opts;
  opts.paging = false;
  opts.max = false;
  opts.page = function(e, previous) { // best to call this via previous or next
    var ref, ref1;
    try {
      e.preventDefault();
    } catch (error) {}
    opts.query.from = ((ref = opts.query.from) != null ? ref : 0) + ((previous ? -1 : 1) * ((ref1 = opts.query.size) != null ? ref1 : 10));
    if (opts.query.from < 0) {
      opts.query.from = 0;
    }
    if (P('.PResultFrom' + opts.query.from)) {
      P.hide('.PSearchResult');
      P.show('.PResultFrom' + opts.query.from);
      return opts.placeholder();
    } else if (!opts.max) {
      P.show('.PLoading');
      opts.paging = true;
      return opts.search();
    }
  };
  opts.previous = function(e) {
    return opts.page(e, true);
  };
  opts.next = function(e) {
    return opts.page(e);
  };
  opts.from = function() {
    opts.query.from = parseInt(P.val('.PSearchFrom'));
    return opts.search();
  };
  opts.to = function() {
    var ref;
    opts.query.size = P.val('.PSearchTo') - ((ref = opts.query.from) != null ? ref : 0);
    return opts.search();
  };
  opts.scroller = function() {
    return window.addEventListener('scroll', function() {
      if (!opts.paging && (window.innerHeight + window.pageYOffset) >= document.body.offsetHeight) {
        return opts.next();
      }
    });
  };
  opts.add = function(e) {
    var k, tf, v, val;
    try {
      e.preventDefault();
    } catch (error) {}
    delete opts.query.from;
    // TODO add range sliders and a way to get data out of them when they change
    if (val = P.val(e.target)) {
      if (val.indexOf('opts.') === 0) {
        if (val.indexOf(':') === -1) { // print opts config to the search box placeholder
          opts.placeholder(P.dot(opts, val.replace('opts.', ''))); // change the opts config to the provided value
        } else {
          k = val.substring(8, val.indexOf(':')).replace(' ', '');
          v = val.substring(val.indexOf(':') + 1).trim();
          try {
            v = JSON.parse(v);
          } catch (error) {}
          if (opts.scroll === false && k === 'opts.scroll' && v === true) {
            opts.scroller();
          }
          try {
            P.dot(opts, k, v);
            opts.search();
          } catch (error) {}
        }
      } else if (val.indexOf(':') !== -1 && val.split(':')[0].indexOf(' ') === -1 && val.indexOf('*') === -1 && val.indexOf('~') === -1 && val.indexOf(' AND ') === -1 && val.indexOf(' OR ') === -1) {
        tf = {
          term: {}
        };
        tf.term[val.split(':')[0]] = val.split(':')[1].replace(/"/g, '');
        opts.query.query.bool.filter.push(tf);
        opts.search();
      } else if (val.startsWith('"') && val.endsWith('"')) {
        opts.query.query.bool.filter.push({
          "match_phrase": {
            "_all": val.replace(/"/g, '')
          }
        });
        opts.search();
      } else {
        opts.query.query.bool.filter.push({
          "query_string": {
            "default_operator": opts.operator,
            "query": opts.fuzzify(val)
          }
        });
        opts.search();
      }
    }
    try {
      P.set(e.target, '');
    } catch (error) {}
    return P.blur('.PSearch');
  };
  opts.remove = function(e) {
    try {
      e.preventDefault();
    } catch (error) {}
    P.remove(e.target.closest('a'));
    if (false) { // TODO if it's the remove all button...
      opts.query = void 0;
    } else {
      opts.query.query.bool.filter = [];
      delete opts.query.from;
    }
    return opts.search();
  };
  opts.placeholder = function(pl) {
    var ref, ref1, ref2, ref3;
    if (!pl) {
      pl = ((ref = opts.query.from) != null ? ref : 0) + ((ref1 = opts.query.size) != null ? ref1 : 10) < opts.response.hits.total ? ((ref2 = opts.query.from) != null ? ref2 : 0) + ((ref3 = opts.query.size) != null ? ref3 : 10) : opts.response.hits.total;
      pl += pl !== 0 ? ' of ' + opts.response.hits.total : '';
    }
    P.set('.PSearch', '');
    return P.attr('.PSearch', 'placeholder', pl);
  };
  opts.fuzzify = function(str) {
    if (opts.fuzzy && str.indexOf('*') === -1 && str.indexOf('~') === -1 && str.indexOf(':') === -1 && str.indexOf('"') === -1 && str.indexOf('AND') === -1 && str.indexOf('OR') === -1) {
      str = (opts.fuzzy === '*' ? '*' : '') + str.trim().replace(/\s/g, opts.fuzzy + ' ' + (opts.fuzzy === '*' ? '*' : '')) + opts.fuzzy;
    }
    return str;
  };
  opts.translate = function() {
    var a, base, base1, base2, base3, f, fq, i, j, l, len, len1, len2, ou, qsf, ref, ref1, ref2, ref3, ref4, sk;
    ref1 = (ref = opts.aggregations) != null ? ref : [];
    for (i = 0, len = ref1.length; i < len; i++) {
      a = ref1[i];
      if ((base = opts.default).aggregations == null) {
        base.aggregations = [];
      }
      opts.default.aggregations.push(typeof a === 'string' ? {
        terms: {
          field: a
        }
      } : a);
    }
    if ((base1 = opts.default).size == null) {
      base1.size = opts.size;
    }
    ref2 = ['includes', 'excludes'];
    for (j = 0, len1 = ref2.length; j < len1; j++) {
      sk = ref2[j];
      if (opts[sk] != null) {
        if ((base2 = opts.default)._source == null) {
          base2._source = {};
        }
        if ((base3 = opts.default._source)[sk] == null) {
          base3[sk] = opts[sk];
        }
      }
    }
    if (opts.filters) {
      opts.default.query.bool.filter = opts.filters;
    }
    if (typeof opts.query !== 'object') { // it can be true or false at startup
      delete opts.query;
    }
    if (opts.query == null) {
      opts.query = JSON.parse(JSON.stringify(opts.default));
    }
    P('.PSearchVal', function(el) {
      var tf, val;
      try {
        val = P.val(el);
      } catch (error) {}
      try {
        if (val == null) {
          val = P.html(el);
        }
      } catch (error) {}
      if (val) {
        if (val.indexOf(':') !== -1) {
          tf = {
            term: {}
          };
          tf.term[val.split(':')[0]] = val.split(':')[1].replace(/"/g, '');
          return opts.query.query.bool.filter.push(tf);
        } else if (val.indexOf('*') !== -1 || val.indexOf('~') !== -1 || val.indexOf(' AND ') !== -1 || val.indexOf(' OR ') === -1) {
          return opts.query.query.bool.filter.push({
            "query_string": {
              "default_operator": opts.operator,
              "query": val
            }
          });
        } else {
          return opts.query.query.bool.filter.push({
            "match_phrase": {
              "_all": val
            }
          });
        }
      }
    });
    ref4 = (ref3 = opts.filters) != null ? ref3 : [];
    for (l = 0, len2 = ref4.length; l < len2; l++) {
      f = ref4[l];
      qsf = JSON.stringify(opts.query.query.bool.filter);
      try {
        if (qsf.indexOf(JSON.stringify(f)) === -1) {
          opts.query.query.bool.filter.push(f);
        }
      } catch (error) {}
    }
    if (opts.random) {
      if (opts.random !== true) {
        if (opts.seed == null) {
          opts.seed = opts.random;
        }
      }
      if (opts.seed == null) {
        opts.seed = Math.floor(Math.random() * 1000000000000);
      }
      fq = {
        function_score: {
          random_score: {
            seed: opts.seed
          }
        }
      };
      fq.function_score.query = opts.query.query;
      opts.query.query = fq;
    } else if (opts.sort != null) {
      opts.query.sort = typeof opts.sort === 'function' ? opts.sort() : opts.sort;
    }
    if (opts.paging) {
      delete opts.query.aggregations;
    }
    if (opts.method !== 'POST') {
      ou = opts.url.split('source=')[0];
      ou += ou.indexOf('?') === -1 ? '?' : !ou.endsWith('&') && !ou.endsWith('?') ? '&' : '';
      opts.url = ou + 'source=' + encodeURIComponent(JSON.stringify(opts.query));
    }
    return opts.query;
  };
  opts._first = true;
  opts.success = function(resp) {
    var ref;
    P.hide('.PLoading');
    opts.response = resp;
    if (opts._first) {
      opts._first = false;
    } else {
      opts.placeholder();
    }
    opts.render();
    opts.construct();
    try {
      opts.max = resp.hits.hits.length < ((ref = opts.query.size) != null ? ref : 10);
    } catch (error) {}
    return opts.paging = false;
  };
  opts.error = function(resp) {
    P.hide('.PLoading');
    P.show('.PError');
    return console.log(resp);
  };
  opts.searching = false;
  opts.search = function(e) {
    if (!opts.searching) {
      opts.searching = true;
      P.hide('.PError');
      P.show('.PLoading');
      if (!opts._first) {
        P.attr('.PSearch', 'placeholder', 'searching...');
      }
      return setTimeout(function() {
        var o;
        o = {
          success: opts.success,
          error: opts.error,
          data: opts.translate() // translate here so it does exist if necessary, but otherwise it at least still needs to run anyway
        };
        if (opts.method !== 'POST') {
          delete o.data;
        }
        o.url = opts.url;
        if (opts.username && opts.password) {
          o.headers = {
            "Authorization": "Basic " + btoa(opts.username + ":" + opts.password)
          };
        }
        if (opts.apikey) {
          o.headers = {
            apikey: opts.apikey
          };
        }
        P.ajax(o);
        return opts.searching = false;
      }, 300);
    }
  };
  opts.render = function() {
    var bt, f, filter, gte, k, key, kk, lte, query, ref, ref1, ref2, ref3, ref4, ws;
    if (opts.pushstate) {
      ws = window.location.search.split('source=')[0];
      if (JSON.stringify(opts.query) !== JSON.stringify(opts.default)) {
        ws += ws.indexOf('?') === -1 ? '?' : !ws.endsWith('&') ? '&' : '';
        ws += 'source=' + JSON.stringify(opts.query); // url encode this?
      }
      if (ws.endsWith('&') || ws.endsWith('?')) {
        ws = ws.substring(0, ws.length - 1);
      }
      try {
        window.history.pushState("", "search", ws);
      } catch (error) {}
    }
    try {
      P.set('.PSearchFrom', (ref = opts.query.from) != null ? ref : 0);
    } catch (error) {}
    try {
      P.set('.PSearchTo', ((ref1 = opts.query.from) != null ? ref1 : 0) + (((ref2 = opts.response) != null ? (ref3 = ref2.hits) != null ? ref3.hits : void 0 : void 0) != null ? opts.response.hits.hits.length : (ref4 = opts.query.size) != null ? ref4 : 10));
    } catch (error) {}
    try {
      P.html('.PSearches', ''); // TODO and reset any range sliders or check buttons
    } catch (error) {}
    for (f in opts.query.query.bool.filter) {
      filter = opts.query.query.bool.filter[f];
      if (JSON.stringify(filter).indexOf('match_all') === -1) {
        query = JSON.stringify(filter).split(':"').pop().split('}')[0].replace(/"/g, '');
        P.append('.PSearches', '<a class="button PSearchRemove" href="#"><b>X</b> <span class="PSearchVal">' + query + '</span></a>');
      } else if (filter.term) {
        bt = '<a style="margin:5px;" class="button PSearchRemove" href="#"><b>X</b> <span class="PSearchVal">';
        for (k in filter.term) {
          bt += ' ' + k.replace('.keyword', '').split('.').pop() + ':' + filter.term[k];
        }
        P.append('.PSearches', bt + '</span></a>');
      } else if (filter.range) {
        for (kk in filter.range) {
          key = kk.replace('.keyword', '').split('.').pop();
          gte = filter.range[kk].gte;
          lte = filter.range[kk].lte;
        }
      }
    }
    // TODO adjust the relevant range filter sliders on the UI to match the values
    if (opts.query.query.bool.filter.length > 2) {
      P.append('.PSearches', '<a class="button PSearchRemove" href="#">clear all</a>');
    }
    return P.listen('click', '.PSearchRemove', opts.remove);
  };
  opts.results = []; // all resulting records, after transform if present
  opts.result = function(rec) { // a function that draws a given result on the page (can be false to not draw results)
    var headers, i, k, kk, len, nt, re, ref, ref1, t;
    if (Array.isArray(opts.table)) {
      nt = {};
      ref = opts.table;
      for (i = 0, len = ref.length; i < len; i++) {
        t = ref[i];
        nt[t] = '';
      }
      opts.table = nt;
    }
    re = opts.table ? '<tr' : '<p style="word-wrap: break-word; padding:5px; margin-bottom:0px;"';
    re += ' class="PSearchResult PResultFrom' + ((ref1 = opts.query.from) != null ? ref1 : 0) + '">';
    headers = P.html('.PSearchHeaders');
    for (k in (opts.table ? opts.table : rec)) {
      kk = typeof opts.table === 'object' && opts.table[k] ? opts.table[k] : k;
      if (opts.table && headers.indexOf(kk) === -1) {
        P.append('.PSearchHeaders', '<th>' + kk + '</th>');
      }
      re += opts.table ? '<td>' : '<b>' + kk + '</b>: ';
      if (Array.isArray(rec[k])) {
        rec[k] = rec[k].length === 0 ? void 0 : rec[k].length === 1 ? rec[k][0] : typeof rec[k][0] !== 'object' ? rec[k].join(', ') : rec[k];
      }
      if (rec[k]) {
        re += (typeof rec[k] === 'object' ? JSON.stringify(rec[k]) : rec[k]);
      }
      re += opts.table ? '</td>' : ', ';
    }
    re += opts.table ? '</tr>' : '</p>';
    return re;
  };
  opts.transform = false; // an optional function that transforms an individual result
  opts.construct = function(data) {
    var i, len, rec, ref, ref1, results;
    if (data == null) {
      data = JSON.parse(JSON.stringify(opts.response));
    }
    if ((data != null ? (ref = data.hits) != null ? ref.hits : void 0 : void 0) != null) {
      data = data.hits.hits;
    }
    if (opts.paging) {
      if (opts.scroll === false) {
        P.hide('.PSearchResult');
      }
    } else {
      opts.results = [];
      P.html('.PSearchResults', '');
    }
    ref1 = data != null ? data : [];
    results = [];
    for (i = 0, len = ref1.length; i < len; i++) {
      rec = ref1[i];
      rec = typeof opts.transform === 'function' ? opts.transform(rec) : rec._source != null ? rec._source : rec;
      opts.results.push(rec);
      if (typeof opts.result === 'function') {
        results.push(P.append('.PSearchResults', opts.result(rec)));
      } else {
        results.push(void 0);
      }
    }
    return results;
  };
  if (!opts.template && opts.template !== false) {
    // NOTE: TODO sticky is not working yet in this layout
    opts.template = '<div class="container big PSearchDiv"><div' + (opts.sticky ? ' class="sticky"' : '') + '>';
    if (opts.scroll === false) {
      opts.template += '<a href="#" class="button PSearchPrevious" alt="previous" title="previous">&lt;</a>';
    }
    opts.template += '<input style="margin-top:5px;" type="text" class="PSearch big" placeholder="' + opts.msg + '">'; // can add PSuggest to this to trigger suggestions
    if (opts.scroll === false) {
      //opts.template += '<a href="#" class="button PSearchopts" alt="show/hide search options" title="show/hide search options">+</a>'
      opts.template += '<a href="#" class="button PSearchNext" alt="next" title="next">&gt;</a>';
    }
    //opts.template += '<div class="PSuggestions"></div>'
    opts.template += '<div class="PSearches" style="margin-top:5px; margin-bottom:5px;"></div>'; //<div class="PRange"></div>
    opts.template += opts.table ? '<table class="striped"><thead' + (opts.sticky ? ' class="sticky"' : '') + '><tr class="PSearchHeaders"></tr></thead><tbody class="PSearchResults"></tbody></table>' : '<div class="PSearchResults"></div>';
    opts.template += '<div class="PLoading" style="display:none;"><div class="loading big"></div></div>';
    opts.template += '</div></div>';
  }
  if (opts.ui == null) {
    opts.ui = function() {
      var k;
      if (opts.template !== false && !P('.PSearch')) {
        P.append('body', opts.template);
      }
      P.on('focus', '.PSearch', function() {
        try {
          return P.show('.POptions');
        } catch (error) {}
      });
      P.on('enter', '.PSearch', opts.add);
      for (k in opts) {
        if (typeof opts[k] === 'function') {
          // could some of these require click or keyup instead of change? how to tell?
          P.on('change', '.PSearch' + k.substring(0, 1).toUpperCase() + k.substring(1).toLowerCase(), opts[k]);
        }
      }
      if (opts.scroll !== false) {
        opts.scroller();
      }
      try {
        return P.focus('.PSearch');
      } catch (error) {}
    };
  }
  if (typeof opts.ui === 'function') {
    opts.ui();
  }
  for (p in pp = P.params()) {
    if (p !== 'search') {
      opts[p === 'source' ? 'query' : p] = pp[p];
    }
  }
  if (opts.query) {
    if (opts.scroll !== false) {
      delete opts.query.from;
    }
    return opts.search();
  }
};
