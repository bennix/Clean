import Foundation

nonisolated struct CleanupRule: Sendable {
    let root: URL
    let category: String
    var sensitive = false
    var ownerIDs: [String] = []
    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        return path.hasPrefix(base + "/") && !path.dropFirst(base.count + 1).contains("/")
            && url.resolvingSymlinksInPath().path == path
    }
    var scanRoot: ScanRoot { ScanRoot(url: root, category: category, sensitive: sensitive, optional: true) }
}

nonisolated struct CleanupDiscovery: Sendable {
    var rules: [CleanupRule]
    var issues: [ScanIssue]
}

nonisolated enum CleanupCatalog {
    // Independent Swift rules for documented cache locations. Never delete a cache root itself.
    static let browsers: [(String, [String])] = [
            ("Google/Chrome", ["com.google.Chrome"]), ("Google/Chrome Beta", ["com.google.Chrome.beta"]),
            ("Microsoft Edge", ["com.microsoft.edgemac"]), ("BraveSoftware/Brave-Browser", ["com.brave.Browser"]),
            ("Chromium", ["org.chromium.Chromium"]), ("Vivaldi", ["com.vivaldi.Vivaldi"]),
            ("Arc/User Data", ["company.thebrowser.Browser"])
        ]
    static func baseRules(home: URL) -> [CleanupRule] {
        var rules: [CleanupRule] = []
        func add(_ path: String, _ category: String, sensitive: Bool = false, owners: [String] = []) {
            rules.append(CleanupRule(root: home.appendingPathComponent(path), category: category, sensitive: sensitive, ownerIDs: owners))
        }
        for (path, label, sensitive) in [
            ("Library/Caches", L("应用缓存"), false), ("Library/Logs", L("用户日志"), false),
            ("Library/Developer/Xcode/DerivedData", L("Xcode 构建缓存"), false),
            ("Library/Developer/Xcode/Archives", L("Xcode 归档 · 个人数据"), true),
            ("Library/Developer/CoreSimulator/Caches", L("模拟器缓存"), false),
            ("Library/Developer/Xcode/iOS DeviceSupport", L("设备支持"), true),
            ("Library/Developer/Xcode/DocumentationCache", L("Xcode 文档缓存"), false),
            ("Library/Application Support/MobileSync/Backup", L("设备备份 · 个人数据"), true),
            (".npm/_cacache", L("npm 下载缓存"), false), (".npm/_logs", L("npm 日志"), false),
            (".npm/_prebuilds", L("npm 构建下载缓存"), false), (".bun/install/cache", L("Bun 下载缓存"), false),
            (".yarn/berry/cache", L("Yarn 下载缓存"), false), (".cache/yarn", L("Yarn 缓存"), false),
            (".cache/pip", L("pip 下载缓存"), false), (".cache/uv", L("uv 下载缓存"), false),
            (".cache/pypoetry", L("Poetry 缓存"), false), (".cache/pre-commit", L("pre-commit 环境缓存"), false),
            (".cache/ruff", L("Ruff 缓存"), false), (".cache/mypy", L("mypy 缓存"), false),
            (".cache/node/corepack", L("Corepack 下载缓存"), false),
            (".gradle/caches", L("Gradle 缓存"), false), (".cargo/registry/cache", L("Cargo 下载缓存"), false)
        ] { add(path, label, sensitive: sensitive) }
        let electronApps: [(String, [String])] = [
            ("Code", ["com.microsoft.VSCode"]), ("Code - Insiders", ["com.microsoft.VSCodeInsiders"]),
            ("Cursor", ["com.todesktop.230313mzl4w4u92"]), ("Windsurf", ["com.exafunction.windsurf"]),
            ("VSCodium", ["com.vscodium"]), ("Claude", ["com.anthropic.claudefordesktop"]),
            ("ChatGPT", ["com.openai.chat"]), ("Slack", ["com.tinyspeck.slackmacgap"]),
            ("discord", ["com.hnc.Discord"]), ("Notion", ["notion.id"]), ("obsidian", ["md.obsidian"])
        ]
        for (app, owners) in electronApps {
            for cache in ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "CachedData", "CachedExtensionVSIXs"] {
                add("Library/Application Support/\(app)/\(cache)", "\(app) · \(cache)", owners: owners)
            }
        }
        return rules
    }
    static var defaultBaseRules: [CleanupRule] { baseRules(home: DiskService.home) }
    static var defaultRulesByPath: [String: CleanupRule] { Dictionary(uniqueKeysWithValues: defaultBaseRules.map { ($0.root.standardizedFileURL.path, $0) }) }
    static func discover(home: URL = DiskService.home) -> CleanupDiscovery {
        var rules = home == DiskService.home ? defaultBaseRules : baseRules(home: home)
        var issues: [ScanIssue] = []
        func add(_ path: String, _ category: String, sensitive: Bool = false, owners: [String] = []) {
            rules.append(CleanupRule(root: home.appendingPathComponent(path), category: category, sensitive: sensitive, ownerIDs: owners))
        }
        func children(_ path: String) -> [URL] {
            let url = home.appendingPathComponent(path)
            do { return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) }
            catch {
                let issue = ScanIssue.from(error, at: url)
                if issue.kind != .missing { issues.append(issue) }
                return []
            }
        }
        for container in children("Library/Containers") {
            guard (try? container.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
            add("Library/Containers/\(container.lastPathComponent)/Data/Library/Caches", L("沙盒应用缓存 · {0}", String(describing: container.lastPathComponent)), owners: [container.lastPathComponent])
        }
        // Group data itself, tmp, Documents and databases are never added.
        for container in children("Library/Group Containers") {
            guard (try? container.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
            add("Library/Group Containers/\(container.lastPathComponent)/Library/Caches", L("共享容器缓存 · {0}", String(describing: container.lastPathComponent)), sensitive: true)
            add("Library/Group Containers/\(container.lastPathComponent)/Data/Library/Caches", L("共享容器缓存 · {0}", String(describing: container.lastPathComponent)), sensitive: true)
        }
        for (browser, owners) in browsers {
            for profile in children("Library/Application Support/" + browser) {
                let name = profile.lastPathComponent
                guard name == "Default" || (name.hasPrefix("Profile ") && Int(name.dropFirst(8)) != nil),
                      (try? profile.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
                for cache in ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"] {
                    add("Library/Application Support/\(browser)/\(name)/\(cache)", L("浏览器缓存 · {0} / {1}", String(describing: browser), String(describing: name)), owners: owners)
                }
            }
        }
        return CleanupDiscovery(rules: rules, issues: issues)
    }
    static func rule(for url: URL, home: URL = DiskService.home) -> CleanupRule? {
        let root = url.deletingLastPathComponent().standardizedFileURL
        if home == DiskService.home {
            if let rule = defaultRulesByPath[root.path], rule.contains(url) { return rule }
        } else if let rule = rule(for: url, in: baseRules(home: home)) { return rule }
        let prefix = home.standardizedFileURL.path + "/"
        guard root.path.hasPrefix(prefix) else { return nil }
        let relative = String(root.path.dropFirst(prefix.count))
        let components = relative.split(separator: "/").map(String.init)
        var result: CleanupRule?
        if components.count == 6, Array(components.prefix(2)) == ["Library", "Containers"], Array(components.suffix(3)) == ["Data", "Library", "Caches"] {
            result = CleanupRule(root: root, category: L("沙盒应用缓存"), ownerIDs: [components[2]])
        } else if components.count >= 5, Array(components.prefix(2)) == ["Library", "Group Containers"],
                  Array(components.dropFirst(3)) == ["Library", "Caches"] || Array(components.dropFirst(3)) == ["Data", "Library", "Caches"] {
            result = CleanupRule(root: root, category: L("共享容器缓存"), sensitive: true)
        } else {
            for (browser, owners) in browsers {
                let base = "Library/Application Support/" + browser + "/"
                guard relative.hasPrefix(base) else { continue }
                let parts = relative.dropFirst(base.count).split(separator: "/").map(String.init)
                guard parts.count == 2,
                      parts[0] == "Default" || (parts[0].hasPrefix("Profile ") && Int(parts[0].dropFirst(8)) != nil),
                      ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"].contains(parts[1]) else { continue }
                result = CleanupRule(root: root, category: L("浏览器缓存"), ownerIDs: owners)
                break
            }
        }
        return result?.contains(url) == true ? result : nil
    }
    static func toolProcessPattern(_ root: URL) -> String? {
        let path = root.path
        if path.contains("/.npm/") || path.contains("/.bun/") || path.contains("/.yarn/") || path.contains("/.cache/yarn") || path.contains("/.cache/node/corepack") { return "node|npm|pnpm|yarn|bun|corepack" }
        if path.contains("/.gradle/") { return "java|gradle|gradlew" }
        if path.contains("/.cargo/") { return "cargo|rustc|rustup" }
        if path.contains("/.cache/") { return "python[0-9.]*|pip[0-9.]*|uv|ruff|mypy|poetry|pre-commit" }
        return nil
    }
    static func rule(for url: URL, in rules: [CleanupRule]) -> CleanupRule? { rules.first { $0.contains(url) } }
}
