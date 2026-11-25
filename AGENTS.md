# AGENTS.md

**Blossom**: a macOS menu bar utility with two features, tiling and Tuck.

## What it does

**Tiling (⌃⌥⌘T).** One global hotkey tiles every window on the current desktop into a
grid. Press again to restore the previous layout. Unlike Mission Control / Exposé, the
windows are *actually moved*, so the tiled layout is real and the user can keep working in
it indefinitely. The saved snapshot persists until explicitly cleared, so restore stays
available.

**Tuck (⌘⇧H).** A menu bar tray, merged in from the standalone Tuck app (the original is
kept in `tuck/` for reference; it is not built). Every floating app gets its own menu bar
icon. Clicking it hides the app or shows it again, which avoids macOS "auto-swoosh" (the
desktop switch when you activate an app assigned to None or This Desktop). Tracked apps are
those assigned to **All Desktops** in the Dock, plus a manual "Floating Apps" list in the main
menu. All-Desktops windows already exist on every desktop, so Tuck only toggles visibility
and never moves anything between desktops. ⌘⇧H tucks all floating apps, or shows them all.

**Naming:** apps in that set are **floating apps**; "tuck" is the hide/show action.

## Hard constraints — do not violate

These are settled decisions, not open questions. Do not relitigate them in code.

- **Public APIs only.** No private SkyLight / CoreGraphics Services calls. No code
  injection. Nothing that requires the user to disable System Integrity Protection.
- **Accessibility permission is the only permission.** Do not add Screen Recording,
  Input Monitoring, or Automation unless the user explicitly asks for a feature that
  needs it.
- **Never move a window between desktops (Spaces).** There is no public API, and the
  private route is blocked cross-process since macOS 15. The app operates on the
  *current* desktop only. If a feature seems to need cross-desktop moves, stop and say so.
- **Never write to `com.apple.spaces` or `com.apple.dock`.** Apple treats preference
  files as implementation detail, not API. Reading is acceptable *with a fallback path*;
  writing is not.
- **Do not use `NSEvent.addGlobalMonitorForEvents` for the hotkey.** It is passive — the
  keystroke still reaches the frontmost app. Use Carbon `RegisterEventHotKey`.
- **Do not trust `defaults read` for system settings.** Since macOS 14 it reports keys as
  missing when they are active. Never branch on it.

## Build and run

```
./build.sh            # builds ./Blossom.app
./build.sh install    # builds, copies to /Applications, launches
./build.sh test       # runs the LayoutEngine tests (plain runner, no XCTest)
```

Requires Xcode Command Line Tools (`xcode-select --install`).

It must ship as a `.app` bundle with `LSUIElement` = true in Info.plist, ad-hoc signed
with a stable `--identifier`. A bare binary will misbehave: no menu bar item, and the
Accessibility permission grant won't stick across rebuilds.

**You cannot build or test this yourself if you are not on macOS.** Write the code, state
plainly that it is uncompiled, and ask the user to run the build and paste errors back.

## Layout

```
Sources/
  main.swift             NSApplication setup, accessory activation policy, main menu bar item
  Hotkey.swift           Carbon RegisterEventHotKey wrapper (one instance per hotkey)
  Shortcuts.swift        Shortcut model, HotkeyAction list, HotkeyManager (owns all hotkeys)
  SettingsWindow.swift   Settings window (tabs): hotkey recorder, snapping, tiling, floating apps
  Snap.swift             Snaps the focused window to a half/corner/third (frame math in LayoutEngine)
  Permissions.swift      AXIsProcessTrusted checks and the prompt
  WindowEnumerator.swift Finds tileable windows on the current desktop; AX helpers
  LayoutEngine.swift     PURE functions. No AppKit. Frames in, frames out.
  Tiler.swift            Applies layouts, owns the snapshot and the toggle state machine
  Tuck.swift             TuckController: tray sync, hide/show, auto-tuck, per-app menu
  TrayEntry.swift        One menu bar icon per floating app
  TuckWindows.swift      Visible / minimized checks, reopen, "new window" request
  TuckSettings.swift     Per-app auto-tuck mode and new-window setting (UserDefaults)
  SpacesPrefs.swift      Reads Dock "All Desktops" bindings; manual app list fallback
Tests/
  LayoutEngineTests.swift
build.sh
```

