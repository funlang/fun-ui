// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-fd-dispatcher-async: runs jCAL handlers on the Fun async scheduler.

use 'lib-fd-dispatcher.fun';
use 'lib-async.fun';

class FdAsyncDispatcher = FdDispatcher()
  var _asyncCmd = nil;

  fun handleCall(msg, fn) ?, 'jCal async'; ?. msg.name;
    result = _asyncCmd and _asyncCmd.exec((self, env) {
      env.args = msg.args;
      env.fn   = fn;
      env.send = _sendRaw;
      result = true;
    }).await((self, env) {
      try
        env.ret = env.fn(env.args);
      except
        env.err = @;
        ?. '$@ @ $@@()'.eval();
      end try;
    }).done((self, env) {
      var res = new [ type: 'jRET', id: msg.id, val: env.ret, err: env.err ];
      var bytes = res.@toJson(0, fd: true);
      if env.send <> nil then ?, ' Ret'; ?. bytes.length();
        env.send(bytes);
      end if;
    }).go();
  end fun;
end class;
