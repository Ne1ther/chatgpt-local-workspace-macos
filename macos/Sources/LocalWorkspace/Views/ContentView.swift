import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(Destination.allCases, selection: $store.destination) { item in
                    Label(item.rawValue, systemImage: item.symbol).tag(item)
                        .padding(.vertical, 5)
                }
                .listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 14) {
                    StatusLabel(state: store.state)
                    Text("26 个工具 · macOS")
                        .font(.caption).foregroundStyle(.secondary)
                    SettingsLink { Label("连接设置", systemImage: "gearshape") }
                        .buttonStyle(.plain)
                        .help("连接设置（⌘,）")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 176, ideal: 195, max: 235)
        } detail: {
            VStack(spacing: 0) {
                if let issue = store.issue {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text(issue).font(.callout)
                        Spacer()
                        Button("关闭", systemImage: "xmark") { store.issue = nil }.labelStyle(.iconOnly).buttonStyle(.plain)
                    }.padding(12).background(.orange.opacity(0.08))
                }
                switch store.destination ?? .overview {
                case .overview: OverviewView(store: store)
                case .workbench:
                    if let url = store.dashboardURL {
                        VStack(spacing: 0) {
                            if store.state == .local {
                                Text("本地自检记录 · 尚未连接 ChatGPT")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(8).background(.quaternary.opacity(0.4))
                            }
                            DashboardView(url: url, revision: store.dashboardRevision)
                        }
                    } else {
                        ContentUnavailableView {
                            Label(store.state == .connected ? "等待首次调用" : "工作台尚未启动", systemImage: "rectangle.3.group")
                        } description: {
                            Text(store.state == .connected ? "隧道已就绪。在 ChatGPT 中刷新插件或调用 get_workspace_status 后，时间线会显示在这里。" : "连接后，在这里查看每次文件操作、执行计划、命令输出和修改对比。")
                        } actions: {
                            Button("运行本地检查") { store.runLocalCheck() }.disabled(store.running || store.busy)
                        }
                    }
                case .activity: ActivityView(store: store)
                case .logs: LogsView(store: store)
                }
            }
            .navigationTitle((store.destination ?? .overview).rawValue)
            .toolbar {
                ToolbarItem(placement: .status) { StatusLabel(state: store.state) }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { store.openBrowser() } label: { Label("在浏览器打开", systemImage: "safari") }
                        .disabled(store.dashboardURL == nil)
                    Button { store.showDiagnostics() } label: { Label("诊断连接", systemImage: "stethoscope") }
                    Menu {
                        Button("刷新工作台", systemImage: "arrow.clockwise") { store.refreshDashboard() }.disabled(store.dashboardURL == nil)
                        Button("复制工作台链接", systemImage: "link") { if let url = store.dashboardURL { store.copy(url.absoluteString) } }.disabled(store.dashboardURL == nil)
                        Divider()
                        Button("复制原始日志", systemImage: "doc.on.doc") { store.copy(store.logs.map(\.text).joined(separator: "\n")) }
                        Button("清空日志", systemImage: "trash") { store.logs.removeAll() }
                    } label: { Label("更多", systemImage: "ellipsis.circle") }
                    Button {
                        if store.running || store.busy { store.stop() }
                        else if store.canConnect { store.connect() }
                        else { openSettings() }
                    } label: {
                        Label(store.running || store.busy ? "停止" : "连接 ChatGPT", systemImage: store.running || store.busy ? "stop.fill" : "bolt.horizontal.fill")
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { store.diagnostics != nil }, set: { if !$0 { store.diagnostics = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("连接诊断", systemImage: "stethoscope").font(.title2.bold())
                ScrollView { Text(store.diagnostics ?? "").frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                HStack { Spacer(); Button("完成") { store.diagnostics = nil }.keyboardShortcut(.defaultAction) }
            }.padding(28).frame(width: 520, height: 480)
        }
    }
}

struct StatusLabel: View {
    let state: ConnectionState
    var body: some View {
        HStack(spacing: 7) {
            if state == .starting { ProgressView().controlSize(.mini) }
            else { Circle().fill(color).frame(width: 7, height: 7) }
            Text(state.label).font(.callout)
        }.accessibilityElement(children: .combine)
    }
    private var color: Color {
        switch state { case .connected: .green; case .local: .blue; case .failed, .reconnecting: .orange; default: .secondary }
    }
}
