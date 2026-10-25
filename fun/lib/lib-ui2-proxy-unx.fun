// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-ui2-proxy-unx: the portable WebSocket host for Linux and macOS.
//
// Unlike the Windows lib-ui2-proxy.fun (which is built on Ui2Form/WebView2),
// this implementation owns no window and does not load libwv2. It serves the
// page and the bridge scripts over HTTP and speaks the same length-prefixed
// WebSocket frames as the WebView2 transport, so an ordinary Chromium browser
// can connect to http://<ip>:<port>/.
//
//     use 'fun/lib/lib-ui2-proxy.fun';   // resolves to this file on Unix
//
//     var p = Ui2Proxy();
//     p.jsDir = '/path/to/fun-ui/js';
//     p.page  = '<h1>Hello</h1>';
//     p.dispatcher = MyDispatcher();
//     p.Start();          // non-blocking, returns the bound port
//     p.Run();            // blocking poll loop (or drive with RunOnce)
//
// The wire protocol is unchanged: every message is a 4-byte little-endian
// length header (bit 31 = raw DEFLATE) followed by an FD document. Incoming
// jCAL calls go to the dispatcher; outgoing jRET/fCAL frames are wrapped the
// same way. fCAL responses arrive as ordinary fRET messages instead of the
// shared-buffer handle used by WebView2.
//
// Handlers run inline on the poll loop. jRET replies go to the socket that
// issued the jCAL call. Frames pushed outside a handler (fCAL callbacks,
// PostData) go to the most recently active page connection, which is what a
// single-page UI needs; use one proxy per page for strict multi-client routing.

use 'lib-winsock.fun';
use 'lib-host.fun';
use 'lib-os.fun';
use 'lib-zlib.fun';
use 'lib-fd-dispatcher.fun';

var @proxyIP   = '127.0.0.1';
var @proxyPort = 8278;
var @proxyJsDir = 'js';

var PROXY_STATIC = ['fd.js', 'fd2.js', 'fun-bridge-ws.js'];

//--------------------------------------------------------------
// framing helpers (same layout as Ui2Form._buildBlock)
//--------------------------------------------------------------
fun ui2Frame(data, compress, minSize)
  var payload = data;
  var flag = 0;
  if compress and data.length() >= minSize then
    var raw = deflate(data);
    if raw <> nil and raw.length() > 0 then
      payload = raw;
      flag = 0x80000000;
    end if;
  end if;

  var n = payload.length();
  var block = 0.toChar().x(4 + n);
  var lenInfo = n bit or flag;
  block.fromByte(0, lenInfo bit and 0xFF);
  block.fromByte(1, (lenInfo >> 8) bit and 0xFF);
  block.fromByte(2, (lenInfo >> 16) bit and 0xFF);
  block.fromByte(3, (lenInfo >> 24) bit and 0xFF);
  payload.move(block.toNum(-1) + 4, n);
  result = block;
end fun;

fun ui2Unframe(body)
  if body = nil or body.length() < 4 then
    result = nil;
    return;
  end if;
  var lenInfo = body.toByte(0) bit or (body.toByte(1) << 8) bit or
                (body.toByte(2) << 16) bit or (body.toByte(3) << 24);
  var n = lenInfo bit and 0x7FFFFFFF;
  var compressed = (lenInfo bit and 0x80000000) <> 0;
  if n = 0 or n > body.length() - 4 then
    result = nil;
    return;
  end if;
  var payload = body.substr(4, n);
  if compressed then
    payload = inflate(payload);
  end if;
  result = payload;
end fun;

fun ui2JsonType(payload)
  var msg = payload.getJson(fd: true);
  if msg = nil then result = ''; else result = '' & msg.type; end if;
end fun;

