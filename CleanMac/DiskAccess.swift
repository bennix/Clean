import SwiftUI
import Combine
import AppKit
import Darwin

nonisolated enum DiskAccessState: Equatable {
    case checking, accessible, limited, unknown
    var title: String {
        switch self {
        case .checking: "磁盘权限：检查中"
        case .accessible: "磁盘权限：可读（实测）"
        case .limited: "磁盘访问：部分位置受限"
        case .unknown: "磁盘权限：未确认"
        }
    }
}

nonisolated struct AccessProbeResult: Sendable {
    let state: DiskAccessState
    let denied: [URL]
    static func classify(readable: Int, denied: [URL], protectedDatabaseReadable: Bool = false) -> AccessProbeResult {
        AccessProbeResult(state: protectedDatabaseReadable ? .accessible : !denied.isEmpty ? .limited : readable > 0 ? .accessible : .unknown, denied: denied)
    }
}

@MainActor
final class DiskAccessManager: ObservableObject {
    static let shared = DiskAccessManager()
    @Published private(set) var state: DiskAccessState = .checking
    @Published private(set) var denied: [URL] = []
    @Published private(set) var fileDenials: [URL] = []
    @Published var automaticPromptRequested = false
    @Published private(set) var checking = false
    private var promptedThisSession = false
    private var checkTask: Task<Void, Never>?

    func refresh() {
        guard !checking else { return }
        checking = true
        checkTask = Task {
            let result = await Task.detached(priority: .utility) { Self.probe() }.value
            apply(result)
            checking = false
        }
    }
    func reportDenied(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        fileDenials = Array(Set(fileDenials + urls)).sorted { $0.path < $1.path }
        // File ownership, ACLs, SIP and per-app protection can deny individual paths
        // even with FDA. Do not downgrade the protected-location probe result.
        if state != .accessible { refresh() }
    }
    func apply(_ result: AccessProbeResult) {
        state = result.state
        denied = result.denied
        if state == .accessible { automaticPromptRequested = false }
        else if state == .limited { requestAutomaticPrompt() }
    }
    private func requestAutomaticPrompt() {
        guard !promptedThisSession else { return }
        promptedThisSession = true
        automaticPromptRequested = true
    }
    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFilesAccess") else { return }
        NSWorkspace.shared.open(url)
    }
    func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    nonisolated static func probe() -> AccessProbeResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = ["Library/Mail", "Library/Safari", "Library/Messages"]
        var readable = 0
        var denied: [URL] = []
        for path in directories {
            let url = home.appendingPathComponent(path)
            errno = 0
            if let directory = opendir(url.path) {
                defer { closedir(directory) }
                errno = 0
                // Check access without reading any file contents or retaining directory names.
                _ = readdir(directory)
                if errno == EACCES || errno == EPERM { denied.append(url) }
                else if errno == 0 { readable += 1 }
            } else if errno == EACCES || errno == EPERM { denied.append(url) }
        }
        let database = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        let descriptor = open(database.path, O_RDONLY | O_CLOEXEC)
        let protectedDatabaseReadable = descriptor >= 0
        if descriptor >= 0 { close(descriptor); readable += 1 }
        else if errno == EACCES || errno == EPERM { denied.append(database) }
        return .classify(readable: readable, denied: Array(Set(denied)).sorted { $0.path < $1.path }, protectedDatabaseReadable: protectedDatabaseReadable)
    }
}

struct DiskAccessGuide: View {
    @ObservedObject var access: DiskAccessManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(access.state == .accessible ? "磁盘访问已就绪" : "检查磁盘访问状态", systemImage: "internaldrive.badge.checkmark").font(.title2.bold())
            Text(access.state.title).foregroundStyle(access.state == .limited ? .orange : .secondary)
            Text(access.state == .accessible
                 ? "受保护位置已可读取，无需重复添加授权。个别文件仍可能受所有者权限、ACL、SIP 或应用数据保护限制，它们会在扫描详情中单独列出。"
                 : "探测到部分位置读取受限，这不等于完全磁盘访问未开启。若已在设置中允许，请退出所有 Clean 进程后重新打开；个别系统或应用专属位置仍可能不可读取。")
                .font(.callout)
            if access.state != .accessible {
                DisclosureGroup("确实需要授权时，查看添加步骤") {
                    VStack(alignment: .leading, spacing: 10) {
                Text("1. 打开系统设置 → 隐私与安全性 → 完全磁盘访问权限。")
                Text("2. 点击“+”，添加下方路径的 Clean.app，并开启开关。也可以将 Finder 中的应用拖入列表。")
                Text("3. 按系统提示退出并重新打开 Clean，然后重新扫描。")
                    }.font(.callout).padding(.top, 8)
                }.font(.callout)
            }
            Text(Bundle.main.bundleURL.path).font(.caption).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            let paths = Array(Set(access.denied + access.fileDenials)).sorted { $0.path < $1.path }
            if !paths.isEmpty {
                DisclosureGroup("单独受限的位置（\(paths.count) 项）") {
                    ScrollView { VStack(alignment: .leading, spacing: 6) { ForEach(paths, id: \.path) { Text($0.path).font(.caption).textSelection(.enabled) } } }.frame(maxHeight: 100)
                }.font(.caption)
            }
            Text("状态通过实际读取检测；macOS 没有公开接口直接查询完全磁盘访问授权。权限不足也可能来自文件所有者或系统保护。检测可读不代表所有系统目录都可访问。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(access.state == .accessible ? "完成" : "关闭") { dismiss() }
                Button("重新检测") { access.refresh() }.disabled(access.checking)
                Spacer()
                if access.state != .accessible {
                    Button("在 Finder 中显示 Clean") { access.revealApp() }
                    Button("打开授权设置") { access.openSettings() }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(28).frame(width: 680)
    }
}
