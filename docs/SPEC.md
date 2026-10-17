# MacScreenshot — Functional Spec

Status: draft for approval · 2026-10-17

## 1. Overview

MacScreenshot is a native macOS menu bar app. Press **Cmd+Shift+X**, the active screen freezes, you drag a region, and the crop is saved to your Screenshots folder and copied to the clipboard in one step.

- **Platform:** macOS 14 Sonoma or later, Apple Silicon and Intel.
- **Tech:** Swift + AppKit, ScreenCaptureKit for capture, Carbon hotkey API for the global shortcut. No third-party dependencies.
- **Form:** background app with a menu bar icon, no Dock icon, starts at login.
- **Output:** PNG at full Retina resolution (a 400 x 300 pt selection on a 2x display saves as 800 x 600 px).

## 2. Step-by-step flow

The crop always comes from the frozen image, so nothing that changes on screen after the hotkey ends up in the shot.

1. **Hotkey.** You press Cmd+Shift+X from any app.
2. **Freeze.** MacScreenshot captures the screen under the mouse pointer and covers it with a borderless window showing that still image.
3. **Crosshair.** The pointer becomes a plus-sign crosshair. Nothing is dimmed yet.
4. **Loupe (always on).** A magnifier floats next to the pointer from the moment the screen freezes: pixels around the pointer zoomed ~8x, a center-pixel marker, x/y position, and while dragging the selection's width x height in pixels. It flips sides near screen edges so it never covers the spot you're aiming at.
5. **Drag.** Press and drag to draw the selection. Everything outside the rectangle gets a semi-transparent grey overlay (~45% black); the inside stays full brightness with a thin white border.
6. **Release.** On mouse-up, MacScreenshot crops the frozen image, saves the PNG, copies it to the clipboard, plays the shutter sound, and closes the overlay.
7. **Back to live.** You're back on your normal screen, ready to paste.

A click with no drag, or a selection under 4 x 4 px, is ignored and you stay in crosshair mode.

## 3. Keyboard controls

Esc always steps back one level: mid-drag it clears the selection; from the plain crosshair it closes the overlay. So two presses mid-drag = back to live.

```
              Cmd+Shift+X                press + drag
 [Live screen] ─────────────▶ [Frozen + crosshair] ─────────────▶ [Dragging]
      ▲        ◀───────────── │   ▲               ◀───────────── │
      │          Esc (exit)   │   │                 Esc (redo)    │
      │                       │ Cmd+A (full screen)               │ release mouse
      │                       ▼                                   │
      └──── overlay closes ── [Save + copy] ◀─────────────────────┘
```

| Key | When | What happens |
| --- | --- | --- |
| Cmd+Shift+X | Anywhere | Freeze the screen under the pointer, show crosshair + loupe |
| Esc (1st) | While dragging | Selection cleared; screen stays frozen, drag again |
| Esc (2nd) | Crosshair, no selection | Overlay closes, back to live screen, nothing saved |
| Cmd+A | Crosshair or dragging | Whole frozen screen saved + copied, overlay closes |
| Cmd+Shift+X | While overlay is open | Ignored (no second freeze) |
| Cmd+Shift+Control+X | Anywhere | Capture last region: same area on the same display as the last screenshot, saved + copied instantly, no overlay. Beeps with a hint if there's no previous region. |

The last region is the selection (or full screen via Cmd+A) from the most recent Cmd+Shift+X capture, remembered across restarts. If that display is disconnected, the screen under the pointer is used.

## 4. Success criteria

A capture is successful only when **both** the file is on disk and the image is on the clipboard. If either fails, MacScreenshot shows an error notification instead of the shutter sound.

- [ ] **File saved.** Written to the folder chosen in MacScreenshot' menu; by default the macOS Screenshots folder (the location set in the Screenshot app; Desktop if never changed). Changing it in MacScreenshot does not change macOS's own setting. Name — see File naming below.
- [ ] **Copied to clipboard.** Same image on the clipboard as PNG, ready to paste into Slack, Mail, Figma, Preview or a browser.
- [ ] **Exact pixels.** Saved image matches the frozen frame pixel for pixel at native resolution, with no overlay, crosshair or loupe in it.
- [ ] **Speed.** Overlay appears within 150 ms of the hotkey and closes within 300 ms of mouse-up.

### File format

- **PNG (default):** lossless, sharp text, saved as `.png`.
- **JPEG (option):** picked in the menu bar menu under Format. Saved as `.jpg`.
- **JPEG quality slider:** 0% to 100% in steps of 5, shown in the menu under Format with its current value (e.g. "Quality: 85%"). Default 85%. The slider is greyed out while PNG is selected.
- Format and quality are remembered across restarts (UserDefaults).
- The clipboard always gets PNG, whichever format is saved, so pasting stays sharp.

### File naming

`screenshot-<date>_<time>-<app>-<window title>.png`, using the window that was active when Cmd+Shift+X was pressed (read before the overlay appears).

| Situation | Example file name |
| --- | --- |
| Browser | `screenshot-2026-10-17_15-08-12-Chrome-GitHub - Pull request 42 Fix login.png` |
| Other app with a title | `screenshot-2026-10-17_15-08-12-Xcode-AppDelegate.swift.png` |
| App with no window title | `screenshot-2026-10-17_15-08-12-Finder.png` |
| Nothing available | `screenshot-2026-10-17_15-08-12.png` |

Rules:
- Time uses `-` instead of `:` because macOS filenames can't safely contain `:` (Finder shows it as `/`).
- App + title part is capped at **80 characters**, cut at a word boundary, trailing spaces/dots removed.
- Characters `/ : \ * ? " < > |` and newlines are replaced with a space; repeated spaces collapsed.
- If a file with the same name exists (two shots in the same second), append `-2`, `-3`, …
- Window title comes from the window list (needs Screen Recording permission, which MacScreenshot already requires).

