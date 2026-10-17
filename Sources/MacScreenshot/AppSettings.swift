import AppKit
import Carbon.HIToolbox
import Shared

/// Settings only the capture app uses.
extension Settings {
    static var startAtLogin: Bool {
        get { (defaults.object(forKey: "startAtLogin") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "startAtLogin") }
    }

    static var hasSeenHelp: Bool {
        get { defaults.bool(forKey: "hasSeenHelp") }
        set { defaults.set(newValue, forKey: "hasSeenHelp") }
    }

    static func shortcut(for action: ShortcutAction) -> Shortcut {
        defaults.data(forKey: key(for: action)).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            ?? action.defaultShortcut
    }

    /// A shortcut equal to the default isn't stored, so a later change of defaults still applies.
    static func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        if shortcut.keyCode == action.defaultShortcut.keyCode, shortcut.modifiers == action.defaultShortcut.modifiers {
            defaults.removeObject(forKey: key(for: action))
        } else {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: key(for: action))
        }
    }

    /// 1.1.x stored defaults when "Reset" was pressed. 1.2 swapped the last-region (⌥) and edit (⌃)
    /// defaults, so a stored old default is dropped once, or it would clash with the new ones.
    static func migrateShortcutDefaults() {
        guard !defaults.bool(forKey: "shortcutsMigrated12") else { return }
        let old: [(ShortcutAction, NSEvent.ModifierFlags)] = [(.lastRegion, [.command, .shift, .option]),
                                                             (.editLast, [.command, .shift, .control])]
        for (action, flags) in old {
            let stored = defaults.data(forKey: key(for: action)).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            if let stored, stored.keyCode == UInt32(kVK_ANSI_X), stored.modifiers == flags.rawValue {
                defaults.removeObject(forKey: key(for: action))
            }
        }
        defaults.set(true, forKey: "shortcutsMigrated12")
    }

    private static func key(for action: ShortcutAction) -> String {
        switch action {
        case .capture: return "shortcut.capture"
        case .lastRegion: return "shortcut.lastRegion"
        case .editLast: return "shortcut.editLast"
        }
    }

    static var lastRegion: Region? {
        get { defaults.data(forKey: "lastRegion").flatMap { try? JSONDecoder().decode(Region.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "lastRegion") }
    }
}

/// A captured area in points, top-left origin, on a given display.
struct Region: Codable {
    var displayID: UInt32
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}
