import AppKit
import Carbon.HIToolbox
import Shared

/// A user-assignable global keyboard shortcut.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    /// NSEvent.ModifierFlags raw value, limited to ⌃ ⌥ ⇧ ⌘.
    var modifiers: UInt
    /// The key as shown to people: "X", "F5", "Space", "→".
    var key: String

    static let captureDefault = Shortcut(keyCode: UInt32(kVK_ANSI_X),
                                         modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue, key: "X")
    static let lastRegionDefault = Shortcut(keyCode: UInt32(kVK_ANSI_X),
                                            modifiers: NSEvent.ModifierFlags([.command, .shift, .control]).rawValue, key: "X")
    static let editLastDefault = Shortcut(keyCode: UInt32(kVK_ANSI_X),
                                          modifiers: NSEvent.ModifierFlags([.command, .shift, .option]).rawValue, key: "X")

    private static let allowedFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Builds a shortcut from a key press. Nil unless it uses ⌘, ⌥ or ⌃ (Shift alone would
    /// steal ordinary typing).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(Self.allowedFlags)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        keyCode = UInt32(event.keyCode)
        modifiers = flags.rawValue
        key = Self.specialKeys[Int(event.keyCode)]
            ?? event.characters(byApplyingModifiers: [])?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "?"
        if key.isEmpty { key = "?" }
    }

    init(keyCode: UInt32, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return UInt32(m)
    }

    /// "⌥⇧⌘X", in Apple's modifier order.
    var display: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + key
    }

    /// Menu items can only show single-character keys.
    var menuKeyEquivalent: String { key.count == 1 ? key.lowercased() : "" }

    private static let specialKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    ]
}
