import AppKit
import Shared

MainActor.assumeIsolated {
    // Hidden developer mode: `open -n -a MacScreenshot --args --memory-test <report-file>`.
    if let index = CommandLine.arguments.firstIndex(of: "--memory-test") {
        let report = CommandLine.arguments.dropFirst(index + 1).first ?? "/tmp/macscreenshot-memory.txt"
        MemoryTest.run(report: URL(fileURLWithPath: report))
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
