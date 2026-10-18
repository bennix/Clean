import SwiftUI
import AppKit
import CoreServices
import Combine

@MainActor
final class AppUsageStore: ObservableObject {
    static let shared = AppUsageStore()
    @Published private(set) var launches: [String: Date] = [:]
    private var observer: NSObjectProtocol?
    private let key = "Clean.observedAppLaunches"
    func start() {
        guard observer == nil else { return }
        if let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: Date] { launches = saved }
        for app in NSWorkspace.shared.runningApplications { record(app) }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.record(app)
            }
        }
    }
    private func record(_ app: NSRunningApplication) {
        guard let url = app.bundleURL, let date = app.launchDate else { return }
        if launches[url.path].map({ $0 >= date }) == true { return }
        launches[url.path] = date
        UserDefaults.standard.set(launches, forKey: key)
    }
    nonisolated static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

struct AppUsageColumns: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    let url: URL
    @ObservedObject private var store = AppUsageStore.shared
    @State private var historical: Date?
    var body: some View {
        let _ = language
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let launch = store.launches[url.path]
            let date = launch ?? historical
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(launch != nil ? L("上次启动") : L("最近使用 · Spotlight")).foregroundStyle(.tertiary)
                    if let date { Text(date.formatted(.dateTime.locale(AppLanguage.locale).year().month().day().hour().minute())) }
                    else { Text(L("暂无记录")) }
                }.frame(width: 140, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("距今")).foregroundStyle(.tertiary)
                    Text(date.map { Self.relative($0, now: timeline.date) } ?? "—")
                }.frame(width: 65, alignment: .leading)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .help(L("上次启动来自运行中的应用或 Clean 观察到的启动记录；历史缺失时显示 Spotlight 最近使用时间，它不一定等于启动时间。"))
        .task(id: url.path) {
            AppUsageStore.shared.start()
            historical = await Task.detached(priority: .utility) { AppUsageStore.lastUsed(url) }.value
        }
    }
    private static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter(); formatter.locale = AppLanguage.locale; formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
