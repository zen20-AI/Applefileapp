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
    private var pendingLinks: [URL] = []
    private lazy var onboarding = OnboardingWindowController()
    private var launched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility: no Dock icon unless the Manager is open or the user asks for one.
        coordinator.start()
        _ = Updater.shared // starts Sparkle's scheduled checks
        launched = true
        pendingLinks.forEach(coordinator.handle)
        if !pendingURLs.isEmpty {
            coordinator.open(pendingURLs)
            pendingURLs.removeAll()
        } else if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            // First launch: a short welcome that also asks for folder access up front.
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            onboarding.show()
        }
    }

    /// Finder "Open With" and drops on the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        let links = urls.filter { $0.scheme == "petal" }
        let files = urls.filter(\.isFileURL)
        if launched {
            links.forEach(coordinator.handle)
            if !files.isEmpty { coordinator.open(files) }
        } else {
            pendingLinks += links
            pendingURLs += files
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.manager.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
