//a library for managing reading writing and saving of objects
var indexOf = [].indexOf;

P.form = function(opts) {
  var dd, elem, f, field, i, j, k, key, len, len1, mm, ne, pv, ref, ref1, ref2, ref3, ref4, ref5, ref6, today, val, yyyy;
  if (opts == null) {
    opts = {};
  }
  opts.class = 'PForm'; // the class name to give to every form element, which MUST be present
  if (opts.form == null) {
    opts.form = 'body'; // should be ID of the target form area, if there is one
  }
  if (opts.labels == null) {
    opts.labels = false;
  }
  if (!opts.labels && JSON.stringify(opts.fields).indexOf('label') !== -1) {
    opts.labels = true;
  }
  opts.stack = false;
  if ((opts.stack == null) || opts.stack === true) {
    opts.stack = 'c8';
  }
  opts.wrapped = false; //true # wraps the element with the label, otherwise provides label followed by element
  if (opts.thanks == null) {
    opts.thanks = 'Thanks! Your submission has been received.';
  }
  if (typeof opts.thanks === 'string' && opts.thanks.indexOf('PThanks') === -1) {
    opts.thanks = '<p id="PThanks" style="display:none;">' + opts.thanks + '</p>';
  }
  if (opts.stack) {
    P.append(opts.form, '<div id="PStackedForm" class="' + opts.stack + '"></div>');
    opts.form = '#PStackedForm';
  }
  ref1 = (ref = opts.fields) != null ? ref : [];
  for (i = 0, len = ref1.length; i < len; i++) {
    field = ref1[i];
    if (typeof field === 'string') {
      field = {
        name: field
      };
    }
    if (field.id && !field.name) {
      field.name = field.id;
    }
    if (field.name && (pv = P.params(field.name))) { // what about values provided in params for which there are no defined fields? Pass them in hidden elements? How to verify them?
      if (field.values) {
        field.default = pv;
      } else {
        field.value = pv;
      }
    }
    if (field.classes == null) {
      field.classes = [];
    }
    if (typeof field.classes === 'string') {
      field.classes = field.classes.replace(/, /g, ',').split(',');
    }
    if (field.class) {
      if (typeof field.class !== 'string' || field.class.includes(',')) {
        field.classes = typeof field.class === 'string' ? field.class.replace(/, /g, ',').split(',') : field.class;
      } else {
        field.classes.push(field.class);
      }
      delete field.class;
    }
    if ((field.values != null) && !field.type) {
      field.type = 'select';
    }
    if (field.name.toLowerCase() === 'submit') {
      field.type = 'submit';
    }
    if (field.type === 'submit' && !field.value) {
      field.value = 'Submit';
    }
    if (field.type === 'submit') {
      if (indexOf.call(field.classes, 'button') < 0) {
        field.classes.push('button');
      }
      if (indexOf.call(field.classes, 'PSave') < 0) {
        field.classes.push('PSave');
      }
    } else {
      if (ref2 = opts.class, indexOf.call(field.classes, ref2) < 0) {
        field.classes.push(opts.class);
      }
    }
    if (indexOf.call(field.classes, 'stack') < 0 && opts.stack) {
      field.classes.push('stack');
    }
    if (opts.labels && (field.label == null)) {
      field.label = field.type === 'submit' || !field.name ? '' : field.name.substring(0, 1).toUpperCase() + field.name.substring(1);
    }
    if (typeof field.values === 'string') {
      field.values = field.values.replace(/, /g, ',').split(',');
    }
    if (field.values == null) {
      field.values = [];
    }
    if (field.value) {
      field.values.push(field.value);
      delete field.value;
    }
    if (field.min === 'today' || field.max === 'today') { // a convenience for date fields that should be minimum set to today
      today = new Date();
      dd = today.getDate();
      mm = today.getMonth() + 1;
      yyyy = today.getFullYear();
      today = yyyy + '-' + (mm < 10 ? '0' : '') + mm + '-' + (dd < 10 ? '0' : '') + dd; // should prob depend on date formatting...
      if (field.min === 'today') {
        field.min = today;
      }
      if (field.max === 'today') {
        field.max = today;
      }
    }
    // field must have name, type will default to text. 
    // type could be radio, checkbox, hidden, date etc. select and textarea can also be passed as type
    // date falls back to text on incompatible browsers, otherwise gets the default datepicker features that the browser provides
    // if has values, it will default to a select box
    // if has default, that will be the default set value
    // can have id, placeholder, class or classes as well
    // any other key will be assumed to be an attr/value pair
    elem = !field.type ? '<input type="text" ' : (ref3 = field.type) === 'select' || ref3 === 'textarea' ? '<' + field.type : '<input type="' + field.type + '" ';
    if (field.classes && field.classes.length) {
      elem += ' class="' + field.classes.join(' ') + '"';
    }
// TODO if field.date, add something that indicates a date picker is needed for the field - maybe just a class?
    for (f in field) {
      if (f !== 'type' && f !== 'values' && f !== 'default' && f !== 'classes' && f !== 'description') {
        elem += ' ' + f + '="' + field[f] + '"';
      }
    }
    if ((ref4 = field.type) === 'select' || ref4 === 'textarea') {
      elem += '>';
    }
    ref5 = field.values;
    for (j = 0, len1 = ref5.length; j < len1; j++) {
      val = ref5[j];
      if (typeof val !== 'string') { // can be an object with val pointing to tidy name
// will only have one
        for (k in val) {
          key = k;
        }
        val = val[key];
      } else {
        key = val;
      }
      if (field.type === 'textarea') {
        elem += val;
      } else if (field.type === 'select') {
        elem += '<option' + (val !== key ? ' value="' + val + '"' : '') + (val === field.default ? ' selected' : '') + '>' + key + '</option>'; // TODO handle radios, checkboxes
      } else {
        elem += ' value="' + val + '"';
      }
    }
    if ((ref6 = field.type) === 'select' || ref6 === 'textarea') {
      elem += '</' + field.type;
    }
    elem += '>';
    if ((field.label != null) && field.type !== 'hidden') {
      ne = '<label ' + (opts.stack ? ' class="stack"' : '') + 'for="' + field.name + '">' + field.label;
      ne += opts.wrapped ? ' ' + elem + '</label>' : '</label>' + elem;
      elem = ne;
    }
    if (field.description) {
      elem += '<p>' + field.description + '</p>';
    }
    P.append(opts.form, elem);
  }
  if (opts.thanks) {
    return P.append(opts.form, opts.thanks);
  }
};
