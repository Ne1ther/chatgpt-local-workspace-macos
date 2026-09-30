import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(Destination.allCases, selection: $store.destination) { item in
                    Label {
                        Text(item.rawValue)
                    } icon: {
                        Image(systemName: item.symbol)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .tag(item)
                    .padding(.vertical, 3)
                }
                .listStyle(.sidebar)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    StatusLabel(state: store.state)
                    Text("26 个工具 · macOS")
                        .font(.caption).foregroundStyle(.secondary)
                    SettingsLink {
                        Label("连接与显示", systemImage: "slider.horizontal.3")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .help("连接与显示（⌘,）")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .navigationSplitViewColumnWidth(min: 176, ideal: 200, max: 235)
        } detail: {
            VStack(spacing: 0) {
                if let issue = store.issue { issueBanner(issue) }
                destinationView
            }
            .navigationTitle((store.destination ?? .overview).rawValue)
            .toolbar {
                ToolbarItem(placement: .status) { StatusLabel(state: store.state) }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { store.openBrowser() } label: {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                    .disabled(store.dashboardURL == nil)
                    .help("在浏览器打开工作台")
                    Button { store.showDiagnostics() } label: {
                        Label("诊断连接", systemImage: "stethoscope")
                    }
                    .help("诊断连接")
                    Menu {
                        Button("刷新工作台", systemImage: "arrow.clockwise") { store.refreshDashboard() }
                            .disabled(store.dashboardURL == nil)
                        Button("复制工作台链接", systemImage: "link") {
                            if let url = store.dashboardURL { store.copy(url.absoluteString) }
                        }
                        .disabled(store.dashboardURL == nil)
                        Divider()
                        Button("复制原始日志", systemImage: "doc.on.doc") {
                            store.copy(store.logs.map(\.text).joined(separator: "\n"))
                        }
                        Button("清空日志", systemImage: "trash") { store.logs.removeAll() }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .help("更多工作区操作")
                    Button {
                        if store.running || store.busy { store.stop() }
                        else if store.canConnect { store.connect() }
                        else { openSettings() }
                    } label: {
                        Label(store.running || store.busy ? "停止" : "连接 ChatGPT",
                              systemImage: store.running || store.busy ? "stop.fill" : "link")
                    }
                    .help(store.running || store.busy ? "停止当前连接" : "连接 ChatGPT")
                }
            }
        }
        .sheet(isPresented: Binding(get: { store.diagnostics != nil }, set: { if !$0 { store.diagnostics = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    WorkspaceSymbol(name: "stethoscope", size: 40)
                    Text("连接诊断").font(.title2.weight(.semibold))
                }
                Divider()
                ScrollView {
                    Text(store.diagnostics ?? "")
                        .font(.callout)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                HStack {
                    Spacer()
                    Button("完成") { store.diagnostics = nil }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(WorkspaceStyle.pagePadding)
            .frame(width: 540, height: 480)
        }
    }

    @ViewBuilder private var destinationView: some View {
        switch store.destination ?? .overview {
        case .overview: OverviewView(store: store)
        case .workbench:
            if let url = store.dashboardURL {
                VStack(spacing: 0) {
                    if store.state == .local {
                        Label("本地自检记录 · 尚未连接 ChatGPT", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.quaternary.opacity(0.4))
                        Divider()
                    }
                    DashboardView(url: url, revision: store.dashboardRevision)
                }
            } else {
                ContentUnavailableView {
                    Label(store.state == .connected ? "等待首次调用" : "工作台尚未启动", systemImage: "rectangle.3.group")
                } description: {
                    Text(store.state == .connected
                         ? "连接已就绪。在 ChatGPT 中刷新插件或调用 get_workspace_status 后，时间线会显示在这里。"
                         : "连接后，在这里查看文件操作、执行计划、命令输出与修改对比。")
                } actions: {
                    Button("运行本地检查", systemImage: "checkmark.shield") { store.runLocalCheck() }
                        .disabled(store.running || store.busy)
                }
            }
        case .activity: ActivityView(store: store)
        case .logs: LogsView(store: store)
        }
    }

    private func issueBanner(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text(issue)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.issue = nil } label: {
                Label("关闭提示", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭提示")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.orange.opacity(0.08))
    }
}

struct StatusLabel: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 7) {
            if state == .starting {
                ProgressView().controlSize(.mini).frame(width: 8, height: 8)
            } else {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(state.label).font(.callout).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
    private var color: Color {
        switch state {
        case .connected: .green
        case .local: .blue
        case .failed, .reconnecting: .orange
        default: .secondary
        }
    }
}
