import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut (Carbon hot key: works in every app, needs no permission).
@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    /// ⌥⌘P by default.
    init(keyCode: Int = kVK_ANSI_P, modifiers: Int = optionKey | cmdKey, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
            return noErr
        }, 1, &spec, context, &handler)
        let id = EventHotKeyID(signature: OSType(0x5045_544C), id: 1) // "PETL"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }

    static let displayString = "⌥⌘P"
}

/// The files selected in the frontmost Finder window (asks for Automation permission the first time).
enum FinderSelection {
    static func urls() -> [URL] {
        let source = """
        tell application "Finder"
            set output to ""
            repeat with anItem in (get selection)
                set output to output & POSIX path of (anItem as alias) & linefeed
            end repeat
            return output
        end tell
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else { return [] }
        return result.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
}
