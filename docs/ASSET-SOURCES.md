# 生产资源来源

本文记录 macOS 1.6.0 / 核心 2.4.1 源码所需的图形来源。候选库、生成式参考图、视觉对照和本机状态截图不属于本次源码发布内容。

## 应用与菜单栏图标

- 当前打包母版：`macos/Resources/Brand/InterlaceApp.png`、`macos/Resources/Brand/InterlaceMenuOptical.png`。
- 这些是经 ImageGen 调整的专用应用及透明菜单栏母版，由 `script/generate_icons.swift` 使用 AppKit 打包；构建输出为 `macos/Resources/AppIcon.png`、`AppIcon.icns` 及两种密度的 `MenuBarIconTemplate*.png`。
- 旧版 `InterlaceMenu.png`、概念图和对照图不参与当前应用打包。应用图标不代表 OpenAI 官方产品，网页插件图标也不会随本机资源自动更新。

## Phosphor 工作台图形

- 来源：[phosphor-icons/core](https://github.com/phosphor-icons/core)，固定提交 `2b75f3ad12b420c9504ef05df8d2564a28f8500e`，使用 `assets/duotone/` 中选定的 SVG。
- `script/generate_phosphor_icons.cjs` 提取 SVG 主体并映射到界面语义名称，生成 `src/ui/assets/phosphor-icons.json`；不需要运行时 CDN。
- MIT 版权及许可全文保存在 [`macos/Resources/Phosphor-MIT.txt`](../macos/Resources/Phosphor-MIT.txt)，构建时随应用分发。生成脚本目前另从 `docs/design-preview/icon-library-research/phosphor/LICENSE` 复制相同许可，因此该文件需与脚本一起保留。

## macOS 系统图形

原生界面使用系统 SF Symbols。`script/generate_ui_symbols.swift` 通过 AppKit 的 `NSImage(systemSymbolName:)` 导出工作台使用的 16 个系统图形，写入 `src/ui/assets/macos-symbols.json`；缺失时由 macOS 构建脚本生成。这些系统图形的权利归其原权利人，本项目 MIT 许可不替代 Apple 对系统图形的条款。

## 研究素材的范围

`docs/design-preview/icon-library-research/` 中的 Phosphor、MingCute、Rune、Lobe 候选来源清单与各自许可仅服务于此前比较。它们不代表全部被产品采用；除上述生成脚本依赖的 Phosphor 许可外，本次无需纳入其余候选 SVG、画板或研究脚本。
