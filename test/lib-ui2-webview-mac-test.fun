// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-unx / WKWebView host: native-window smoke test for macOS.
//
// Requirement: macOS with the host library built by
// src/prj/lib.wkwebview/build.sh. Run from the fun-ui repository root:
//
//     src/prj/lib.wkwebview/build.sh
//     funcmd test/lib-ui2-webview-mac-test.fun
//
// The page loaded in the WKWebView calls Fun('native_ready'). The dispatcher
// flips a flag, and the loop stops as soon as it sees the call. This verifies
// the whole path: AppKit window, WKWebView page load, injected bridge,
// WebSocket transport, dispatcher, and jRET. Progress is written to
// /tmp/ui2-mac-progress.txt for CI diagnostics.

use '../fun/lib/lib-ui2-unx.fun';

var @ready = false;

var PROGRESS = '/tmp/ui2-mac-progress.txt';

fun mark(s)
  PROGRESS.save('' & s & 10.toChar(), append: true);
end fun;

PROGRESS.save('', append: false);
mark('test loaded');

class TestDispatcher = FdDispatcher()
  fun fd_native_ready(args)
    @ready = true;
    mark('native_ready received');
    result = new [ok: true];
  end fun;
end class;

var PAGE = `<!doctype html>
<html>
<head><meta charset="utf-8"><title>mac-webview-test</title></head>
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
form.hostLib = './src/prj/lib.wkwebview/libui2wkwebview.dylib';
form.requireWebview = true;
form.traceFile = PROGRESS;

mark('before Start');
var port = form.Start();
var native = form.Native();
mark('after Start, native=' & native & ', port=' & port & ', error=' & form.lastError);

// WebKit starts its web process asynchronously; give it a generous budget.
try
  for i = 1 to 2000 do
    exit when @ready;
    form.RunOnce(10);
  end do;
except
  mark('loop error: ' & @);
  raise @;
end try;

mark('after loop, ready=' & @ready);
form.Stop();
mark('stopped');

?. 'bound port: ' & (port > 0);
?. 'native window: ' & native;
?. 'page callback: ' & @ready;
if native and @ready then
  ?. 'RESULT: OK';
else
  ?. 'RESULT: FAIL';
  raise 'native window test failed: native=' & native & ', ready=' & @ready;
end if;