## 5. App lifecycle

MacScreenshot is always running: it starts at login and macOS relaunches it automatically if it crashes or is force-quit.

1. **Auto start.** Registered as a login item (SMAppService); launches at login with no window.
2. **Auto restart.** A LaunchAgent with KeepAlive relaunches MacScreenshot within a few seconds if it exits unexpectedly. Quit from the menu stops it until next login.
3. **Menu bar icon.** Camera icon with:
    - Capture (Cmd+Shift+X), Capture Last Region (Cmd+Shift+Control+X)
    - Save as PNG / Save as JPEG, JPEG quality slider
    - Shutter Sound (on/off), Shutter volume slider (0–100%, steps of 5, plays a preview; greyed out when sound is off)
    - Save to: current folder, Change Save Location… (folder picker), Use macOS Screenshots Folder (shown only when a custom folder is set), Open Screenshots Folder
    - Keyboard Shortcuts… (record new combinations for Capture and Capture Last Region; must include ⌘, ⌥ or ⌃; duplicates and combinations owned by other apps are rejected; Restore Defaults)
    - How to Use…, Send Feedback…, Support MacScreenshot ♥
    - Start at Login (auto-restart), Memory usage readout, Quit
6. **Hidden menu bar icon.** Opening the app again (Finder, Spotlight, Launchpad) restores the icon and shows the How to Use window, which has a Show Menu button with every setting.
4. **First-run permissions.** macOS requires Screen Recording permission. On first launch MacScreenshot opens the right System Settings pane and explains why; captures stay disabled until granted.
5. **Install.** Built with Xcode / `swift build` into `MacScreenshot.app`, copied to /Applications. No App Store, no sandbox.

## 6. Memory usage

MacScreenshot runs all day, so it must stay small when idle and give back memory after every capture.

| State | Target RAM |
| --- | --- |
| Idle (menu bar only) | under 30 MB |
| Overlay open, one 5K display | under 150 MB (the frozen frame alone is ~60 MB at 5120 x 2880 x 4 bytes) |
| After capture finishes | back to idle within 2 s |

How it's kept low and tracked:

- Overlay window, frozen image and loupe are created on hotkey and fully released when the overlay closes; nothing is cached between captures.
- Capture only the one active display, not all displays.
- PNG encoding runs on a background queue and its buffers are freed immediately.
- Menu bar shows current memory (read from `task_info` / phys_footprint), so you can see it at a glance.
- After the build I'll measure idle and peak with `footprint` and Activity Monitor over 20 back-to-back captures and report the numbers (checking for leaks/growth).

## 7. Decisions

1. **Esc before dragging:** one Esc from the plain crosshair exits immediately (as above). OK, or should it also need two presses?
2. **Multiple monitors:** freeze only the screen under the pointer (as above), or freeze all screens and let you drag on any of them?
3. **Save location:** macOS Screenshots folder (as above), or a fixed folder like `~/Pictures/MacScreenshot`?
4. ~~File name~~ — decided: `screenshot-date_time-app-title` (see File naming).
5. **Feedback:** shutter sound on success, OK? Also a small thumbnail toast in the corner, or nothing?
6. ~~Auto restart~~ — confirmed: start at login + relaunch on crash.

## 8. Editor (v1.1.0)

**⌘⌥⇧X** (menu: Edit Last Capture…) opens the most recent capture in a simple editor. Quick captures stay exactly as fast as before; editing only happens when you ask for it.

| Tool | Key | How it works |
| --- | --- | --- |
| Crop | C | Drag a rectangle; the image is trimmed to it on release |
| Arrow | A | Drag from tail to tip |
| Box | B | Drag a rectangle outline |
| Circle | O | Drag an oval / circle outline |
| Text | T | Click, type, press Return; size S / M / L / XL, weight Regular / Bold / Heavy |
| Highlight | H | Drag over text; semi-transparent marker colour |

- **Colours:** red (default), orange, yellow, green, blue, black, white.
- **Thickness:** Thin / Medium (default) / Thick for arrows, boxes and circles.
- The toolbar shows only the options for the current tool (thickness for shapes; size and weight for text).
- **Undo / Redo:** ⌘Z / ⇧⌘Z (up to 30 steps), also toolbar buttons.
- **Save** (⌘S or Return): keeps the original, writes `<original name>-edited.<ext>` next to it, copies to clipboard, closes.
- **Replace:** overwrites the original file, copies to clipboard, closes.
- **ⓘ** explains the two buttons; **both always copy the image to the clipboard.**
- The saved file keeps the original's format (PNG/JPEG) and resolution; the clipboard always gets PNG.
- Closing with unsaved edits asks "Discard edits?". Esc closes.
- If there's no capture yet, or the file was moved/deleted, an alert says so.
- The shortcut is changeable in Keyboard Shortcuts like the others.
- **Separate app (1.1.1):** the editor is "MacScreenshot Editor", a nested app at `MacScreenshot.app/Contents/Helpers/`. It runs in its own process, shows its own name in Activity Monitor and a Dock icon while open, and quits when its last window closes. Capture never depends on it, and killing it can't affect ⌘⇧X.
- Both apps share one preferences domain (`io.github.cjayxyz.MacScreenshot`), so JPEG quality, shutter and folder settings apply to edits too.
- Memory: the capture app stays ~12 MB idle (~17 MB after captures, flat). The editor's memory is freed entirely when it quits.
