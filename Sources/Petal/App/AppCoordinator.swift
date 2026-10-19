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
    }

    private func applySettings() {
        dragMonitor.activationDistance = settings.activationDistance
        if settings.ringEnabled { dragMonitor.start() } else { dragMonitor.stop() }
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
            runBatch(title: "Converting to \(format.label)", urls: eligible) { url in
                try Converter.convert(url, to: format)
            }

        case .tool(.compress):
            let eligible = urls.filter(Compressor.canCompress)
            runBatch(title: "Compressing", urls: eligible) { url in
                [try Compressor.compress(url).output]
            }

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
                    self?.runBatch(title: "Resizing", urls: images) { [try Resizer.resize($0, mode: mode)] }
                }, onClose: close)
            }

        case .tool(let tool):
            guard let url = urls.first(where: { FileKind(url: $0) == .image }) else { return }
            openEditor(tool, for: url)
        }
    }

    /// Removes EXIF/GPS/TIFF data from every image in one pass.
    func stripMetadata(_ urls: [URL]) {
        let images = urls.filter { FileKind(url: $0) == .image }
        runBatch(title: "Removing Metadata", urls: images) { url in
            let output = Self.cleanOutputURL(for: url)
            try ImageFile.writeWithoutMetadata(from: url, to: output)
            return [output]
        }
    }

    func merge(_ urls: [URL]) {
        let inputs = urls.filter(PDFMerger.canMerge)
        guard inputs.count > 1 else {
            toast.message("Merge PDF", detail: "Choose at least two images or PDFs", isError: true)
            return
        }
        runJob(title: "Merging \(inputs.count) files", action: "Merge PDF", sources: inputs) {
            [try PDFMerger.merge(inputs)]
        }
    }

    // MARK: - PDF pages

    /// Opens the page organizer: reorder, rotate, delete, extract or split pages of PDFs and images.
    func organizePages(_ urls: [URL]) {
        let inputs = urls.filter(PDFMerger.canMerge)
        guard !inputs.isEmpty else {
            toast.message("Pages", detail: "Choose PDFs or images", isError: true)
            return
        }
        let model: PagesModel
        do {
            model = try PagesModel(urls: inputs)
        } catch {
            toast.message("Pages", detail: error.localizedDescription, isError: true)
            return
        }
        editors.open(size: CGSize(width: 820, height: 640), resizable: true) { close in
            PagesEditor(
                model: model,
                onSave: { [weak self] pages, name in
                    close()
                    self?.writePages(pages, name: name, suffix: "Edited", action: "Organize Pages")
                },
                onExtract: { [weak self] pages, name in
                    self?.writePages(pages, name: name, suffix: "Extract", action: "Extract Pages")
                },
                onSplit: { [weak self] pages, mode, name in
                    self?.runJob(title: "Splitting \(pages.count) pages", action: "Split PDF", sources: Array(Set(pages.map(\.source)))) {
                        try PDFPages.split(pages, mode: mode, name: name)
                    }
                },
                onClose: close)
        }
    }

    /// Splits every PDF into single pages (or another split mode).
    func splitPages(_ urls: [URL], mode: SplitMode = .everyPage) {
        let pdfs = urls.filter { FileKind(url: $0) == .pdf }
        runBatch(title: "Splitting PDF", urls: pdfs) { try PDFPages.split($0, mode: mode) }
    }

    private func writePages(_ pages: [PageRef], name: URL, suffix: String, action: String) {
        let sources = Array(Set(pages.map(\.source)))
        runJob(title: "Saving \(pages.count) pages", action: action, sources: sources) {
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
            toast.message(title, detail: "Nothing here can be processed this way", isError: true)
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

    private func revealIfNeeded(_ outputs: [URL]) {
        guard settings.revealAfterSaving, !outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(outputs)
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
                self?.toast.message("Saved", detail: output.lastPathComponent, outputs: [output])
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
        case .compress, .metadata, .resize, .merge, .pages, .split:
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
            history.record(action: "Remove Metadata", sources: [url], outputs: [output])
            toast.message("Saved", detail: output.lastPathComponent, outputs: [output])
            revealIfNeeded([output])
        } catch {
            toast.message("Couldn't save", detail: error.localizedDescription, isError: true)
        }
    }
}
