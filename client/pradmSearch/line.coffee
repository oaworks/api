
# add an option to search query analysis that takes interval: and sets interval to year, month, week, day, hour, minute
# also add interval button(s) to UI so each interval can be selected
# and add a loop button to allow the line chart to auto-load new data (could set loop to true by default if interval is hour or minute)
# would need to alter the query filters to get most recent data e.g must[1] = {range: {createdAt: {gt: (Date.now()-1000)}}}
# add a compare button, depending on interval, to compare to previous X time sections (e.g. for day interval, compare to previous day)
# would need aggs to contain a date_histogram like qr.aggs = logs: {date_histogram: {field: "createdAt", interval: interval}}

# need to alter query range filters based on interval like so:
'''  if interval in ['month', 'year']
    # do nothing, months can go back as long as desired, so should not have any range restrictions
  else if interval is 'week'
    must.pop() while must.length > 1
    must.push {range: {createdAt: {gt: Date.now() - 2592000000}}} # last 30 days?
  else if interval is 'day'
    must.pop() while must.length > 1
    must.push {range: {createdAt: {gt: Date.now() - 604800000}}} # last 7 days
  else if interval is 'hour'
    must.pop() while must.length > 1
  else if interval is 'minute'
    must.pop() while must.length > 1
    must.push {range: {createdAt: {gt: (Date.now()-10800000)}}} # last 3 hours'''


P.search.line = (opts) ->
  opts ?= {}
  opts.period ?= 'days' # can be days hours or minutes
  opts.parseTime ?= d3.timeParse "%d-%b-%y %H%M"
  opts.fill ?= d3.scaleOrdinal d3.schemeCategory10
  opts.intervals ?= ['year', 'month', 'week', 'day', 'hour', 'minute']
  opts.interval ?= 'day'
  opts.loop ?= opts.interval in ['hour', 'minute']
  
  c = '<svg class="PSearchLine"></svg>'
  for i in (if opts.intervals then opts.intervals else [])
    c += '<a class="PSearchLineRange" href="' + i + '">' + i + '</a> '
    P.append 'body', c
  P.attr '.PSearchLine', 'height', '600' # should set relative to parent container
  P.attr '.PSearchLine', 'width', '800' # should set relative to parent container
  
  # when looking at a histogram of given interval, click on a dot should trigger an interval reduction and new range limit
  P.on 'click', '.PSearchLineDot', () -> 
    must[1] = {range: {createdAt: {gt: $(this).attr('val')}}}
    if interval is 'month'
      interval = 'week'
      must[2] = {range: {createdAt: {lt: (parseInt($(this).attr('val')) + 2592000000)}}}
    else if interval is 'week'
      interval = 'day'
      must[2] = {range: {createdAt: {lt: (parseInt($(this).attr('val'))+604800000)}}}
    else if interval is 'day'
      interval = 'hour'
      must.pop() while must.length > 1
    else if interval is 'hour'
      interval = 'minute'
      must[2] = {range: {createdAt: {lt: (parseInt($(this).attr('val'))+3600000)}}}
    qr.aggs.logs.date_histogram.interval = interval
    opts.search()
  
  datasets = {}

  P.search.line.draw = (records, key, append=true) ->
    P.html '.PSearchLine', ''

    # records could be the buckets of a named date_histogram agg?

  	#points = [] # is this a useful way to build result sets for time series?
    #for d in data
    #  text = moment.utc(moment.unix(d.key/1000)).format 'DD/MM/YYYY HHmm'
    #  points.push key: (key ? text), text: text, date: d.key, val: td.doc_count
    #data = points
  
    #key ?= data[0]?.key
    #for ds of datasets
    #  datasets[ds] = if append then (datasets[ds] ? []).concat(data) else if ds is key then data else undefined
    #datasets[key] ?= data

    dates = {}
    data = []
    for r in records
      if r.createdAt
        date = new Date parseInt r.createdAt
        ts = (if date.getDate().toString().length is 1 then '0' else '') + date.getDate() + '-' + ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][date.getMonth()] + '-' + date.getFullYear().toString().substring(2,4)
        ts += if opts.period in ['hours', 'minutes'] then ' ' + date.getHours() + '00' + (if opts.period is 'minutes' then date.getMinutes() else '') else ''
        dates[ts] ?= 0
        dates[ts] += 1
    if not data.length
      data.push(key: parseTime(d), val: dates[d]) for d of dates
    data.sort (a,b) -> return (new Date(a.key)) > (new Date(b.key))
    data = [data] if not Array.isArray data
    # example data
    #data = [{ date: opts.parseTime('24-Apr-07'), close: +93.24 }, { date: opts.parseTime('24-Jul-07'), close: +90.24 }]

    svg = d3.select 'svg.PSearchLine'
    margin = top: 10, right: 5, bottom: 10, left: 45
    width = +svg.attr("width") - margin.left - margin.right
    height = +svg.attr("height") - margin.top - margin.bottom
    g = svg.append("g").attr "transform", "translate(" + margin.left + "," + margin.top + ")"

    x = if data[0]?.date then d3.scaleUtc().rangeRound([0, width]) else d3.scaleLinear().rangeRound [0, width] # scaleTime for local time
    y = d3.scaleLinear().rangeRound [height, 0]

    line = d3.line()
			#.curve(d3.curveCatmullRomOpen) # add this for curved line, or CatmullRom may be better
      .x((d) -> return x d.date ? d.x)
      .y((d) -> return y d.val ? d.y)

    x.domain(d3.extent(data, (d) -> return d.date ? d.x)).range [0, width - margin.left - margin.right]
    y.domain(d3.extent(data, (d) -> return d.val ? d.y)).nice().range [height - margin.top - margin.bottom, 0]

    g.append("g")
      .attr("class", "axis")
      .attr("transform", "translate(0," + y.range()[0] + ")")
      .call d3.axisBottom(x)
      .ticks(10)
      #.tickSize(-(height - margin.top - margin.bottom), 0, 0)
      .tickSizeOuter(0)

    g.append("g")
      .attr("class", "axis")
      .call d3.axisLeft(y)
      .ticks(10)
      #.tickSize(-(width - margin.right - margin.left), 0, 0)
      .tickSizeOuter(0)

    for dd in datasets
      g.append("path")
        .datum(dd) # would just be data if not using datasets
        .attr("class", "line values")
        .attr("d", line)
        #.attr("d", d3.line()
        #             .curve(d3.curveLinear)
        #             .x((d) -> return x d.key)
        #             .y((d) -> return y d.val)
        #)
        .style('fill', 'none')
        .attr("stroke", opts.fill) # had a special case for error graphs of fill #ff0c00
        .style('stroke-width', '1.3px' )
  		
      svg.selectAll("dot")
        .data(dd)
        .enter().append("circle")
        .attr("r", .5) # .5 or 4? was 4 in log line examples
        .attr("cx", (d) -> return x(d.key) + margin.left) # d.key or d.date?
        .attr("cy", (d) -> return y(d.val) + margin.top)
        .attr("class", "PSearchLineDot")
        .attr("stroke", opts.fill)
        .attr("fill", opts.fill)
        .attr("key", (d) -> return d.key ? key ? 'createdAt')
        .attr("val", (d) -> return d.key) # or d.date.valueOf() ?
        .style('cursor', 'pointer' )
        .append("title")
        .text((d) -> return d.val + " at " + d.key) # or on (d.text ? d.date)

  P.search.line.draw()

