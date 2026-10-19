import AppKit

/// Detects file drags anywhere on screen (e.g. from Finder or the Desktop).
///
/// A global `leftMouseDragged` monitor notices drags; the system drag pasteboard's
/// change count tells a new drag session apart from ordinary mouse drags.
@MainActor
final class DragMonitor {
    var onDragBegan: (([URL], NSPoint) -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragStart: NSPoint?
    private var isTracking = false
    private var releaseTimer: Timer?

    /// Distance the pointer must travel before the ring appears, so quick drags pass by untouched.
    var activationDistance: CGFloat = 24

    func start() {
        guard monitors.isEmpty else { return }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseReleased() }
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        releaseTimer?.invalidate()
    }

    private func mouseDragged() {
        guard !isTracking else { return }
        let location = NSEvent.mouseLocation
        let pasteboard = NSPasteboard(name: .drag)

        // Remember where the gesture began; the drag session usually starts a few points in.
        if dragStart == nil { dragStart = location }
        guard pasteboard.changeCount != lastChangeCount, let start = dragStart,
              hypot(location.x - start.x, location.y - start.y) >= activationDistance
        else { return }
        lastChangeCount = pasteboard.changeCount

        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }

        isTracking = true
        onDragBegan?(urls, location)

        // Global mouse-up events are not always delivered while a drag session owns the mouse,
        // so also poll the button state.
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if NSEvent.pressedMouseButtons & 1 == 0 { self?.mouseReleased() }
            }
        }
    }

    private func mouseReleased() {
        dragStart = nil
        guard isTracking else { return }
        isTracking = false
        releaseTimer?.invalidate()
        releaseTimer = nil
        // Let a drop on the ring finish before it disappears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated { self?.onDragEnded?() }
        }
    }
}
