var grl, ref, state;

if (this.pradm == null) {
  this.pradm = {};
}

if (pradm.service == null) {
  pradm.service = void 0; // optionally set the name of the service using the login
}

if (pradm.api == null) {
  pradm.api = window.location.host; // set this elsewhere if not on the current host
}

pradm.oauthRedirectUri = void 0; // this can be set, but if not, current page will be used (whatever is used has to be authorised as a redirect URI with the oauth provider)

pradm.oauthGoogleClientId = void 0; // this must be provided for oauth to work

pradm.account = void 0; // set to the account object once retrieved

pradm.getCookie = function(cname) {
  var c, i, len, ref;
  if (cname == null) {
    cname = 'pradm';
  }
  ref = document.cookie.split(';');
  for (i = 0, len = ref.length; i < len; i++) {
    c = ref[i];
    while (c.charAt(0) === ' ') {
      c = c.substring(1);
    }
    if (c.indexOf(cname + '=') !== -1) {
      return JSON.parse(decodeURIComponent(c.substring(cname.length + 1, c.length)));
    }
  }
  return false;
};

pradm.setCookie = function(name, values, options) {
  var date, text;
  text = name + '=';
  if (values) {
    text += encodeURIComponent(JSON.stringify(values));
  }
  if (options == null) {
    options = {};
  }
  date = options.expires;
  if (typeof date === 'number') {
    date = new Date();
    date.setDate(date.getDate() + options.expires);
  }
  if (date instanceof Date) {
    text += '; expires=' + date.toUTCString();
  }
  if (typeof options.domain === 'string' && options.domain !== '') {
    text += '; domain=' + options.domain;
  }
  text += '; path=' + (typeof options.path === 'string' && options.path !== '' ? options.path : '/');
  if (options.secure !== false) { // default to secure
    text += '; secure';
  }
  if (options.httponly) {
    text += '; HttpOnly';
  }
  document.cookie = text;
  return text;
};

pradm.removeCookie = function(name, domain) {
  return pradm.setCookie(name, void 0, {
    domain: domain,
    expires: -1
  });
};

pradm.ajax = function(url, opts) {
  var base, h, ref, ref1, xhr;
  if (typeof url === 'object') {
    opts = url;
    url = void 0;
  }
  if (url == null) {
    url = (ref = opts.url) != null ? ref : '';
  }
  if (url === '' || url.startsWith('/')) {
    url = pradm.api + url;
  }
  if (opts == null) {
    opts = {};
  }
  if (opts.headers == null) {
    opts.headers = {};
  }
  if (opts.data != null) {
    opts.method = 'POST';
    if (typeof opts.data === 'object' && typeof opts.data.append !== 'function') { // a FormData object will have an append function, a normal json object will not. FormData should be POSTable by xhr as-is
      opts.data = JSON.stringify(opts.data);
      if ((base = opts.headers)['Content-type'] == null) {
        base['Content-type'] = 'application/json';
      }
    }
    url += (url.indexOf('?') === -1 ? '?' : '&') + '_=' + Date.now(); // set a random header to break caching
  }
  xhr = new XMLHttpRequest();
  xhr.open((ref1 = opts.method) != null ? ref1 : 'GET', url);
  for (h in opts.headers) {
    xhr.setRequestHeader(h, headers[h]);
  }
  xhr.send(opts.data);
  xhr.onload = function() { // worth checking xhr.status is 200?
    var err;
    try {
      return opts.success(JSON.parse(xhr.response), xhr);
    } catch (error) {
      err = error;
      try {
        console.log(err);
      } catch (error) {}
      try {
        return opts.error(xhr);
      } catch (error) {}
    }
  };
  return xhr.onerror = function(err) {
    try {
      return opts.error(err);
    } catch (error) {}
  };
};

pradm.token = function(e) {
  var email, opts;
  try {
    e.preventDefault();
  } catch (error) {}
  pradm.removeCookie();
  // TODO add a validation of the email val if email not already set?
  if (!(email = $('#pradmEmail').val())) {
    $('#pradmEmail').css('border-color', '#f04717').focus();
    return;
  }
  $('.pradmLogin').hide();
  $('.pradmLoading').show();
  $('.pradmToken').show();
  opts = {
    success: function(data) {
      $('.pradmLoading').hide();
      return $('#pradmToken').focus();
    },
    data: {
      email: email,
      service: pradm.service
    }
  };
  return pradm.ajax('/auth/token', opts);
};

