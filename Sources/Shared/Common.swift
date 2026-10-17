import AppKit

public enum CaptureError: LocalizedError {
    case noDisplay
    case encodeFailed
    case clipboardFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "Couldn't find the display to capture."
        case .encodeFailed: return "Couldn't encode the image."
        case .clipboardFailed: return "Couldn't copy the image to the clipboard."
        case .writeFailed(let reason): return "Couldn't save the file: \(reason)"
        }
    }
}

/// The app and window that were frontmost when the hotkey was pressed.
public struct WindowInfo: Sendable {
    public let app: String?
    public let title: String?

    public init(app: String?, title: String?) {
        self.app = app
        self.title = title
    }

    public static func current() -> WindowInfo {
        guard let front = NSWorkspace.shared.frontmostApplication else { return WindowInfo(app: nil, title: nil) }
        let pid = front.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // The list is ordered front to back, so the first normal window of the app is its active one.
        let title = windows.lazy
            .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { $0[kCGWindowName as String] as? String }
            .first { !$0.isEmpty }
        return WindowInfo(app: front.localizedName, title: title)
    }
}

/// The capture shutter sound, honouring the on/off and volume settings.
@MainActor
public enum Shutter {
    private static let sound: NSSound? =
        NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
                byReference: true) ?? NSSound(named: "Tink")

    public static func play() {
        guard Settings.shutterEnabled, Settings.shutterVolume > 0, let sound else { return }
        sound.stop()
        sound.volume = Float(Settings.shutterVolume) / 100
        sound.play()
    }
}
