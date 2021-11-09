var indexOf = [].indexOf;

P.tabulate = function(ls, hide, tc = 'striped bordered') { // convert list of objects to simple html table, nested
  var h, head, headers, i, j, k, l, len, len1, len2, o, obj, t;
  headers = [];
  t = '</tr></thead><tbody>';
  for (i = 0, len = ls.length; i < len; i++) {
    obj = ls[i];
    for (o in obj) {
      if (indexOf.call(headers, o) < 0) {
        headers.push(o);
      }
    }
    t += '<tr>';
    for (j = 0, len1 = headers.length; j < len1; j++) {
      k = headers[j];
      t += '<td>';
      if (Array.isArray(obj[k])) {
        obj[k] = obj[k].length === 0 ? void 0 : obj[k].length === 1 ? obj[k][0] : typeof obj[k][0] !== 'object' ? obj[k].join(', ') : obj[k];
      }
      if (typeof obj[k] === 'object') {
        if (!Array.isArray(obj[k])) {
          obj[k] = [obj[k]];
        }
        t += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;" alt="View more" title="View more">' + obj[k].length + '...</a><pre style="display:none;background:transparent;color:#333;border:none;width:100%;">';
        t += P.tabulate(obj[k], true);
      } else if (obj[k]) {
        t += obj[k];
      }
      t += '</td>';
    }
    t += '</tr>';
  }
  t += '</tbody></table>';
  head = '<tr>';
  for (l = 0, len2 = headers.length; l < len2; l++) {
    h = headers[l];
    head += '<th>' + (h.toUpperCase() === h || h[0].toUpperCase() === h[0] ? h : h[0].toUpperCase() + h.substr(1).toLowerCase()) + '</th>';
  }
  return '<table class="' + tc.trim() + '"' + (hide != null ? ' style="display:none;"' : '') + '><thead>' + head + t;
};

