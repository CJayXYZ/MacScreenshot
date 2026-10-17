// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacScreenshot",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MacScreenshot",
            path: "Sources/MacScreenshot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
