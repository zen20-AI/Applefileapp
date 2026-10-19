import AppKit
import Foundation

/// macOS asks once per protected folder (Desktop, Documents, Downloads…) before an app may read it.
/// This asks up front, from one place, instead of in the middle of a drag.
@MainActor
final class FolderAccess: ObservableObject {
    static let shared = FolderAccess()

    struct Folder: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let url: URL
    }

    enum Status { case unknown, granted, denied }

    let folders: [Folder] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func folder(_ id: String, _ title: String, _ symbol: String, _ directory: FileManager.SearchPathDirectory) -> Folder {
            let url = FileManager.default.urls(for: directory, in: .userDomainMask).first ?? home.appendingPathComponent(id)
            return Folder(id: id, title: title, symbol: symbol, url: url)
        }
        return [
            folder("Desktop", String(localized: "Desktop"), "menubar.dock.rectangle", .desktopDirectory),
            folder("Documents", String(localized: "Documents"), "doc.on.doc", .documentDirectory),
            folder("Downloads", String(localized: "Downloads"), "arrow.down.circle", .downloadsDirectory),
            folder("Pictures", String(localized: "Pictures"), "photo.on.rectangle", .picturesDirectory),
            Folder(id: "iCloud", title: String(localized: "iCloud Drive"), symbol: "icloud",
                   url: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")),
        ]
    }()

    @Published private(set) var status: [String: Status] = [:]

    var allGranted: Bool { folders.allSatisfy { status[$0.id] == .granted || !exists($0) } }

    private init() {
        // Only remember what the user already allowed; checking unasked folders would pop up prompts.
        for id in UserDefaults.standard.stringArray(forKey: "grantedFolders") ?? [] { status[id] = .granted }
    }

    /// Reading a folder's contents is what makes macOS show its "allow access" prompt.
    func request(_ folder: Folder) {
        guard exists(folder) else { return }
        let granted = (try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) != nil
        status[folder.id] = granted ? .granted : .denied
        let ids = folders.filter { status[$0.id] == .granted }.map(\.id)
        UserDefaults.standard.set(ids, forKey: "grantedFolders")
    }

    /// Asks for each folder in turn (macOS shows one prompt per folder).
    func requestAll() {
        for folder in folders where status[folder.id] != .granted { request(folder) }
    }

    /// Re-checks folders that were allowed before (e.g. after access was turned off in System Settings).
    func refresh() {
        for folder in folders where status[folder.id] != nil { request(folder) }
    }

    func exists(_ folder: Folder) -> Bool { FileManager.default.fileExists(atPath: folder.url.path) }

    /// Full Disk Access can't be requested by an app; this opens the right System Settings page.
    func openFullDiskAccessSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    func openFilesAndFoldersSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
