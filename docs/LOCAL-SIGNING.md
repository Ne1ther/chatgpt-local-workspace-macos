# 本机构建签名与钥匙串授权

临时签名（`codesign --sign -`）按构建内容识别程序。应用或后端改变后，先前的钥匙串授权可能不再匹配。固定签名证书让后续构建保持同一身份，但旧钥匙串还可能保存按二进制哈希划分的访问限制，因此固定证书本身不足以消除所有更新授权。

在自己的 Mac 上配置一次：

```sh
./scripts/setup_macos_signing.sh
./scripts/build_and_run.sh --install
```

配置脚本生成仅用于本机代码签名的证书，将不可导出的私钥存入用户默认钥匙串，只预授权 `/usr/bin/codesign` 使用。临时私钥文件在退出时删除。脚本不更改系统证书信任，也不放宽运行密钥或状态密钥的访问权限。

公有证书指纹保存在 `~/Library/Application Support/ChatGPT Codex Workspace/Build/signing-identity.txt`；私钥和此配置不提交到 Git。已有配置但签名钥匙丢失时，构建失败，不自动退回临时签名。请保留该钥匙串身份，重新生成证书会改变程序身份。

固定签名构建使用只读组件 `Contents/Helpers/workspace-credentials` 读取连接密钥。它校验直接父进程的证书、应用标识和同包路径，并要求调用方启用 Hardened Runtime，拒绝可放宽动态库校验的调用方。组件只读固定的连接项目，密钥通过 GUI 的私有管道返回，不支持任意项目查询，不接受网络请求，不写文件。

组件不会编入工作台或 Swift 界面，源码、证书和工具链不变时，其代码哈希保持一致。只修改界面时，钥匙串看到的读取程序保持不变。修改凭据组件、编译工具链或证书时仍可能需要重新授权。

首次切换时，确认请求来自安装目录中的 `workspace-credentials` 后，在系统弹窗选择“始终允许”。“允许”只授权本次访问；钥匙串锁定或访问策略变化仍可能要求确认。后端仍单独读取状态加密密钥，修改后端代码时可能产生相应授权。密码只输入系统弹窗。

连接密钥在首次连接时读取，随后只在当前 GUI 进程内复用；退出后缓存消失。状态加密密钥仍由后端在进程内缓存，保留原加密文件及钥匙串项目。

本机自签名证书不等于 Developer ID 签名或 Apple 公证。其他开发者未配置时仍可临时签名构建；也可通过 `WORKSPACE_CODESIGN_IDENTITY` 指定自己的签名身份，以及 `WORKSPACE_CODESIGN_KEYCHAIN` 指定专用构建钥匙串。显式设置 `WORKSPACE_CODESIGN_IDENTITY=-` 会改回临时签名，可能重新触发授权。

macOS 包中的 `Backend/dashboard.html` 是必需资源；页面不再嵌入后端可执行文件。Windows 继续保留嵌入页面的回退。

验证依据：[Apple 代码签名要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[签名要求语言](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)。隔离回归使用临时钥匙串，验证更换 GUI 构建后固定组件仍可非交互读取；直接调用、其他签名和未启用运行保护的调用方被拒绝。另验证不同构建目录生成相同组件代码哈希。回归只使用合成密钥。
