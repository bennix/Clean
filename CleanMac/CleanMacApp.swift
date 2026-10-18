import SwiftUI

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(CleanAppDelegate.self) private var delegate
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    var body: some Scene {
        let _ = language
        WindowGroup("Clean") {
            ContentView()
                .background(MainWindowReader())
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L("检查更新…")) { UpdateService.shared.check() }
            }
        }
    }
}
