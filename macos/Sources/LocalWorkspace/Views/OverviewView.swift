import SwiftUI

struct OverviewView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    private let features: [(String, String, String)] = [
        ("folder", "文件与搜索", "浏览目录、读取文件与图片、搜索内容，导入聊天附件。"),
        ("square.and.pencil", "编辑与历史恢复", "预演与版本检查，保存直接文件修改历史，支持撤销与重做。"),
        ("terminal", "命令会话", "运行 zsh 或 Bash，防止重试重复执行，分页读取长输出。"),
        ("arrow.triangle.branch", "Git 审阅", "按审阅基准查看修改与暂存差异，不会自行提交或推送。"),
        ("checklist", "计划与验证", "跟踪任务进展、登记验证结果，检查剩余工作。"),
        ("clock.arrow.circlepath", "实时工作台", "按对话查看调用与输出，本地保存计划、对话与近期记录。")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 20) {
                    WorkspaceBrandMark(size: 76)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("让 AI，连接你的 Mac。")
                            .font(.system(size: 28, weight: .semibold))
                        Text("在 ChatGPT 中处理本地项目，每一步都清晰可见。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)

                connectionCard

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("你的本地工作区").font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(WorkspaceCore.toolCount) 个工具").font(.caption).foregroundStyle(.secondary)
                    }
                    WorkspaceCard {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)],
                            alignment: .leading,
                            spacing: 18
                        ) {
                            ForEach(features, id: \.0) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    WorkspaceSymbol(name: item.0)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.1).font(.callout.weight(.semibold))
                                        Text(item.2)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .lineSpacing(3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("工作台仅监听本机。连接后，ChatGPT 可访问当前用户有权限的文件与命令；停止连接或退出应用，即结束服务。")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                    .foregroundStyle(.secondary)
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Text("CSL19980820 / chatgpt-local-workspace · MIT")
                        Spacer(minLength: 12)
                        Text(versionLabel).monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(WorkspaceStyle.pagePadding)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var connectionCard: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    WorkspaceSymbol(name: connectionSymbol, size: 40)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(statusTitle).font(.headline)
                        Text(statusDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StatusLabel(state: store.state)
                        .padding(.top, 2)
                }
                HStack(spacing: 10) {
                    Button(primaryTitle, systemImage: primarySymbol, action: primaryAction)
                        .buttonStyle(.borderedProminent)
                    Button("本地检查", systemImage: "checkmark.shield") { store.runLocalCheck() }
                        .disabled(store.running || store.busy)
                    if store.dashboardURL != nil {
                        Button("打开工作台", systemImage: "rectangle.3.group") { store.destination = .workbench }
                    }
                    Spacer(minLength: 8)
                    Link(destination: store.supportURL) {
                        Label("连接指南", systemImage: "arrow.up.right")
                            .font(.callout)
                    }
                }
                .controlSize(.large)
            }
        }
    }

    private var primaryTitle: String { store.running || store.busy ? "停止连接" : store.canConnect ? "连接 ChatGPT" : "设置连接" }
    private var primarySymbol: String { store.running || store.busy ? "stop.fill" : store.canConnect ? "link" : "slider.horizontal.3" }
    private var connectionSymbol: String { store.state == .connected ? "checkmark.circle" : store.state == .local ? "checkmark.shield" : "link" }
    private func primaryAction() {
        if store.running || store.busy { store.stop() }
        else if store.canConnect { store.connect() }
        else { openSettings() }
    }
    private var statusTitle: String {
        if store.state == .connected { return store.actualCallObserved ? "ChatGPT 已连接到这台 Mac" : "连接就绪，等待 ChatGPT 调用" }
        if store.state == .reconnecting { return "等待网络恢复" }
        if store.state == .local && store.localCheckPassed { return "本地工具已通过检查" }
        if store.busy { return store.state == .local ? "正在检查本地工具…" : "正在建立连接…" }
        if store.state == .failed { return "连接中断，请检查设置" }
        return "开始连接你的 ChatGPT"
    }
    private var statusDescription: String {
        if store.state == .connected { return "在 ChatGPT 中刷新插件，再调用 get_workspace_status 确认工作区。" }
        if store.state == .reconnecting { return "本地任务仍在运行，隧道会在网络恢复后重新就绪。" }
        if store.state == .local && store.localCheckPassed { return "文件读写和命令运行正常。填写 Tunnel 配置后即可连接 ChatGPT。" }
        if store.busy { return store.state == .local ? "正在验证工具发现、文件读写与 Shell 命令。" : "正在启动安全隧道，请稍候。" }
        return "填写 Tunnel ID 与运行密钥即可连接，也可以先检查本地工具。"
    }
    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
        return "Mac \(version) · 核心 \(store.coreVersion)"
    }
}
