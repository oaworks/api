P.command = function(opts) {
  var commands, history, idx, ui;
  if (opts == null) {
    opts = {};
  }
  if (opts.api == null) {
    opts.api = '';
  }
  commands = [];
  P.ajax(opts.api + '/subroutes', {
    success: function(res) {
      return commands = res;
    }
  });
  ui = '<div id="results"></div>';
  ui += '<textarea style="border: none; resize: none;" id="command" placeholder=">"></textarea>';
  ui += '<div id="suggestions"></div>';
  P.css('body', 'height', '100%');
  P.append('body', ui);
  P.focus('#command');
  idx = -1;
  history = [];
  return P.on('keyup', '#command', function(e) {
    var c, command, i, key, len, ref, ref1, results, success;
    P.html('#suggestions', '');
    if ((ref = e.keyCode) === 38 || ref === 40) {
      idx += e.keyCode === 38 && idx > 0 ? -1 : e.keyCode === 40 && idx < history.length ? 1 : 0;
      return P.set('#command', (ref1 = history[idx]) != null ? ref1 : '');
    } else {
      command = P.val('#command').replace('\n', '');
      if (command.includes(' = /')) {
        [key, command] = command.split(' = /');
        command = '/' + command;
      }
      if (e.keyCode === 13) {
        if (history[history.length - 1] !== command) {
          history.push(command);
        }
        idx = history.length;
        P.set('#command', '');
        success = function(res) {
          if (key && (res != null)) {
            window[key] = res;
          }
          P.append('#results', '<pre style="color: black; background: transparent; border: none; border-bottom: 1px dotted #ccc;  margin: 0px; padding: 4px;">' + JSON.stringify(res, '', 2) + '</pre>');
          return window.scrollTo(0, document.body.scrollHeight);
        };
        if (command === 'clear') {
          return P.html('#results', '');
        } else if (command.startsWith('/')) {
          return P.ajax(opts.api + command, {
            success: success
          });
        } else {
          return success(Function('return (' + command + ')')());
        }
      } else if (command && command.startsWith('/')) {
        command = command.replace('/', '');
        results = [];
        for (i = 0, len = commands.length; i < len; i++) {
          c = commands[i];
          if (c.startsWith(command)) {
            results.push(P.append('#suggestions', c + '<br>'));
          } else {
            results.push(void 0);
          }
        }
        return results;
      }
    }
  });
};

P.afterLogin = function() {
  return P.attr('#command', 'placeholder', P.account.email.split('@')[0].split('.')[0] + ' >');
};
