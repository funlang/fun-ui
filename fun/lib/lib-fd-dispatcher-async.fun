########################################
# fun-ui - lib-fd-dispatcher-async
# Copyright (c) 2026 funlang.org
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
########################################
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
