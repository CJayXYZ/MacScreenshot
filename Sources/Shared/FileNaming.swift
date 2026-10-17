import Foundation

/// Builds `screenshot-<date>_<time>-<app>-<window title>` file names.
public enum FileNaming {
    static let maxTailCharacters = 80
    static let maxTailBytes = 180 // keeps the full name well under the 255-byte filesystem limit

    private static let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|")
        .union(.newlines)
        .union(.controlCharacters)

    public static func baseName(date: Date, app: String?, title: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        var name = "screenshot-" + formatter.string(from: date)

        var parts = [app, title].compactMap { $0 }.map(sanitize).filter { !$0.isEmpty }
        if parts.count == 2, parts[0].caseInsensitiveCompare(parts[1]) == .orderedSame {
            parts.removeLast()
        }
        let tail = truncate(parts.joined(separator: "-"))
        if !tail.isEmpty { name += "-" + tail }
        return name
    }

    public static func sanitize(_ text: String) -> String {
        let replaced = String(String.UnicodeScalarView(text.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        return replaced.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    public static func truncate(_ text: String) -> String {
        var out = text
        if out.count > maxTailCharacters {
            let cut = String(out.prefix(maxTailCharacters))
            // Cut at the last word boundary, unless that would throw away more than half.
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxTailCharacters / 2 {
                out = String(cut[..<space])
            } else {
                out = cut
            }
        }
        while out.utf8.count > maxTailBytes { out.removeLast() }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
    }

    /// Appends -2, -3, ... when a file with the same name already exists.
    public static func uniqueURL(in folder: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
