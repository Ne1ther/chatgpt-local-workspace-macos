import SwiftUI

/// Observed calls and command processes drive the stage; model thinking is not inferred.
struct WorkspaceFlowView: View {
    let store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var ready: Bool { store.running && !store.snapshotStale && store.state != .failed }
    private var active: Bool { ready && store.activeWorkCount > 0 }

    var body: some View {
        HStack(spacing: 0) {
            node("ChatGPT / Codex", subtitle: ready ? "等待请求" : "未连接", symbol: "bubble.left.and.bubble.right", current: false)
            connector
            node("安全连接", subtitle: store.activeCallCount > 0 && active ? "正在处理" : store.state == .connected ? "已就绪" : "本机服务", symbol: "link", current: active && store.activeCommandCount == 0)
            connector
            node("这台 Mac", subtitle: store.activeCommandCount > 0 && active ? "命令运行中" : active ? "正在执行" : "本地工作区", symbol: "desktopcomputer", current: active && store.activeCommandCount > 0)
        }
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: active)
    }
    private func node(_ title: String, subtitle: String, symbol: String, current: Bool) -> some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 29, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(current ? Color.blue : ready ? .primary : .secondary)
                .frame(width: 68, height: 68)
                .background(current ? Color.blue.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 19))
            Text(title).font(.callout.weight(.medium))
            Text(subtitle).font(.caption).foregroundStyle(current ? .blue : .secondary)
        }.frame(maxWidth: .infinity)
    }
    private var connector: some View {
        HStack(spacing: 6) {
            Rectangle().frame(height: 1).opacity(0.24)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(active ? Color.blue : .secondary)
        .frame(width: 60).offset(y: -29).accessibilityHidden(true)
    }
}