//--------------------------------------------------------------
// static page helpers
//--------------------------------------------------------------
fun ui2Mime(name)
  var n = name.lower();
  if n =~ /\.js$/ then result = 'application/javascript; charset=utf-8';
  elsif n =~ /\.css$/ then result = 'text/css; charset=utf-8';
  elsif n =~ /\.html?$/ then result = 'text/html; charset=utf-8';
  elsif n =~ /\.json$/ then result = 'application/json; charset=utf-8';
  elsif n =~ /\.png$/ then result = 'image/png';
  elsif n =~ /\.jpe?g$/ then result = 'image/jpeg';
  elsif n =~ /\.gif$/ then result = 'image/gif';
  elsif n =~ /\.svg$/ then result = 'image/svg+xml';
  else result = 'application/octet-stream';
  end if;
end fun;

fun ui2InjectBridge(page)
  // Never inject twice; pages may already include the scripts.
  if page.subpos('fun-bridge-ws.js') >= 0 or page.subpos('fun-bridge.js') >= 0 then
    result = page;
    return;
  end if;
  var tag = '<script src="/fd.js"></script>
<script src="/fun-bridge-ws.js"></script>';
  var at = page.lower().subpos('</head>');
  if at >= 0 then
    result = page.substr(0, at) & tag & page.substr(at);
  else
    result = tag & page;
  end if;
end fun;

