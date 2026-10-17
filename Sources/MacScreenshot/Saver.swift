import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Saver {
    /// The folder chosen in MacScreenshot, else the macOS Screenshots folder.
    static func folder() -> URL {
        if let custom = Settings.saveFolder, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return systemFolder()
    }

    /// The folder macOS saves screenshots to (Screenshot app > Options > Save to), else the Desktop.
    static func systemFolder() -> URL {
        if let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
           !location.isEmpty {
            return URL(fileURLWithPath: (location as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    /// Encodes and writes the file. Runs off the main thread.
    /// Returns the saved file and the PNG data for the clipboard.
    static func write(_ image: CGImage, scale: CGFloat, format: ImageFormat, quality: Int,
                      info: WindowInfo, date: Date) throws -> (url: URL, png: Data) {
        let (fileData, png) = try encodeForFile(image, scale: scale, format: format, quality: quality)

        let folder = folder()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let base = FileNaming.baseName(date: date, app: info.app, title: info.title)
            let url = FileNaming.uniqueURL(in: folder, base: base, ext: format.fileExtension)
            try fileData.write(to: url, options: .withoutOverwriting)
            return (url, png)
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
    }

    /// Writes an edited image to a specific file (a new "-edited" copy, or over the original).
    /// Returns the PNG data for the clipboard.
    static func write(_ image: CGImage, to url: URL, scale: CGFloat, format: ImageFormat, quality: Int,
                      replacing: Bool) throws -> Data {
        let (fileData, png) = try encodeForFile(image, scale: scale, format: format, quality: quality)
        do {
            try fileData.write(to: url, options: replacing ? .atomic : .withoutOverwriting)
            return png
        } catch {
            throw CaptureError.writeFailed(error.localizedDescription)
        }
    }

    /// The file's bytes in the chosen format, plus PNG for the clipboard (the same data when saving PNG).
    private static func encodeForFile(_ image: CGImage, scale: CGFloat, format: ImageFormat,
                                      quality: Int) throws -> (file: Data, png: Data) {
        let dpi = 72 * scale
        guard let png = encode(image, as: .png, quality: nil, dpi: dpi) else { throw CaptureError.encodeFailed }
        if format == .png { return (png, png) }
        guard let jpeg = encode(image, as: .jpeg, quality: Double(quality) / 100, dpi: dpi) else {
            throw CaptureError.encodeFailed
        }
        return (jpeg, png)
    }

    /// Puts the PNG on the clipboard. Main thread only.
    static func copyToClipboard(_ png: Data) throws {
        let board = NSPasteboard.general
        board.clearContents()
        guard board.setData(png, forType: .png) else { throw CaptureError.clipboardFailed }
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?, dpi: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if let quality { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
