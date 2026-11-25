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

    private static let styleKey = "layoutStyle"
    private static let skipTuckAppsKey = "skipTuckAppsWhenTiling"

    /// When on, apps Tuck manages (All Desktops in the Dock, or the manual Tuck list) are
    /// left out of tiling. Their windows float on every desktop, so giving them a cell on
    /// one desktop usually isn't what you want. On by default.
    var skipTuckApps: Bool {
        get { UserDefaults.standard.object(forKey: Self.skipTuckAppsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.skipTuckAppsKey) }
    }

    /// The chosen layout style, remembered across launches.
    var style: LayoutStyle {
        get { UserDefaults.standard.string(forKey: Self.styleKey).flatMap(LayoutStyle.init(rawValue:)) ?? .grid }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.styleKey) }
    }

    /// Switches style. If already tiled, re-tiles straight away in the new style. The
    /// snapshot keeps each window's ORIGINAL frame, so restore still returns to the layout
    /// from before the first tile, not the previous style.
    func setStyle(_ newStyle: LayoutStyle) {
        style = newStyle
        if snapshot != nil, Permissions.isTrusted() { tile() }
    }

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
        // Filter before the cap, so skipped apps don't use up any of the 8 slots.
        let excluded = skipTuckApps ? SpacesPrefs.trackedBundleIDs() : []  // lowercased
        let windows = Array(WindowEnumerator.tileableWindows()
            .filter { screenRect.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            .filter { window in !(window.bundleID.map { excluded.contains($0.lowercased()) } ?? false) }
            .prefix(LayoutEngine.maxWindows))

        // Minimums known before we start: learned on earlier presses, or the window's own
        // size if it can't be resized at all.
        var items = windows.map { window in
            LayoutItem(minSize: MinSizeCache.minSize(for: window.bundleID),
                       fixedSize: window.canResize ? nil : window.frame.size)
        }
        var targets = LayoutEngine.frames(for: items, in: usable, style: style, gap: Self.gap)
        var actual = [CGRect?](repeating: nil, count: windows.count)

        // Pass 1: apply, read back, and learn from any window that came back larger than
        // its cell. That's a minimum size the app enforced silently.
        var learnedSomething = false
        for (i, window) in windows.enumerated() where i < targets.count {
            actual[i] = AX.setFrame(window.element, targets[i])
            guard window.canResize, let got = actual[i], let observed = Self.clampedMinimum(got, asked: targets[i]) else { continue }
            MinSizeCache.learn(observed, for: window.bundleID)
            items[i].minSize = CGSize(width: max(items[i].minSize.width, observed.width),
                                      height: max(items[i].minSize.height, observed.height))
            learnedSomething = true
        }

        // Pass 2 (at most once): re-lay out with what we just learned, so the stubborn
        // windows get bigger cells and nothing overlaps. Next time the cache makes pass 1
        // right, so this costs extra round-trips only the first time an app clamps.
        if learnedSomething {
            let retargets = LayoutEngine.frames(for: items, in: usable, style: style, gap: Self.gap)
            if retargets.count == targets.count {
                for (i, window) in windows.enumerated() where actual[i] != nil && retargets[i] != targets[i] {
                    actual[i] = AX.setFrame(window.element, retargets[i])
                }
                targets = retargets
            }
        }

        // Center windows that came out smaller than their cell: Terminal snapping to its
        // character grid, or a fixed-size window the engine already centered but the app
        // nudged. One position write each, no resize.
        for (i, window) in windows.enumerated() where i < targets.count {
            guard let got = actual[i],
                  got.width < targets[i].width - 1 || got.height < targets[i].height - 1 else { continue }
            let origin = CGPoint(x: (targets[i].midX - got.width / 2).rounded(),
                                 y: (targets[i].midY - got.height / 2).rounded())
            if abs(origin.x - got.minX) > 1 || abs(origin.y - got.minY) > 1 {
                AX.setPosition(window.element, origin)
            }
        }

        // Re-tiling (a style change while tiled) keeps the frames already in the snapshot:
        // those are the originals. Only windows tiled for the first time add their current
        // frame.
        var saved = snapshot ?? []
        for (i, window) in windows.enumerated() where actual[i] != nil {
            if !saved.contains(where: { CFEqual($0.element, window.element) }) {
                saved.append((window.element, window.frame))
            }
        }

        // If nothing moved, stay untiled. Otherwise the next press would "restore" nothing
        // and the user would have to press twice to tile.
        if saved.isEmpty {
            NSSound.beep()
        } else {
            snapshot = saved
        }
    }

    /// If the window came back more than 2px larger than asked in either dimension, the
    /// minimum it enforced (0 for the dimension that fit). Smaller is step snapping and
    /// teaches nothing.
    private static func clampedMinimum(_ got: CGRect, asked: CGRect) -> CGSize? {
        let w = got.width > asked.width + 2 ? got.width : 0
        let h = got.height > asked.height + 2 ? got.height : 0
        return (w > 0 || h > 0) ? CGSize(width: w, height: h) : nil
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
