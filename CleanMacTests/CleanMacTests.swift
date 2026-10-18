import Foundation
import Testing
@testable import CleanMac

struct CleanMacTests {
    @Test func deletionBoundary() {
        let home = DiskService.home
        #expect(!DiskService.canDelete(URL(fileURLWithPath: "/System/Library/Caches/test")))
        #expect(!DiskService.canDelete(home.appendingPathComponent("Library/Caches")))
        #expect(!DiskService.canDelete(home.appendingPathComponent("Documents/test")))
        #expect(!DiskService.canDelete(home.appendingPathComponent("Library/Caches-other/test")))
        #expect(!DiskService.canDelete(home.appendingPathComponent("Library/Caches/../Preferences/test")))
        #expect(DiskService.canDelete(home.appendingPathComponent("Library/Caches/cleanmac-boundary-test")))
    }
    @Test func analyzedTrashBoundary() {
        #expect(!DiskService.canTrashAnalyzed(URL(fileURLWithPath: "/System")))
        #expect(!DiskService.canTrashAnalyzed(DiskService.home))
        #expect(!DiskService.canTrashAnalyzed(DiskService.home.appendingPathComponent("Documents")))
        #expect(!DiskService.canTrashAnalyzed(DiskService.home.appendingPathComponent("Library/Preferences/a.plist")))
        #expect(DiskService.canTrashAnalyzed(DiskService.home.appendingPathComponent("Downloads/clean-boundary-test.txt")))
    }
    @Test func symlinkEscapeIsRejected() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let link = root.appendingPathComponent("escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: DiskService.home)
        #expect(!DiskService.canDelete(link.appendingPathComponent("Library/Caches/test")))
    }
    @Test func scanningDoesNotDeleteFiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("sample.txt")
        try Data(repeating: 65, count: 8192).write(to: file)
        let result = DiskService.children(root, category: "测试")
        #expect(result.entries.count == 1)
        #expect(result.entries.first?.bytes ?? 0 >= 8192)
        #expect(fm.fileExists(atPath: file.path))
    }
}

struct MonitoringTests {
    @Test func networkRateHandlesResetAndInvalidTime() {
        #expect(NetworkCounters.rate(current: 5000, previous: 1000, elapsed: 2) == 2000)
        #expect(NetworkCounters.rate(current: 500, previous: 1000, elapsed: 1) == 0)
        #expect(NetworkCounters.rate(current: 5000, previous: 1000, elapsed: 0) == 0)
    }
    @Test func temperatureSamplesRejectSentinelsAndDeduplicate() {
        let values = TemperatureSensors.normalized([
            .init(name: "chip", celsius: 60), .init(name: "chip", celsius: 62),
            .init(name: "battery", celsius: 35), .init(name: "invalid", celsius: .nan),
            .init(name: "zero", celsius: 0), .init(name: "sentinel", celsius: 255)
        ])
        #expect(values == [.init(name: "chip", celsius: 62), .init(name: "battery", celsius: 35)])
    }
}

private actor ProgressRecorder {
    var events: [ScanProgress] = []
    func record(_ progress: ScanProgress) { events.append(progress) }
    func snapshots() -> [ScanProgress] { events }
}

struct ConcurrentScannerTests {
    @Test func concurrentScanMatchesSizesAndReportsPendingThenFinished() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for i in 0..<8 {
            let folder = root.appendingPathComponent("folder-\(i)")
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 8192 * (i + 1)).write(to: folder.appendingPathComponent("data"))
        }
        try fm.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: root)
        let recorder = ProgressRecorder()
        let result = await Task.detached {
            await DiskService.scanConcurrently([ScanRoot(url: root, category: "测试")]) { await recorder.record($0) }
        }.value
        let snapshots = await recorder.snapshots()
        #expect(snapshots.first?.completed == 0)
        #expect(snapshots.first?.result.entries.allSatisfy { !$0.isComplete } == true)
        #expect(snapshots.last?.completed == 8)
        #expect(result.entries.count == 8)
        #expect(result.entries.allSatisfy { $0.isComplete && $0.bytes == DiskService.size($0.url) })
        #expect(result.skipped == 1)
    }
    @Test func applicationScanFiltersNonAppsBeforeTraversal() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("Example.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Unrelated"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let result = await Task.detached {
            await DiskService.scanConcurrently([ScanRoot(url: root, category: "应用", applicationsOnly: true)]) { _ in }
        }.value
        #expect(result.entries.map(\.name) == ["Example.app"])
    }
    @Test func cancellationStopsBeforeTraversingPendingDirectories() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root.appendingPathComponent("pending"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let result = await Task.detached {
            await DiskService.scanConcurrently([ScanRoot(url: root, category: "测试")]) { progress in
                if progress.completed == 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }.value
        #expect(result.entries.count == 1)
        #expect(result.entries.allSatisfy { !$0.isComplete })
    }
}

