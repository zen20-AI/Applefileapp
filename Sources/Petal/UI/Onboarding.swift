import AppKit
import SwiftUI

/// First-launch welcome: what Petal does, folder access, and where to find it.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        for button in [NSWindow.ButtonType.miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = true
        }
        window.contentView = NSHostingView(rootView: OnboardingView { [weak window] in window?.close() }
            .frame(width: 520, height: 500))
        return window
    }
}

struct OnboardingView: View {
    let onDone: () -> Void
    @State private var step = 0
    @ObservedObject private var access = FolderAccess.shared
    private let steps = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcome.transition(slide)
                case 1: folders.transition(slide)
                default: shortcuts.transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.top, 40)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? Theme.accent : Theme.surfaceStrong)
                            .frame(width: index == step ? 18 : 6, height: 6)
                    }
                }
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation(Theme.spring) { step -= 1 } }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Button(step == steps - 1 ? "Start Using Petal" : "Continue") {
                    if step == steps - 1 { onDone() } else { withAnimation(Theme.spring) { step += 1 } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .background(GlassBackground(material: .hudWindow))
        .animation(Theme.spring, value: step)
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(x: 30)), removal: .opacity.combined(with: .offset(x: -30)))
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 104, height: 104)
            Text("Welcome to Petal").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Start dragging any file and a ring of tools blooms beside the pointer. Drop it on a petal to convert, compress, read text, cut out, merge or split.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.label)
                .frame(maxWidth: 380)
            HStack(spacing: 18) {
                feature("hand.draw", "Drag")
                feature("circle.hexagongrid", "Drop on a petal")
                feature("checkmark.seal", "New file saved")
            }
            .padding(.top, 8)
        }
    }

    private var folders: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Allow access to your folders").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("macOS asks once for each folder. Allow them now and Petal can save next to your files without interrupting you later. Nothing ever leaves your Mac.")
                .foregroundStyle(Theme.label)
                .fixedSize(horizontal: false, vertical: true)
            FolderAccessList(access: access)
            HStack {
                Button(access.allGranted ? "All Allowed" : "Allow All") { access.requestAll() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(access.allGranted)
                Button("Full Disk Access…") { access.openFullDiskAccessSettings() }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("For external drives and every other folder: add Petal in System Settings")
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Always one step away").font(.system(size: 22, weight: .bold, design: .rounded))
            tip("menubar.rectangle", "Menu bar", "Click the petal icon at the top of the screen for quick controls, updates and Quit.")
            tip("command", "\(HotKey.displayString) in Finder", "Select files in Finder and press \(HotKey.displayString) to open the ring for them.")
            tip("contextualmenu.and.cursorarrow", "Right-click in Finder", "Quick Actions → Petal: Compress, Copy Text, Remove Background and more.")
            tip("tray.full", "Workspace", "Drop whole folders in to rename, convert or compress many files at once.")
        }
    }

    private func feature(_ symbol: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentGradient)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.surfaceStrong))
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.label)
        }
    }

    private func tip(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.surfaceStrong))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One row per protected folder with its state and an Allow button.
struct FolderAccessList: View {
    @ObservedObject var access: FolderAccess

    var body: some View {
        VStack(spacing: 2) {
            ForEach(access.folders.filter(access.exists)) { folder in
                let status = access.status[folder.id] ?? .unknown
                HStack(spacing: 10) {
                    Image(systemName: folder.symbol)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22)
                    Text(folder.title).font(.system(size: 13))
                    Spacer()
                    switch status {
                    case .granted:
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                    case .denied:
                        Button("Open Settings") { access.openFilesAndFoldersSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                            .help("Access was turned off. Turn it back on in System Settings → Privacy & Security → Files & Folders.")
                    case .unknown:
                        Button("Allow") { access.request(folder) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                .animation(Theme.snappy, value: status)
            }
        }
    }
}
