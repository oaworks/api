
#a library for managing reading writing and saving of objects
@pradm ?= {}

pradm._editStyle = '<style>\
  .pradmChanged {
    border-color: yellow;
    box-shadow: 2px 2px 2px 2px yellow;
  }
  .pradmSaved {
    border-color: green;
    box-shadow: 2px 2px 2px 2px green;
  }
  .pradmError {
    border-color: red;
    box-shadow: 2px 2px 2px 2px red;
  }
</style>'
pradm._editTimeout
pradm._editObject
pradm.edit = (obj) ->
  pradm.append 'body', pradm._editStyle
  if obj?
    # could add options to build or populate here
    pradm._editObject = obj
  else
    pradm.save undefined, false
  _watch = (e) ->
    el = e.target
    clearTimeout(pradm._editTimeout) if pradm._editTimeout?
    pradm.class el, 'pradmError', false
    pradm.class el, 'pradmSaved', false
    pradm.class el, 'pradmChanged'
    if not pradm.gebi '#pradmSave'
      pradm._editTimeout = setTimeout pradm.save, 1500
  pradm.listen 'change', '.pradmForm', _watch
  pradm.listen 'keyup', '.pradmForm', _watch
  if pradm.gebi '#pradmSave'
    pradm.listen 'click', '#pradmSave', (el) -> pradm.save(); return false;

pradm.save = (obj, send) ->
  console.log 'saving'
  if not obj?
    pradm._editObject ?= {}
    pradm.each '.pradmSaved', (el) ->
      pradm.class el, 'pradmSaved', false
    pradm.each (if send is false then '.pradmForm' else '.pradmChanged'), (el) ->
      key = pradm.get el, 'pradmKey'
      key ?= pradm.get el, 'id'
      if el.getAttribute('type') is 'radio'
        pradm._editObject[key] ?= []
        pradm._editObject[key].push pradm.get el
      else
        pradm._editObject[key] = pradm.get el
    obj = pradm._editObject
  if send isnt false
    pradm.ajax window.location.pathname.replace('.html', ''), 
      data: obj
      success: (data) ->
        pradm.each '.pradmChanged', (el) -> 
          pradm.class el, 'pradmChanged', false
          pradm.class el, 'pradmSaved'
      error: (data) ->
        pradm.each '.pradmChanged', (el) -> 
          pradm.class el, 'pradmChanged', false
          pradm.class el, 'pradmError'
