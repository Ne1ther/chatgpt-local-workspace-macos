import SwiftUI

struct LogsView: View {
    @Bindable var store: WorkspaceStore
    @State private var search = ""
    @State private var follow = true

    private var rows: [LogEntry] {
        store.logs.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle("跟随最新", isOn: $follow).toggleStyle(.checkbox)
                Text("\(rows.count) 条日志")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("复制", systemImage: "doc.on.doc") {
                    store.copy(rows.map(\.text).joined(separator: "\n"))
                }
                .disabled(rows.isEmpty)
                .help("复制当前显示的日志")
                Button("清空", systemImage: "trash") { store.logs.removeAll() }
                    .disabled(store.logs.isEmpty)
            }
            .controlSize(.small)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            if rows.isEmpty {
                ContentUnavailableView {
                    Label(search.isEmpty ? "暂无日志" : "没有匹配的日志",
                          systemImage: search.isEmpty ? "text.alignleft" : "magnifyingglass")
                } description: {
                    Text(search.isEmpty ? "本地服务与安全隧道的日志会显示在这里。" : "尝试搜索其他关键词。")
                }
            } else {
                ScrollViewReader { proxy in
                    GeometryReader { geometry in
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(rows) { row in
                                    HStack(alignment: .top, spacing: 18) {
                                        Text(row.time.formatted(date: .omitted, time: .standard))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 72, alignment: .leading)
                                        Text(row.text)
                                            .fixedSize(horizontal: true, vertical: false)
                                            .foregroundStyle(row.isError ? Color.orange : row.isTool ? Color.accentColor : Color.primary)
                                    }
                                    .font(.system(size: 12, design: .monospaced))
                                    .padding(.vertical, 5)
                                    .textSelection(.enabled)
                                    .id(row.id)
                                }
                            }
                            .frame(minWidth: max(0, geometry.size.width - 40), alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }
                    }
                    .onChange(of: store.logs.count) { _, _ in
                        scrollToLatest(proxy)
                    }
                    .onChange(of: follow) { _, value in
                        if value { scrollToLatest(proxy) }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "搜索日志")
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if follow, let last = rows.last { proxy.scrollTo(last.id, anchor: .bottomLeading) }
    }
}
