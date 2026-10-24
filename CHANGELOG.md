# Changelog

All notable changes to fun-ui are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.0.0]: https://github.com/funlang/fun-ui/releases/tag/v1.0.0
