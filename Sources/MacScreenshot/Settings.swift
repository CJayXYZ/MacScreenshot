import Foundation

enum ImageFormat: String {
    case png, jpeg

    var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// User preferences, persisted in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    static var format: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: "format") }
    }

    /// JPEG quality in percent, 0...100 in steps of 5.
    static var jpegQuality: Int {
        get { (defaults.object(forKey: "jpegQuality") as? Int) ?? 85 }
        set { defaults.set(min(100, max(0, newValue)), forKey: "jpegQuality") }
    }

    static var startAtLogin: Bool {
        get { (defaults.object(forKey: "startAtLogin") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "startAtLogin") }
    }

    static var shutterEnabled: Bool {
        get { (defaults.object(forKey: "shutterEnabled") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "shutterEnabled") }
    }

    /// Shutter volume in percent, 0...100 in steps of 5.
    static var shutterVolume: Int {
        get { (defaults.object(forKey: "shutterVolume") as? Int) ?? 100 }
        set { defaults.set(min(100, max(0, newValue)), forKey: "shutterVolume") }
    }

    /// Custom save folder; nil means the macOS Screenshots folder.
    static var saveFolder: String? {
        get { defaults.string(forKey: "saveFolder") }
        set { defaults.set(newValue, forKey: "saveFolder") }
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
        action == .capture ? "shortcut.capture" : "shortcut.lastRegion"
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
