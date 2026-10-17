import AppKit
import Shared

/// MacScreenshot Editor: a separate app inside MacScreenshot.app. It runs in its own
/// process, so closing, crashing or force-quitting it never affects screen capture, and
/// everything it loaded (images, undo history, UI frameworks) is freed when it quits.
@MainActor
final class EditorAppDelegate: NSObject, NSApplicationDelegate {
    private var editors: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        // Opened without a file (e.g. double-clicked): open the last capture, or explain and quit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            guard editors.isEmpty else { return }
            if let path = Settings.lastCapturePath, FileManager.default.fileExists(atPath: path) {
                open(URL(fileURLWithPath: path))
            } else {
                let alert = NSAlert()
                alert.messageText = "Nothing to edit yet"
                alert.informativeText = "Take a screenshot with MacScreenshot first, then press ⌃⇧⌘X."
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func open(_ url: URL) {
        if let existing = editors.first(where: { $0.fileURL == url }) {
            existing.bringToFront()
            return
        }
        let editor = EditorWindowController()
        editor.onSaved = { url, png in
            // Save and Replace both end here: the edit becomes the "last capture",
            // and it always goes to the clipboard.
            Settings.lastCapturePath = url.path
            do {
                try Saver.copyToClipboard(png)
                Shutter.play()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Saved, but not copied"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        editor.onClosed = { [weak self, weak editor] in
            self?.editors.removeAll { $0 === editor }
        }
        do {
            try editor.open(url)
            editors.append(editor)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't open the capture"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            if editors.isEmpty { NSApp.terminate(nil) }
        }
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MacScreenshot Editor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = EditorAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
