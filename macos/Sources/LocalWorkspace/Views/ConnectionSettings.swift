import SwiftUI

struct ConnectionSettings: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "network.badge.shield.half.filled").font(.largeTitle).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("连接 ChatGPT").font(.title2.bold())
                    Text("使用 OpenAI 官方 Secure MCP Tunnel").foregroundStyle(.secondary)
                }
            }
            Form {
                Section {
                    TextField("Tunnel ID", text: $store.tunnelID, prompt: Text("tunnel_…"))
                        .textContentType(.none)
                    SecureField("运行密钥", text: $store.apiKey, prompt: Text("API Key"))
                } footer: {
                    Text("运行密钥仅保存在 macOS 钥匙串。不要使用 ChatGPT 密码；此处填写 Tunnel 配置提供的 API Key。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(store.running || store.busy)
                Section("如何获取") {
                    Text("1. 在 OpenAI Platform 创建 Tunnel，获取 Tunnel ID 和运行密钥。\n2. 在 ChatGPT 开发者模式中添加连接，选择该 Tunnel。\n3. 启动本应用的连接，在 ChatGPT 刷新工具列表。")
                        .font(.callout).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    Link("打开官方设置指南 ↗", destination: store.supportURL)
                }
                Section {
                    Toggle("在菜单栏显示", isOn: $store.showMenuBarIcon)
                    Toggle("在 Dock 显示", isOn: $store.showDockIcon)
                } header: {
                    Text("关闭窗口后")
                } footer: {
                    Text("两项可同时开启或关闭。都关闭时，可用 Spotlight 搜索 ChatGPT 或 Codex 打开窗口。关闭窗口后仍保持连接；选择“退出 ChatGPT Codex Workspace”或按 ⌘Q 才结束应用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if !store.settingsMessage.isEmpty {
                Text(store.settingsMessage).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack {
                Text("默认 Shell：zsh · 系统外观自动适配").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("保存") { store.saveSettings() }.disabled(store.running || store.busy)
                Button("保存并连接") { store.connect() }
                    .buttonStyle(.borderedProminent).disabled(!store.canConnect || store.running || store.busy)
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 570, height: 620)
    }
}
