import SwiftUI

struct ActivityView: View {
    @Bindable var store: WorkspaceStore
    @State private var search = ""
    @State private var thread = ""
    @State private var selection: String?

    private var rows: [ActivityEntry] {
        store.activity.filter {
            (thread.isEmpty || $0.threadId == thread) &&
            (search.isEmpty || ($0.tool + $0.target).localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("对话", selection: $thread) {
                    Text("全部对话").tag("")
                    Text("未归属").tag("unassigned")
                    ForEach(store.conversations) { Text($0.title).tag($0.id) }
                }
                .frame(maxWidth: 260)
                Spacer(minLength: 8)
                if store.snapshotStale {
                    Label("保留上次记录", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .help("连接失效，当前显示的是上次读取的记录")
                } else {
                    Text("\(rows.count) 条记录 · 最多 \(WorkspaceCore.activityLimit) 条")
                        .foregroundStyle(.secondary)
                }
                Button("复制", systemImage: "doc.on.doc") { copySelection() }
                    .disabled(rows.isEmpty)
                    .help("复制选中记录；未选择时复制当前显示的记录")
                Button("清空", systemImage: "trash") { selection = nil; store.clearActivity() }
                    .disabled(store.activity.isEmpty)
                    .help("仅清空当前操作记录列表，不删除已保存的文件历史")
            }
            .font(.caption)
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            if rows.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty && thread.isEmpty ? "暂无操作记录" : "没有匹配的记录",
                          systemImage: search.isEmpty && thread.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                } description: {
                    Text(search.isEmpty && thread.isEmpty
                         ? "连接后，连接状态与工具调用会自动出现在这里。"
                         : "尝试更换对话，或搜索其他工具与路径。")
                }
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("时间") {
                        Text($0.localTime).monospacedDigit().foregroundStyle(.secondary)
                    }.width(82)
                    TableColumn("工具") {
                        Text($0.tool).lineLimit(1).help($0.tool)
                    }.width(min: 132, ideal: 160, max: 208)
                    TableColumn("目标") {
                        Text($0.target).lineLimit(1).truncationMode(.middle).help($0.target)
                    }
                    TableColumn("状态") { row in
                        Text(row.statusLabel)
                            .foregroundStyle(row.status == "failed" ? Color.orange : Color.secondary)
                    }.width(64)
                    TableColumn("耗时") {
                        Text("\($0.elapsedMs) ms").monospacedDigit().foregroundStyle(.secondary)
                    }.width(82)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("复制记录", systemImage: "doc.on.doc") {
                        store.copy(rows.filter { ids.contains($0.id) }.map(\.copyText).joined(separator: "\n"))
                    }
                    Button("在工作台查看", systemImage: "rectangle.3.group") {
                        store.reviewActivity(rows.first { ids.contains($0.id) })
                    }
                    .disabled(store.dashboardURL == nil || !rows.contains { ids.contains($0.id) && !$0.isConnectionEvent })
                } primaryAction: { ids in
                    store.copy(rows.filter { ids.contains($0.id) }.map(\.copyText).joined(separator: "\n"))
                    store.reviewActivity(rows.first { ids.contains($0.id) })
                }
                .onCopyCommand {
                    let text = rows.filter { selection == nil || $0.id == selection }.map(\.copyText).joined(separator: "\n")
                    return text.isEmpty ? [] : [NSItemProvider(object: text as NSString)]
                }
            }
        }
        .searchable(text: $search, prompt: "搜索工具或路径")
    }

    private func copySelection() {
        store.copy(rows.filter { selection == nil || $0.id == selection }.map(\.copyText).joined(separator: "\n"))
    }
}
