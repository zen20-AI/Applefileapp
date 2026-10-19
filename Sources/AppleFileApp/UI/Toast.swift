import AppKit
import SwiftUI

@MainActor
final class ToastModel: ObservableObject {
    @Published var title = ""
    @Published var detail = ""
    @Published var progress: Double = 0
    @Published var isError = false
}

struct ToastView: View {
    @ObservedObject var model: ToastModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.label)
                }
                .buttonStyle(.plain)
                Text(model.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                    .lineLimit(1)
            }
            Text(model.detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.isError ? Color.red.opacity(0.8) : Theme.ink.opacity(0.6))
                .lineLimit(2)
            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.hub.opacity(0.75)))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4))
        .padding(20)
    }
}

/// "Converting to JPG — 1 of 1 saved" progress card near the pointer.
@MainActor
final class ToastController {
    private let model = ToastModel()
    private var hideWork: DispatchWorkItem?
    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: CGSize(width: 340, height: 130))
        let host = NSHostingView(rootView: ToastView(model: model) { [weak self] in self?.hide() })
        host.frame = CGRect(x: 0, y: 0, width: 340, height: 130)
        panel.contentView = host
        return panel
    }()

    func begin(_ title: String, total: Int) {
        hideWork?.cancel()
        model.title = title
        model.detail = "0 of \(total) saved"
        model.progress = 0
        model.isError = false
        present()
    }

    func update(saved: Int, total: Int) {
        model.detail = "\(saved) of \(total) saved"
        withAnimation { model.progress = total > 0 ? Double(saved) / Double(total) : 1 }
    }

    func finish(detail: String? = nil, isError: Bool = false) {
        if let detail { model.detail = detail }
        model.isError = isError
        withAnimation { model.progress = 1 }
        scheduleHide(after: isError ? 4 : 2.2)
    }

    func message(_ title: String, detail: String, isError: Bool = false) {
        begin(title, total: 1)
        finish(detail: detail, isError: isError)
    }

    private func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 30, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        if !panel.isVisible { panel.setFrameOrigin(origin) }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}
