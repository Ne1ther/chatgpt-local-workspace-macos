import SwiftUI

struct ConversationsView: View {
    let store: WorkspaceStore
    @State private var query = ""

    private var conversations: [Conversation] {
        store.conversations.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { (latest($0)?.startedAt ?? "") > (latest($1)?.startedAt ?? "") }
    }

    private func latest(_ conversation: Conversation) -> ActivityEntry? {
        store.activity.first { !$0.isConnectionEvent && $0.threadId == conversation.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("全部对话").font(.title2.weight(.semibold))
                Text("\(store.conversations.count)").font(.callout).foregroundStyle(.tertiary)
                Spacer()
                TextField("搜索", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
                    .accessibilityLabel("搜索对话")
                Button { store.openAllActivity() } label: {
                    Label("全部操作", systemImage: "list.bullet.rectangle")
                }
                .help("查看所有对话的操作与输出")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            if conversations.isEmpty {
                ContentUnavailableView(query.isEmpty ? "暂无对话" : "没有匹配的对话", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(conversations) { conversation in
                    Button { store.selectConversation(conversation.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .resizable().scaledToFit()
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                                .frame(width: 22, height: 20)
                            Text(conversation.title)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 20)
                            if let entry = latest(conversation) {
                                Text(entry.displayTool)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Text(entry.localTime)
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 76, alignment: .trailing)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(conversation.path ?? conversation.title)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
