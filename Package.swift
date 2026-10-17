// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacScreenshot",
    platforms: [.macOS(.v14)],
    targets: [
        // Code both apps use: saving, file names, shared settings, memory helpers.
        .target(name: "Shared", path: "Sources/Shared"),
        // The always-running capture app (menu bar, hotkeys, frozen-screen overlay).
        .executableTarget(
            name: "MacScreenshot",
            dependencies: ["Shared"],
            path: "Sources/MacScreenshot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // MacScreenshot Editor: a separate app and process, bundled inside MacScreenshot.app.
        .executableTarget(
            name: "MacScreenshotEditor",
            dependencies: ["Shared"],
            path: "Sources/MacScreenshotEditor"
        ),
    ]
)
