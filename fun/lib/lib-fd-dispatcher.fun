// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-fd-dispatcher: jCAL handler lookup, jRET replies, and fCAL/fRET
// callbacks.

class FdDispatcher(args)
  var _prefix = args?.prefix? or 'fd_';
  var _sendRaw;
  var _sendFCAL;
  var _jsCallbacks = [];
  var _jsNextId = 1;
  var _next = nil;    // Next dispatcher in the chain of responsibility

  if args?.prev? then
    args?.prev?._next = this;
    setSendRaw(args?.prev?._sendRaw);
  end if;

  // jRET send callback
  fun setSendRaw(fn)
    _sendRaw = fn;
  end fun;

  // fCAL send callback
  fun setSendFCAL(fn)
    _sendFCAL = fn;
  end fun;

  // Incoming data (jCAL only)
  fun process(data)
    var obj = data.getJson(fd: true);
    if obj = nil then return; end if;
    if obj.type = 'jCAL' then
      var p = this;
      while p loop
        var fn = p.findHandler(obj.name);
        if fn then
          p.handleCall(obj, fn, data);
          return;
        else
          p = this._next;
        end if;
      end loop;
      var res = new [type: 'jRET', id: obj.id, err: 'method not found: ' & obj.name];
      var bytes = res.@toJson(0, fd: true);
      if _sendRaw <> nil then ?, ' Ret'; ?. bytes.length();
        _sendRaw(bytes);
      end if;
    end if;
  end fun;

  // Handle a jCAL call
  fun handleCall(msg, fn)
    var id   = msg.id;
    var name = msg.name; ?, 'jCal'; ?. name;
    var args = msg.args;
    if args = nil then args = []; end if;

    var ret;
    var err;
    try
      ret = fn(args);
    except
      err = @;
    end try;

    var res = new [ type: 'jRET', id: id, val: ret, err: err ];
    var bytes = res.@toJson(0, fd: true);
    if _sendRaw <> nil then ?, ' Ret'; ?. bytes.length();
      _sendRaw(bytes);
    end if;
  end fun;

  // Resolve a local handler by name
  fun findHandler(name)
    result = this[_prefix & name.replace(/-++|\s++/g, '_')];
    if result = nil then
      result = this[_prefix & name.replace(/-++|\s++/g, '')];
    end if;
  end fun;

  // ---------- fCAL/fRET support ----------

  // Call into JavaScript
  fun callJS(name, args, maxRetSize, callback)
    if _sendFCAL = nil then
      callback(nil, 'sendFCAL not configured');
      return;
    end if;
    _jsNextId += 1;
    var id = _jsNextId;
    var msg = new [ type: 'fCAL', id: id, name: name, args: args or [], timeout: 0 ];
    var fcalBytes = msg.@toJson(0, fd: true);
    var handle = _sendFCAL(fcalBytes, maxRetSize);
    if handle <= 0 then
      callback(nil, 'send fCAL failed');
      return;
    end if;
    _jsCallbacks[id] = callback;
  end fun;

  // Handle an fRET result (invoked by Ui2Form on MSG_FCAL_RESULT, or by the
  // WebSocket host when an fRET frame arrives)
  fun handleFret(fretPayload)
    var obj = fretPayload.getJson(fd: true);
    if obj = nil then return; end if;
    if obj.type = 'fRET' then
      var id = obj.id;
      var cb = _jsCallbacks[id];
      if cb <> nil then
        _jsCallbacks[id] = nil;
        cb(obj.val, obj.err);
      end if;
    end if;
  end fun;
end class;
