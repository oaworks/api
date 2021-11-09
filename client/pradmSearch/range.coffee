
P.search.range = (options) ->
  options ?= {}

  # optional options.ranges can take the form of
  options.ranges ?=
    createdAt:
      name: 'Created'
      date:
        value: (date) ->
          # should be a function that customises the provided value into a unix timestamp - NOTE js timestamps are 13 digits, unix are 10, so customise
          date = parseInt(date) if typeof date is 'string'
          dv = Math.floor(date/1000) if date.toString().length > 10
          dv = dv - dv%86400 # also converts to start of current day
          return dv
        display: (date) ->
          # should be a function that customises the customised value for display
          date = parseInt(date) if typeof date is 'string'
          date = date * 1000 if date.toString().length <= 10
          d = new Date date
          dd = d.getDate() + '/' + (d.getMonth()+1) + '/' + d.getFullYear()
          return dd
        submit: (date, max) ->
          # should be a function that converts the values back into the necessary format for submitting on the query
          date = parseInt(date) if typeof date is 'string'
          ds = if date.toString().length <= 10 then date * 1000 else date
          ds += 86400 if max # to make sure we get things created during the max day
          return ds
      step: 86400 # the value that steps the date by required chunk sizes - that is, for a day step on a js timestamp, 86400000ms moves forward one day - on unix timestamp, just 86400 will do for seconds
      min: 1356998400 # min and max could be functions that query a remote - in some cases there could be endpoints that serve the min and max

  if options.ranges
    if not P '.'+options.class+'.range'
      if P '.'+options.class+'.options'
        P.append '.'+options.class+'.options', '<div class="' + options.class + ' range display"></div>'
      else
       obj.append '<div class="' + options.class + ' range display"></div>'

    P.html '.'+options.class+'.range', ''
    
    for r in options.ranges
      step = r.step ? 1
      r.min ?= 946684800
      r.max ?= Math.floor((new Date()).valueOf()/1000) + 86400
      vals = [r.min, r.max]
      try
        for fm in options.query.query.bool.filter
          if fm.range and fm.range[r]
            vals[0] = parseInt(options.query.query.filter[fm].range[r].gte) if options.query.query.filter[fm].range[r].gte
            vals[1] = parseInt(options.query.query.filter[fm].range[r].lte) if options.query.query.filter[fm].range[r].lte
            if r.date?.value
              vals[0] = r.date.value vals[0]
              vals[1] = r.date.value vals[1]
      n = r.name ? r
      low = if r.date?.display then r.date.display(vals[0]) else vals[0]
      high = if r.date?.display then r.date.display(vals[1]) else vals[1]
      ranger = '<div class="col-md-12"><div class="input-group" style="border:1px solid #ccc;border-radius:5px;margin-bottom:3px;"> \
        <div class="input-group-btn"> \
          <button class="rangebutton" style="border:none;border-right:1px solid #ccc;padding-right:5px;cursor:default;width:90px;">' + n + '</button> \
        </div>'
      ranger += '<div style="padding:0px 10px 0px 20px;"><input key="' + r + '" style="width:100%;" class="' + options.class + ' ranger" type="text"/></div>'
      ranger += '</div></div>'
      P.append '.'+options.class+'.range', ranger
      P('.'+options.class+'.ranger').last().slider({ min: options.ranges[r].min, max: options.ranges[r].max, value: vals, step: step, tooltip:'hide' })
      .on('slide', ((e) ->
        low = options.ranges[$(this).attr('key')].date.display(e.value[0]) ? e.value[0]
        P.text '.'+options.class+'.rangelow.'+r, low
        high = options.ranges[P.attr this, 'key'].date.display(e.value[1]) ? e.value[1]
        P.text '.'+options.class+'.rangehigh.'+r, high
        P.attr '.search', 'pre', P.attr '.search', 'placeholder'
        P.attr '.search', 'placeholder', (options.ranges[P.attr this, 'key'].name ? P.attr this, 'key') + ': ' + low + ' to ' + high
      ))
      .on 'slideStop', (e) ->
        low = options.ranges[$(this).attr('key')].date.submit(e.value[0]) ? e.value[0]
        P.attr this, 'val', low
        P.attr this, 'range', 'from'
        options.add undefined, this
        high = options.ranges[P.attr this, 'key'].date.submit(e.value[1], true) ? e.value[1]
        P.attr this, 'val', high
        P.attr this, 'range', 'to'
        options.add undefined, $(this)
        P.attr '.search', 'placeholder', P.attr '.search', 'pre'


