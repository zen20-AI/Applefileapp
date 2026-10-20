import AppKit
import FileAppCore
import SwiftUI
import UniformTypeIdentifiers

/// Wires drag detection → ring → actions (batch jobs or editor windows).
@MainActor
final class AppCoordinator {
    private let dragMonitor = DragMonitor()
    private let ring = RingController()
    private let toast = ToastController()
    private let editors = EditorWindows()
    private let settings = AppSettings.shared
    private let history = HistoryStore.shared
    private(set) lazy var manager = ManagerWindowController(coordinator: self)
    private lazy var services = ServiceProvider(coordinator: self)
    private var hotKey: HotKey?
    private(set) lazy var shelf: ShelfController = {
        let shelf = ShelfController()
        shelf.onRing = { [weak self] urls in self?.showRing(for: urls, near: NSEvent.mouseLocation) }
        return shelf
    }()

    func start() {
        dragMonitor.onDragBegan = { [weak self] urls, location in
            self?.ring.show(urls: urls, near: location, interaction: .drag)
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.ring.hide()
        }

        ring.model.onAction = { [weak self] action, urls in
            self?.ring.hide()
            // Leave the drop callback before doing any work.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.perform(action, on: urls) }
            }
        }
        ring.model.onDismiss = { [weak self] in self?.ring.hide() }

        settings.onChange = { [weak self] in self?.applySettings() }
        applySettings()

        FolderWatcher.shared.onResult = { [weak self] rule, source, result in
            guard let self else { return }
            switch result {
            case .success(let outputs):
                self.history.record(action: rule.action.title, sources: [source], outputs: outputs)
                self.toast.message(rule.action.title, detail: source.lastPathComponent, outputs: outputs)
            case .failure(FileAppError.alreadyUnder), .failure(FileAppError.noSavings):
                break // nothing to do for this file; not worth a toast
            case .failure(let error):
                self.toast.message(rule.action.title, detail: error.localizedDescription, isError: true)
            }
        }
        FolderWatcher.shared.start()

        // Finder: right-click → Quick Actions / Services → Petal.
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    /// ⌥⌘P: the ring for whatever is selected in Finder (or a file picker when nothing is).
    func ringForFinderSelection() {
        let urls = FinderSelection.urls()
        if urls.isEmpty { chooseFiles() } else { showRing(for: urls, near: NSEvent.mouseLocation) }
    }

    /// Runs a tool by name: used by Finder services and petal:// links (Shortcuts → Open URL).
    func run(named name: String, on urls: [URL]) {
        switch name.lowercased() {
        case "ring": urls.isEmpty ? ringForFinderSelection() : showRing(for: urls, near: NSEvent.mouseLocation)
        case "workspace": open(urls)
        case "pages": organizePages(urls)
        case "split": splitPages(urls)
        case "merge": merge(urls)
        case "rename": rename(urls)
        case "text", "copytext", "ocr": copyText(urls)
        case "shelf": urls.isEmpty ? shelf.toggle() : shelf.add(urls)
        case let name where name.hasPrefix("compress-") && ByteFormatter.parseLimit(String(name.dropFirst(9))) != nil:
            compress(urls, limit: ByteFormatter.parseLimit(String(name.dropFirst(9))))
        default:
            if let tool = Tool(rawValue: name) ?? Tool.allCases.first(where: { $0.rawValue.lowercased() == name.lowercased() }) {
                perform(.tool(tool), on: urls)
            } else if name.lowercased().hasPrefix("convert-"), let format = OutputFormat(rawValue: String(name.dropFirst(8)).lowercased()) {
                perform(.convert(format), on: urls)
            } else {
                toast.message(String(localized: "Petal"), detail: String(localized: "Unknown action “\(name)”"), isError: true)
            }
        }
    }

