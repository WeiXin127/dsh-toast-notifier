# dsh-toast-notifier

权限请求与任务完成的**系统级置顶浮窗**提醒插件（DeepSeek Harness / DSH）。

一个独立于 DSH 主窗口的原生浮动通知窗，类似 QQ 消息弹窗：始终置顶、跨屏显示、可拖动、位置记忆。它用 Windows PowerShell + WPF 创建真正的原生窗口，因此能盖在所有应用窗口之上，不受 DSH 对话窗口边界裁剪。

## 功能

四类事件触发提醒：

| 事件 | 触发时机 | 弹窗标题 |
|---|---|---|
| `approval/request` | 工具请求越权执行（需要授权） | 「权限请求」+ 工具名 |
| `user-questions/request` | 模型向你提问（`ask_user_question`） | 「需要你回答」+ 问题内容 |
| `api-session/status`（running→idle） | 会话任务结束 | 「任务完成」 |
| `api-session/error` | 会话任务出错 | 「任务出错」+ 错误信息 |

特性：

- **系统级置顶**：WPF `Topmost` 窗口，盖在所有应用之上。
- **脱离 DSH 窗口**：独立进程的原生窗口，不受对话窗口裁剪，支持跨屏。
- **可拖动**：按住顶部「⠿ 拖动」把手拖动。
- **位置记忆**：拖动后保存到 `~/.dsh/dsh-toast-notifier/position.json`，之后沿用；窗口变小时钳制回可视区。
- **点 × 关闭**。
- **无控制台闪窗**：宿主半用 `windowsHide: true` 隐藏 powershell 控制台窗口。

## 效果预览

> 截图还没放进仓库。建议实际截一张弹窗图存为 `docs/screenshot.png`，然后取消下面这行 Markdown 的注释（去掉两端的反引号包裹）。
>
> `![弹窗效果](docs/screenshot.png)`

## 环境要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows 10 / 11（依赖 `powershell.exe` + WPF） |
| 运行环境 | DeepSeek Harness（DSH） |
| Cordis | `^4.0.1`（由 DSH 提供，无需单独安装） |

## 架构

```
┌─────────────────────────────────────────────────────────┐
│ DSH 宿主进程（Node，Electron-as-Node）                    │
│   lib/index.js                                           │
│     ctx.on(...) 监听 4 个事件                             │
│        ↓ 事件发生                                        │
│     showToast()：写 content JSON + spawn powershell       │
└───────────────────────────┬─────────────────────────────┘
                            ↓ spawn powershell.exe -File toast.ps1
┌─────────────────────────────────────────────────────────┐
│ 独立 powershell 进程（每个提醒一个）                       │
│   toast.ps1                                              │
│     读 content JSON → 建 WPF 窗口 → ShowDialog()         │
│     拖动 → DragMove()   关闭 → 写 position.json          │
└─────────────────────────────────────────────────────────┘
```

关键点：**不需要浏览器半（client）**。宿主半直接监听宿主事件，比原来「宿主转发到浏览器、浏览器再弹 DOM」的方案更简单，也彻底解决了「弹窗被对话窗口裁剪」的问题。

## 文件结构

```
dsh-toast-notifier/
├── package.json        # 插件清单：dsh.bundle 声明 + exports
├── cordis.patch.yml    # bundle patch：向 profile 插入一条条目
├── lib/index.js        # 宿主半：监听事件 + spawn 浮窗进程
├── toast.ps1           # PowerShell(WPF) 浮窗脚本
├── README.md           # 本文档
├── LICENSE             # MIT 许可证
├── .gitignore          # 忽略 node_modules / 日志 / 运行时数据
└── .gitattributes      # 行尾规范（.ps1 保持原样）
```

## 各文件详解

### `package.json`

```json
{
  "name": "dsh-toast-notifier",
  "type": "module",
  "main": "lib/index.js",
  "dsh": {
    "bundle": { "patch": "./cordis.patch.yml" }
  },
  "exports": {
    ".": { "default": "./lib/index.js" },
    "./cordis.patch.yml": "./cordis.patch.yml",
    "./package.json": "./package.json"
  },
  "peerDependencies": { "@deepseek-ai/cordis": "^4.0.1" }
}
```

