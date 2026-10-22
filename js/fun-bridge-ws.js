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

// fun-bridge-ws.js - WebSocket bridge (new protocol + native compression)
(function () {
  if (typeof FD === 'undefined') {
    console.error('fun-bridge-ws: FD not available');
    return;
  }

  const wsUrl = (typeof window !== 'undefined' && window.__wsUrl) || ('ws://' + location.host);
  const ws = new WebSocket(wsUrl);
  ws.binaryType = 'arraybuffer';

  const callbacks = Object.create(null);
  let nextId = 1;

  async function compressIfNeeded(data) {
    const compressEnabled = window.__funCompress || false;
    const compressMinSize = window.__funCompressMinSize || 512;
    if (!compressEnabled || data.length < compressMinSize) return data;
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
      const compressed = new Uint8Array(totalLen);
      let offset = 0;
      for (const chunk of chunks) {
        compressed.set(chunk, offset);
        offset += chunk.length;
      }
      return compressed;
    } catch (e) {
      return data;
    }
  }

  async function decompressIfNeeded(compressed) {
    const ds = new DecompressionStream('deflate-raw');
    const writer = ds.writable.getWriter();
    writer.write(compressed);
    writer.close();
    const reader = ds.readable.getReader();
    const chunks = [];
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
    }
    const totalLen = chunks.reduce((s, c) => s + c.length, 0);
    const result = new Uint8Array(totalLen);
    let offset = 0;
    for (const chunk of chunks) {
      result.set(chunk, offset);
      offset += chunk.length;
    }
    return result;
  }

  function sendCall(name, args, timeout, callback) {
    const id = nextId++;
    if (callback) callbacks[id] = callback;

    const msg = { type: 'jCAL', id, name, args: args || [], timeout: timeout ?? 0 };
    const fdStr = FD.stringify(msg);
    let bytes = new TextEncoder('gbk').encode(fdStr);

    compressIfNeeded(bytes).then(compressed => {
      let compressFlag = 0;
      if (compressed !== bytes) {
        bytes = compressed;
        compressFlag = 0x80000000;
      }
      const totalLen = bytes.length;
      const lenWithFlag = totalLen | compressFlag;
      const block = new Uint8Array(4 + totalLen);
      block[0] = lenWithFlag & 0xFF;
      block[1] = (lenWithFlag >> 8) & 0xFF;
      block[2] = (lenWithFlag >> 16) & 0xFF;
      block[3] = (lenWithFlag >> 24) & 0xFF;
      block.set(bytes, 4);

      if (ws.readyState === WebSocket.OPEN) {
        ws.send(block.buffer);
      } else {
        ws.addEventListener('open', () => ws.send(block.buffer), { once: true });
      }
    });
  }

  ws.addEventListener('message', async (e) => {
    if (!(e.data instanceof ArrayBuffer)) return;
    const copy = new Uint8Array(e.data).slice(); // Copy before any mutation
    try {
      if (copy.length < 4) return;
      const rawLen = copy[0] | (copy[1] << 8) | (copy[2] << 16) | (copy[3] << 24);
      const compressed = (rawLen & 0x80000000) !== 0;
      const actualLen = rawLen & 0x7FFFFFFF;
      if (actualLen === 0 || actualLen > copy.length - 4) return;
      const payload = copy.slice(4, 4 + actualLen);

      let msgData;
      if (compressed) {
        msgData = await decompressIfNeeded(payload);
        if (!msgData) return;
      } else {
        msgData = payload;
      }

      const msg = FD.parse(msgData, 'gbk');
      if (msg && msg.type === 'jRET') {
        const { id, val, err } = msg;
        const cb = callbacks[id];
        if (cb) {
          delete callbacks[id];
          cb(val, err);
        }
      }
    } catch (err) {
      console.error('fun-bridge-ws: receive error', err);
    }
  });

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
      console.error('fun-bridge-ws: invalid arguments');
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
