# Blossom

A macOS menu bar utility with two jobs:

- **Tile** — one hotkey tiles every window on the current desktop into a grid; press
  again to put them all back. The windows are actually moved, so you can keep working in
  the tiled layout.
- **Tuck** — a menu-bar tray for apps you've assigned to **All Desktops** in the Dock.
  Click an app's icon to hide it, click again to bring it back *on the desktop you're on*
  — no "auto-swoosh" to another Space.

Formerly **Tuck**; the tray app was merged into Blossom and the repo renamed.

Keywords: window tiling, grid layout, auto-swoosh, all desktops, space switching, multiple
desktops, menu bar utility, app hider, window management, macOS Spaces

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```
./build.sh            # builds ./Blossom.app
./build.sh install    # builds, copies to /Applications, launches
./build.sh test       # runs the layout engine tests
```

## Permissions

**Accessibility** is the only permission, and tiling needs it to move and resize other
apps' windows. Grant it in **System Settings → Privacy & Security → Accessibility**. The
menu bar item shows whether it's granted.

Tuck's hide/show works without it. Accessibility is used only for the optional "open a
new window when the app has none".

The build is ad-hoc signed. If tiling silently stops working after a rebuild, remove
Blossom from the Accessibility list and add it again.

## Settings and hotkeys

Choose **Settings…** (⌘,) in Blossom's menu to change hotkeys. Click a field and press
the new combination: it needs ⌘, ⌃ or ⌥, unless it's an F-key. Esc cancels, and **Clear**
turns that hotkey off. If another app already owns a combination, Blossom says so and
keeps the old one.

| Action | Default |
| --- | --- |
| Tile / Restore | ⌃⌥T |
| Tile Others | ⌃⌥A |
| Tuck All / Show All | ⌃⌥H |
| Next Layout | ⌃⌥N |
| Forget Saved Layout | none |

Every default uses **⌃⌥**. To use different modifier keys for all of them at once (⌃⌘, ⌥⌘,
⌃⌥⌘ or ⌃⌥⇧), change **Modifier keys** at the top of Settings → Hotkeys. Shortcuts you've
recorded yourself keep their own keys.

The Settings window also holds the gap between windows (0–12 pt in 1 pt steps, default 8), the Floating
Windows mode and *Reset learned window sizes*.

## Snapping

Move the window you're working in to part of its screen. The Snap Window menu has the
same positions. Change any shortcut under **Settings → Snapping**.

| Position | Default |
| --- | --- |
| Left / Right / Top / Bottom half | ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ |
| Top-left / Top-right / Bottom-left / Bottom-right | ⌃⌥U ⌃⌥I ⌃⌥J ⌃⌥K |
| Thirds: press again to cycle left → center → right | ⌃⌥D |
| Two thirds: press again to toggle left ⇄ right | ⌃⌥E |
| Maximize / Center | ⌃⌥↩ ⌃⌥C |

Turn on *After snapping a window, tile the other windows* (Settings → Snapping) and a
snap also tiles everything else into the space left. Snap to the left half and the rest
fills the right. This doesn't happen after Maximize or Center.

**Top / Bottom half** change only the height. The window keeps its position and width, so a
left-third window becomes the top-left third. Press ⌃⌥↑ or ⌃⌥↓ again to stretch it to full height,
and again to go back to the half.

If another window manager already uses these keys, Settings shows them as taken. Pick
others, or quit the other app.

## Tiling

| Action | Result |
| --- | --- |
| **⌃⌥T** | Tile all windows on the current desktop, or restore the saved layout |
| **⌃⌥A** | Tile Others: keep the focused window where it is and tile the rest beside it. Press again (or ⌃⌥T) to restore |
| Menu → Forget Saved Layout | Drop the saved layout so the next press tiles afresh |
| Menu → Layout | Grid, Master + Stack (frontmost window gets 60%), or Columns |
| Settings → Floating windows | Leave floating apps alone (default, others may overlap them), tile around them, or tile them like others |

- One window fills the screen, two split it in half, and more use a near-square grid.
- At most 8 windows are tiled; any beyond that are left alone.
- Works on the display holding the focused window.
- Full-screen windows are skipped. Windows that can't be resized are placed at their own
  size, centered in a cell.
- Minimum window sizes are learned per app, and stubborn windows get bigger cells. Windows
  overlap only when nothing fits.
- Floating apps (below) are never tiled. By default they're left where they are and other windows may tile underneath them. Choose *Tile Around Them* in Settings to keep the space they use clear.

## Tuck

### Setup

1. Right-click an app's Dock icon → **Options** → **Assign To** → **All Desktops**.
2. Its icon appears in your menu bar within ~3 seconds.

You can also tick any running app under **Floating Apps** in Blossom's menu. To stop managing
an app, set its Dock assignment back to **None**, or untick it.

Tuck doesn't move anything. macOS already puts All-Desktops windows on every desktop, so
Tuck just switches the app between hidden and shown, using only supported APIs.

### Use

| Action | Result |
| --- | --- |
| Click an app icon | Tuck the app away, or bring it back to this desktop |
| Right-click (or ctrl-click) an app icon | Menu: Show/Tuck Away, Tuck All Away, Auto-tuck, new-window option, Refresh |
| **⌃⌥H** | Tuck all floating apps away, or bring them all back |
| Dimmed icon | That app is tucked away (hidden or minimized) |

**Auto-tuck** is set per app: off, when the app loses focus, or when you switch Spaces
(the default).

Settings from the standalone Tuck app are imported automatically on first launch. Quit the
old Tuck.app so you don't get two icons for every floating app.

### Known limitations

- **Hiding is per app, not per window.** Everything the app has open is hidden.
- **Menu bar space is finite.** On a notched MacBook Pro, icons that overflow past the
  notch don't render. Three or four floating apps is a comfortable ceiling.
- **The Dock tile stays**, and a tucked app is still in ⌘-Tab and Mission Control.
  Removing it from those needs private APIs.
- **Full-screen apps are out of scope.** macOS won't assign them to All Desktops.
- **Finder** resists hiding and behaves oddly as a floating app.
- The app list refreshes on a 3-second poll.
- If no icons appear for Dock-assigned apps, the read of the Dock setting may have broken
  on your macOS version. Use the **Floating Apps** list instead.
