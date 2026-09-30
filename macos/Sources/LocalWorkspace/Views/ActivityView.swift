import SwiftUI

struct ActivityView: View {
    @Bindable var store: WorkspaceStore
    @State private var search = ""
    @State private var thread = ""
    @State private var selection: String?
    private var rows: [ActivityEntry] {
        store.activity.filter { (thread.isEmpty || $0.threadId == thread) && (search.isEmpty || ($0.tool + $0.target).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("对话", selection: $thread) {
                    Text("全部对话").tag("")
                    Text("未归属").tag("unassigned")
                    ForEach(store.conversations) { Text($0.title).tag($0.id) }
                }.frame(maxWidth: 360)
                Spacer()
                Text(store.snapshotStale ? "连接失效 · 保留上次记录" : "\(rows.count) 条调用 · 当前进程")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
            if rows.isEmpty {
                ContentUnavailableView("暂无操作记录", systemImage: "clock.arrow.circlepath", description: Text("连接后，工具调用会自动出现在这里。"))
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("时间") { Text($0.localTime).monospacedDigit() }.width(86)
                    TableColumn("工具", value: \.tool).width(min: 120, ideal: 170)
                    TableColumn("目标", value: \.target)
                    TableColumn("状态") { row in
                        Text(row.statusLabel).foregroundStyle(row.status == "failed" ? Color.orange : Color.secondary)
                    }.width(60)
                    TableColumn("耗时") { Text("\($0.elapsedMs) ms").monospacedDigit().foregroundStyle(.secondary) }.width(86)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("复制记录") {
                        store.copy(rows.filter { ids.contains($0.id) }.map { "\($0.startedAt)  \($0.tool)  \($0.target)  \($0.statusLabel)" }.joined(separator: "\n"))
                    }
                    Button("在工作台查看") { store.destination = .workbench }
                }
            }
        }.searchable(text: $search, prompt: "搜索工具或路径")
    }
}
