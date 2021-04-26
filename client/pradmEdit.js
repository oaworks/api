//a library for managing reading writing and saving of objects
if (this.pradm == null) {
  this.pradm = {};
}

pradm._editStyle = '<style>.pradmChanged { border-color: yellow; box-shadow: 2px 2px 2px 2px yellow; } .pradmSaved { border-color: green; box-shadow: 2px 2px 2px 2px green; } .pradmError { border-color: red; box-shadow: 2px 2px 2px 2px red; } </style>';

pradm._editTimeout;

pradm._editObject;

pradm.edit = function(obj) {
  var _watch;
  pradm.append('body', pradm._editStyle);
  if (obj != null) {
    // could add options to build or populate here
    pradm._editObject = obj;
  } else {
    pradm.save(void 0, false);
  }
  _watch = function(e) {
    var el;
    el = e.target;
    if (pradm._editTimeout != null) {
      clearTimeout(pradm._editTimeout);
    }
    pradm.class(el, 'pradmError', false);
    pradm.class(el, 'pradmSaved', false);
    pradm.class(el, 'pradmChanged');
    if (!pradm.gebi('#pradmSave')) {
      return pradm._editTimeout = setTimeout(pradm.save, 1500);
    }
  };
  pradm.listen('change', '.pradmForm', _watch);
  pradm.listen('keyup', '.pradmForm', _watch);
  if (pradm.gebi('#pradmSave')) {
    return pradm.listen('click', '#pradmSave', function(el) {
      pradm.save();
      return false;
    });
  }
};

pradm.save = function(obj, send) {
  console.log('saving');
  if (obj == null) {
    if (pradm._editObject == null) {
      pradm._editObject = {};
    }
    pradm.each('.pradmSaved', function(el) {
      return pradm.class(el, 'pradmSaved', false);
    });
    pradm.each((send === false ? '.pradmForm' : '.pradmChanged'), function(el) {
      var base, key;
      key = pradm.get(el, 'pradmKey');
      if (key == null) {
        key = pradm.get(el, 'id');
      }
      if (el.getAttribute('type') === 'radio') {
        if ((base = pradm._editObject)[key] == null) {
          base[key] = [];
        }
        return pradm._editObject[key].push(pradm.get(el));
      } else {
        return pradm._editObject[key] = pradm.get(el);
      }
    });
    obj = pradm._editObject;
  }
  if (send !== false) {
    return pradm.ajax(window.location.pathname.replace('.html', ''), {
      data: obj,
      success: function(data) {
        return pradm.each('.pradmChanged', function(el) {
          pradm.class(el, 'pradmChanged', false);
          return pradm.class(el, 'pradmSaved');
        });
      },
      error: function(data) {
        return pradm.each('.pradmChanged', function(el) {
          pradm.class(el, 'pradmChanged', false);
          return pradm.class(el, 'pradmError');
        });
      }
    });
  }
};
