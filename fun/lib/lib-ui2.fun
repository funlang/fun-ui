########################################
# fun-ui - lib-ui2
# Copyright (c) 2026 funlang.org
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
########################################
use 'lib-ui.fun';
use 'lib-zlib.fun';
use 'lib-async.fun';

var MSG_ERROR   = 0;
var MSG_CREATED = 1;
var MSG_TITLE   = 2;
var MSG_BINARY  = 3;
var MSG_FCAL_RESULT = 5;       // fCAL result callback
var WMX_Async   = 0x765;

var @libwv2dll;

class Ui2Form = BaseForm()
  var main;
  var _compress         = false;
  var _compressMinSize  = 512;

  @libwv2dll.getapi('Init', 'c:i').call(onEvent.@toCallback(this, 'iiii:i'));

  // ---------- Build the full send block (4-byte length header) ----------
  fun _buildBlock(data)
    var dataLen = data.length();
    var block;
    if _compress and dataLen >= _compressMinSize then
      var raw = deflate(data);
      if raw <> nil and raw.length() > 0 then
        var rawLen = raw.length();
        // Allocate the buffer and write the length header (bit 31 = compressed)
        block = 0.toChar().x(4 + rawLen);
        block[0.1] = rawLen bit and 0xFF;
        block[1.1] = (rawLen >> 8) bit and 0xFF;
        block[2.1] = (rawLen >> 16) bit and 0xFF;
        block[3.1] = ((rawLen >> 24) bit or 0x80) bit and 0xFF; // Set bit 31
        raw.move(block.toNum(-1) + 4, rawLen);  ?, dataLen; ?, '-[C]->'; ?. rawlen;
        return block;
      end if;
    end if;
    // Uncompressed
    block = 0.toChar().x(4 + dataLen);
    block[0.1] = dataLen bit and 0xFF;
    block[1.1] = (dataLen >> 8) bit and 0xFF;
    block[2.1] = (dataLen >> 16) bit and 0xFF;
    block[3.1] = (dataLen >> 24) bit and 0xFF;
    data.move(block.toNum(-1) + 4, dataLen);
    return block;
  end fun;

  // ---------- Unpack: extract and decompress the payload from callback arguments ----------
  fun _unpackBlock(wParam, lParam)
    var buf = 0.toChar().x(lParam);
    wParam.move(buf.toNum(-1), lParam);
    if lParam < 4 then return ''; end if;
    var lenInfo = buf[0.1] bit or (buf[1.1] << 8) bit or (buf[2.1] << 16) bit or (buf[3.1] << 24);
    var actualLen = lenInfo bit and 0x7FFFFFFF;
    var compressed = (lenInfo bit and 0x80000000) <> 0;
    if actualLen = 0 or actualLen > lParam - 4 then return ''; end if;
    var payload = buf.substr(4, actualLen);
    if compressed then
      payload = inflate(payload); ?. payload.length();
    end if;
    return payload;
  end fun;

  fun onEvent(hwnd, msg, wParam, lParam)
    result = false; ?, 'onEvent'; ?. msg;
    case msg is
      when MSG_ERROR do ?. 'WV2 error: ' & lParam;
      when MSG_CREATED do
        this.onReady();
        user32.getapi('SetParent', 'ii:i').call(this.hWnd, this.main.hWnd);
        this.ShowMax();
      when MSG_TITLE do
        var cap = ' '.x(lParam);
        wParam.move(cap.toNum(-1), lParam);
        this.main.setCaption(cap);
      when MSG_BINARY do
        var payload = this._unpackBlock(wParam, lParam);
        if payload <> '' then
          if this.dispatcher <> nil then
            try
              this.dispatcher.process(payload);
            except
              ?. '$@ @ $@@()'.eval();
            end try;
          else
            this.onBinary(payload);
          end if;
        end if;
      when MSG_FCAL_RESULT do
        // Handle an fCAL result
        var buf = 0.toChar().x(lParam);
        wParam.move(buf.toNum(-1), lParam);
        if lParam < 4 then return; end if;
        var retLen = buf[0.1] bit or (buf[1.1] << 8) bit or (buf[2.1] << 16) bit or (buf[3.1] << 24);
        if retLen = 0 or retLen > lParam - 4 then return; end if;
        var retPayload = buf.substr(4, retLen);
        if this.dispatcher <> nil then
          this.dispatcher.handleFret(retPayload);
        else
          this.onBinary(retPayload);
        end if;
    end case;
  end fun;

  fun Show(main)
    this.main = main or Form(caption, onMsg: onMainMsg.@toCallback(this, 'iiii:i', true));
    this.main.show();
    this.hWnd = @libwv2dll.getapi('Show', 'i:i').call(this.main.hWnd);
    if this.dispatcher <> nil then
      var self = this;
      this.dispatcher.setSendRaw( data -> self.PostData(data) );
      this.dispatcher.setSendFCAL( (data, maxRetSize) -> self.PostData(data, maxRetSize) );
      this.onInitDispatch?(this.dispatcher);
    end if;
  end fun;

  fun onReady() end fun;
  fun onBinary(data) end fun;

  fun Navigate(url)
    @libwv2dll.getapi('Navigate', 's:i').call(url);
  end fun;

  // Send a payload, with an optional negative maxRetSize for the fCAL response buffer
  fun PostData(data, maxRetSize)
    var block = this._buildBlock(data);
    var len = block.length();
    if maxRetSize > 0 then
      len = max(len, maxRetSize) * -1;
    end if;
    @libwv2dll.getapi('PostData', 'ii:i').call(block.toNum(-1), len);
  end fun;

  fun ExecScript(script)
    @libwv2dll.getapi('ExecScript', 's:i').call(script);
  end fun;

  fun OnClose()
    if this.hWnd then
      @libwv2dll.getapi('Close', ':i').call();
    end if;
    @libwv2dll.getapi('Free', ':i').call();
  end fun;

  fun onMessage(hwnd, message, wParam, lParam) end fun;
  fun onMainMsg(hwnd, message, wParam, lParam)
    result = false;
    try
      case message is
        when 5 do // WM_SIZE
          this.main.Move(this.hWnd, 0, 0, lParam bit and 0xffff, lParam >> 16);
        when 0x10 do // WM_CLOSE
          this.OnClose();
        when WMX_Async do
          result = onAsyncMsg(hwnd, message, wParam, lParam);
        else
          result = this.onMessage(hwnd, message, wParam, lParam);
      end case;
    except
      ?. '$@ @ $@@()'.eval();
    end try;
  end fun;

  fun setCompress(flag, minSize)
    _compress = flag;
    if minSize <> nil then _compressMinSize = minSize; end if;
  end fun;
end class;
