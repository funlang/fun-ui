########################################
# fun-ui - lib-fd-dispatcher-proc
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
use 'lib-os.fun';
use 'lib-fd-dispatcher.fun';

var FILE_NOTIFY_CHANGE_SIZE       = 0x00000008;
var FILE_NOTIFY_CHANGE_LAST_WRITE = 0x00000010;

class DirWatcher(dir, pattern, timeout, onFile)
  var _dir = dir;
  var _pattern = pattern or '*.fd';
  var _timeout = timeout or 30000;
  var _onFile = onFile;
  var _running = true;
  var _hfchange = fileChanged(_dir, false,
    FILE_NOTIFY_CHANGE_SIZE bit or FILE_NOTIFY_CHANGE_LAST_WRITE
  );

  fun run()
    if _hfchange = -1 then
      _pollingLoop();
    else
      _eventLoop();
    end if;
  end fun;

  fun stop()
    _running = false;
    if _hfchange <> -1 then
      closeHandle(_hfchange);
      _hfchange = -1;
    end if;
  end fun;

  fun _eventLoop()
    loop
      exit when not _running;
      if wait(_hfchange, _timeout) = 0 then
        _processChanges();
      end if;
      nextChanged(_hfchange);
    end loop;
  end fun;

  fun _pollingLoop()
    loop
      exit when not _running;
      _processChanges();
      sleep(3000);
    end loop;
  end fun;

  fun _processChanges()
    var files = '%s\%s'.format(_dir, _pattern).find();
    for f in files do
      exit when not _running;
      _onFile(f);
    end do;
  end fun;

  fun destroy()
    stop();
  end fun;
end class;

class FdProcDispatcher = FdDispatcher()
  var _taskDir = args?.taskDir? or 'tasks';
  var _isTest = args?.isTest? or false;
  var _watcher = DirWatcher('%s\out'.format(_taskDir), '*.fd',
    ifv(_isTest, 6000, 30000),
    (f){
      if _sendRaw <> nil then
        _sendRaw(f.load());
        f.move();
      end if;
    }
  );

  fun init()
    startThread(-> _watcher.run());
  end fun;

  fun handleCall(msg, fn, data)
    var taskFile = '%s\in\task-%s-%s.fd'.format(_taskDir,
      1.time().format('yyyymmddhhnnsszzz'), msg.id);
    var tmp = taskFile & '.tmp';
    tmp.save(data);
    tmp.move(taskFile);
  end fun;

  fun findHandler(name)
    result = 1;
  end fun;

  fun destroy()
    if _watcher <> nil then
      _watcher.stop();
    end if;
  end fun;
end class;

class FdProcWorker = FdDispatcher()
  var _taskDir = args?.taskDir? or 'tasks';
  var _isTest = args?.isTest? or false;
  var _watcher = DirWatcher('%s\in'.format(_taskDir), '*.fd',
    ifv(_isTest, 6000, 30000),
    (f){ _processTask(f); }
  );

  fun run()
    _watcher.run();
  end fun;

  fun _processTask(f)
    var ingName = '';
    try
      ingName = '%s\ing\task-%s-%s.fd'.format(_taskDir,
        1.time().format('yyyymmddhhnnsszzz'),
        0.random()
      );
      f.move(ingName);
    except
      return;
    end try;

    try
      var content = ingName.load();

      setSendRaw((s){
        var ret = '%s\out\ret-%s-%s'.format(_taskDir,
          1.time().format('yyyymmddhhnnsszzz'),
          ingName.replace(/^[^\\]*+\\/g, '')
        );
        ret.save(s);
        ingName.move('%s\done\'.format(_taskDir));
      });

      process(content);
    except
      try
        ingName.move('%s\in\'.format(_taskDir));
      except
        ingName.move('%s\error\'.format(_taskDir));
      end try;
    end try;
  end fun;

  fun destroy()
    if _watcher <> nil then
      _watcher.stop();
    end if;
  end fun;
end class;
