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
    var supplementalKind: SupplementalCleanup.Kind?
    var originalURL: URL?
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
        // Inspect open paths once, rather than treating every Node/Python process as a cache user.
        let toolUsage = entries.contains { entry in
            if entry.supplementalKind != nil { return true }
            guard let rule = CleanupCatalog.rule(for: entry.url, in: rules) else { return false }
            return CleanupCatalog.requiresToolUsageCheck(rule.root)
        } ? openToolPaths() : nil
        for entry in entries {
            if entry.supplementalKind != nil {
                guard entry.isComplete, !entry.isPartial, SupplementalCleanup.valid(entry, verifyContents: true) else {
                    failed.append(entry.url.path + L("：候选项目已变化或无法证明可清理，请重新扫描")); continue
                }
                guard let usage = toolUsage else { skipped.append(entry.url.path + L("：无法检查缓存占用，请稍后重试")); continue }
                let blockers = blockingProcesses(for: entry.url, usage: usage)
                if !blockers.isEmpty {
                    skipped.append(entry.url.path + L("：缓存正被以下进程使用，请退出后重试：{0}", blockers.joined(separator: ", "))); continue
                }
                if entry.supplementalKind == .duplicate && running.keys.contains(where: { $0.hasPrefix("com.tencent.xinWeChat") }) {
                    skipped.append(entry.url.path + L("：相关应用仍在运行或未完成退出，已跳过")); continue
                }
                do { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil); count += 1 }
                catch { failed.append(entry.url.path + "：" + error.localizedDescription) }
                continue
            }
            guard entry.isComplete, !entry.isPartial, let rule = CleanupCatalog.rule(for: entry.url, in: rules) else { failed.append(entry.url.path + L("：不在清理边界内或统计不完整")); continue }
            let live = running.contains { id, name in matchesRunningApp(entry, rule: rule, id: id, name: name) }
            if live {
                skipped.append(entry.url.path + L("：相关应用仍在运行或未完成退出，已跳过"))
                continue
            }
            if CleanupCatalog.requiresToolUsageCheck(rule.root) {
                guard let toolUsage else {
                    skipped.append(entry.url.path + L("：无法检查缓存占用，请稍后重试")); continue
                }
                let blockers = blockingProcesses(for: entry.url, usage: toolUsage)
                if !blockers.isEmpty {
                    skipped.append(entry.url.path + L("：缓存正被以下进程使用，请退出后重试：{0}", blockers.joined(separator: ", ")))
                    continue
                }
            }
            do {
                if rule.sensitive { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil) }
                else { try FileManager.default.removeItem(at: entry.url) }
                count += 1
                var info = stat()
                if entry.url.path.withCString({ lstat($0, &info) }) == 0 {
                    remaining.append(entry.url.path + L("：仍存在或已重新生成，约 ") + formattedBytes(measure(entry.url).bytes))
                } else if errno != ENOENT { failed.append(entry.url.path + L("：无法确认删除后的状态")) }
            } catch { failed.append(entry.url.path + "：" + error.localizedDescription) }
        }
        var report = L("已处理 {0} 项；运行中跳过 {1} 项；失败 {2} 项。", String(describing: count), String(describing: skipped.count), String(describing: failed.count))
        if !remaining.isEmpty { report += L("\n\n仍存在 / 已重新生成：\n") + remaining.joined(separator: "\n") }
        if !skipped.isEmpty { report += L("\n\n运行中跳过：\n") + skipped.joined(separator: "\n") }
        if !failed.isEmpty { report += L("\n\n失败：\n") + failed.joined(separator: "\n") }
        return report + L("\n\nSafari 以外的系统应用、后台服务和命令行任务不会自动退出；缓存可能由后台进程重新生成；移入废纸篓的项目在清空废纸篓前仍占用磁盘空间。")
    }
    struct OpenToolPath {
        let process: String
        let path: String
    }
    static func parseOpenToolPaths(_ output: String) -> [OpenToolPath] {
        var pid = ""; var name = ""; var result: [OpenToolPath] = []
        for line in output.split(separator: "\n") {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p": pid = value; name = ""
            case "c": name = value
            case "n":
                if value.hasPrefix("/"), !pid.isEmpty {
                    result.append(OpenToolPath(process: "\(name) (PID \(pid))", path: value))
                }
            default: break
            }
        }
        return result
    }
    static func blockingProcesses(for url: URL, usage: [OpenToolPath]) -> [String] {
        let path = url.standardizedFileURL.path
        return Set(usage.filter { $0.path == path || $0.path.hasPrefix(path + "/") }.map(\.process)).sorted()
    }
    static func openToolPaths() -> [OpenToolPath]? {
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-u", String(getuid()), "-Fpcn"]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
            return parseOpenToolPaths(text)
        } catch { return nil }
    }
    static func trashAnalyzed(_ entries: [DiskEntry]) -> String {
        var count = 0
        var failures: [String] = []
        for entry in entries {
            guard ScanSelection.canSelect(entry, mode: .analyze) else { failures.append(entry.url.path + L("：已跳过受保护或不完整项目")); continue }
            do { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil); count += 1 }
            catch { failures.append(entry.url.path + "：" + error.localizedDescription) }
        }
        return L("已移入废纸篓 {0} 项。", String(describing: count)) + (failures.isEmpty ? "" : L("\n未完成：\n") + failures.joined(separator: "\n"))
    }
    static func canTrashAnalyzed(_ url: URL) -> Bool {
        analyzedProtectionReason(url) == nil
    }
    static func analyzedProtectionReason(_ url: URL, home: URL = home) -> String? {
        let path = url.standardizedFileURL.path
        let base = home.standardizedFileURL.path + "/"
        guard path.hasPrefix(base) else { return L("受保护：仅支持处理当前用户目录内的项目") }
        guard url.resolvingSymlinksInPath().path == path else { return L("受保护：符号链接或路径经过符号链接") }
        let relative = String(path.dropFirst(base.count))
        let first = relative.split(separator: "/").first.map(String.init) ?? ""
        let dataRoots = [".colima", ".cache", ".npm", ".bun/install/cache", ".yarn/berry/cache",
                         ".ollama/models", ".docker/desktop/vms", ".cargo/registry", ".cargo/git",
                         ".gradle/caches", ".gradle/wrapper/dists"]
        if dataRoots.contains(where: { relative.hasPrefix($0 + "/") }) { return nil }
        if first == "Library" {
            if CleanupCatalog.baseRules(home: home).contains(where: { path.hasPrefix($0.root.path + "/") }) { return nil }
            // Also recognize browser and sandbox cache descendants without opening their parent data directories.
            var candidate = url.standardizedFileURL
            while candidate.path.hasPrefix(base + "Library/") {
                if CleanupCatalog.rule(for: candidate, home: home) != nil { return nil }
                candidate.deleteLastPathComponent()
            }
            return L("受保护：Library 仅开放已识别的缓存、日志、构建文件和备份的子项，请进入相应目录")
        }
        if first.hasPrefix(".") { return L("受保护：仅开放已识别的数据目录子项，密钥、配置及其他隐藏项目保留") }
        if ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"].contains(relative) {
            return L("受保护：保留常用文件夹本身，请进入后选择子项")
        }
        return nil
    }

}


nonisolated func formattedBytes(_ bytes: Int64) -> String { bytes.formatted(.byteCount(style: .file).locale(AppLanguage.locale)) }
