import AppKit
import SwiftUI

@main
struct PetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanel(coordinator: appDelegate.coordinator, settings: .shared, history: .shared)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()
    private var pendingURLs: [URL] = []
    private var launched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility: no Dock icon unless the Manager is open or the user asks for one.
        coordinator.start()
        _ = Updater.shared // starts Sparkle's scheduled checks
        launched = true
        if !pendingURLs.isEmpty {
            coordinator.open(pendingURLs)
            pendingURLs.removeAll()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            // First launch: show the Manager so people find the app.
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            coordinator.manager.show(section: .about)
        }
    }

    /// Finder "Open With" and drops on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { coordinator.open(urls) } else { pendingURLs += urls }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.manager.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
