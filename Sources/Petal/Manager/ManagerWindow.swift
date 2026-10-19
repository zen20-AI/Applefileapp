import AppKit
import SwiftUI

enum ManagerSection: String, CaseIterable, Identifiable {
    case workspace, history, settings, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "Workspace"
        case .history: return "History"
        case .settings: return "Settings"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "tray.full"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// The Manager: a regular window for working with many files, browsing results and changing settings.
@MainActor
final class ManagerWindowController: NSObject, NSWindowDelegate {
    let workspace = WorkspaceModel()
    let navigation = ManagerNavigation()
    private unowned let coordinator: AppCoordinator
    private var window: NSWindow?

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    var isOpen: Bool { window?.isVisible == true }

    func show(section: ManagerSection? = nil) {
        if let section { navigation.section = section }
        let window = self.window ?? makeWindow()
        self.window = window
        updateActivationPolicy(forceRegular: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Petal"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = CGSize(width: 820, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ManagerView(
            coordinator: coordinator,
            workspace: workspace,
            navigation: navigation,
            settings: AppSettings.shared,
            history: HistoryStore.shared))
        // Center first; the autosave name then restores the last position if there is one.
        window.center()
        window.setFrameAutosaveName("ManagerWindow")
        return window
    }

    /// Shows a Dock icon while the Manager is open (or always, if the user asked for it).
    func updateActivationPolicy(forceRegular: Bool = false) {
        let wantsDock = forceRegular || isOpen || AppSettings.shared.showDockIcon
        let policy: NSApplication.ActivationPolicy = wantsDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.updateActivationPolicy() }
        }
    }
}

@MainActor
final class ManagerNavigation: ObservableObject {
    @Published var section: ManagerSection = .workspace
}
