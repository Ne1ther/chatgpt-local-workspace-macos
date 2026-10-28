import AppKit
import SwiftUI

struct StatusMenuView: View {
    let store: WorkspaceStore
    let delegate: AppDelegate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var activeCount: Int { store.activeCommandCount > 0 ? store.activeCommandCount : store.activeCallCount }
    private var workLabel: String {
        if store.snapshotStale { return "状态暂不可用" }
        if store.activeCommandCount > 0 { return "命令正在运行" }
        return store.activeCallCount > 0 ? "正在处理调用" : "已就绪，等待调用"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                WorkspaceBrandMark(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地工作区").font(.headline)
                    StatusLabel(state: store.state).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if store.running {
                HStack {
                    Label(workLabel,
                          systemImage: store.activeWorkCount > 0 ? "terminal" : "checkmark.circle")
                    Spacer()
                    if store.activeWorkCount > 0 && !store.snapshotStale {
                        Text("\(activeCount)").font(.callout.monospacedDigit()).foregroundStyle(.mint)
                            .contentTransition(.numericText())
                    }
                }
                .font(.callout)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: store.activeWorkCount)
                Text(store.snapshotStale ? "连接恢复后将更新本机状态。" : "文件、命令输出与操作记录可在工作台查看。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { store.destination = .workbench; delegate.showMainWindow() } label: {
                    HStack { Text("查看工作台"); Spacer(); Image(systemName: "arrow.up.right") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(WorkspacePalette.button).controlSize(.large)
            } else {
                Button("连接 ChatGPT", systemImage: "link") {
                    if store.canConnect { store.connect() } else { showSettings() }
                }
                .buttonStyle(.borderedProminent).tint(WorkspacePalette.button).controlSize(.large)
            }
            HStack {
                Button("主窗口", systemImage: "macwindow") { delegate.showMainWindow() }
                Spacer()
                Menu {
                    Button("打开 Tunnel 状态页", systemImage: "network") { store.openTunnelStatus() }.disabled(store.tunnelStatusURL == nil)
                    Button("诊断连接", systemImage: "stethoscope") { store.showDiagnostics(); delegate.showMainWindow() }
                    if store.running || store.busy {
                        Button("停止连接", systemImage: "stop.circle") { store.stop() }
                    }
                    Divider()
                    Button("退出 ChatGPT Codex Workspace", systemImage: "power") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("更多操作")
                Button { showSettings() } label: { Image(systemName: "gearshape") }.help("连接与显示")
            }
            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 300)
    }
    private func showSettings() {
        delegate.showSettings()
    }
}
