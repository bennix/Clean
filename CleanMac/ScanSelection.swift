import Foundation

nonisolated enum ScanSelection {
    enum Mode { case clean, uninstall, analyze }
    static func canSelect(_ entry: DiskEntry, mode: Mode) -> Bool {
        guard entry.isComplete, !entry.isPartial else { return false }
        switch mode {
        case .clean: return DiskService.canDelete(entry.url)
        case .uninstall: return UninstallService.validApp(entry.url)
        case .analyze: return DiskService.canTrashAnalyzed(entry.url)
        }
    }
    static func eligibleIDs(_ entries: [DiskEntry], mode: Mode) -> Set<String> {
        Set(entries.filter { canSelect($0, mode: mode) }.map(\.id))
    }
}
