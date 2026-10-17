import Foundation

/// Spotlight matches the start of each word in an app's name, and "MacScreenshot" is one
/// word, so typing "shot" wouldn't find it. On launch the app tags its own bundle with
/// keywords (a metadata extended attribute, which doesn't affect the code signature) so
/// ⌘Space finds it by "mac", "screen", "shot" and similar words.
enum SpotlightKeywords {
    static let keywords = [
        "mac", "screen", "shot", "screenshot", "screen shot", "capture", "screen capture",
        "snip", "snipping tool", "greenshot", "flameshot",
    ]

    private static let attribute = "com.apple.metadata:kMDItemKeywords"

    static func apply(to bundle: URL = Bundle.main.bundleURL) {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: keywords, format: .binary, options: 0)
        else { return }
        bundle.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            // Skip if already set, so Spotlight doesn't re-index on every launch.
            let size = getxattr(path, attribute, nil, 0, 0, 0)
            if size == data.count {
                var existing = Data(count: size)
                let read = existing.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, size, 0, 0) }
                if read == size, existing == data { return }
            }
            // Fails quietly if the app is somewhere read-only (e.g. still in Downloads).
            _ = data.withUnsafeBytes { setxattr(path, attribute, $0.baseAddress, data.count, 0, 0) }
        }
    }
}
