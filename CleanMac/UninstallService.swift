import Foundation
import AppKit
import Security

nonisolated struct UninstallFile: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let category: String
    let note: String
    var bytes: Int64 = 0
    var containsData = false
    var allowed = true
    var isComplete = false
    var needsDiskAccess = false
    var issue: String?
}

nonisolated struct UninstallPlan: Sendable {
    let apps: [DiskEntry]
    var files: [UninstallFile]
    var completed = 0
    var dockApps: [String] = []
    var warnings: [String] = []
}

nonisolated enum UninstallService {
    static func validApp(_ url: URL) -> Bool {
        ["/Applications", DiskService.home.appendingPathComponent("Applications").path].contains(url.deletingLastPathComponent().path)
        && url.pathExtension == "app" && url.resolvingSymlinksInPath().path == url.standardizedFileURL.path
        && url.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL
    }
    static func validIdentifier(_ id: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return !id.isEmpty && id.utf8.count <= 255 && id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
    static func groups(_ url: URL) -> [String] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
    static func installedApps() -> [URL] {
        DiskService.applicationRoots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0.url, includingPropertiesForKeys: nil)) ?? [] }.filter { $0.pathExtension == "app" }
    }
    static func discover(_ apps: [DiskEntry]) -> UninstallPlan {
        let fm = FileManager.default
        let home = DiskService.home
        var files: [UninstallFile] = []
        var warnings: [String] = []
        let selectedPaths = Set(apps.map(\.id))
        let otherApps = installedApps().filter { !selectedPaths.contains($0.path) }
        var otherGroups: [URL: [String]] = [:]
        func add(_ url: URL, _ category: String, _ note: String, data: Bool = false, allowed: Bool = true) {
            // lstat detects permission errors and symlinks without following a link outside the boundary.
            var info = stat()
            let status = url.path.withCString { lstat($0, &info) }
            if status != 0 && errno == ENOENT { return }
            let symlink = status == 0 && (info.st_mode & S_IFMT) == S_IFLNK
            files.append(UninstallFile(url: url, category: category, note: note, containsData: data, allowed: allowed && !symlink, needsDiskAccess: status != 0 && (errno == EACCES || errno == EPERM), issue: symlink ? L("符号链接，已阻止") : status != 0 ? L("无法检查此路径，可能需要完全磁盘访问权限") : nil))
        }
        for app in apps where validApp(app.url) {
            if Task.isCancelled { break }
            guard let bundle = Bundle(url: app.url), let id = bundle.bundleIdentifier, validIdentifier(id) else {
                warnings.append(app.url.path + L("：无法读取有效应用标识符，关联扫描不完整。请检查权限或使用厂商卸载器。"))
                continue
            }
            let name = app.url.deletingPathExtension().lastPathComponent
            let reason = L("匹配应用标识符 ") + id
            for (path, category, data) in [
                ("Library/Preferences/\(id).plist", L("偏好设置"), false),
                ("Library/Caches/\(id)", L("缓存"), false),
                ("Library/Application Support/\(id)", L("支持文件"), true),
                ("Library/Saved Application State/\(id).savedState", L("窗口保存状态"), false),
                ("Library/Containers/\(id)", L("应用容器"), true),
                ("Library/HTTPStorages/\(id)", L("网络存储"), true),
                ("Library/HTTPStorages/\(id).binarycookies", "Cookie", true),
                ("Library/WebKit/\(id)", L("WebKit 数据"), true),
                ("Library/Logs/\(id)", L("日志"), false)
            ] { add(home.appendingPathComponent(path), category, reason, data: data) }
            for (path, category, data) in [
                ("/Library/Application Support/" + id, L("全局支持文件"), true),
                ("/Library/Preferences/" + id + ".plist", L("全局偏好设置"), false),
                ("/Library/Caches/" + id, L("全局缓存"), false),
                ("/Library/Logs/" + id, L("全局日志"), false)
            ] { add(URL(fileURLWithPath: path), category, L("匹配应用标识符；移动时可能需要系统授权。"), data: data) }
            if let helpers = bundle.infoDictionary?["SMPrivilegedExecutables"] as? [String: Any] {
                for helper in helpers.keys where validIdentifier(helper) && !helper.hasPrefix("com.apple.") {
                    add(URL(fileURLWithPath: "/Library/PrivilegedHelperTools/" + helper), L("特权辅助工具"), L("涉及系统服务，请用厂商卸载器注销。"), allowed: false)
                }
            }
            if name.count > 2, !name.contains("/"), !name.contains(".."), !name.contains("\\") {
                add(home.appendingPathComponent("Library/Application Support/" + name), L("同名支持文件"), L("按名称匹配，可能包含个人数据或同名软件数据，请核对。"), data: true)
                add(home.appendingPathComponent("Library/Logs/" + name), L("同名日志"), L("按应用名称匹配，请核对。"), data: true)
            }
            if let byHost = try? fm.contentsOfDirectory(at: home.appendingPathComponent("Library/Preferences/ByHost"), includingPropertiesForKeys: nil) {
                for url in byHost where url.lastPathComponent.hasPrefix(id + ".") && url.pathExtension == "plist" { add(url, L("设备偏好设置"), reason) }
            }
            for group in groups(app.url) where validIdentifier(group) {
                var owners: [String] = []
                for other in otherApps {
                    if Task.isCancelled { break }
                    let values = otherGroups[other] ?? groups(other)
                    otherGroups[other] = values
                    if values.contains(group) { owners.append(other.deletingPathExtension().lastPathComponent) }
                }
                add(home.appendingPathComponent("Library/Group Containers/" + group), L("共享容器"), owners.isEmpty ? L("签名声明的共享容器；仍可能被扩展或其他应用使用，请确认。") : L("仍被以下应用使用，已保留：") + owners.joined(separator: "、"), data: true, allowed: owners.isEmpty)
            }
            for (directory, system) in [(home.appendingPathComponent("Library/LaunchAgents"), false), (URL(fileURLWithPath: "/Library/LaunchAgents"), true), (URL(fileURLWithPath: "/Library/LaunchDaemons"), true)] {
                guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
                for url in urls where url.pathExtension == "plist" {
                    guard let data = try? Data(contentsOf: url), let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                    let label = value["Label"] as? String ?? ""
                    let executable = value["Program"] as? String ?? (value["ProgramArguments"] as? [String])?.first ?? ""
                    let pathMatch = executable.hasPrefix(app.url.path + "/")
                    let labelMatch = label == id || label.hasPrefix(id + ".")
                    guard pathMatch || (!system && labelMatch) else { continue }
                    add(url, system ? L("系统启动服务") : L("用户启动项"), system ? L("系统级服务，请使用厂商卸载器注销，避免残留后台进程。") : L("卸载前会先尝试注销此用户启动项。"), allowed: !system)
                }
            }
        }
        let unique = Dictionary(files.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return UninstallPlan(apps: apps, files: unique.values.sorted { $0.id < $1.id }, dockApps: DockCleanup.matchingPaths(Set(apps.map(\.id))), warnings: warnings)
    }
    static func prepare(_ apps: [DiskEntry], onProgress: @Sendable (UninstallPlan) async -> Void) async -> UninstallPlan {
        var plan = discover(apps)
        await onProgress(plan)
        await withTaskGroup(of: (Int, Int64, String?, Bool).self) { group in
            var next = 0
            func enqueue(_ index: Int) {
                let url = plan.files[index].url
                group.addTask {
                    let value = DiskService.measure(url)
                    return (index, value.bytes, value.issues.first?.detail, value.issues.contains { $0.kind == .permission })
                }
            }
            for _ in 0..<min(4, plan.files.count) { enqueue(next); next += 1 }
            var last = ContinuousClock.now
            while let (index, bytes, issue, permission) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                plan.files[index].bytes = bytes; plan.files[index].isComplete = true
                plan.files[index].issue = plan.files[index].issue ?? issue
                plan.files[index].needsDiskAccess = plan.files[index].needsDiskAccess || permission
                plan.completed += 1
                if next < plan.files.count { enqueue(next); next += 1 }
                if last.duration(to: .now) >= .milliseconds(150) || plan.completed == plan.files.count { await onProgress(plan); last = .now }
            }
        }
        return plan
    }
    static func unloadAgent(_ url: URL) -> String? {
        guard url.deletingLastPathComponent() == DiskService.home.appendingPathComponent("Library/LaunchAgents"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let label = plist["Label"] as? String else { return nil }
        func run(_ arguments: [String]) -> (Int32, String) {
            let process = Process(); let error = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl"); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = error
            do { try process.run() } catch { return (-1, error.localizedDescription) }
            let message = String(data: error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            process.waitUntilExit(); return (process.terminationStatus, message)
        }
        guard run(["print", "gui/\(getuid())/" + label]).0 == 0 else { return nil }
        let result = run(["bootout", "gui/\(getuid())", url.path])
        return result.0 == 0 ? nil : L("无法注销启动项：") + result.1
    }
    static func execute(_ plan: UninstallPlan, selected: Set<String>, systemAuthorization: Bool, removeDockEntries: Bool,
                        authorize: @Sendable (URL) async -> String?) async -> String {
        guard plan.apps.allSatisfy({ validApp($0.url) }) else { return L("已拒绝：包含受保护、无效或当前正在运行的 Clean 应用路径。") }
        let running = await MainActor.run { NSWorkspace.shared.runningApplications.compactMap(\.bundleURL) }
        guard !plan.apps.contains(where: { running.contains($0.url) }) else { return L("请先退出所选应用，再重试卸载。未删除任何文件。") }
        let verified = Dictionary(discover(plan.apps).files.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var successes: [String] = []; var failures: [String] = []; var removedApps: Set<String> = []
        for file in plan.files where selected.contains(file.id) {
            guard let current = verified[file.id], current.allowed, file.url.resolvingSymlinksInPath().path == file.url.standardizedFileURL.path else { failures.append(file.url.path + L("：关联验证失败或为共享/保护项目")); continue }
            if let error = unloadAgent(file.url) { failures.append(file.url.path + "：" + error); continue }
            if let error = await trash(file.url, systemAuthorization: systemAuthorization, authorize: authorize) { failures.append(file.url.path + "：" + error) } else { successes.append(file.url.path) }
        }
        for app in plan.apps {
            if let error = await trash(app.url, systemAuthorization: systemAuthorization, authorize: authorize) { failures.append(app.url.path + "：" + error) } else { successes.append(app.url.path); removedApps.insert(app.url.path) }
        }
        if removeDockEntries && !removedApps.isEmpty, let error = DockCleanup.remove(removedApps) { failures.append(error) }
        return L("已移入废纸篓 {0} 项。", String(describing: successes.count)) + (failures.isEmpty ? "" : L("\n\n未完成（可复制路径后重试）：\n") + failures.joined(separator: "\n"))
    }
    private static func trash(_ url: URL, systemAuthorization: Bool, authorize: @Sendable (URL) async -> String?) async -> String? {
        do { _ = try FileManager.default.trashItem(at: url, resultingItemURL: nil); return nil }
        catch {
            let issue = ScanIssue.from(error, at: url)
            if issue.kind == .permission && systemAuthorization { return await authorize(url) }
            return error.localizedDescription + (issue.kind == .permission ? L("；请检查完全磁盘访问权限，或开启系统授权重试。") : "")
        }
    }
}

@MainActor
enum FinderAuthorization {
    static func trash(_ url: URL) -> String? {
        let path = url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "tell application \"Finder\" to delete (POSIX file \"" + path + "\")")
        var error: NSDictionary?
        guard script != nil else { return L("无法创建系统授权请求。") }
        _ = script?.executeAndReturnError(&error)
        if let error { return L("Finder 授权未完成：{0}。请检查自动化和完全磁盘访问权限。", String(describing: error)) }
        var status = stat()
        if url.path.withCString({ lstat($0, &status) }) == 0 { return L("系统操作未完成，文件仍存在。") }
        return errno == ENOENT ? nil : L("权限不足，无法核实系统是否完成移动；请在 Finder 中检查。")
    }
}

nonisolated enum DockCleanup {
    static func appPath(_ item: [String: Any]) -> String? {
        guard let tile = item["tile-data"] as? [String: Any], let file = tile["file-data"] as? [String: Any],
              let value = file["_CFURLString"] as? String, let url = URL(string: value), url.isFileURL else { return nil }
        return url.standardizedFileURL.path
    }
    static func matchingPaths(_ paths: Set<String>) -> [String] {
        guard let items = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return [] }
        return items.compactMap(appPath).filter { paths.contains($0) }
    }
    static func remove(_ paths: Set<String>) -> String? {
        guard let items = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return nil }
        let remaining = items.filter { item in appPath(item).map { !paths.contains($0) } ?? true }
        guard remaining.count != items.count else { return nil }
        CFPreferencesSetAppValue("persistent-apps" as CFString, remaining as CFArray, "com.apple.dock" as CFString)
        guard CFPreferencesAppSynchronize("com.apple.dock" as CFString) else { return L("Dock 图标移除失败：无法保存偏好设置。") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); process.arguments = ["Dock"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return L("Dock 偏好已更新，但需要手动重新登录以刷新图标。") }
        return process.terminationStatus == 0 ? nil : L("Dock 偏好已更新，但需要手动重新登录以刷新图标。")
    }
}
