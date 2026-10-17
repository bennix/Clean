import Foundation

nonisolated struct ScanIssue: Identifiable, Sendable {
    enum Kind: String, Sendable { case missing = "目录不存在", permission = "权限不足", symbolicLink = "已跳过符号链接", unreadable = "无法读取" }
    var id: String { url.path + kind.rawValue }
    let url: URL
    let kind: Kind
    let detail: String
    static func from(_ error: Error, at url: URL) -> ScanIssue {
        let ns = error as NSError
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        let codes = [ns, underlying].compactMap { $0 }
        let permission = codes.contains { ($0.domain == NSPOSIXErrorDomain && [1, 13].contains($0.code)) || ($0.domain == NSCocoaErrorDomain && [257, 513].contains($0.code)) }
        let missing = codes.contains { ($0.domain == NSPOSIXErrorDomain && $0.code == 2) || ($0.domain == NSCocoaErrorDomain && [4, 260].contains($0.code)) }
        return ScanIssue(url: url, kind: permission ? .permission : missing ? .missing : .unreadable, detail: error.localizedDescription)
    }
}
