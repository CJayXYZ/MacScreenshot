import AppKit
import SwiftUI

enum ShortcutAction: CaseIterable {
    case capture, lastRegion

    var title: String {
        switch self {
        case .capture: return "Capture an area"
        case .lastRegion: return "Capture last region"
        }
    }

    var defaultShortcut: Shortcut {
        switch self {
        case .capture: return .captureDefault
        case .lastRegion: return .lastRegionDefault
        }
    }
}

/// What the Shortcuts window needs from the app.
@MainActor
protocol ShortcutStore: AnyObject {
    func shortcut(for action: ShortcutAction) -> Shortcut
    /// Applies and saves the shortcut. Returns an error message if it can't be used.
    func setShortcut(_ shortcut: Shortcut, for action: ShortcutAction) -> String?
    /// Global hotkeys are paused while recording, so the current combination can be re-typed.
    func setRecording(_ recording: Bool)
}

@MainActor
final class ShortcutsWindowController {
    private var window: NSWindow?
    private weak var store: ShortcutStore?

    init(store: ShortcutStore) {
        self.store = store
    }

    func show() {
        guard let store else { return }
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsView(store: store)))
            window.title = "Keyboard Shortcuts"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ShortcutsView: View {
    let store: ShortcutStore
    @State private var shortcuts: [ShortcutAction: Shortcut] = [:]
    @State private var recording: ShortcutAction?
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Click a shortcut, then press the new key combination. It must include ⌘, ⌥ or ⌃. Press Esc to cancel.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    GridRow {
                        Text(action.title)
                        Button { startRecording(action) } label: {
                            Text(recording == action ? "Press keys…" : (shortcuts[action]?.display ?? ""))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(minWidth: 130)
                        }
                        .buttonStyle(.bordered)
                        .tint(recording == action ? .accentColor : nil)
                    }
                }
            }

            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("While the screen is frozen, ⌘A captures the full screen and Esc goes back. Those keys stay fixed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Restore Defaults", action: restoreDefaults)
                Spacer()
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear(perform: reload)
        .onDisappear(perform: stopRecording)
    }

    private func reload() {
        for action in ShortcutAction.allCases { shortcuts[action] = store.shortcut(for: action) }
    }

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        message = nil
        recording = action
        store.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil // swallow the key press
        }
    }

    private func handle(_ event: NSEvent, for action: ShortcutAction) {
        if event.keyCode == 53, event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) {
            stopRecording() // Esc: keep the current shortcut
            return
        }
        guard let shortcut = Shortcut(event: event) else {
            message = "Add ⌘, ⌥ or ⌃ to the key."
            return
        }
        stopRecording()
        message = store.setShortcut(shortcut, for: action)
        reload()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            store.setRecording(false)
        }
    }

    private func restoreDefaults() {
        stopRecording()
        message = nil
        for action in ShortcutAction.allCases {
            if let error = store.setShortcut(action.defaultShortcut, for: action) { message = error }
        }
        reload()
    }
}
