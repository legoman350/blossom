import AppKit
import ApplicationServices

extension SnapPosition {
    /// A small screen outline with the snapped region filled, for menus and Settings.
    /// Drawn from the same `fractions` the snapping uses, so the icon can't drift from
    /// the behavior. It's a template image, so it follows light/dark mode and menu
    /// highlighting.
    ///
    /// `template: false` draws in `labelColor` instead, resolved each time the image is
    /// drawn, so it still follows light/dark mode where template tinting isn't applied
    /// (images embedded in text).
    func icon(size: NSSize = NSSize(width: 20, height: 14), template: Bool = true) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in  // flipped: y grows downward, like `fractions`
            let color: NSColor = template ? .black : .labelColor
            let screen = bounds.insetBy(dx: 0.5, dy: 0.5)
            let outline = NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2)
            outline.lineWidth = 1
            color.setStroke()
            outline.stroke()

            let inner = screen.insetBy(dx: 2, dy: 2)
            let region: NSRect
            if let (fx0, y0, fx1, y1) = self.fractions {
                // Positions that keep the window's width: show a narrower block, so the
                // icon doesn't look like a full-width half.
                let (x0, x1) = self.keepsHorizontal ? (CGFloat(0.3), CGFloat(0.7)) : (fx0, fx1)
                // Leave a 1pt gap on inner edges so halves and thirds read as separate panes.
                let left = inner.minX + inner.width * x0 + (x0 > 0 ? 0.5 : 0)
                let right = inner.minX + inner.width * x1 - (x1 < 1 ? 0.5 : 0)
                let top = inner.minY + inner.height * y0 + (y0 > 0 ? 0.5 : 0)
                let bottom = inner.minY + inner.height * y1 - (y1 < 1 ? 0.5 : 0)
                region = NSRect(x: left, y: top, width: right - left, height: bottom - top)
            } else {
                region = inner.insetBy(dx: inner.width * 0.25, dy: inner.height * 0.22)  // center
            }
            color.setFill()
            NSBezierPath(roundedRect: region, xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = title
        return image
    }
}

/// Snaps the focused window to a part of its own screen: halves, corners, thirds,
/// maximize, center. Independent of tiling. A tiled layout can still be restored afterwards.
enum Snap {
    /// One position, or a cycle: if the window already sits at one of `positions`, go to
    /// the next one (wrapping); otherwise start at the first. Stateless: the window's
    /// current frame is the state, so cycling picks up correctly after manual moves too.
    /// Returns the position applied, or nil if nothing moved.
    @discardableResult
    static func focusedWindow(cycling positions: [SnapPosition]) -> SnapPosition? {
        guard let first = positions.first else { return nil }
        guard positions.count > 1, let window = AX.focusedWindow(), let frame = AX.frame(of: window),
              let screen = Geometry.screen(containing: frame) ?? NSScreen.main else {
            return focusedWindow(to: first)
        }
        let area = Geometry.axRect(fromCocoa: screen.visibleFrame)
        return focusedWindow(to: LayoutEngine.nextSnap(in: positions, window: frame, area: area, gap: Tiler.gap))
    }

    /// Returns `position` if the window moved, nil otherwise.
    @discardableResult
    static func focusedWindow(to position: SnapPosition) -> SnapPosition? {
        guard Permissions.isTrusted(prompt: true) else { return nil }
        guard let window = AX.focusedWindow(), let frame = AX.frame(of: window) else {
            NSSound.beep()  // nothing focused, e.g. the desktop
            return nil
        }
        // Full-screen windows live in their own Space and can't be moved.
        guard !AX.isFullScreen(window), let screen = Geometry.screen(containing: frame) ?? NSScreen.main else {
            NSSound.beep()
            return nil
        }
        let area = Geometry.axRect(fromCocoa: screen.visibleFrame)  // excludes menu bar and Dock
        let target = LayoutEngine.snapFrame(position, in: area, gap: Tiler.gap, window: frame)

        // setFrame moves only if the window can't resize. A window with a minimum size
        // larger than the target stays bigger; that's accepted, as Rectangle does.
        guard let actual = AX.setFrame(window, target) else {
            NSSound.beep()
            return nil
        }
        // Keep a window that came out smaller than asked (fixed size, or Terminal snapping
        // to its grid) centered on the spot it was meant for.
        if actual.width < target.width - 1 || actual.height < target.height - 1 {
            AX.setPosition(window, CGPoint(x: (target.midX - actual.width / 2).rounded(),
                                           y: (target.midY - actual.height / 2).rounded()))
        }
        return position
    }

    /// Fill Empty Space: grow the focused window into the largest empty part of its screen,
    /// the biggest rectangle no other window on this desktop covers. Every visible window
    /// counts, floating ones too, and the focused window may itself be floating (nothing
    /// here filters floats out). Beeps if there's no room left.
    static func fillEmptySpace() {
        guard Permissions.isTrusted(prompt: true) else { return }
        guard let window = AX.focusedWindow(), let frame = AX.frame(of: window), !AX.isFullScreen(window),
              let screen = Geometry.screen(containing: frame) ?? NSScreen.main else {
            NSSound.beep()
            return
        }
        let screenRect = Geometry.axRect(fromCocoa: screen.frame)
        let area = Geometry.axRect(fromCocoa: screen.visibleFrame)
        // tileableWindows skips windows that can't move, but those still take up space, so
        // ask for every on-screen window here.
        let others = WindowEnumerator.tileableWindows(includeUnmovable: true)
            .filter { !CFEqual($0.element, window) && screenRect.intersects($0.frame) }
            .map(\.frame)
        guard let target = LayoutEngine.fillFrame(in: area, avoiding: others, gap: Tiler.gap),
              let actual = AX.setFrame(window, target) else {
            NSSound.beep()
            return
        }
        if actual.width < target.width - 1 || actual.height < target.height - 1 {
            AX.setPosition(window, CGPoint(x: (target.midX - actual.width / 2).rounded(),
                                           y: (target.midY - actual.height / 2).rounded()))
        }
    }

    /// Menu icon for Fill Empty Space: another window on the left, ours filling the rest.
    static func fillIcon(size: NSSize = NSSize(width: 20, height: 14), template: Bool = true) -> NSImage {
        let image = NSImage(size: size, flipped: true) { bounds in
            let color: NSColor = template ? .black : .labelColor
            let screen = bounds.insetBy(dx: 0.5, dy: 0.5)
            color.setStroke()
            NSBezierPath(roundedRect: screen, xRadius: 2, yRadius: 2).stroke()
            let inner = screen.insetBy(dx: 2, dy: 2)
            let split = inner.minX + inner.width * 0.4
            let other = NSRect(x: inner.minX + 0.5, y: inner.minY + 0.5, width: split - inner.minX - 1.5, height: inner.height * 0.6)
            NSBezierPath(roundedRect: other, xRadius: 1, yRadius: 1).stroke()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: split + 0.5, y: inner.minY, width: inner.maxX - split - 0.5, height: inner.height),
                         xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "Fill Empty Space"
        return image
    }
}
