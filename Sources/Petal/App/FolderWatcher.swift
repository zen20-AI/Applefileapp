import Foundation
import FileAppCore

/// "Watch folder" automation: new files in a folder get an action applied automatically.
struct WatchRule: Codable, Identifiable, Equatable {
    enum Action: String, Codable, CaseIterable, Identifiable {
        case compress, toJPG, toPNG, toPDF, removeMetadata, copyText, cutOut

        var id: String { rawValue }

        var title: String {
            switch self {
            case .compress: return String(localized: "Compress")
            case .toJPG: return String(localized: "Convert to JPG")
            case .toPNG: return String(localized: "Convert to PNG")
            case .toPDF: return String(localized: "Convert to PDF")
            case .removeMetadata: return String(localized: "Remove Metadata")
            case .copyText: return String(localized: "Save Text (OCR)")
            case .cutOut: return String(localized: "Remove Background")
            }
        }

        func applies(to url: URL) -> Bool {
            switch self {
            case .compress: return Compressor.canCompress(url)
            case .toJPG: return Converter.isAvailable(.jpg, for: url)
            case .toPNG: return Converter.isAvailable(.png, for: url)
            case .toPDF: return Converter.isAvailable(.pdf, for: url)
            case .removeMetadata, .cutOut: return FileKind(url: url) == .image
            case .copyText: return TextRecognizer.canRecognize(url)
            }
        }

        func run(on url: URL) throws -> [URL] {
            switch self {
            case .compress: return [try Compressor.compress(url).output]
            case .toJPG: return try Converter.convert(url, to: .jpg)
            case .toPNG: return try Converter.convert(url, to: .png)
            case .toPDF: return try Converter.convert(url, to: .pdf)
            case .removeMetadata:
                let output = OutputNaming.url(for: url, suffix: "Clean", fileExtension: url.pathExtension.isEmpty ? "png" : url.pathExtension)
                try ImageFile.writeWithoutMetadata(from: url, to: output)
                return [output]
            case .copyText: return [try TextRecognizer.extract(url).output]
            case .cutOut: return [try BackgroundRemover.removeBackground(url)]
            }
        }
    }

    var id = UUID()
    var folderPath: String
    var action: Action
    var enabled = true

    var folder: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
}

/// Watches each enabled rule's folder and runs its action on files that appear there.
@MainActor
final class FolderWatcher: ObservableObject {
    static let shared = FolderWatcher()

    @Published var rules: [WatchRule] { didSet { save(); restart() } }
    /// Called with (rule, outputs) or (rule, error) so the app can show a toast and record history.
    var onResult: ((WatchRule, URL, Result<[URL], Error>) -> Void)?

    private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
    private var known: [UUID: Set<String>] = [:]
    /// Files Petal wrote itself, so a rule never processes its own results.
    private var produced: Set<String> = []
    private var pending: [UUID: DispatchWorkItem] = [:]

    private init() {
        let data = UserDefaults.standard.data(forKey: "watchRules")
        rules = data.flatMap { try? JSONDecoder().decode([WatchRule].self, from: $0) } ?? []
    }

    func start() { restart() }

    func add(folder: URL, action: WatchRule.Action) {
        rules.append(WatchRule(folderPath: folder.path, action: action))
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(rules), forKey: "watchRules")
    }

    private func restart() {
        sources.values.forEach { $0.cancel() }
        sources.removeAll()
        for rule in rules where rule.enabled {
            let fd = open(rule.folderPath, O_EVTONLY)
            guard fd >= 0 else { continue }
            known[rule.id] = known[rule.id] ?? listing(rule.folder)
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.scheduleScan(rule) }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources[rule.id] = source
        }
    }

    /// Waits for the folder to settle (downloads and copies write in bursts) before scanning.
    private func scheduleScan(_ rule: WatchRule) {
        pending[rule.id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.scan(rule) }
        }
        pending[rule.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func scan(_ rule: WatchRule) {
        let now = listing(rule.folder)
        let new = now.subtracting(known[rule.id] ?? []).subtracting(produced)
        known[rule.id] = now
        let files = new.map { URL(fileURLWithPath: $0) }
            .filter { !$0.lastPathComponent.hasPrefix(".") && !Self.isPartial($0) && !Self.isResult($0)
                && rule.action.applies(to: $0) }
        for url in files.sorted(by: { $0.path < $1.path }) {
            DispatchQueue.global(qos: .utility).async {
                let result = Result { try rule.action.run(on: url) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if case .success(let outputs) = result {
                            self.produced.formUnion(outputs.map(\.path))
                            self.known[rule.id, default: []].formUnion(outputs.map(\.path))
                        }
                        self.onResult?(rule, url, result)
                    }
                }
            }
        }
    }

    private func listing(_ folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names.map { folder.appendingPathComponent($0).path })
    }

    /// Results Petal writes ("… Compressed.jpg", "… Clean 2.png") are never fed back into a rule,
    /// even when they land before the job that made them reports back.
    private static func isResult(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
        return ["Compressed", "Clean", "No Background", "Text", "Resized"].contains { name.hasSuffix(" " + $0) }
    }

    /// Browsers write downloads under temporary names first.
    private static func isPartial(_ url: URL) -> Bool {
        ["crdownload", "download", "part", "partial", "tmp"].contains(url.pathExtension.lowercased())
    }
}
