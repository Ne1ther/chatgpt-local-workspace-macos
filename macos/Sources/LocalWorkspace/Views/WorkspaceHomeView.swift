import SwiftUI

struct WorkspaceHomeView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    private var latest: ActivityEntry? { store.activity.first { !$0.isConnectionEvent } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 18) {
                    WorkspaceBrandMark(size: 52)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("本地工作区")
                            .font(.system(size: 25, weight: .semibold))
                        Text(statusDescription).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    StatusLabel(state: store.state).font(.callout)
                }
                WorkspaceFlowView(store: store).padding(.vertical, 12)
                HStack(spacing: 12) {
                    Button(primaryTitle, systemImage: store.running ? "rectangle.3.group" : "link", action: primaryAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.busy)
                    Button("本地能力与权限", systemImage: "folder.badge.gearshape") { store.destination = .access }
                    Spacer()
                    if store.activeWorkCount > 0 && !store.snapshotStale {
                        Text("\(store.activeWorkCount) 项执行中").font(.callout.monospacedDigit())
                            .foregroundStyle(.blue).contentTransition(.numericText())
                    }
                }.controlSize(.large)
                WorkspaceAdviceView(store: store)
                Divider()
                VStack(alignment: .leading, spacing: 15) {
                    HStack {
                        Text(store.activeWorkCount > 0 ? "正在进行" : "最近操作").font(.headline)
                        Spacer()
                        if !store.activity.isEmpty { Button("全部记录") { store.destination = .activity }.buttonStyle(.link) }
                    }
                    if let entry = latest {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: entry.status == "failed" ? "exclamationmark.circle" : entry.status == "running" ? "terminal" : "checkmark.circle")
                                .font(.title3).foregroundStyle(entry.status == "failed" ? .orange : .blue).frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(entry.displayTool).font(.callout.weight(.medium)); Spacer()
                                    Text(entry.statusLabel).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(entry.target).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                            }
                        }.padding(.vertical, 10)
                    } else {
                        Text(store.running ? "首次调用后，这里会显示真实的执行记录。" : "连接后，在 ChatGPT 或 Codex 中继续你的项目。")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                }
                HStack {
                    Label("本地执行 · 加密保存", systemImage: "lock.shield"); Spacer()
                    Text("核心 \(store.coreVersion) · \(WorkspaceCore.toolCount) 个工具").monospacedDigit()
                }.font(.callout).foregroundStyle(.secondary)
            }
            .padding(36).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var primaryTitle: String { store.busy ? (store.state == .local ? "正在检查" : store.state == .starting ? "正在连接" : "正在保存") : store.running ? "查看工作台" : store.canConnect ? "连接 ChatGPT" : "设置连接" }
    private func primaryAction() {
        if store.running { store.selectConversation("") }
        else if store.canConnect { store.connect() }
        else { openSettings() }
    }
    private var statusDescription: String {
        if store.running && store.snapshotStale { return "正在重新获取本机状态。" }
        if store.state == .connected { return store.actualCallObserved ? "连接已确认，文件与执行记录在本机可见。" : "隧道已就绪，等待首次调用。" }
        if store.state == .reconnecting { return "等待网络恢复，本地任务继续运行。" }
        if store.state == .local { return store.localCheckPassed ? "本地检查通过，可以连接 ChatGPT。" : "正在检查本地工具。" }
        if store.busy { return store.operationMessage.isEmpty ? "正在建立连接。" : store.operationMessage }
        if store.state == .failed { return "连接已中断，可在设置中检查。" }
        return "将 ChatGPT 与 Codex 连接到本地项目。"
    }
}
