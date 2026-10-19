import AppKit
import SwiftUI

@MainActor
final class ToastModel: ObservableObject {
    enum Status { case working, done, failed }

    @Published var title = ""
    @Published var detail = ""
    @Published var progress: Double = 0
    @Published var status: Status = .working
    @Published var outputs: [URL] = []
    @Published var isPresented = false

    var isError: Bool { status == .failed }
}

struct ToastView: View {
    @ObservedObject var model: ToastModel
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.9))
                    .lineLimit(1)
                Text(model.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(model.isError ? Color.red.opacity(0.85) : Theme.label)
                    .lineLimit(2)
                    .contentTransition(.numericText())
                if model.status == .working {
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .tint(Theme.accent)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)

            if model.status == .done, let first = model.outputs.first {
                ResultChip(url: first, count: model.outputs.count)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassEdge, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 6))
        .overlay(alignment: .topLeading) {
            CloseButton(action: onClose)
                .scaleEffect(0.85)
                .offset(x: -6, y: -6)
                .opacity(hovering ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(Theme.spring, value: model.status)
        .scaleEffect(model.isPresented ? 1 : 0.92, anchor: .leading)
        .opacity(model.isPresented ? 1 : 0)
        .offset(y: model.isPresented ? 0 : 8)
        .animation(Theme.spring, value: model.isPresented)
        .padding(20)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.status {
        case .working:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white, Theme.accent)
                .symbolEffect(.bounce, value: model.status)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white, Color.red.opacity(0.85))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Thumbnail of the result: drag it anywhere, or click to reveal it in Finder.
struct ResultChip: View {
    let url: URL
    let count: Int
    @State private var hovering = false

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: 34, height: 34)
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Theme.accent))
                        .offset(x: 5, y: -3)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 9).fill(hovering ? Theme.surfaceStrong : Color.clear))
            .scaleEffect(hovering ? 1.08 : 1)
            .animation(Theme.snappy, value: hovering)
            .onHover { hovering = $0 }
            .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            .onDrag { NSItemProvider(object: url as NSURL) }
            .help("Drag the result anywhere, or click to show it in Finder")
    }
}

/// "Converting to JPG — 1 of 1 saved" progress card near the pointer.
@MainActor
final class ToastController {
    private let model = ToastModel()
    private var hideWork: DispatchWorkItem?
    private var hovering = false
    private lazy var panel: FloatingPanel = {
        let panel = FloatingPanel(size: CGSize(width: 360, height: 130))
        let host = NSHostingView(rootView: ToastView(model: model) { [weak self] in self?.hide() }
            .onHover { [weak self] inside in
                MainActor.assumeIsolated { self?.hoverChanged(inside) }
            })
        host.frame = CGRect(x: 0, y: 0, width: 360, height: 130)
        panel.contentView = host
        return panel
    }()

    func begin(_ title: String, total: Int) {
        hideWork?.cancel()
        model.title = title
        model.detail = "0 of \(total) saved"
        model.progress = 0
        model.status = .working
        model.outputs = []
        present()
    }

    func update(saved: Int, total: Int) {
        withAnimation {
            model.detail = "\(saved) of \(total) saved"
            model.progress = total > 0 ? Double(saved) / Double(total) : 1
        }
    }

    func finish(detail: String? = nil, isError: Bool = false, outputs: [URL] = []) {
        if let detail { model.detail = detail }
        model.outputs = outputs
        if !isError, detail == nil, let first = outputs.first {
            model.detail = outputs.count == 1 ? first.lastPathComponent : "\(outputs.count) files saved"
        }
        withAnimation { model.progress = 1 }
        model.status = isError ? .failed : .done
        // Results stay a little longer so there's time to drag them out.
        scheduleHide(after: isError ? 4.5 : (outputs.isEmpty ? 2.2 : 4))
    }

    func message(_ title: String, detail: String, isError: Bool = false, outputs: [URL] = []) {
        begin(title, total: 1)
        finish(detail: detail, isError: isError, outputs: outputs)
    }

    private func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x + 30, y: mouse.y - size.height / 2)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        if !panel.isVisible || !model.isPresented { panel.setFrameOrigin(origin) }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        model.isPresented = true
    }

    /// Keeps the toast up while the pointer rests on it.
    private func hoverChanged(_ inside: Bool) {
        hovering = inside
        if inside {
            hideWork?.cancel()
        } else if model.status != .working {
            scheduleHide(after: 1.5)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        guard !hovering else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hide() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        model.isPresented = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.model.isPresented else { return }
                self.panel.orderOut(nil)
            }
        }
    }
}
