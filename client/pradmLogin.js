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

pradm.getCookie = function(name) {
  var c, i, len, ref;
  if (name == null) {
    name = 'pradm';
  }
  ref = document.cookie.split(';');
  for (i = 0, len = ref.length; i < len; i++) {
    c = ref[i];
    while (c.charAt(0) === ' ') {
      c = c.substring(1);
    }
    if (c.indexOf(name + '=') !== -1) {
      return JSON.parse(decodeURIComponent(c.substring(name.length + 1, c.length)));
    }
  }
  return false;
};

pradm.setCookie = function(name, values, options) {
  var date, ref, text;
  if (name == null) {
    name = 'pradm';
  }
  text = name + '=';
  if (values) {
    text += encodeURIComponent(JSON.stringify(values));
  }
  if (options == null) {
    options = {};
  }
  date = (ref = options.expires) != null ? ref : 180;
  if (typeof date === 'number') {
    date = new Date();
    date.setDate(date.getDate() + options.expires);
  }
  if (date instanceof Date) {
    text += '; expires=' + new Date(date).toUTCString();
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

pradm.token = function(e) {
  var email, opts;
  try {
    e.preventDefault();
  } catch (error) {}
  pradm.removeCookie();
  // TODO add a validation of the email val if email not already set?
  if (!(email = pradm.get('#pradmEmail'))) {
    pradm.css('#pradmEmail', 'border-color', '#f04717');
    pradm.focus('#pradmEmail');
    return;
  }
  pradm.hide('.pradmEmail');
  pradm.show('.pradmLoading');
  pradm.show('.pradmToken');
  opts = {
    success: function(data) {
      pradm.hide('.pradmLoading');
      return pradm.focus('#pradmToken');
    },
    data: {
      email: email,
      url: window.location.protocol + '//' + window.location.host + window.location.pathname,
      service: pradm.service
    }
  };
  return pradm.ajax('/auth/token', opts);
};

pradm.loginSuccess = function(data) {
  var ref;
  pradm.hide('.pradmLogin');
  pradm.hide('.pradmLoading');
  pradm.hide('.pradmToken');
  if (data != null) {
    pradm.account = data;
    pradm.setCookie(void 0, data);
  }
  if (pradm.next || window.location.href.indexOf('next=') !== -1) {
    if (pradm.next === true) {
      return location.reload();
    } else {
      return window.location = (ref = pradm.next) != null ? ref : decodeURIComponent(window.location.href.split('next=')[1].split('&')[0]);
    }
  } else {
    try {
      pradm.show('.pradmLogout');
      return pradm.listen('click', '#pradmLogout', pradm.logout);
    } catch (error) {}
  }
};

pradm.loginError = function(err) {
  console.log(err); // and log an error to backend somewhere...
  pradm.removeCookie();
  pradm.account = void 0;
  pradm.hide('.pradmLoading');
  pradm.hide('.pradmToken');
  pradm.set('#pradmEmail', 'placeholder', 'Login error, please try your email address again');
  pradm.show('.pradmEmail');
  return pradm.show('.pradmLogin');
};

pradm.login = function(e) {
  var account, k, oauthcookie, opts, p, pt, pts, v;
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
  pt = pradm.get('#pradmToken');
  if (window.location.hash.indexOf('access_token=') !== -1) {
    opts.data.oauth = {};
    for (p in pts = window.location.hash.replace('#', '').split('&')) {
      [k, v] = pts[p].split('=');
      opts.data.oauth[k] = v;
    }
    oauthcookie = pradm.getCookie('poauth');
    pradm.removeCookie('poauth');
  } else if (window.location.hash.replace('#', '').length === 8) {
    opts.data.token = window.location.hash.replace('#', '');
    try {
      window.history.pushState("", "", window.location.pathname);
    } catch (error) {}
  } else if (typeof pt === 'string' && pt.length === 8) {
    opts.data.token = pt;
  } else if (account = pradm.loggedin()) {
    opts.data.email = account.email;
    opts.data.resume = account.resume;
  }
  if ((opts.data.email && opts.data.resume) || opts.data.hash || opts.data.token || opts.data.oauth.state === (oauthcookie != null ? oauthcookie.state : void 0)) {
    pradm.hide('.pradmEmail');
    pradm.hide('.pradmToken');
    pradm.show('.pradmLoading');
    return pradm.ajax('/auth', opts);
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
  pradm.removeCookie();
  if (pradm.next) {
    if (pradm.next === true) {
      return location.reload();
    } else {
      return window.location = pradm.next;
    }
  }
};

pradm.listen('enter', '#pradmEmail', pradm.token);

try {
  pradm.listen('keyup', '#pradmToken', function(e) {
    if (pradm.get('#pradmToken').length === 8) {
      return pradm.login();
    }
  });
} catch (error) {}

try {
  if (pradm.get('#pradmOauthGoogle').length && pradm.oauthGoogleClientId) {
    state = Math.random().toString(36).substring(2, 8);
    grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile';
    grl += '&state=' + state + '&redirect_uri=' + ((ref = pradm.oauthRedirectUri) != null ? ref : window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + pradm.oauthGoogleClientId;
    pradm.set('#pradmOauthGoogle', 'href', grl);
    pradm.listen('click', '#pradmOauthGoogle', function() {
      return pradm.setCookie('poauth', {
        state: state
      }, {
        expires: 1
      });
    });
  }
} catch (error) {}

if (pradm.loggedin() || (typeof window.location.hash === 'string' && window.location.hash && window.location.hash.replace('#', '').length === 8)) {
  pradm.login();
}
