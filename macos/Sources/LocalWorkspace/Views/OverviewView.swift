import SwiftUI

struct OverviewView: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.openSettings) private var openSettings
    private let features: [(String, String, String)] = [
        ("folder", "文件与搜索", "浏览目录、读取文件与图片、搜索内容、导入聊天附件。"),
        ("square.and.pencil", "编辑与补丁", "精确替换、多文件修改，以及清晰的修改前后对比。"),
        ("terminal", "命令会话", "使用 zsh 或 Bash，持续读取输出、发送输入与停止命令。"),
        ("arrow.triangle.branch", "Git 审阅", "查看工作区状态与暂存差异，不会自行提交或推送。"),
        ("checklist", "计划与完成检查", "逐步跟踪任务、登记验证结果，并检查剩余工作。"),
        ("clock", "实时工作台", "按对话查看调用时间线、日志、图片和命令输出。")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 22) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 44, weight: .light)).foregroundStyle(.blue)
                        .frame(width: 86, height: 86)
                        .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("你的对话，连接这台 Mac。")
                            .font(.system(size: 30, weight: .semibold))
                        Text("让 ChatGPT 处理本地文件、执行命令，\n每一步都能在工作台看见。")
                            .font(.body).foregroundStyle(.secondary).lineSpacing(5)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(statusTitle).font(.headline)
                            Text(statusDescription).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.busy { ProgressView().controlSize(.small) }
                    }
                    HStack(spacing: 12) {
                        Button(store.canConnect ? "连接 ChatGPT" : "设置连接", systemImage: "bolt.horizontal.fill") {
                            if store.canConnect { store.connect() } else { openSettings() }
                        }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.busy || store.state == .connected)
                        Button("运行本地检查", systemImage: "checkmark.shield") { store.runLocalCheck() }
                            .controlSize(.large).disabled(store.running || store.busy)
                        Spacer()
                        Link("连接指南 ↗", destination: store.supportURL).font(.callout)
                    }
                }
                .padding(22)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary, lineWidth: 1))

                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("熟悉的功能，原生的体验").font(.title3.weight(.semibold))
                        Spacer()
                        Text("26 个本地工具").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], alignment: .leading, spacing: 24) {
                        ForEach(features, id: \.0) { item in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: item.0).font(.system(size: 18)).foregroundStyle(.blue).frame(width: 28, height: 26)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.1).font(.headline)
                                    Text(item.2).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("工作台只监听本机。连接后，ChatGPT 可通过工具访问当前用户有权限的文件与命令。停止连接或退出应用，即结束本次服务。")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }
                HStack {
                    Text("基于 CSL19980820 / chatgpt-local-workspace · MIT").font(.caption2).foregroundStyle(.tertiary)
                    Spacer()
                    Text("2.2.1 · Mac 1.2").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(36).frame(maxWidth: 1040, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    private var statusTitle: String {
        if store.state == .connected { return store.actualCallObserved ? "已收到实际工具调用" : "隧道就绪，等待 ChatGPT 调用" }
        if store.state == .local && store.localCheckPassed { return "这台 Mac 已通过本地检查" }
        if store.busy { return store.state == .local ? "正在检查本地工具…" : "正在建立连接…" }
        return "从连接你的 ChatGPT 开始"
    }
    private var statusDescription: String {
        if store.state == .connected { return "在 ChatGPT 中刷新插件，并调用 get_workspace_status 核对连接。" }
        if store.localCheckPassed { return "文件读写和命令运行正常。填写 Tunnel 配置后即可连接 ChatGPT。" }
        return "已有 Tunnel ID 和运行密钥即可连接，也可以先检查本地功能。"
    }
}
