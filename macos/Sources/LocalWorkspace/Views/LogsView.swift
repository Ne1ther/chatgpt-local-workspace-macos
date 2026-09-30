import SwiftUI

struct LogsView: View {
    @Bindable var store: WorkspaceStore
    @State private var search = ""
    @State private var follow = true
    var rows: [LogEntry] { store.logs.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("跟随最新", isOn: $follow).toggleStyle(.checkbox)
                Spacer()
                Button("复制日志", systemImage: "doc.on.doc") { store.copy(rows.map(\.text).joined(separator: "\n")) }
                Button("清空", systemImage: "trash") { store.logs.removeAll() }
            }.padding(16)
            Divider()
            if rows.isEmpty {
                ContentUnavailableView("暂无日志", systemImage: "terminal", description: Text("本地服务与官方 Tunnel 的日志会显示在这里。"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(rows) { row in
                                HStack(alignment: .top, spacing: 16) {
                                    Text(row.time.formatted(date: .omitted, time: .standard)).foregroundStyle(.tertiary)
                                    Text(row.text).foregroundStyle(row.isError ? Color.orange : row.isTool ? Color.blue : Color.primary)
                                }
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).id(row.id)
                            }
                        }.padding(18)
                    }
                    .onChange(of: store.logs.count) { _, _ in
                        if follow, let last = rows.last { proxy.scrollTo(last.id, anchor: .bottomLeading) }
                    }
                }
            }
        }.searchable(text: $search, prompt: "搜索日志")
    }
}
