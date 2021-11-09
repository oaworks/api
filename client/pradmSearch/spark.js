P.search.spark = function(opts) {
  var first, values;
  if (opts == null) {
    opts = {};
  }
  if (opts.span == null) {
    opts.span = 300000; // 5 minutes
  }
  if (opts.loop == null) {
    opts.loop = 5000; // every 5 seconds
  }
  if (opts.fill == null) {
    opts.fill = function() {
      return 'steelblue';
    };
  }
  values = {};
  first = true;
  P.search.spark.draw = function(resp) {
    var base, dist, dm, graph, height, id, k, kc, line, mx, results, width, x, y;
// decide how to iterate the response to find all sparks values and draw them
    results = [];
    for (k in resp) {
      kc = k.replace(/[^a-zA-Z0-9]/g, '_');
      id = '#PSearchSpark_' + kc;
      if (!P(id)) {
        values[k] = resp[k];
        if ((base = values[k]).values == null) {
          base.values = new Array(Math.floor(opts.span / opts.loop)).fill(0);
        }
        P.prepend('.PSearchSpark', '<div class="PSearchSparks" id="PSearchSpark_' + kc + '" style="width:100%;height:60px;margin-top:-22px;"></div>');
        width = P(id).width();
        height = P(id).height();
        graph = d3.select(id).append("svg:svg").attr("width", "100%").attr("height", "100%");
        dist = width / values[pid].values.length;
        x = d3.scale.linear().domain([0, values[pid].values.length]).range([
          Math.floor(-dist / 2),
          Math.ceil(width + (dist * 1.5)) // starting point is -5 so the first value doesn't show and slides off the edge as part of the transition
        ]);
        mx = d3.max(values[pid].values);
        if (mx < 10) {
          mx = 10;
        }
        y = d3.scale.linear().domain([mx, 0]).range([0, height]);
        line = d3.svg.line().x(function(d, i) {
          return x(i);
        }).y(function(d) {
          return y(d);
        }).interpolate('basis');
        graph.append("svg:path").attr("d", line(values[pid].values));
        $('.panels').css({
          'border-color': '#4682B4',
          'background-color': 'transparent'
        });
        dm = d3.max(values[pid].values);
        if (values[pid].values.indexOf(dm) === values[pid].values.length) {
          // check if this updates the scale domain on larger data - if it does, flash the border and line colours too, to indicate an increase
          y = d3.scale.linear().domain([dm, 0]).range([0, height]);
          $('#panel_' + kc).css({
            'border-color': 'orange'
          });
        }
        //.attr("fill", 'none')
        graph.selectAll("path").data([values[pid].values]).attr("stroke", opts.fill).style('stroke-width', '1.3px').attr("transform", "translate(" + x(1) + ")").attr("d", line); // apply the new data values ... but the new value is hidden at this point off the right of the canvas
        if (first) {
          first = false;
          results.push(graph.selectAll("path").transition().ease(d3.easeLinear).duration(opts.loop).attr("transform", "translate(" + x(0) + ")").on("end", opts.search)); // start a transition to bring the new value into view // animate a slide to the left back to x(0) pixels to reveal the new value // only do this on the first spark line, no point calling a new search on the end of every one - somehow indicate to main search it is a spark update?
        } else {
          results.push(graph.selectAll("path").transition().ease(d3.easeLinear).duration(opts.loop).attr("transform", "translate(" + x(0) + ")"));
        }
      } else {
        values[k].values.shift();
        results.push(values[k].values.push(resp[k].value));
      }
    }
    return results;
  };
  return P.search.spark.draw();
};
