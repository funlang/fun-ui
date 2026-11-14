// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// Starter snippets for each editor language.

(function (global) {
  'use strict';

  global.EDITOR_SAMPLES = {
    fun: `// Fun: classes, member calls, and the echo operator.
class Greeter(args)
  var name = args.name or 'world';

  fun greet(prefix)
    result = (prefix or 'Hello') & ', ' & name & '!';
  end fun;
end class;

var g = Greeter(new [name: 'Fun']);
?. g.greet();          // echo to stdout
?. g.greet('Hi');

#* Block comments start with '#*' and end with '#'. *#
var ports = [80, 443, 8080];
for p in ports do
  ?. 'port: ' & p;
end do;
`,

    fd: `#!FD
# FD: JSON-compatible data with indentation instead of braces.
server
  name   api-01
  region cn-east
  ports
    - 80
    - 443
  status online
  limits
    cpu    2
    memory 512Mi
    enabled true
  tags  ["edge", "prod"]

# A quoted key and a larger number
"build info"
  commit  'a1b2c3d'
  time    2026-11-14T19:09:41+08:00
  retries 3
`,

    js: `// JavaScript: call a Fun method through the fun-ui bridge.
async function ping() {
  const reply = await Fun('info');
  console.log(reply);
}

// The bridge is injected by Ui2Proxy, so this page also works in a
// plain browser when Fun is absent.
if (typeof Fun === 'function') {
  ping();
} else {
  console.log('standalone mode: no Fun bridge');
}
`,

    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Hello</title>
  <style>
    body { font-family: system-ui, sans-serif; }
    .card { padding: 1rem; border: 1px solid #ddd; border-radius: 8px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Hello, HTML</h1>
    <p>Edit this page, then save it from the toolbar.</p>
  </div>
  <script>
    document.querySelector('h1').addEventListener('click', () => {
      alert('clicked');
    });
  </script>
</body>
</html>
`,

    css: `:root {
  --accent: #0ae;
  --text: #222;
}

body {
  margin: 0;
  font-family: system-ui, sans-serif;
  color: var(--text);
}

.card {
  padding: 1rem 1.25rem;
  border: 1px solid color-mix(in srgb, var(--accent) 40%, #fff);
  border-radius: 10px;
}

.card:hover {
  border-color: var(--accent);
}
`,

    zdata: `<template z-data="{name: 'z-data', items: ['Fun', 'FD', 'JavaScript']}">
  <style>
    .demo { font-family: system-ui, sans-serif; }
    .demo li { color: #0a7; }
  </style>
  <div class="demo">
    <h1 :text="'Hello, ' + name + '!'"></h1>
    <ul>
      <template for="item in items" key=item>
        <li :text=item></li>
      </template>
    </ul>
    <button @click="items.push('z-data')">add item</button>
  </div>
</template>
`
  };
})(window);
