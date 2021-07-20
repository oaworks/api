
P.writer = {}

P.writer.numbering = () ->
  counts = [0]
  currpos = 0
  prevheader = 0
  P 'header', (el) ->
    cls = P.classes el
    if 'ignore' not in cls
      thisheader = el.nodeName.replace /[A-z]/gi, ''
      prevheader = thisheader if prevheader is 0
      hdiff = thisheader - prevheader
      if hdiff > 0
        currpos = counts.push(1) - 1
      else if hdiff is 0
        counts[currpos] = counts[currpos] + 1
      else if hdiff < 0
        pops = 0
        while pops > hdiff
          counts.pop()
          pops = pops - 1
        currpos = currpos + hdiff
        counts[currpos] = counts[currpos] + 1
      prevheader = thisheader
      P.html el, counts.toString().replace(/,/gi,'.') + P.html el


P.writer.toc = (opts) ->
  opts ?= {}
  opts.contents ?= '.contents'
  opts.start ?= 2
  try opts.start = parseInt(opts.start.toLowerCase().replace('h', '')) if typeof opts.start is 'string'
  opts.depth ?= 2
  try opts.depth = parseInt(opts.depth.toLowerCase().replace('h', '')) - opts.start if typeof opts.depth is 'string'
  opts.end ?= opts.start + opts.depth
  opts.offset ?= 70

  toc = '<div class="P_contents" style="font-size:0.9em; overflow-y:auto; height:100%;"><ul>'
  heads = ''
  hs = opts.start
  while hs < opts.end
    heads += (if heads then ',h' else 'h') + hs
    hs++
  counter = 0
  P heads, (el) ->
    counter++
    if 'ignore' not in P.classes el
      header = P.html el
      P.prepend el, '<a name="toc' + counter + '"></a>'
      toc += '<li>'
      spaces = 0
      ms = 2 * (parseInt(el.nodeName.toLowerCase().replace('h','')) - opts.start)
      while spaces < ms
        toc += '&nbsp;'
        spaces++
      toc += '<a class="goto" href="#toc' + counter + '">' + header + '</a></li>';
  P.html opts.contents, toc + '</ul></div>'

  P.on 'click', '.goto', (e) ->
    e.preventDefault()
    window.scrollTo 0, P(P.attr(e.target, 'href').replace('#', '')).offsetTop - opts.offset


P.writer.figures = () ->
  counter = 0
  P '.figure', (el) ->
    P.html el, 'Figure ' + counter++ + ': ' + P.html el


'''
P.writer.refs = (opts) ->
  opts ?= {}
  opts.url ?= '/query/reference/'
  opts.offset ?= 70

  gotoref = (e) ->
    e.preventDefault()
    window.scrollTo 0, P('ref' + P.html(e.target).replace('[','').replace(']','')).offsetTop - opts.offset

  gotocite = (e) ->
    e.preventDefault()
    #window.scrollTo( 0, ($('a:contains([' + $(this).attr('href') + '])', obj).offsetTop - opts.offset) )
    window.scrollTo 0, P('ref' + P.html(e.target).replace('[','').replace(']','')).offsetTop - opts.offset

  writeref = (data, counter, ident, obj) ->
    if data.missing
      reference = '? '
      if obj.attr 'href'
        reference += '<a target="_blank" href="' + obj.attr("href") + '">' + obj.attr("href") + '</a>'
    else 
      reference = ''
      for author in (data.author ? [])
        if author.name
          reference += ', ' if reference.length
          reference += nm
        reference += ' ' if reference.length
      reference += '(' + data.year + ') ' if data.year
      reference += '<br>' if reference.length
      reference += '<b>' + data.title + '</b>' if data.title
      if data.journal
        reference += '<br>'
        reference += ' in <i>' + data.journal + '</i>'
        reference += ' ' + data.journal.volume if data.journal.volume
        reference += ' (' + data.journal.issue + ')' if data.journal.issue
      reference += '<br>' + data.publisher if data.publisher

  	obj.html('[' + counter + ']');
  	obj.attr('alt','#' + ident + ": " + data.title);
  	obj.attr('title','#' + ident + ": " + data.title);
  	obj.addClass('hidden-print');
  	obj.after('<span class="visible-print">[' + counter + ']</span>');

    if data.link
      reference += '<br><a class="hidden-print" target="_blank" href="' + data.link[0].url + '">' + data.link[0].url + '</a>';
      reference += '<span class="visible-print">' + data.link[0].url + '<br>(last accessed 30/09/2015)</span>';

  	var reftab = '<tr class="references">' +
	    '<td style="text-align:right;border:none;"><a class="hidden-print reftocite" alt="^ back to ' + ident +
	    '" title="^ back to ' + ident + '" href="' + counter + '">' + counter +
	    '</a><span class="visible-print">' + counter + '</span></td><td class="theref" style="border:none;"><p>' + reference + '</p></td></tr>';
    $('#reftable').append(reftab)

    $('.reftocite').last().bind('click',backtocite)
  	obj.bind('click', gotoref)

  P.success = (data) ->
    $('.references').append('<table class="table" id="reftable"></table>')
    refs = {}
    for d in data.hits.hits
      refs[d._source.id] = d._source
    counter = 0
    P 'a:contains("#")', (el) ->
      if 'ignore' not in P.classes(el)
        counter++
        ident = P.html(el).replace '#', ''
        rec = refs[ident] ? missing: true
        writeref rec, counter, ident, el

  P.ajax opts.url + (opts.url.indexOf('?') === -1 ? '?' : '&') + 'q=*&size=10000'
'''
