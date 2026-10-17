import AppKit
import SwiftUI
import Shared

enum Links {
    static let repo = URL(string: "https://github.com/CJayXYZ/MacScreenshot")!
    static let feedback = URL(string: "https://github.com/CJayXYZ/MacScreenshot/issues/new/choose")!
    static let githubSponsors = URL(string: "https://github.com/sponsors/CJayXYZ")!

    /// Ko-fi page username; empty hides the Ko-fi option. Set before a release (scripts/check-release.sh checks it).
    static let kofiUsername = "cjayxyz"
    static var kofi: URL? { kofiUsername.isEmpty ? nil : URL(string: "https://ko-fi.com/\(kofiUsername)") }

    /// Donation options in display order.
    static var donations: [(title: String, url: URL)] {
        [("Sponsor on GitHub", githubSponsors)] + (kofi.map { [("Tip on Ko-fi", $0)] } ?? [])
    }
}

/// The "How to Use" window: shown on first launch and from the menu bar.
@MainActor
final class HelpWindowController {
    private var window: NSWindow?
    private let showMenu: () -> Void

    init(showMenu: @escaping () -> Void) {
        self.showMenu = showMenu
    }

    func show() {
        let view = HelpView(showMenu: showMenu) { [weak self] in self?.window?.close() }
        if let window {
            window.contentViewController = NSHostingController(rootView: view)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "How to Use MacScreenshot"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            Memory.releaseOnClose(window) { [weak self] in
                self?.window?.contentViewController = nil
                self?.window = nil
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct HelpView: View {
    let showMenu: () -> Void
    let close: () -> Void
    @State private var hasPermission = CGPreflightScreenCaptureAccess()

    // Read when the window is built, so changed shortcuts show up (the window is rebuilt on each show).
    private let shortcuts: [(keys: String, action: String)] = [
        (Settings.shortcut(for: .capture).display, "Freeze the screen and select an area"),
        ("Drag, release", "Save the area and copy it to the clipboard"),
        ("⌘A", "Capture the whole screen instead"),
        ("Esc", "While dragging: clear the selection and drag again"),
        ("Esc Esc", "Back to the live screen, nothing saved"),
        (Settings.shortcut(for: .lastRegion).display, "Capture the same area as last time, instantly"),
        (Settings.shortcut(for: .editLast).display, "Edit the last capture: crop, arrow, box, circle, text, highlight"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacScreenshot").font(.title2.bold())
                    Text("Freeze, select, saved and copied. Version \(version)")
                        .foregroundStyle(.secondary)
                }
            }

            permissionRow

            VStack(alignment: .leading, spacing: 8) {
                Text("Shortcuts").font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    ForEach(shortcuts, id: \.keys) { row in
                        GridRow {
                            Text(row.keys)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                            Text(row.action)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Good to know").font(.headline)
                Label("The magnifier next to the pointer shows exact pixels and the selection size.", systemImage: "plus.magnifyingglass")
                Label("Every capture is saved as a file and copied, so you can paste right away.", systemImage: "doc.on.clipboard")
                Label("Format, JPEG quality, shutter sound, save folder and keyboard shortcuts are in the menu bar icon.", systemImage: "menubar.rectangle")
                Label("MacScreenshot starts at login and restarts itself if it ever crashes.", systemImage: "arrow.clockwise")
            }
            .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Can't see the menu bar icon?").font(.headline)
                Text("Open MacScreenshot again from Applications or Spotlight to get back to this window. The menu bar icon can hide behind the notch on MacBooks, or be switched off in System Settings → Menu Bar.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Show Menu (all settings)", action: showMenu)
            }

            Divider()

            HStack {
                Button("Send Feedback") { NSWorkspace.shared.open(Links.feedback) }
                Menu("Support the Project ♥") {
                    ForEach(Links.donations, id: \.url) { option in
                        Button(option.title) { NSWorkspace.shared.open(option.url) }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Got It", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = CGPreflightScreenCaptureAccess()
        }
    }

    @ViewBuilder private var permissionRow: some View {
        if hasPermission {
            Label("Screen Recording permission is on. You're ready to go.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            HStack {
                Label("Screen Recording permission is needed.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }
            Text("Turn on MacScreenshot there, then quit and reopen it from the menu bar icon.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
