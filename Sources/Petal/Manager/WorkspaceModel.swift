import AppKit
import FileAppCore
import QuickLookThumbnailing

struct WorkspaceFile: Identifiable {
    let url: URL
    let kind: FileKind
    let size: Int64

    var id: URL { url }

    var kindLabel: String {
        switch kind {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .video: return "Video"
        case .document: return "Document"
        case .other: return "Other"
        }
    }
}

/// Files collected in the Manager, waiting for an action.
@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var files: [WorkspaceFile] = []
    @Published var selection: Set<URL> = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]

    /// Folders are expanded (recursively) up to this many files.
    static let folderLimit = 500

    /// The files an action applies to: the selection, or everything when nothing is selected.
    var targets: [URL] {
        let all = files.map(\.url)
        return selection.isEmpty ? all : all.filter(selection.contains)
    }

    var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }

    func add(_ urls: [URL]) {
        var known = Set(files.map(\.url))
        var added: [WorkspaceFile] = []
        for url in urls.flatMap(expand) where !known.contains(url) {
            known.insert(url)
            added.append(WorkspaceFile(url: url, kind: FileKind(url: url), size: url.fileSize))
        }
        files += added
        added.forEach(loadThumbnail)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func remove(_ urls: Set<URL>) {
        files.removeAll { urls.contains($0.url) }
        selection.subtract(urls)
        urls.forEach { thumbnails[$0] = nil }
    }

    /// After a rename: same rows, new file names.
    func replace(_ old: [URL], with new: [URL]) {
        let map = Dictionary(zip(old, new), uniquingKeysWith: { first, _ in first })
        files = files.map { file in
            guard let url = map[file.url] else { return file }
            thumbnails[url] = thumbnails.removeValue(forKey: file.url)
            return WorkspaceFile(url: url, kind: file.kind, size: file.size)
        }
        selection = Set(selection.map { map[$0] ?? $0 })
    }

    func move(from offsets: IndexSet, to destination: Int) {
        files.move(fromOffsets: offsets, toOffset: destination)
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name, kind, size, modified

        var id: String { rawValue }
        var title: String {
            switch self {
            case .name: return "Name"
            case .kind: return "Kind"
            case .size: return "Size (Largest First)"
            case .modified: return "Date Modified (Newest First)"
            }
        }
    }

    func sort(by order: SortOrder) {
        func name(_ file: WorkspaceFile) -> String { file.url.lastPathComponent }
        func modified(_ file: WorkspaceFile) -> Date {
            (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        files.sort { a, b in
            switch order {
            case .name: return name(a).localizedStandardCompare(name(b)) == .orderedAscending
            case .kind: return (a.url.pathExtension.lowercased(), name(a)) < (b.url.pathExtension.lowercased(), name(b))
            case .size: return a.size > b.size
            case .modified: return modified(a) > modified(b)
            }
        }
    }

    /// Moves files to the Trash (recoverable from Finder) and drops them from the list.
    func trash(_ urls: [URL]) {
        var trashed: Set<URL> = []
        for url in urls where (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
            trashed.insert(url)
        }
        remove(trashed)
    }

    func clear() {
        files.removeAll()
        selection.removeAll()
        thumbnails.removeAll()
    }

    /// Drops files that were moved or deleted since they were added.
    func refresh() {
        let missing = files.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.map(\.url)
        remove(Set(missing))
    }

    private func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else { return [url] }

        var found: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        while let item = enumerator?.nextObject() as? URL, found.count < Self.folderLimit {
            if (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
               FileKind(url: item) != .other {
                found.append(item)
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func loadThumbnail(_ file: WorkspaceFile) {
        thumbnails[file.url] = NSWorkspace.shared.icon(forFile: file.url.path)
        let request = QLThumbnailGenerator.Request(
            fileAt: file.url, size: CGSize(width: 64, height: 64),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            guard let image = thumbnail?.nsImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.files.contains(where: { $0.url == file.url }) else { return }
                    self.thumbnails[file.url] = image
                }
            }
        }
    }
}
