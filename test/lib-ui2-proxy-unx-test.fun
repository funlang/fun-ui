// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-proxy-unx: HTTP page + WebSocket jCAL/jRET + fCAL/fRET test.
//
// Self-contained loopback test. It drives the poll loop by hand, so it runs
// without a browser and without a window. Run from the fun-ui repository root:
//
//     funcmd test/lib-ui2-proxy-unx-test.fun
//
// (If your Fun binary lives elsewhere, adjust the path; the `use` below is
// relative to this file.)

use '../fun/lib/lib-ui2-proxy-unx.fun';
use 'lib-winsock.fun';

fun pump(p, n)
  for i = 1 to n do
    exit when p.RunOnce(200) = 0;
  end do;
end fun;

// client -> server frame (masked, FIN + text opcode, length < 126)
fun wsMasked(s)
  var n = s.length();
  var h;
  if n < 126 then
    h = 0x81.toChar() & (0x80 bit or n).toChar();
  else
    h = 0x81.toChar() & 126.toChar() & (n div 256).toChar() & (n mod 256).toChar();
  end if;
  var m = [1, 2, 3, 4];
  var body = '';
  for i = 0 to n - 1 do
    body &= (s.toByte(i) bit xor m[i mod 4]).toChar();
  end do;
  result = h & m[0].toChar() & m[1].toChar() & m[2].toChar() & m[3].toChar() & body;
end fun;

// extract the FD payload from a server WebSocket frame (2-byte header + block)
fun wsPayload(resp)
  var block = resp.substr(2);
  var n = block.toByte(0) bit or (block.toByte(1) << 8) bit or
          (block.toByte(2) << 16) bit or (block.toByte(3) << 24);
  var compressed = (n bit and 0x80000000) <> 0;
  var len = n bit and 0x7FFFFFFF;
  var payload = block.substr(4, len);
  if compressed then payload = inflate(payload); end if;
  result = payload;
end fun;

fun httpGet(port, path)
  var c = ConnectSocket('127.0.0.1', port);
  SendAll(c, ('GET ' & path & ' HTTP/1.1' & 13.toChar() & 10.toChar() &
              'Host: x' & 13.toChar() & 10.toChar() & 13.toChar() & 10.toChar()).escape());
  result = c;
end fun;

fun wsConnect(port)
  var c = ConnectSocket('127.0.0.1', port);
  var req = 'GET /ws HTTP/1.1' & 13.toChar() & 10.toChar() &
            'Host: x' & 13.toChar() & 10.toChar() &
            'Upgrade: websocket' & 13.toChar() & 10.toChar() &
            'Connection: Upgrade' & 13.toChar() & 10.toChar() &
            'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' & 13.toChar() & 10.toChar() &
            'Sec-WebSocket-Version: 13' & 13.toChar() & 10.toChar() & 13.toChar() & 10.toChar();
  SendAll(c, req.escape());
  result = c;
end fun;

class TestDispatcher = FdDispatcher()
  fun fd_ping(args)
    result = new [pong: args[0], answer: 42];
  end fun;
end class;

var p = Ui2Proxy();
p.port = 0;
p.jsDir = 'js';   // relative to the repository root
p.page = '<html><head><title>t</title></head><body>hello-ui</body></html>';
p.dispatcher = TestDispatcher();
var port = p.Start();
?. 'bound port: ' & (port > 0);
?. 'url: ' & p.Url();

//--------------------------------------------------------------
// 1. HTTP page + bridge injection
//--------------------------------------------------------------
var c1 = httpGet(port, '/');
pump(p, 5);
var page = RecvSome(c1, 65536);
CloseSocket(c1);
?. 'page 200: ' & (page.subpos(' 200 ') >= 0);
?. 'page body: ' & (page.subpos('hello-ui') >= 0);
?. 'page injects fd.js: ' & (page.subpos('/fd.js') >= 0);
?. 'page injects ws bridge: ' & (page.subpos('/fun-bridge-ws.js') >= 0);

