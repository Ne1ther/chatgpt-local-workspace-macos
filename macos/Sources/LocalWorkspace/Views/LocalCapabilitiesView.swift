import SwiftUI

struct LocalCapabilitiesView: View {
    @Bindable var store: WorkspaceStore
    private var access: LocalAccessController { store.localAccess }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本地能力").font(.system(size: 26, weight: .semibold))
                    Text("先确认项目能否访问，再交给网页中的 AI 操作。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("项目访问检查").font(.headline)
                            Spacer()
                            if access.busy { ProgressView().controlSize(.small) }
                            Button("选择目录", systemImage: "folder.badge.plus") { access.chooseDirectory() }
                                .disabled(access.busy)
                        }
                        if access.path.isEmpty {
                            Text("选择一个本地项目。检查只针对这个目录，不扫描整台 Mac。")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            Text(access.path).font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        if !store.conversations.isEmpty {
                            Menu("选择已有工作区") {
                                ForEach(store.conversations.filter { $0.path != nil }) { item in
                                    Button(item.title) { if let path = item.path { access.select(path) } }
                                }
                            }.disabled(access.busy)
                        }
                        HStack(spacing: 12) {
                            Button("检查读取", systemImage: "doc.text.magnifyingglass") { access.check(base: store.dashboardURL, write: false) }
                            Button("检查读写", systemImage: "checkmark.shield") { access.check(base: store.dashboardURL, write: true) }
                            Spacer()
                            if let report = access.report { Button("复制结果") { store.copy(report.copyText) } }
                        }
                        .disabled(access.busy || access.path.isEmpty || store.dashboardURL == nil)
                        Text("读写检查会创建、写入并删除一个独立临时文件，不修改原有文件。")
                            .font(.callout).foregroundStyle(.secondary)
                        if store.dashboardURL == nil {
                            Text("本机服务尚未启动。连接后可检查；也可先运行不使用账号的本地检查。")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("运行本地检查") { store.runLocalCheck() }.disabled(store.running || store.busy)
                        }
                        if let message = access.message {
                            Label(message, systemImage: "exclamationmark.circle").font(.callout)
                                .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        if let report = access.report {
                            Divider()
                            HStack(alignment: .top, spacing: 24) {
                                checkResult("读取目录", check: report.read)
                                checkResult("创建、写入与删除", check: report.write)
                            }
                            if let actual = report.canonicalPath, actual != report.path {
                                Text("实际位置：\(actual)").font(.callout).textSelection(.enabled)
                            }
                            if let artifact = report.probeFile {
                                Text("临时文件未清理：\(artifact)").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                            }
                            Text("检查时间：\(report.checkedTime)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }.padding(16)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("权限如何生效").font(.headline)
                    capability("文件与目录", "使用当前 macOS 用户的实际权限；受保护目录仍由系统决定是否允许。", symbol: "folder")
                    capability("命令与进程", "默认超时 5 分钟；长任务可明确设置最长 24 小时，通过同一会话等待输出或停止进程树。不会自动提权。", symbol: "terminal")
                    capability("修改与恢复", "文件工具的修改支持历史预览和恢复；Shell 命令及外部程序产生的效果需要另行核对。", symbol: "clock.arrow.circlepath")
                    capability("工作区与权限范围", "选择工作区用于组织记录；当前版本没有目录白名单沙箱，不能把分组当作访问隔离。", symbol: "lock.shield")
                    HStack {
                        Button("打开文件与文件夹权限", systemImage: "gearshape") { access.openPrivacySettings() }
                        Button("复制网页测试指令", systemImage: "doc.on.doc") { store.copy(access.testPrompt) }
                    }
                    Text("检查结果只代表当前路径、当前后端和检查时刻。授权或重新签名后，请重新检查。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                WorkspaceAdviceView(store: store)
            }.padding(32).frame(maxWidth: 920, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private func checkResult(_ title: String, check: LocalAccessReport.Check) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            Label(check.label, systemImage: check.passed ? "checkmark.circle.fill" : check.status == "not_checked" ? "circle.dashed" : "exclamationmark.circle")
                .font(.callout.weight(.medium)).foregroundStyle(check.passed ? Color.green : check.status == "not_checked" ? .secondary : .orange)
            Text(check.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func capability(_ title: String, _ description: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).frame(width: 24).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.callout.weight(.medium))
                Text(description).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct WorkspaceAdviceView: View {
    let store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        let advice = store.recommendations
        if !advice.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("建议处理").font(.headline)
                ForEach(advice) { item in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.callout.weight(.medium))
                            Text(item.detail).font(.callout).foregroundStyle(WorkspacePalette.secondaryText)
                                .lineLimit(3).textSelection(.enabled)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button(item.actionLabel) {
                            switch item.action {
                            case .settings: openSettings()
                            case .diagnostics: store.showDiagnostics()
                            case .access:
                                if item.id == "host" { store.copy(store.localAccess.testPrompt) }
                                else { store.destination = .access }
                            case .workbench: store.selectConversation("")
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(WorkspacePalette.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(WorkspacePalette.orange.opacity(0.45)))
        }
    }
}
