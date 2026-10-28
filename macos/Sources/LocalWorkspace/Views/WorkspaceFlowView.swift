import SwiftUI

/// Observed calls and command processes drive the stage; model thinking is not inferred.
struct WorkspaceFlowView: View {
    let store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredStage: String?
    private var ready: Bool { store.running && !store.snapshotStale && store.state != .failed }
    private var active: Bool { ready && store.activeWorkCount > 0 }

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 12) {
            // Connectors and symbols share one row: no optical offset or card-height dependency.
            GridRow {
                symbol("chat", name: "bubble.left.and.bubble.right", color: WorkspacePalette.violet, current: false)
                connector
                symbol("tunnel", name: "link", color: WorkspacePalette.blue, current: active && store.activeCommandCount == 0)
                connector
                symbol("mac", name: "desktopcomputer", color: WorkspacePalette.teal, current: active && store.activeCommandCount > 0)
            }
            GridRow {
                caption("ChatGPT / Codex", subtitle: ready ? "等待请求" : "未连接", color: WorkspacePalette.violet)
                Color.clear.frame(width: 40, height: 1)
                caption("安全连接", subtitle: store.activeCallCount > 0 && active ? "正在处理" : store.state == .connected ? "已就绪" : "本机服务", color: WorkspacePalette.blue)
                Color.clear.frame(width: 40, height: 1)
                caption("这台 Mac", subtitle: store.activeCommandCount > 0 && active ? "命令运行中" : active ? "正在执行" : "本地工作区", color: WorkspacePalette.teal)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: active)
    }

    private func symbol(_ id: String, name: String, color: Color, current: Bool) -> some View {
        Image(systemName: name).font(.system(size: 32, weight: .regular))
            .symbolRenderingMode(.hierarchical).foregroundStyle(color)
            .frame(maxWidth: .infinity).frame(height: 48)
            .symbolEffect(.bounce, value: reduceMotion ? false : current)
            .scaleEffect(hoveredStage == id && !reduceMotion ? 1.06 : 1)
            .onHover { inside in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { hoveredStage = inside ? id : nil }
            }
            .accessibilityHidden(true)
    }

    private func caption(_ title: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.callout.weight(.semibold)).foregroundStyle(WorkspacePalette.text)
            Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.1), in: Capsule())
                .contentTransition(.opacity)
        }.frame(maxWidth: .infinity)
    }

    private var connector: some View {
        HStack(spacing: 5) {
            Rectangle().fill(WorkspacePalette.border).frame(height: 1)
            Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium))
                .foregroundStyle(WorkspacePalette.secondaryText)
        }.frame(width: 40, height: 48).accessibilityHidden(true)
    }
}
