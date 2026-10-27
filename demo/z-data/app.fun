// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Minimal fun-ui + z-data demo.
//
// Run from the repository root:
//
//     funcmd demo/z-data/app.fun
//
// The host serves demo/z-data/index.html over the portable WebSocket
// transport and opens it in the default browser. The page uses z-data for
// rendering and calls the Fun method below with `Fun('greet', ...)`.

use '../../fun/lib/lib-ui2-proxy.fun';
use 'lib-winsock.fun';
use 'lib-os.fun';

class DemoDispatcher = FdDispatcher()
  fun fd_greet(args)
    result = 'Hello, ' & (args[0] or 'world') & '!';
  end fun;
end class;

var proxy = Ui2Proxy();
proxy.port = 0;                          // let the OS pick a free port
proxy.jsDir = 'js';                      // fd.js and fun-bridge-ws.js
proxy.page = 'demo/z-data/index.html';
proxy.dispatcher = DemoDispatcher();
proxy.autoOpen = true;
proxy.Start();

?. 'fun-ui + z-data demo: ' & proxy.Url();
proxy.Run();
