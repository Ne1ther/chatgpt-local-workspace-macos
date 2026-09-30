import SwiftUI

struct ConnectionSettings: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                WorkspaceSymbol(name: "link", size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("连接与显示").font(.title2.weight(.semibold))
                    Text("让 ChatGPT 安全连接这台 Mac")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(WorkspaceStyle.pagePadding)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    connectionSection
                    displaySection
                    guideSection
                }
                .padding(WorkspaceStyle.pagePadding)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if !store.settingsMessage.isEmpty {
                    Label(store.settingsMessage, systemImage: store.settingsMessage.hasPrefix("已保存") ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(alignment: .center, spacing: 10) {
                    Text("默认 Shell：zsh")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Button("保存") { store.saveSettings() }
                        .disabled(store.running || store.busy)
                    Button("保存并连接", systemImage: "link") { store.connect() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.canConnect || store.running || store.busy)
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
            .padding(.horizontal, WorkspaceStyle.pagePadding)
            .padding(.vertical, 18)
        }
        .frame(width: 620, height: 700)
    }

    private var connectionSection: some View {
        WorkspaceSettingsSection(title: "安全隧道", symbol: "network") {
            VStack(alignment: .leading, spacing: 16) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        Text("Tunnel ID").frame(width: 84, alignment: .leading)
                        TextField("Tunnel ID", text: $store.tunnelID, prompt: Text("tunnel_…"))
                            .textContentType(.none)
                            .labelsHidden()
                            .accessibilityLabel("Tunnel ID")
                    }
                    GridRow {
                        Text("运行密钥").frame(width: 84, alignment: .leading)
                        SecureField("运行密钥", text: $store.apiKey, prompt: Text("API Key"))
                            .labelsHidden()
                            .accessibilityLabel("运行密钥")
                    }
                }
                .font(.callout)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disabled(store.running || store.busy)

                Divider()
                Label {
                    Text("密钥仅保存在 macOS 钥匙串。请填写具有 Tunnel 使用权限的 API Key，不是 ChatGPT 密码。")
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(3)
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if store.running || store.busy {
                    Text("连接期间配置不可修改。请先在主窗口停止连接。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var displaySection: some View {
        WorkspaceSettingsSection(title: "显示与后台", symbol: "macwindow") {
            VStack(alignment: .leading, spacing: 16) {
                WorkspacePreferenceRow(
                    title: "在菜单栏显示", description: "随时查看状态、打开窗口或停止连接",
                    symbol: "menubar.rectangle", isOn: $store.showMenuBarIcon
                )
                Divider()
                WorkspacePreferenceRow(
                    title: "在 Dock 显示", description: "在 Dock 保留应用图标与运行状态",
                    symbol: "dock.rectangle", isOn: $store.showDockIcon
                )
                Divider()
                Text("两项可以同时开启或关闭。关闭窗口后仍保留后台；只有选择“退出”或按 ⌘Q 才结束应用。都关闭时，可通过 Spotlight 搜索 ChatGPT 或 Codex 打开窗口。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
    }

    private var guideSection: some View {
        WorkspaceSettingsSection(title: "首次连接", symbol: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 14) {
                guideStep(1, "在 OpenAI Platform 创建 Tunnel，并生成运行密钥。")
                guideStep(2, "在 ChatGPT 添加 MCP 插件，选择同一个 Tunnel。")
                guideStep(3, "连接本应用，在 ChatGPT 刷新工具并核对工作区。")
                Link(destination: store.supportURL) {
                    Label("打开官方设置指南", systemImage: "arrow.up.right")
                }
                .font(.callout)
                .padding(.top, 2)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary.opacity(0.5), in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
