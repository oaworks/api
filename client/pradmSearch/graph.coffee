
P.search.graph = (opts) ->
  opts ?= {}
  P.append 'body', '<svg class="PSearchGraph"></svg>'
  P.attr '.PSearchGraph', 'height', '600' # should set relative to parent container
  P.attr '.PSearchGraph', 'width', '800' # should set relative to parent container
  
  P.search.graph.draw = (resp) ->
    P.html '.PSearchGraph', ''
    keys = ['val'] # range of keys if showing more than one val
    data = [] # build data from search results / aggs - a list of objects with at least key and val
    try
      for dt in resp.aggregations[WHAT?].terms
        data.push key: dt.key, val: dt.doc_count # group?
    catch
      try
        for rec in resp.hits.hits
          for k in keys
            data.push key: k, val: rec[k]
  
    svg = d3.select 'svg.PSearchGraph'
    #margin = top: 100, right: 100, bottom: 30, left: 40
    margin = top: 10, right: 5, bottom: 10, left: 60
    width = +svg.attr("width") - margin.left - margin.right
    height = +svg.attr("height") - margin.top - margin.bottom
    g = svg.append("g").attr "transform", "translate(" + margin.left + "," + margin.top + ")"
		
    x = d3.scaleBand().rangeRound([0, width]).paddingInner 0.1
    #x1 = d3.scaleBand().padding 0.05
    y = d3.scaleLinear().rangeRound [height, 0]

    x.domain data.map (d) -> return d.key
    #x1.domain(keys).rangeRound [0, x.bandwidth()]
    #y.domain([0, d3.max(data, (d) -> return d3.max(keys, (key) -> return d[key]))]).nice()
    y.domain [0, d3.max data, (d) -> return d.val]
    
    opts.fill = if keys.length < 2 then ((d) -> return 'steelblue') else if keys.length < 10 then d3.scaleOrdinal(d3.schemeCategory10) else d3.scaleOrdinal d3.schemeCategory20c

    g.append("g")
      .selectAll("g")
      .data(data)
      #.enter().append("g")
      #.attr("transform", (d) -> return "translate(" + x(d[key]) + ",0)")
      #.selectAll("rect")
      #.data((d) -> return keys.map (key) -> return key: key, val: (d[key] ? 0))
      .enter().append("rect")
      #.attr("x", (d) -> return x1 d.key)
      .attr("x", (d) -> return x d.key)
      .attr("y", (d) -> return y d.val)
      #.attr("width", (d) -> return x1.bandwidth())
      .attr("width", (d) -> return x.bandwidth())
      .attr("height", (d) -> return height - y d.val)
      .attr("fill", opts.fill)
  		#.attr("class","graph bar")
  		#.style('cursor', 'pointer' )
      .append("title")
      .text((d) -> return d.key + "\n" + d.val)

    g.append("g")
      .attr("class", "axis")
      .attr("transform", "translate(0," + height + ")")
      #.call d3.axisBottom(x)

    g.append("g")
      .attr("class", "axis")
      .call d3.axisLeft(y).ticks(10, "s").tickSize(-(width), 0, 0).tickSizeOuter(0)

    legend = g.append("g")
      .attr("font-family", "sans-serif")
      .attr("font-size", 10)
      .attr("text-anchor", "end")
      .selectAll("g")
      .data(keys.slice().reverse())
      .enter().append("g")
      .attr("transform", (d, i) -> return "translate(100," + (-100 + i * 20) + ")")

    legend.append("circle")
      .attr("r", 8)
      .attr("cx", width - 10)
      .attr("cy", 10)
      .attr("fill", opts.fill)
      .attr("stroke", opts.fill)
      .attr("stroke-width", "2px")

    legend.append("text")
      .attr("x", width - 24)
      .attr("y", 9.5)
      .attr("dy", "0.32em")
      .text((d) -> return d)
  
  P.search.graph.draw()

