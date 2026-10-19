import AppKit
import FileAppCore
import SwiftUI
import UniformTypeIdentifiers

/// Hosts editor sheets in their own frameless-looking windows.
@MainActor
final class EditorWindows {
    private var windows: [NSWindow] = []

    func open<Content: View>(size: CGSize, @ViewBuilder content: (_ close: @escaping () -> Void) -> Content) {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }

        let close: () -> Void = { [weak window] in window?.close() }
        window.contentView = NSHostingView(rootView: content(close).frame(width: size.width, height: size.height))

        _ = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                self?.windows.removeAll { $0 === note.object as? NSWindow }
            }
        }

        windows.append(window)
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// Saves an editor result next to its source as "<name> <suffix>.<ext>".
enum EditorOutput {
    static func save(_ image: CGImage, source: URL, suffix: String, forcePNG: Bool = false) throws -> URL {
        let sourceType = source.contentType
        let type = (!forcePNG && ImageFile.canWrite(sourceType)) ? sourceType! : .png
        let output = OutputNaming.url(for: source, suffix: suffix, fileExtension: type.preferredFilenameExtension ?? "png")
        let lossy = [UTType.jpeg, .heic, .heif].contains { type.conforms(to: $0) }
        try ImageFile.write(image, to: output, type: type, quality: lossy ? 0.92 : nil)
        return output
    }
}
