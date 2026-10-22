// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-proxy: WebSocket mode. Serves the page and tunnels binary messages
// through a local WebSocket.

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
