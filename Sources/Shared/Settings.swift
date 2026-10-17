import Foundation

public enum ImageFormat: String, Sendable {
    case png, jpeg

    public var fileExtension: String { self == .png ? "png" : "jpg" }
}

/// Preferences shared by the capture app and the editor. Both read and write the capture
/// app's preferences domain, so the editor sees the same JPEG quality, shutter and folder.
/// App-only settings (shortcuts, start at login…) are extensions in the app target.
public enum Settings {
    public static let mainBundleID = "io.github.cjayxyz.MacScreenshot"

    public static let defaults: UserDefaults =
        Bundle.main.bundleIdentifier == mainBundleID ? .standard : (UserDefaults(suiteName: mainBundleID) ?? .standard)

    public static var format: ImageFormat {
        get { ImageFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .png }
        set { defaults.set(newValue.rawValue, forKey: "format") }
    }

    /// JPEG quality in percent, 0...100 in steps of 5.
    public static var jpegQuality: Int {
        get { (defaults.object(forKey: "jpegQuality") as? Int) ?? 85 }
        set { defaults.set(min(100, max(0, newValue)), forKey: "jpegQuality") }
    }

    public static var shutterEnabled: Bool {
        get { (defaults.object(forKey: "shutterEnabled") as? Bool) ?? true }
        set { defaults.set(newValue, forKey: "shutterEnabled") }
    }

    /// Shutter volume in percent, 0...100 in steps of 5.
    public static var shutterVolume: Int {
        get { (defaults.object(forKey: "shutterVolume") as? Int) ?? 50 }
        set { defaults.set(min(100, max(0, newValue)), forKey: "shutterVolume") }
    }

    /// Custom save folder; nil means the macOS Screenshots folder.
    public static var saveFolder: String? {
        get { defaults.string(forKey: "saveFolder") }
        set { defaults.set(newValue, forKey: "saveFolder") }
    }

    /// The most recently saved capture (or edit), opened by "Edit Last Capture".
    public static var lastCapturePath: String? {
        get { defaults.string(forKey: "lastCapturePath") }
        set { defaults.set(newValue, forKey: "lastCapturePath") }
    }
}
