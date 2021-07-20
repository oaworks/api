
#a library for managing reading writing and saving of records
P._editStyle = '<style>\
  .PChanged {
    border-color: yellow;
    box-shadow: 1px 1px 1px 1px yellow;
  }
  .PSaved {
    border-color: green;
    box-shadow: 1px 1px 1px 1px green;
  }
  .PError {
    border-color: red;
    box-shadow: 1px 1px 1px 1px red;
  }
</style>'
P._editTimeout
P._editRecord
P.edit = (opts) ->
  opts ?= {} # goto can be a class or ID to show after submission, or a URL to go to. clear can also be set to true to empty the form, or hide can be true to hide it
  if pe = P '.PSave'
    if not opts.goto
      pa = P.get pe, 'goto'
      pa ?= P.get pe, 'href'
      opts.goto = pa if pa
      if not opts.goto
        opts.goto = '#PThanks'
        opts.clear ?= true
        opts.hide ?= false
  try
    if pf = P '.PForm'
      pf = pf[0] if Array.isArray(pf) or HTMLCollection.prototype.isPrototypeOf(pf) or NodeList.prototype.isPrototypeOf pf
      form = pf.closest 'form'
      opts.url ?= P.get form, 'action'
      opts.method ?= P.get form, 'method'
  opts.url ?= window.location.pathname.replace '.html', ''
  P.append('body', opts.style ? P._editStyle) if opts.style isnt false
  if opts.record?
    # could add opts to build or populate here
    P._editRecord = opts.record
  else
    P.save undefined, false
  _watch = (e) ->
    el = e.target
    clearTimeout(P._editTimeout) if P._editTimeout?
    P.class el, 'PError', false
    P.class el, 'PSaved', false
    P.class el, 'PChanged'
    if not P '.PSave'
      P._editTimeout = setTimeout (() -> P.save(undefined, opts)), 1500
  if P '.PSave'
    P.on 'click', '.PSave', (e) -> return P.save undefined, opts, e
  else if opts.watch isnt false
    P.on 'change', '.PForm', _watch
    P.on 'keyup', '.PForm', _watch

P.save = (rec, opts, e) -> # does this need to be separate?
  if typeof P.validate isnt 'function' or P.validate()
    console.log 'saving'
    P.show '.PLoading'
    if e?
      try
        P.attr e.target, '_content', P.html e.target
        P.html e.target, 'Submitting...'
      try e.preventDefault()
    if not rec?
      P._editRecord ?= {}
      P '.PSaved', (el) ->
        P.class el, 'PSaved', false
      cls = if opts is false then '.PForm' else '.PChanged'
      cls = '.PForm' if cls is '.PChanged' and not P cls
      P cls, (el) ->
        key = P.get el, 'PKey'
        key ?= P.get el, 'id'
        if el.getAttribute('type') is 'radio'
          P._editRecord[key] ?= []
          P._editRecord[key].push P.get el
        else
          pv = P.get el
          if pv is null
            try delete P._editRecord[key]
          else
            P._editRecord[key] = pv
      rec = P._editRecord
    if opts isnt false
      rec._id ?= P._newid
      P.ajax opts.url, 
        method: opts.method
        data: rec # use opts.method and other settings to decide whether to GET or POST or send a form-URL-encoded
        success: (data) ->
          try P.html e.target, P.attr e.target, '_content'
          P.hide '.PLoading'
          if not P._newid and window.location.search.indexOf('?new') isnt -1 or window.location.search.indexOf('&new') isnt -1
            P._newid = data._id
            try window.history.replaceState "","", window.location.pathname.replace '.html', '/' + data._id + '.html?edit'
          P '.PChanged', (el) -> 
            P.class el, 'PChanged', false
            P.class el, 'PSaved'
          if opts.clear
            try P.set '.PForm', ''
          P.hide(e.target.closest('form')) if opts.hide and e?
          if typeof opts.goto is 'function'
            opts.goto()
          else if typeof opts.goto is 'string'
            if opts.goto.startsWith('#') or opts.goto.startsWith('.') and P opts.goto
              P.hide '.PSave'
              P.show opts.goto
              setTimeout (() -> 
                P.hide opts.goto
                P.show '.PSave'
              ), 10000
            else
              window.location = opts.goto
        error: (data) ->
          try P.html e.target, P.attr e.target, '_content'
          P.hide '.PLoading'
          P.show '.PError'
          P '.PChanged', (el) -> 
            P.class el, 'PChanged', false
            P.class el, 'PError'
  return false # always returns false to stop form submitting manually as well
  
P.validate = (form) ->
  if not form? and pf = P '.PForm'
    pf = P.list(pf)[0]
    form = pf.closest 'form'
  if form?
    form = P.list(form)[0]
    res = form.checkValidity()
    return res
  else
    return true
