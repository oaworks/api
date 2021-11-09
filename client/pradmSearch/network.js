// a force directed network graph visualisation
P.search.network = function(opts) {
  var fl, g, svg;
  if (opts == null) {
    opts = {};
  }
  // opts.valued can be the key name to pick a particular from a record object 
  // opts.sized can be a key name to pick a size from, or a number to represent the size
  if (opts.repel == null) {
    opts.repel = 5; // how much force the nodes should repel each other with
  }
  fl = d3.scaleOrdinal(d3.schemeCategory20); // 10, 20, 20b, 20c
  opts.fill = function(d) {
    return fl(d.key);
  };
  opts.text = opts.label = function(d) {
    return (d.val ? d.key + ': ' + d.value : d.key) + (d.size && d.size !== d.value ? ' (' + d.size + ')' : ''); // overwrite this one to return text on hover over node (or make it same as above)
  };
  opts.radius = function(d) {
    var r;
    r = d3.scaleLinear().domain([
      0,
      d3.max(opts.nodes,
      function(d,
      i) {
        return d.size;
      })
    ]).range([5, width / 12]);
    if (!d.size) {
      return 0;
    } else {
      return r(d.size);
    }
  };
  P.append('body', '<svg class="PSearchNetwork"></svg>');
  P.attr('.PSearchNetwork', 'height', '600'); // should set relative to parent container
  P.attr('.PSearchNetwork', 'width', '800'); // should set relative to parent container
  svg = void 0;
  g = void 0;
  P.search.network.draw = function(resp) {
    var a, agg, bi, height, j, k, len, len1, link, n, node, rec, ref, ref1, ref10, ref2, ref3, ref4, ref5, ref6, ref7, ref8, ref9, ri, scale, simulation, width;
    opts.nodes = (ref = resp.nodes) != null ? ref : [];
    opts.links = (ref1 = resp.links) != null ? ref1 : [];
    if (!resp.nodes) {
      ref2 = resp.hits.hits;
      // TODO what about when paging backwards, how does it affect the result set?
      for (j = 0, len = ref2.length; j < len; j++) {
        ri = ref2[j];
        rec = (ref3 = ri._source) != null ? ref3 : ri.fields;
        if (rec.key == null) {
          rec.key = (ref4 = opts.valued) != null ? ref4 : 'record';
        }
        if (rec.val == null) {
          rec.val = rec[opts.valued];
        }
        if (rec.size == null) {
          rec.size = (ref5 = (ref6 = rec[opts.sized]) != null ? ref6 : opts.sized) != null ? ref5 : 1;
        }
        opts.nodes.push(rec);
      }
    }
    for (a in (ref7 = resp.aggregations) != null ? ref7 : {}) {
      agg = resp.aggregations[a];
      ref10 = (ref8 = (ref9 = agg.buckets) != null ? ref9 : agg.terms) != null ? ref8 : [];
      for (k = 0, len1 = ref10.length; k < len1; k++) {
        bi = ref10[k];
        if (!resp.links) {
          for (n in opts.nodes) {
            if ((!Array.isArray(opts.nodes[n].val) ? [opts.nodes[n].val] : opts.nodes[n].val).includes(bi.key)) {
              opts.links.push({
                source: opts.nodes.length,
                target: parseInt(n)
              });
            }
          }
        }
        if (!resp.nodes) {
          opts.nodes.push({
            key: a,
            val: bi.key,
            size: bi.doc_count
          });
        }
      }
    }
    P.html('.PSearchNetwork', '');
    scale = 1;
    width = P.attr('.PSearchNetwork', 'width');
    height = P.attr('.PSearchNetwork', 'height');
    svg = d3.select('.PSearchNetwork').append("svg").attr("width", width).attr("height", height).call(d3.zoom().on("zoom", function() {
      g.attr("transform", d3.event.transform);
      return scale = g.attr('transform').split('scale')[1].replace('(', '').replace(')', '');
    }));
    g = svg.append("g");
    link = g.append("g").selectAll();
    node = g.append("g").selectAll();
    simulation = d3.forceSimulation(opts.nodes).force("charge", d3.forceManyBody().strength(-opts.repel * (width / 10))).force("link", d3.forceLink(opts.links).distance(-50 + width / 4)).force("collide", d3.forceCollide().radius(function(d) {
      return opts.radius(d) * 1.3; //.iterations(5) )
    })).force("center", d3.forceCenter(width / 2, height / 2)).force("x", d3.forceX()).force("y", d3.forceY()).on("tick", function() {
      node.attr('transform', function(d) {
        return "translate(" + [d.x, d.y] + ")";
      });
      // network scale starts at 1, gets less than 1 as we zoom out, more than 1 as we zoom in
      P.attr('.nodeText', 'font-size', function(d) {
        return (width * 0.0006 * (scale < 1 ? scale : 1 / scale)) + "em";
      });
      return link.attr('x1', function(d) {
        var ref11, ref12, ref13, ref14;
        return (ref11 = (ref12 = (ref13 = d.source) != null ? ref13.y : void 0) != null ? ref12 : (ref14 = d.target) != null ? ref14.y : void 0) != null ? ref11 : d.y;
      }).attr('y1', function(d) {
        var ref11, ref12, ref13, ref14;
        return (ref11 = (ref12 = (ref13 = d.source) != null ? ref13.y : void 0) != null ? ref12 : (ref14 = d.target) != null ? ref14.y : void 0) != null ? ref11 : d.y;
      }).attr('x2', function(d) {
        var ref11, ref12, ref13, ref14;
        return (ref11 = (ref12 = (ref13 = d.source) != null ? ref13.x : void 0) != null ? ref12 : (ref14 = d.target) != null ? ref14.x : void 0) != null ? ref11 : d.x;
      }).attr('y2', function(d) {
        var ref11, ref12, ref13, ref14;
        return (ref11 = (ref12 = (ref13 = d.source) != null ? ref13.y : void 0) != null ? ref12 : (ref14 = d.target) != null ? ref14.y : void 0) != null ? ref11 : d.y;
      });
    });
    node = node.data(opts.nodes);
    node = node.enter().append("g").on('mouseover', function(d) {
      P.show('.nodeText');
      P.attr('.PSearch', 'pre', P.attr('.PSearch', 'placeholder'));
      P.attr('.PSearch', 'placeholder', opts.label(d));
      return link.attr('stroke', function(ld) {
        if (d.index === ld.source.index || d.index === ld.target.index) {
          return '#666';
        }
      });
    }).on('mouseout', function() {
      link.attr('stroke', '#aaa');
      P.hide('.nodeText');
      return P.attr('.PSearch', 'placeholder', P.attr('.PSearch', 'pre'));
    }).on('click', opts.click).call(d3.drag().on('start', function(d) { // TODO add a class to this that would trigger the normal search action, and add the value etc to the element as expected for a search trigger
      if (!d3.event.active) {
        simulation.alphaTarget(0.3).restart();
      }
      d.fx = d.x;
      return d.fy = d.y;
    }).on('drag', function(d) {
      d.fx = d3.event.x;
      return d.fy = d3.event.y;
    }).on('end', function(d) {
      if (!d3.event.active) {
        simulation.alphaTarget(0);
      }
      d.fx = null;
      return d.fy = null;
    })).merge(node);
    node.append('circle').attr('class', 'node').attr('r', opts.radius).attr('fill', opts.fill).style('cursor', 'pointer').attr('stroke', '#666').attr('stroke-width', 1).append('svg:title').text(opts.label);
    node.append('text').classed('nodeText', true).text(opts.text).attr('font-size', function() {
      return (width * 0.0004 * (1 / scale)) + "em";
    //.attr('dx', opts.radius) # offset from center
    }).attr('dy', function(d) {
      return opts.radius(d) * 1.1;
    });
    node.exit().remove();
    link = link.data(opts.links);
    link.exit().remove();
    link = link.enter().append('line').merge(link);
    link.attr('class', 'net').attr('stroke', '#aaa').attr('stroke-width', 1);
    simulation.nodes(opts.nodes);
    simulation.force('link').links(opts.links);
    simulation.alpha(1).restart();
    return P.hide('.nodeText');
  };
  P.search.network.draw();
  return P.search.network.zoom = function(scale) { // e.g. adjust scale externally from the above network function, to 0.2 for example
    var h, w;
    h = P.attr(svg, "height");
    w = P.attr(svg, "width");
    return g.attr("transform", "translate(" + w / 2 + ", " + h / 2 + ") " + "scale(" + scale + ") " + "translate(" + (-w / 2) + ", " + (-h / 2) + ")");
  };
};