    /// petal://run?action=compress&path=/Users/me/a.jpg&path=…   ·   petal://ring
    func handle(_ link: URL) {
        let components = URLComponents(url: link, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        let paths = items.filter { $0.name == "path" || $0.name == "file" }.compactMap(\.value)
        let urls = paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let action = items.first(where: { $0.name == "action" })?.value ?? link.host ?? "ring"
        run(named: action == "run" ? "ring" : action, on: urls)
    }

    private func applySettings() {
        dragMonitor.activationDistance = settings.activationDistance
        if settings.ringEnabled { dragMonitor.start() } else { dragMonitor.stop() }
        if settings.hotKeyEnabled, hotKey == nil {
            hotKey = HotKey { [weak self] in self?.ringForFinderSelection() }
        } else if !settings.hotKeyEnabled {
            hotKey?.unregister()
            hotKey = nil
        }
        manager.updateActivationPolicy()
    }

    /// Menu bar entry point: pick files, then use the ring with clicks.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        showRing(for: panel.urls)
    }

    func showRing(for urls: [URL], near point: NSPoint? = nil) {
        ring.show(urls: urls, near: point, interaction: .click)
    }

    /// Files opened from Finder ("Open With", Dock icon drops) land in the Manager.
    func open(_ urls: [URL]) {
        manager.show(section: .workspace)
        manager.workspace.add(urls)
    }

    func perform(_ action: RingAction, on urls: [URL]) {
        switch action {
        case .convert(let format):
            let eligible = urls.filter { Converter.isAvailable(format, for: $0) }
            runBatch(title: String(localized: "Converting to \(format.label)"), urls: eligible) { url in
                try Converter.convert(url, to: format)
            }

        case .tool(.compress):
            compress(urls, limit: settings.compressLimit > 0 ? settings.compressLimit : nil)

        case .tool(.shelf):
            shelf.add(urls)

        case .tool(.cutOut):
            let images = urls.filter(BackgroundRemover.canRemove)
            runBatch(title: String(localized: "Removing Background"), urls: images) { [try BackgroundRemover.removeBackground($0)] }

        case .tool(.copyText):
            copyText(urls)

        case .tool(.animate):
            animate(urls)

        case .tool(.secure):
            guard let pdf = urls.first(where: PDFTools.isPDF) else { return }
            openPDFTools(pdf)

        case .tool(.merge):
            merge(urls)

        case .tool(.pages):
            organizePages(urls)

        case .tool(.split):
            splitPages(urls)

        case .tool(.resize):
            let images = urls.filter { FileKind(url: $0) == .image }
            guard !images.isEmpty else { return }
            editors.open(size: CGSize(width: 460, height: 310)) { close in
                ResizeEditor(urls: images, onSave: { [weak self] mode in
                    close()
                    self?.runBatch(title: String(localized: "Resizing"), urls: images) { [try Resizer.resize($0, mode: mode)] }
                }, onClose: close)
            }

        case .tool(let tool):
            guard let url = urls.first(where: { FileKind(url: $0) == .image }) else { return }
            openEditor(tool, for: url)
        }
    }

    /// Compresses at the quality setting, or to "no bigger than `limit`" (videos always use the video preset).
    func compress(_ urls: [URL], limit: Int64?) {
        let eligible = urls.filter { Tool.compress.isAvailable(for: $0) }
        let quality = settings.videoQuality
        let title = limit.map { String(localized: "Compressing to under \(ByteFormatter.limit($0))") } ?? String(localized: "Compressing")
        runBatch(title: title, urls: eligible) { url in
            if FileKind(url: url) == .video { return [try MediaMaker.compressVideo(url, quality: quality)] }
            if let limit { return [try Compressor.compress(url, under: limit).output] }
            return [try Compressor.compress(url, quality: Compressor.defaultQuality).output]
        }
    }

    /// Removes EXIF/GPS/TIFF data from every image in one pass.
    func stripMetadata(_ urls: [URL]) {
        let images = urls.filter { FileKind(url: $0) == .image }
        runBatch(title: String(localized: "Removing Metadata"), urls: images) { url in
            let output = Self.cleanOutputURL(for: url)
            try ImageFile.writeWithoutMetadata(from: url, to: output)
            return [output]
        }
    }

