import AppKit
import ApplicationServices

/// A window we can move, paired with its Accessibility element.
struct TileableWindow {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    /// Accessibility coordinates: top-left origin on the primary display.
    let frame: CGRect
    /// Some windows (dialogs, Calculator, utility panels) can move but not resize. They
    /// still get a cell, at their own size.
    let canResize: Bool
}

enum WindowEnumerator {
    /// Tileable windows on the current desktop, frontmost first.
    static func tileableWindows() -> [TileableWindow] {
        // The on-screen list is effectively "windows on the active desktop". Owner pid,
        // bounds and layer need no permission; titles would need Screen Recording, so we
        // never read them.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }

        let ownPid = getpid()
        var axPool: [pid_t: [(element: AXUIElement, frame: CGRect)]] = [:]
        var result: [TileableWindow] = []

        for entry in info {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPid,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 60, bounds.height >= 60,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular
            else { continue }

            if axPool[pid] == nil { axPool[pid] = AX.windows(ofPid: pid) }
            guard var pool = axPool[pid], let index = bestMatch(for: bounds, in: pool.map(\.frame)) else { continue }
            let match = pool.remove(at: index)
            axPool[pid] = pool  // each AX element pairs with at most one CG window

            if AX.isFullScreen(match.element) { continue }  // full-screen windows can't be resized
            // A window that can't even move is useless to tile. Skip it rather than leave a hole.
            guard AX.isSettable(match.element, kAXPositionAttribute) else { continue }
            result.append(TileableWindow(element: match.element, pid: pid, bundleID: app.bundleIdentifier,
                                         frame: match.frame,
                                         canResize: AX.isSettable(match.element, kAXSizeAttribute)))
        }
        return result
    }

    /// There is no public bridge from CGWindowID to AXUIElement, so we match by frame
    /// within one process. Both sources use top-left coordinates, but the vertical origin
    /// can differ by the title bar height, so the top edge gets a looser tolerance while
    /// left, right and bottom edges must agree closely.
    private static func bestMatch(for cg: CGRect, in candidates: [CGRect]) -> Int? {
        let tight: CGFloat = 4, titleBarSlack: CGFloat = 50
        var best: (index: Int, score: CGFloat)?
        for (i, ax) in candidates.enumerated() {
            let dLeft = abs(ax.minX - cg.minX), dRight = abs(ax.maxX - cg.maxX)
            let dBottom = abs(ax.maxY - cg.maxY), dTop = abs(ax.minY - cg.minY)
            guard dLeft <= tight, dRight <= tight, dBottom <= tight, dTop <= titleBarSlack else { continue }
            let score = dLeft + dRight + dBottom + dTop
            if best == nil || score < best!.score { best = (i, score) }
        }
        return best?.index
    }
}

/// Thin Accessibility helpers shared by the enumerator and the tiler.
enum AX {
    /// Accessibility calls are synchronous round-trips into the target app. Without a
    /// timeout, one unresponsive app freezes the whole tiling operation (default is ~6s).
    static let messagingTimeout: Float = 0.2

    static func windows(ofPid pid: pid_t) -> [(element: AXUIElement, frame: CGRect)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { window in
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            return frame(of: window).map { (window, $0) }
        }
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// The focused window of the frontmost app, if any.
    static func focusedWindow() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, messagingTimeout)
        var app: CFTypeRef?, window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let app, CFGetTypeID(app) == AXUIElementGetTypeID() else { return nil }
        let appElement = app as! AXUIElement
        AXUIElementSetMessagingTimeout(appElement, messagingTimeout)
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        return (window as! AXUIElement)
    }

    static func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) == true
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Moves a window, and resizes it too if it allows that. Returns the frame it actually
    /// ended up with, or nil if it refused to move or no longer exists.
    ///
    /// The returned frame can differ from `target`: minimum sizes clamp silently (larger),
    /// and Terminal-style windows snap to their character grid (slightly smaller). The
    /// tiler learns from the first and centers the second.
    @discardableResult
    static func setFrame(_ element: AXUIElement, _ target: CGRect) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        guard isSettable(element, kAXPositionAttribute) else { return nil }
        let resizable = isSettable(element, kAXSizeAttribute)

        var origin = target.origin, size = target.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else { return nil }

        // Position, then size, then position AGAIN. This is not superstition: when the new
        // size would push the window past the screen edge at its old position, the window
        // server shoves it back on-screen, so the first position write gets undone. The
        // second write lands it where we asked. Do not "clean up" the duplicate.
        guard AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success else { return nil }
        if resizable {
            _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, dimensions)
            _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        }
        return frame(of: element) ?? target
    }

    /// Moves a window without resizing it. Used to center a window inside its cell.
    @discardableResult
    static func setPosition(_ element: AXUIElement, _ point: CGPoint) -> Bool {
        var origin = point
        guard let position = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position) == .success
    }
}
