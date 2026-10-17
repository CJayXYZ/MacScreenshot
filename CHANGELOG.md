# Changelog

## 1.1.3 — 2026-10-17

- **New default shortcuts:** Edit Last Capture is now **⌘⌥⇧X** (easier to reach) and Capture Last Region is **⌃⇧⌘X**, matching how macOS uses ⌃ for capture variations. Shortcuts you set yourself are kept. You can change any of them in Keyboard Shortcuts….

## 1.1.2 — 2026-10-17

- Spotlight (⌘Space) now finds MacScreenshot by "mac", "screen", "shot", "screenshot", "capture" or "snip". The app adds these search keywords to itself when it starts.

## 1.1.1 — 2026-10-17

- The editor is now **MacScreenshot Editor**, a separate app inside MacScreenshot.app. It runs in its own process with its own name in Activity Monitor and its own Dock icon while open. Closing, crashing or force-quitting it never affects capture, and it frees all its memory when it quits.
- The always-running capture app stays lean: about 12 MB idle and 17 MB after repeated captures. It used to climb to 33–45 MB after editing.
- Closed windows release their memory, and freed memory goes back to macOS after each capture.
- **Esc always works on the frozen screen.** Esc and ⌘A are claimed system-wide only while it's showing, so they work even when macOS keeps another app receiving keystrokes. They're released as soon as it closes.
- A hint under the coordinates: "Esc to exit · ⌘A full screen", or "Esc to redo" while dragging.
- The shutter sound now defaults to 50% volume.
- **Fixed slow memory growth in the background.** Mouse activity elsewhere could build up thousands of unreleased event objects (several MB per minute) until you switched apps. A lightweight tidy-up now empties them every 2 seconds and returns freed memory to macOS. CPU stays at 0%.

## 1.1.0 — 2026-10-17

- **Editor:** ⌃⇧⌘X (or menu → Edit Last Capture…) opens the latest capture with crop, arrow, box, circle, text and highlight tools, 7 colours, and undo/redo.
- Line thickness (thin / medium / thick) for arrows, boxes and circles; text size (S/M/L/XL) and weight (regular / bold / heavy).
- **Save** keeps the original and adds an "-edited" copy; **Replace** overwrites the original. Both copy to the clipboard.
- Bigger, high-contrast **+** cursor while capturing, so it's clear screenshot mode is on.
- The capture cursor and keyboard now work even when macOS keeps another app in front.

## 1.0.0 — 2026-10-17

First public release.

- ⌘⇧X freezes the screen under the pointer; drag to capture.
- Magnifier with pixel coordinates and selection size.
- Every capture is saved to a file and copied to the clipboard.
- ⌘A captures the full screen; Esc clears the selection, a second Esc exits.
- ⌘⌥⇧X re-captures the last region instantly.
- File names include date, time, app and window title.
- PNG (default) or JPEG with a 0–100% quality slider.
- Shutter sound on/off with volume.
- Custom save folder, or the macOS screenshot folder.
- Customisable keyboard shortcuts (menu bar icon → Keyboard Shortcuts…).
- Light, dark, tinted and clear app icon on macOS 26; matching menu bar icon.
- Opening the app again restores a hidden menu bar icon and shows the full menu.
- Starts at login and restarts automatically after a crash.
- How to Use window, Send Feedback and Support menu items.
