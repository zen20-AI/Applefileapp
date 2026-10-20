import AppKit
import FileAppCore
import SwiftUI

/// Watch folders, the global shortcut, Finder Quick Actions and Shortcuts links.
struct AutomationView: View {
    @ObservedObject var watcher: FolderWatcher
    @ObservedObject var settings: AppSettings
    @State private var newAction: WatchRule.Action = .compress

    var body: some View {
        Form {
            Section {
                if watcher.rules.isEmpty {
                    Text("No watch folders yet. Add one and Petal handles new files there by itself — e.g. compress every screenshot, or convert downloads to JPG.")
                        .foregroundStyle(.secondary)
                }
                ForEach($watcher.rules) { $rule in
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.folder.lastPathComponent).fontWeight(.medium)
                            Text(rule.folderPath.abbreviatingWithTilde)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Picker("", selection: $rule.action) {
                            ForEach(WatchRule.Action.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                        Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Button {
                            withAnimation(Theme.spring) { watcher.rules.removeAll { $0.id == rule.id } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Stop watching this folder")
                    }
                }
                HStack {
                    Picker("New rule", selection: $newAction) {
                        ForEach(WatchRule.Action.allCases) { Text($0.title).tag($0) }
                    }
                    .frame(maxWidth: 300)
                    Spacer()
                    Button("Choose Folder…", action: addRule)
                }
            } header: {
                Text("Watch Folders")
            } footer: {
                Text("Only files added after a rule starts are processed. Results are saved as new files next to them.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("\(HotKey.displayString) opens the ring for files selected in Finder", isOn: $settings.hotKeyEnabled)
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("The first time, macOS asks to let Petal see Finder's selection.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("In Finder") {
                    Text("Right-click files → Quick Actions or Services → Petal")
                        .foregroundStyle(.secondary)
                }
                Button("Turn On Petal Actions…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Services") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("Finder Quick Actions")
            } footer: {
                Text("If they don't appear, turn on the Petal entries in System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Open the ring") { link("petal://ring") }
                LabeledContent("Run a tool") { link("petal://run?action=compress&path=/path/to/file.jpg") }
                Text("Actions: compress, compress-1mb (any size: compress-500kb, compress-2mb…), shelf, resize, cutOut, copyText, pages, split, merge, rename, workspace, convert-jpg, convert-png, convert-pdf…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Shortcuts & Scripts")
            } footer: {
                Text("Use “Open URLs” in the Shortcuts app, or `open \"petal://…\"` in Terminal.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Automation")
    }

    private func link(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(1)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
                .help("Copy")
        }
    }

    private func addRule() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Watch Folder")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        withAnimation(Theme.spring) { watcher.add(folder: url, action: newAction) }
    }
}

/// App language: follow macOS, or force English / Thai (takes effect after a restart).
struct LanguageSection: View {
    @State private var language = LanguageSection.current
    @State private var changed = false

    static var current: String {
        (UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String])?.first
            .map { $0.hasPrefix("th") ? "th" : "en" } ?? "system"
    }

    var body: some View {
        Section {
            Picker("Language", selection: $language) {
                Text("Same as macOS").tag("system")
                Text("English").tag("en")
                Text("ไทย").tag("th")
            }
            .onChange(of: language) {
                if language == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([language], forKey: "AppleLanguages")
                }
                changed = true
            }
            if changed {
                Button("Restart Petal to Apply") { Self.relaunch() }
            }
        } header: {
            Text("Language")
        }
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
