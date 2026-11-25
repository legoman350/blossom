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

## Tiling

| Action | Result |
| --- | --- |
| **⌃⌥⌘T** | Tile all windows on the current desktop, or restore the saved layout |
| Menu → Forget Saved Layout | Drop the saved layout so the next press tiles afresh |

- One window fills the screen, two split it in half, and more use a near-square grid.
- At most 8 windows are tiled; any beyond that are left alone.
- Works on the display holding the focused window.
- Full-screen windows and windows that refuse resizing are skipped.
- Windows with a large minimum size may overlap their neighbor.

## Tuck

### Setup

1. Right-click an app's Dock icon → **Options** → **Assign To** → **All Desktops**.
2. Its icon appears in your menu bar within ~3 seconds.

You can also tick any running app under **Tuck Apps** in Blossom's menu. To stop managing
an app, set its Dock assignment back to **None**, or untick it.

Tuck doesn't move anything. macOS already puts All-Desktops windows on every desktop, so
Tuck just switches the app between hidden and shown, using only supported APIs.

### Use

| Action | Result |
| --- | --- |
| Click an app icon | Tuck the app away, or bring it back to this desktop |
| Right-click (or ctrl-click) an app icon | Menu: Show/Tuck Away, Tuck All Away, Auto-tuck, new-window option, Refresh |
| **⌘⇧H** | Tuck all tracked apps away, or bring them all back |
| Dimmed icon | That app is tucked away (hidden or minimized) |

**Auto-tuck** is set per app: off, when the app loses focus, or when you switch Spaces
(the default).

Settings from the standalone Tuck app are imported automatically on first launch. Quit the
old Tuck.app so the two don't both claim ⌘⇧H.

### Known limitations

- **Hiding is per app, not per window.** Everything the app has open is hidden.
- **Menu bar space is finite.** On a notched MacBook Pro, icons that overflow past the
  notch don't render. Three or four tracked apps is a comfortable ceiling.
- **The Dock tile stays**, and a tucked app is still in ⌘-Tab and Mission Control.
  Removing it from those needs private APIs.
- **Full-screen apps are out of scope.** macOS won't assign them to All Desktops.
- **Finder** resists hiding and behaves oddly if tracked.
- The app list refreshes on a 3-second poll.
- If no icons appear for Dock-assigned apps, the read of the Dock setting may have broken
  on your macOS version. Use the **Tuck Apps** list instead.
