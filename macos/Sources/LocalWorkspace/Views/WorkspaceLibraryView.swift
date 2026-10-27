import SwiftUI
import AppKit

struct WorkspaceLibraryView: View {
    let store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""

    private var directories: [WorkspaceDirectory] {
        WorkspaceDirectory.grouped(store.conversations, activity: store.activity).compactMap { directory in
            let matchesDirectory = query.isEmpty || directory.displayPath.localizedStandardContains(query) || directory.title.localizedStandardContains(query)
            let rows = matchesDirectory ? directory.conversations : directory.conversations.filter { $0.title.localizedStandardContains(query) }
            return rows.isEmpty ? nil : WorkspaceDirectory(id: directory.id, path: directory.path, conversations: rows, latestActivity: directory.latestActivity)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("工作台").font(.system(size: 25, weight: .semibold))
                        Text("先找到工作目录，再继续对应的对话。")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.registerConversation() } label: { Label("登记对话", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).disabled(store.dashboardURL == nil)
                }
                HStack(spacing: 14) {
                    TextField("搜索目录或对话", text: $query)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                        .accessibilityLabel("搜索目录或对话")
                    Text("\(WorkspaceDirectory.grouped(store.conversations, activity: store.activity).filter { $0.path != nil }.count) 个目录 · \(store.conversations.count) 个对话")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("全部操作", systemImage: "list.bullet.rectangle") { store.openAllActivity() }
                        .disabled(store.dashboardURL == nil)
                }.controlSize(.regular)
            }
            .padding(28)
            Divider()

            if directories.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "从工作目录开始" : "没有匹配的目录或对话", systemImage: "folder.badge.plus")
                } description: {
                    Text(query.isEmpty
                         ? "连接后，已登记的对话会按本地文件夹归组。这里的分组不会移动磁盘上的文件。"
                         : "可以搜索文件夹名称、路径，或对话标题。")
                } actions: {
                    if !store.running {
                        Button("连接 ChatGPT", systemImage: "link") {
                            if store.canConnect { store.connect() } else { openSettings() }
                        }.buttonStyle(.borderedProminent).disabled(store.busy)
                        Button("运行本地检查", systemImage: "checkmark.shield") { store.runLocalCheck() }.disabled(store.busy)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(directories) { directory in directorySection(directory) }
                        Button("查看未归属操作", systemImage: "tray") { store.selectConversation("unassigned") }
                            .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    .padding(28).frame(maxWidth: 1180).frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func directorySection(_ directory: WorkspaceDirectory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: directory.path == nil ? "tray" : "folder.fill")
                    .font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(directory.title).font(.headline).lineLimit(1)
                        Text("\(directory.conversations.count) 个对话").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(directory.displayPath).font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                if let path = directory.path {
                    Button { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path) } label: {
                        Label("在访达中打开", systemImage: "arrow.up.forward.square").labelStyle(.iconOnly)
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help("在访达中打开工作目录")
                }
            }.padding(18)
            Divider().padding(.horizontal, 18)
            ForEach(directory.conversations) { conversation in
                Button { store.selectConversation(conversation.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bubble.left").foregroundStyle(.secondary).frame(width: 22)
                        Text(conversation.title).font(.callout.weight(.medium)).lineLimit(1)
                        Spacer(minLength: 12)
                        if let entry = directory.latestActivity[conversation.id] {
                            Text(entry.displayTool).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(entry.statusLabel).font(.caption)
                                .foregroundStyle(entry.status == "failed" ? Color.orange : entry.status == "running" ? Color.blue : Color.secondary)
                            Text(entry.localTime).font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        } else {
                            Text("暂无操作").font(.caption).foregroundStyle(.tertiary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("打开对话：\(conversation.title)")
            }
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}
