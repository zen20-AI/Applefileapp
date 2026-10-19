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

    func start() {
        dragMonitor.onDragBegan = { [weak self] urls, location in
            self?.ring.show(urls: urls, near: location, interaction: .drag)
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.ring.hide()
        }
        dragMonitor.start()

        ring.model.onAction = { [weak self] action, urls in
            self?.ring.hide()
            // Leave the drop callback before doing any work.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.perform(action, on: urls) }
            }
        }
        ring.model.onDismiss = { [weak self] in self?.ring.hide() }
    }

    /// Menu bar entry point: pick files, then use the ring with clicks.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        ring.show(urls: panel.urls, near: nil, interaction: .click)
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

        case .tool(let tool):
            guard let url = urls.first(where: { FileKind(url: $0) == .image }) else { return }
            openEditor(tool, for: url)
        }
    }

    // MARK: - Batch jobs

    private func runBatch(title: String, urls: [URL], work: @escaping (URL) throws -> [URL]) {
        guard !urls.isEmpty else { return }
        toast.begin(title, total: urls.count)

        DispatchQueue.global(qos: .userInitiated).async {
            var saved = 0
            var failures: [String] = []
            for url in urls {
                do {
                    _ = try work(url)
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
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.toast.finish(detail: summary, isError: failed) }
            }
        }
    }

    // MARK: - Editors

    private func openEditor(_ tool: Tool, for url: URL) {
        if tool == .metadata {
            editors.open(size: CGSize(width: 560, height: 560)) { close in
                MetadataView(url: url, onStrip: { [weak self] in
                    self?.saveCopy(of: url, suffix: "Clean") { output in
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
                self?.toast.message("Saved", detail: output.lastPathComponent)
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
        case .compress, .metadata:
            break
        }
    }

    private func saveCopy(of url: URL, suffix: String, write: (URL) throws -> Void) {
        let type = url.contentType.flatMap { ImageFile.canWrite($0) ? $0 : nil } ?? .png
        let output = OutputNaming.url(for: url, suffix: suffix, fileExtension: type.preferredFilenameExtension ?? "png")
        do {
            try write(output)
            toast.message("Saved", detail: output.lastPathComponent)
        } catch {
            toast.message("Couldn't save", detail: error.localizedDescription, isError: true)
        }
    }
}
