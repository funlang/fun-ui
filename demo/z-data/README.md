# fun-ui + z-data demo

A five-line [z-data](https://github.com/Funlang/z-data) page served by
`Ui2Proxy`. The page renders with z-data and calls one Fun method; no build
step is involved.

## Run

From the repository root:

```bash
funcmd demo/z-data/app.fun
```

The host picks a free port, prints the URL, and opens the default browser.
Click **Call Fun** and the heading changes from `not called yet` to
`Hello, z-data!`.

## Files

| Path | Purpose |
| ---- | ------- |
| `index.html` | The z-data page. `Ui2Proxy` injects `fd.js` and `fun-bridge-ws.js`, so only z-data is added. |
| `app.fun` | `Ui2Proxy` host with `DemoDispatcher.fd_greet`, plus the page and `jsDir` settings. |

## Offline use

`index.html` loads z-data from jsDelivr. To run without network access, replace
that `<script src=...>` tag with an inline copy of `z-data.min.js` (the proxy
only serves `fd.js`, `fd2.js`, and `fun-bridge-ws.js`).
