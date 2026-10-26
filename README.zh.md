# fun-ui

[Fun](https://funlang.org) 编程语言的浏览器界面组件。

**简体中文**（本文件） - [English](README.md)

- 版本：**1.0.1**
- 网站：<https://funlang.org>
- 许可证：MIT（见 [LICENSE](LICENSE)）

`fun-ui` 负责把 Fun 脚本和 Web 界面连接起来。Fun 进程持有窗口和业务逻辑，
界面是运行在 Chromium 内核浏览器中的普通 HTML、CSS 和 JavaScript。调用可以
双向传递：

- **jCAL / jRET**：JavaScript 调用 Fun 方法并取得返回值。
- **fCAL / fRET**：Fun 调用 JavaScript 处理函数并取得返回值。

项目提供两种传输方式。WebView2 方式通过一个很小的 Delphi DLL 把 Chromium
直接嵌入 Fun 窗口；WebSocket 方式用套接字代替共享内存来传递同样的消息。
两种方式共用同一套消息格式和 JavaScript API。在 Linux 和 macOS 上，
WebSocket 方式不再需要窗口：它通过 HTTP 提供页面和桥接脚本，让普通浏览器
直接连接。

## 项目状态与路线图

**状态：** WebView2 宿主（`libwv2.dll`）和 `Ui2Form` 仅支持 Windows；
Windows 的 `Ui2Proxy` 仍然基于窗体。在 Linux 和 macOS 上，
`lib-ui2-proxy-unx.fun` 提供同一套宿主 API，不需要窗口或 `libwv2`。
在 Linux 上，`lib-ui2-unx.fun` 还可以把页面嵌入 GTK3/WebKit2GTK 窗口；
macOS 目前回退到默认浏览器。

**目标：** 在 Windows、Linux 和 macOS 上提供同一套 Fun 侧和 JavaScript API，
让 Fun 程序可以在 Fun 支持的所有平台上提供浏览器界面。

1. **Windows 基线（已完成）。** WebView2 传输、WebSocket 传输、FD 序列化，以及
   本仓库中的调度器和桥接实现。
2. **可移植的 WebSocket 传输（Linux/macOS 已完成）。** 把 `Ui2Proxy` 与
   WebView2 窗体解耦，通过共享的 HTTP/WebSocket 核心服务外部浏览器；
   Windows 的窗体代理保留以兼容旧代码。
3. **原生 webview 后端（Linux 已完成，macOS 待做）。** Linux 的 `Ui2Form`
   把第 2 步的 WebSocket 页面装入 GTK3/WebKit2GTK 窗口，消息协议和
   JavaScript 桥接保持不变。macOS 的 WKWebView 宿主尚未实现，目前回退浏览器。
4. **发布工程。** 各平台构建脚本、CI 覆盖、打包示例和兼容性矩阵。

上述步骤中，线协议和 JavaScript API 计划保持稳定。平台相关代码应限制在宿主
层（`libwv2`、未来的 webview 宿主和套接字后端）。

---

## 内容

| 路径 | 用途 |
| ---- | ---- |
| [`fun/lib/lib-ui2.fun`](fun/lib/lib-ui2.fun) | `Ui2Form`：WebView2 宿主窗口、消息分帧、压缩、二进制传输。 |
| [`fun/lib/lib-ui2-proxy.fun`](fun/lib/lib-ui2-proxy.fun) | `Ui2Proxy`：WebSocket 方式，提供页面并通过本地 WebSocket 转发二进制消息。 |
| [`fun/lib/lib-ui2-proxy-unx.fun`](fun/lib/lib-ui2-proxy-unx.fun) | Linux/macOS 的无窗口 `Ui2Proxy`：HTTP 页面加 WebSocket，不需要 WebView2。 |
| [`fun/lib/lib-ui2-unx.fun`](fun/lib/lib-ui2-unx.fun) | Unix 的 `Ui2Form`：可移植代理加可选的 Linux 原生 GTK/WebKit 窗口，或浏览器回退。 |
| [`fun/lib/lib-fd-dispatcher.fun`](fun/lib/lib-fd-dispatcher.fun) | `FdDispatcher`：jCAL 处理函数查找、jRET 应答、fCAL/fRET 回调。 |
| [`fun/lib/lib-fd-dispatcher-async.fun`](fun/lib/lib-fd-dispatcher-async.fun) | `FdAsyncDispatcher`：在 Fun 异步调度器中运行 jCAL 处理函数。 |
| [`fun/lib/lib-fd-dispatcher-proc.fun`](fun/lib/lib-fd-dispatcher-proc.fun) | 基于文件队列的调度器和 worker，用于进程外 UI 后端。 |
| [`js/fd.js`](js/fd.js) | 浏览器端完整的 FD 解析器和序列化器（v1.8 API）。 |
| [`js/fd2.js`](js/fd2.js) | 支持分块输入的流式 FD 解析器和序列化器。 |
| [`js/fun-bridge.js`](js/fun-bridge.js) | WebView2 桥接：共享缓冲区、Base64 通道、压缩、`window.Fun`。 |
| [`js/fun-bridge-ws.js`](js/fun-bridge-ws.js) | WebSocket 桥接，提供相同的 `window.Fun` API。 |
| [`src/prj/lib.wv2/`](src/prj/lib.wv2) | Delphi 2006 工程，基于 WebView4Delphi 构建 `libwv2.dll`。 |
| [`src/prj/lib.webkitgtk/`](src/prj/lib.webkitgtk) | Linux 的小型 GTK3 + WebKit2GTK 窗口宿主（`libui2webkitgtk.so`）。 |

---

## 仓库结构

```text
fun-ui/
├── fun/lib/                 # Fun 侧模块
│   ├── lib-ui2.fun
│   ├── lib-ui2-proxy.fun
│   ├── lib-ui2-proxy-unx.fun
│   ├── lib-ui2-unx.fun
│   ├── lib-fd-dispatcher.fun
│   ├── lib-fd-dispatcher-async.fun
│   └── lib-fd-dispatcher-proc.fun
├── js/                      # 浏览器侧模块
│   ├── fd.js
│   ├── fd2.js
│   ├── fun-bridge.js
│   └── fun-bridge-ws.js
├── src/prj/lib.wv2/         # 原生 WebView2 宿主（Windows、Delphi）
    ├── libwv2.dpr
    ├── wv2.pas
    ├── wv2.dfm
    ├── setenv.bat
    └── make-2006.bat
├── src/prj/lib.webkitgtk/    # 原生 GTK/WebKit 宿主（Linux、C）
│   ├── host.c
│   └── build.sh
└── test/                    # 回环与桥接测试
    ├── lib-ui2-proxy-unx-test.fun
    ├── lib-ui2-webview-lnx-test.fun
    └── fun-bridge-ws.test.js
```

`fun-ui` 不包含 Fun 语言实现。`fun/lib` 中的模块使用相邻
[`fun`](https://github.com/Funlang/fun) 项目自带的标准库（`lib-ui.fun`、
`lib-zlib.fun`、`lib-async.fun`、`lib-ajax.fun`、`lib-winsock.fun`、
`lib-os.fun`）。

### 使用 Fun 模块

1. 把 `fun/lib` 加入 Fun 的模块搜索路径，或把模块复制到
   `<FUN_ROOT>/fun/lib`。
2. 在宿主脚本中加载 `lib-ui2.fun`，从 `Ui2Form` 派生窗体类。覆盖 `onReady`，
   在其中调用 `Navigate`。
3. 显示窗体前，把 `FdDispatcher` 子类（或 `FdAsyncDispatcher`）赋给窗体的
   `dispatcher` 属性，这样 `fd_*` 方法就能处理 jCAL 调用。
4. 把 `libwv2.dll` 放入 DLL 搜索路径；`lib-ui2.fun` 通过全局 `@libwv2dll`
   访问它。

在 Linux 和 macOS 上不需要 `libwv2`，改用可移植代理：

```fun
use 'lib-ui2-proxy.fun';   // 自动解析到 lib-ui2-proxy-unx.fun

class AppDispatcher = FdDispatcher()
  fun fd_ping(args)
    result = new [pong: args[0]];
  end fun;
end class;

var proxy = Ui2Proxy();
proxy.port = 8278;          // 0 表示随机端口
proxy.jsDir = 'js';         // 包含 fd.js 和 fun-bridge-ws.js 的目录
proxy.page = '<h1>Hello from Fun</h1>';
proxy.dispatcher = AppDispatcher();
var port = proxy.Start();   // 非阻塞，返回实际端口
?. proxy.Url();             // http://127.0.0.1:<port>/
proxy.Run();                // 阻塞轮询循环
```

`Ui2Proxy` 会向页面注入 `<script src="/fd.js">` 和
`<script src="/fun-bridge-ws.js">`，除非页面已经包含桥接脚本。设置
`proxy.autoOpen = true` 可自动打开默认浏览器。HTTP 服务默认绑定
`127.0.0.1`；需要供其他机器访问时设置 `proxy.ip = '0.0.0.0'`。

---

## 消息协议

所有消息都是 FD 文档，由 `type` 字段选择通道。

| 消息 | 方向 | 含义 |
| ---- | ---- | ---- |
| `jCAL` | JS 到 Fun | 调用 Fun 处理函数。字段：`id`、`name`、`args`、`timeout`。 |
| `jRET` | Fun 到 JS | `jCAL` 的结果。字段：`id`、`val`、`err`。 |
| `fCAL` | Fun 到 JS | 调用 JavaScript 处理函数。字段：`id`、`name`、`args`、`timeout`。 |
| `fRET` | JS 到 Fun | `fCAL` 的结果。字段：`id`、`val`、`err`。 |

二进制载荷使用带 4 字节小端长度头的帧。长度头的第 31 位表示载荷已压缩。
压缩算法为 raw DEFLATE（Fun 侧使用 `deflate`，浏览器侧使用
`CompressionStream('deflate-raw')`）。页面启用后，JavaScript 侧会压缩发出的帧：

```js
window.__funCompress = true;        // 默认：false
window.__funCompressMinSize = 512;  // 默认：512 字节
```

Fun 侧用自己的 `Ui2Form.setCompress(flag, minSize)` 控制发出的数据是否压缩。

桥接脚本为 FD 文本使用 `gbk` 编码标签（发送时 `TextEncoder('gbk')`，接收时
`FD.parse(..., 'gbk')`），以便旧的 Windows 代码页和现有 Fun 字符串能够往返。
Chromium 支持 `gbk` 解码标签，因此支持范围是 Chromium 内核浏览器。

对于 `fCAL` 的返回值，Fun 侧分配共享缓冲区并把句柄传给 JavaScript。
JavaScript 把 `fRET` 帧写入该缓冲区后只回传句柄，避免第二次大块复制。

---

## JavaScript API

先加载 `fd.js`（或 `fd2.js`），再加载任意一个桥接脚本：

```html
<script src="fd.js"></script>
<script src="fun-bridge.js"></script>
<script>
  Fun('load_profile', { id: 42 }).then(function (profile) {
    console.log(profile);
  });

  Fun({ name: 'ping', args: ['hello'], callback: function (val, err) {
    if (err) console.error(err);
    else console.log(val);
  }});
</script>
```

`window.Fun` 既支持 `Fun(name, ...args)`，也支持传入包含 `name`、`args`、
`callback` 和 `timeout` 的单个选项对象。不传回调时返回 Promise。Fun 侧的
`FdDispatcher` 会把名字解析为 `fd_<name>` 方法；名字中的连字符和空格会替换
为下划线，若找不到再去掉分隔符重试。

`timeout` 的单位是毫秒，`0`（默认）表示不超时。超时后回调收到
`(null, 'timeout after Nms')`，Promise 形式以同一字符串 reject。WebSocket
关闭时所有未完成调用以 `'connection closed'` 失败。Fun 侧的
`callJS(name, args, maxRetSize, callback, timeout)` 接受同样的可选超时；
宿主应在轮询循环中调用 `dispatcher.expire()`（`Ui2Proxy.RunOnce` 已包含），
`dispatcher.failPending(reason)` 可取消全部未完成调用。

`fCAL` 调用对应的 JavaScript 处理函数注册在桥接调度器上：

```js
window.__fdDispatcher.register('update_title', function (args) {
  document.title = args[0];
  return true;
});
```

---

## 构建原生 WebView2 宿主

`libwv2.dll` 是用 Delphi 2006 构建的 32 位 Windows DLL，依赖
[WebView4Delphi](https://github.com/salvadordf/WebView4Delphi)。本仓库不包含
WebView4Delphi 源码。

### 依赖

| 项目 | 说明 |
| ---- | ---- |
| Windows | 需要安装 WebView2 Runtime，建议使用 Evergreen 版本。 |
| Delphi 2006 | `DELPHI2006` 指向其安装根目录。 |
| WebView4Delphi | `WV2_SRC` 指向包含 `uWVLoader.pas`、`uWVBrowser.pas` 等单元的目录。 |
| Fun 仓库 | `FUN_ROOT` 指向相邻的 `fun` 仓库。 |

### 工具链配置

所有与机器相关的路径都在
[`src/prj/lib.wv2/setenv.bat`](src/prj/lib.wv2/setenv.bat) 中。只需修改一次，
或在命令行中预先设置变量。每项赋值都使用 `if not defined` 保护，因此你预先
设置的值优先。

| 变量 | 含义 | 默认值 |
| ---- | ---- | ------ |
| `FUN_ROOT` | `fun` 仓库根目录 | `..\..\..\..\fun` |
| `DELPHI2006` | Delphi 2006 安装根目录 | `D:\Borland\Delphi2006` |
| `WV2_SRC` | WebView4Delphi 源码目录 | `..\..\..\..\WebView4Delphi\source` |

### 构建步骤

```text
cd src\prj\lib.wv2
make-2006.bat
```

脚本会加载 `setenv.bat`，把 `WV2_SRC` 加入单元搜索路径后调用
`dcc32 libwv2.dpr`，并透传额外的编译开关，例如 `make-2006.bat -B`。
生成的 `libwv2.dll` 位于工程目录。把它复制到 Fun 宿主程序旁边，或任何位于
DLL 搜索路径中的目录。

运行时，Fun 侧通过全局 `@libwv2dll` 访问原生模块。把 `libwv2.dll` 放在宿主
程序旁边，或放在 DLL 搜索路径中。导出的入口如下：

| 导出 | 用途 |
| ---- | ---- |
| `Init(callback)` | 保存 Fun 事件回调，创建 WebView2 loader 并启动。 |
| `Show(parentHandle)` | 创建浏览器窗口并返回窗口句柄。 |
| `Navigate(url)` | 加载 URL；字符串以 `<` 开头时按 HTML 加载。 |
| `PostData(ptr, len)` | 向 JavaScript 发送数据块。`len` 为负数时分配 fCAL 响应缓冲区。 |
| `ExecScript(script)` | 在页面中执行 JavaScript。 |
| `Close`、`Free` | 销毁窗口和 loader。 |

事件消息码定义在 `wv2.pas` 中（`MSG_ERROR`、`MSG_CREATED`、
`MSG_TITLE_CHANGED`、`MSG_BINARY`、`MSG_TEXT`、`MSG_FCAL_RESULT`）。

---

## WebSocket 方式

`Ui2Proxy` 提供本地 HTTP 页面，并在 `proxyPort`（默认 `8278`）上接受
WebSocket 连接。JavaScript 加载 `fun-bridge-ws.js`，它使用 `window.__wsUrl`
或 `ws://<location.host>`。帧格式与 WebView2 方式完全一致，因此调度器和页面
代码无需修改。

在 Linux 和 macOS 上，代理运行在与 `lib-winsock-unx.fun` 相同的 poll
循环上，不需要窗口、`libwv2.dll` 或 WebView2 运行时。`Start()` 返回绑定
端口，`RunOnce(timeout)` 供宿主驱动单轮轮询，`Run()` 阻塞到 `Stop()`。
`PostData` 向最近连接的页面推送一帧；fCAL 的应答以普通 `fRET` 消息返回，
`fun-bridge-ws.js` 不需要共享缓冲区即可处理。

Windows 的 `lib-ui2-proxy.fun` 仍然把页面放在 `Ui2Form` 中；平台感知的模块
加载器会在 Linux 和 macOS 上自动选择可移植实现。

### 安全

浏览器发来的每个 WebSocket 帧在进入调度器前都会检查：

- 带 `Origin` 时，它必须等于 `http://` 或 `https://` 加上请求的 `Host`，
  且主机必须是 IP 字面量、`localhost`、配置的 `ip`，或 `allowedHosts` 中的
  条目。这可以阻止跨站 WebSocket 劫持和 DNS 重绑定，否则任意网页都可能
  调用 `127.0.0.1` 上的 `fd_*` 方法。
- 没有 `Origin` 的请求（非浏览器客户端）允许通过，但可选 `token` 仍然生效。
- `token` 必须是 URL 安全字符（`A-Z a-z 0-9 _ -`）。服务端会在页面中注入
  `window.__wsUrl = 'ws://<host>/?token=...'`，升级请求必须携带它。
- `allowedOrigins` 用于反向代理或自定义主机，填入精确的 origin。
- `checkOrigin = false` 会关闭检查，仅在可信网络中使用。

可移植宿主还只接受 `/` 和 `/ws` 路径的升级请求，用 `maxFrameBytes`
（默认 16 MiB，解压后同样检查）限制消息大小，并在路由前丢弃畸形或超限帧。
只有解析成功的帧才会更新推送目标，坏帧无法抢走 fCAL/推送连接。

除非确实需要远程访问，否则绑定 `127.0.0.1`；非回环绑定且没有 token 时会
打印警告。每个进程只运行一个 `Ui2Proxy`：Unix socket 层的 poll 状态是进程级
的，停止或驱动第二个代理会干扰第一个。

---

## 原生 WebKitGTK 宿主（Linux）

`lib-ui2-unx.fun` 在 Unix 上提供 `Ui2Form`。Linux 下如果存在
`libui2webkitgtk.so`，它会创建 GTK3 窗口和 WebKit2GTK 视图，并加载可移植
代理提供的页面。页面仍通过 WebSocket 与 Fun 通信，因此协议、调度器和
JavaScript 桥接都不变。

构建宿主（需要开发包，见兼容性）：

```bash
src/prj/lib.webkitgtk/build.sh
```

在 Fun 中使用：

```fun
use 'lib-ui2.fun';          // 在 Unix 上解析到 lib-ui2-unx.fun

var form = Ui2Form();
form.port = 8278;
form.jsDir = 'js';
form.hostLib = './src/prj/lib.webkitgtk/libui2webkitgtk.so';
form.requireWebview = true; // 缺少宿主时直接报错，不回退浏览器
form.dispatcher = MyDispatcher();
form.Show();                // Start + Run
```

不设置 `requireWebview` 时，缺少宿主库会回退到 `OpenBrowser()`。把
`form.traceFile` 设为文件路径可记录原生启动和循环诊断。宿主在进入
GTK/WebKit 前会屏蔽 FPC 默认未屏蔽的浮点异常，并在关闭时排空主循环，
等待 WebKit 进程退出。

---

## 兼容性

- Fun 9.x 运行时，并包含上面列出的标准库模块。
- `libwv2.dll` 和 `Ui2Form` 需要 Windows 与 WebView2。
- Linux 和 macOS 可使用可移植 WebSocket 宿主（`lib-ui2-proxy-unx.fun`），
  使用平台自带的 `lib-winsock` 后端，不需要窗口或 WebView2 运行时。
- Linux 原生窗口需要 GTK3 和 WebKit2GTK 4.0/4.1 开发包及对应运行时库；
  无显示器环境可用 Xvfb 和 D-Bus 会话。
- `fun-bridge.js` 和 `fun-bridge-ws.js` 需要 Chromium 内核浏览器，因为桥接
  使用了 `CompressionStream` 和 `gbk` 文本编码标签。

## 测试

```bash
# HTTP + WebSocket + jCAL/jRET + fCAL/fRET + 压缩（Linux/macOS）
funcmd test/lib-ui2-proxy-unx-test.fun

# 浏览器桥接单元测试（Node 18+，需要 CompressionStream）
node --experimental-websocket test/fun-bridge-ws.test.js

# Linux 原生窗口冒烟测试（需要 GTK/WebKitGTK、Xvfb、D-Bus）
src/prj/lib.webkitgtk/build.sh
xvfb-run -a -s "-screen 0 1280x1024x24" \
  dbus-run-session -- funcmd test/lib-ui2-webview-lnx-test.fun
```

GitHub Actions 会在 ubuntu-24.04 上同时运行回环/桥接测试和无头 WebKitGTK
测试，见 `.github/workflows/ci.yml`。

---

## 许可证

MIT，见 [LICENSE](LICENSE)。发布历史见 [CHANGELOG.md](CHANGELOG.md)。

版权所有 (c) 2026 张卫东 <zwd@funlang.org>。
