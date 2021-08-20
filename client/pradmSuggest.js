P.suggest = function(opts, scope) {
  if (opts == null) {
    opts = {};
  }
  if (opts.scope == null) {
    opts.scope = scope != null ? scope : '';
  }
  if (opts.scope && !opts.scope.endsWith(' ')) {
    opts.scope += ' ';
  }
  if (opts.query == null) {
    opts.query = false; // opts.query can be set to true or to an ES default query, otherwise the search string is just appended to the url
  }
  if (opts.fuzzy == null) {
    opts.fuzzy = '*';
  }
  //opts.key = 'name' # this can be set to the key from a result object to find the display value in, otherwise it looks for defaults [title, name, DOI, _id, value]
  //opts.include = ['_id'] # optionally define to provide objects in return, including the specified keys (and the suggest key)
  // option to provide vals list instead of remote query worthwhile?
  if (opts.counts == null) {
    opts.counts = true; // shows counts from ES aggs in suggestion string (if available)
  }
  //opts.url =  '' # provide a search endpoint URL compatible with 7.x versions of ES - can also be provided on the element, and that's how to do it for multiple elements
  if (opts.suggestion == null) {
    opts.suggestion = function(e, val, rec, cls) {}; // customise this function to do whatever is the preferred action on clicking a suggestion (it will already clear the suggestions and fill the box)
  }
  // e is the event, val is the suggestion value that was selected, rec is the corresponding record if there was one, cls is the classname to group by if there is more than one suggester on the page
  if (opts.terms == null) {
    opts.terms = [];
  }
  P.suggesting = false;
  opts.suggestions = function(e) {
    var agg, c, cls, i, len, o, q, ref, ref1, ref2, str, su, url;
    try {
      e.preventDefault();
    } catch (error) {}
    url = (ref = (ref1 = P.attr(e.target, 'url')) != null ? ref1 : opts.url) != null ? ref : window.location.href.split('?')[0].replace('.html', '');
    ref2 = P.classes(e.target);
    for (i = 0, len = ref2.length; i < len; i++) {
      c = ref2[i];
      if (c.startsWith('PFor')) {
        cls = c;
      }
    }
    str = P.val(e.target);
    if (str) {
      str = str.trim();
    }
    if (str && (!opts.starter || !str.startsWith(opts.starter))) { // no point searching if term is same, or still adding to a term that already returned nothing
      P.suggesting = true;
      agg = P.attr(e.target, 'agg');
      if (opts.query || agg) {
        q = typeof opts.query === 'object' ? JSON.parse(JSON.stringify(opts.query)) : {
          query: {
            bool: {
              filter: []
            }
          }
        };
        if (opts.query && opts.fuzzy && str.indexOf('*') === -1 && str.indexOf('~') === -1 && str.indexOf(':') === -1 && str.indexOf('"') === -1 && str.indexOf('AND') === -1 && str.indexOf('OR') === -1) {
          str = (opts.fuzzy === '*' ? '*' : '') + str.trim().replace(/\s/g, opts.fuzzy + ' ' + (opts.fuzzy === '*' ? '*' : '')) + opts.fuzzy;
        }
        q.query.bool.filter.push({
          "query_string": {
            "query": str
          }
        });
        if (agg && !q.aggregations) {
          if (q.size == null) {
            q.size = 0;
          }
          q.aggregations = {};
          q.aggregations[agg] = {
            terms: {
              field: agg,
              size: 100
            }
          };
        }
      }
      su = url + (!opts.query ? str : opts.method === 'POST' ? '' : '?source=' + JSON.stringify(q));
      if (opts.include) {
        su += (su.includes('?') ? '&' : '?') + 'include=' + (typeof opts.include === 'string' ? opts.include : opts.include.join(','));
      }
      o = {
        url: su,
        success: (data) => {
          P.suggesting = false;
          P.html(opts.scope + '.PSuggestions ' + (cls != null ? cls : ''), '');
          return opts.suggest(data, cls);
        }
      };
      if (opts.method === 'POST' && opts.query) {
        o.data = q;
      }
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
      return P.ajax(o);
    } else if (!str) {
      return P.html(opts.scope + '.PSuggestions ' + (cls != null ? cls : ''), '');
    } else {
      return opts.starter = str;
    }
  };
  P.on('keyup', opts.scope + '.PSuggest', opts.suggestions, 800);
  opts.suggest = function(data, cls) {
    var agg, clsn, counter, da, i, k, len, ref, ref1, ref2, ref3, ref4, results, results1;
    cls = opts.scope + '.PSuggestions' + (cls ? ' ' + cls.replace('.', '') : '');
    clsn = cls.replace('.PSuggestions', 'PSuggestion');
    if ((!Array.isArray(data) && (data != null ? data.aggregations : void 0)) || (Array.isArray(data) && data.length && (data[0].doc_count != null))) {
      da = Array.isArray(data) ? data : data.aggregations;
      results = [];
      for (agg in da) {
        results.push((function() {
          var i, len, ref, ref1, results1;
          ref1 = (ref = da[agg].buckets) != null ? ref : [];
          results1 = [];
          for (i = 0, len = ref1.length; i < len; i++) {
            k = ref1[i];
            results1.push(P.append(cls, '<a class="' + clsn + '" href="' + k.key + '" key="' + agg('">' + k.key + '</a>' + (opts.counts && k.doc_count > 1 ? ' (' + k.doc_count + ')' : '') + '<br>')));
          }
          return results1;
        })());
      }
      return results;
    } else {
      opts._data = [];
      counter = 0;
      ref2 = (Array.isArray(data) ? data : (ref = data != null ? (ref1 = data.hits) != null ? ref1.hits : void 0 : void 0) != null ? ref : []);
      results1 = [];
      for (i = 0, len = ref2.length; i < len; i++) {
        k = ref2[i];
        if (typeof k === 'string') {
          P.append(cls, '<a class="' + clsn + '" href="' + k + '">' + k + '</a><br>');
        } else {
          if (k._source) {
            k = k._source;
          }
          if (opts.key == null) {
            opts.key = k.title ? 'title' : k.name ? 'name' : k.DOI ? 'DOI' : k._id ? '_id' : k.value ? 'value' : void 0;
          }
          P.append(cls, '<a class="' + clsn + '" href="' + ((ref3 = k[opts.key]) != null ? ref3 : '#') + '" key="' + counter + '">' + ((ref4 = k[opts.key]) != null ? ref4 : JSON.stringify(k)) + '</a><br>');
        }
        opts._data.push(k);
        results1.push(counter += 1);
      }
      return results1;
    }
  };
  return P.on('click', opts.scope + '.PSuggestion', function(e) {
    var c, cls, i, len, ref, ref1, val;
    try {
      e.preventDefault();
    } catch (error) {}
    ref = P.classes(e.target);
    for (i = 0, len = ref.length; i < len; i++) {
      c = ref[i];
      if (c.startsWith('PFor')) {
        cls = c;
      }
    }
    P.html(opts.scope + '.PSuggestions ' + (cls != null ? cls : ''), '');
    val = P.attr(e.target, 'href');
    P.set('.PSuggest ' + (cls != null ? cls : ''), val);
    // TODO if on a pradm search context, should be putting the val in the search box and trigger it?
    return opts.suggestion(e, val, (ref1 = opts._data) != null ? ref1[P.attr(e.target, 'key')] : void 0, cls);
  }, 800);
};
