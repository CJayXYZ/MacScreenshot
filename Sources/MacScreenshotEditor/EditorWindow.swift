import AppKit
import ImageIO
import SwiftUI
import Shared

/// The editor window: toolbar on top, canvas below. Everything (image, undo history)
/// is released when the window closes.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    /// Called after Save / Replace with the written file and PNG data for the clipboard.
    var onSaved: ((URL, Data) -> Void)?
    /// Called when the window has closed and everything is released.
    var onClosed: (() -> Void)?

    private var window: EditorWindow?
    private var model: EditorModel?
    private var canvas: EditorCanvas?
    private(set) var fileURL: URL?
    private var closingAfterSave = false

    func bringToFront() {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func open(_ url: URL) throws {
        if let window, fileURL == url {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        if let window {
            // Another file is open; close it (asking about unsaved edits) before loading the new one.
            guard confirmDiscard() else { return }
            closingAfterSave = true
            window.close()
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CaptureError.writeFailed("couldn't open \(url.lastPathComponent)")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
        let model = EditorModel(image: image, scale: CGFloat(dpi / 72).rounded())

        let canvas = EditorCanvas(model: model)
        canvas.onEscape = { [weak self] in self?.window?.performClose(nil) }
        let toolbar = NSHostingView(rootView: EditorToolbar(
            model: model,
            onSave: { [weak self] in self?.save(replace: false) },
            onReplace: { [weak self] in self?.save(replace: true) }))

        let content = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)
        content.addSubview(canvas)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // The toolbar is widest with the Text tool (size + weight buttons); never let the
        // window get narrower than that, so nothing in it is squeezed.
        let minWidth = ceil(Self.widestToolbarWidth(image: image, scale: model.scale))
        let window = EditorWindow(contentRect: initialFrame(for: image, scale: model.scale, minWidth: minWidth),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                  backing: .buffered, defer: false)
        window.title = "Edit — \(url.lastPathComponent)"
        window.contentView = content
        window.contentMinSize = NSSize(width: minWidth, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.editor = self
        window.center()

        self.window = window
        self.model = model
        self.canvas = canvas
        self.fileURL = url
        closingAfterSave = false

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
    }

    /// Measures the toolbar laid out for the Text tool, its widest state.
    private static func widestToolbarWidth(image: CGImage, scale: CGFloat) -> CGFloat {
        let probe = EditorModel(image: image, scale: scale)
        probe.tool = .text
        return NSHostingView(rootView: EditorToolbar(model: probe, onSave: {}, onReplace: {})).fittingSize.width
    }

    /// Real capture size, shrunk to fit 85% of the screen, plus room for the toolbar.
    private func initialFrame(for image: CGImage, scale: CGFloat, minWidth: CGFloat) -> NSRect {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let toolbar: CGFloat = 52, pad: CGFloat = 40
        let natural = CGSize(width: CGFloat(image.width) / scale + pad, height: CGFloat(image.height) / scale + pad)
        let maxSize = CGSize(width: visible.width * 0.85, height: visible.height * 0.85 - toolbar)
        let fit = min(1, maxSize.width / natural.width, maxSize.height / natural.height)
        return NSRect(x: 0, y: 0, width: max(minWidth, natural.width * fit), height: max(360, natural.height * fit + toolbar))
    }

    // MARK: Actions

    func undo() { canvas?.commitText(); model?.undo() }
    func redo() { model?.redo() }

    func save(replace: Bool) {
        guard let model, let canvas, let source = fileURL else { return }
        canvas.commitText()

        let image = EditorRenderer.flatten(model.document)
        let ext = source.pathExtension.lowercased()
        let format: ImageFormat = (ext == "jpg" || ext == "jpeg") ? .jpeg : .png
        let destination = replace ? source : Self.editedCopyURL(for: source)
        do {
            let png = try Saver.write(image, to: destination, scale: model.scale, format: format,
                                      quality: Settings.jpegQuality, replacing: replace)
            onSaved?(destination, png)
            closingAfterSave = true
            window?.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save the edit"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// "<name>-edited.<ext>" next to the original; editing an edited copy doesn't stack suffixes.
    static func editedCopyURL(for source: URL) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let range = base.range(of: #"-edited(-\d+)?$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        return FileNaming.uniqueURL(in: source.deletingLastPathComponent(), base: base + "-edited",
                                    ext: source.pathExtension)
    }

    private func confirmDiscard() -> Bool {
        guard let model, model.hasChanges, !closingAfterSave else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your edits?"
        alert.informativeText = "Use Save or Replace to keep them."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: "Discard")
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas?.commitText()
        return confirmDiscard()
    }

    func windowWillClose(_ notification: Notification) {
        // Free the image, undo history and drawing buffers.
        window?.editor = nil
        window?.contentView = nil
        window = nil
        model = nil
        canvas = nil
        fileURL = nil
        Memory.trimSoon()
        onClosed?()
    }
}

/// Handles editor key equivalents. MacScreenshot has no main menu (it's a menu bar app),
/// so ⌘Z / ⌘S / ⌘C / ⌘V would otherwise do nothing.
final class EditorWindow: NSWindow {
    weak var editor: EditorWindowController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let editingText = firstResponder is NSTextView

        switch (flags, key) {
        case ([.command], "s"):
            MainActor.assumeIsolated { editor?.save(replace: false) }
            return true
        case ([.command], "w"):
            performClose(nil)
            return true
        case ([.command], "z") where !editingText:
            MainActor.assumeIsolated { editor?.undo() }
            return true
        case ([.command, .shift], "z") where !editingText:
            MainActor.assumeIsolated { editor?.redo() }
            return true
        case ([.command], "x"):
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case ([.command], "c"):
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case ([.command], "v"):
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case ([.command], "a"):
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case ([.command], "z"):
            return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// Segment icons drawn as images: macOS segmented controls ignore font weight, so SF Symbols
/// or text with different weights all render identically. Template images follow the
/// control's tint (white when selected, grey otherwise).
@MainActor
enum ToolbarIcons {
    private static var cache: [String: NSImage] = [:]

    static func stroke(_ width: StrokeWidth) -> NSImage {
        let line: CGFloat = width == .thin ? 1 : width == .medium ? 2.5 : 4.5
        return icon("stroke-\(width.rawValue)") {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 4, y: 4))
            path.line(to: NSPoint(x: 18, y: 14))
            path.lineWidth = line
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
        }
    }

    static func weight(_ weight: TextWeight) -> NSImage {
        icon("weight-\(weight.rawValue)") {
            let text = NSAttributedString(string: "A", attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: weight.font),
                .foregroundColor: NSColor.black,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: (22 - size.width) / 2, y: (18 - size.height) / 2))
        }
    }

    private static func icon(_ key: String, draw: @escaping () -> Void) -> NSImage {
        if let cached = cache[key] { return cached }
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return image
    }
}

