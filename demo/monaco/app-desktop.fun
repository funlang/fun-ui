// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Monaco demo hosted by the native GTK3 + WebKit2GTK window (Ui2Form on
// Unix) instead of an external browser.
//
// Needs libui2webkitgtk.so from src/prj/lib.webkitgtk/build.sh, or the
// prebuilt host from the release assets.
//
// Run from the repository root:
//
//     funcmd demo/monaco/app-desktop.fun

use '../../fun/lib/lib-ui2-unx.fun';
use 'lib-winsock.fun';
use 'lib-os.fun';

class EditorDispatcher = FdDispatcher()
  fun fd_info(args)
    result = new [service: 'fun-monaco', status: 'connected'];
  end fun;
end class;

var form = Ui2Form();
form.port = 7801;                          // fixed, so the window URL is stable
form.jsDir = 'js';                         // fd.js and fun-bridge-ws.js
form.wwwDir = 'demo/monaco/www';           // static document root
form.page = 'demo/monaco/www/index.html';
form.dispatcher = EditorDispatcher();
form.hostLib = './src/prj/lib.webkitgtk/libui2webkitgtk.so';
form.requireWebview = true;                // fail loudly instead of a browser
form.SetSize(1024, 760);

var port = form.Start();
?. 'fun-ui Monaco (gtk/webkit): ' & form.Url() & ' native=' & form.Native();
if form.Native() then
  form.Run();
else
  raise 'native webview host failed: ' & form.lastError;
end if;
