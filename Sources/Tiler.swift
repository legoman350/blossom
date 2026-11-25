import AppKit
import ApplicationServices

/// Owns the snapshot and the strict toggle:
/// no snapshot → tile and save one; snapshot → restore it and drop it.
/// The snapshot stays until restored or explicitly forgotten. If the user hand-moves
/// windows while tiled, restore still puts them back. That's deliberate.
final class Tiler {
    static let gap: CGFloat = 8

    private var snapshot: [(element: AXUIElement, frame: CGRect)]?

    var hasSnapshot: Bool { snapshot != nil }

    func toggle() {
        guard Permissions.isTrusted(prompt: true) else { return }
        if let saved = snapshot {
            restore(saved)
            snapshot = nil
        } else {
            tile()
        }
    }

    func forgetSnapshot() {
        snapshot = nil
    }

    private func tile() {
        guard let screen = focusedScreen() else { return }
        let screenRect = Geometry.axRect(fromCocoa: screen.frame)
        let usable = Geometry.axRect(fromCocoa: screen.visibleFrame)  // already excludes menu bar and Dock

        // Phase 1: only the display with keyboard focus. Windows are frontmost first, so if
        // there are more than the cap, the ones buried at the back are left alone.
        let windows = WindowEnumerator.tileableWindows()
            .filter { screenRect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .prefix(LayoutEngine.maxWindows)

        let targets = LayoutEngine.frames(count: windows.count, in: usable, style: .grid, gap: Self.gap)
        var saved: [(element: AXUIElement, frame: CGRect)] = []
        for (window, target) in zip(windows, targets) where AX.setFrame(window.element, target) {
            saved.append((window.element, window.frame))
        }

        // If nothing moved, stay untiled. Otherwise the next press would "restore" nothing
        // and the user would have to press twice to tile.
        if saved.isEmpty {
            NSSound.beep()
        } else {
            snapshot = saved
        }
    }

    private func restore(_ saved: [(element: AXUIElement, frame: CGRect)]) {
        // Windows closed while tiled fail the write and are skipped silently. Windows
        // opened while tiled aren't in the snapshot, so they're left where they are.
        for entry in saved {
            AX.setFrame(entry.element, entry.frame)
        }
    }

    /// The screen holding the focused window of the frontmost app. Falls back to
    /// NSScreen.main when there is no focused window, for example on an empty desktop.
    private func focusedScreen() -> NSScreen? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, AX.messagingTimeout)
        var app: CFTypeRef?, window: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
           let app, CFGetTypeID(app) == AXUIElementGetTypeID(),
           AXUIElementCopyAttributeValue(app as! AXUIElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
           let frame = AX.frame(of: window as! AXUIElement) {
            let center = CGPoint(x: frame.midX, y: frame.midY)
            if let screen = NSScreen.screens.first(where: { Geometry.axRect(fromCocoa: $0.frame).contains(center) }) {
                return screen
            }
        }
        return NSScreen.main
    }
}

enum Geometry {
    /// NSScreen uses a bottom-left origin; Accessibility uses a top-left origin anchored to
    /// the primary display (screens[0], the one with the menu bar). Skip this and windows
    /// land off-screen.
    static func axRect(fromCocoa rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