**`LayoutEngine.swift` must have zero AppKit/Accessibility dependencies.** It takes a
window count, a usable rect, a style, and a gap, and returns `[CGRect]`. It is the only
part of this project that can be meaningfully unit tested — keep it that way. Everything
that touches live windows is manual-test-only.

## API facts (already verified — do not re-research)

**Finding windows on the current desktop**

`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`.
The on-screen set is effectively "windows on the active desktop". Needs **no permission**
for owner process, bounds and layer. Window *titles* would need Screen Recording — don't
read them.

Filter to: layer == 0; owning app `activationPolicy == .regular`; not our own pid; width
and height both >= 60.

**Pairing window IDs with Accessibility elements**

`CGWindowListCopyWindowInfo` gives window IDs; resizing needs `AXUIElement`. No public
bridge exists. Match by owning process plus frame, with a small tolerance — note that the
vertical origin can differ by the title bar height between the two sources. If frame
matching proves ambiguous in practice, the fallback is the private
`_AXUIElementGetWindow`; ask the user before introducing it.

**Resizing**

```swift
AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, axValue)
AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, axValue)
```

Public, documented, needs Accessibility. Order matters: **position, then size, then
position again.** Constraint resolution shoves windows; the second write is required, not
superstition.

Call `AXUIElementIsAttributeSettable` first and skip windows that refuse.

**Usable screen area**

`NSScreen.visibleFrame` — already excludes menu bar and Dock. Note the coordinate space
mismatch: Accessibility uses a top-left origin on the primary display, `NSScreen` uses
bottom-left. Convert, or windows land off-screen.

**Timeouts**

Set `AXUIElementSetMessagingTimeout` to ~0.2s on each app element before writing.
Accessibility calls are synchronous round-trips; without a timeout a single unresponsive
app freezes the whole tiling operation.

## Known traps

- **Minimum window sizes silently clamp.** A window with a 600px minimum in a 400px cell
  overflows and overlaps its neighbor. There is no reliable public way to ask for the
  minimum: `AXMinimumSize` is missing in most apps, and probing by shrinking to 1×1
  flickers. So minimums are *learned*:
  1. `AX.setFrame` returns the read-back frame.
  2. When it comes back >2px larger than asked, `Tiler` records the size in
     `MinSizeCache` (per app, only ever grows) and re-lays out once with the new minimums.
  3. Read-backs that come back *smaller* are step snapping (Terminal) and are centered in
     the cell, not learned.

  `LayoutEngine.frames(for:)` honors minimums with rows of variable-width cells. It
  overlaps only when nothing fits.
- **Some windows move but can't resize** (dialogs, Calculator). They're tiled at their own
  size, centered in a cell at least that big. Windows that can't even move are skipped.
- **Full-screen windows cannot be resized.** Detect and skip them.
- **Speed.** Ten windows is ~30 round-trips, a few hundred milliseconds of visible
  shuffling. Expected. Do not add threading to hide it in phase 1.
- **Window count.** Tiling 15 windows produces useless slivers. Cap at 8; leave the rest
  untouched.
- **Electron and Java apps** animate, resist, or snap back. The double position write
  handles most cases. Don't special-case individual apps without evidence.
- `NSImage.lockFocus` is deprecated — use `NSImage(size:flipped:drawingHandler:)`.
- Dictionaries: snapshot `Array(dict.keys)` before mutating inside the loop.
- **Every Carbon hotkey handler sees every hotkey press.** `Hotkey` gives each instance a
  unique ID and ignores presses that aren't its own. Removing that check makes ⌘⇧H tile too.