//--------------------------------------------------------------
// Ui2Proxy
//--------------------------------------------------------------
class Ui2Proxy(args)
  var ip    = @proxyIP;
  var port  = @proxyPort;
  var jsDir = @proxyJsDir;
  var page  = '';
  var dispatcher = nil;
  var autoOpen = false;

  var _server = nil;
  var _running = false;
  var _current = nil;   // socket of the request being dispatched
  var _last = nil;      // most recent page socket, for Fun-initiated fCAL
  var _compress = false;
  var _compressMinSize = 512;

  if args then
    if args.ip <> nil then ip = args.ip; end if;
    if args.port <> nil then port = args.port; end if;
    if args.jsDir <> nil then jsDir = args.jsDir; end if;
    if args.page <> nil then page = args.page; end if;
    if args.dispatcher <> nil then dispatcher = args.dispatcher; end if;
    if args.autoOpen <> nil then autoOpen = args.autoOpen; end if;
  end if;

  //---- lifecycle ------------------------------------------------
  fun Start()
    var self = this;
    // Derived classes get a chance to set page/dispatcher here.
    this.onReady();

    if dispatcher <> nil then
      dispatcher.setSendRaw( data -> self._sendRaw(data) );
      dispatcher.setSendFCAL( (data, maxRetSize) -> self._sendFCAL(data, maxRetSize) );
    end if;

    _server = Server.HTTP(ip, port,
      (req, header, body, sock, wargs) {
        self._handle(req, header, body, sock, wargs);
      });
    _server.Start();
    _running = true;
    result = _server.LocalPort();

    if autoOpen then
      this.OpenBrowser();
    end if;
  end fun;

  fun RunOnce(timeout)
    if _server = nil then result = 0; return; end if;
    result = _server.RunOnce(timeout or 200);
  end fun;

  fun Run(timeout)
    if _server = nil then this.Start(); end if;
    while _running loop
      _server.RunOnce(timeout or 200);
    end loop;
  end fun;

  // Compatibility with the form-based API: Start then block on the poll loop.
  fun Show()
    this.Start();
    this.Run();
  end fun;

  fun Close()
    this.Stop();
  end fun;

  fun Stop()
    _running = false;
    if _server <> nil then
      _server.Stop(); ?. 'Ui2Proxy stopped.';
      _server = nil;
    end if;
  end fun;

  fun LocalPort()
    if _server = nil then result = 0; else result = _server.LocalPort(); end if;
  end fun;

  fun Url()
    result = 'http://' & ip & ':' & this.LocalPort() & '/';
  end fun;

  fun OpenBrowser()
    var url = this.Url();
    if IsMac() then
      execShow('open', url, nil);
    else
      execShow('xdg-open', url, nil);
    end if;
    result = url;
  end fun;

  // Hooks kept from Ui2Form.
  fun onReady() end fun;
  fun onBinary(data) this.PostData(data); end fun;
  fun onMessage(hwnd, message, wParam, lParam) result = false; end fun;

  //---- page -----------------------------------------------------
  // A string starting with '<' is HTML; anything else is treated as a file
  // path and loaded when the page is first requested.
  fun Navigate(urlOrHtml)
    page = urlOrHtml;
  end fun;

  fun SetPage(html)
    page = html;
  end fun;

  fun PageHtml()
    var p = page;
    if p = nil or p = '' then
      p = '<!doctype html><html><head><meta charset="utf-8"><title>fun-ui</title></head><body><h1>fun-ui</h1></body></html>';
    elsif p.substr(0, 1) <> '<' then
      var loaded = nil;
      try loaded = p.load(); except loaded = nil; end try;
      if loaded = nil then
        p = '<!doctype html><html><head><meta charset="utf-8"><title>fun-ui</title></head><body><p>page not found: ' & p & '</p></body></html>';
      else
        p = loaded;
      end if;
    end if;
    result = ui2InjectBridge(p);
  end fun;

  fun Asset(name)
    var s = nil;
    try s = (jsDir & '/' & name).load(); except s = nil; end try;
    result = s;
  end fun;

  //---- transport ------------------------------------------------
  fun setCompress(flag, minSize)
    _compress = flag;
    if minSize <> nil then _compressMinSize = minSize; end if;
  end fun;

  fun _sendTo(sock, data)
    if sock = nil or _server = nil then return; end if;
    _server.Reply(ui2Frame(data, _compress, _compressMinSize), sock, [bin: true]);
  end fun;

  fun _sendRaw(data)
    this._sendTo(_current or _last, data);
  end fun;

  // WebSocket has no shared response buffer, so return a non-zero synthetic
  // handle; the browser answers with a normal fRET and handleFret() finds the
  // callback by message id.
  fun _sendFCAL(data, maxRetSize)
    var sock = _current or _last;
    if sock = nil then result = 0; return; end if;
    this._sendTo(sock, data);
    result = 1;
  end fun;

  // Public push channel, matching Ui2Form.PostData.
  fun PostData(data, maxRetSize)
    this._sendTo(_current or _last, data);
  end fun;

  fun _handle(req, header, body, sock, wargs)
    if wargs and wargs.webSocket then
      this._handleWs(body, sock, wargs.op bit and 0x0F);
    else
      this._handleHttp(req, sock);
    end if;
  end fun;

  fun _handleHttp(req, sock)
    var path = req;
    var qi = path.subpos('?');
    if qi >= 0 then path = path.substr(0, qi); end if;

    if path = '' or path = '/' or path = '/index.html' then
      _server.Reply200(this.PageHtml(), sock,
        new ['Content-Type': 'text/html; charset=utf-8']);
      return;
    end if;

    var name = path;
    if name.substr(0, 1) = '/' then name = name.substr(1); end if;

    if name in PROXY_STATIC then
      var s = this.Asset(name);
      if s = nil then
        _server.Reply404('asset not found: ' & name, sock);
      else
        _server.Reply200(s, sock, new ['Content-Type': ui2Mime(name)]);
      end if;
      return;
    end if;

    if name = 'favicon.ico' then
      _server.Reply200('', sock, new ['Content-Type': 'image/x-icon']);
      return;
    end if;

    _server.Reply404('not found: ' & path, sock);
  end fun;

  fun _handleWs(body, sock, op)
    if op = 8 then                       // close
      _server.Reply('', sock, [bin: true, close: true]);
      if _last = sock then _last = nil; end if;
      return;
    end if;
    if op = 9 then                       // ping
      _server.Reply(body, sock, [bin: true, pong: true]);
      return;
    end if;
    if op = 10 then return; end if;      // pong

    _last = sock;
    _current = sock;
    try
      var payload = ui2Unframe(body);
      if payload <> nil and payload <> '' then
        var kind = ui2JsonType(payload);
        if kind = 'fRET' then
          if this.dispatcher <> nil then
            this.dispatcher.handleFret(payload);
          else
            this.onBinary(payload);
          end if;
        elsif this.dispatcher <> nil then
          this.dispatcher.process(payload);
        else
          this.onBinary(payload);
        end if;
      end if;
    except
      ?. 'Ui2Proxy: ' & @;
    end try;
    _current = nil;
  end fun;
end class;
