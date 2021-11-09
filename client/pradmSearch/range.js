P.search.range = function(options) {
  var fm, high, i, j, len, len1, low, n, r, ranger, ref, ref1, ref2, ref3, ref4, ref5, ref6, results, step, vals;
  if (options == null) {
    options = {};
  }
  // optional options.ranges can take the form of
  if (options.ranges == null) {
    options.ranges = {
      createdAt: {
        name: 'Created',
        date: {
          value: function(date) {
            var dv;
            if (typeof date === 'string') {
              // should be a function that customises the provided value into a unix timestamp - NOTE js timestamps are 13 digits, unix are 10, so customise
              date = parseInt(date);
            }
            if (date.toString().length > 10) {
              dv = Math.floor(date / 1000);
            }
            dv = dv - dv % 86400; // also converts to start of current day
            return dv;
          },
          display: function(date) {
            var d, dd;
            if (typeof date === 'string') {
              // should be a function that customises the customised value for display
              date = parseInt(date);
            }
            if (date.toString().length <= 10) {
              date = date * 1000;
            }
            d = new Date(date);
            dd = d.getDate() + '/' + (d.getMonth() + 1) + '/' + d.getFullYear();
            return dd;
          },
          submit: function(date, max) {
            var ds;
            if (typeof date === 'string') {
              // should be a function that converts the values back into the necessary format for submitting on the query
              date = parseInt(date);
            }
            ds = date.toString().length <= 10 ? date * 1000 : date;
            if (max) { // to make sure we get things created during the max day
              ds += 86400;
            }
            return ds;
          }
        },
        step: 86400, // the value that steps the date by required chunk sizes - that is, for a day step on a js timestamp, 86400000ms moves forward one day - on unix timestamp, just 86400 will do for seconds
        min: 1356998400 // min and max could be functions that query a remote - in some cases there could be endpoints that serve the min and max
      }
    };
  }
  if (options.ranges) {
    if (!P('.' + options.class + '.range')) {
      if (P('.' + options.class + '.options')) {
        P.append('.' + options.class + '.options', '<div class="' + options.class + ' range display"></div>');
      } else {
        obj.append('<div class="' + options.class + ' range display"></div>');
      }
    }
    P.html('.' + options.class + '.range', '');
    ref = options.ranges;
    results = [];
    for (i = 0, len = ref.length; i < len; i++) {
      r = ref[i];
      step = (ref1 = r.step) != null ? ref1 : 1;
      if (r.min == null) {
        r.min = 946684800;
      }
      if (r.max == null) {
        r.max = Math.floor((new Date()).valueOf() / 1000) + 86400;
      }
      vals = [r.min, r.max];
      try {
        ref2 = options.query.query.bool.filter;
        for (j = 0, len1 = ref2.length; j < len1; j++) {
          fm = ref2[j];
          if (fm.range && fm.range[r]) {
            if (options.query.query.filter[fm].range[r].gte) {
              vals[0] = parseInt(options.query.query.filter[fm].range[r].gte);
            }
            if (options.query.query.filter[fm].range[r].lte) {
              vals[1] = parseInt(options.query.query.filter[fm].range[r].lte);
            }
            if ((ref3 = r.date) != null ? ref3.value : void 0) {
              vals[0] = r.date.value(vals[0]);
              vals[1] = r.date.value(vals[1]);
            }
          }
        }
      } catch (error) {}
      n = (ref4 = r.name) != null ? ref4 : r;
      low = ((ref5 = r.date) != null ? ref5.display : void 0) ? r.date.display(vals[0]) : vals[0];
      high = ((ref6 = r.date) != null ? ref6.display : void 0) ? r.date.display(vals[1]) : vals[1];
      ranger = '<div class="col-md-12"><div class="input-group" style="border:1px solid #ccc;border-radius:5px;margin-bottom:3px;"> <div class="input-group-btn"> <button class="rangebutton" style="border:none;border-right:1px solid #ccc;padding-right:5px;cursor:default;width:90px;">' + n + '</button> </div>';
      ranger += '<div style="padding:0px 10px 0px 20px;"><input key="' + r + '" style="width:100%;" class="' + options.class + ' ranger" type="text"/></div>';
      ranger += '</div></div>';
      P.append('.' + options.class + '.range', ranger);
      results.push(P('.' + options.class + '.ranger').last().slider({
        min: options.ranges[r].min,
        max: options.ranges[r].max,
        value: vals,
        step: step,
        tooltip: 'hide'
      }).on('slide', (function(e) {
        var ref7, ref8, ref9;
        low = (ref7 = options.ranges[$(this).attr('key')].date.display(e.value[0])) != null ? ref7 : e.value[0];
        P.text('.' + options.class + '.rangelow.' + r, low);
        high = (ref8 = options.ranges[P.attr(this, 'key')].date.display(e.value[1])) != null ? ref8 : e.value[1];
        P.text('.' + options.class + '.rangehigh.' + r, high);
        P.attr('.search', 'pre', P.attr('.search', 'placeholder'));
        return P.attr('.search', 'placeholder', ((ref9 = options.ranges[P.attr(this, 'key')].name) != null ? ref9 : P.attr(this, 'key')) + ': ' + low + ' to ' + high);
      })).on('slideStop', function(e) {
        var ref7, ref8;
        low = (ref7 = options.ranges[$(this).attr('key')].date.submit(e.value[0])) != null ? ref7 : e.value[0];
        P.attr(this, 'val', low);
        P.attr(this, 'range', 'from');
        options.add(void 0, this);
        high = (ref8 = options.ranges[P.attr(this, 'key')].date.submit(e.value[1], true)) != null ? ref8 : e.value[1];
        P.attr(this, 'val', high);
        P.attr(this, 'range', 'to');
        options.add(void 0, $(this));
        return P.attr('.search', 'placeholder', P.attr('.search', 'pre'));
      }));
    }
    return results;
  }
};
