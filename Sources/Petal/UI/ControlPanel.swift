import AppKit
import FileAppCore
import SwiftUI

/// The glass panel that drops down from the menu bar icon: quick controls for the whole app.
struct ControlPanel: View {
    let coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var history: HistoryStore
    @ObservedObject private var updater = Updater.shared
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ringPill
            dropZone
            shortcuts
            if !history.recentOutputs.isEmpty { recents }
        }
        .padding(12)
        .frame(width: 320)
    }

    /// Title bar: name and status on the left, Update and Quit always one click away on the right.
    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("Petal").font(.system(size: 13, weight: .bold, design: .rounded))
                Text(version).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.label)
            }
            StatusPill(text: settings.ringEnabled ? String(localized: "Active") : String(localized: "Paused"),
                       active: settings.ringEnabled)
            Spacer()
            if updater.isConfigured {
                HeaderButton(symbol: "arrow.down.circle", title: String(localized: "Check for Updates")) {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            HeaderButton(symbol: "power", title: String(localized: "Quit Petal"), destructive: true) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// Big Control Center–style pill: tap anywhere to pause or resume the ring.
    private var ringPill: some View {
        PillButton(
            title: String(localized: "Drag Ring"),
            subtitle: settings.ringEnabled ? String(localized: "On · drag any file") : String(localized: "Off"),
            symbol: "circle.hexagongrid.fill",
            isOn: settings.ringEnabled,
            large: true
        ) {
            withAnimation(Theme.spring) { settings.ringEnabled.toggle() }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: isTargeted ? "circle.hexagongrid.circle.fill" : "circle.hexagongrid.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accentGradient)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isTargeted ? 1.15 : 1)
            Text(isTargeted ? "Release to open the ring" : "Drop files here")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.8))
            Text("or click to choose · \(HotKey.displayString) in Finder")
                .font(.system(size: 10))
                .foregroundStyle(Theme.label)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isTargeted ? Theme.accent.opacity(0.12) : Theme.surfaceStrong))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: isTargeted ? [] : [6, 5]))
                .foregroundStyle(isTargeted ? Theme.accent : Theme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture { coordinator.chooseFiles() }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            coordinator.showRing(for: urls, near: NSEvent.mouseLocation)
            return true
        } isTargeted: { targeted in withAnimation(Theme.snappy) { isTargeted = targeted } }
    }

    /// Round shortcuts, like the small buttons in Control Center.
    private var shortcuts: some View {
        HStack(spacing: 0) {
            RoundShortcut(title: String(localized: "Workspace"), symbol: "tray.full.fill") { coordinator.manager.show(section: .workspace) }
            RoundShortcut(title: String(localized: "Automation"), symbol: "bolt.fill") { coordinator.manager.show(section: .automation) }
            RoundShortcut(title: String(localized: "History"), symbol: "clock.fill") { coordinator.manager.show(section: .history) }
            RoundShortcut(title: String(localized: "Settings"), symbol: "gearshape.fill") { coordinator.manager.show(section: .settings) }
        }
        .padding(.vertical, 4)
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(history.totalOutputs) made").font(.system(size: 10)).foregroundStyle(Theme.label)
            }
            ForEach(history.recentOutputs.prefix(4), id: \.self) { url in
                RecentRow(url: url)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.surfaceStrong))
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return String(localized: "Version \(short)")
    }
}

/// Small circular icon button for the panel's title bar.
private struct HeaderButton: View {
    let symbol: String
    let title: String
    var destructive = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Theme.ink.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(Circle().fill(hovering ? (destructive ? Color.red.opacity(0.85) : Theme.accent) : Theme.surfaceStrong))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering = $0 && isEnabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

private struct RoundShortcut: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hovering ? Color.white : Theme.ink.opacity(0.8))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(hovering ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceStrong)))
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.ink.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
    }
}

/// Capsule button in the style of Control Center: a round icon badge and a label.
private struct PillButton: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var isOn = false
    var large = false
    let action: () -> Void
    @State private var hovering = false
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surfaceStrong))
                    Image(systemName: symbol)
                        .font(.system(size: large ? 15 : 12, weight: .semibold))
                        .foregroundStyle(isOn ? Color.white : Theme.ink.opacity(0.75))
                        .symbolEffect(.bounce, value: isOn)
                }
                .frame(width: large ? 38 : 28, height: large ? 38 : 28)
                .shadow(color: isOn ? Theme.accent.opacity(0.4) : .clear, radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: large ? 13 : 12, weight: .semibold))
                        .foregroundStyle(Theme.ink.opacity(0.9))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.label)
                            .contentTransition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, large ? 8 : 6)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity)
            .frame(height: large ? 54 : 40)
            .background(Capsule().fill(hovering ? Theme.surfaceStrong.opacity(1.6) : Theme.surfaceStrong))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
        }
        .buttonStyle(PressReportingStyle(pressed: $pressed))
        .onHover { hovering = $0 }
        .animation(Theme.snappy, value: hovering)
        .animation(Theme.snappy, value: pressed)
        .animation(Theme.spring, value: isOn)
    }
}

private struct PressReportingStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { pressed = configuration.isPressed }
    }
}

/// Small status capsule with a live dot ("● Active").
private struct StatusPill: View {
    let text: String
    let active: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.green : Theme.label)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle().stroke(Color.green.opacity(active ? 0.6 : 0), lineWidth: 2)
                        .scaleEffect(pulse ? 2.2 : 1)
                        .opacity(pulse ? 0 : 1))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.ink.opacity(0.75))
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.surfaceStrong))
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .animation(Theme.spring, value: active)
    }
}

private struct RecentRow: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 11))
                .foregroundStyle(Theme.label)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.surfaceStrong : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help("Click to show in Finder · drag to use it anywhere")
    }
}

/// Menu bar glyph: six tiny petals around a dot, drawn as a template image so it follows the menu bar's color.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setFill()
            for index in 0..<6 {
                let angle = CGFloat(index) * .pi / 3 + .pi / 2
                let petal = NSBezierPath(ovalIn: CGRect(x: -2.4, y: 3.2, width: 4.8, height: 5.4))
                var transform = AffineTransform(translationByX: center.x, byY: center.y)
                transform.rotate(byRadians: angle - .pi / 2)
                petal.transform(using: transform)
                petal.fill()
            }
            NSBezierPath(ovalIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