- `main` 指向宿主半 `lib/index.js`（loader 会导入它）。
- `dsh.bundle.patch` 让 loader 应用 `cordis.patch.yml`，把本插件插入 profile。
- `peerDependencies` 声明依赖 Cordis（运行时由 DSH 提供，不安装到本地）。
- **没有 `dsh.client`**——因为本插件不需要浏览器半。

### `cordis.patch.yml`

```yaml
- insert:
    - id: dsh-toast-notifier
      name: 'dsh-toast-notifier'
```

向 profile 的条目树插入一条 `id` 为 `dsh-toast-notifier` 的条目，`name` 指定要导入的模块（本包 `main`）。放在 `dsh.profile.bundles` 的 `@deepseek-ai/dsh-web-app` **之前**，保证权限/提问的监听器先于官方审批流注册（见「实现要点」第 5 条）。

### `lib/index.js`（宿主半）

核心逻辑：

```js
const SCRIPT = join(here, '..', 'toast.ps1')                 // toast.ps1 路径
const DATA_DIR = join(homedir(), '.dsh', 'dsh-toast-notifier') // 数据目录
```

`showToast(kind, title, body)`：
1. 把内容写成 `content-<时间戳>-<序号>.json`（UTF-8）。
2. `spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT, contentFile, positionFile], { stdio: 'inherit', windowsHide: true })`。
3. `child.unref()` 让宿主进程不等待该子进程（fire-and-forget）。

`apply(ctx)` 注册 4 个监听器：

```js
ctx.on('api-session/status', (sessionId, running) => { if (!running) showToast('done', ...) })   // emit
ctx.on('api-session/error',  (sessionId, message) => showToast('error', ...))                    // emit
ctx.on('approval/request',      (req, next) => { showToast('warn', ...); return next() })        // waterfall，放行
ctx.on('user-questions/request', (req, next) => { showToast('question', ...); return next() })   // waterfall，放行
```

- `api-session/status`、`api-session/error` 是 **emit** 事件：所有监听器都会收到，无需争抢顺序。
- `approval/request`、`user-questions/request` 是 **waterfall** 事件：多个监听器串成链，谁先返回结果谁「抢到」。本插件只是「观察 + 放行」——弹窗后 `return next()` 把请求交给官方审批/问答 UI，不抢占流程。

### `toast.ps1`（WPF 浮窗脚本）

分四段：

1. **读入**：从参数读 `content JSON`（kind/title/body）和 `position.json`（上次位置）。
2. **建窗口**：`Window` 设置 `WindowStyle=None`（无边框）、`AllowsTransparency=True`（透明）、`Topmost=True`（置顶）、`ShowInTaskbar=False`（不在任务栏）、`SizeToContent=Height`（高度自适应）、`Width=380`。
3. **画卡片**：一个圆角 `Border` 里放 `Grid`（左边 4px 彩色条 + 内容列），内容列含顶部行（拖动把手 + 关闭按钮）、标题、正文。颜色按 `kind` 取左条色：done 绿 / error 红 / warn 橙 / question 蓝。
4. **交互与收尾**：
   - 拖动：`$dragHandle.Add_MouseLeftButtonDown({ $window.DragMove() })` —— 只让「⠿ 拖动」把手可拖。
   - 关闭：`$closeBox.Add_MouseLeftButtonUp({ $window.Close() })` —— 鼠标松开时关闭。
   - 定位：`Loaded` 事件里，无历史位置则放右下角，否则把历史位置钳制回工作区。
   - 关闭时：`Closed` 事件里写回 `position.json` 并删除本次 content JSON。
   - 显示：`$window.ShowDialog()`。

## 数据文件

目录 `~/.dsh/dsh-toast-notifier/`：