struct PermissionAndUninstallTests {
    @Test func readErrorsDistinguishMissingFromPermission() {
        let url = URL(fileURLWithPath: "/private/test")
        #expect(ScanIssue.from(NSError(domain: NSPOSIXErrorDomain, code: 2), at: url).kind == .missing)
        #expect(ScanIssue.from(NSError(domain: NSPOSIXErrorDomain, code: 13), at: url).kind == .permission)
        #expect(ScanIssue.from(NSError(domain: NSCocoaErrorDomain, code: 257), at: url).kind == .permission)
    }
    @Test func unknownAndProtectedUninstallTargetsAreRejected() {
        #expect(!UninstallService.validApp(URL(fileURLWithPath: "/System/Applications/Mail.app")))
        #expect(!UninstallService.validApp(URL(fileURLWithPath: "/Users/Shared/Other.app")))
        #expect(!UninstallService.validIdentifier("../../other"))
        #expect(!UninstallService.validIdentifier("."))
        #expect(!UninstallService.validIdentifier("com..example"))
        #expect(!UninstallService.validIdentifier("com.test/other"))
        #expect(UninstallService.validIdentifier("com.example.app"))
    }
    @Test func dockMatchingUsesExactFileURL() {
        #expect(DockCleanup.appPath(["tile-data": ["file-data": ["_CFURLString": "file:///Applications/Example.app/"]]]) == "/Applications/Example.app")
        #expect(DockCleanup.appPath(["tile-data": ["file-data": ["_CFURLString": "https://example.com"]]]) == nil)
    }
    @Test func missingRootReportsItsActualPath() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = await Task.detached {
            await DiskService.scanConcurrently([ScanRoot(url: url, category: "测试")]) { _ in }
        }.value
        #expect(result.entries.isEmpty)
        #expect(result.issues.first?.url == url)
        #expect(result.issues.first?.kind == .missing)
    }
}

struct DiskAccessTests {
    @Test func absenceOfProbeTargetsDoesNotClaimAuthorization() {
        #expect(AccessProbeResult.classify(readable: 0, denied: []).state == .unknown)
    }
    @Test func deniedAccessOverridesSuccessfulProbes() {
        let blocked = URL(fileURLWithPath: "/private/denied")
        let result = AccessProbeResult.classify(readable: 3, denied: [blocked])
        #expect(result.state == .limited)
        #expect(result.denied == [blocked])
    }
    @Test func readableTargetsAreMarkedAsObservedAccess() {
        #expect(AccessProbeResult.classify(readable: 2, denied: []).state == .accessible)
    }
}

struct DiskAccessRecoveryTests {
    @Test func readablePrivacyDatabaseIsNotOverriddenByOtherDeniedPaths() {
        #expect(AccessProbeResult.classify(readable: 1, denied: [URL(fileURLWithPath: "/some/protected/location")], protectedDatabaseReadable: true).state == .accessible)
    }
    @MainActor @Test func recoveryClearsQueuedAuthorizationPrompt() {
        let access = DiskAccessManager()
        access.apply(.classify(readable: 0, denied: [URL(fileURLWithPath: "/protected")]))
        #expect(access.automaticPromptRequested)
        access.apply(.classify(readable: 1, denied: []))
        #expect(access.state == .accessible)
        #expect(!access.automaticPromptRequested)
    }
    @MainActor @Test func fileSpecificDenialDoesNotRevokeObservedAccess() {
        let access = DiskAccessManager()
        access.apply(.classify(readable: 1, denied: []))
        access.reportDenied([URL(fileURLWithPath: "/System/protected")])
        #expect(access.state == .accessible)
        #expect(access.fileDenials.count == 1)
        #expect(!access.automaticPromptRequested)
    }
}