//--------------------------------------------------------------
// 2. bridge script is served from jsDir
//--------------------------------------------------------------
var c2 = httpGet(port, '/fun-bridge-ws.js');
pump(p, 5);
var js = RecvSome(c2, 65536);
CloseSocket(c2);
?. 'asset 200: ' & (js.subpos(' 200 ') >= 0);
?. 'asset has handleFCAL: ' & (js.subpos('function handleFCAL') >= 0);
?. 'asset has fRET: ' & (js.subpos('fRET') >= 0);

//--------------------------------------------------------------
// 3. WebSocket handshake
//--------------------------------------------------------------
var w = wsConnect(port);
pump(p, 5);
var hs = RecvSome(w, 4096);
?. 'handshake 101: ' & (hs.subpos(' 101 ') >= 0);

//--------------------------------------------------------------
// 4. jCAL -> jRET
//--------------------------------------------------------------
var call = 'type jCAL' & 10.toChar() & 'id 1' & 10.toChar() &
           'name ping' & 10.toChar() & 'args' & 10.toChar() &
           '  - hello' & 10.toChar() & 'timeout 0';
SendAll(w, wsMasked(ui2Frame(call, false, 0)));
pump(p, 5);
var resp = wsPayload(RecvSome(w, 65536));
?. 'jRET type: ' & (resp.subpos('type jRET') >= 0);
?. 'jRET pong: ' & (resp.subpos('pong hello') >= 0);
?. 'jRET answer: ' & (resp.subpos('answer 42') >= 0);

//--------------------------------------------------------------
// 5. fCAL -> fRET (Fun calls JavaScript; browser answers over the socket)
//--------------------------------------------------------------
var gotVal = nil;
var gotErr = nil;
p.dispatcher.callJS('echo', ['hi'], 0, (val, err){ gotVal = val; gotErr = err; });
var fcal = wsPayload(RecvSome(w, 65536));
?. 'fCAL type: ' & (fcal.subpos('type fCAL') >= 0);
?. 'fCAL name: ' & (fcal.subpos('name echo') >= 0);
SendAll(w, wsMasked(ui2Frame('type fRET' & 10.toChar() & 'id 2' & 10.toChar() &
                             'val ok' & 10.toChar() & 'err null', false, 0)));
pump(p, 5);
?. 'fRET callback val: ' & (gotVal = 'ok');
?. 'fRET callback err: ' & (gotErr = nil);

//--------------------------------------------------------------
// 6. compressed frames in both directions
//--------------------------------------------------------------
p.setCompress(true, 1);   // 0 is nil in Fun, so use the smallest positive size
var call2 = 'type jCAL' & 10.toChar() & 'id 3' & 10.toChar() &
            'name ping' & 10.toChar() & 'args' & 10.toChar() &
            '  - zipped' & 10.toChar() & 'timeout 0';
SendAll(w, wsMasked(ui2Frame(call2, true, 0)));
pump(p, 5);
var rawBlock = RecvSome(w, 65536);
var hdr = rawBlock.substr(2, 4);
var lenInfo = hdr.toByte(0) bit or (hdr.toByte(1) << 8) bit or
              (hdr.toByte(2) << 16) bit or (hdr.toByte(3) << 24);
?. 'response compressed flag: ' & ((lenInfo bit and 0x80000000) <> 0);
var cresp = wsPayload(rawBlock);
?. 'compressed jRET ok: ' & (cresp.subpos('type jRET') >= 0 and cresp.subpos('pong zipped') >= 0);

//--------------------------------------------------------------
// 7. one client's binary push (PostData) reaches the page socket
//--------------------------------------------------------------
p.PostData('raw-push');
var push = RecvSome(w, 65536);
?. 'postdata frame: ' & (wsPayload(push) = 'raw-push');

CloseSocket(w);
p.Stop();
?. 'RESULT: OK';
