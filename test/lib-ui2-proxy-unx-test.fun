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
use 'lib-os.fun';

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

// WebSocket upgrade with explicit path, Origin, and Host headers.
fun wsTry(port, path, origin, host)
  var c = ConnectSocket('127.0.0.1', port);
  var crlf = 13.toChar() & 10.toChar();
  var req = 'GET ' & path & ' HTTP/1.1' & crlf;
  if host <> nil then
    req &= 'Host: ' & host & crlf;
  else
    req &= 'Host: 127.0.0.1:' & port & crlf;
  end if;
  if origin <> nil then req &= 'Origin: ' & origin & crlf; end if;
  req &= 'Upgrade: websocket' & crlf &
         'Connection: Upgrade' & crlf &
         'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' & crlf &
         'Sec-WebSocket-Version: 13' & crlf & crlf;
  SendAll(c, req.escape());
  result = c;
end fun;

fun hasText(s, t)
  if s = nil then result = false; else result = s.subpos(t) >= 0; end if;
end fun;

class TestDispatcher = FdDispatcher()
  var probeCount = 0;
  fun fd_ping(args)
    result = new [pong: args[0], answer: 42];
  end fun;
  fun fd_probe(args)
    probeCount += 1;
    result = true;
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

//--------------------------------------------------------------
// 8. cross-site WebSocket requests are rejected
//--------------------------------------------------------------
var probeCall = 'type jCAL' & 10.toChar() & 'id 11' & 10.toChar() &
                'name probe' & 10.toChar() & 'args' & 10.toChar() & 'timeout 0';

fun wsHeader(origin, host)
  var h = 'GET / HTTP/1.1' & 13.toChar() & 10.toChar() &
          'Host: ' & host & 13.toChar() & 10.toChar();
  if origin <> nil then h &= 'Origin: ' & origin & 13.toChar() & 10.toChar(); end if;
  result = h & 13.toChar() & 10.toChar();
end fun;

var sameOrigin = 'http://127.0.0.1:' & port;
?. 'same-origin allowed: ' & (p._checkWebSocket('/', wsHeader(sameOrigin, '127.0.0.1:' & port)) = '');
?. 'cross-origin denied: ' & (p._checkWebSocket('/', wsHeader('https://evil.example', '127.0.0.1:' & port)) <> '');
// DNS rebinding: Origin and Host agree, but the host is not an IP literal.
?. 'rebinding denied: ' & (p._checkWebSocket('/', wsHeader('http://evil.example:' & port, 'evil.example:' & port)) <> '');
?. 'missing origin allowed: ' & (p._checkWebSocket('/', wsHeader(nil, '127.0.0.1:' & port)) = '');
?. 'unknown path denied: ' & (p._checkWebSocket('/other', wsHeader(nil, '127.0.0.1:' & port)) <> '');

// One live rejection: the frame is dropped and the socket is closed.
var before = p.dispatcher.probeCount;
var bad = wsTry(port, '/', 'https://evil.example', nil);
pump(p, 3);
var badHs = RecvSome(bad, 4096);
?. 'cross-origin upgrade answered: ' & hasText(badHs, ' 101 ');
try SendAll(bad, wsMasked(ui2Frame(probeCall, false, 0))); except end try;
pump(p, 3);
var badRest = RecvSome(bad, 4096);
?. 'cross-origin call rejected: ' & (p.dispatcher.probeCount = before);
?. 'cross-origin reply suppressed: ' & (not hasText(badRest, 'jRET'));
CloseSocket(bad);

//--------------------------------------------------------------
// 9. oversize frames are dropped before dispatch
//--------------------------------------------------------------
var probeBefore3 = p.dispatcher.probeCount;
var limit = p.maxFrameBytes;
p.maxFrameBytes = 64;
var big = wsTry(port, '/', nil, nil);
pump(p, 3);
RecvSome(big, 4096);
var bigCall = 'type jCAL' & 10.toChar() & 'id 12' & 10.toChar() &
              'name probe' & 10.toChar() & 'args' & 10.toChar() & 'timeout 0' &
              'x'.x(200);
SendAll(big, wsMasked(ui2Frame(bigCall, false, 0)));
pump(p, 3);
?. 'oversize frame ignored: ' & (p.dispatcher.probeCount = probeBefore3);
p.maxFrameBytes = limit;
CloseSocket(big);

//--------------------------------------------------------------
// 10. fCAL timeout expires the callback
//--------------------------------------------------------------
var toErr = nil;
p.dispatcher.callJS('never', [], 0, (v, e){ toErr = e; }, 80);
var fcalTimeout = wsPayload(RecvSome(w, 65536));
?. 'timeout fCAL sent: ' & hasText(fcalTimeout, 'type fCAL');
for i = 1 to 30 do
  p.RunOnce(20);
  sleep(10);
  exit when toErr <> nil;
end do;
?. 'fCAL timeout err: ' & (toErr = 'timeout');

//--------------------------------------------------------------
// 11. closing the page socket cancels outstanding fCAL callbacks
//--------------------------------------------------------------
var closeErr = nil;
p.dispatcher.callJS('never', [], 0, (v, e){ closeErr = e; }, 0);
RecvSome(w, 65536);
var closeFrame = 0x88.toChar() & 0x80.toChar() & 1.toChar() & 2.toChar() & 3.toChar() & 4.toChar();
SendAll(w, closeFrame);
pump(p, 5);
?. 'close cancels pending: ' & (closeErr = 'connection closed');

CloseSocket(w);
p.Stop();

//--------------------------------------------------------------
// 12. optional token: injected into the page and required on upgrade.
// Runs after the first proxy is stopped: the Unix winsock server keeps
// per-process poll state, so only one proxy should be live at a time.
//--------------------------------------------------------------
var p2 = Ui2Proxy();
p2.port = 0;
p2.jsDir = 'js';
p2.page = '<html><head><title>t</title></head><body>token-page</body></html>';
p2.token = 's3cret';
p2.dispatcher = TestDispatcher();
var port2 = p2.Start();
var c3 = httpGet(port2, '/');
pump(p2, 3);
var page2 = RecvSome(c3, 65536);
CloseSocket(c3);
?. 'token injected: ' & hasText(page2, 'token=s3cret');
?. 'token before bridge: ' & (page2.subpos('token=s3cret') < page2.subpos('fun-bridge-ws.js'));

var noTok = wsTry(port2, '/', nil, nil);
pump(p2, 3);
RecvSome(noTok, 4096);
try SendAll(noTok, wsMasked(ui2Frame(probeCall, false, 0))); except end try;
pump(p2, 3);
?. 'missing token rejected: ' & (p2.dispatcher.probeCount = 0);
CloseSocket(noTok);

var withTok = wsTry(port2, '/?token=s3cret', nil, nil);
pump(p2, 3);
RecvSome(withTok, 4096);
SendAll(withTok, wsMasked(ui2Frame(probeCall, false, 0)));
pump(p2, 3);
var tokRet = RecvSome(withTok, 65536);
?. 'token accepted: ' & (p2.dispatcher.probeCount = 1 and hasText(tokRet, 'jRET'));
CloseSocket(withTok);
p2.Stop();
?. 'RESULT: OK';