struct EditorToolbar: View {
    @ObservedObject var model: EditorModel
    let onSave: () -> Void
    let onReplace: () -> Void
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 14) {
            Picker("Tool", selection: $model.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Image(systemName: tool.symbol)
                        .help("\(tool.title) (\(String(tool.key).uppercased()))")
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            HStack(spacing: 6) {
                ForEach(EditorModel.colors, id: \.self) { color in
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(model.color == color ? Color.accentColor : Color.secondary.opacity(0.4),
                                                       lineWidth: model.color == color ? 3 : 1))
                        .contentShape(Circle())
                        .onTapGesture { model.color = color }
                }
            }

            // Only the options for the current tool, so the toolbar stays simple.
            if model.tool.usesStroke {
                Picker("Thickness", selection: $model.stroke) {
                    ForEach(StrokeWidth.allCases) { width in
                        Image(nsImage: ToolbarIcons.stroke(width))
                            .help(width.rawValue)
                            .tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Line thickness")
            } else if model.tool == .text {
                Picker("Text size", selection: $model.textSize) {
                    ForEach(TextSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Text size")

                Picker("Text weight", selection: $model.textWeight) {
                    ForEach(TextWeight.allCases) { weight in
                        Image(nsImage: ToolbarIcons.weight(weight))
                            .help(weight.rawValue)
                            .tag(weight)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Text weight")
            }

            HStack(spacing: 4) {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!model.canUndo).help("Undo (⌘Z)")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!model.canRedo).help("Redo (⇧⌘Z)")
            }
            .fixedSize()

            Spacer(minLength: 8)

            // Save, Replace and ⓘ keep their full size, whatever the window width.
            HStack(spacing: 10) {
            Button { showInfo.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("What Save and Replace do")
                .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("**Save** keeps the original and adds an “-edited” copy next to it.")
                        Text("**Replace** overwrites the original file.")
                        Text("Both always copy the image to the clipboard.")
                    }
                    .padding(14)
                    .frame(width: 280)
                }
            Button("Replace", action: onReplace)
                .help("Overwrite the original and copy to the clipboard")
            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .help("Save an “-edited” copy and copy to the clipboard (⌘S)")
            }
            .fixedSize()
            .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
