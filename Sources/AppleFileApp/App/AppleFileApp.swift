import AppKit
import SwiftUI

@main
struct AppleFileApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Apple File App", systemImage: "circle.hexagongrid.circle") {
            Button("Open Files…") { appDelegate.coordinator.chooseFiles() }
                .keyboardShortcut("o")
            Divider()
            Text("Drag any file to open the ring")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar utility: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        coordinator.start()
    }
}
