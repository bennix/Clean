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
