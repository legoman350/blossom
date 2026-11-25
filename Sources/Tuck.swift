import AppKit
import Carbon.HIToolbox

/// Tuck: a menu bar tray for apps assigned to All Desktops (or added manually).
///
/// Activating an app assigned to None or This Desktop makes macOS switch desktops
/// ("auto-swoosh"). Tuck avoids that by hiding and unhiding the app instead. All-Desktops
/// windows already exist on every desktop, so unhiding shows them where you are. Nothing
/// is moved between desktops; it is visibility only, which is fully supported API.
final class TuckController: NSObject {

    private var entries: [String: TrayEntry] = [:]  // canonical (running app's) bundleID -> entry
    private var refreshTimer: Timer?
    private var lastClickAt: TimeInterval = 0
    private var hotkey: Hotkey?
    private var spaceChangeWorkItem: DispatchWorkItem?

    var hotkeyAvailable: Bool { hotkey != nil }
    var hasTrackedApps: Bool { !entries.isEmpty }

    func start() {
        sync()
        // Polling, because there's no notification when the Dock's "Assign To" changes.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.sync()
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appDeactivated(_:)),
                           name: NSWorkspace.didDeactivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(activeSpaceChanged(_:)),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.toggleAll()
        }
    }

    // MARK: Tuck all / show all (⌘⇧H)

    /// True if any tracked app currently has a window on screen. A minimized window counts
    /// as tucked away, not visible.
    var anyVisible: Bool {
        entries.keys.contains { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains {
                !$0.isTerminated && !$0.isHidden && TuckWindows.hasVisibleWindow(pid: $0.processIdentifier)
            }
        }
    }

    func toggleAll() {
        if anyVisible {
            hideAll()
            return
        }
        for bundleID in Array(entries.keys) {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
                _ = app.unhide()
                if TuckWindows.isMinimized(pid: app.processIdentifier) {
                    TuckWindows.reopen(app)
                } else {
                    TuckWindows.activate(app)
                }
            }
        }
        sync()
    }

    func hideAll() {
        for bundleID in Array(entries.keys) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { _ = $0.hide() }
        }
        syncSoon(after: 0.25)
    }

    // MARK: Keeping the icons in sync

    func sync() {
        let tracked = SpacesPrefs.trackedBundleIDs()
        // Only running apps get an icon. Key by the running app's canonical ID.
        var wanted = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular, !app.isTerminated,
                  app.processIdentifier != getpid(),
                  let bundleID = app.bundleIdentifier,
                  tracked.contains(bundleID.lowercased()) else { continue }
            wanted.insert(bundleID)
        }

        // Snapshot the keys: we mutate `entries` inside the loop.
        for bundleID in Array(entries.keys) where !wanted.contains(bundleID) {
            entries[bundleID]?.remove()
            entries.removeValue(forKey: bundleID)
        }
        for bundleID in wanted where entries[bundleID] == nil {
            entries[bundleID] = TrayEntry(bundleID: bundleID, controller: self)
        }
        for entry in entries.values {
            entry.refreshAppearance()
        }
    }

    private func syncSoon(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sync() }
    }

    // MARK: Show / hide one app

    func toggle(bundleID: String) {
        lastClickAt = Date().timeIntervalSince1970
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { !$0.isTerminated }) else { return }

        if app.isHidden {
            show(app)
        } else if TuckWindows.isMinimized(pid: app.processIdentifier) {
            restore(app)
        } else {
            _ = app.hide()  // has a visible window (including a media pop-out): tuck it away
        }
        syncSoon(after: 0.25)
    }

    private func show(_ app: NSRunningApplication) {
        _ = app.unhide()
        TuckWindows.activate(app)

        let pid = app.processIdentifier
        let bundleID = app.bundleIdentifier
        // The delays give the app time to process the unhide before we inspect its windows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            // Unhiding can leave a formerly minimized window in the Dock.
            if TuckWindows.isMinimized(pid: pid) {
                TuckWindows.reopen(app)
                return
            }
            // Genuinely no windows: ask for one, only if enabled for this app.
            guard let bundleID,
                  TuckSettings.isAutoRequestNewWindowEnabled(for: bundleID),
                  !TuckWindows.hasAnyWindow(pid: pid) else { return }
            TuckWindows.requestNewWindow(pid: pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                if let a = NSRunningApplication(processIdentifier: pid) { TuckWindows.activate(a) }
            }
        }
    }

    /// Bring a minimized app back with a LaunchServices reopen, then re-check (reopen is
    /// app-defined) and fall back to plain activation.
    private func restore(_ app: NSRunningApplication) {
        TuckWindows.reopen(app)
        let pid = app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            if let a = NSRunningApplication(processIdentifier: pid), TuckWindows.isMinimized(pid: pid) {
                TuckWindows.activate(a)
            }
            self?.sync()
        }
    }

    // MARK: Auto-tuck

    @objc private func appDeactivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              entries[bundleID] != nil,
              TuckSettings.autoTuckMode(for: bundleID) == .loseFocus else { return }

        // Clicking our own menu bar icon deactivates the front app; that isn't "the user
        // moved on".
        if Date().timeIntervalSince1970 - lastClickAt < 1.0 { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { [weak self] in
            guard let self else { return }
            if Date().timeIntervalSince1970 - self.lastClickAt < 1.0 { return }
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier == getpid() || front?.bundleIdentifier == bundleID { return }
            _ = app.hide()
            self.sync()
        }
    }

    @objc private func activeSpaceChanged(_ note: Notification) {
        // Space changes arrive in bursts (animation, full-screen transitions); debounce so
        // we tuck once per switch.
        spaceChangeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tuckForSpaceChange() }
        spaceChangeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40, execute: work)
    }

    /// Hide every tracked app in `.switchSpace` mode except the frontmost one.
    private func tuckForSpaceChange() {
        // Restoring an app can itself trigger a desktop change; ignore our own.
        if Date().timeIntervalSince1970 - lastClickAt < 1.0 { return }

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == getpid() { return }
        let frontPid = front?.processIdentifier

        var changed = false
        for bundleID in entries.keys where TuckSettings.autoTuckMode(for: bundleID) == .switchSpace {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where !app.isTerminated && !app.isHidden && app.processIdentifier != frontPid {
                _ = app.hide()
                changed = true
            }
        }
        if changed { sync() }
    }

    // MARK: Per-app menu

    func buildMenu(for entry: TrayEntry) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false  // so our explicit isEnabled states stick
        let bundleID = entry.bundleID

        if let app = entry.app {
            let header = NSMenuItem(title: app.localizedName ?? bundleID, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(item(app.isHidden ? "Show" : "Tuck Away", #selector(menuToggle(_:)), bundleID))
            menu.addItem(.separator())
        }

        let hideAllItem = item("Tuck All Away  ⌘⇧H", #selector(menuHideAll(_:)), nil)
        hideAllItem.isEnabled = !entries.isEmpty
        menu.addItem(hideAllItem)

        let current = TuckSettings.autoTuckMode(for: bundleID)
        let autoParent = NSMenuItem(title: "Auto-tuck", action: nil, keyEquivalent: "")
        let autoMenu = NSMenu()
        for mode in TuckSettings.AutoTuckMode.allCases {
            let modeItem = item(mode.title, #selector(menuSetAutoTuckMode(_:)), [bundleID, mode.rawValue])
            modeItem.state = mode == current ? .on : .off
            autoMenu.addItem(modeItem)
        }
        autoParent.submenu = autoMenu
        menu.addItem(autoParent)

        let newWindowItem = item("Open a new window when app has none", #selector(menuToggleAutoRequestWindow(_:)), bundleID)
        newWindowItem.state = TuckSettings.isAutoRequestNewWindowEnabled(for: bundleID) ? .on : .off
        menu.addItem(newWindowItem)

        menu.addItem(item("Refresh", #selector(menuRefresh(_:)), nil))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ represented: Any?) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = represented
        return menuItem
    }

    @objc private func menuToggle(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        toggle(bundleID: bundleID)
    }

    @objc private func menuHideAll(_ sender: NSMenuItem) { hideAll() }

    @objc private func menuRefresh(_ sender: NSMenuItem) { sync() }

    @objc private func menuSetAutoTuckMode(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let mode = TuckSettings.AutoTuckMode(rawValue: pair[1]) else { return }
        TuckSettings.setAutoTuckMode(mode, for: pair[0])
    }

    @objc private func menuToggleAutoRequestWindow(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        TuckSettings.toggleAutoRequestNewWindow(for: bundleID)
    }
}
