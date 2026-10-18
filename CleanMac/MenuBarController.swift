import SwiftUI
import AppKit

extension Notification.Name {
    static let cleanShowStatus = Notification.Name("Clean.showStatus")
    static let cleanOpenWindow = Notification.Name("Clean.openWindow")
}

@MainActor
final class CleanAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var current: CleanAppDelegate?
    override init() { super.init(); Self.current = self }
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var mainWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: L("Clean 系统状态"))
            image?.isTemplate = true
            button.image = image
            button.toolTip = L("Clean · 点击查看系统状态")
            button.target = self; button.action = #selector(toggleStatus)
        }
        statusItem = item
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 700)
        popover.contentViewController = NSHostingController(rootView: StatusDashboard(monitor: .shared, compact: true).frame(width: 440, height: 700))
        _ = UpdateService.shared
        SystemMonitor.shared.start()
        AppUsageStore.shared.start()
        observers.append(NotificationCenter.default.addObserver(forName: .cleanShowStatus, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.showStatusAndHideWindow() } })
        observers.append(NotificationCenter.default.addObserver(forName: .cleanOpenWindow, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.openWindow() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let window = note.object as? NSWindow, window.identifier?.rawValue == "Clean.main" else { return }
                self?.attach(window)
            }
        })
    }
    func attach(_ window: NSWindow) {
        mainWindow = window
        window.delegate = self
        window.isReleasedWhenClosed = false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openWindow(); return true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }
    func windowDidMiniaturize(_ notification: Notification) {
        mainWindow?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    private func showStatusAndHideWindow() {
        mainWindow?.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        showStatus()
    }
    @objc private func toggleStatus() {
        if popover.isShown { popover.performClose(nil) } else { showStatus() }
    }
    private func showStatus() {
        guard let button = statusItem?.button else { return }
        button.toolTip = L("Clean · 点击查看系统状态")
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    private func openWindow() {
        popover.performClose(nil)
        NSApplication.shared.setActivationPolicy(.regular)
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

struct MainWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class WindowView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("Clean.main")
            CleanAppDelegate.current?.attach(window)
        }
    }
}
