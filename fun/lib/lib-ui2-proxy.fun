########################################
# fun-ui - lib-ui2-proxy
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
use 'lib-ui2.fun';
use 'lib-ajax.fun';
use 'lib-winsock.fun';

var @proxyIP;
var @proxyPort = 8278;

class Ui2Proxy = Ui2Form()
  var _wsClient;
  var _WM_WS = 0x777;

  fun onReady()
    var self = this;

    var httpUrl = 'http://' & @proxyIP & ':' & @proxyPort; ?. httpUrl;

    _wsClient = Server.HTTP(@proxyIP, @proxyPort,
      fun(req, header, body, sock, ws) {
        if ws and body <> nil and body <> '' then
          if body.length() >= 4 then
            var len = body[0.1] bit or (body[1.1] << 8) bit or
                     (body[2.1] << 16) bit or (body[3.1] << 24);
            if len > 0 then
              self.PostData(body.substr(4));
            end if;
          end if;
        end if;
      });

    _wsClient.Connect(self.main.hWnd, _WM_WS, fun() {
      _wsClient.SendWebSocketRequest('/', nil);

      var s = '' & Ajax().get(httpUrl);
      Navigate(s);
    });
  end fun;

  fun onBinary(data)
    if _wsClient <> nil then
      _wsClient.Reply(int2str(data.length()) & data, 0, [bin: true]);
    end if;
    base.onBinary(data);
  end fun;

  fun onMessage(hwnd, message, wParam, lParam)
    if message = _WM_WS then
      if _wsClient <> nil then
        _wsClient.OnMessage(hwnd, message, wParam, lParam);
      end if;
      return true;
    end if;
    return base.onMessage(hwnd, message, wParam, lParam);
  end fun;

  fun OnClose()
    if _wsClient <> nil then
      _wsClient.Stop(); ?. 'ws stopped.';
      _wsClient = nil;
    end if;
    base.OnClose();
  end fun;
end class;
