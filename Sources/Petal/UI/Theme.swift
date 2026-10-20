import AppKit
import SwiftUI

/// Minimal, translucent look: system glass materials, adaptive ink and one mint accent.
enum Theme {
    /// Mint: deep enough for white text, with a lighter tone for gradients.
    static let accent = Color(red: 0.10, green: 0.74, blue: 0.60)
    static let accentSoft = Color(red: 0.42, green: 0.92, blue: 0.78)
    static let accentGradient = LinearGradient(colors: [accentSoft, accent], startPoint: .top, endPoint: .bottom)

    /// Text and glyphs (adapts to light / dark).
    static let ink = Color.primary
    /// Section titles and quiet labels.
    static let label = Color.secondary
    /// Faint fills layered on glass.
    static let surface = Color.primary.opacity(0.05)
    static let surfaceStrong = Color.primary.opacity(0.09)
    static let field = Color.primary.opacity(0.06)
    static let hairline = Color.primary.opacity(0.10)
    /// Light edge highlight that makes glass read as glass.
    static let glassEdge = LinearGradient(
        colors: [Color.white.opacity(0.55), Color.white.opacity(0.08)],
        startPoint: .top, endPoint: .bottom)

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.85)
}

/// An NSVisualEffectView behind SwiftUI content, blending with what's behind the window.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// Capsule segmented control with a sliding selection ("Free | 1:1 | 16:9 …").
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(Theme.snappy) { selection = option }
                } label: {
                    Text(LocalizedStringKey(title(option)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Theme.ink.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(Theme.accentGradient)
                                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration) { hovering in
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Capsule().fill(Theme.accentGradient).brightness(hovering ? 0.05 : 0))
                .shadow(color: Theme.accent.opacity(hovering ? 0.45 : 0.25), radius: hovering ? 8 : 4, y: 2)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverLabel(configuration: configuration) { hovering in
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(hovering ? Theme.surfaceStrong : Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
    }
}

/// Shared hover + press feedback for the button styles.
private struct HoverLabel<Content: View>: View {
    let configuration: ButtonStyleConfiguration
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content(hovering && isEnabled)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }
}

/// Labeled slider row with a trailing value readout ("Padding ——o—— 609 px").
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit = "px"
    var format: (Double) -> String = { String(Int($0.rounded())) }

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(Theme.accent)
                .controlSize(.small)
            Text(unit.isEmpty ? format(value) : "\(format(value)) \(unit)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ink.opacity(0.6))
                .frame(width: 56, alignment: .trailing)
                .contentTransition(.numericText())
        }
    }
}

/// Shared chrome for editor windows: close button, title, content, footer, all on glass.
struct EditorScaffold<Content: View, Footer: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink.opacity(0.85))
                HStack {
                    CloseButton(action: onClose)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            content
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
        .background(GlassBackground(material: .hudWindow))
        .scaleEffect(appeared ? 1 : 0.97)
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(Theme.spring) { appeared = true } }
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Color.white : Theme.ink.opacity(0.55))
                .frame(width: 20, height: 20)
                .background(Circle().fill(hovering ? Color.red.opacity(0.85) : Theme.surfaceStrong))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Aspect-fit placement of an image inside a container.
func fittedRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(
        x: (container.width - size.width) / 2,
        y: (container.height - size.height) / 2,
        width: size.width,
        height: size.height)
}

extension CGImage {
    var size: CGSize { CGSize(width: width, height: height) }
    var nsImage: NSImage { NSImage(cgImage: self, size: size) }
}
