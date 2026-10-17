import Foundation
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

    static func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key(for: action))
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
