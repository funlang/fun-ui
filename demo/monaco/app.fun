// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Offline Monaco editor demo.
//
// Run from the repository root:
//
//     funcmd demo/monaco/app.fun
//
// Ui2Proxy serves index.html, the Monaco bundle, z-data, and the demo
// JavaScript from demo/monaco/www. Nothing is fetched from a CDN, so the
// editor works without network access. The status bar calls fd_info through
// the fun-ui WebSocket bridge.

use '../../fun/lib/lib-ui2-proxy.fun';
use 'lib-winsock.fun';
use 'lib-os.fun';

class EditorDispatcher = FdDispatcher()
  fun fd_info(args)
    result = new [service: 'fun-monaco', status: 'connected'];
  end fun;
end class;

var proxy = Ui2Proxy();
proxy.port = 0;                          // let the OS pick a free port
proxy.jsDir = 'js';                      // fd.js and fun-bridge-ws.js
proxy.wwwDir = 'demo/monaco/www';        // static document root
proxy.page = 'demo/monaco/www/index.html';
proxy.dispatcher = EditorDispatcher();
proxy.autoOpen = true;
proxy.Start();

?. 'fun-ui Monaco editor demo: ' & proxy.Url();
proxy.Run();
