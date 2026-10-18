import Foundation

nonisolated enum ScanSelection {
    enum Mode { case clean, uninstall, analyze }
    static func canSelect(_ entry: DiskEntry, mode: Mode) -> Bool {
        disabledReason(entry, mode: mode) == nil
    }
    static func disabledReason(_ entry: DiskEntry, mode: Mode) -> String? {
        guard entry.isComplete else { return L("等待统计完成后可选择") }
        guard !entry.isPartial else { return L("统计不完整：请检查读取错误与访问权限后重新扫描") }
        switch mode {
        case .clean: return DiskService.canDelete(entry.url) ? nil : L("受保护：不在已识别的清理范围内")
        case .uninstall: return UninstallService.validApp(entry.url) ? nil : L("受保护：不是可卸载的应用")
        case .analyze: return DiskService.analyzedProtectionReason(entry.url)
        }
    }
    static func eligibleIDs(_ entries: [DiskEntry], mode: Mode) -> Set<String> {
        Set(entries.filter { canSelect($0, mode: mode) }.map(\.id))
    }
}
