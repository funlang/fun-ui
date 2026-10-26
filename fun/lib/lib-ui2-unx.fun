// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-unx: Ui2Form for Linux and macOS.
//
// On Unix the transport is the portable WebSocket host
// (lib-ui2-proxy-unx.fun). Ui2Form adds an optional native window:
//
//   * Linux: if the GTK3/WebKit2GTK host (libui2webkitgtk.so) is available,
//     create a real window and load the page served by the proxy.
//   * macOS: if the AppKit/WKWebView host (libui2wkwebview.dylib) is
//     available, create a real window and load the page served by the proxy.
//   * Otherwise (or on other Unix systems): fall back to opening the default
//     browser. The proxy still runs and serves the same page.
//
// The page always talks to Fun over the WebSocket transport, so the message
// protocol, dispatcher, and JavaScript bridge are unchanged from step 2.
//
//     @ui2webkitdll = '/path/to/libui2webkitgtk.so';  // optional; on macOS
//                                                     // libui2wkwebview.dylib
//     var form = Ui2Form();
//     form.port = 8278;
//     form.jsDir = 'js';
//     form.dispatcher = MyDispatcher();
//     form.Show();          // Start + Run
//
// Set @ui2RequireWebview = true to turn a missing host library into an error
// instead of the browser fallback (used by the headless CI smoke test).

use 'lib-ui2-proxy.fun';
use 'lib-host.fun';

var @ui2webkitdll = 'libui2webkitgtk.so';
var @ui2RequireWebview = false;
var @ui2FormTitle = 'fun-ui';
var @ui2FormWidth = 1024;
var @ui2FormHeight = 768;

class Ui2Form = Ui2Proxy()
  var title  = @ui2FormTitle;
  var width  = @ui2FormWidth;
  var height = @ui2FormHeight;
  var hostLib = @ui2webkitdll;
  var requireWebview = @ui2RequireWebview;
  var lastError = '';
  var traceFile = '';      // optional path for native startup tracing

  var _host = nil;
  var _native = false;
  var _fnInit = nil;
  var _fnShow = nil;
  var _fnIterate = nil;
  var _fnClose = nil;
  var _fnTitle = nil;

  fun _trace(s)
    if traceFile <> '' then
      traceFile.save('' & s & 10.toChar(), append: true);
    end if;
  end fun;

  //---- lifecycle ------------------------------------------------
  fun Start()
    // Start the HTTP + WebSocket server first. This calls onReady(), which is
    // where subclasses set page/jsDir/dispatcher.
    var port = base.Start();

    var lib = hostLib;
    var sym = 'ui2_gtk_';
    if IsMac() then
      sym = 'ui2_wk_';
      if lib = '' or lib = 'libui2webkitgtk.so' then
        lib = 'libui2wkwebview.dylib';
      end if;
    end if;

    if IsLinux() or IsMac() then
      try
        _host = lib;
        _fnInit    = _host.getapi(sym & 'init', ':i');
        _fnShow    = _host.getapi(sym & 'show', 'siis:i');
        _fnIterate = _host.getapi(sym & 'iterate', ':i');
        _fnClose   = _host.getapi(sym & 'close', ':i');
        _fnTitle   = _host.getapi(sym & 'set_title', 's:i');
        _trace('host init begin');
        var initOk = _fnInit.call();
        _trace('host init returned ' & initOk);
        if initOk <> 0 then
          _trace('host show begin ' & this.Url());
          var shown = _fnShow.call(this.Url(), width, height, title);
          _trace('host show returned ' & shown);
          if shown <> 0 then
            _native = true;
          end if;
        end if;
      except
        _native = false;
        lastError = '' & @;
      end try;
    end if;

    if not _native then
      if lastError = '' then
        lastError = 'native host init/show returned false';
      end if;
      if requireWebview then
        raise 'Ui2Form: native webview host not available: ' & lib & ': ' & lastError;
      end if;
      this.OpenBrowser();
    end if;

    result = port;
  end fun;

  fun RunOnce(timeout)
    if _native then
      _trace('iterate begin');
      var alive = _fnIterate.call();
      _trace('iterate returned ' & alive);
      if alive = 0 then
        // The user closed the native window. Close the server too.
        this.Stop();
        result = 0;
        return;
      end if;
    end if;
    _trace('proxy runonce begin');
    result = base.RunOnce(timeout);
    _trace('proxy runonce returned ' & result);
  end fun;

  fun Run(timeout)
    if _server = nil then this.Start(); end if;
    while _running loop
      this.RunOnce(timeout or 10);
    end loop;
  end fun;

  //---- native window helpers ------------------------------------
  fun SetTitle(s)
    title = s;
    if _native then
      try
        _fnTitle.call(s);
      except
        ?. 'Ui2Form SetTitle: ' & @;
      end try;
    end if;
  end fun;

  fun SetSize(w, h)
    width = w;
    height = h;
  end fun;

  fun Native()
    result = _native;
  end fun;

  fun Stop()
    if _native then
      try
        _fnClose.call();
      except
        ?. 'Ui2Form Stop: ' & @;
      end try;
      _native = false;
    end if;
    base.Stop();
  end fun;
end class;
