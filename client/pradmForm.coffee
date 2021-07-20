
#a library for managing reading writing and saving of objects
P.form = (opts) ->
  opts ?= {}
  opts.class = 'PForm' # the class name to give to every form element, which MUST be present
  opts.form ?= 'body' # should be ID of the target form area, if there is one
  opts.labels ?= false
  opts.labels = true if not opts.labels and JSON.stringify(opts.fields).indexOf('label') isnt -1
  opts.stack = false
  opts.stack = 'c8' if not opts.stack? or opts.stack is true
  opts.wrapped = false #true # wraps the element with the label, otherwise provides label followed by element
  opts.thanks ?= 'Thanks! Your submission has been received.'
  opts.thanks = '<p id="PThanks" style="display:none;">' + opts.thanks + '</p>' if typeof opts.thanks is 'string' and opts.thanks.indexOf('PThanks') is -1

  if opts.stack
    P.append opts.form, '<div id="PStackedForm" class="' + opts.stack + '"></div>'
    opts.form = '#PStackedForm'

  for field in opts.fields ? []
    field = {name: field} if typeof field is 'string'
    field.name = field.id if field.id and not field.name
    if field.name and pv = P.params field.name # what about values provided in params for which there are no defined fields? Pass them in hidden elements? How to verify them?
      if field.values
        field.default = pv
      else
        field.value = pv
    field.classes ?= []
    field.classes = field.classes.replace(/, /g, ',').split(',') if typeof field.classes is 'string'
    if field.class
      if typeof field.class isnt 'string' or field.class.includes ','
        field.classes = if typeof field.class is 'string' then field.class.replace(/, /g, ',').split(',') else field.class
      else
        field.classes.push field.class
      delete field.class
    field.type = 'select' if field.values? and not field.type
    field.type = 'submit' if field.name.toLowerCase() is 'submit'
    field.value = 'Submit' if field.type is 'submit' and not field.value
    if field.type is 'submit'
      field.classes.push('button') if 'button' not in field.classes
      field.classes.push('PSave') if 'PSave' not in field.classes
    else
      field.classes.push(opts.class) if opts.class not in field.classes
    field.classes.push('stack') if 'stack' not in field.classes and opts.stack
    if opts.labels and not field.label?
      field.label = if field.type is 'submit' or not field.name then '' else field.name.substring(0,1).toUpperCase() + field.name.substring(1)
    field.values = field.values.replace(/, /g, ',').split(',') if typeof field.values is 'string'
    field.values ?= []
    if field.value
      field.values.push field.value
      delete field.value
    if field.min is 'today' or field.max is 'today' # a convenience for date fields that should be minimum set to today
      today = new Date()
      dd = today.getDate()
      mm = today.getMonth() + 1
      yyyy = today.getFullYear()
      today = yyyy + '-' + (if mm < 10 then '0' else '') + mm + '-' + (if dd < 10 then '0' else '') + dd # should prob depend on date formatting...
      field.min = today if field.min is 'today'
      field.max = today if field.max is 'today'
    # field must have name, type will default to text. 
    # type could be radio, checkbox, hidden, date etc. select and textarea can also be passed as type
    # date falls back to text on incompatible browsers, otherwise gets the default datepicker features that the browser provides
    # if has values, it will default to a select box
    # if has default, that will be the default set value
    # can have id, placeholder, class or classes as well
    # any other key will be assumed to be an attr/value pair
    elem = if not field.type then '<input type="text" ' else if field.type in ['select', 'textarea'] then '<' + field.type else '<input type="' + field.type + '" '
    if field.classes and field.classes.length
      elem += ' class="' + field.classes.join(' ') + '"'
    # TODO if field.date, add something that indicates a date picker is needed for the field - maybe just a class?
    for f of field
      if f not in ['type', 'values', 'default', 'classes', 'description']
        elem += ' ' + f + '="' + field[f] + '"'
    elem += '>' if field.type in ['select', 'textarea']
    for val in field.values
      if typeof val isnt 'string' # can be an object with val pointing to tidy name
        for k of val # will only have one
          key = k
        val = val[key]
      else
        key = val
      if field.type is 'textarea'
        elem += val
      else if field.type is 'select'
        elem += '<option' + (if val isnt key then ' value="' + val + '"' else '') + (if val is field.default then ' selected' else '') + '>' + key + '</option>'
      else # TODO handle radios, checkboxes
        elem += ' value="' + val + '"'
    elem += '</' + field.type if field.type in ['select', 'textarea']
    elem += '>'
    if field.label? and field.type isnt 'hidden'
      ne = '<label ' + (if opts.stack then ' class="stack"' else '') + 'for="' + field.name + '">' + field.label
      ne += if opts.wrapped then ' ' + elem + '</label>' else '</label>' + elem
      elem = ne
    if field.description
      elem += '<p>' + field.description + '</p>'
    P.append opts.form, elem
  P.append(opts.form, opts.thanks) if opts.thanks

