# 本机构建签名与钥匙串授权

临时签名（`codesign --sign -`）按构建内容识别程序。应用或后端改变后，先前的钥匙串授权可能不再匹配。固定签名证书和程序标识可让后续构建保持同一身份。

在自己的 Mac 上配置一次：

```sh
./scripts/setup_macos_signing.sh
./scripts/build_and_run.sh --install
```

配置脚本生成仅用于本机代码签名的证书，将不可导出的私钥存入用户默认钥匙串，只预授权 `/usr/bin/codesign` 使用。临时私钥文件在退出时删除。脚本不更改系统证书信任，也不放宽运行密钥或状态密钥的访问权限。

公有证书指纹保存在 `~/Library/Application Support/ChatGPT Codex Workspace/Build/signing-identity.txt`；私钥和此配置不提交到 Git。已有配置但签名钥匙丢失时，构建失败，不自动退回临时签名。请保留该钥匙串身份，重新生成证书会改变程序身份。

从临时签名首次切换到固定签名时，macOS 仍可能要求重新授权。确认是安装目录中的本应用或 `workspace-server` 后，在系统弹窗选择“始终允许”。“允许”只授权本次访问；钥匙串锁定、访问策略变化或证书更换仍可能再次要求确认。密码只输入系统弹窗。

连接密钥在首次连接时读取，随后只在当前 GUI 进程内复用；退出后缓存消失。状态加密密钥仍由后端在进程内缓存，保留原加密文件及钥匙串项目。

本机自签名证书不等于 Developer ID 签名或 Apple 公证。其他开发者未配置时仍可临时签名构建；也可通过 `WORKSPACE_CODESIGN_IDENTITY` 指定自己的签名身份，以及 `WORKSPACE_CODESIGN_KEYCHAIN` 指定专用构建钥匙串。显式设置 `WORKSPACE_CODESIGN_IDENTITY=-` 会改回临时签名，可能重新触发授权。

macOS 包中的 `Backend/dashboard.html` 是必需资源；页面不再嵌入后端可执行文件。Windows 继续保留嵌入页面的回退。

验证依据：[Apple 代码签名要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[签名要求语言](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)。隔离回归使用临时钥匙串，验证修改后的同签名版本可读、其他签名不可读，不访问真实连接密钥。
