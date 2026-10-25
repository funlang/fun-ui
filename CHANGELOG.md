# Changelog

All notable changes to fun-ui are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-10-25

### Added

- **Portable WebSocket host** (`fun/lib/lib-ui2-proxy-unx.fun`): a windowless
  `Ui2Proxy` for Linux and macOS. It serves the page and bridge scripts over
  HTTP, tunnels the unchanged length-prefixed frames over WebSocket, and runs
  on the platform `lib-winsock` poll loop. `use 'lib-ui2-proxy.fun'` selects it
  automatically on Unix; the Windows form-based proxy is unchanged.
- HTTP asset serving and automatic bridge-script injection for the portable
  host (`fd.js`, `fun-bridge-ws.js`, optional `fd2.js`).
- `fun-bridge-ws.js` now handles `fCAL` and answers with an `fRET` frame, so
  Fun-initiated JavaScript calls work without the WebView2 shared buffer.
- `Start()`, `RunOnce()`, `Run()`, `Stop()`, `LocalPort()`, `Url()`,
  `OpenBrowser()`, `SetPage()` and `PostData()` on the portable host.
- Tests: `test/lib-ui2-proxy-unx-test.fun` (HTTP, WebSocket, jCAL/jRET,
  fCAL/fRET, compression) and `test/fun-bridge-ws.test.js`.
- **Native Linux window host** (`src/prj/lib.webkitgtk/`): a small GTK3 +
  WebKit2GTK host that loads the step-2 WebSocket page in a real window. It
  needs no new wire protocol or JavaScript bridge.
- `fun/lib/lib-ui2-unx.fun`: `Ui2Form` for Unix. On Linux it uses the native
  WebKitGTK window when the host library is available; otherwise (and on
  macOS) it falls back to the default browser.
- Headless CI on ubuntu-24.04 with Xvfb: the native window loads a page, calls
  `Fun('native_ready')` over WebSocket, and asserts the dispatcher receives
  it. GTK/WebKit startup masks FPC's unmasked FP exceptions, and shutdown
  drains the main context while WebKit terminates its processes.

## [1.0.0] - 2026-10-24

First open-source release.

### Added

- **jCAL / jRET protocol**: JavaScript calls a Fun method and receives the
  result, including binary payloads.
- **fCAL / fRET protocol**: Fun calls a JavaScript handler and receives the
  result.
- `Ui2Form` (`fun/lib/lib-ui2.fun`): WebView2 host form with message framing,
  compression and binary-safe transfer.
- `Ui2Proxy` (`fun/lib/lib-ui2-proxy.fun`): WebSocket transport on port 8278
  (configurable through `proxyPort`), serving the page and tunnelling binary
  messages.
- `FdDispatcher` (`fun/lib/lib-fd-dispatcher.fun`) and the synchronous and
  asynchronous FD dispatcher variants.
- JavaScript side: `fun-bridge.js` and `fun-bridge-ws.js` transports, plus the
  `fd.js` and `fd2.js` serializers.
- `libwv2` (`src/prj/lib.wv2`): 32-bit Windows DLL built with Delphi 2006 that
  embeds Chromium through WebView4Delphi. Exports `Init`, `Show`, `Navigate`,
  `PostData`, `ExecScript`, `Close` and `Free`.
- README in English and Simplified Chinese, covering architecture, API,
  building the native host, compatibility and the cross-platform roadmap.

### Known limitations

- Windows only. The WebView2 host (`libwv2.dll`) and `Ui2Form` require Windows
  and the WebView2 Runtime; `Ui2Proxy` is built on `Ui2Form`.
- The WebSocket transport still renders the served page in the WebView2 window.
  Decoupling it so an external browser can connect is roadmap step 2.
- Requires a Fun 9.x runtime and Chromium-based browsers, because the bridges
  use `CompressionStream` and the `gbk` text-encoding label.

[1.0.1]: https://github.com/funlang/fun-ui/releases/tag/v1.0.1
[1.0.0]: https://github.com/funlang/fun-ui/releases/tag/v1.0.0
