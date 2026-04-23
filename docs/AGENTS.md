# AGENTS.md - THISCREEN

macOS screen capture app with annotation tools. Background-only agent (no Dock icon).

## Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Entry Point | `THISCREENApp.swift` | App delegate, hotkey init, empty SwiftUI Scene |
| Window Manager | `WindowManager` singleton | Owns permanent `NSWindow` (never destroyed, only hidden/shown) |
| State | `CaptureManager` singleton | Screenshots, recordings, save directory |
| UI | `ContentView.swift` | Drawing canvas, toolbar, save dialogs |
| Hotkeys | `GlobalHotkeyManager.swift` | Carbon global hotkey registration |

## Build & Run

```bash
open THISCREEN.xcodeproj
# Or:
xcodebuild -project THISCREEN.xcodeproj -scheme THISCREEN -configuration Debug
```

No external dependencies. Standard Xcode project using `PBXFileSystemSynchronizedRootGroup`.

## Critical Implementation Details

### Window Level Quirk
Window uses `level = .popUpMenu + 1` to appear above other apps. This causes save dialogs to appear behind the window. **Always use `runModal()` instead of `beginSheetModal()`** for save panels.

See: `ContentView.presentSavePanel()` - already handles this.

### Window Lifecycle
- `isReleasedWhenClosed = false` — window lives forever
- Never destroy the window; use `orderOut()` to hide, `makeKeyAndOrderFront()` to show
- Always call `configureOverlay()` before showing to reset window level
- Window starts hidden — no "Ready for Capture" screen at launch

### Background-Only App
- `NSApp.setActivationPolicy(.accessory)` in `AppDelegate.applicationDidFinishLaunching()`
- Status bar item provides menu access
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`

### Global Hotkeys (Carbon)
Registered in `GlobalHotkeyManager.setupHotkeys()`:
- ⌘⇧S: Capture area
- ⌘⇧A: Record entire screen
- ⌘⇧R: Record selected area
- ⌘⇧T: Stop recording

Requires accessibility permissions in System Settings.

### Screenshot & Recording
- Uses `/usr/sbin/screencapture` system binary
- App hides itself before capture via `NSApp.hide(nil)`
- Video recording requires macOS 14.0+ (uses `-v` flag)
- Temporary files in `NSTemporaryDirectory()`, then copied to destination

### Default Save Directory
Created automatically at `~/Pictures/THISCREEN/` on app launch via `CaptureManager.getDefaultSaveDirectory()`.

### File Operations
All file I/O must happen on background queue:

```swift
DispatchQueue.global(qos: .userInitiated).async {
    // File operations here
    DispatchQueue.main.async {
        // UI updates here
    }
}
```

### Drawing Tools
Tool keyboard shortcuts (when screenshot loaded): V (select), P (pen), L (line), A (arrow), R (rectangle), O (oval), X (pixelate), T (text), K (crop).

Pixelation uses `CIPixellate` Core Image filter cached in `pixelatedImage`.

### Inter-Component Communication
Uses `NotificationCenter` with names: `TriggerCapture`, `TriggerRecord`, `TriggerStopRecord`, `TriggerEntireRecord`, `TriggerShowWindow`, `TriggerUndo`, `TriggerCopy`, `TriggerSave`, `TriggerAutoSaveVideo`.

## Testing

No automated tests. Manual verification:
1. Build and run
2. Press ⌘⇧S to capture
3. Draw annotations
4. Save to verify dialog appears correctly
5. Check `~/Pictures/THISCREEN/` for saved files

## Common Issues

- **Save dialog behind window**: Ensure `runModal()` is used, not `beginSheetModal()`
- **Window not appearing**: Check `WindowManager.show()` — window level may need reset via `configureOverlay()`
- **Hotkeys not working**: Verify accessibility permissions in System Settings > Privacy & Security
- **Recording fails**: Requires macOS 14.0+; check Screen Recording permissions
