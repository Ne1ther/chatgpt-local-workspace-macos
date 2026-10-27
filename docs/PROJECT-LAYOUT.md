# 项目目录

- `macos/`：原生窗口、菜单栏、设置与 macOS 后端适配。`Sources/LocalWorkspace/Views/WorkspaceLibraryView.swift` 是按目录归组的工作台入口。
- `src/`：共享 C# 核心；`src/ui/` 是 React 工作台；`dashboard.css` 为样式源，`dashboard.html` 是构建脚本生成、供应用内嵌的单文件页面。
- `scripts/`：统一的构建、预览、检查和资源生成入口。Windows 专用脚本位于 `scripts/windows/`，均从项目根目录读写构建产物。
- `tests/`：隔离的功能和界面回归。
- `assets/`、`macos/Resources/`：产品实际使用的资源及来源许可。
- `docs/`：使用、架构与验证文档。
- `.local/`：仅本机保留的设计研究、旧母版、渲染脚本和界面验证材料，已忽略，不参与打包或推送。
- `.tools/`、`node_modules/`、`macos/.build/`、`macos/backend/{bin,obj}/`：可重新生成的开发依赖和缓存。
- `dist-macos/`：构建输出。正在使用的正式安装位于 `/Applications/ChatGPT Codex Workspace.app`。

## 常用入口

```sh
npm ci
npm run build:ui
./scripts/build_and_run.sh --build-only
./scripts/build_preview.sh
npm test
npm run clean:macos
```

`clean:macos` 仅清理开发缓存，不处理用户数据、安装的应用或本机设计归档。界面中的目录归组只整理显示关系，不移动项目文件，也不合并对话历史。
