# Status Bar Feature: Per-Tile Script-Driven Status Bar

## Context

Add a configurable status bar at the bottom of each terminal tile. Users provide a shell script via config (`status-bar-script = ~/.config/ghostty/statusbar.sh`). Ghostty invokes this script on terminal events (command start/finish, pwd change) and on a periodic timer, passing context as environment variables. The script outputs a JSON array of styled segments, which Ghostty renders as a dedicated bar below the terminal surface.

This is macOS-only for the initial implementation. GTK support deferred to follow-up.

---

## Step 1: Configuration

**File: `src/config/Config.zig`**
- Add `@"status-bar-script": ?Path = null` config option (follows `bell-audio-path` pattern)
- Uses existing `Path` type from `src/config/path.zig` — handles `~/` expansion, optional `?` prefix, quoting automatically

**File: `macos/Sources/Ghostty/Ghostty.Config.swift`**
- Add `statusBarScript` computed property to read config via `ghostty_config_get()` (follows `bellAudioPath` pattern)

---

## Step 2: Action Type (C ABI Bridge)

**File: `src/apprt/action.zig`**
- Add `status_bar_update: StatusBarUpdate` to `Action` union
- Add `status_bar_update` to `Key` enum (at end for ABI compat)
- Define `StatusBarUpdate` extern struct: pass raw JSON string (`[*:0]const u8` + `json_len: usize`) across C boundary — Swift-side parses it. Avoids complex variable-length C structs.

**File: `include/ghostty.h`**
- Add `GHOSTTY_ACTION_STATUS_BAR_UPDATE` to `ghostty_action_tag_e`
- Add `ghostty_action_status_bar_update_s` struct (json pointer + length)
- Add to `ghostty_action_u` union

---

## Step 3: Message & Event Triggers

**File: `src/apprt/surface.zig`**
- Add `refresh_status_bar` variant to `Message` union

**File: `src/termio/stream_handler.zig`**
- In `semanticPrompt()`: send `refresh_status_bar` message on `end_input_start_output` (command start) and `end_command` (command finish)
- In `reportPwd()`: send `refresh_status_bar` message after pwd change

---

## Step 4: Script Execution Engine (most complex)

**File: `src/Surface.zig`**

Add status bar state fields to Surface struct:
- `status_bar_script_path: ?[:0]const u8` — resolved from config
- `status_bar_last_run: ?std.time.Instant` — for debouncing (200ms)
- `status_bar_pending: bool` — coalesce rapid events
- `status_bar_thread: ?std.Thread` — currently running script

Handle `refresh_status_bar` message in `handleMessage()`:
1. If no script configured → return
2. Debounce: if <200ms since last run → set pending, return
3. If thread already running → set pending, return
4. Spawn new thread:
   - Fork child process via `std.process.Child`
   - Set env vars: `GHOSTTY_PWD`, `GHOSTTY_EXIT_CODE`, `GHOSTTY_COLS`, `GHOSTTY_ROWS`
   - Capture stdout, apply 5-second timeout
   - Send result via `performAction(.status_bar_update, ...)`
   - On completion, check `status_bar_pending` to re-run if needed

Periodic timer: add a 30-second (configurable) refresh timer that sends `refresh_status_bar` to itself.

---

## Step 5: macOS Swift — Data Model

**New file: `macos/Sources/Features/StatusBar/StatusBarSegment.swift`**

```swift
struct StatusBarSegment: Identifiable, Codable {
    let text: String
    let fg: String?       // hex color e.g. "#a6e3a1"
    let bg: String?       // hex color
    let bold: Bool?
    let italic: Bool?
    let underline: Bool?
    let align: String?    // "left" (default) or "right"

    static func parse(json: String) -> [StatusBarSegment]
}
```

---

## Step 6: macOS Swift — Action Handler

**File: `macos/Sources/Ghostty/Ghostty.App.swift`**
- Add `GHOSTTY_ACTION_STATUS_BAR_UPDATE` case to action switch
- Parse JSON string into `[StatusBarSegment]`
- Set `surfaceView.statusBarSegments` on main queue

**File: `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift`**
- Add `@Published var statusBarSegments: [StatusBarSegment] = []`

---

## Step 7: macOS Swift — StatusBar View

**New file: `macos/Sources/Features/StatusBar/StatusBarView.swift`**

SwiftUI view rendering segments in an HStack:
- Left-aligned segments on the left, Spacer, right-aligned on the right
- Fixed height (~22px), full width
- Background matches terminal theme or uses semi-transparent dark background
- Supports text color, background color, bold/italic/underline per segment

---

## Step 8: Layout Integration

**File: `macos/Sources/Ghostty/Surface View/SurfaceView.swift`**

Wrap the existing `ZStack` in `SurfaceWrapper.body` with a `VStack`:

```swift
VStack(spacing: 0) {
    ZStack {
        // ... existing GeometryReader + overlays (unchanged) ...
    }

    // Status bar below terminal — takes dedicated space
    if !surfaceView.statusBarSegments.isEmpty {
        StatusBarView(segments: surfaceView.statusBarSegments)
    }
}
```

**Row reduction happens automatically**: The `GeometryReader` inside the ZStack reports a smaller height when the status bar is visible → Surface recalculates grid → PTY gets `TIOCSWINSZ` with fewer rows. No manual row math needed.

---

## Step 9: Xcode Project

**File: `macos/Ghostty.xcodeproj/project.pbxproj`**
- Add `StatusBarView.swift` and `StatusBarSegment.swift` to the project

---

## JSON Segment Format (for user scripts)

```json
[
  {"text": "\ue0b0 main", "fg": "#a6e3a1", "bg": "#313244", "bold": true},
  {"text": " ~/dev/ghostty ", "fg": "#cdd6f4"},
  {"text": " 0 ", "fg": "#a6e3a1", "align": "right"}
]
```

## Environment Variables Passed to Script

| Variable | Description |
|----------|-------------|
| `GHOSTTY_PWD` | Current working directory |
| `GHOSTTY_EXIT_CODE` | Last command exit code |
| `GHOSTTY_COLS` | Terminal column count |
| `GHOSTTY_ROWS` | Terminal row count |

---

## Verification

1. Add `status-bar-script = ~/.config/ghostty/statusbar.sh` to config
2. Create a test script that outputs styled JSON segments
3. Open Ghostty — status bar should appear below terminal
4. Run `cd /tmp` — status bar should refresh showing new pwd
5. Run a command — status bar should refresh on completion
6. Verify terminal programs see correct (reduced) row count via `tput lines`
7. Verify splits each get their own independent status bar
8. Kill the script mid-run — verify 5s timeout, no hang
