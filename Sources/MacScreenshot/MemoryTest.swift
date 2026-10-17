import AppKit
import Shared

/// Developer check that memory goes back down after use (the app runs all day).
/// Runs real capture → save cycles (the editor is a separate app and process) in a temporary folder, without touching
/// the clipboard, hotkeys, menu bar or settings, and writes footprint numbers to a report.
@MainActor
enum MemoryTest {
    static func run(report: URL) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MacScreenshot-memtest-\(getpid())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Saver.folderOverride = folder

        var lines: [String] = []
        func log(_ label: String) {
            let line = String(format: "%-34@ %6.1f MB", label as NSString, Memory.footprintMB())
            lines.append(line)
            try? lines.joined(separator: "\n").appending("\n").write(to: report, atomically: true, encoding: .utf8)
        }

        Task { @MainActor in
            log("start")
            let capturer = Capturer()
            let cycles = 5
            for cycle in 1...cycles {
                do {
                    // Capture: freeze the screen, then finish as if ⌘A was pressed.
                    let screen = Capturer.screenUnderMouse()
                    let image = try await capturer.capture(screen: screen)
                    var captured: CGImage?
                    let overlay = OverlayController(screen: screen, image: image) { result in
                        if case .image(let img, _) = result { captured = img }
                    }
                    overlay.show()
                    try await Task.sleep(for: .milliseconds(300))
                    overlay.overlayView?.finishFullScreen()
                    overlay.close()
                    guard let shot = captured else { throw CaptureError.noDisplay }
                    _ = try Saver.write(shot, scale: screen.backingScaleFactor, format: .png, quality: 85,
                                                info: WindowInfo(app: "MemTest", title: "cycle \(cycle)"), date: Date())
                    if cycle == 1 { log("after 1st capture") }

                } catch {
                    lines.append("cycle \(cycle) failed: \(error.localizedDescription)")
                }
            }
            log("after \(cycles) capture cycles")
            try? await Task.sleep(for: .seconds(3))
            log("3 s later (idle)")
            // Optional pause so a developer can inspect the process (footprint, heap, vmmap).
            if let hold = ProcessInfo.processInfo.environment["MEMTEST_HOLD"].flatMap(Double.init) {
                try? await Task.sleep(for: .seconds(hold))
            }
            try? FileManager.default.removeItem(at: folder)
            exit(0)
        }
        app.run()
        exit(0)
    }
}
