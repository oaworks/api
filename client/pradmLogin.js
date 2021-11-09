if (P.service == null) {
  P.service = void 0; // optionally set the name of the service using the login
}

P.oauthRedirectUri = void 0; // this can be set, but if not, current page will be used (whatever is used has to be authorised as a redirect URI with the oauth provider)

P.oauthGoogleClientId = void 0; // this must be provided for oauth to work

P.account = void 0; // set to the account object once retrieved

P.token = function(e) {
  var email, opts;
  try {
    e.preventDefault();
  } catch (error) {}
  P.cookie(false);
  // TODO add a validation of the email val if email not already set?
  if (!(email = P.val('#PEmail'))) {
    P.css('#PEmail', 'border-color', '#f04717');
    P.focus('#PEmail');
    return;
  }
  P.hide('.PEmail');
  P.show('.PLoading');
  P.show('.PToken');
  opts = {
    success: function(data) {
      P.hide('.PLoading');
      P.focus('#PToken');
      return P._loggingin = setInterval(function() {
        if (P.loggedin()) {
          return P.loginSuccess();
        }
      }, 2000);
    },
    data: {
      email: email,
      url: window.location.protocol + '//' + window.location.host + window.location.pathname,
      service: P.service
    }
  };
  return P.ajax('/auth/token', opts);
};

P.loginSuccess = function(data) {
  var ph, ref;
  if (P._loggingin) {
    clearInterval(P._loggingin);
    delete P._loggingin;
  }
  P.hide('.PLogin');
  P.hide('.PLoading');
  P.hide('.PToken');
  if (typeof data === 'object') {
    P.account = data;
    P.cookie(data);
  }
  if (((ref = P.account) != null ? ref.email : void 0) && P('.PWelcome')) {
    ph = P.html('.PWelcome');
    ph = ph.length ? ph + ' ' + P.account.email.split('@')[0] : P.account.email;
    P.html('.PWelcome', ph);
    P.show('.PWelcome');
  }
  if (!P.loginNext && window.location.search.indexOf('next=') !== -1) {
    P.loginNext = decodeURIComponent(window.location.search.split('next=')[1].split('&')[0]);
  } else if (!P.loginNext && window.location.search.startsWith('?next')) {
    P.loginNext = true;
  }
  if (P.loginNext) {
    if (P.loginNext === true) {
      return location.reload();
    } else {
      return window.location = P.loginNext;
    }
  } else {
    try {
      P.show('.PLogout');
      P.on('click', '#PLogout', P.logout);
    } catch (error) {}
    try {
      if (typeof P.afterLogin === 'function') {
        return P.afterLogin();
      }
    } catch (error) {}
  }
};

P.loginError = function(err, xhr) {
  console.log('Login error');
  console.log(err); // and log an error to backend somewhere...
  console.log(xhr); // paradigm API may have xhr.response with a follow-up option such as a way to request access or permission
  if (P._loggingin) {
    clearInterval(P._loggingin);
    delete P._loggingin;
  }
  P.cookie(false);
  P.account = void 0;
  P.hide('.PLoading');
  P.hide('.PToken');
  P.set('#PEmail', '');
  P.set('#PEmail', 'placeholder', 'error, enter your email to try again');
  P.show('.PEmail');
  return P.show('.PLogin');
};

P.login = function(e) {
  var account, k, oauthcookie, opts, p, pt, pts, ref, v;
  try {
    e.preventDefault();
  } catch (error) {}
  opts = {
    success: P.loginSuccess,
    error: P.loginError,
    data: {
      service: P.service
    }
  };
  pt = P.val('#PToken');
  if (window.location.hash.indexOf('access_token=') !== -1) {
    opts.data.oauth = {};
    for (p in pts = window.location.hash.replace('#', '').split('&')) {
      [k, v] = pts[p].split('=');
      opts.data.oauth[k] = v;
    }
    oauthcookie = P.cookie('poauth');
    P.cookie('poauth', false);
  } else if (window.location.hash.replace('#', '').length === 8) {
    opts.data.token = window.location.hash.replace('#', '');
    try {
      window.history.pushState("", "", window.location.pathname);
    } catch (error) {}
  } else if (typeof pt === 'string' && pt.length === 8) {
    opts.data.token = pt;
  } else if (account = P.loggedin()) {
    opts.data.email = account.email;
    opts.data.resume = account.resume;
  }
  if ((opts.data.email && opts.data.resume) || opts.data.hash || opts.data.token || ((ref = opts.data.oauth) != null ? ref.state : void 0) === (oauthcookie != null ? oauthcookie.state : void 0)) {
    P.hide('.PEmail');
    P.hide('.PToken');
    P.show('.PLoading');
    return P.ajax('/auth', opts);
  }
};

P.loggedin = function() {
  var p;
  if (p = P.cookie()) {
    if (typeof p === 'object' && JSON.stringify(p) !== '{}') {
      P.account = p;
    }
  }
  return P.account;
};

P.logout = function(e) {
  var account;
  try {
    e.preventDefault();
  } catch (error) {}
  P.show('.PLoading');
  if (account = P.loggedin()) {
    return P.ajax('/auth/logout?apikey=' + account.apikey, {
      success: function() {
        P.account = void 0;
        P.cookie(false);
        P.hide('.PLoading'); // just in case anything made this visible
        if (P.loginNext === true) {
          return location.reload();
        } else if (P.loginNext) {
          return window.location = P.loginNext;
        } else if (typeof P.afterLogout === 'function') {
          try {
            return P.afterLogout();
          } catch (error) {}
        }
      }
    });
  }
};

P.requestPermission = function() {
  P.hide('.PRequestPermission');
  P.show('.PRequestedPermission');
  return P.ajax('/auth/request');
};

P.ready(function() {
  var grl, loggedin, ref, state;
  try {
    P.on('enter', '#PEmail', P.token);
  } catch (error) {}
  try {
    P.on('keyup', '#PToken', function(e) {
      if (P.val('#PToken').length === 8) {
        return P.login();
      }
    });
  } catch (error) {}
  try {
    P.on('click', '#PRequestPermission', P.requestPermission);
  } catch (error) {}
  try {
    if (P.val('#POauthGoogle').length && P.oauthGoogleClientId) {
      state = Math.random().toString(36).substring(2, 8);
      grl = 'https://accounts.google.com/o/oauth2/v2/auth?response_type=token&include_granted_scopes=true&scope=https://www.googleapis.com/auth/userinfo.email+https://www.googleapis.com/auth/userinfo.profile';
      grl += '&state=' + state + '&redirect_uri=' + ((ref = P.oauthRedirectUri) != null ? ref : window.location.href.split('#')[0].split('?')[0]) + '&client_id=' + P.oauthGoogleClientId;
      P.set('#POauthGoogle', 'href', grl);
      P.on('click', '#POauthGoogle', function() {
        return P.cookie('poauth', {
          state: state
        }, {
          expires: 1
        });
      });
    }
  } catch (error) {}
  loggedin = P.loggedin();
  if (loggedin || (typeof window.location.hash === 'string' && window.location.hash && window.location.hash.replace('#', '').length === 8)) {
    if (loggedin) { // don't go to next if already logged in
      P.loginNext = void 0;
    }
    return P.login(); // will it be worth doing this on every page load, or only those with a login token hash?
  }
});
