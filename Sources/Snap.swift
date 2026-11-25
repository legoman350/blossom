import AppKit
import ApplicationServices

/// Snaps the focused window to a part of its own screen: halves, corners, thirds,
/// maximize, center. Independent of tiling. A tiled layout can still be restored afterwards.
enum Snap {
    static func focusedWindow(to position: SnapPosition) {
        guard Permissions.isTrusted(prompt: true) else { return }
        guard let window = AX.focusedWindow(), let frame = AX.frame(of: window) else {
            NSSound.beep()  // nothing focused, e.g. the desktop
            return
        }
        // Full-screen windows live in their own Space and can't be moved.
        guard !AX.isFullScreen(window), let screen = Geometry.screen(containing: frame) ?? NSScreen.main else {
            NSSound.beep()
            return
        }
        let area = Geometry.axRect(fromCocoa: screen.visibleFrame)  // excludes menu bar and Dock
        let target = LayoutEngine.snapFrame(position, in: area, gap: Tiler.gap, windowSize: frame.size)

        // setFrame moves only if the window can't resize. A window with a minimum size
        // larger than the target stays bigger; that's accepted, as Rectangle does.
        guard let actual = AX.setFrame(window, target) else {
            NSSound.beep()
            return
        }
        // Keep a window that came out smaller than asked (fixed size, or Terminal snapping
        // to its grid) centered on the spot it was meant for.
        if actual.width < target.width - 1 || actual.height < target.height - 1 {
            AX.setPosition(window, CGPoint(x: (target.midX - actual.width / 2).rounded(),
                                           y: (target.midY - actual.height / 2).rounded()))
        }
    }
}