    func merge(_ urls: [URL]) {
        let inputs = urls.filter(PDFMerger.canMerge)
        guard inputs.count > 1 else {
            toast.message(String(localized: "Merge PDF"), detail: String(localized: "Choose at least two images or PDFs"), isError: true)
            return
        }
        runJob(title: String(localized: "Merging \(inputs.count) files"), action: String(localized: "Merge PDF"), sources: inputs) {
            [try PDFMerger.merge(inputs)]
        }
    }

    // MARK: - Text, animation, PDF tools, rename

    /// Reads text from images / PDFs (on device), copies it and shows it.
    func copyText(_ urls: [URL]) {
        let inputs = urls.filter(TextRecognizer.canRecognize)
        guard let first = inputs.first else {
            toast.message(String(localized: "Copy Text"), detail: String(localized: "Choose images or PDFs"), isError: true)
            return
        }
        toast.begin(String(localized: "Reading text"), total: 1)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try inputs.map(TextRecognizer.text(of:)).joined(separator: "\n\n") }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        self.toast.finish(detail: String(localized: "Text copied to the clipboard"))
                        self.editors.open(size: CGSize(width: 560, height: 520), resizable: true) { close in
                            TextResultView(source: first, text: text, onSave: { [weak self] edited in
                                self?.saveText(edited, for: first, sources: inputs)
                            }, onClose: close)
                        }
                    case .success:
                        self.toast.finish(detail: String(localized: "No text found"), isError: true)
                    case .failure(let error):
                        self.toast.finish(detail: error.localizedDescription, isError: true)
                    }
                }
            }
        }
    }

    private func saveText(_ text: String, for source: URL, sources: [URL]) {
        let output = OutputNaming.url(for: source, suffix: "Text", fileExtension: "txt")
        do {
            try text.write(to: output, atomically: true, encoding: .utf8)
            history.record(action: String(localized: "Copy Text"), sources: sources, outputs: [output])
            toast.message(String(localized: "Saved"), detail: output.lastPathComponent, outputs: [output])
            revealIfNeeded([output])
        } catch {
            toast.message(String(localized: "Couldn't save"), detail: error.localizedDescription, isError: true)
        }
    }

    func animate(_ urls: [URL]) {
        let images = urls.filter { FileKind(url: $0) == .image }
        guard images.count > 1 else {
            toast.message(String(localized: "GIF / Video"), detail: String(localized: "Choose at least two images"), isError: true)
            return
        }
        editors.open(size: CGSize(width: 460, height: 330)) { close in
            AnimateEditor(urls: images, onCreate: { [weak self] kind, seconds, maxSide in
                close()
                let title = kind == .gif ? String(localized: "Making GIF") : String(localized: "Making Video")
                self?.runJob(title: title, action: kind == .gif ? "GIF" : String(localized: "Video"), sources: images) {
                    kind == .gif
                        ? [try MediaMaker.makeGIF(images, frameDelay: seconds, maxSide: maxSide)]
                        : [try MediaMaker.makeVideo(images, secondsPerImage: seconds, maxSide: maxSide)]
                }
            }, onClose: close)
        }
    }

    func openPDFTools(_ url: URL) {
        editors.open(size: CGSize(width: 640, height: 470)) { close in
            PDFToolsEditor(url: url, onApply: { [weak self] request in
                let title: String
                let work: () throws -> URL
                switch request {
                case .lock(let password):
                    title = String(localized: "Lock PDF"); work = { try PDFTools.lock(url, password: password) }
                case .unlock(let password):
                    title = String(localized: "Unlock PDF"); work = { try PDFTools.unlock(url, password: password) }
                case .watermark(let text, let opacity):
                    title = String(localized: "Watermark"); work = { try PDFTools.watermark(url, text: text, opacity: opacity) }
                case .number(let position, let ofTotal):
                    title = String(localized: "Page Numbers"); work = { try PDFTools.numberPages(url, position: position, ofTotal: ofTotal) }
                case .sign(let image, let page, let rect):
                    title = String(localized: "Sign PDF"); work = { try PDFTools.stamp(url, image: image, pageIndex: page, rect: rect) }
                }
                close()
                self?.runJob(title: title, action: title, sources: [url]) { [try work()] }
            }, onClose: close)
        }
    }

    /// Renames files in place from a pattern and keeps the Workspace pointing at them.
    func rename(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        editors.open(size: CGSize(width: 520, height: 380)) { close in
            RenameEditor(urls: urls, onRename: { [weak self] pattern in
                guard let self else { return }
                close()
                do {
                    let renamed = try BatchRenamer.rename(urls, pattern: pattern)
                    self.manager.workspace.replace(urls, with: renamed)
                    self.toast.message(String(localized: "Renamed"), detail: String(localized: "\(renamed.count) files"), outputs: renamed)
                } catch {
                    self.toast.message(String(localized: "Rename"), detail: error.localizedDescription, isError: true)
                }
            }, onClose: close)
        }
    }

    // MARK: - PDF pages

    /// Opens the page organizer: reorder, rotate, delete, extract or split pages of PDFs and images.
    func organizePages(_ urls: [URL]) {
        let inputs = urls.filter(PDFMerger.canMerge)
        guard !inputs.isEmpty else {
            toast.message(String(localized: "Pages"), detail: String(localized: "Choose PDFs or images"), isError: true)
            return
        }
        let model: PagesModel
        do {
            model = try PagesModel(urls: inputs)
        } catch {
            toast.message(String(localized: "Pages"), detail: error.localizedDescription, isError: true)
            return
        }
        editors.open(size: CGSize(width: 820, height: 640), resizable: true) { close in
            PagesEditor(
                model: model,
                onSave: { [weak self] pages, name in
                    close()
                    self?.writePages(pages, name: name, suffix: "Edited", action: String(localized: "Organize Pages"))
                },
                onExtract: { [weak self] pages, name in
                    self?.writePages(pages, name: name, suffix: "Extract", action: String(localized: "Extract Pages"))
                },
                onSplit: { [weak self] pages, mode, name in
                    self?.runJob(title: String(localized: "Splitting \(pages.count) pages"), action: String(localized: "Split PDF"), sources: Array(Set(pages.map(\.source)))) {
                        try PDFPages.split(pages, mode: mode, name: name)
                    }
                },
                onClose: close)
        }
    }

    /// Splits every PDF into single pages (or another split mode).
    func splitPages(_ urls: [URL], mode: SplitMode = .everyPage) {
        let pdfs = urls.filter { FileKind(url: $0) == .pdf }
        runBatch(title: String(localized: "Splitting PDF"), urls: pdfs) { try PDFPages.split($0, mode: mode) }
    }

    private func writePages(_ pages: [PageRef], name: URL, suffix: String, action: String) {
        let sources = Array(Set(pages.map(\.source)))
        runJob(title: String(localized: "Saving \(pages.count) pages"), action: action, sources: sources) {
            [try PDFPages.write(pages, name: name, suffix: suffix)]
        }
    }

    /// One background job that produces files, with toast progress and history.
    private func runJob(title: String, action: String, sources: [URL], work: @escaping () throws -> [URL]) {
        toast.begin(title, total: 1)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try work() }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let outputs):
                        self.history.record(action: action, sources: sources, outputs: outputs)
                        self.toast.finish(outputs: outputs)
                        self.revealIfNeeded(outputs)
                    case .failure(let error):
                        self.toast.finish(detail: error.localizedDescription, isError: true)
                    }
                }
            }
        }
    }

    // MARK: - Batch jobs

    private func runBatch(title: String, urls: [URL], work: @escaping (URL) throws -> [URL]) {
        guard !urls.isEmpty else {
            toast.message(title, detail: String(localized: "Nothing here can be processed this way"), isError: true)
            return
        }
        toast.begin(title, total: urls.count)

        DispatchQueue.global(qos: .userInitiated).async {
            var saved = 0
            var outputs: [URL] = []
            var failures: [String] = []
            for url in urls {
                do {
                    outputs += try work(url)
                    saved += 1
                } catch {
                    failures.append(error.localizedDescription)
                }
                let done = saved
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self.toast.update(saved: done, total: urls.count) }
                }
            }
            let summary: String?
            if failures.isEmpty {
                summary = nil
            } else if failures.count == urls.count {
                summary = failures[0]
            } else {
                summary = "\(saved) of \(urls.count) saved · \(failures.count) failed"
            }
            let failed = !failures.isEmpty
            let produced = outputs
            let failureCount = failures.count
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.history.record(action: title, sources: urls, outputs: produced, failures: failureCount)
                    self.toast.finish(detail: summary, isError: failed && produced.isEmpty, outputs: produced)
                    self.revealIfNeeded(produced)
                }
            }
        }
    }

    /// Results go to Finder and/or the Shelf, depending on the settings.
    private func revealIfNeeded(_ outputs: [URL]) {
        guard !outputs.isEmpty else { return }
        if settings.shelfCollectsResults { shelf.add(outputs.filter { !$0.hasDirectoryPath }) }
        if settings.revealAfterSaving { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
    }

    // MARK: - Editors

    private func openEditor(_ tool: Tool, for url: URL) {
        if tool == .metadata {
            editors.open(size: CGSize(width: 560, height: 560)) { close in
                MetadataView(url: url, onStrip: { [weak self] in
                    self?.saveCopy(of: url) { output in
                        try ImageFile.writeWithoutMetadata(from: url, to: output)
                    }
                    close()
                }, onClose: close)
            }
            return
        }

        let image: CGImage
        do {
            image = try ImageFile.load(url)
        } catch {
            toast.message(tool.title, detail: error.localizedDescription, isError: true)
            return
        }

        let save: (String, Bool, CGImage, () -> Void) -> Void = { [weak self] suffix, forcePNG, result, close in
            do {
                let output = try EditorOutput.save(result, source: url, suffix: suffix, forcePNG: forcePNG)
                self?.history.record(action: tool.title, sources: [url], outputs: [output])
                self?.toast.message(String(localized: "Saved"), detail: output.lastPathComponent, outputs: [output])
                self?.revealIfNeeded([output])
                close()
            } catch {
                self?.toast.message(tool.title, detail: error.localizedDescription, isError: true)
            }
        }

        switch tool {
        case .crop:
            editors.open(size: CGSize(width: 520, height: 660)) { close in
                CropEditor(image: image, onSave: { save("Cropped", false, $0, close) }, onClose: close)
            }
        case .addBackground:
            editors.open(size: CGSize(width: 560, height: 720)) { close in
                BackgroundEditor(image: image, onSave: { save("With Background", true, $0, close) }, onClose: close)
            }
        case .edit:
            editors.open(size: CGSize(width: 540, height: 680)) { close in
                AdjustEditor(image: image, onSave: { save("Edited", false, $0, close) }, onClose: close)
            }
        case .annotate:
            editors.open(size: CGSize(width: 620, height: 680)) { close in
                AnnotateEditor(image: image, onSave: { save("Annotated", false, $0, close) }, onClose: close)
            }
        case .redact:
            editors.open(size: CGSize(width: 620, height: 680)) { close in
                RedactEditor(image: image, onSave: { save("Redacted", false, $0, close) }, onClose: close)
            }
        case .compress, .metadata, .resize, .merge, .pages, .split, .cutOut, .copyText, .animate, .secure, .shelf:
            break
        }
    }

    private static func cleanOutputURL(for url: URL) -> URL {
        let type = url.contentType.flatMap { ImageFile.canWrite($0) ? $0 : nil } ?? .png
        return OutputNaming.url(for: url, suffix: "Clean", fileExtension: type.preferredFilenameExtension ?? "png")
    }

    private func saveCopy(of url: URL, write: (URL) throws -> Void) {
        let output = Self.cleanOutputURL(for: url)
        do {
            try write(output)
            history.record(action: String(localized: "Remove Metadata"), sources: [url], outputs: [output])
            toast.message(String(localized: "Saved"), detail: output.lastPathComponent, outputs: [output])
            revealIfNeeded([output])
        } catch {
            toast.message(String(localized: "Couldn't save"), detail: error.localizedDescription, isError: true)
        }
    }
}