struct ScanSelectionTests {
    @Test func analysisAllowsColimaContentsButProtectsOtherHiddenDirectories() {
        let home = DiskService.home
        let lima = DiskEntry(url: home.appendingPathComponent(".colima/_lima"), bytes: 1, category: "文件", sensitive: false)
        #expect(ScanSelection.canSelect(lima, mode: .analyze))
        #expect(!ScanSelection.canSelect(lima, mode: .clean))
        #expect(!DiskService.canTrashAnalyzed(home.appendingPathComponent(".colima")))
        #expect(!DiskService.canTrashAnalyzed(home.appendingPathComponent(".ssh/id_ed25519")))
        #expect(!DiskService.canTrashAnalyzed(home.appendingPathComponent(".colima-backup/data")))
        #expect(!ScanSelection.canSelect(DiskEntry(url: lima.url, bytes: 1, category: "文件", sensitive: false, isPartial: true), mode: .analyze))
    }
    @Test func analysisRecognizesDataDirectoriesWithoutOpeningCredentials() {
        let home = DiskService.home
        for path in [".colima/default/disk", ".cache/huggingface/model", ".npm/_cacache/data", ".ollama/models/blobs/model", ".docker/desktop/vms/0/data", ".cargo/registry/src/crate", ".cargo/git/db/repo", ".gradle/caches/modules/data", ".gradle/wrapper/dists/gradle", "Library/Caches/app/nested/cache", "Library/Logs/app/log", "Library/Developer/Xcode/DerivedData/project/Build", "Library/Application Support/MobileSync/Backup/device/file", "Library/Containers/com.example.app/Data/Library/Caches/app/nested/file", "Library/Application Support/Google/Chrome/Default/Cache/Cache_Data/file"] {
            #expect(DiskService.canTrashAnalyzed(home.appendingPathComponent(path)), "Expected selectable: \(path)")
        }
        for path in [".ssh/key", ".gnupg/key", ".aws/credentials", ".config/tool/config", ".docker/config.json", ".docker/contexts/meta", ".ollama/id_ed25519", ".cargo/credentials.toml", ".gradle/gradle.properties", ".cache-other/data", ".colima/../../etc/passwd", "Library/Keychains/login.keychain-db", "Library/Preferences/app.plist", "Library/Application Support/app/database", "Library/Caches", "Library/Containers/com.example.app/Data/Documents/file", "Library/Application Support/Google/Chrome/Default/Cookies"] {
            #expect(!DiskService.canTrashAnalyzed(home.appendingPathComponent(path)), "Expected protected: \(path)")
        }
    }
    @Test func analysisReportsProtectionAndIncompleteScanReasons() {
        let url = DiskService.home.appendingPathComponent(".ssh/key")
        #expect(ScanSelection.disabledReason(DiskEntry(url: url, bytes: 0, category: "文件", sensitive: false), mode: .analyze)?.contains("受保护") == true)
        #expect(ScanSelection.disabledReason(DiskEntry(url: url, bytes: 0, category: "文件", sensitive: false, isComplete: false), mode: .analyze)?.contains("等待统计") == true)
        #expect(ScanSelection.disabledReason(DiskEntry(url: url, bytes: 0, category: "文件", sensitive: false, isPartial: true), mode: .analyze)?.contains("统计不完整") == true)
    }
    @Test func analysisRejectsSymlinksAndSymlinkAncestors() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: home.appendingPathComponent(".cache"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let link = home.appendingPathComponent(".cache/escape")
        try fm.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System"))
        #expect(DiskService.analyzedProtectionReason(link, home: home)?.contains("符号链接") == true)
        #expect(DiskService.analyzedProtectionReason(link.appendingPathComponent("Library"), home: home)?.contains("符号链接") == true)
        #expect(DiskService.analyzedProtectionReason(home.appendingPathComponent(".cache/../.ssh/key"), home: home) != nil)
        #expect(DiskService.analyzedProtectionReason(URL(fileURLWithPath: home.path + "-other/.cache/file"), home: home) != nil)
    }
    @Test func bulkCleanupExcludesRootAndUnfinishedEntries() {
        let root = DiskService.home.appendingPathComponent("Library/Caches")
        let file = root.appendingPathComponent("clean-selection-test")
        let entries = [DiskEntry(url: root, bytes: 0, category: "缓存", sensitive: false), DiskEntry(url: file, bytes: 1, category: "缓存", sensitive: false), DiskEntry(url: root.appendingPathComponent("pending"), bytes: 0, category: "缓存", sensitive: false, isComplete: false), DiskEntry(url: root.appendingPathComponent("partial"), bytes: 1, category: "缓存", sensitive: false, isPartial: true)]
        #expect(ScanSelection.eligibleIDs(entries, mode: .clean) == [file.path])
    }
    @Test func bulkAnalysisExcludesProtectedPaths() {
        let file = DiskService.home.appendingPathComponent("Downloads/clean-selection-test")
        let entries = [DiskEntry(url: file, bytes: 1, category: "文件", sensitive: false), DiskEntry(url: URL(fileURLWithPath: "/System/Library"), bytes: 1, category: "文件", sensitive: false), DiskEntry(url: DiskService.home.appendingPathComponent("Library"), bytes: 1, category: "文件", sensitive: false)]
        #expect(ScanSelection.eligibleIDs(entries, mode: .analyze) == [file.path])
    }
    @Test func selectVisiblePreservesPriorSelectionsWithoutSelectingHiddenRows() {
        let home = DiskService.home
        let visible = DiskEntry(url: home.appendingPathComponent("Downloads/visible"), bytes: 1, category: "文件", sensitive: false)
        var selected: Set<String> = ["previous-selection"]
        selected.formUnion(ScanSelection.eligibleIDs([visible], mode: .analyze))
        #expect(selected == ["previous-selection", visible.id])
    }
}

