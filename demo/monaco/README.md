# Offline Monaco editor

A small Monaco editor whose chrome is built with
[z-data](https://github.com/Funlang/z-data). Everything it needs is vendored:
Monaco 0.31.1, z-data, and the language grammars. The page makes no network
requests once `Ui2Proxy` is running.

## Run

From the repository root:

```bash
funcmd demo/monaco/app.fun
```

`Ui2Proxy` picks a free port, prints the URL, and opens the default browser.
On a headless machine, open the printed URL manually.

## Features

- Syntax highlighting for **Fun**, **FD**, **JavaScript**, **HTML**, **CSS**,
  and **z-data**.
- A starter snippet for each language, plus Open and Save (Ctrl/Cmd+S).
- Light and dark themes.
- Per-language buffers and the selected language/theme persist in
  `localStorage`.
- The status bar calls `fd_info` through the fun-ui WebSocket bridge, so the
  page also demonstrates jCAL/jRET without adding another protocol.

HTML and z-data embed CSS and JavaScript; those regions use Monaco's built-in
grammars. The Fun/FD/z-data grammars live in
[`www/js/languages.js`](www/js/languages.js):

| Language | Source of the grammar |
| -------- | --------------------- |
| Fun | `funide/syntaxes/fun.tmLanguage.yaml`, `funide/src/ide/funsyntax.pas` |
| FD | `funide/src/ide/fdsyntax.pas`, `fun/lib/fd.bnf.fd` |
| z-data | z-data's studio grammar, extended with HTML/CSS/JS embedding |

## Files

| Path | Purpose |
| ---- | ------- |
| `app.fun` | `Ui2Proxy` host, static document root, and `fd_info`. |
| `www/index.html` | z-data page: toolbar, editor container, status bar. |
| `www/js/app.js` | Monaco setup, language switching, theme, files, persistence. |
| `www/js/languages.js` | Fun, FD, and z-data Monarch grammars and themes. |
| `www/js/samples.js` | Starter snippets for the six languages. |
| `www/css/app.css` | Toolbar, status bar, and light/dark page styles. |
| `www/vendor/monaco/` | Monaco 0.31.1 `min/vs` subset (MIT). |
| `www/vendor/z-data/` | z-data runtime (MIT). |

The vendored Monaco subset contains only `editor.main`, the HTML/CSS/JS basic
languages, their workers, and the codicon font. Add more
`vs/basic-languages/<id>/<id>.js` files (and `vs/language/...` workers when the
language has a service) to support another Monaco language.

## Scope

This is the minimal first version. A preview panel for HTML/z-data, formatting,
and running Fun snippets would be natural next steps; the current page focuses
on offline editing and correct highlighting.

`wwwDir` static serving is implemented by the portable Unix proxy
(`lib-ui2-proxy-unx.fun`) used on Linux and macOS. The Windows form-based proxy
does not serve a document root yet.

## Licenses

The vendored Monaco and z-data trees keep their upstream MIT license files.