pradm.loginSuccess = function(data) {
  $('.pradmLoading').hide();
  $('.pradmLogin').hide();
  $('.pradmToken').hide();
  if (data != null) {
    pradm.account = data.account; // prob needs apikey, account, email
    pradm.setCookie(void 0, data.account, data.settings);
  }
  if (window.location.href.indexOf('next=') !== -1) {
    return window.location = decodeURIComponent(window.location.href.split('next=')[1].split('&')[0]);
  } else {
    try {
      $('.pradmLogout').show();
      return $('#pradmLogout').unbind('click').bind('click', pradm.logout);
    } catch (error) {}
  }
};

pradm.loginError = function(err) {
  console.log(err); // and log an error to backend somewhere...
  pradm.removeCookie();
  pradm.account = void 0;
  $('.pradmLoading').hide();
  $('.pradmToken').hide();
  $('#pradmEmail').attr('placeholder', 'Login error, please try your email address again');
  $('#pradmEmail').show();
  return $('.pradmLogin').show();
};

pradm.login = function(e) {
  var account, k, oauthcookie, opts, p, pts, v;
  try {
    e.preventDefault();
  } catch (error) {}
  opts = {
    success: pradm.loginSuccess,
    error: pradm.loginError,
    data: {
      service: pradm.service
    }
  };
  if (window.location.hash.indexOf('access_token=') !== -1) {
    opts.data.oauth = {};
    for (p in pts = window.location.hash.replace('#', '').split('&')) {
      [k, v] = pts[p].split('=');
      opts.data.oauth[k] = v;
    }
    oauthcookie = pradm.getCookie('poauth');
    pradm.removeCookie('poauth');
  } else if (window.location.hash.replace('#', '').length === 21) {
    opts.data.hash = window.location.hash.replace('#', '');
  } else if ($('#pradmToken').val().length === 7) {
    opts.data.token = $('#pradmToken').val();
  } else if (account = pradm.loggedin()) {
    opts.data.email = account.email;
    opts.data.resume = account.resume;
  }
  if ((opts.data.email && opts.data.resume) || opts.data.hash || opts.data.token || opts.data.oauth.state === (oauthcookie != null ? oauthcookie.state : void 0)) {
    $('.pradmEmail').hide();
    $('.pradmToken').hide();
    $('.pradmLoading').show();
    return pradm.ajax('/auth/login', opts);
  }
};

pradm.loggedin = function() {
  if (pradm.account == null) {
    pradm.account = pradm.getCookie();
  }
  return pradm.account;
};

pradm.logout = function(e) {
  var account;
  try {
    e.preventDefault();
  } catch (error) {}
  if (account = pradm.loggedin()) {
    pradm.ajax('/auth/logout' + (pradm.api.indexOf(window.location.host) === -1 ? '?apikey=' + account.apikey : ''));
  }
  pradm.account = void 0;
  return pradm.removeCookie();
};

$('#pradmEmail').unbind('keyup').bind('keyup', function(e) {
  if (e.keyCode === 13) {
    return pradm.token();
  }
});

try {
  $('#pradmToken').unbind('keyup').bind('keyup', function(e) {
    if ($('#pradmToken').val().length === 7) {
      return pradm.login();
    }
  });
} catch (error) {}

if ($('#pradmOauthGoogle').length && pradm.oauthGoogleClientId) {
  state = Math.random().toString(36).substring(2, 8);
  grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile';
  grl += '&state=' + state + '&redirect_uri=' + ((ref = pradm.oauthRedirectUri) != null ? ref : window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + pradm.oauthGoogleClientId;
  $('#pradmOauthGoogle').attr('href', grl).unbind('click').bind('click', function() {
    return pradm.setCookie('poauth', {
      state: state
    }, {
      expires: 1
    });
  });
}

if (pradm.loggedin()) {
  pradm.login();
}
