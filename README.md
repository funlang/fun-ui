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
same messages over a socket instead of shared memory. On Linux and macOS the
WebSocket transport has no window at all: it serves the page and bridge scripts
over HTTP and lets an ordinary browser connect. Both transports share the same
message format and JavaScript API.

## Project status and roadmap

**Status:** the WebView2 host (`libwv2.dll`) and `Ui2Form` are Windows-only.
The Windows `Ui2Proxy` remains form-based. On Linux and macOS,
`lib-ui2-proxy-unx.fun` provides the same host API without a window or
`libwv2`, and is selected automatically by `use 'lib-ui2-proxy.fun'`.

**Goal:** offer the same Fun-side and JavaScript API on Windows, Linux and
macOS, so a Fun program can serve a browser UI on every platform Fun supports.

1. **Windows baseline (done).** WebView2 transport, WebSocket transport, FD
   serialization, and the dispatcher/bridge implementations in this repository.
2. **Portable WebSocket transport (done on Linux/macOS).** `Ui2Proxy` is split
   from the WebView2 form and serves an external browser through the shared
   HTTP/WebSocket core. The Windows form-based proxy remains for backward
   compatibility.
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
| [`fun/lib/lib-ui2-proxy-unx.fun`](fun/lib/lib-ui2-proxy-unx.fun) | Windowless `Ui2Proxy` for Linux and macOS: HTTP page plus WebSocket, no WebView2. |
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
│   ├── lib-ui2-proxy-unx.fun
│   ├── lib-fd-dispatcher.fun
│   ├── lib-fd-dispatcher-async.fun
│   └── lib-fd-dispatcher-proc.fun
├── js/                      # Browser-side modules
│   ├── fd.js
│   ├── fd2.js
│   ├── fun-bridge.js
│   └── fun-bridge-ws.js
├── src/prj/lib.wv2/         # Native WebView2 host (Windows, Delphi)
    ├── libwv2.dpr
    ├── wv2.pas
    ├── wv2.dfm
    ├── setenv.bat
    └── make-2006.bat
└── test/                    # Loopback and bridge tests
    ├── lib-ui2-proxy-unx-test.fun
    └── fun-bridge-ws.test.js
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

On Linux and macOS, skip `libwv2` and use the portable proxy instead:

```fun
use 'lib-ui2-proxy.fun';   // resolves to lib-ui2-proxy-unx.fun

class AppDispatcher = FdDispatcher()
  fun fd_ping(args)
    result = new [pong: args[0]];
  end fun;
end class;

var proxy = Ui2Proxy();
proxy.port = 8278;          // 0 picks an ephemeral port
proxy.jsDir = 'js';         // directory containing fd.js and fun-bridge-ws.js
proxy.page = '<h1>Hello from Fun</h1>';
proxy.dispatcher = AppDispatcher();
var port = proxy.Start();   // non-blocking; returns the bound port
?. proxy.Url();             // http://127.0.0.1:<port>/
proxy.Run();                // blocking poll loop
```

`Ui2Proxy` injects `<script src="/fd.js">` and
`<script src="/fun-bridge-ws.js">` into the served page unless the page already
includes a bridge. Set `proxy.autoOpen = true` to launch the default browser.
The HTTP server binds to `127.0.0.1` by default; set `proxy.ip = '0.0.0.0'` to
serve other machines.

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

On Linux and macOS the proxy runs on the same poll loop as
`lib-winsock-unx.fun` and needs no window, `libwv2.dll`, or WebView2 runtime.
`Start()` returns the bound port, `RunOnce(timeout)` drives one poll round for
embedding, and `Run()` blocks until `Stop()`. `PostData` pushes an unsolicited
frame to the most recent page connection. fCAL responses arrive as ordinary
`fRET` messages, so `fun-bridge-ws.js` handles them without shared buffers.

The Windows `lib-ui2-proxy.fun` still hosts the page in `Ui2Form`; the portable
host is selected automatically on Linux and macOS by the platform-aware module
loader.

---

## Compatibility

- Fun 9.x runtime with the standard library modules listed above.
- Windows with WebView2 for `libwv2.dll` and `Ui2Form`.
- Linux and macOS for the portable WebSocket host (`lib-ui2-proxy-unx.fun`),
  using the platform's `lib-winsock` backend. No window or WebView2 runtime is
  required.
- Chromium-based browsers for `fun-bridge.js` and `fun-bridge-ws.js`, because
  the bridges use `CompressionStream` and the `gbk` text-encoding label.

## Tests

```bash
# HTTP + WebSocket + jCAL/jRET + fCAL/fRET + compression (Linux/macOS)
funcmd test/lib-ui2-proxy-unx-test.fun

# Browser bridge unit test (Node 18+; CompressionStream is required)
node --experimental-websocket test/fun-bridge-ws.test.js
```

---

## License

MIT. See [LICENSE](LICENSE). Release history is in [CHANGELOG.md](CHANGELOG.md).

Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>.
