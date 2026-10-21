# 在 ChatGPT 网页创建本机工作区插件

沿用原来的连接方式：**ChatGPT 网页 → 自定义 MCP App → Secure MCP Tunnel → 此 Mac**。本机应用保持运行，网页负责创建连接和调用工具。

按 [OpenAI 自定义 MCP 服务器文档](https://developers.openai.com/api/docs/guides/custom-mcp-server) 和 [Secure MCP Tunnel 文档](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels) 整理，核对日期 2026-10-17。

## 1. 确认 Mac 服务已连接

打开 ChatGPT Codex Workspace，进入“连接与显示”，确认“隧道已就绪”。应用需要在工具调用期间持续运行。

Tunnel ID 可以在应用设置中复制；需要创建网页连接时，使用你自己的 `<TUNNEL_ID>`。

API Key 继续留在 Mac 钥匙串中。网页使用 Tunnel ID，不填写本机的 API Key。

## 2. 创建网页连接

打开 [ChatGPT Plugins](https://chatgpt.com/plugins)，点击 **＋ → Add custom MCP server（添加自定义 MCP 服务器）**。

| 项目 | 填写内容 |
| --- | --- |
| 名称 | `Local Workspace Mac` |
| 描述 | `连接这台 Mac，读取和编辑项目文件、执行命令、查看 Git 状态与任务进度。` |
| Connection / 连接方式 | `Tunnel` |
| Tunnel | 选择或粘贴应用设置中同一个 `tunnel_…` ID |
| Authentication / 认证 | `No authentication`，与本项目现有 MCP 配置一致；Tunnel 的访问权限仍由 OpenAI 控制 |

本项目使用 stdio MCP，经 Tunnel 连接。选择 Tunnel 后按页面填写，不能把 `127.0.0.1`、工作台地址或本机 `.app` 路径作为公网 Server URL。

阅读页面的连接提示，勾选确认，再点 **Create as a plugin（创建为插件）**。创建后在个人插件中打开它，点击安装；新建网页对话，在输入框键入 `@`，选择 **Local Workspace Mac**。

已有网页连接可以继续使用同一个 Tunnel；更新本机服务后刷新工具定义，并以实际工具调用确认连接。

## 3. 做一次只读验收

在已选择插件的网页对话中发送：

```text
请使用 Local Workspace Mac 调用 get_workspace_status，报告实际 version、tool_count 和 default_shell。
然后打开本地工作区 <项目绝对路径> README.macos.md 前 10 行，不修改文件。
```

macOS 1.6.0 源码构建的预期返回为核心版本 `2.4.1`、公开工具 `23` 个、默认 shell `zsh`。现有 1.4.1 Release 安装包为核心 `2.3.0`、28 个工具。网页登记版本与本机应用、核心版本分别管理，请以实际响应为准。

若工具数量不符，在该连接的工具详情中 **Refresh / 刷新工具**，再用新对话测试。若创建页看不到 Tunnel，核对 ChatGPT 账号/工作区与 Tunnel 的关联和 Use 权限。

## 4. 图标

当前图标是 [`macos/Resources/AppIcon.png`](../macos/Resources/AppIcon.png)，1024×1024 PNG，暖白底、石墨交织标志和蓝色下划线。页面若提供图标上传项，选择这个文件。

本机应用的图标不会自动同步到 ChatGPT。当前自定义 MCP 创建文档没有承诺图标上传入口；如果你的页面没有该项，先完成连接。图标是否显示，以网页实际提供的设置和显示结果为准。

## 连接与插件包的区别

单独声明 `mcp.json` 的便携插件包不等于已注册的网页 MCP App，也不能代替网页工具调用验收。

如果以后确实需要把已注册的网页连接与技能一起打包，应按 [官方打包文档](https://developers.openai.com/plugins/build/plugins#create-and-test-a-plugin-locally-with-an-mcp-server)，使用真实的已注册 App 映射。单独上传一个含 `mcp.json` 的 ZIP 不能作为网页连接验收。
