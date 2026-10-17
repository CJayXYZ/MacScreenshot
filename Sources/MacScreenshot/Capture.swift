import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    case encodeFailed
    case clipboardFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Couldn't find the display to capture."
        case .encodeFailed: return "Couldn't encode the image."
        case .clipboardFailed: return "Couldn't copy the image to the clipboard."
        case .writeFailed(let reason): return "Couldn't save the file: \(reason)"
        }
    }
}

/// The app and window that were frontmost when the hotkey was pressed.
struct WindowInfo {
    let app: String?
    let title: String?

    static func current() -> WindowInfo {
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

@MainActor
final class Capturer {
    private var displays: [CGDirectDisplayID: SCDisplay] = [:]

    static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// Display list changes (monitor plugged/unplugged) invalidate the cache.
    func invalidate() { displays = [:] }

    func capture(screen: NSScreen) async throws -> CGImage {
        guard let id = Self.displayID(of: screen) else { throw CaptureError.noDisplay }
        let display = try await display(for: id)

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(screen.frame.width * scale)
        config.height = Int(screen.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func display(for id: CGDirectDisplayID) async throws -> SCDisplay {
        if let cached = displays[id] { return cached }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        displays = Dictionary(content.displays.map { ($0.displayID, $0) }, uniquingKeysWith: { a, _ in a })
        guard let display = displays[id] else { throw CaptureError.noDisplay }
        return display
    }
}
