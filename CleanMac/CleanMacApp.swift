import SwiftUI

@main
struct CleanMacApp: App {
    @NSApplicationDelegateAdaptor(CleanAppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Clean") {
            ContentView()
                .background(MainWindowReader())
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
    }
}
