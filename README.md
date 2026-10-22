# fun-ui

Browser-based user interfaces for the [Fun](https://funlang.org) programming
language.

**English** (this file) - [简体中文](README.zh.md)

- Version: **1.0**
- Website: <https://funlang.org>
- License: MIT (see [LICENSE](LICENSE))

`fun-ui` connects Fun scripts to web UIs. A Fun process owns the window and the
business logic, while the interface is ordinary HTML, CSS and JavaScript running
in a Chromium-based browser. Calls cross the boundary in both directions:

- **jCAL / jRET**: JavaScript calls a Fun method and receives the result.
- **fCAL / fRET**: Fun calls a JavaScript handler and receives the result.

Two transports are provided. The WebView2 transport embeds Chromium directly in
a Fun window through a small Delphi DLL. The WebSocket transport carries the
same messages over a socket instead of shared memory. Both share the same
message format and JavaScript API. The current WebSocket implementation still
hosts the page in the Windows WebView2 window; the roadmap below covers serving
it to an external browser.

## Project status and roadmap

**Status:** the initial open-source release targets Windows. The WebView2 host
(`libwv2.dll`) and `Ui2Form` are Windows-only. `Ui2Proxy` is built on `Ui2Form`
and loads the Windows `lib-winsock` backend.

**Goal:** offer the same Fun-side and JavaScript API on Windows, Linux and
macOS, so a Fun program can serve a browser UI on every platform Fun supports.

1. **Windows baseline (current).** WebView2 transport, WebSocket transport, FD
   serialization, and the dispatcher/bridge implementations in this repository.
2. **Portable WebSocket transport.** Split `Ui2Proxy` from the WebView2 form so
   it can serve an external browser, then select `lib-winsock-lnx` on Linux and
   `lib-winsock-unx` on macOS. The HTTP/WebSocket core in
   `lib-winsock-base.fun` is already shared, so this is the shortest path to
   running the browser UI outside Windows.
3. **Native webview backends.** Add Linux and macOS hosts behind the `Ui2Form`
   API, using WebKitGTK and WKWebView (or another embeddable engine), without
   changing the message protocol or the JavaScript bridge.
4. **Release engineering.** Per-platform build scripts, CI coverage, packaged
   examples, and a compatibility matrix.

The wire protocol and JavaScript API are intended to remain stable across these
steps. Platform-specific code should stay in the host layer (`libwv2`, future
webview hosts, and the socket backend).

---

## Contents

| Path | Purpose |
| ---- | ------- |
| [`fun/lib/lib-ui2.fun`](fun/lib/lib-ui2.fun) | `Ui2Form`: WebView2 host form, message framing, compression, binary-safe transfer. |
| [`fun/lib/lib-ui2-proxy.fun`](fun/lib/lib-ui2-proxy.fun) | `Ui2Proxy`: WebSocket mode. Serves the page and tunnels binary messages through a local WebSocket. |
| [`fun/lib/lib-fd-dispatcher.fun`](fun/lib/lib-fd-dispatcher.fun) | `FdDispatcher`: jCAL handler lookup, jRET replies, fCAL/fRET callbacks. |
| [`fun/lib/lib-fd-dispatcher-async.fun`](fun/lib/lib-fd-dispatcher-async.fun) | `FdAsyncDispatcher`: runs jCAL handlers on the Fun async scheduler. |
| [`fun/lib/lib-fd-dispatcher-proc.fun`](fun/lib/lib-fd-dispatcher-proc.fun) | File-queue dispatcher and worker for out-of-process UI back ends. |
| [`js/fd.js`](js/fd.js) | Complete FD parser and serializer for the browser (v1.8 API). |
| [`js/fd2.js`](js/fd2.js) | Streaming FD parser and serializer for chunked input. |
| [`js/fun-bridge.js`](js/fun-bridge.js) | WebView2 bridge: shared buffers, base64 channel, compression, `window.Fun`. |
| [`js/fun-bridge-ws.js`](js/fun-bridge-ws.js) | WebSocket bridge with the same `window.Fun` API. |
| [`src/prj/lib.wv2/`](src/prj/lib.wv2) | Delphi 2006 project that builds `libwv2.dll` on top of WebView4Delphi. |

---

## Repository layout

```text
fun-ui/
├── fun/lib/                 # Fun-side modules
│   ├── lib-ui2.fun
│   ├── lib-ui2-proxy.fun
│   ├── lib-fd-dispatcher.fun
│   ├── lib-fd-dispatcher-async.fun
│   └── lib-fd-dispatcher-proc.fun
├── js/                      # Browser-side modules
│   ├── fd.js
│   ├── fd2.js
│   ├── fun-bridge.js
│   └── fun-bridge-ws.js
└── src/prj/lib.wv2/         # Native WebView2 host (Windows, Delphi)
    ├── libwv2.dpr
    ├── wv2.pas
    ├── wv2.dfm
    ├── setenv.bat
    └── make-2006.bat
```

`fun-ui` does not contain the Fun language implementation. The modules in
`fun/lib` use the standard library that ships with the neighbouring
[`fun`](https://github.com/Funlang/fun) project (`lib-ui.fun`, `lib-zlib.fun`,
`lib-async.fun`, `lib-ajax.fun`, `lib-winsock.fun`, `lib-os.fun`).

### Using the Fun modules

1. Put `fun/lib` on the Fun module search path, or copy the modules into
   `<FUN_ROOT>/fun/lib`.
2. Load `lib-ui2.fun` from the host script and derive a form class from
   `Ui2Form`. Override `onReady` to call `Navigate`.
3. Assign an `FdDispatcher` subclass (or `FdAsyncDispatcher`) to the form's
   `dispatcher` property before showing it, so `fd_*` methods can serve jCAL
   calls.
4. Keep `libwv2.dll` on the DLL search path; `lib-ui2.fun` accesses it through
   the global `@libwv2dll`.

---

## Message protocol

All messages are FD documents. The `type` field selects the channel.

| Message | Direction | Meaning |
| ------- | --------- | ------- |
| `jCAL` | JS to Fun | Call a Fun handler. Fields: `id`, `name`, `args`, `timeout`. |
| `jRET` | Fun to JS | Result of a `jCAL`. Fields: `id`, `val`, `err`. |
| `fCAL` | Fun to JS | Call a JavaScript handler. Fields: `id`, `name`, `args`, `timeout`. |
| `fRET` | JS to Fun | Result of a `fCAL`. Fields: `id`, `val`, `err`. |

Binary payloads travel in a frame with a 4-byte little-endian length header.
Bit 31 of the header marks a compressed payload. Compression is raw DEFLATE
(`deflate` in Fun, `CompressionStream('deflate-raw')` in the browser). The
JavaScript side compresses its outgoing frames when the page enables it:

```js
window.__funCompress = true;        // default: false
window.__funCompressMinSize = 512;  // default: 512 bytes
```

The Fun side controls its own outgoing compression with
`Ui2Form.setCompress(flag, minSize)`.

The bridges use the `gbk` encoding label for FD text (`TextEncoder('gbk')` on
send and `FD.parse(..., 'gbk')` on receive) so that legacy Windows code pages
and existing Fun strings round-trip. Chromium supports the `gbk` decoding
label, which is why the supported browsers are Chromium-based.

For `fCAL` responses, the Fun side allocates a shared buffer and passes its
handle to JavaScript. JavaScript writes the `fRET` frame into that buffer and
posts only the handle back, which avoids a second large copy.

---

## JavaScript API

Load `fd.js` (or `fd2.js`) followed by one bridge:

```html
<script src="fd.js"></script>
<script src="fun-bridge.js"></script>
<script>
  Fun('load_profile', { id: 42 }).then(function (profile) {
    console.log(profile);
  });

  Fun({ name: 'ping', args: ['hello'], callback: function (val, err) {
    if (err) console.error(err);
    else console.log(val);
  }});
</script>
```

`window.Fun` accepts either `Fun(name, ...args)` or a single options object with
`name`, `args`, `callback` and `timeout`. Without a callback it returns a
Promise. On the Fun side, `FdDispatcher` resolves a name to a method called
`fd_<name>`; dashes and spaces in the name become underscores, with a
name-without-separators lookup as a fallback.

JavaScript handlers for `fCAL` calls are registered on the bridge dispatcher:

```js
window.__fdDispatcher.register('update_title', function (args) {
  document.title = args[0];
  return true;
});
```

---

## Building the native WebView2 host

`libwv2.dll` is a 32-bit Windows DLL built with Delphi 2006. It links against
[WebView4Delphi](https://github.com/salvadordf/WebView4Delphi), which is not
vendored here.

### Prerequisites

| Item | Notes |
| ---- | ----- |
| Windows | WebView2 Runtime must be installed; the Evergreen runtime is recommended. |
| Delphi 2006 | `DELPHI2006` points at its install root. |
| WebView4Delphi | `WV2_SRC` points at the folder containing `uWVLoader.pas`, `uWVBrowser.pas` and friends. |
| Fun checkout | `FUN_ROOT` points at the neighbouring `fun` repository. |

### Toolchain configuration

All machine-specific paths live in
[`src/prj/lib.wv2/setenv.bat`](src/prj/lib.wv2/setenv.bat). Edit it once, or
pre-set the variables in your shell. Every assignment uses an `if not defined`
guard, so your values win.

| Variable | Meaning | Default |
| -------- | ------- | ------- |
| `FUN_ROOT` | Root of the `fun` checkout | `..\..\..\..\fun` |
| `DELPHI2006` | Delphi 2006 install root | `D:\Borland\Delphi2006` |
| `WV2_SRC` | WebView4Delphi source folder | `..\..\..\..\WebView4Delphi\source` |

### Build steps

```text
cd src\prj\lib.wv2
make-2006.bat
```

The script loads `setenv.bat`, invokes `dcc32 libwv2.dpr` with `WV2_SRC` on the
unit search path, and passes extra switches through, for example
`make-2006.bat -B`. The resulting `libwv2.dll` is written next to the project.
Copy it beside the Fun host executable, or to any directory on the DLL search
path.

At runtime the Fun side reaches the native module through the global
`@libwv2dll`. Keep `libwv2.dll` beside the host executable or on the DLL search
path. The exported entry points are:

| Export | Purpose |
| ------ | ------- |
| `Init(callback)` | Store the Fun event callback, create the WebView2 loader and start it. |
| `Show(parentHandle)` | Create the browser window and return its handle. |
| `Navigate(url)` | Load a URL, or HTML when the string starts with `<`. |
| `PostData(ptr, len)` | Send a block to JavaScript. A negative `len` allocates an fCAL response buffer. |
| `ExecScript(script)` | Run JavaScript in the page. |
| `Close`, `Free` | Tear down the window and the loader. |

Event messages use the codes defined in `wv2.pas` (`MSG_ERROR`, `MSG_CREATED`,
`MSG_TITLE_CHANGED`, `MSG_BINARY`, `MSG_TEXT`, `MSG_FCAL_RESULT`).

---

## WebSocket transport

`Ui2Proxy` serves a local HTTP page and accepts WebSocket connections on
`proxyPort` (default `8278`). JavaScript loads `fun-bridge-ws.js`, which uses
`window.__wsUrl` or `ws://<location.host>`. The frame format is identical to the
WebView2 transport, so the dispatcher and page code do not change.

The current implementation still shows the served page in the WebView2 window.
Once the proxy is decoupled from `Ui2Form` (roadmap step 2), the same page can
run in an external browser, including when the Fun process is remote or when
developing the page against a service.

---

## Compatibility

- Fun 9.x runtime with the standard library modules listed above.
- Windows with WebView2 for `libwv2.dll` and `Ui2Form`.
- The first release is Windows-only. Cross-platform support, including the
  planned WebSocket-only path that does not need WebView2, is described in
  [Project status and roadmap](#project-status-and-roadmap).
- Chromium-based browsers for `fun-bridge.js` and `fun-bridge-ws.js`, because
  the bridges use `CompressionStream` and the `gbk` text-encoding label.

---

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>.
