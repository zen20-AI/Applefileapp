import AppKit
import SwiftUI

/// Borderless panel that never takes focus, so it can pop up mid-drag over any app.
final class FloatingPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class RingController {
    let model = RingModel()
    private lazy var panel: FloatingPanel = {
        let side = RingModel.diameter + 40
        let panel = FloatingPanel(size: CGSize(width: side, height: side))
        let host = NSHostingView(rootView: RingView(model: model).frame(width: side, height: side))
        host.frame = CGRect(x: 0, y: 0, width: side, height: side)
        panel.contentView = host
        return panel
    }()

    private(set) var isVisible = false
    private var clickOutsideMonitor: Any?

    /// Shows the ring beside `point` (screen coordinates), or centered on screen when nil.
    func show(urls: [URL], near point: NSPoint?, interaction: RingInteraction) {
        model.configure(urls: urls, interaction: interaction)

        let size = panel.frame.size
        let anchor = point ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)

        var origin: NSPoint
        if let point {
            // Open to the right of the cursor so the pointer starts outside the petals.
            origin = NSPoint(x: point.x + 50, y: point.y - size.height / 2)
            if origin.x + size.width > visible.maxX {
                origin.x = point.x - 50 - size.width
            }
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        isVisible = true

        if interaction == .click {
            clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if !self.isVisible { panel.orderOut(nil) }
            }
        })
        model.updateHover(nil)
    }
}
