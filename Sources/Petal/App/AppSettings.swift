import AppKit
import FileAppCore
import Foundation
import ServiceManagement

/// User preferences, persisted in UserDefaults and pushed into FileAppCore.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var ringEnabled: Bool { didSet { save() } }
    @Published var activationDistance: Double { didSet { save() } }
    @Published var useCustomFolder: Bool { didSet { save() } }
    @Published var customFolderPath: String { didSet { save() } }
    @Published var lossyQuality: Double { didSet { save() } }
    @Published var compressQuality: Double { didSet { save() } }
    @Published var pdfDPI: Double { didSet { save() } }
    @Published var revealAfterSaving: Bool { didSet { save() } }
    @Published var showDockIcon: Bool { didSet { save() } }

    /// Fired after any change so observers (drag monitor, Dock icon) can follow along.
    var onChange: (() -> Void)?

    private init() {
        defaults.register(defaults: [
            "ringEnabled": true,
            "activationDistance": 24.0,
            "useCustomFolder": false,
            "customFolderPath": "",
            "lossyQuality": 0.9,
            "compressQuality": 0.6,
            "pdfDPI": 300.0,
            "revealAfterSaving": false,
            "showDockIcon": false,
        ])
        ringEnabled = defaults.bool(forKey: "ringEnabled")
        activationDistance = defaults.double(forKey: "activationDistance")
        useCustomFolder = defaults.bool(forKey: "useCustomFolder")
        customFolderPath = defaults.string(forKey: "customFolderPath") ?? ""
        lossyQuality = defaults.double(forKey: "lossyQuality")
        compressQuality = defaults.double(forKey: "compressQuality")
        pdfDPI = defaults.double(forKey: "pdfDPI")
        revealAfterSaving = defaults.bool(forKey: "revealAfterSaving")
        showDockIcon = defaults.bool(forKey: "showDockIcon")
        applyToCore()
    }

    var customFolder: URL? {
        guard useCustomFolder, !customFolderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: customFolderPath, isDirectory: true)
    }

    func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customFolderPath = url.path
        useCustomFolder = true
    }

    func resetToDefaults() {
        for key in ["ringEnabled", "activationDistance", "useCustomFolder", "customFolderPath", "lossyQuality",
                    "compressQuality", "pdfDPI", "revealAfterSaving", "showDockIcon"] {
            defaults.removeObject(forKey: key)
        }
        ringEnabled = defaults.bool(forKey: "ringEnabled")
        activationDistance = defaults.double(forKey: "activationDistance")
        useCustomFolder = defaults.bool(forKey: "useCustomFolder")
        customFolderPath = ""
        lossyQuality = defaults.double(forKey: "lossyQuality")
        compressQuality = defaults.double(forKey: "compressQuality")
        pdfDPI = defaults.double(forKey: "pdfDPI")
        revealAfterSaving = defaults.bool(forKey: "revealAfterSaving")
        showDockIcon = defaults.bool(forKey: "showDockIcon")
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(ringEnabled, forKey: "ringEnabled")
        defaults.set(activationDistance, forKey: "activationDistance")
        defaults.set(useCustomFolder, forKey: "useCustomFolder")
        defaults.set(customFolderPath, forKey: "customFolderPath")
        defaults.set(lossyQuality, forKey: "lossyQuality")
        defaults.set(compressQuality, forKey: "compressQuality")
        defaults.set(pdfDPI, forKey: "pdfDPI")
        defaults.set(revealAfterSaving, forKey: "revealAfterSaving")
        defaults.set(showDockIcon, forKey: "showDockIcon")
        applyToCore()
        onChange?()
    }

    private func applyToCore() {
        OutputNaming.destinationDirectory = customFolder
        Converter.lossyQuality = lossyQuality
        Converter.pdfRenderDPI = CGFloat(pdfDPI)
        Compressor.defaultQuality = compressQuality
    }
}
