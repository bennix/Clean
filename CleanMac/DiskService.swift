import Foundation
import AppKit

nonisolated struct DiskEntry: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
    let category: String
    let sensitive: Bool
    var isComplete = true
    var isPartial = false
    var name: String { url.lastPathComponent }
}

nonisolated struct ScanResult: Sendable {
    var entries: [DiskEntry] = []
    var skipped = 0
    var issues: [ScanIssue] = []
}

nonisolated enum DiskService {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func size(_ url: URL) -> Int64 {
        measure(url).bytes
    }

    static func children(_ root: URL, category: String, sensitive: Bool = false) -> ScanResult {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
            return ScanResult(entries: urls.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }.map { DiskEntry(url: $0, bytes: size($0), category: category, sensitive: sensitive) }.sorted { $0.bytes > $1.bytes })
        } catch { return ScanResult(skipped: 1) }
    }
    static func canDelete(_ url: URL) -> Bool {
        CleanupCatalog.rule(for: url) != nil
    }
    static func matchesRunningApp(_ entry: DiskEntry, rule: CleanupRule, id: String, name: String) -> Bool {
        if rule.ownerIDs.contains(where: { $0 == id || $0.hasPrefix(id + ".") }) { return true }
        let generic = rule.root == home.appendingPathComponent("Library/Caches") || rule.root == home.appendingPathComponent("Library/Logs")
        return generic && (entry.name == id || entry.name.hasPrefix(id + ".") || name.lowercased() == entry.name.lowercased() || name.lowercased().hasPrefix(entry.name.lowercased() + " "))
    }
    static func remove(_ entries: [DiskEntry], quitApplications: Bool = false) async -> String {
        let rules = CleanupCatalog.discover().rules
        if quitApplications {
            let targets = await MainActor.run {
                NSWorkspace.shared.runningApplications.filter { app in
                    guard app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                          let id = app.bundleIdentifier, (!id.hasPrefix("com.apple.") || id == "com.apple.Safari"),
                          let executable = app.executableURL, (!executable.path.hasPrefix("/System/") || id == "com.apple.Safari") else { return false }
                    return entries.contains { entry in
                        guard entry.isComplete, !entry.isPartial, let rule = CleanupCatalog.rule(for: entry.url, in: rules) else { return false }
                        return matchesRunningApp(entry, rule: rule, id: id, name: app.localizedName ?? id)
                    }
                }.map { app in app.terminate(); return app.processIdentifier }
            }
            // Normal termination allows the app to ask about unsaved work. Never force quit.
            for _ in 0..<80 {
                let active = await MainActor.run { targets.contains { NSRunningApplication(processIdentifier: $0)?.isTerminated == false } }
                if !active { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let running: [String: String] = await MainActor.run {
            Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }, uniquingKeysWith: { a, _ in a })
        }
        var failed: [String] = []; var skipped: [String] = []; var remaining: [String] = []
        var count = 0
        var toolStates: [String: Bool] = [:]
        for entry in entries {
            guard entry.isComplete, !entry.isPartial, let rule = CleanupCatalog.rule(for: entry.url, in: rules) else { failed.append(entry.url.path + "：不在清理边界内或统计不完整"); continue }
            let live = running.contains { id, name in matchesRunningApp(entry, rule: rule, id: id, name: name) }
            if live {
                skipped.append(entry.url.path + "：相关应用仍在运行或未完成退出，已跳过")
                continue
            }
            if let pattern = CleanupCatalog.toolProcessPattern(rule.root) {
                let active: Bool
                if let cached = toolStates[pattern] { active = cached }
                else {
                    let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); process.arguments = ["-x", pattern]
                    process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                    do { try process.run(); process.waitUntilExit(); active = process.terminationStatus != 1 }
                    catch { active = true }
                    toolStates[pattern] = active
                }
                if active { skipped.append(entry.url.path + "：相关开发工具可能正在运行，请退出后重试"); continue }
            }
            do {
                if rule.sensitive { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil) }
                else { try FileManager.default.removeItem(at: entry.url) }
                count += 1
                var info = stat()
                if entry.url.path.withCString({ lstat($0, &info) }) == 0 {
                    remaining.append(entry.url.path + "：仍存在或已重新生成，约 " + formattedBytes(measure(entry.url).bytes))
                } else if errno != ENOENT { failed.append(entry.url.path + "：无法确认删除后的状态") }
            } catch { failed.append(entry.url.path + "：" + error.localizedDescription) }
        }
        var report = "已处理 \(count) 项；运行中跳过 \(skipped.count) 项；失败 \(failed.count) 项。"
        if !remaining.isEmpty { report += "\n\n仍存在 / 已重新生成：\n" + remaining.joined(separator: "\n") }
        if !skipped.isEmpty { report += "\n\n运行中跳过：\n" + skipped.joined(separator: "\n") }
        if !failed.isEmpty { report += "\n\n失败：\n" + failed.joined(separator: "\n") }
        return report + "\n\nSafari 以外的系统应用、后台服务和命令行任务不会自动退出；缓存可能由后台进程重新生成；移入废纸篓的项目在清空废纸篓前仍占用磁盘空间。"
    }
    static func trashAnalyzed(_ entries: [DiskEntry]) -> String {
        var count = 0
        var failures: [String] = []
        for entry in entries {
            guard ScanSelection.canSelect(entry, mode: .analyze) else { failures.append(entry.url.path + "：已跳过受保护或不完整项目"); continue }
            do { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil); count += 1 }
            catch { failures.append(entry.url.path + "：" + error.localizedDescription) }
        }
        return "已移入废纸篓 \(count) 项。" + (failures.isEmpty ? "" : "\n未完成：\n" + failures.joined(separator: "\n"))
    }
    static func canTrashAnalyzed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = home.path + "/"
        guard path.hasPrefix(base), url.resolvingSymlinksInPath().path == path else { return false }
        let relative = String(path.dropFirst(base.count))
        let first = relative.split(separator: "/").first.map(String.init) ?? ""
        return !first.isEmpty && !first.hasPrefix(".") && first != "Library"
            && !["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"].contains(relative)
    }

}


nonisolated func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
