import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sidebarVisible = true

    private enum SidebarSelection: Hashable {
        case page(Destination), conversation(String)
    }
    private var selection: Binding<SidebarSelection?> {
        Binding(get: {
            store.destination == .workbench ? .conversation(store.selectedThreadID) : .page(store.destination ?? .overview)
        }, set: { value in
            switch value {
            case .conversation(let id): store.selectConversation(id)
            case .page(let page): store.destination = page
            case nil: break
            }
        })
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
            VStack(spacing: 0) {
                List(selection: selection) {
                    ForEach(Destination.allCases) { item in
                        Label { Text(item.rawValue).foregroundStyle(pageSelected(item) ? Color.white : .primary) } icon: {
                            sidebarSymbol(item.symbol, color: item == .overview ? .indigo : item == .workbench ? .blue : item == .activity ? .purple : .secondary,
                                          selected: pageSelected(item))
                        }
                        .tag(item == .workbench ? SidebarSelection.conversation("") : .page(item))
                    }
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                .frame(height: 194)
                Divider().padding(.horizontal, 16)
                // Project scrolling never displaces the fixed primary navigation.
                List(selection: selection) {
                    Section("工作区") {
                        ForEach(store.conversations) { conversation in
                            Label {
                                Text(conversation.title).lineLimit(1)
                                    .foregroundStyle(store.destination == .workbench && store.selectedThreadID == conversation.id ? Color.white : .primary)
                            } icon: {
                                sidebarSymbol("folder.fill", color: .blue, selected: store.destination == .workbench && store.selectedThreadID == conversation.id)
                            }
                            .help(conversation.path ?? conversation.title)
                            .tag(SidebarSelection.conversation(conversation.id))
                        }
                        Label { Text("未归属").foregroundStyle(store.destination == .workbench && store.selectedThreadID == "unassigned" ? Color.white : .primary) } icon: { sidebarSymbol("tray.fill", color: .orange, selected: store.destination == .workbench && store.selectedThreadID == "unassigned") }
                            .tag(SidebarSelection.conversation("unassigned"))
                    }
                }
                .listStyle(.sidebar)
                .font(.system(size: 13))
                .tint(.accentColor)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Button { store.registerConversation() } label: {
                        Label("登记对话", systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(store.dashboardURL == nil)
                    SettingsLink {
                        Label("连接与显示", systemImage: "gearshape")
                    }
                    .buttonStyle(.plain)
                    .help("连接与显示（⌘,）")
                    Divider().padding(.vertical, 2)
                    StatusLabel(state: store.state)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(width: 224)
            .background(.regularMaterial)
            .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if let issue = store.issue { issueBanner(issue) }
                destinationView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle((store.destination ?? .overview).rawValue)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { sidebarVisible.toggle() }
                    } label: { Label("显示或隐藏侧栏", systemImage: "sidebar.left") }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .help("显示或隐藏侧栏（⌥⌘S）")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { store.openBrowser() } label: {
                        Label("在浏览器打开", systemImage: "safari")
                    }
                    .disabled(store.dashboardURL == nil)
                    .help("在浏览器打开工作台")
                    Menu {
                        Button("诊断连接", systemImage: "stethoscope") { store.showDiagnostics() }
                        Divider()
                        Button("打开 Tunnel 状态页", systemImage: "network") { store.openTunnelStatus() }
                            .disabled(store.tunnelStatusURL == nil)
                        Divider()
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
                        Button("清空操作记录", systemImage: "clock.arrow.circlepath") { store.clearActivity() }
                            .disabled(store.activity.isEmpty)
                        Divider()
                        Button("停止连接", systemImage: "stop.circle") { store.stop() }
                            .disabled(!store.running && !store.busy)
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .help("更多工作区操作")
                    if !store.running && !store.busy {
                        Button {
                            if store.canConnect { store.connect() } else { openSettings() }
                        } label: { Label("连接 ChatGPT", systemImage: "link") }
                    }
                }
            }
        }
        .onChange(of: scenePhase) {
            store.dashboardSession.setVisible(scenePhase == .active && store.destination == .workbench && (!store.selectedThreadID.isEmpty || store.showsAllActivity))
        }
        .sheet(isPresented: Binding(get: { store.diagnostics != nil }, set: { if !$0 { store.closeDiagnostics() } })) {
            ConnectionDiagnosticsView(store: store)
        }
    }

    private func pageSelected(_ page: Destination) -> Bool {
        store.destination == page && (page != .workbench || store.selectedThreadID.isEmpty)
    }
    private func sidebarSymbol(_ name: String, color: Color, selected: Bool = false) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(selected ? .white : color)
            .frame(width: 18, height: 18)
            .frame(width: 20, height: 20)
    }

    @ViewBuilder private var destinationView: some View {
        switch store.destination ?? .overview {
        case .overview: WorkspaceHomeView(store: store)
        case .workbench:
            if let url = store.dashboardURL {
                if store.selectedThreadID.isEmpty && !store.showsAllActivity {
                    ConversationsView(store: store)
                } else {
                    VStack(spacing: 0) {
                        if store.showsAllActivity {
                            HStack {
                                Button("全部对话", systemImage: "chevron.left") { store.selectConversation("") }
                                    .buttonStyle(.plain)
                                Spacer()
                            }.font(.callout).padding(.horizontal, 24).padding(.vertical, 10)
                        }
                    DashboardView(session: store.dashboardSession, url: url, revision: store.dashboardRevision)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear { store.dashboardSession.setVisible(true) }
                        .onDisappear { store.dashboardSession.setVisible(false) }
                    }
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
        case .access: LocalCapabilitiesView(store: store)
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
