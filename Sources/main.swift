import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tiler = Tiler()
    private let tuck = TuckController()
    private let hotkeys = HotkeyManager()
    private var settings: SettingsWindowController?
    private var statusItem: NSStatusItem!

    // Shortcuts are drawn into the titles, not set as key equivalents: a global hotkey
    // pressed while the menu is open would otherwise fire twice.
    private let toggleItem = NSMenuItem(title: "", action: #selector(toggleTiling), keyEquivalent: "")
    private let tileOthersItem = NSMenuItem(title: "", action: #selector(tileOthers), keyEquivalent: "")
    private let forgetItem = NSMenuItem(title: "", action: #selector(forgetLayout), keyEquivalent: "")
    private let layoutItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
    private let snapItem = NSMenuItem(title: "Snap Window", action: nil, keyEquivalent: "")
    private let tuckAllItem = NSMenuItem(title: "", action: #selector(toggleTuckAll), keyEquivalent: "")
    private let floatingAppsItem = NSMenuItem(title: "Floating Apps", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "⚠︎ Grant Accessibility Access…", action: #selector(openPermissions), keyEquivalent: "")
    private let hotkeyWarningItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.make()  // the app icon's blossom, as a template

        // Menu, top to bottom: tiling, Tuck, problems (only when there are any), app.
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        layoutItem.submenu = NSMenu()
        snapItem.submenu = NSMenu()
        floatingAppsItem.submenu = NSMenu()
        for item in [toggleItem, tileOthersItem, forgetItem, tuckAllItem, permissionItem, hotkeyWarningItem] { item.target = self }

        menu.addItem(toggleItem)
        menu.addItem(tileOthersItem)
        menu.addItem(forgetItem)
        menu.addItem(layoutItem)
        menu.addItem(snapItem)
        menu.addItem(.separator())
        menu.addItem(tuckAllItem)
        menu.addItem(floatingAppsItem)
        menu.addItem(.separator())
        menu.addItem(permissionItem)
        menu.addItem(hotkeyWarningItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem(title: "Quit Blossom", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hotkeys.setHandler(for: .tile) { [weak self] in self?.tiler.toggle() }
        hotkeys.setHandler(for: .tileOthers) { [weak self] in self?.tiler.toggleTileOthers() }
        hotkeys.setHandler(for: .tuckAll) { [weak self] in self?.tuck.toggleAll() }
        hotkeys.setHandler(for: .nextLayout) { [weak self] in self?.nextLayout() }
        hotkeys.setHandler(for: .forgetLayout) { [weak self] in self?.tiler.forgetSnapshot() }
        for action in HotkeyAction.snapping {
            guard let positions = action.snapPositions else { continue }
            hotkeys.setHandler(for: action) { [weak self] in
                guard let self else { return }
                self.afterSnap(Snap.focusedWindow(cycling: positions))
            }
        }
        hotkeys.registerAll()
        tuck.start()

        _ = Permissions.isTrusted(prompt: true)
        refreshMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        let tiled = tiler.hasSnapshot
        toggleItem.attributedTitle = titled(tiled ? "Restore Layout" : "Tile Windows", .tile)
        tileOthersItem.attributedTitle = titled("Tile Others", .tileOthers)
        tileOthersItem.isHidden = tiled  // while tiled, "Restore Layout" above covers both keys
        forgetItem.attributedTitle = titled("Forget Saved Layout", .forgetLayout)
        forgetItem.isHidden = !tiled  // only meaningful while tiled
        rebuildLayoutMenu()
        rebuildSnapMenu()

        // Tuck All only when there's something to tuck; the app list always stays so apps
        // can be added by hand.
        tuckAllItem.attributedTitle = titled(tuck.anyVisible ? "Tuck All Away" : "Show All Tucked", .tuckAll)
        tuckAllItem.isHidden = !tuck.hasFloatingApps
        rebuildFloatingAppsMenu()

        // Problems appear only when they exist.
        permissionItem.isHidden = Permissions.isTrusted()
        let taken = HotkeyAction.allCases.filter { hotkeys.unavailable.contains($0) }
        hotkeyWarningItem.isHidden = taken.isEmpty
        hotkeyWarningItem.title = "⚠︎ Hotkey taken by another app: \(taken.map(\.title).joined(separator: ", "))…"
    }

    /// A menu title with the action's current shortcut right-aligned, like a native item.
    ///
    /// `icon` is embedded in the text itself. On recent macOS a menu item's `image` isn't
    /// drawn once it has an attributed title, so setting `item.image` shows nothing.
    private func titled(_ text: String, _ action: HotkeyAction, icon: NSImage? = nil) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 230)]
        let attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style, .font: font]

        let result = NSMutableAttributedString()
        if let icon {
            let attachment = NSTextAttachment()
            attachment.image = icon
            // Center the icon on the text: drop it below the baseline by half the difference.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - icon.size.height) / 2,
                                       width: icon.size.width, height: icon.size.height)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: "  ", attributes: attributes))
        }
        result.append(NSAttributedString(string: text, attributes: attributes))
        if let shortcut = hotkeys.shortcut(for: action) {
            result.append(NSAttributedString(string: "\t", attributes: attributes))
            result.append(NSAttributedString(string: shortcut.display, attributes: [
                .paragraphStyle: style, .font: font, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        return result
    }

    private func rebuildLayoutMenu() {
        guard let submenu = layoutItem.submenu else { return }
        submenu.removeAllItems()
        for style in LayoutStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(chooseLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = style == tiler.style ? .on : .off
            submenu.addItem(item)
        }
        if let shortcut = hotkeys.shortcut(for: .nextLayout) {
            submenu.addItem(.separator())
            let hint = NSMenuItem(title: "Next Layout: \(shortcut.display)", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            submenu.addItem(hint)
        }
    }

    /// Snap positions for the focused window, grouped like the screen: halves, corners,
    /// thirds, then maximize/center. Clicking Blossom's menu doesn't activate Blossom, so
    /// "focused window" is still the one you were working in.
    private func rebuildSnapMenu() {
        guard let submenu = snapItem.submenu else { return }
        submenu.removeAllItems()
        // Every position is listed for clicking. Thirds share one cycling hotkey, so that
        // key shows on each of them.
        let groups: [[SnapPosition]] = [
            [.leftHalf, .rightHalf, .topHalf, .bottomHalf],
            [.topLeft, .topRight, .bottomLeft, .bottomRight],
            [.firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds],
            [.maximize, .center, .centerTwoThirds, .centerHalf],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            for position in group {
                let item = NSMenuItem(title: "", action: #selector(snapFromMenu(_:)), keyEquivalent: "")
                let icon = position.icon(template: false)
                item.attributedTitle = HotkeyAction.covering(position).map { titled(position.title, $0, icon: icon) }
                    ?? NSAttributedString(string: position.title)
                item.target = self
                item.representedObject = position.rawValue
                submenu.addItem(item)
            }
        }
    }

    @objc private func snapFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let position = SnapPosition(rawValue: raw) else { return }
        afterSnap(Snap.focusedWindow(to: position))
    }

    /// With "auto tile others" on, a snap is followed by tiling the other windows into the
    /// space left. Not after Maximize (no space left) or Center (no clean space either side).
    private func afterSnap(_ position: SnapPosition?) {
        guard tiler.autoTileOthers, let position, position != .maximize, position != .center else { return }
        tiler.tileOthers()
    }

    /// Running apps, checked when they float. Apps assigned to All Desktops in the Dock
    /// float automatically; the rest can be added by hand. The manual list is also the
    /// fallback if reading the Dock setting ever breaks.
    private func rebuildFloatingAppsMenu() {
        guard let submenu = floatingAppsItem.submenu else { return }
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
                                  action: #selector(toggleManualFloating(_:)), keyEquivalent: "")
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

    private func nextLayout() {
        let all = LayoutStyle.allCases
        tiler.setStyle(all[((all.firstIndex(of: tiler.style) ?? 0) + 1) % all.count])
    }

    @objc private func chooseLayout(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = LayoutStyle(rawValue: raw) else { return }
        tiler.setStyle(style)
    }

    @objc private func toggleTiling() { tiler.toggle() }
    @objc private func tileOthers() { tiler.toggleTileOthers() }
    @objc private func forgetLayout() { tiler.forgetSnapshot() }
    @objc private func toggleTuckAll() { tuck.toggleAll() }

    @objc private func toggleManualFloating(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        SpacesPrefs.toggleManual(bundleID)
        tuck.sync()
    }

    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(hotkeys: hotkeys, tiler: tiler) { [weak self] in self?.refreshMenu() }
        }
        settings?.show()
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
