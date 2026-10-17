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
    static let cacheRoots = ["Library/Caches", "Library/Logs", "Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator/Caches", "Library/Developer/Xcode/iOS DeviceSupport", "Library/Caches/Homebrew", "Library/Caches/Google/Chrome", "Library/Caches/com.apple.Safari", "Library/Caches/org.swift.swiftpm", "Library/Application Support/MobileSync/Backup"]
    static func size(_ url: URL) -> Int64 {
        measure(url).bytes
    }

    static func children(_ root: URL, category: String, sensitive: Bool = false) -> ScanResult {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
            return ScanResult(entries: urls.filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }.map { DiskEntry(url: $0, bytes: size($0), category: category, sensitive: sensitive) }.sorted { $0.bytes > $1.bytes })
        } catch { return ScanResult(skipped: 1) }
    }
    static func scan() -> ScanResult {
        var result = ScanResult()
        for root in cleanupRoots {
            if Task.isCancelled { break }
            let sub = children(root.url, category: root.category, sensitive: root.sensitive)
            result.entries += sub.entries
            result.skipped += sub.skipped
        }
        result.entries.sort { $0.sensitive == $1.sensitive ? $0.bytes > $1.bytes : !$0.sensitive }
        return result
    }

    static func canDelete(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard url.resolvingSymlinksInPath().path == path else { return false }
        return cacheRoots.contains { root in
            let base = home.appendingPathComponent(root).path
            return path.hasPrefix(base + "/") && !path.dropFirst(base.count + 1).contains("/")
        }
    }
    static func remove(_ entries: [DiskEntry]) -> String {
        var failed: [String] = []
        var count = 0
        for entry in entries {
            guard canDelete(entry.url) else { failed.append(entry.name); continue }
            do {
                if entry.sensitive { _ = try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil) }
                else { try FileManager.default.removeItem(at: entry.url) }
                count += 1
            } catch { failed.append(entry.name + ": " + error.localizedDescription) }
        }
        return "已处理 \(count) 项。" + (failed.isEmpty ? "" : "跳过或失败：" + failed.joined(separator: "；"))
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
    static func applications() -> [DiskEntry] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].flatMap { children($0, category: "应用", sensitive: true).entries }.filter { $0.url.pathExtension == "app" }
    }
}


func formattedBytes(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
