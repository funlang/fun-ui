// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-unx / WebKitGTK host: headless native-window smoke test.
//
// Requirement: Linux with gtk+-3.0 and webkit2gtk-4.x, a display (Xvfb is
// fine), and the host library built by src/prj/lib.webkitgtk/build.sh.
//
//     src/prj/lib.webkitgtk/build.sh
//     xvfb-run -a -s "-screen 0 1280x1024x24" \
//       dbus-run-session -- funcmd test/lib-ui2-webview-lnx-test.fun
//
// The page loaded in the native WebKit view calls Fun('native_ready'). The
// dispatcher flips a flag, and the loop stops as soon as it sees the call.
// This verifies the whole path: GTK window, WebKit page load, injected
// bridge, WebSocket transport, dispatcher, and jRET.

use '../fun/lib/lib-ui2-unx.fun';

var @ready = false;

class TestDispatcher = FdDispatcher()
  fun fd_native_ready(args)
    @ready = true;
    result = new [ok: true];
  end fun;
end class;

var @ui2webkitdll = './src/prj/lib.webkitgtk/libui2webkitgtk.so';
var @ui2RequireWebview = true;

var PAGE = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>webview-test</title></head>
<body>
<h1>native webview</h1>
<script>
window.addEventListener('load', function () {
  Fun('native_ready', { from: 'page' }).then(function (v) {
    console.log('native_ready returned', v);
  }).catch(function (e) {
    console.error('native_ready failed', e);
  });
});
</script>
</body>
</html>`;

var form = Ui2Form();
form.port = 0;
form.jsDir = 'js';
form.page = PAGE;
form.dispatcher = TestDispatcher();
form.SetSize(800, 600);

var port = form.Start();
var native = form.Native();

// WebKit starts its web process asynchronously; give it a generous budget.
for i = 1 to 2000 do
  exit when @ready;
  form.RunOnce(10);
end do;

form.Stop();

?. 'bound port: ' & (port > 0);
?. 'native window: ' & native;
?. 'page callback: ' & @ready;
if native and @ready then
  ?. 'RESULT: OK';
else
  ?. 'RESULT: FAIL';
  raise 'native window test failed: native=' & native & ', ready=' & @ready;
end if;
