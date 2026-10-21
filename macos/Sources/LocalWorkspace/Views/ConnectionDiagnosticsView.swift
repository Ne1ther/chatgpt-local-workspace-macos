import SwiftUI

struct ConnectionDiagnosticsView: View {
    let store: WorkspaceStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "stethoscope").font(.title2).foregroundStyle(.blue)
                Text("连接诊断").font(.title2.weight(.semibold))
                Spacer()
                if store.diagnosticsBusy { ProgressView().controlSize(.small) }
            }
            Text("区分隧道就绪、工具发现与真正的网页调用。检查不会停止现有任务。")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let report = store.diagnosticReport {
                        ForEach(Array(report.checks.enumerated()), id: \.offset) { _, check in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: check.status == "pass" ? "checkmark.circle.fill" : check.status == "fail" ? "exclamationmark.circle" : "circle.dashed")
                                    .foregroundStyle(check.status == "pass" ? Color.green : check.status == "fail" ? .orange : .secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(check.label).font(.callout.weight(.medium))
                                        Spacer()
                                        Text(check.statusLabel).font(.callout).foregroundStyle(.secondary)
                                    }
                                    Text(check.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                        }
                        if let versions = report.versions {
                            Divider()
                            Text("运行组件").font(.headline)
                            ForEach(versions, id: \.id) { version in
                                HStack(alignment: .top) {
                                    Text(version.label)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(version.running ?? "未确认").monospacedDigit()
                                        if version.restartRequired {
                                            Text("磁盘 \(version.installed ?? "") · 需重启").foregroundStyle(.orange)
                                        }
                                    }
                                }.font(.callout)
                            }
                        }
                        DisclosureGroup("完整报告") { reportText }
                    } else { reportText }
                }.padding(.trailing, 8)
            }
            Divider()
            HStack {
                Button("复制报告", systemImage: "doc.on.doc") { store.copy(store.diagnostics ?? "") }
                    .disabled(store.diagnosticsBusy)
                Button("本地能力与权限") { store.closeDiagnostics(); store.destination = .access }
                Spacer()
                Button(store.diagnosticsBusy ? "取消" : "完成") { store.closeDiagnostics() }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 640, height: 600)
    }
    private var reportText: some View {
        Text(store.diagnostics ?? "").font(.callout).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}
