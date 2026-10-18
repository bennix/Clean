import Foundation
import AppKit
import CryptoKit

// Independently implemented detection. Candidates remain local and require explicit review.
nonisolated enum SupplementalCleanup {
    enum Kind: Sendable { case installer, artifact, duplicate, residual }
    static let projectRoots = ["Projects", "Developer", "GitHub", "dev"]
    static let wechatPath = "Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files"
    static let minimumAge: TimeInterval = 7 * 24 * 60 * 60

    static func safe(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home.standardizedFileURL.path + "/") && url.resolvingSymlinksInPath().path == path
    }
    static func oldEnough(_ url: URL, now: Date) -> Bool {
        guard let date = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return false }
        return now.timeIntervalSince(date) >= minimumAge
    }
    static func artifact(_ url: URL, home: URL, now: Date) -> Bool {
        guard safe(url, home: home), (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              projectRoots.contains(where: { url.standardizedFileURL.path.hasPrefix(home.appendingPathComponent($0).standardizedFileURL.path + "/") }),
              oldEnough(url, now: now) else { return false }
        let parent = url.deletingLastPathComponent()
        let markers: [String]
        switch url.lastPathComponent {
        case "node_modules", "dist": markers = ["package.json"]
        case "target": markers = ["Cargo.toml", "pom.xml"]
        case ".build": markers = ["Package.swift"]
        default: return false
        }
        return markers.contains { marker in
            let file = parent.appendingPathComponent(marker)
            return safe(file, home: home) && (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }
    static func original(for copy: URL) -> URL? {
        let stem = copy.deletingPathExtension().lastPathComponent
        guard let range = stem.range(of: #"[（(][1-9][0-9]*[）)]$"#, options: .regularExpression) else { return nil }
        let base = String(stem[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let name = base + (copy.pathExtension.isEmpty ? "" : "." + copy.pathExtension)
        return copy.deletingLastPathComponent().appendingPathComponent(name)
    }
    static func digest(_ url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            if Task.isCancelled { throw CancellationError() }
            hash.update(data: data)
        }
        return hash.finalize()
    }
    static func identical(_ copy: URL, _ original: URL, home: URL) -> Bool {
        guard copy != original, safe(copy, home: home), safe(original, home: home) else { return false }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let a = try? copy.resourceValues(forKeys: keys), a.isRegularFile == true,
              let b = try? original.resourceValues(forKeys: keys), b.isRegularFile == true,
              a.fileSize == b.fileSize, let ah = try? digest(copy), let bh = try? digest(original), ah == bh,
              let afterA = try? URL(fileURLWithPath: copy.path).resourceValues(forKeys: keys), let afterB = try? URL(fileURLWithPath: original.path).resourceValues(forKeys: keys),
              afterA.fileSize == a.fileSize, afterA.contentModificationDate == a.contentModificationDate,
              afterB.fileSize == b.fileSize, afterB.contentModificationDate == b.contentModificationDate else { return false }
        return true
    }
    static func valid(_ entry: DiskEntry, home: URL = DiskService.home, now: Date = Date(), verifyContents: Bool = false) -> Bool {
        guard safe(entry.url, home: home) else { return false }
        switch entry.supplementalKind {
        case .installer:
            return ["Downloads", "Desktop"].contains(entry.url.deletingLastPathComponent().lastPathComponent)
                && [home.appendingPathComponent("Downloads"), home.appendingPathComponent("Desktop")].contains(entry.url.deletingLastPathComponent())
                && ["dmg", "pkg", "mpkg", "iso", "xip"].contains(entry.url.pathExtension.lowercased())
                && (try? entry.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
                && oldEnough(entry.url, now: now)
        case .artifact: return artifact(entry.url, home: home, now: now)
        case .duplicate:
            guard entry.url.standardizedFileURL.path.hasPrefix(home.appendingPathComponent(wechatPath).standardizedFileURL.path + "/"),
                  let source = entry.originalURL, original(for: entry.url) == source else { return false }
            return !verifyContents || identical(entry.url, source, home: home)
        case .residual, nil: return false
        }
    }
    static func scan(home: URL = DiskService.home, now: Date = Date()) -> ScanResult {
        let fm = FileManager.default
        var result = ScanResult()
        func add(_ url: URL, kind: Kind, original: URL? = nil) {
            let label: String
            switch kind {
            case .installer: label = L("旧安装包 · 请确认不再需要")
            case .artifact: label = L("工程产物 · 删除后可能需要重新构建")
            case .duplicate: label = L("微信重复附件 · 内容一致")
            case .residual: label = L("疑似应用残留 · 仅提示，请人工核对")
            }
            let size = DiskService.measure(url)
            var entry = DiskEntry(url: url, bytes: size.bytes, category: label, sensitive: true, isPartial: size.skipped > 0)
            entry.supplementalKind = kind; entry.originalURL = original
            result.entries.append(entry); result.issues.append(contentsOf: size.issues); result.skipped += size.skipped
        }
        func children(_ root: URL) -> [URL] {
            guard safe(root, home: home), !Task.isCancelled else { return [] }
            do { return try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).map(\.standardizedFileURL) }
            catch {
                let issue = ScanIssue.from(error, at: root)
                if issue.kind != .missing { result.issues.append(issue); result.skipped += 1 }
                return []
            }
        }
        for folder in ["Downloads", "Desktop"] {
            for url in children(home.appendingPathComponent(folder)) {
                var candidate = DiskEntry(url: url, bytes: 0, category: "", sensitive: true)
                candidate.supplementalKind = .installer
                if valid(candidate, home: home, now: now) { add(url, kind: .installer) }
            }
        }
        func walk(_ root: URL, depth: Int, visit: (URL) -> Bool) {
            guard depth < 8, !Task.isCancelled else { return }
            for url in children(root) {
                guard !Task.isCancelled, safe(url, home: home) else { continue }
                if visit(url) { continue }
                guard !url.lastPathComponent.hasPrefix("."), url.pathExtension != "app",
                      (try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]).isDirectory) == true,
                      (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) != true else { continue }
                walk(url, depth: depth + 1, visit: visit)
            }
        }
        for root in projectRoots {
            walk(home.appendingPathComponent(root), depth: 0) { url in
                guard ["node_modules", "target", ".build", "dist"].contains(url.lastPathComponent) else { return false }
                if artifact(url, home: home, now: now) { add(url, kind: .artifact) }
                return true
            }
        }
        walk(home.appendingPathComponent(wechatPath), depth: 0) { url in
            if let source = original(for: url), identical(url, source, home: home) { add(url, kind: .duplicate, original: source) }
            return false
        }
        for url in children(home.appendingPathComponent("Library/Application Support")) {
            guard !Task.isCancelled, safe(url, home: home), oldEnough(url, now: now),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let id = url.lastPathComponent
            guard id.split(separator: ".").count >= 3, UninstallService.validIdentifier(id),
                  !["com.apple", "com.1password", "com.agilebits", "com.docker"].contains(where: { id == $0 || id.hasPrefix($0 + ".") }),
                  NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil else { continue }
            add(url, kind: .residual)
        }
        return result
    }
}
