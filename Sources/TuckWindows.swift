import AppKit
import ApplicationServices

/// Window-state helpers for Tuck. The CGWindowList reads need no permission: they use only
/// owner pid, layer, bounds and on-screen state, never titles (which need Screen Recording).
enum TuckWindows {

    /// Does this process own at least one on-screen window right now?
    /// Counts any layer >= 0, not only layer 0: media pop-outs and other panels can sit
    /// above layer 0.
    static func hasVisibleWindow(pid: pid_t) -> Bool {
        windowInfo(.optionOnScreenOnly).contains { info in
            guard owner(info) == pid, let layer = layer(info), layer >= 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return rect.width >= 60 && rect.height >= 60
        }
    }

    /// Does this process own any window at all, on screen or not (minimized counts)?
    static func hasAnyWindow(pid: pid_t) -> Bool {
        windowInfo(.optionAll).contains { owner($0) == pid && (layer($0) ?? -1) >= 0 }
    }

    /// True when the app owns a normal window but nothing of its is on screen, meaning its
    /// windows are minimized. Tuck only tracks All-Desktops apps, whose live windows are on
    /// every desktop, so "none on screen" reduces to "minimized" rather than "on another
    /// desktop". Any on-screen window (including a pop-out) makes the app "not minimized".
    static func isMinimized(pid: pid_t) -> Bool {
        var anyNormalWindow = false
        for info in windowInfo(.optionAll) where owner(info) == pid {
            guard let layer = layer(info), layer >= 0 else { continue }
            if layer == 0 { anyNormalWindow = true }
            if (info[kCGWindowIsOnscreen as String] as? Bool) == true { return false }
        }
        return anyNormalWindow
    }

    /// Ask LaunchServices to reopen the app. For most AppKit apps this restores a minimized
    /// window with no permission prompt. The behavior is app-defined, so callers re-check
    /// and fall back to `activate`.
    static func reopen(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { activate(app); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
    }

    /// Best-effort "open a window please": File → New Window, else ⌘N.
    /// Needs Accessibility; silently does nothing without it.
    static func requestNewWindow(pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        if pressNewWindowMenuItem(pid: pid) { return }
        postCommandN(pid: pid)
    }

    static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [])
        }
    }

    // MARK: Private

    private static func windowInfo(_ scope: CGWindowListOption) -> [[String: Any]] {
        CGWindowListCopyWindowInfo([scope, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    private static func owner(_ info: [String: Any]) -> pid_t? { info[kCGWindowOwnerPID as String] as? pid_t }
    private static func layer(_ info: [String: Any]) -> Int? { info[kCGWindowLayer as String] as? Int }

    private static func pressNewWindowMenuItem(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        // Walking a menu bar is many synchronous round-trips; a hung app must not freeze us.
        AXUIElementSetMessagingTimeout(axApp, AX.messagingTimeout)
        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let raw = menuBarRef, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }

        for menu in children(of: raw as! AXUIElement) where title(of: menu) == "File" {
            for submenu in children(of: menu) {
                for item in children(of: submenu) {
                    guard let t = title(of: item), t == "New Window" || t == "New Main Window" else { continue }
                    if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success { return true }
                }
            }
        }
        return false
    }

    private static func postCommandN(pid: pid_t) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let keyN: CGKeyCode = 45  // kVK_ANSI_N
        for isDown in [true, false] {
            if let event = CGEvent(keyboardEventSource: src, virtualKey: keyN, keyDown: isDown) {
                event.flags = .maskCommand
                event.postToPid(pid)
            }
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &ref) == .success else { return [] }
        return ref as? [AXUIElement] ?? []
    }

    private static func title(of element: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