| 文件 | 说明 |
|---|---|
| `content-<ts>-<seq>.json` | 单次提醒内容（`{kind,title,body}`），窗口关闭后自动删除 |
| `position.json` | 位置记忆（`{left,top}`），拖动后写入、下次沿用 |

## 安装

### 方式一：从 GitHub 仓库引用（推荐分享给别人）

把仓库克隆到本地，然后让 profile 依赖指向 **克隆下来的目录**（不要指向 `node_modules`，插件需要能读到同目录的 `toast.ps1`）：

```powershell
mkdir C:\dsh-plugins -Force
git clone https://github.com/<你的用户名>/dsh-toast-notifier.git C:\dsh-plugins\dsh-toast-notifier
```

然后编辑 profile 的 `package.json`（`%USERPROFILE%\.dsh\profiles\desktop\package.json`）：

```json
{
  "dependencies": {
    "dsh-toast-notifier": "file:C:/dsh-plugins/dsh-toast-notifier"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "dsh-toast-notifier",
        "@deepseek-ai/dsh-web-app",
        "dshmarket"
      ]
    }
  }
}
```

### 方式二：从本地目录安装

```json
"dependencies": {
  "dsh-toast-notifier": "file:D:/Harness-one/dsh-toast-notifier"
}
```

### 之后（两种方式相同）

1. `bundles` 里 `"dsh-toast-notifier"` 必须放在 `"@deepseek-ai/dsh-web-app"` **之前**（见「实现要点」第 5 条）。
2. 在 profile 目录运行 `pnpm install`（若报「minimumReleaseAge」策略拦截，可加 `--config.minimumReleaseAge=0` 放行）。
3. 重启 Harness。

插件通过自身的 `cordis.patch.yml` 自动插入条目，无需手动编辑 profile 的 `cordis.patch.yml`。

### 卸载

从 profile 的 `bundles` 和 `dependencies` 中删掉 `dsh-toast-notifier`，`pnpm install`，重启 Harness；再删掉 `~/.dsh/dsh-toast-notifier/` 即可（里面只有位置记忆）。

## 实现要点 / 踩坑记录

这些是调试过程中确认的关键点，改动时务必保留：

1. **spawn 必须用 `{ stdio: 'inherit', windowsHide: true }`**：
   - `stdio: 'ignore'` 会让 powershell 启动失败（退出码 1），窗口不显示。
   - `stdio: 'pipe'` 在受限沙箱里会 EPERM（插件运行时不受影响，但不可靠）。
   - `windowsHide: true` 只隐藏 powershell 的**控制台**窗口，**不会**隐藏 WPF 窗口（已实测）；去掉它会出现黑色命令窗口。
2. **关闭按钮用 `Border` + `MouseLeftButtonUp`，而不是 `Button` + `Click`**：`Button` 的 `Click` 与 `PreviewMouseLeftButtonDown` 的 `$e.Handled = $true` 会互相干扰，导致「关不掉」或「窗口不显示」的诡异问题。
3. **用 `ShowDialog()` 而非 `Application.Run()`**：前者在本环境实测能正常阻塞显示，后者会立即返回。
4. **脚本里不用中文/特殊字符字面量**，改用 `[char]0xXXXX` 码点（`⠿`=0x283F、`拖动`=0x62D6/0x52A8、`×`=0x00D7），避免 PowerShell 5.1 的编码（无 BOM 被当 ANSI）导致乱码。
5. **bundle 顺序**：必须放在 `dsh-web-app` 之前，否则 waterfall 监听器会排在官方审批流之后，收不到 `approval/request` / `user-questions/request`。
6. **仅 Windows**：依赖 `powershell.exe`（Windows PowerShell 5.1）+ WPF（.NET Framework），不跨平台。

## 局限

- 仅支持 Windows（依赖 WPF）。
- 每个提醒是一个独立 powershell 进程，弹窗约 0.5–1.5 秒启动（可接受）。
- 样式用 WPF 近似还原（圆角卡片 + 彩色左条），与网页 CSS 版本非逐像素一致。

## 许可证

[MIT](LICENSE) © 2026 惟昕
