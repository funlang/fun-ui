// Copyright (c) 2026 funlang.org
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// fun-bridge.js - WebView2 bridge (jCAL/jRET + fCAL/fRET, with compression)
(function () {
  if (typeof FD === 'undefined' || typeof chrome === 'undefined' || !chrome.webview) {
    console.error('fun-bridge: FD or chrome.webview not available');
    return;
  }

  const callbacks = Object.create(null);
  let nextId = 1;

  // ---------- Pack / unpack (including compression) ----------
  async function buildBlock(data) {
    const compressEnabled = window.__funCompress || false;
    const compressMinSize = window.__funCompressMinSize || 512;
    let bytes = data;
    let compressed = false;

    if (compressEnabled && data.length >= compressMinSize) {
      try {
        const cs = new CompressionStream('deflate-raw');
        const writer = cs.writable.getWriter();
        writer.write(data);
        writer.close();
        const reader = cs.readable.getReader();
        const chunks = [];
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
        }
        const totalLen = chunks.reduce((s, c) => s + c.length, 0);
        const compressedArray = new Uint8Array(totalLen);
        let offset = 0;
        for (const chunk of chunks) {
          compressedArray.set(chunk, offset);
          offset += chunk.length;
        }
        bytes = compressedArray;
        compressed = true;
      } catch (e) { /* Fall back to uncompressed */ }
    }

    const totalLen = bytes.length;
    const block = new Uint8Array(4 + totalLen);
    block[0] = totalLen & 0xFF;
    block[1] = (totalLen >> 8) & 0xFF;
    block[2] = (totalLen >> 16) & 0xFF;
    block[3] = (totalLen >> 24) & 0xFF;
    if (compressed) block[3] |= 0x80;
    block.set(bytes, 4);
    return block;
  }

  async function unpackBlock(block) {
    if (block.length < 4) return null;
    const rawLen = block[0] | (block[1] << 8) | (block[2] << 16) | (block[3] << 24);
    const compressed = (rawLen & 0x80000000) !== 0;
    const actualLen = rawLen & 0x7FFFFFFF;
    if (actualLen === 0 || actualLen + 4 > block.length) return null;
    let payload = block.slice(4, 4 + actualLen);

    if (compressed) {
      try {
        const ds = new DecompressionStream('deflate-raw');
        const writer = ds.writable.getWriter();
        writer.write(payload);
        writer.close();
        const reader = ds.readable.getReader();
        const chunks = [];
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          chunks.push(value);
        }
        const totalLen = chunks.reduce((s, c) => s + c.length, 0);
        const decompressed = new Uint8Array(totalLen);
        let offset = 0;
        for (const chunk of chunks) {
          decompressed.set(chunk, offset);
          offset += chunk.length;
        }
        return decompressed;
      } catch (e) { return null; }
    }
    return payload;
  }

  // ---------- Build an FD message ----------
  function buildFD(type, id, name, args, timeout) {
    const msg = { type, id, name, args: args || [], timeout: timeout ?? 0 };
    return FD.stringify(msg);
  }

  // ---------- Send jCAL ----------
  async function sendCall(name, args, timeout, callback) {
    const id = nextId++;
    if (callback) callbacks[id] = callback;

    const fdStr = buildFD('jCAL', id, name, args, timeout);
    const gbkBytes = new TextEncoder('gbk').encode(fdStr);
    const block = await buildBlock(gbkBytes);
    const base64 = btoa(String.fromCharCode(...block));
    chrome.webview.postMessage('B64:' + base64);
  }

  // ---------- fCAL dispatch ----------
  class FdDispatcherJS {
    constructor() { this._handlers = Object.create(null); }
    register(name, fn) { this._handlers[name] = fn; }
    getHandler(name) { return this._handlers[name]; }
  }
  window.__fdDispatcher = new FdDispatcherJS();

  async function handleFCAL(handle, buf) {
    const reqData = await unpackBlock(new Uint8Array(buf));
    if (!reqData) return;

    const msg = FD.parse(reqData, 'gbk');
    if (!msg || msg.type !== 'fCAL') return;

    const { name, args } = msg;
    const handler = window.__fdDispatcher.getHandler(name);
    let err = false, val;
    if (handler) {
      try { val = await handler(args); } catch (e) { err = true; val = e.message; }
    } else { err = true; val = 'method not found: ' + name; }

    const fretPayload = FD.stringify({ type: 'fRET', id: msg.id, val, err });
    const fretBytes = new TextEncoder('gbk').encode(fretPayload);
    const fretBlock = await buildBlock(fretBytes);

    const dst = new Uint8Array(buf);
    if (fretBlock.length <= dst.length) {
      dst.set(fretBlock, 0);
    } else {
      console.error('fCAL result too large');
    }
    chrome.webview.postMessage('FRET:' + handle);
  }

  // ---------- Receive ----------
  window.chrome.webview.addEventListener('sharedbufferreceived', async (e) => {
    const extra = e.additionalData;
    const buf = e.getBuffer();
    if (!buf) return;

    // fCAL channel
    if (extra && /^\d+$/.test(extra)) {
      return handleFCAL(extra, buf);
    }

    // jRET channel
    const copy = new Uint8Array(buf).slice();
    const msgData = await unpackBlock(copy);
    if (!msgData) return;

    const msg = FD.parse(msgData, 'gbk');
    if (msg && /^jR(ET|et)$/.test(msg.type)) {
      const { id, val, err } = msg;
      const cb = callbacks[id];
      if (cb) {
        delete callbacks[id];
        cb(val, err);
      }
    }
  });

  // ---------- Public API ----------
  window.Fun = function (first, ...rest) {
    let name, args = [], callback, timeout;
    if (typeof first === 'object' && first !== null && !Array.isArray(first)) {
      name = first.name || first.method;
      args = first.args || [];
      callback = first.callback;
      timeout = first.timeout;
    } else if (typeof first === 'string') {
      name = first;
      callback = typeof rest[rest.length - 1] === 'function' ? rest.pop() : null;
      args = rest;
    } else {
      console.error('fun-bridge: invalid arguments');
      return;
    }
    if (!Array.isArray(args)) args = [args];

    if (callback) {
      sendCall(name, args, timeout, callback);
      return;
    }
    return new Promise((resolve, reject) => {
      sendCall(name, args, timeout, (val, err) => {
        if (err) reject(err);
        else resolve(val);
      });
    });
  };
})();
