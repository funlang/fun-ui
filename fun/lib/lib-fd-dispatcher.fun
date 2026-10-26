// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// lib-fd-dispatcher: jCAL handler lookup, jRET replies, and fCAL/fRET
// callbacks.

// Milliseconds since the Unix epoch. Fun's `1.time()` returns days as a
// floating-point value, so scale it here.
fun fdNowMs()
  result = 1.time() * 86400000;
end fun;

class FdDispatcher(args)
  var _prefix = args?.prefix? or 'fd_';
  var _sendRaw;
  var _sendFCAL;
  var _jsCallbacks = new [];
  var _fcalIds = new [];    // ids with an outstanding fCAL, dense for iteration
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

  // Call into JavaScript. `timeout` is in milliseconds; 0 means no timeout.
  // Expired callbacks receive (nil, 'timeout') from expire(), which the host
  // calls from its poll loop.
  fun callJS(name, args, maxRetSize, callback, timeout)
    if _sendFCAL = nil then
      callback(nil, 'sendFCAL not configured');
      return;
    end if;
    _jsNextId += 1;
    var id = _jsNextId;
    var ms = timeout or 0;
    var deadline = 0;
    if ms > 0 then
      deadline = fdNowMs() + ms;
    end if;
    var msg = new [ type: 'fCAL', id: id, name: name, args: args or [], timeout: ms ];
    var fcalBytes = msg.@toJson(0, fd: true);
    var handle = _sendFCAL(fcalBytes, maxRetSize);
    if handle <= 0 then
      callback(nil, 'send fCAL failed');
      return;
    end if;
    // Note: avoid names that collide with built-in members (e.g. `_jsPending`);
    // the collision silently creates a fresh local collection.
    _jsCallbacks[id] = new [ cb: callback, deadline: deadline ];
    _fcalIds.@add(id);
  end fun;

  // Handle an fRET result (invoked by Ui2Form on MSG_FCAL_RESULT, or by the
  // WebSocket host when an fRET frame arrives)
  fun handleFret(fretPayload)
    var obj = fretPayload.getJson(fd: true);
    if obj = nil then return; end if;
    if obj.type = 'fRET' then
      var id = obj.id;
      var entry = _jsCallbacks[id];
      if entry <> nil then
        _jsCallbacks[id] = nil;
        if entry.cb <> nil then
          entry.cb(obj.val, obj.err);
        end if;
      end if;
    end if;
  end fun;

  // Drop callbacks whose deadline has passed. Call from the host's poll loop;
  // `now` may be supplied to share one clock reading across dispatchers.
  fun expire(now)
    if _fcalIds.@count() = 0 then return; end if;
    var t = now or fdNowMs();
    var done = new [];
    for id in _fcalIds do
      var entry = _jsCallbacks[id];
      if entry <> nil and entry.deadline > 0 and t >= entry.deadline then
        _jsCallbacks[id] = nil;
        done.@add(entry);
      end if;
    end do;
    // Reply-completed ids are cleared by handleFret; drop them either way.
    _compactPending();
    if done.@count() = 0 then return; end if;
    for entry in done do
      if entry.cb <> nil then
        entry.cb(nil, 'timeout');
      end if;
    end do;
  end fun;

  // Fail every outstanding JavaScript call, for example when the page socket
  // closes or the host stops.
  fun failPending(reason)
    if _fcalIds.@count() = 0 then return; end if;
    var done = new [];
    for id in _fcalIds do
      var entry = _jsCallbacks[id];
      _jsCallbacks[id] = nil;
      if entry <> nil then done.@add(entry); end if;
    end do;
    _fcalIds = new [];
    for entry in done do
      if entry.cb <> nil then
        entry.cb(nil, reason or 'cancelled');
      end if;
    end do;
  end fun;

  fun _compactPending()
    var alive = new [];
    for id in _fcalIds do
      if _jsCallbacks[id] <> nil then alive.@add(id); end if;
    end do;
    _fcalIds = alive;
  end fun;
end class;