struct CleanupCoverageTests {
    @Test func developerCacheRulesDoNotIncludeModelsOrRepositories() {
        let home = URL(fileURLWithPath: "/tmp/clean-policy-home")
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent(".npm/_cacache/content-v2"), home: home) != nil)
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent(".cache/uv/archive-v0"), home: home) != nil)
        for path in [".cache/huggingface/model", ".cache/lm-studio/model", ".m2/repository/artifact", "Projects/app/node_modules/package", ".ssh/id_ed25519"] {
            #expect(CleanupCatalog.rule(for: home.appendingPathComponent(path), home: home) == nil)
        }
    }
    @Test func containerRulesOnlyAllowCacheChildren() {
        let home = URL(fileURLWithPath: "/tmp/clean-policy-home")
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent("Library/Containers/com.example.app/Data/Library/Caches/cache"), home: home) != nil)
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent("Library/Containers/com.example.app/Data/Documents/document"), home: home) == nil)
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent("Library/Group Containers/group.example/Library/Caches/cache"), home: home)?.sensitive == true)
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent("Library/Group Containers/group.example/database"), home: home) == nil)
    }
    @Test func browserRulesExcludeAccountAndOfflineData() {
        let home = URL(fileURLWithPath: "/tmp/clean-policy-home")
        let base = "Library/Application Support/Google/Chrome/Profile 2/"
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent(base + "Code Cache/js"), home: home) != nil)
        for path in ["Cookies", "Login Data", "History", "IndexedDB/data", "Service Worker/CacheStorage/data"] {
            #expect(CleanupCatalog.rule(for: home.appendingPathComponent(base + path), home: home) == nil)
        }
        #expect(CleanupCatalog.rule(for: home.appendingPathComponent("Library/Application Support/Google/Chrome/Unknown/Code Cache/js"), home: home) == nil)
    }
    @Test func optionalRulesSkipAbsentAppsAndIncludeHiddenCacheFiles() async throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let cache = home.appendingPathComponent("Library/Containers/com.example.test/Data/Library/Caches")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let file = cache.appendingPathComponent(".hidden-cache")
        try Data(repeating: 1, count: 8192).write(to: file)
        let result = await Task.detached {
            let discovery = CleanupCatalog.discover(home: home)
            return await DiskService.scanConcurrently(discovery.rules.map(\.scanRoot), initialIssues: discovery.issues) { _ in }
        }.value
        #expect(result.entries.map { $0.url.resolvingSymlinksInPath() } == [file.resolvingSymlinksInPath()])
        #expect(result.issues.isEmpty)
        #expect(result.skipped == 0)
        #expect(fm.fileExists(atPath: file.path))
    }
}

struct CleanupRunningAppTests {
    @Test func matchesOnlyRelatedCacheOwners() {
        let root = DiskService.home.appendingPathComponent("Library/Caches")
        let entry = DiskEntry(url: root.appendingPathComponent("com.example.Editor.cache"), bytes: 1, category: "缓存", sensitive: false)
        let rule = CleanupRule(root: root, category: "缓存")
        #expect(DiskService.matchesRunningApp(entry, rule: rule, id: "com.example.Editor", name: "Editor"))
        #expect(!DiskService.matchesRunningApp(entry, rule: rule, id: "com.example.Other", name: "Other"))
        let owned = CleanupRule(root: root, category: "缓存", ownerIDs: ["com.example.Editor.helper"])
        #expect(DiskService.matchesRunningApp(entry, rule: owned, id: "com.example.Editor", name: "Editor"))
    }
}
