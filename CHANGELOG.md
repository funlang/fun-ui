# Changelog

All notable changes to fun-ui are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `fd.js` / `fd2.js` now agree with the Fun interpreter and `lib-fd.fun` on
  FD values: numbers use the RFC 8259 grammar (the same as `json: 2`), so
  leading-zero forms such as `03`/`01` are strings and values follow the
  host number type (IEEE-754 double, so integers beyond 2^53 lose exactness;
  quote large IDs if they must round-trip). Empty documents parse as `[]`,
  `\xHH` escapes are decoded, `#!kvd:<char>` selects a custom key/value
  delimiter, and duplicate named keys are last-wins. The writers quote
  numeric-looking strings with the same grammar, and use 15 significant
  digits for non-integer numbers so `0.1 + 0.2` writes as `0.3`.

## [1.0.3] - 2026-10-28

### Added

- `demo/z-data/`: a runnable five-line z-data page served by `Ui2Proxy`,
  with `fd_greet` and a host script that prints the URL and opens a browser.

### Changed

- The English and Chinese READMEs now introduce
  [z-data](https://github.com/Funlang/z-data) in the overview as the
  complementary page-side framework, add a Related projects section, and show
  the page/`fd_greet` example behind the demo.
- CI caches the downloaded GTK/WebKit `.deb` packages and bounds every apt
  step, so `linux-webkitgtk` no longer spends the whole run on a slow package
  mirror.
- Pushing an annotated version tag now publishes the GitHub release through the
  `release` workflow; the same workflow can backfill a tag from the Actions UI.

## [1.0.2] - 2026-10-26

### Added

- **Native macOS host** (`src/prj/lib.wkwebview/`): a small AppKit window
  with a WKWebView that loads the page served by the portable proxy. It
  exports `ui2_wk_init`, `ui2_wk_show`, `ui2_wk_iterate`, `ui2_wk_set_title`,
  `ui2_wk_close`, and `ui2_wk_free`, pumps AppKit/WebKit work from `RunOnce`,
  masks FPC's floating-point exceptions, and ad-hoc signs the dylib.
- `lib-ui2-unx.fun` selects `libui2wkwebview.dylib` and the `ui2_wk_*` symbols
  on macOS, keeping the browser fallback and `requireWebview` behaviour.
- `test/lib-ui2-webview-mac-test.fun` and a `macos-wkwebview` CI job: the job
  builds Fun with Homebrew FPC (requiring `getapi`), runs the portable loopback
  test, builds the host, and runs the native-window smoke test on macos-14.
- WebSocket upgrade checks in the portable host: same-origin `Origin`/`Host`
  validation (blocking cross-site WebSocket hijacking and DNS rebinding),
  optional `allowedOrigins`/`allowedHosts`, an optional URL-safe `token`
  injected into the served page, and a configurable `maxFrameBytes` cap
  (16 MiB by default, enforced after decompression as well).
- Call timeouts. `Fun(..., { timeout })` now expires callbacks and rejects
  promises; `FdDispatcher.callJS` accepts a fifth `timeout` argument, and
  `expire()`/`failPending(reason)` are public. `Ui2Proxy.RunOnce` expires
  callbacks on every poll round.
- Pending fCAL calls fail with `connection closed` when the page socket sends
  a close frame, and with `proxy stopped` when the host stops.

### Changed

- CI pins Fun v9.4.7, which includes the macOS `getapi`/libffi support, and
  `setup-fun` builds Fun with Homebrew FPC plus `make-macos.sh` on macOS.

### Fixed

- The dispatcher's pending-id collection used a name that collides with a
  built-in member, so `expire()` never saw outstanding calls. Renamed to
  `_fcalIds`.
- Only frames that parse become the fCAL/`PostData` target; an oversized or
  malformed frame can no longer steal routing from the real page connection.
- A frame queued during `Stop()` no longer dereferences the cleared server
  (`_server nil.Reply`).

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

[1.0.3]: https://github.com/funlang/fun-ui/releases/tag/v1.0.3
[1.0.2]: https://github.com/funlang/fun-ui/releases/tag/v1.0.2
[1.0.1]: https://github.com/funlang/fun-ui/releases/tag/v1.0.1
[1.0.0]: https://github.com/funlang/fun-ui/releases/tag/v1.0.0
