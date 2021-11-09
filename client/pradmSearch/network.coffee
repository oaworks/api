# a force directed network graph visualisation

P.search.network = (opts) ->
	opts ?= {}
	# opts.valued can be the key name to pick a particular from a record object 
	# opts.sized can be a key name to pick a size from, or a number to represent the size
	opts.repel ?= 5 # how much force the nodes should repel each other with

	fl = d3.scaleOrdinal d3.schemeCategory20 # 10, 20, 20b, 20c
	opts.fill = (d) -> return fl d.key
	opts.text = opts.label = (d) -> return (if d.val then d.key + ': ' + d.value else d.key) + (if d.size and d.size isnt d.value then ' (' + d.size + ')' else '') # overwrite this one to return text on hover over node (or make it same as above)
	opts.radius = (d) ->
		r = d3.scaleLinear().domain([0, d3.max(opts.nodes, (d,i) -> return d.size)]).range([5, width/12])
		return if not d.size then 0 else r d.size

	P.append 'body', '<svg class="PSearchNetwork"></svg>'
	P.attr '.PSearchNetwork', 'height', '600' # should set relative to parent container
	P.attr '.PSearchNetwork', 'width', '800' # should set relative to parent container
	
	svg = undefined
	g = undefined

	P.search.network.draw = (resp) ->
		opts.nodes = resp.nodes ? []
		opts.links = resp.links ? []
		if not resp.nodes
			for ri in resp.hits.hits # TODO what about when paging backwards, how does it affect the result set?
				rec = ri._source ? ri.fields
				rec.key ?= opts.valued ? 'record'
				rec.val ?= rec[opts.valued] # which value from the record to use as an actual value, if any
				rec.size ?= rec[opts.sized] ? opts.sized ? 1
				opts.nodes.push rec
		
		for a of resp.aggregations ? {}
			agg = resp.aggregations[a]
			for bi in agg.buckets ? agg.terms ? []
				if not resp.links
					for n of opts.nodes
						if (if not Array.isArray(opts.nodes[n].val) then [opts.nodes[n].val] else opts.nodes[n].val).includes bi.key
							opts.links.push  source: opts.nodes.length, target: parseInt n
				if not resp.nodes
					opts.nodes.push key: a, val: bi.key, size: bi.doc_count

		P.html '.PSearchNetwork', ''

		scale = 1
		width = P.attr '.PSearchNetwork', 'width'
		height = P.attr '.PSearchNetwork', 'height'
		svg = d3.select('.PSearchNetwork').append("svg").attr("width", width).attr("height", height).call(d3.zoom().on("zoom", () -> g.attr( "transform", d3.event.transform ); scale = g.attr('transform').split('scale')[1].replace('(','').replace(')','')))
		g = svg.append("g")
		link = g.append("g").selectAll()
		node = g.append("g").selectAll()

		simulation = d3.forceSimulation(opts.nodes)
			.force("charge", d3.forceManyBody().strength(-opts.repel * (width/10)))
			.force("link", d3.forceLink(opts.links).distance(-50 + width/4))
			.force("collide", d3.forceCollide().radius (d) -> return opts.radius(d) * 1.3) #.iterations(5) )
			.force("center", d3.forceCenter(width / 2, height / 2))
			.force("x", d3.forceX())
			.force("y", d3.forceY())
			.on "tick", () ->
				node.attr 'transform', (d) -> return "translate(" + [d.x, d.y] + ")"
				# network scale starts at 1, gets less than 1 as we zoom out, more than 1 as we zoom in
				P.attr '.nodeText', 'font-size', (d) -> return (width * 0.0006 * (if scale < 1 then scale else 1/scale)) + "em"
				link.attr('x1', (d) -> return d.source?.y ? d.target?.y ? d.y)
					.attr('y1', (d) -> return d.source?.y ? d.target?.y ? d.y)
					.attr('x2', (d) -> return d.source?.x ? d.target?.x ? d.x)
					.attr('y2', (d) -> return d.source?.y ? d.target?.y ? d.y)

		node = node.data opts.nodes
		node = node.enter()
			.append("g")
			.on('mouseover', (d) ->
				P.show '.nodeText'
				P.attr '.PSearch', 'pre', P.attr '.PSearch', 'placeholder'
				P.attr '.PSearch', 'placeholder', opts.label d
				link.attr 'stroke', (ld) -> return '#666' if d.index is ld.source.index or d.index is ld.target.index
			)
			.on('mouseout', () ->
				link.attr 'stroke', '#aaa'
				P.hide '.nodeText'
				P.attr '.PSearch', 'placeholder', P.attr '.PSearch', 'pre'
			)
			.on('click', opts.click) # TODO add a class to this that would trigger the normal search action, and add the value etc to the element as expected for a search trigger
			.call(d3.drag()
				.on('start', (d) ->
					simulation.alphaTarget(0.3).restart() if not d3.event.active
					d.fx = d.x
					d.fy = d.y
				)
				.on('drag', (d) ->
					d.fx = d3.event.x
					d.fy = d3.event.y
				)
				.on('end', (d) ->
					simulation.alphaTarget(0) if not d3.event.active
					d.fx = null
					d.fy = null
				))
			.merge(node)
		node
			.append('circle')
			.attr('class', 'node')
			.attr('r', opts.radius)
			.attr('fill', opts.fill)
			.style('cursor', 'pointer')
			.attr('stroke', '#666')
			.attr('stroke-width', 1)
			.append('svg:title').text(opts.label)

		node
			.append('text')
			.classed('nodeText', true)
			.text(opts.text)
			.attr('font-size', () -> return (width * 0.0004 * (1/scale)) + "em")
			#.attr('dx', opts.radius) # offset from center
			.attr('dy', (d) -> return opts.radius(d) * 1.1)

		node.exit().remove()

		link = link.data opts.links
		link.exit().remove()
		link = link.enter().append('line').merge link
		link.attr('class', 'net').attr('stroke', '#aaa').attr('stroke-width', 1)

		simulation.nodes opts.nodes
		simulation.force('link').links opts.links
		simulation.alpha(1).restart()
		P.hide '.nodeText'

	P.search.network.draw()
	
	P.search.network.zoom = (scale) -> # e.g. adjust scale externally from the above network function, to 0.2 for example
		h = P.attr svg, "height"
		w = P.attr svg, "width"
		g.attr "transform", "translate(" + w/2 + ", " + h/2 + ") " + "scale(" + scale + ") " + "translate(" + (-w/2) + ", " + (-h/2) + ")"
