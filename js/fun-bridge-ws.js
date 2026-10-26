// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-bridge-ws.js: WebSocket bridge (new protocol + native compression).

(function () {
  if (typeof FD === 'undefined') {
    console.error('fun-bridge-ws: FD not available');
    return;
  }

  const wsUrl = (typeof window !== 'undefined' && window.__wsUrl) || ('ws://' + location.host);
  const ws = new WebSocket(wsUrl);
  ws.binaryType = 'arraybuffer';

  const callbacks = Object.create(null);
  const timers = Object.create(null);
  let nextId = 1;

  function clearTimer(id) {
    if (timers[id] !== undefined) {
      clearTimeout(timers[id]);
      delete timers[id];
    }
  }

  function failAll(reason) {
    for (const id of Object.keys(callbacks)) {
      const cb = callbacks[id];
      delete callbacks[id];
      clearTimer(id);
      if (cb) cb(null, reason);
    }
  }

  // ---------- build the length-prefixed block ----------
  async function buildBlock(bytes) {
    const compressed = await compressIfNeeded(bytes);
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
    return block;
  }

  function sendBlock(block) {
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(block.buffer);
    } else {
      ws.addEventListener('open', () => ws.send(block.buffer), { once: true });
    }
  }

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
    if (callback) {
      callbacks[id] = callback;
      if (Number(timeout) > 0) {
        timers[id] = setTimeout(function () {
          delete timers[id];
          const cb = callbacks[id];
          if (cb) {
            delete callbacks[id];
            cb(null, 'timeout after ' + timeout + 'ms');
          }
        }, Number(timeout));
      }
    }

    const msg = { type: 'jCAL', id, name, args: args || [], timeout: timeout ?? 0 };
    const fdStr = FD.stringify(msg);
    const bytes = new TextEncoder('gbk').encode(fdStr);
    buildBlock(bytes).then(sendBlock);
  }

  ws.addEventListener('close', function () {
    failAll('connection closed');
  });

  // ---------- fCAL dispatch ----------
  class FdDispatcherJS {
    constructor() { this._handlers = Object.create(null); }
    register(name, fn) { this._handlers[name] = fn; }
    getHandler(name) { return this._handlers[name]; }
  }
  if (!window.__fdDispatcher) {
    window.__fdDispatcher = new FdDispatcherJS();
  }

  async function handleFCAL(msg) {
    const { name, args, id } = msg;
    const handler = window.__fdDispatcher.getHandler(name);
    let err = false, val;
    if (handler) {
      try {
        val = await handler(args);
      } catch (e) {
        err = true;
        val = e.message;
      }
    } else {
      err = true;
      val = 'method not found: ' + name;
    }

    const fretPayload = FD.stringify({ type: 'fRET', id, val, err });
    const fretBytes = new TextEncoder('gbk').encode(fretPayload);
    sendBlock(await buildBlock(fretBytes));
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
          clearTimer(id);
          cb(val, err);
        }
      } else if (msg && msg.type === 'fCAL') {
        await handleFCAL(msg);
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
