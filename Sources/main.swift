import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tiler = Tiler()
    private let tuck = TuckController()
    private var tileHotkey: Hotkey?
    private var statusItem: NSStatusItem!

    // Shortcuts are shown in the titles rather than as key equivalents, so a key press
    // while the menu is open can't fire both the menu item and the global hotkey.
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleTiling), keyEquivalent: "")
    private let forgetItem = NSMenuItem(title: "Forget Saved Layout", action: #selector(forgetLayout), keyEquivalent: "")
    private let layoutMenu = NSMenu()
    private let skipTuckItem = NSMenuItem(title: "Don't Tile Tuck Apps", action: #selector(toggleSkipTuck), keyEquivalent: "")
    private let tuckAllItem = NSMenuItem(title: "", action: #selector(toggleTuckAll), keyEquivalent: "")
    private let tuckAppsItem = NSMenuItem(title: "Tuck Apps", action: nil, keyEquivalent: "")
    private let hotkeyWarningItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "", action: #selector(openPermissions), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Blossom")

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        for item in [toggleItem, forgetItem, tuckAllItem, permissionItem] { item.target = self }
        tuckAppsItem.submenu = NSMenu()
        hotkeyWarningItem.isEnabled = false

        menu.addItem(toggleItem)
        menu.addItem(forgetItem)
        let layoutItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
        layoutItem.submenu = layoutMenu
        menu.addItem(layoutItem)
        skipTuckItem.target = self
        menu.addItem(skipTuckItem)
        let resetSizes = NSMenuItem(title: "Reset Learned Window Sizes", action: #selector(resetLearnedSizes), keyEquivalent: "")
        resetSizes.target = self
        menu.addItem(resetSizes)
        menu.addItem(.separator())
        menu.addItem(tuckAllItem)
        menu.addItem(tuckAppsItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(hotkeyWarningItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Blossom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        tileHotkey = Hotkey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.tiler.toggle()
        }
        tuck.start()

        _ = Permissions.isTrusted(prompt: true)
        refreshMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        toggleItem.title = tiler.hasSnapshot ? "Restore Layout  ⌃⌥⌘T" : "Tile Windows  ⌃⌥⌘T"
        forgetItem.isEnabled = tiler.hasSnapshot
        rebuildLayoutMenu()
        skipTuckItem.state = tiler.skipTuckApps ? .on : .off

        tuckAllItem.title = tuck.anyVisible || !tuck.hasTrackedApps ? "Tuck All Away  ⌘⇧H" : "Show All Tucked  ⌘⇧H"
        tuckAllItem.isEnabled = tuck.hasTrackedApps
        rebuildTuckAppsMenu()

        let taken = [tileHotkey == nil ? "⌃⌥⌘T" : nil, tuck.hotkeyAvailable ? nil : "⌘⇧H"].compactMap { $0 }
        hotkeyWarningItem.isHidden = taken.isEmpty
        hotkeyWarningItem.title = "\(taken.joined(separator: " and ")) taken by another app"

        let trusted = Permissions.isTrusted()
        permissionItem.title = trusted ? "Accessibility: Granted" : "Grant Accessibility Access…"
        permissionItem.isEnabled = !trusted
    }

    /// Running apps with a checkmark when Tuck tracks them. Apps assigned to All Desktops
    /// in the Dock are tracked automatically; the rest can be added by hand. The manual
    /// list is also the fallback if reading the Dock setting ever breaks.
    private func rebuildTuckAppsMenu() {
        guard let submenu = tuckAppsItem.submenu else { return }
        submenu.removeAllItems()
        submenu.autoenablesItems = false

        let dock = SpacesPrefs.dockAllDesktopsBundleIDs()
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }

        for app in apps {
            let bundleID = app.bundleIdentifier!
            let name = app.localizedName ?? bundleID
            let viaDock = dock.contains(bundleID.lowercased())
            let item = NSMenuItem(title: viaDock ? "\(name) (Dock)" : name,
                                  action: #selector(toggleManualTuck(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = viaDock || SpacesPrefs.isManual(bundleID) ? .on : .off
            item.isEnabled = !viaDock  // Dock-assigned apps are managed from the Dock
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let hint = NSMenuItem(title: "Or in the Dock: Options → Assign To → All Desktops", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        submenu.addItem(hint)
    }

    private func rebuildLayoutMenu() {
        layoutMenu.removeAllItems()
        for style in LayoutStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(chooseLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == tiler.style ? .on : .off
            layoutMenu.addItem(item)
        }
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = LayoutStyle(rawValue: raw) else { return }
        tiler.setStyle(style)
    }

    @objc private func toggleSkipTuck() { tiler.skipTuckApps.toggle() }
    @objc private func toggleTiling() { tiler.toggle() }
    @objc private func forgetLayout() { tiler.forgetSnapshot() }
    @objc private func resetLearnedSizes() { MinSizeCache.reset() }
    @objc private func toggleTuckAll() { tuck.toggleAll() }

    @objc private func toggleManualTuck(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        SpacesPrefs.toggleManual(bundleID)
        tuck.sync()
    }

    @objc private func openPermissions() {
        _ = Permissions.isTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: no Dock icon, and we never steal focus from the windows we're working on.
app.setActivationPolicy(.accessory)
app.run()
