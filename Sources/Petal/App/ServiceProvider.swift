import AppKit

/// Finder services ("Quick Actions"): right-click files → Services → Petal: Compress, etc.
/// Declared under NSServices in Info.plist; NSUserData names the action.
@MainActor
final class ServiceProvider: NSObject {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    @objc func runService(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = "No files" as NSString
            return
        }
        coordinator.run(named: userData ?? "ring", on: urls)
    }
}
