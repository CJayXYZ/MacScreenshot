import AppKit
import ScreenCaptureKit
import Shared

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