P.search = function(opts) {
  var p, pp;
  if (opts == null) {
    opts = {};
  }
  if (opts.scope == null) {
    opts.scope = 'body'; // can be the ID of a div to append the search element to
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
  if (opts.table == null) {
    opts.table = true; // or could be list of keys such as ['DOI', 'title', 'year', 'ISSN'] or object of keys pointing to display names, or false for non-tabular default layout
  }
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
      if (val.startsWith('opts.')) {
        if (!val.includes(':')) { // print opts config to the search box placeholder
          opts.placeholder(JSON.stringify(P.dot(opts, val.replace('opts.', '')))); // change the opts config to the provided value
        } else {
          k = val.substr(5, val.indexOf(':')).replace(' ', '');
          v = val.substr(val.indexOf(':') + 1).trim();
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
      } else if (val.includes(':') && !val.split(':')[0].includes(' ') && !val.includes('*') && !val.includes('~') && !val.includes(' AND ') && !val.includes(' OR ')) {
        tf = {
          term: {}
        };
        tf.term[val.split(':')[0]] = val.split(':')[1].replace(/"/g, '');
        opts.query.query.bool.filter.push(tf);
        opts.search();
      } else {
        if (opts.fuzzy && !val.includes('*') && !val.includes('~') && !val.includes(':') && !val.includes('"') && !val.includes(' AND ') && !val.includes('OR')) {
          val = val.trim().replace(/\s/g, opts.fuzzy + ' ') + opts.fuzzy;
        }
        opts.query.query.bool.filter.push({
          "query_string": {
            "default_operator": opts.operator,
            "query": val.replace(/"/g, '')
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
    if (P('.PSearchRemove').length <= 2 || P.has(e.target, '.PSearchRemoveAll')) {
      P.html('.PSearches', '');
    } else {
      P.remove(e.target.closest('a'));
    }
    opts.query.query.bool.filter = [];
    delete opts.query.from;
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
    qsf = JSON.stringify(opts.query.query.bool.filter).toLowerCase();
    P('.PSearchVal', function(el) {
      var tf, val, vc;
      try {
        val = P.val(el);
      } catch (error) {}
      try {
        if (val == null) {
          val = P.html(el);
        }
      } catch (error) {}
      if (val) {
        vc = (val.includes(':') ? val.split(':')[1] : val).toLowerCase().replace(/"/g, '');
        if (!qsf.includes(vc)) {
          if (val.includes(':')) {
            tf = {
              term: {}
            };
            tf.term[val.split(':')[0]] = vc;
            return opts.query.query.bool.filter.push(tf);
          } else {
            return opts.query.query.bool.filter.push({
              "query_string": {
                "default_operator": opts.operator,
                "query": val
              }
            });
          }
        }
      }
    });
    ref4 = (ref3 = opts.filters) != null ? ref3 : [];
    for (l = 0, len2 = ref4.length; l < len2; l++) {
      f = ref4[l];
      try {
        if (!qsf.includes(JSON.stringify(f).toLowerCase())) {
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
      ou += !ou.includes('?') ? '?' : !ou.endsWith('&') && !ou.endsWith('?') ? '&' : '';
      opts.url = ou + 'source=' + encodeURIComponent(JSON.stringify(opts.query));
    }
    return opts.query;
  };
  opts.first = true;
  opts.success = function(resp) {
    var ref;
    P.hide('.PLoading');
    P.show('.PSearchResults');
    opts.response = resp;
    if (opts.first) {
      opts.first = false;
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
      if (!opts.paging) {
        P.hide('.PSearchResults');
      }
      P.show('.PLoading');
      if (!opts.first) {
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
    var bt, filter, gte, i, k, key, kk, len, lte, query, ref, ref1, ref2, ref3, ref4, ref5, ws;
    if (opts.pushstate) {
      ws = window.location.search.split('source=')[0];
      if (JSON.stringify(opts.query) !== JSON.stringify(opts.default)) {
        ws += !ws.includes('?') ? '?' : !ws.endsWith('&') ? '&' : '';
        ws += 'source=' + JSON.stringify(opts.query); // url encode this?
      }
      while (ws.endsWith('&') || ws.endsWith('?')) {
        ws = ws.substr(0, ws.length - 1);
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
    if (!opts.paging) {
      P.html('.PSearches', ''); // TODO and reset any range sliders or check buttons
      ref5 = opts.query.query.bool.filter;
      for (i = 0, len = ref5.length; i < len; i++) {
        filter = ref5[i];
        if (JSON.stringify(filter).includes('query_string')) {
          query = JSON.stringify(filter).split(':"').pop().split('}')[0].replace(/"/g, '').replace(/\*$/, '').replace(/\~$/, '');
          P.append('.PSearches', '<a class="button err PSearchRemove" href="#" alt="Remove" title="Remove"><span class="PSearchVal">' + query + '</span></a> ');
        } else if (filter.term) {
          bt = '<a class="button err PSearchRemove" href="#" alt="Remove" title="Remove"><span class="PSearchVal">';
          for (k in filter.term) {
            bt += ' ' + k.replace('.keyword', '').split('.').pop() + ':' + filter.term[k];
          }
          P.append('.PSearches', bt + '</span></a> ');
        } else if (filter.range) {
          for (kk in filter.range) {
            key = kk.replace('.keyword', '').split('.').pop();
            gte = filter.range[kk].gte;
            lte = filter.range[kk].lte;
          }
        }
      }
      // TODO adjust the relevant range filter sliders on the UI to match the values
      if (opts.query.query.bool.filter.length) {
        P.append('.PSearches', '<a class="button err c1 PSearchRemove PSearchRemoveAll" href="#" alt="Remove all" title="Remove all">X</a>');
      }
      return P.on('click', '.PSearchRemove', opts.remove);
    }
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
    for (k in (typeof opts.table === 'object' ? opts.table : rec)) {
      kk = typeof opts.table === 'object' && !Array.isArray(opts.table) && opts.table[k] ? opts.table[k] : k;
      if (opts.table && !headers.includes(kk)) {
        P.append('.PSearchHeaders', '<th>' + kk + '</th>');
      }
      re += opts.table ? '<td>' : '<b>' + kk + '</b>: ';
      if (Array.isArray(rec[k])) {
        rec[k] = rec[k].length === 0 ? void 0 : rec[k].length === 1 ? rec[k][0] : typeof rec[k][0] !== 'object' ? rec[k].join(', ') : rec[k];
      }
      if (typeof rec[k] === 'object') {
        if (!Array.isArray(rec[k])) {
          rec[k] = [rec[k]];
        }
        re += '<a href="#" onclick="if (this.nextSibling.style.display === \'none\') {this.nextSibling.style.display = \'block\'} else {this.nextSibling.style.display = \'none\'}; return false;" alt="View more" title="View more">' + rec[k].length + '...</a>'; //'<pre style="display:none;background:transparent;color:#333;border:none;width:100%;">'
        //re += JSON.stringify(rec[k], undefined, 2) + '</pre>'
        re += P.tabulate(rec[k], true);
      } else if (rec[k]) {
        re += rec[k];
      }
      re += opts.table ? '</td>' : ', ';
    }
    re += opts.table ? '</tr>' : '</p>';
    return re;
  };
  opts.transform = false; // an optional function that transforms an individual result
  opts.construct = function(data) {
    var i, len, rec, ref, ref1, ref2, ref3, results;
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
      rec = typeof opts.transform === 'function' ? opts.transform(rec) : (ref2 = (ref3 = rec._source) != null ? ref3 : rec.fields) != null ? ref2 : rec;
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
    opts.template = '<div class="PSearchDiv"><div class="PSearchControls' + (opts.sticky ? ' sticky' : '') + ' pb5">';
    opts.template += '<div class="tab flex big">';
    if (opts.scroll === false) {
      opts.template += '<a href="#" class="button PSearchPrevious c1" alt="Previous page" title="Previous page">&lt;</a>';
    }
    if (opts.suggest) {
      opts.template += '<select class="PSuggester c1"><option value="" disabled="disabled" selected="selected">&#x2315;</option></select>';
    }
    opts.template += '<input type="text" class="PSearch" placeholder="' + opts.msg + '">';
    if (opts.scroll === false) {
      //opts.template += '<div class="loader big PLoading"><div class="loading"></div></div>'
      //opts.template += '<a class="button cream c1" style="font-size:2.3em;padding:0;" href="#">&#x2315;</a>'
      //opts.template += '<a href="#" class="button PSearchopts" alt="show/hide search options" title="show/hide search options">+</a>'
      opts.template += '<a href="#" class="button PSearchNext c1" alt="Next page" title="Next page">&gt;</a>';
    }
    opts.template += '</div>';
    if (opts.suggest) {
      opts.template += '<div class="PSuggestions"></div>';
    }
    opts.template += '<div class="PSearches tab flex" style="margin-top:-1px;"></div>'; //<div class="PRange"></div>
    opts.template += '</div>';
    opts.template += opts.table ? '<table class="striped bordered' + (false && opts.scope !== 'body' ? ' fixed' : '') + ' PSearchTable"><thead' + (false && opts.sticky ? ' class="sticky"' : '') + '><tr class="PSearchHeaders"></tr></thead><tbody class="PSearchResults"></tbody></table>' : '<div class="PSearchResults"></div>';
    opts.template += '<div class="PLoading" style="display: none; padding-bottom: 100px;"><div class="loading big"></div></div>';
    opts.template += '</div>';
  }
  if (opts.ui == null) {
    opts.ui = function() {
      var k, ref, ref1;
      if (opts.template !== false && !P('.PSearch')) {
        P.append(opts.scope, opts.template);
        P.css('.PSearchControls', 'background-color', (ref = (ref1 = P.css(opts.scope, 'background')) != null ? ref1 : P.css(opts.scope, 'background-color')) != null ? ref : '#FFFFFC');
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
          P.on('change', '.PSearch' + k[0].toUpperCase() + k.substr(1).toLowerCase(), opts[k]);
        }
      }
      if (opts.scroll !== false) {
        opts.scroller();
      }
      try {
        if (!P.mobile()) {
          return P.focus('.PSearch');
        }
      } catch (error) {}
    };
  }
  if (typeof opts.ui === 'function') {
    opts.ui();
  }
  for (p in pp = P.params()) {
    if (p !== 'search') {
      if (p === 'source') {
        opts.first = false;
      }
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
