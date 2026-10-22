# fun-ui

[Fun](https://funlang.org) 编程语言的浏览器界面组件。

**简体中文**（本文件） - [English](README.md)

- 版本：**1.0**
- 网站：<https://funlang.org>
- 许可证：MIT（见 [LICENSE](LICENSE)）

`fun-ui` 负责把 Fun 脚本和 Web 界面连接起来。Fun 进程持有窗口和业务逻辑，
界面是运行在 Chromium 内核浏览器中的普通 HTML、CSS 和 JavaScript。调用可以
双向传递：

- **jCAL / jRET**：JavaScript 调用 Fun 方法并取得返回值。
- **fCAL / fRET**：Fun 调用 JavaScript 处理函数并取得返回值。

项目提供两种传输方式。WebView2 方式通过一个很小的 Delphi DLL 把 Chromium
直接嵌入 Fun 窗口；WebSocket 方式用套接字代替共享内存来传递同样的消息。
两种方式共用同一套消息格式和 JavaScript API。当前 WebSocket 实现仍然把页面
放在 Windows 的 WebView2 窗口中，下面的路线图会把它改为提供给外部浏览器。

## 项目状态与路线图

**状态：** 首次开源发布面向 Windows。WebView2 宿主（`libwv2.dll`）和
`Ui2Form` 目前仅支持 Windows。`Ui2Proxy` 基于 `Ui2Form`，并加载 Windows 的
`lib-winsock` 后端。

**目标：** 在 Windows、Linux 和 macOS 上提供同一套 Fun 侧和 JavaScript API，
让 Fun 程序可以在 Fun 支持的所有平台上提供浏览器界面。

1. **Windows 基线（当前）。** WebView2 传输、WebSocket 传输、FD 序列化，以及
   本仓库中的调度器和桥接实现。
2. **可移植的 WebSocket 传输。** 把 `Ui2Proxy` 与 WebView2 窗体解耦，使它能
   服务外部浏览器；然后在 Linux 上选择 `lib-winsock-lnx`，在 macOS 上选择
   `lib-winsock-unx`。HTTP/WebSocket 核心已经在 `lib-winsock-base.fun` 中共享，
   这是把浏览器界面带出 Windows 的最短路径。
3. **原生 webview 后端。** 在 `Ui2Form` API 之后增加 Linux 和 macOS 宿主，
   使用 WebKitGTK 和 WKWebView（或其他可嵌入引擎），消息协议和 JavaScript
   桥接保持不变。
4. **发布工程。** 各平台构建脚本、CI 覆盖、打包示例和兼容性矩阵。

上述步骤中，线协议和 JavaScript API 计划保持稳定。平台相关代码应限制在宿主
层（`libwv2`、未来的 webview 宿主和套接字后端）。

---

## 内容

| 路径 | 用途 |
| ---- | ---- |
| [`fun/lib/lib-ui2.fun`](fun/lib/lib-ui2.fun) | `Ui2Form`：WebView2 宿主窗口、消息分帧、压缩、二进制传输。 |
| [`fun/lib/lib-ui2-proxy.fun`](fun/lib/lib-ui2-proxy.fun) | `Ui2Proxy`：WebSocket 方式，提供页面并通过本地 WebSocket 转发二进制消息。 |
| [`fun/lib/lib-fd-dispatcher.fun`](fun/lib/lib-fd-dispatcher.fun) | `FdDispatcher`：jCAL 处理函数查找、jRET 应答、fCAL/fRET 回调。 |
| [`fun/lib/lib-fd-dispatcher-async.fun`](fun/lib/lib-fd-dispatcher-async.fun) | `FdAsyncDispatcher`：在 Fun 异步调度器中运行 jCAL 处理函数。 |
| [`fun/lib/lib-fd-dispatcher-proc.fun`](fun/lib/lib-fd-dispatcher-proc.fun) | 基于文件队列的调度器和 worker，用于进程外 UI 后端。 |
| [`js/fd.js`](js/fd.js) | 浏览器端完整的 FD 解析器和序列化器（v1.8 API）。 |
| [`js/fd2.js`](js/fd2.js) | 支持分块输入的流式 FD 解析器和序列化器。 |
| [`js/fun-bridge.js`](js/fun-bridge.js) | WebView2 桥接：共享缓冲区、Base64 通道、压缩、`window.Fun`。 |
| [`js/fun-bridge-ws.js`](js/fun-bridge-ws.js) | WebSocket 桥接，提供相同的 `window.Fun` API。 |
| [`src/prj/lib.wv2/`](src/prj/lib.wv2) | Delphi 2006 工程，基于 WebView4Delphi 构建 `libwv2.dll`。 |

---

## 仓库结构

```text
fun-ui/
├── fun/lib/                 # Fun 侧模块
│   ├── lib-ui2.fun
│   ├── lib-ui2-proxy.fun
│   ├── lib-fd-dispatcher.fun
│   ├── lib-fd-dispatcher-async.fun
│   └── lib-fd-dispatcher-proc.fun
├── js/                      # 浏览器侧模块
│   ├── fd.js
│   ├── fd2.js
│   ├── fun-bridge.js
│   └── fun-bridge-ws.js
└── src/prj/lib.wv2/         # 原生 WebView2 宿主（Windows、Delphi）
    ├── libwv2.dpr
    ├── wv2.pas
    ├── wv2.dfm
    ├── setenv.bat
    └── make-2006.bat
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

当前实现仍然在 WebView2 窗口中显示提供的页面。把代理与 `Ui2Form` 解耦
（路线图第 2 步）后，同一个页面就可以运行在外部浏览器中，也适用于 Fun 进程
位于远端或针对服务开发页面的场景。

---

## 兼容性

- Fun 9.x 运行时，并包含上面列出的标准库模块。
- `libwv2.dll` 和 `Ui2Form` 需要 Windows 与 WebView2。
- 首次发布仅支持 Windows。包括计划中的、无需 WebView2 的纯 WebSocket 方式在内
  的跨平台支持，见[项目状态与路线图](#项目状态与路线图)。
- `fun-bridge.js` 和 `fun-bridge-ws.js` 需要 Chromium 内核浏览器，因为桥接
  使用了 `CompressionStream` 和 `gbk` 文本编码标签。

---

## 许可证

MIT，见 [LICENSE](LICENSE)。

版权所有 (c) 2026 张卫东 <zwd@funlang.org>。
