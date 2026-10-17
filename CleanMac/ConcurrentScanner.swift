import Foundation

nonisolated struct ScanRoot: Sendable {
    let url: URL
    let category: String
    var sensitive = false
    var applicationsOnly = false
}

nonisolated struct ScanProgress: Sendable {
    var result: ScanResult
    var completed: Int
    var total: Int
}

extension DiskService {
    nonisolated static var cleanupRoots: [ScanRoot] {
        [("Library/Caches", "应用缓存", false), ("Library/Logs", "用户日志", false), ("Library/Developer/Xcode/DerivedData", "构建缓存", false), ("Library/Developer/Xcode/Archives", "Xcode 归档", true), ("Library/Developer/CoreSimulator/Caches", "模拟器缓存", false), ("Library/Developer/Xcode/iOS DeviceSupport", "设备支持", true), ("Library/Application Support/MobileSync/Backup", "设备备份", true)].map {
            ScanRoot(url: home.appendingPathComponent($0.0), category: $0.1, sensitive: $0.2)
        }
    }
    nonisolated static var applicationRoots: [ScanRoot] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].map {
            ScanRoot(url: $0, category: "应用", sensitive: true, applicationsOnly: true)
        }
    }
    /// Run from a detached task. At most four filesystem traversals are in flight.
    nonisolated static func scanConcurrently(_ roots: [ScanRoot], concurrency: Int = 4,
                                 onProgress: @Sendable (ScanProgress) async -> Void) async -> ScanResult {
        var seeds: [DiskEntry] = []
        var skipped = 0
        var issues: [ScanIssue] = []
        for root in roots {
            guard !Task.isCancelled else { return ScanResult() }
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: root.url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles])
                for url in urls {
                    guard !Task.isCancelled else { return ScanResult() }
                    if root.applicationsOnly && url.pathExtension.lowercased() != "app" { continue }
                    do {
                        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                        if values.isSymbolicLink == true {
                            skipped += 1
                            issues.append(ScanIssue(url: url, kind: .symbolicLink, detail: "不跟随链接，避免重复计数和跨越扫描边界。"))
                            continue
                        }
                    } catch { skipped += 1; issues.append(.from(error, at: url)); continue }
                    seeds.append(DiskEntry(url: url, bytes: 0, category: root.category, sensitive: root.sensitive, isComplete: false))
                }
            } catch { skipped += 1; issues.append(.from(error, at: root.url)) }
        }
        let pending = seeds.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var result = ScanResult(entries: pending, skipped: skipped, issues: issues)
        await onProgress(ScanProgress(result: result, completed: 0, total: pending.count))
        guard !Task.isCancelled else { return result }
        var completed = 0
        var lastUpdate = ContinuousClock.now
        await withTaskGroup(of: (Int, Int64, Int, [ScanIssue]).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let entry = pending[index]
                group.addTask {
                    let measurement = measure(entry.url)
                    return (index, measurement.bytes, measurement.skipped, measurement.issues)
                }
            }
            for _ in 0..<min(max(1, concurrency), pending.count) { enqueue(next); next += 1 }
            while let (index, bytes, errors, errorsDetail) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                let entry = pending[index]
                result.entries[index] = DiskEntry(url: entry.url, bytes: bytes, category: entry.category, sensitive: entry.sensitive, isPartial: errors > 0)
                result.skipped += errors
                result.issues.append(contentsOf: errorsDetail.prefix(max(0, 500 - result.issues.count)))
                completed += 1
                if next < pending.count { enqueue(next); next += 1 }
                if lastUpdate.duration(to: .now) >= .milliseconds(150) || completed == pending.count {
                    var snapshot = result
                    snapshot.entries.sort(by: scanOrder)
                    await onProgress(ScanProgress(result: snapshot, completed: completed, total: pending.count))
                    lastUpdate = .now
                }
            }
        }
        result.entries.sort(by: scanOrder)
        return result
    }
    private nonisolated static func scanOrder(_ a: DiskEntry, _ b: DiskEntry) -> Bool {
        if a.sensitive != b.sensitive { return !a.sensitive }
        if a.bytes != b.bytes { return a.bytes > b.bytes }
        return a.id < b.id
    }
    nonisolated static func measure(_ url: URL) -> (bytes: Int64, skipped: Int, issues: [ScanIssue]) {
        guard !Task.isCancelled else { return (0, 0, []) }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey]
        do {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { return (0, 1, [ScanIssue(url: url, kind: .symbolicLink, detail: "不跟随符号链接。")]) }
            if values.isRegularFile == true { return (Int64(values.fileAllocatedSize ?? 0), 0, []) }
        } catch { return (0, 1, [.from(error, at: url)]) }
        var skipped = 0
        var issues: [ScanIssue] = []
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { path, error in
            skipped += 1
            if issues.count < 100 { issues.append(.from(error, at: path)) }
            return true
        }) else { return (0, 1, [ScanIssue(url: url, kind: .unreadable, detail: "无法遍历目录。")]) }
        var total: Int64 = 0
        for case let file as URL in iterator {
            if Task.isCancelled { break }
            do {
                let value = try file.resourceValues(forKeys: keys)
                if value.isSymbolicLink == true { iterator.skipDescendants(); continue }
                if value.isRegularFile == true { total += Int64(value.fileAllocatedSize ?? 0) }
            } catch {
                skipped += 1
                if issues.count < 100 { issues.append(.from(error, at: file)) }
            }
        }
        return (total, skipped, issues)
    }
}
