import AppKit

/// One menu bar icon for one tracked app. Left click tucks or shows the app; right click
/// (or control-click) opens its menu. Dimmed means tucked away (hidden or minimized).
final class TrayEntry: NSObject {
    let bundleID: String
    let statusItem: NSStatusItem
    private weak var controller: TuckController?

    init(bundleID: String, controller: TuckController) {
        self.bundleID = bundleID
        self.controller = controller
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refreshAppearance()
    }

    var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { !$0.isTerminated }
    }

    func refreshAppearance() {
        guard let button = statusItem.button, let app else { return }
        let name = app.localizedName ?? bundleID
        let minimized = !app.isHidden && TuckWindows.isMinimized(pid: app.processIdentifier)
        button.image = Self.menuBarIcon(for: app)
        button.alphaValue = (app.isHidden || minimized) ? 0.45 : 1.0
        if app.isHidden {
            button.toolTip = "\(name) — click to show"
        } else if minimized {
            button.toolTip = "\(name) — minimized; click to restore"
        } else {
            button.toolTip = "\(name) — click to tuck away"
        }
    }

    private static func menuBarIcon(for app: NSRunningApplication) -> NSImage? {
        guard let icon = app.icon else { return nil }
        // NSImage.lockFocus is deprecated; draw through a handler instead.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func clicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || (event?.modifierFlags.contains(.control) ?? false)
        if isRightClick {
            showMenu()
        } else {
            controller?.toggle(bundleID: bundleID)
        }
    }

    private func showMenu() {
        guard let button = statusItem.button, let controller else { return }
        let menu = controller.buildMenu(for: self)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }
}
