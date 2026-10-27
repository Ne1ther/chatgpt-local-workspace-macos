# ChatGPT Codex Workspace for macOS

[项目目录与构建入口](docs/PROJECT-LAYOUT.md) · 工作台按工作目录归组，对话单独列出。

这是 [CSL19980820/chatgpt-local-workspace](https://github.com/CSL19980820/chatgpt-local-workspace) 的独立 macOS 移植，保留原 macOS 移植并选择性纳入上游 **2.4.1 / f2ab383**。保留原作者与贡献者的 MIT 许可和署名；不是 OpenAI 官方应用，也不代表上游作者发布。

**当前源码为 macOS 1.6.1 / 核心 2.4.1，公开 23 个工具并兼容 5 个旧名称。** 当前已发布安装包仍为 1.4.1 / 核心 2.3.0。使用 1.6.1 请按下方步骤从源码构建。

## 下载安装（无需编译）

- 当前已在 Apple Silicon Mac 上构建、运行和验证。最低部署目标为 macOS 14；较旧系统和 Intel Mac 未做实机验证。
- 打开 **[macOS 1.4.1 下载](https://github.com/Ne1ther/chatgpt-local-workspace-macos/releases/tag/macos-v1.4.1)**，在 Assets 中下载 `ChatGPT-Codex-Workspace-1.4.1-arm64.dmg`。`arm64` 对应 M 系列 Apple Silicon Mac；本次不提供 Intel 包。`Source code` 是源码，不是安装包。
- 打开 DMG，将 **ChatGPT Codex Workspace.app** 拖入 **Applications（应用程序）**，再从应用程序或 Spotlight 启动。若选择 ZIP，解压后将 `.app` 拖入应用程序即可。
- 应用内含原生界面、工作台、本地工具和官方 Tunnel Client。**使用时不需要安装 Node、Python 或 .NET。** 执行 Git 工具需要系统已有 Git；执行其他开发命令仍需要用户安装相应软件。
- 后续更新仍从 Releases 下载新版，先从应用菜单明确退出旧版，再用新版替换应用程序中的 `.app`；关闭窗口不等于退出。已有 Tunnel ID、钥匙串中的运行密钥和显示偏好独立于 `.app`，更新时保留，不需要重新编译。
- 由于当前采用 ad-hoc 签名，更新后 macOS 可能重新请求钥匙串访问授权。确认请求来自本应用的 `workspace-server` 后按系统提示允许；不要删除原有状态加密项来跳过授权，否则旧操作记录将无法解密。

### 首次打开与 macOS 安全提示

当前社区安装包为 **ad-hoc 签名，尚未进行 Developer ID 签名和 Apple 公证**，不能将它当作已公证应用。macOS 可能在首次打开时提示“无法验证开发者”或“Apple 无法检查”。

确认安装包来自本仓库 Releases 后，先尝试打开应用，再进入 **系统设置 → 隐私与安全性 → 仍要打开**，并确认打开。具体步骤见 [Apple 官方说明](https://support.apple.com/en-us/102445)。不需要关闭系统的 Gatekeeper。

Releases 附有 `SHA256SUMS.txt`。需要核对下载完整性时，将 DMG/ZIP 和校验文件放在同一目录，在该目录运行 `shasum -a 256 -c SHA256SUMS.txt`；只下载了一种格式时，另一种会显示文件不存在，核对已下载项为 `OK` 即可。文件校验不替代 Apple 公证。

## 连接 ChatGPT

需要自行创建网页插件时，按 [网页插件创建步骤](docs/CREATE-CHATGPT-PLUGIN.md) 填写现有 Tunnel；这里沿用原来的网页调用方式。

1. 按 [OpenAI Secure MCP Tunnel 官方指南](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels) 获取 Tunnel ID 和运行 API Key，并准备 ChatGPT 开发者模式连接。Tunnel 权限与 ChatGPT 开发者模式权限分别管理。
2. 在本应用打开 **连接与显示（⌘,）**，填写两个值，选择“保存并连接”。密钥保存在本机钥匙串，Tunnel ID 保存在应用偏好设置。请在应用内填写密钥，不要贴到聊天或源码里。
3. 等 Mac 应用显示“隧道已就绪”后，打开 ChatGPT 的 Plugins 页面，点击加号 → **Add custom MCP server**。填写名称（例如 Local Workspace Mac）和简介，在 Connection 中选择 **Tunnel**，选本应用使用的同一个 Tunnel ID；按页面要求核对认证及连接信息，选择 **Create as a plugin**，检查发现的工具列表并安装该插件。
4. 新开一个 ChatGPT 对话，在工具菜单启用刚创建的插件，然后输入“调用 `get_workspace_status` 确认连接”。本地 1.6.1 版本的响应包含 `version: 2.4.1`、`tool_count: 23`（已发布 1.4.1 为核心 2.3.0、28 个工具）、`default_shell: zsh` 和实际 Mac 程序路径。
5. 之后可以直接说“在 `<项目绝对路径>` 里先读取 AGENTS.md、列出目录，不修改文件”，再按需交代具体编辑任务。桌面应用的“实时工作台”显示每次调用、命令输出和修改对比；结束时点“停止”或退出应用。

隧道就绪不代表 ChatGPT 已调用成功。初次调用前，工作台可能显示“等待首次调用”；“诊断连接”会区分隧道状态、工具发现与实际调用。应用必须保持运行，ChatGPT 才能通过该 Tunnel 使用这台 Mac 的工具。

### 以后怎样更新网页插件

| 想更新的内容 | 更新位置 |
| --- | --- |
| 可复用的操作流程、额外指令或参考文件 | ChatGPT Plugins → 选择已有插件 → **Edit Plugin**，在打开的编辑对话中描述改动，再按提示检查并完成更新。需要当前账号有编辑权限。 |
| 新增工具、文件处理或命令执行逻辑 | 修改本项目并运行新版 Mac 应用，连接原 Tunnel；到网页的该 MCP 连接详情点 **Refresh**，重新获取工具定义，再用新对话测试。 |
| 仅 Mac 界面或应用图标 | 运行新版 Mac 应用，网页连接继续复用；本机图标不会自动改变网页插件资料。 |

当前项目的工具由本机 MCP 服务提供。网页里增加一段使用指令，可以规定如何调用已有工具；增加真正的新工具仍需要实现本机功能。网页插件的版本与本机应用、核心版本分别管理。创建和工具刷新步骤见 [OpenAI 官方连接文档](https://developers.openai.com/plugins/deploy/connect-chatgpt)，插件编辑步骤见 [官方使用指南](https://learn.chatgpt.com/docs/build-plugins#edit-an-existing-plugin)。

没有连接信息时，可以点 **运行本地检查**。它会在临时目录中完成 MCP 握手、工具发现、中文文件读写和 zsh 命令；工作台明确标记为本地自检，不冒充 ChatGPT 对话。停止或退出时清理自检临时目录。

当前开发工作副本的本地检查使用只存于进程内存的临时加密密钥，不访问正式钥匙串。正式连接仍使用钥匙串保护持久状态，每个后端进程只读取一次状态密钥；拒绝访问后，本进程不反复请求，重新连接才重试。应用启动时的凭据读取不弹授权框，需要交互授权时延后到用户主动保存或连接。

### 后台运行与显示位置

关闭主窗口的红色按钮**不会退出应用或断开连接**，已启动的 Tunnel 和本地任务继续运行。默认同时显示菜单栏图标和 Dock 图标；在“连接与显示 → 显示与后台”可独立控制，两项可以同时开启或同时关闭。关闭“在 Dock 显示”后，打开或关闭主窗口和设置窗口均保持隐藏，不再留下运行中的 Dock 图标。两项都关闭时，用 Spotlight 搜索 ChatGPT 或 Codex，或从 Finder 打开应用，即可恢复同一个进程中的主窗口。点击菜单栏图标可打开主窗口、查看连接状态、停止连接或明确退出；Dock 图标也能重新打开主窗口。只有选择“退出 ChatGPT Codex Workspace”或按 `⌘Q` 才会结束应用和它拥有的后台进程。“停止连接”只断开本次服务，应用仍留在后台。

### macOS 1.6.1 源码 / 上游核心 2.4.1

- “本地能力”检查实际后端对所选目录的读取，以及按需创建、写入、删除临时文件；准确报告权限拒绝与路径缺失，提供系统权限入口。
- 连接诊断改为逐项状态与版本；概览自动归纳需要处理的问题，侧栏选中项保持文字可读。
- 长命令可显式设置最长 24 小时，默认 5 分钟；返回截止时间，通过原会话等待，后端需持续运行。
- 凭据内容延迟到主动连接时读取，减少启动阻塞；建议复用现有状态，不增加后台轮询。实现、验证和边界见 [1.6 记录](docs/LOCAL-CAPABILITIES-1.6.md)。

### macOS 1.5 界面与核心移植

- 固定主导航，工作区列表独立滚动；概览聚焦连接、实际执行流程和最近操作，适配系统浅深色。
- 暖白应用图标与蓝色终端下划线；顶部菜单栏仅在真实工作期间扫光，使用 Core Animation 图层，不逐帧生成图像。减少动态效果、空闲或菜单栏不可见时停止。
- 工作台纳入上游的就地详情、可收起检查器、搜索筛选与回合分组。只打包选定的 Phosphor Duotone 矢量图标及 MIT 许可，无图标 CDN 或额外动画运行时。
- 公开 23 个工具，兼容原 5 个工具名。命令输出默认只返回 output；read_command 可等待新输出并使用 offset 游标。完整副本仅在 include_full_output=true 时返回。
- Codex threadId 与回合元数据、写入行数统计、组件运行/磁盘版本诊断；官方 Tunnel Client 升至 0.0.16，校验发布资产 SHA-256。
- 合并重复 Tunnel INFO 事件，保留告警、错误和其他有用信息。继续加密保存对话、计划、近期活动与独立验证证据；不采用上游启动时清空历史的行为。
- Preview 使用独立应用标识与配置空间；当前 GitHub 更新仅包含源码，Release 安装包仍为 1.4.1。更多范围见 [移植记录](docs/MACOS-2.4.1-PORT.md)。

### macOS 1.4 / 上游核心 2.3.0

- 命令 `request_id` 重试去重、长输出分页；文件哈希检查、修改预演、编辑诊断。
- `workspace_history` 查看直接文件操作历史；`restore_change` 默认预览，支持带冲突检查的撤销与重做。最多 100 次历史、约 48 MiB 原始前后字节，单文件 16 MiB。Shell、Git 远端、附件导入和目录创建等副作用不在恢复范围内。
- 状态保存在 `~/Library/Application Support/LocalWorkspacePlugin/state-v1`，用专用 macOS 钥匙串密钥和 AES-256-GCM 加密，与 Tunnel API Key 分离；状态文件权限为 0600。损坏状态或密钥缺失不会被静默覆盖。`WORKSPACE_STATE_DIR` 可指定独立实例目录，同一目录只允许一个后端写入。
- Git 私有审阅基准不改正常暂存区、HEAD 或远端；计划可引用成功操作作为证据，失败恢复需明确说明。
- 工作台切换原生页面时复用同一 WebView，保留暂停、选择与折叠状态；停止连接后清理该临时浏览会话。
- 补全官方 Tunnel 状态页、未连接时的官方 doctor 检查、操作记录复制/清空与快捷键。Shell 返回真实可执行路径，编辑/恢复保留 Unix 执行权限。

### macOS 1.3 界面更新

- 原创“叠层工作区 + 本地终端”应用图标，采用暖白、石墨和金属灰；菜单栏使用同一图形的单色模板，自动适配系统的深浅色外观。
- 内部操作图标使用 SF Symbols；概览、设置、操作记录和日志统一边距、控件列及图标尺寸。
- 应用图标的矢量源在 `scripts/generate_icons.swift`；构建时按需生成 16–1024 像素图标及菜单栏 1×/2× 资源，不依赖第三方图标网站。

## 功能对应

| 原版能力 | macOS 版 |
| --- | --- |
| 23 个公开工具及 5 个兼容名称 | 纳入上游 2.4.1；文件读写、搜索、图片、附件、命令、Git、计划、完成检查、文件历史与撤销/重做 |
| 双时代协议 | 保留 legacy initialize 和上游 modern discovery、确认重试、任务句柄 |
| 实时工作台 | WKWebView 内嵌原版 React 工作台；时间线、计划、diff、图片、搜索、筛选、暂停观察、对话归组 |
| 操作记录与原始日志 | 原生表格、对话筛选、搜索、复制、清空与跟随最新 |
| 连接配置与诊断 | SwiftUI 设置窗口、macOS 钥匙串、官方 Tunnel Client 0.0.16、本地健康检查 |
| 文件位置跳转 | 目录在 Finder 打开，文件在 Finder 选中；不执行文件 |
| Shell | 默认 `/bin/zsh`，也支持 Bash、sh、已安装的 pwsh；不自动翻译 Windows 命令，不支持 PTY |
| 停止、超时、退出 | 独立 POSIX 进程组清理命令及子进程，不停止其他程序 |
| 单文件 EXE | 自包含 `.app`，另提供 DMG 和 ZIP |

### 与原版相同的边界

- 工作台只监听 `127.0.0.1`；工具通过 stdio 交给 Tunnel，不暴露公网本地服务。
- 已连接的工具可以访问**当前 macOS 用户权限内的本地文件和命令**。此版没有额外增加目录白名单沙箱；不要把工作区分组理解为授权隔离。
- 对话归属、计划、最近 100 条后端活动、请求去重账本和文件历史会加密保存；原生操作列表在当前应用进程内保留最多 500 条连接/工具记录。命令进程与图片预览不跨重启恢复，未确认结束的命令会提示 `PROCESS_RESTARTED`。后台模型思考不可见，也不能强制 ChatGPT 自动继续。
- 默认 shell 不加载交互配置。使用 conda / nvm 等环境时，请在命令中显式初始化，或使用绝对可执行路径。
- ChatGPT 是否向工具提供附件对象和会话元数据，仍取决于宿主。附件工具本身已通过真实 HTTPS 下载测试，但实际账号的附件选择没有验证。

## 已完成的验证

以下为开发阶段的验证记录；1.6.1 的新增功能与验证边界见 [1.6 记录](docs/LOCAL-CAPABILITIES-1.6.md)。

- 原生 `.app` 编译、启动及实际 SwiftUI / WKWebView 窗口检查。
- 在隔离临时目录中逐个调用 23 个公开工具及 5 个兼容旧工具，并校验返回结构；实际中文、空格、引号路径读写，BOM 保留，多文件增改移删及路径越界拒绝。
- zsh / Bash / sh，持续命令输入输出，停止进程树、无人轮询时超时，实际 Git 差异，真实 HTTPS 附件下载，图片原始字节保留。
- 新旧协议握手、修改确认、长任务句柄、对话隔离、工作台同源限制。
- 原版工作台浏览器回归：时间线、分类详情、diff、计划、筛选、浅深色，以及 1920 / 1366 / 640 宽度无横向溢出。原生窗口按桌面使用设计，最小宽度 1000。
- 原生本地自检 → 工作台命令输出 → Finder 打开 → 操作记录 / 日志 → 停止；停止后对应本地端口关闭，服务进程退出。
- Dock 显示开关、设置和主窗口关闭/重开、双隐藏模式的 LaunchServices 恢复；隐藏时实际进程策略为 accessory，应用与 Tunnel 进程保持不变。

2026-10-17 已通过真实 ChatGPT 网页 → 官方 Tunnel → 此 Mac 的只读验收：实际返回核心 2.4.1、23 个工具、zsh，打开本项目并读取 README；5 秒及 20 秒信号命令均各启动一次，通过原会话取回输出，退出码为 0。新版菜单栏的 Core Animation 启停与真实工作状态对应。`npm test` 为 24 项通过、1 项 Windows 专用测试跳过、0 失败。详细证据与边界见 [移植记录](docs/MACOS-2.4.1-PORT.md)。

## 从源码构建

需要 Xcode Command Line Tools / Swift，以及构建工作台所用的 Node/npm。脚本将 .NET SDK 和官方 Tunnel 下载到项目内忽略的 `.tools/` 目录，不改全局运行时。支持在本机架构构建；Intel 分支尚未实机验证。构建完成后可用 `npm run clean:macos` 精简开发目录，已构建 App 可独立运行；下次编译会重新下载依赖。App 的缓存和历史保留方式见[磁盘占用与清理](docs/STORAGE-AND-CLEANUP.md)。

```sh
./scripts/build_and_run.sh             # 构建并启动
./scripts/build_and_run.sh --install   # 构建、更新 Applications 中的应用并启动
./scripts/build_and_run.sh --verify    # 构建、启动并检查进程
./scripts/build_and_run.sh --build-only
./scripts/build_preview.sh             # 生成独立 Preview.app，不安装、不自动启动
npm test                             # macOS 上运行 Mac 集成与工作台回归
npm run clean:macos                   # 构建后移除项目内的 SDK、依赖与编译缓存
./scripts/package_macos.sh             # 先重新构建，再生成 DMG、ZIP 和 SHA256SUMS
```

界面试用可打开 `dist-macos/ChatGPT Codex Workspace Preview.app`。预览使用独立应用标识与偏好；没有独立连接配置时，沿用本机正式版已有的 Tunnel ID 和钥匙串密钥项。启动仅检查密钥项是否存在，不读取密钥内容；设置显示“已保存，连接时读取”，主动保存或连接时才读取，密钥没有修改时不复制或重复写入。预览中新填写的密钥保存在独立项目中。本地检查的临时数据在停止后清理。预览仍在运行时，构建脚本拒绝覆盖它。验证范围见 [1.6 记录](docs/LOCAL-CAPABILITIES-1.6.md)，生产图标来源见 [资源说明](docs/ASSET-SOURCES.md)。

后续修改代码或获取 GitHub 更新后，在项目目录运行 `./scripts/build_and_run.sh --install` 即可更新本机应用。脚本先在临时目录完成构建与签名验证，通过后才替换 `/Applications/ChatGPT Codex Workspace.app`；编译失败时，已安装版本仍可用。更新只关闭对应路径中的 ChatGPT Codex Workspace，不按进程名停止其他副本。钥匙串中的运行密钥和应用偏好设置独立于 `.app`，更新时保留。安装器会把同标识的旧 `Local Workspace.app` 迁移为新名称；名称变化不会更改钥匙串或偏好设置。

如果已经构建好，只想安装当前构建，可运行 `./scripts/install_macos.sh`。需要安装到个人应用目录时，先创建 `~/Applications`，再运行 `./scripts/install_macos.sh --destination "$HOME/Applications"`。安装器会检查应用标识和签名，拒绝覆盖同名的其他应用或符号链接。更新中如果复制或签名验证失败，会保留或恢复原版应用。

目录：`macos/Sources/LocalWorkspace` 为原生应用；`macos/backend` 是现代 .NET 适配层；`src/` 继续作为共享工具核心，平台差异用 `MACOS` 条件编译隔离。

上游 Windows 使用方式与原有发布记录保留在 `README.md` 的上游说明区。此 Fork 由 Ne1ther 维护 macOS 适配；不会直接推送到上游主分支。