- **Tuck hides per app, not per window.** `hide()` takes everything the app has open.
- **Finder resists `hide()`** and behaves oddly as a floating app.
- **Menu bar space is finite.** On notched MacBooks, icons that overflow past the notch
  don't render at all. Three or four floating apps is a comfortable ceiling.
- A tucked app stays in the Dock, ⌘-Tab and Mission Control. Removing it from those
  needs private APIs.
- The tray refreshes on a 3-second poll: there's no notification for Dock "Assign To"
  changes.

## Behavior decisions

- **Strict toggle.** Hotkey tiles; hotkey again restores. If the user hand-moves a window
  while tiled, restore still restores — do not try to be clever. Provide a separate
  "forget snapshot" menu command instead.
- **All windows, not one per app.** Exposé-like.
- **Windows that closed while tiled** are skipped on restore, silently.
- **Windows that opened while tiled** have no saved frame; leave them alone on restore.
- **Multiple displays:** phase 1 handles the display with keyboard focus only. Phase 2
  tiles each display independently within its own `visibleFrame`.
- **Tuck tracks** the Dock's All-Desktops apps (read from `com.apple.spaces` →
  `app-bindings`, never written) **plus** the manual list. The manual list is the
  required fallback if that read breaks. Matching is case-insensitive.
- **Auto-tuck** is per app: Off, "when it loses focus", or "when switching Spaces"
  (the default).
- **Settings carry over:** on first launch, Tuck settings are imported once from the
  standalone app's `local.tuck.agent` defaults.
- **Floating windows and tiling:** Floating Windows menu, default *Tile Around Them*.
  - Floating windows are never tiled or put in the snapshot.
  - The others tile into `LayoutEngine.freeArea`: the largest rectangle the visible
    floats leave free.
  - If that's under 40% of the screen (a float mid-screen), tile full screen and accept
    the overlap.
  - Tucked (hidden) floats aren't on screen, so they take no space.
  - Other modes: *Leave Alone* (tile underneath) and *Tile Like Others*.

## Phases

**Phase 1 — MVP.** Hotkey, enumerate, grid tile (`columns = ceil(sqrt(n))`, special-case
n=1 fill and n=2 halves), toggle restore, single display, in-memory snapshot, no
animation. Menu bar item with Quit and the permission status. Target ~300 lines.

**Phase 2.** Multiple displays. Minimum-size reflow. Layout styles (grid, master+stack,
columns). Configurable gap. Per-app exclusion list.

**Phase 3.** Snapshots persisted to disk and keyed per desktop. Animated transitions.
Per-app rules.

Do not start phase 2 work while phase 1 is unverified on real hardware.
**Status:** Phase 1 was verified on real hardware on 2026-11-25 (macOS 27.2): tile and
restore work. From phase 2, minimum-size reflow and the layout styles are implemented.
The styles are Grid, Master + Stack (the frontmost window gets 60%) and Columns, chosen
from the Layout submenu. Changing style while tiled re-tiles and keeps the original
snapshot. Still open: multiple displays, configurable gap, per-app exclusion.

## Prior art — read before writing the layout math

- **Amethyst** — open-source automatic tiling window manager for macOS, Accessibility-only,
  no System Integrity Protection changes. Its tiling engine solves exactly this problem.
- **Moom** — ships saved layout snapshots and restore; the other half of this feature.

What this project does — on-demand tile, keep it, restore later — sits between the two.

## Style

- Swift, AppKit, no third-party dependencies.
- Comment *why*, especially where behavior looks superstitious (the double position write,
  the messaging timeout). A future reader will otherwise "clean up" the workarounds.
- Small files, plain structs, no frameworks-within-frameworks.
- When something is impossible on this platform, say so in the response rather than
  shipping a silent no-op.
