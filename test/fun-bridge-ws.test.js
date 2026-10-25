// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// fun-bridge-ws.js: jCAL/jRET and fCAL/fRET unit test.
//
//     node --experimental-websocket test/fun-bridge-ws.test.js
//
// The test fakes the browser WebSocket, so it does not need a Fun server. It
// checks that the bridge frames outgoing calls with the 4-byte length header
// and answers incoming fCAL messages with an fRET frame.

const fs = require('fs');
const path = require('path');

const { FD } = require('../js/fd.js');

class FakeWebSocket {
  static OPEN = 1;
  static CLOSED = 3;
  constructor(url) {
    this.url = url;
    this.readyState = FakeWebSocket.OPEN;
    this.sent = [];
    this.listeners = Object.create(null);
  }
  addEventListener(type, fn) {
    (this.listeners[type] || (this.listeners[type] = [])).push(fn);
  }
  send(data) {
    this.sent.push(new Uint8Array(data));
  }
  emit(type, event) {
    for (const fn of this.listeners[type] || []) fn(event);
  }
}

const ws = new FakeWebSocket('ws://localhost/fake');
const FakeConstructor = function (url) { return ws; };
FakeConstructor.OPEN = FakeWebSocket.OPEN;
FakeConstructor.CLOSED = FakeWebSocket.CLOSED;
global.WebSocket = FakeWebSocket;
global.window = {};
global.location = { host: 'localhost' };
global.FD = FD;

// Load the browser bridge in this process.
const bridge = fs.readFileSync(path.join(__dirname, '..', 'js', 'fun-bridge-ws.js'), 'utf8');
// `new WebSocket` must return our fake. Replace the global constructor used by
// the bridge by shadowing it in the evaluated scope.
const load = new Function('window', 'location', 'WebSocket', 'FD', 'TextEncoder', 'CompressionStream', 'DecompressionStream',
  bridge + '\n return window;');
const win = load(global.window, global.location, FakeConstructor, FD,
  global.TextEncoder, global.CompressionStream, global.DecompressionStream);

function encodeFrame(fdText) {
  const bytes = new TextEncoder().encode(fdText);
  const block = new Uint8Array(4 + bytes.length);
  const n = bytes.length;
  block[0] = n & 0xff;
  block[1] = (n >> 8) & 0xff;
  block[2] = (n >> 16) & 0xff;
  block[3] = (n >> 24) & 0xff;
  block.set(bytes, 4);
  return block;
}

function decodeSent(block) {
  const n = block[0] | (block[1] << 8) | (block[2] << 16) | (block[3] << 24);
  const len = n & 0x7fffffff;
  if ((n & 0x80000000) !== 0) throw new Error('unexpected compressed frame');
  return FD.parse(block.slice(4, 4 + len), 'gbk');
}

function check(name, ok) {
  console.log(`${name}: ${ok ? 'True' : 'False'}`);
  if (!ok) process.exitCode = 1;
}

async function main() {
  // ---------- fCAL -> fRET ----------
  win.__fdDispatcher.register('echo', function (args) {
    return args[0] + '-js';
  });

  const fcalText = FD.stringify({ type: 'fCAL', id: 7, name: 'echo', args: ['hi'], timeout: 0 });
  const before = ws.sent.length;
  ws.emit('message', { data: encodeFrame(fcalText).buffer });
  await new Promise(r => setTimeout(r, 20));   // handleFCAL is async

  check('fCAL produced one reply', ws.sent.length === before + 1);
  const fret = decodeSent(ws.sent[ws.sent.length - 1]);
  check('fRET type', fret.type === 'fRET');
  check('fRET id', fret.id === 7);
  check('fRET val', fret.val === 'hi-js');
  check('fRET err', !fret.err);

  // ---------- jCAL -> jRET ----------
  const p = win.Fun('ping', 'x');
  await new Promise(r => setTimeout(r, 10));
  const jcal = decodeSent(ws.sent[ws.sent.length - 1]);
  check('jCAL type', jcal.type === 'jCAL');
  check('jCAL name', jcal.name === 'ping');
  check('jCAL args', jcal.args[0] === 'x');

  const jretText = FD.stringify({ type: 'jRET', id: jcal.id, val: { ok: 1 }, err: null });
  ws.emit('message', { data: encodeFrame(jretText).buffer });
  const val = await p;
  check('jRET resolved', val && val.ok === 1);

  // ---------- unknown fCAL handler ----------
  const before2 = ws.sent.length;
  ws.emit('message', { data: encodeFrame(FD.stringify({ type: 'fCAL', id: 9, name: 'nope', args: [], timeout: 0 })).buffer });
  await new Promise(r => setTimeout(r, 20));
  check('unknown fCAL replies', ws.sent.length === before2 + 1);
  const errRet = decodeSent(ws.sent[ws.sent.length - 1]);
  check('unknown fCAL err', errRet.type === 'fRET' && errRet.err === true);
}

main();
