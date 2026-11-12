import AppKit
import SwiftUI

struct ConsultCockpitView: View {
    @Bindable var store: WorkspaceStore
    @State private var previewSession: ConsultSessionSummary?
    @State private var copiedItemID: String?

    private var stagedCount: Int { store.consults.filter { $0.status == "staged" }.count }
    private var readingCount: Int { store.consults.filter { $0.status == "reading" }.count }
    private var completedCount: Int { store.consults.filter { $0.status == "completed" }.count }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            if store.consults.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(store.consults) { session in
                            consultCard(session)
                        }
                    }
                    .padding(WorkspaceStyle.pagePadding)
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(WorkspacePalette.page)
        .sheet(item: $previewSession) { session in
            if let receipt = session.receipt {
                ConsultReportPreviewSheet(store: store, session: session, receipt: receipt)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                WorkspaceSymbol(name: "sparkles.rectangle.stack", size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text("科研咨询")
                        .font(.system(size: 25, weight: .semibold))
                    Text("T3 Code ⇄ ChatGPT Web Pro 零剪贴板科研咨询管线：本地打包研究资料包、Web Pro 直接读取分析、研究报告自动归档回写。")
                        .font(.callout)
                        .foregroundStyle(WorkspacePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    countPill(label: "已打包", count: stagedCount, tint: WorkspacePalette.blue)
                    countPill(label: "读取中", count: readingCount, tint: WorkspacePalette.orange)
                    countPill(label: "已归档", count: completedCount, tint: WorkspacePalette.teal)
                }
            }
        }
        .padding(WorkspaceStyle.pagePadding)
    }

    private func countPill(label: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(count > 0 ? tint : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(count > 0 ? tint : .secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            (count > 0 ? tint.opacity(0.11) : Color.secondary.opacity(0.08)),
            in: Capsule()
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("暂无科研咨询会话", systemImage: "sparkles.rectangle.stack")
        } description: {
            Text("当 T3 Code 发起 `--stage-consult` 或 Web Pro 调用 `read_research_bundle` / `submit_pro_report` 时，资料包校验与报告归档状态将实时显示在这里。")
        } actions: {
            HStack(spacing: 12) {
                Button("查看操作记录", systemImage: "clock.arrow.circlepath") {
                    store.destination = .activity
                }
                Button("返回工作台", systemImage: "rectangle.3.group") {
                    store.destination = .workbench
                }
                .buttonStyle(.borderedProminent)
                .tint(WorkspacePalette.button)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func consultCard(_ session: ConsultSessionSummary) -> some View {
        WorkspaceCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(session.title.isEmpty ? session.consultId : session.title)
                                .font(.headline)
                                .foregroundStyle(WorkspacePalette.text)
                            Text("#\(session.consultId)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let updated = session.updatedLabel {
                                Text("· \(updated)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            Label("\(session.fileCount) 个文件", systemImage: "doc.on.doc")
                            if !session.shortSha.isEmpty {
                                Label("SHA-256 \(session.shortSha)", systemImage: "number.square")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            if !session.displayInboxDir.isEmpty {
                                Text(session.displayInboxDir)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(WorkspacePalette.secondaryText)
                    }
                    Spacer(minLength: 12)
                    statusBadge(for: session)
                }

                consultStepper(stage: session.stageIndex)

                if let receipt = session.receipt {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(WorkspacePalette.teal)
                            Text(receipt.displayReportPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(WorkspacePalette.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer()
                            if let lines = receipt.lineCount, let bytes = receipt.byteLength {
                                Text("\(lines) 行 · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !receipt.shortSha.isEmpty {
                                Text("SHA \(receipt.shortSha)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let summary = receipt.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.callout)
                                .foregroundStyle(WorkspacePalette.secondaryText)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .background(WorkspacePalette.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(WorkspacePalette.teal.opacity(0.22), lineWidth: 1)
                    )
                }

                HStack(spacing: 10) {
                    if let prompt = session.webProPrompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            copyWithFeedback(prompt, id: "prompt-\(session.id)")
                        } label: {
                            Label(copiedItemID == "prompt-\(session.id)" ? "已复制指令" : "复制 Web Pro 指令",
                                  systemImage: copiedItemID == "prompt-\(session.id)" ? "checkmark" : "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        openInFinder(path: session.inboxDir, isDirectory: true)
                    } label: {
                        Label("打开收件箱", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .disabled(session.inboxDir.isEmpty)

                    if let receipt = session.receipt {
                        Button {
                            previewSession = session
                        } label: {
                            Label("预览报告", systemImage: "doc.text.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WorkspacePalette.button)

                        Button {
                            copyWithFeedback(session.t3ReceiptText, id: "receipt-\(session.id)")
                        } label: {
                            Label(copiedItemID == "receipt-\(session.id)" ? "已复制回执" : "复制 T3 回执",
                                  systemImage: copiedItemID == "receipt-\(session.id)" ? "checkmark" : "terminal")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            openInFinder(path: receipt.reportPath, isDirectory: false)
                        } label: {
                            Label("在访达中定位", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    if let threadId = session.threadId, !threadId.isEmpty {
                        Button {
                            store.selectConversation(threadId)
                        } label: {
                            Label("关联工作台会话", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(WorkspacePalette.blue)
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    private func consultStepper(stage: Int) -> some View {
        let steps: [(index: Int, title: String, subtitle: String, icon: String)] = [
            (1, "1. 已打包 Staged", "研究资料包已生成并计算 SHA-256", "shippingbox.fill"),
            (2, "2. Web Pro 读取中", "read_research_bundle 读取材料", "sparkles"),
            (3, "3. 报告已归档 Completed", "submit_pro_report 落盘校验完成", "checkmark.seal.fill")
        ]
        return HStack(spacing: 10) {
            ForEach(steps, id: \.index) { step in
                let isReached = stage >= step.index
                let isCurrent = stage == step.index
                HStack(spacing: 10) {
                    Image(systemName: step.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isReached ? (step.index == 3 ? WorkspacePalette.teal : WorkspacePalette.blue) : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            (isReached
                             ? (step.index == 3 ? WorkspacePalette.teal : WorkspacePalette.blue).opacity(0.14)
                             : Color.secondary.opacity(0.10)),
                            in: Circle()
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(isCurrent ? .semibold : .medium))
                            .foregroundStyle(isReached ? WorkspacePalette.text : .secondary)
                        Text(step.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isCurrent
                        ? (step.index == 3 ? WorkspacePalette.teal : WorkspacePalette.blue).opacity(0.08)
                        : WorkspacePalette.raised.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isCurrent
                                ? (step.index == 3 ? WorkspacePalette.teal : WorkspacePalette.blue).opacity(0.35)
                                : WorkspacePalette.border.opacity(0.6),
                            lineWidth: 1
                        )
                )
            }
        }
    }

    private func statusBadge(for session: ConsultSessionSummary) -> some View {
        let tint: Color = session.status == "completed"
            ? WorkspacePalette.teal
            : session.status == "reading"
                ? WorkspacePalette.orange
                : WorkspacePalette.blue
        return HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(session.statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
    }

    private func copyWithFeedback(_ text: String, id: String) {
        store.copy(text)
        copiedItemID = id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if copiedItemID == id { copiedItemID = nil }
        }
    }

    private func openInFinder(path: String, isDirectory: Bool) {
        guard !path.isEmpty else { return }
        if isDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
        } else {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
        }
    }
}

private struct ConsultReportPreviewSheet: View {
    let store: WorkspaceStore
    let session: ConsultSessionSummary
    let receipt: ConsultReceiptSummary
    @Environment(\.dismiss) private var dismiss
    @State private var reportContent = ""
    @State private var loadError: String?
    @State private var copiedReceipt = false
    @State private var copiedMarkdown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                WorkspaceSymbol(name: "doc.text.magnifyingglass", size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.title.isEmpty ? "Web Pro 研究报告" : session.title)
                        .font(.headline)
                    Text(receipt.displayReportPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button {
                    store.copy(session.t3ReceiptText)
                    copiedReceipt = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedReceipt = false
                    }
                } label: {
                    Label(copiedReceipt ? "已复制 T3 回执" : "复制 T3 回执",
                          systemImage: copiedReceipt ? "checkmark" : "terminal")
                }
                .buttonStyle(.bordered)

                Button {
                    NSWorkspace.shared.selectFile(receipt.reportPath, inFileViewerRootedAtPath: (receipt.reportPath as NSString).deletingLastPathComponent)
                } label: {
                    Label("在访达中定位", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)

                Button {
                    store.copy(reportContent)
                    copiedMarkdown = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedMarkdown = false
                    }
                } label: {
                    Label(copiedMarkdown ? "已复制全文" : "复制全文",
                          systemImage: copiedMarkdown ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(reportContent.isEmpty)

                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(WorkspacePalette.surface)

            Divider()

            if let loadError {
                ContentUnavailableView {
                    Label("无法读取报告文件", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(reportContent)
                        .font(.system(size: 13.5, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(WorkspacePalette.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(24)
                }
                .background(WorkspacePalette.page)
            }
        }
        .frame(minWidth: 780, idealWidth: 880, minHeight: 540, idealHeight: 680)
        .onAppear(perform: loadReport)
    }

    private func loadReport() {
        let path = receipt.reportPath
        guard !path.isEmpty else {
            loadError = "报告文件路径为空。"
            return
        }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            reportContent = String(decoding: data, as: UTF8.self)
        } catch {
            loadError = "读取 \(receipt.displayReportPath) 失败：\(error.localizedDescription)"
        }
    }
}
