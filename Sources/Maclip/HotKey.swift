import AppKit
import Carbon.HIToolbox

/// A keyboard shortcut: a key plus at least one of ⌘, ⌃ or ⌥ (⇧ may be added).
/// The default is ⇧⌘V, the closest Mac equivalent of Win+V.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    /// Raw value of the NSEvent.ModifierFlags (⌘ ⌃ ⌥ ⇧ only).
    var modifiers: UInt
    /// What the key is called on the keyboard, e.g. "V", "Space", "F5".
    var key: String

    static let `default` = KeyCombo(keyCode: UInt32(kVK_ANSI_V),
                                    modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "V")

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.relevantFlags) }

    /// Shown in the UI in the usual macOS order, e.g. "⌃⌥⇧⌘V".
    var title: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    /// The character for an NSMenuItem key equivalent, when the key is a plain character.
    var menuKeyEquivalent: String? {
        key.count == 1 ? key.lowercased() : nil
    }

    /// The combination typed in `event`, or nil if it has no ⌘/⌃/⌥ (a bare key or ⇧+key
    /// would stop that key from typing anywhere on the Mac).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.relevantFlags)
        guard !flags.isDisjoint(with: [.command, .control, .option]) else { return nil }
        let code = Int(event.keyCode)
        guard let key = Self.specialKeyNames[code]
                ?? event.characters(byApplyingModifiers: [])?.uppercased().nilIfBlank else { return nil }
        self.init(keyCode: UInt32(code), modifiers: flags.rawValue, key: key)
    }

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

/// A system-wide hotkey registered through Carbon's RegisterEventHotKey. Unlike a global
/// NSEvent monitor this needs no Accessibility permission, and it swallows the keystroke.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Registers the shortcut, replacing any previous one. Returns false if macOS refused
    /// it (usually because the system or another app reserves that combination).
    @discardableResult
    func register(_ combo: KeyCombo) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // 'CLIP'
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Maclip: could not register hotkey %@ (OSStatus %d)", combo.title, status)
            hotKeyRef = nil
        }
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
