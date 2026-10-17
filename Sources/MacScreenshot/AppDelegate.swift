import AppKit
import Carbon.HIToolbox
import Shared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ShortcutStore {
    private var statusItem: NSStatusItem!
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    private let capturer = Capturer()
    private var overlay: OverlayController?
    private var busy = false
    private lazy var help = HelpWindowController { [weak self] in self?.popUpMenuAtMouse() }
    private lazy var shortcutsWindow = ShortcutsWindowController(store: self)
    private var editItem: NSMenuItem!
    private var captureItem: NSMenuItem!

    private var lastRegionItem: NSMenuItem!
    private var pngItem: NSMenuItem!
    private var jpegItem: NSMenuItem!
    private var qualitySlider: NSSlider!
    private var qualityLabel: NSTextField!
    private var shutterItem: NSMenuItem!
    private var volumeSlider: NSSlider!
    private var volumeLabel: NSTextField!
    private var folderItem: NSMenuItem!
    private var resetFolderItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var memoryItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LaunchManager.bootstrap() else { exit(0) }

        Settings.migrateShortcutDefaults()
        buildMenu()
        registerHotKeys()
        startMemoryJanitor()
        SpotlightKeywords.apply()

        // Opening the app again while it runs (Finder, Spotlight, Terminal) brings back its controls.
        DistributedNotificationCenter.default().addObserver(forName: LaunchManager.reopenNotification,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reopen() }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.capturer.invalidate() }
        }

        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }

        if !Settings.hasSeenHelp {
            Settings.hasSeenHelp = true
            help.show()
        }
    }

    // MARK: Memory

    private var janitorTimer: Timer?
    private var janitorTicks = 0

    /// Keeps the always-running app's memory flat. AppKit empties its per-event memory pool
    /// only when an event is handed to the app; a menu bar app can sit inside one wait for
    /// minutes while macOS passes mouse events by it, and those pile up in that pool. A tiny
    /// no-op event every 2 s keeps that pile to a few dozen events (less fragmentation); every
    /// 30 s, freed memory is returned to macOS. Costs microseconds, coalesced with other timers.
    private func startMemoryJanitor() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.janitorTick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        janitorTimer = timer
    }

    private func janitorTick() {
        if let wake = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: 0, context: nil,
                                         subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(wake, atStart: false)
        }
        janitorTicks += 1
        if janitorTicks % 15 == 0 { malloc_zone_pressure_relief(nil, 0) }
    }

    /// Finder / Spotlight / Dock open of the already-running app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen()
        return false
    }

    /// The way back when the menu bar icon is hidden (notch, macOS menu bar settings,
    /// menu bar managers): restore the icon and show the window with the full menu.
    private func reopen() {
        statusItem.isVisible = true
        help.show()
    }

    private func popUpMenuAtMouse() {
        guard let menu = statusItem.menu else { return }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func registerHotKeys() {
        let taken = ShortcutAction.allCases.filter { !register($0, Settings.shortcut(for: $0)) }
        if !taken.isEmpty {
            let names = taken.map { Settings.shortcut(for: $0).display }.joined(separator: " and ")
            showAlert("Shortcut already in use",
                      "\(names) is used by another app. Pick a different one in the menu bar icon → Keyboard Shortcuts.")
        }
    }

    /// (Re)registers one global hotkey. Returns false if another app already owns the combination.
    @discardableResult
    private func register(_ action: ShortcutAction, _ shortcut: Shortcut) -> Bool {
        hotKeys[action] = nil // unregister the old one first
        let id = action.hotKeyID
        let hotKey = HotKey(id: id, keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            MainActor.assumeIsolated {
                switch action {
                case .capture: self?.startCapture()
                case .lastRegion: self?.captureLastRegion()
                case .editLast: self?.editLastCapture()
                }
            }
        }
        hotKeys[action] = hotKey
        return hotKey != nil
    }

    // MARK: ShortcutStore

    func shortcut(for action: ShortcutAction) -> Shortcut { Settings.shortcut(for: action) }

    func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) -> String? {
        if let other = ShortcutAction.allCases.first(where: { $0 != action && Settings.shortcut(for: $0) == shortcut }) {
            return "\(shortcut.display) is already used for “\(other.title)”."
        }
        let previous = Settings.shortcut(for: action)
        guard register(action, shortcut) else {
            register(action, previous)
            return "\(shortcut.display) is used by another app. Try a different combination."
        }
        Settings.setShortcut(shortcut, for: action)
        updateMenuShortcuts()
        return nil
    }

    func setRecording(_ recording: Bool) {
        if recording {
            hotKeys = [:]
        } else {
            for action in ShortcutAction.allCases where hotKeys[action] == nil {
                register(action, Settings.shortcut(for: action))
            }
        }
    }

    private func updateMenuShortcuts() {
        for (item, action) in [(captureItem, ShortcutAction.capture), (lastRegionItem, .lastRegion), (editItem, .editLast)] {
            let shortcut = Settings.shortcut(for: action)
            item?.keyEquivalent = shortcut.menuKeyEquivalent
            item?.keyEquivalentModifierMask = shortcut.menuKeyEquivalent.isEmpty ? [] : shortcut.flags
        }
    }

    // MARK: Capture

    @objc func startCapture() {
        guard !busy else { return }
        busy = true

        // Read these before the overlay takes focus.
        let info = WindowInfo.current()
        let previous = NSWorkspace.shared.frontmostApplication
        let screen = Capturer.screenUnderMouse()
        let date = Date()

        Task { @MainActor in
            do {
                let image = try await capturer.capture(screen: screen)
                let scale = screen.backingScaleFactor
                let displayID = Capturer.displayID(of: screen) ?? 0
                let controller = OverlayController(screen: screen, image: image) { [weak self] result in
                    self?.finishOverlay(result, scale: scale, displayID: displayID, info: info, date: date, previous: previous)
                }
                overlay = controller
                controller.show()
            } catch {
                busy = false
                handleCaptureError(error)
            }
        }
    }

    /// Captures the same area as the last screenshot, with no overlay.
    @objc func captureLastRegion() {
        guard !busy else { return }
        guard let region = Settings.lastRegion else {
            NSSound.beep()
            showAlert("No previous region", "Take a screenshot with \(Settings.shortcut(for: .capture).display) first.")
            return
        }
        busy = true

        let info = WindowInfo.current()
        let date = Date()
        // Same display as last time if it's still connected.
        let screen = Capturer.screen(withDisplayID: region.displayID) ?? Capturer.screenUnderMouse()

        Task { @MainActor in
            defer { busy = false }
            do {
                let image = try await capturer.capture(screen: screen)
                let sx = CGFloat(image.width) / screen.frame.width
                let sy = CGFloat(image.height) / screen.frame.height
                let pixels = CGRect(x: (region.x * sx).rounded(), y: (region.y * sy).rounded(),
                                    width: (region.width * sx).rounded(), height: (region.height * sy).rounded())
                    .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1, let cropped = image.cropping(to: pixels) else {
                    throw CaptureError.noDisplay
                }
                save(cropped, scale: screen.backingScaleFactor, info: info, date: date)
            } catch {
                handleCaptureError(error)
            }
        }
    }

    private func finishOverlay(_ result: OverlayResult, scale: CGFloat, displayID: CGDirectDisplayID,
                               info: WindowInfo, date: Date, previous: NSRunningApplication?) {
        overlay?.close()
        overlay = nil
        busy = false
        if let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previous.activate()
        }

        guard case .image(let image, let region) = result else { return }
        Settings.lastRegion = Region(displayID: displayID, x: region.minX, y: region.minY,
                                     width: region.width, height: region.height)
        save(image, scale: scale, info: info, date: date)
    }

    private func save(_ image: CGImage, scale: CGFloat, info: WindowInfo, date: Date) {
        let format = Settings.format
        let quality = Settings.jpegQuality
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome = Result { try Saver.write(image, scale: scale, format: format, quality: quality, info: info, date: date) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.completeSave(outcome) }
            }
        }
    }

    /// Success = file saved AND image on the clipboard.
    private func completeSave(_ outcome: Result<(url: URL, png: Data), Error>) {
        do {
            let saved = try outcome.get()
            Settings.lastCapturePath = saved.url.path
            try Saver.copyToClipboard(saved.png)
            playShutter()
        } catch {
            NSSound(named: "Basso")?.play()
            showAlert("Screenshot failed", error.localizedDescription)
        }
        Memory.trimSoon()
    }

    private func playShutter() { Shutter.play() }

    private func handleCaptureError(_ error: Error) {
        if !CGPreflightScreenCaptureAccess() {
            askForPermission()
        } else {
            showAlert("Capture failed", error.localizedDescription)
        }
    }

    private func askForPermission() {
        let alert = NSAlert()
        alert.messageText = "MacScreenshot needs Screen Recording permission"
        alert.informativeText = "Turn on MacScreenshot in System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen MacScreenshot."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "MacScreenshot"
        statusItem.isVisible = true
        statusItem.button?.image = MenuBarIcon.make()

        let menu = NSMenu()
        menu.delegate = self

        captureItem = NSMenuItem(title: "Capture", action: #selector(startCapture), keyEquivalent: "")
        menu.addItem(captureItem)
        lastRegionItem = NSMenuItem(title: "Capture Last Region", action: #selector(captureLastRegion), keyEquivalent: "")
        menu.addItem(lastRegionItem)
        editItem = NSMenuItem(title: "Edit Last Capture…", action: #selector(editLastCapture), keyEquivalent: "")
        menu.addItem(editItem)
        menu.addItem(NSMenuItem(title: "Keyboard Shortcuts…", action: #selector(showShortcuts), keyEquivalent: ""))
        updateMenuShortcuts()
        menu.addItem(.separator())

        pngItem = NSMenuItem(title: "Save as PNG", action: #selector(choosePNG), keyEquivalent: "")
        jpegItem = NSMenuItem(title: "Save as JPEG", action: #selector(chooseJPEG), keyEquivalent: "")
        menu.addItem(pngItem)
        menu.addItem(jpegItem)
        let quality = sliderItem(value: Settings.jpegQuality, action: #selector(qualityChanged))
        qualitySlider = quality.slider
        qualityLabel = quality.label
        menu.addItem(quality.item)
        menu.addItem(.separator())

        shutterItem = NSMenuItem(title: "Shutter Sound", action: #selector(toggleShutter), keyEquivalent: "")
        menu.addItem(shutterItem)
        let volume = sliderItem(value: Settings.shutterVolume, action: #selector(volumeChanged))
        volumeSlider = volume.slider
        volumeLabel = volume.label
        menu.addItem(volume.item)
        menu.addItem(.separator())

        folderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        folderItem.isEnabled = false
        menu.addItem(folderItem)
        menu.addItem(NSMenuItem(title: "Change Save Location…", action: #selector(chooseFolder), keyEquivalent: ""))
        resetFolderItem = NSMenuItem(title: "Use macOS Screenshots Folder", action: #selector(resetFolder), keyEquivalent: "")
        menu.addItem(resetFolderItem)
        menu.addItem(NSMenuItem(title: "Open Screenshots Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "How to Use…", action: #selector(showHelp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: ""))
        let support = NSMenuItem(title: "Support MacScreenshot ♥", action: nil, keyEquivalent: "")
        let supportMenu = NSMenu()
        for (index, option) in Links.donations.enumerated() {
            let item = NSMenuItem(title: option.title, action: #selector(openDonation(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            supportMenu.addItem(item)
        }
        support.submenu = supportMenu
        menu.addItem(support)
        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Start at Login (auto-restart)", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        memoryItem = NSMenuItem(title: "Memory: –", action: nil, keyEquivalent: "")
        memoryItem.isEnabled = false
        menu.addItem(memoryItem)
        menu.addItem(NSMenuItem(title: "Quit MacScreenshot", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { if $0.action != nil { $0.target = self } }
        statusItem.menu = menu
    }

    /// A menu row with a label above a 0–100% slider in steps of 5.
    private func sliderItem(value: Int, action: Selector) -> (item: NSMenuItem, slider: NSSlider, label: NSTextField) {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 48))

        let label = NSTextField(labelWithString: "")
        label.font = .menuFont(ofSize: 0)
        label.frame = NSRect(x: 20, y: 26, width: 200, height: 18)
        container.addSubview(label)

        let slider = NSSlider(value: Double(value), minValue: 0, maxValue: 100, target: self, action: action)
        slider.numberOfTickMarks = 21
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.frame = NSRect(x: 18, y: 2, width: 204, height: 22)
        container.addSubview(slider)

        let item = NSMenuItem()
        item.view = container
        return (item, slider, label)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lastRegionItem.isEnabled = Settings.lastRegion != nil
        editItem.isEnabled = Settings.lastCapturePath != nil

        let isJPEG = Settings.format == .jpeg
        pngItem.state = isJPEG ? .off : .on
        jpegItem.state = isJPEG ? .on : .off
        qualitySlider.integerValue = Settings.jpegQuality
        qualitySlider.isEnabled = isJPEG
        qualityLabel.textColor = isJPEG ? .labelColor : .disabledControlTextColor
        qualityLabel.stringValue = "JPEG quality: \(Settings.jpegQuality)%"

        let soundOn = Settings.shutterEnabled
        shutterItem.state = soundOn ? .on : .off
        volumeSlider.integerValue = Settings.shutterVolume
        volumeSlider.isEnabled = soundOn
        volumeLabel.textColor = soundOn ? .labelColor : .disabledControlTextColor
        volumeLabel.stringValue = "Shutter volume: \(Settings.shutterVolume)%"

        folderItem.title = "Save to: " + (Saver.folder().path as NSString).abbreviatingWithTildeInPath
        resetFolderItem.isHidden = Settings.saveFolder == nil

        loginItem.state = LaunchManager.isEnabled ? .on : .off
        memoryItem.title = String(format: "Memory: %.1f MB", Memory.footprintMB())
    }

    @objc private func choosePNG() { Settings.format = .png }
    @objc private func chooseJPEG() { Settings.format = .jpeg }

    @objc private func qualityChanged() {
        Settings.jpegQuality = Int((qualitySlider.doubleValue / 5).rounded()) * 5
        qualityLabel.stringValue = "JPEG quality: \(Settings.jpegQuality)%"
    }

    @objc private func toggleShutter() { Settings.shutterEnabled.toggle() }

    @objc private func volumeChanged() {
        let newValue = Int((volumeSlider.doubleValue / 5).rounded()) * 5
        guard newValue != Settings.shutterVolume else { return }
        Settings.shutterVolume = newValue
        volumeLabel.stringValue = "Shutter volume: \(newValue)%"
        playShutter() // preview
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose where MacScreenshot saves screenshots"
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Saver.folder()
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            Settings.saveFolder = url.path
        }
    }

    @objc private func resetFolder() { Settings.saveFolder = nil }

    @objc private func openFolder() {
        let folder = Saver.folder()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func toggleLogin() {
        if LaunchManager.isEnabled { LaunchManager.disable() } else { LaunchManager.enable() }
    }

    @objc private func showHelp() { help.show() }
    @objc private func showShortcuts() { shortcutsWindow.show() }

    /// Opens the most recent capture in MacScreenshot Editor, a separate app inside this bundle.
    /// It runs in its own process: closing, crashing or force-quitting it never affects capture,
    /// and all its memory is freed when it quits.
    @objc func editLastCapture() {
        guard !busy else { return }
        guard let path = Settings.lastCapturePath else {
            showAlert("Nothing to edit yet", "Take a screenshot with \(Settings.shortcut(for: .capture).display) first.")
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            showAlert("Last capture not found", "\((path as NSString).lastPathComponent) was moved or deleted.")
            return
        }
        let editorApp = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/MacScreenshot Editor.app")
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: editorApp, configuration: config) { _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.showAlert("Couldn't open the editor", error.localizedDescription) }
            }
        }
    }
    @objc private func sendFeedback() { NSWorkspace.shared.open(Links.feedback) }
    @objc private func openDonation(_ sender: NSMenuItem) {
        let options = Links.donations
        guard options.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(options[sender.tag].url)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
