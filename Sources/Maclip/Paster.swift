import AppKit
import Carbon.HIToolbox

/// The synthetic Cmd+V used to paste into the previously focused app, and the permission it
/// needs. macOS only lets apps post keyboard events to other apps after the user enables them
/// in System Settings > Privacy & Security > Accessibility. These are the sandbox-compatible
/// CoreGraphics calls for that permission (the Accessibility API itself is off-limits to
/// sandboxed apps, which is why Maclip doesn't read the text cursor position).
enum Paster {
    static var isTrusted: Bool {
        #if DEBUG
        if let snapshotTrusted { return snapshotTrusted }
        #endif
        return CGPreflightPostEventAccess()
    }

    #if DEBUG
    /// Lets snapshot mode render the windows as if auto-paste were enabled.
    static var snapshotTrusted: Bool?
    #endif

    /// Shows the system prompt that adds Maclip to the Accessibility list (turned off) and
    /// offers to open System Settings. Returns true if access is already granted.
    @discardableResult
    static func requestTrust() -> Bool {
        CGRequestPostEventAccess()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Simulates Cmd+V in whatever app currently has keyboard focus.
    /// Returns false (and does nothing) without permission.
    @discardableResult
    static func pasteIntoFrontApp() -> Bool {
        guard isTrusted else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
