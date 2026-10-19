import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.40, blue: 0.10)
    static let petal = Color(red: 1.0, green: 0.91, blue: 0.78)
    static let hub = Color(red: 1.0, green: 0.95, blue: 0.88)
    static let ink = Color(red: 0.24, green: 0.15, blue: 0.09)
    static let label = Color(red: 0.85, green: 0.33, blue: 0.08)
    static let field = Color.white.opacity(0.85)

    static let panelBackground = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.80, blue: 0.45),
            Color(red: 1.0, green: 0.64, blue: 0.32),
            Color(red: 0.99, green: 0.56, blue: 0.30),
        ],
        startPoint: .top,
        endPoint: .bottom)
}

/// Orange capsule segmented control used across the editors ("Free | 1:1 | 16:9 …").
struct PillPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Theme.ink.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(selected ? Theme.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.35)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.ink.opacity(0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.5 : 0.35)))
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
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.label)
                .frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(Theme.accent)
            Text(unit.isEmpty ? format(value) : "\(format(value)) \(unit)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ink.opacity(0.7))
                .frame(width: 56, alignment: .trailing)
        }
    }
}

/// Shared chrome for editor windows: close button, title, content, footer.
struct EditorScaffold<Content: View, Footer: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.label)
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.ink.opacity(0.6))
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().overlay(Color.white.opacity(0.4))

            content
                .padding(18)

            Divider().overlay(Color.white.opacity(0.4))

            footer
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .background(Theme.panelBackground)
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
