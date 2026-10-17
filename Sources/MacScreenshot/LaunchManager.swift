import AppKit
import ServiceManagement
import Shared

/// Start-at-login and auto-restart, via a LaunchAgent bundled in Contents/Library/LaunchAgents.
/// launchd starts MacScreenshot at login and relaunches it after a crash (KeepAlive.SuccessfulExit = false);
/// a normal Quit exits with 0 and stays quit until the next login.
enum LaunchManager {
    static let label = "io.github.cjayxyz.MacScreenshot.agent"
    /// Posted by a second launch so the running copy shows its window and menu bar icon.
    static let reopenNotification = Notification.Name("io.github.cjayxyz.MacScreenshot.reopen")
    private static var agent: SMAppService { SMAppService.agent(plistName: "\(label).plist") }

    private static var launchedByLaunchd: Bool {
        ProcessInfo.processInfo.environment["MACSCREENSHOT_LAUNCHD"] == "1"
    }

    /// Decides whether this process should run. Returns false when it should exit
    /// because the launchd-supervised copy is (or will be) the one running.
    static func bootstrap() -> Bool {
        if launchedByLaunchd { return waitForOtherInstancesToExit() }

        // Opened by hand (Finder, `open`, Spotlight): hand over to launchd so crashes get restarted.
        if Settings.startAtLogin {
            do {
                if agent.status != .enabled { try agent.register() }
                if agent.status == .enabled, kickstart() {
                    notifyRunningCopy()
                    return false
                }
            } catch {
                NSLog("MacScreenshot: launch agent registration failed: \(error)")
            }
        }
        // Not supervised: run here, as the only instance.
        if waitForOtherInstancesToExit() { return true }
        notifyRunningCopy()
        return false
    }

    private static func notifyRunningCopy() {
        DistributedNotificationCenter.default().postNotificationName(reopenNotification, object: nil,
                                                                     userInfo: nil, deliverImmediately: true)
    }

    static var isEnabled: Bool { Settings.startAtLogin && agent.status == .enabled }

    static func enable() {
        Settings.startAtLogin = true
        do {
            try agent.register()
        } catch {
            NSLog("MacScreenshot: launch agent registration failed: \(error)")
        }
        if agent.status == .enabled, kickstart() {
            exit(0) // the launchd copy takes over
        } else if agent.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    static func disable() {
        Settings.startAtLogin = false
        // Unregistering stops the launchd job (and this process), so start an unsupervised copy first.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.activates = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                try? agent.unregister()
                exit(0)
            }
        }
    }

    private static func kickstart() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func waitForOtherInstancesToExit(timeout: TimeInterval = 3) -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
                .filter { $0.processIdentifier != me && !$0.isTerminated }
            if others.isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return false
    }
}
