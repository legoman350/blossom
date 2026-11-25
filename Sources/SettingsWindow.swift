import AppKit

/// A button that records a shortcut when clicked. It only watches key presses inside
/// Blossom's own window, so it needs no Input Monitoring permission. (The global hotkeys
/// themselves still go through Carbon RegisterEventHotKey.)
final class ShortcutField: NSButton {
    var shortcut: Shortcut? { didSet { updateTitle() } }
    var onRecordingChanged: ((Bool) -> Void)?
    var onRecorded: ((Shortcut) -> Void)?
    var onRejected: ((String) -> Void)?

    private var recording = false { didSet { updateTitle(); onRecordingChanged?(recording) } }

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(startRecording)
        widthAnchor.constraint(equalToConstant: 170).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { recording }

    @objc private func startRecording() {
        recording = true
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
    }

    private func updateTitle() {
        title = recording ? "Type shortcut…" : (shortcut?.display ?? "None")
    }

    // ⌘ combinations arrive as key equivalents, not keyDown, so both paths handle them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53, Shortcut.carbonModifiers(event.modifierFlags) == 0 {  // plain Escape cancels
            stopRecording()
            return
        }
        guard let recorded = Shortcut.from(event: event) else {
            onRejected?("Use ⌘, ⌃ or ⌥ with the key (or an F-key on its own).")
            return
        }
        stopRecording()
        onRecorded?(recorded)
    }

    override func resignFirstResponder() -> Bool {
        if recording { recording = false }  // clicking elsewhere cancels
        return super.resignFirstResponder()
    }
}

/// Settings window with four tabs: Hotkeys, Tiling, Floating Apps, General.
final class SettingsWindowController: NSWindowController {
    private let hotkeys: HotkeyManager
    private let tiler: Tiler
    private let onChange: () -> Void

    private let tabView = NSTabView()
    private var fields: [HotkeyAction: ShortcutField] = [:]
    private let hotkeyStatus = SettingsWindowController.helpLabel("")
    private let snapStatus = SettingsWindowController.helpLabel("")
    private let autoTileOthersBox = NSButton(checkboxWithTitle: "After snapping a window, tile the other windows into the space left",
                                             target: nil, action: nil)
    private let stylePopup = NSPopUpButton()
    private let floatPopup = NSPopUpButton()
    private let modifierPopup = NSPopUpButton()
    private let gapSlider = NSSlider()
    private let gapValue = NSTextField(labelWithString: "")
    private let tilingStatus = SettingsWindowController.helpLabel("")
    private let floatingAppsTab = NSTabViewItem(identifier: "floating")
    private let accessibilityLabel = NSTextField(labelWithString: "")
    private let loginBox = NSButton(checkboxWithTitle: "Open Blossom at login", target: nil, action: nil)
    private let loginNote = SettingsWindowController.helpLabel("")
    private let loginApproveButton = NSButton(title: "Open Login Items Settings…", target: nil, action: nil)
    private let accessibilityButton = NSButton(title: "Open Accessibility Settings…", target: nil, action: nil)

    init(hotkeys: HotkeyManager, tiler: Tiler, onChange: @escaping () -> Void) {
        self.hotkeys = hotkeys
        self.tiler = tiler
        self.onChange = onChange
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Blossom Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        tabView.addTabViewItem(tab("Hotkeys", buildHotkeysPage()))
        tabView.addTabViewItem(tab("Snapping", buildSnappingPage()))
        tabView.addTabViewItem(tab("Tiling", buildTilingPage()))
        floatingAppsTab.label = "Floating Apps"
        tabView.addTabViewItem(floatingAppsTab)
        tabView.addTabViewItem(tab("General", buildGeneralPage()))

        let container = NSView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            tabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            tabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            container.widthAnchor.constraint(equalToConstant: 640),
            container.heightAnchor.constraint(equalToConstant: 480),
        ])
        window.contentView = container
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        refresh()
        // An accessory app has no Dock icon; it must activate itself for its window to take
        // keyboard focus, which the recorder needs.
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        if window?.isVisible == false { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    private func refresh() {
        for (action, field) in fields { field.shortcut = hotkeys.shortcut(for: action) }
        for (actions, status) in [(HotkeyAction.general, hotkeyStatus), (HotkeyAction.snapping, snapStatus)] {
            let taken = actions.filter { hotkeys.unavailable.contains($0) }.map(\.title)
            setStatus(status, taken.isEmpty ? "" : "Taken by another app: \(taken.joined(separator: ", ")). Pick another shortcut.", isError: true)
        }

        modifierPopup.selectItem(at: HotkeyManager.modifierChoices.firstIndex(of: HotkeyManager.baseModifiers) ?? 0)
        autoTileOthersBox.state = tiler.autoTileOthers ? .on : .off
        gapSlider.doubleValue = Double(Tiler.gap)
        gapValue.stringValue = "\(Int(Tiler.gap)) pt"
        stylePopup.selectItem(at: LayoutStyle.allCases.firstIndex(of: tiler.style) ?? 0)
        floatPopup.selectItem(at: FloatMode.allCases.firstIndex(of: tiler.floatMode) ?? 0)
        floatingAppsTab.view = buildFloatingAppsPage()  // the app list changes; rebuild each time

        let trusted = Permissions.isTrusted()
        accessibilityLabel.stringValue = trusted ? "✓ Granted" : "Not granted. Tiling won't work without it."
        accessibilityLabel.textColor = trusted ? .systemGreen : .systemRed
        accessibilityButton.isHidden = trusted
        refreshLoginItem()
    }

    /// Reads the login item state fresh every time: the user can change it in System
    /// Settings while this window is closed.
    private func refreshLoginItem(error: String? = nil) {
        let state = LoginItem.state
        loginBox.state = (state == .on || state == .needsApproval) ? .on : .off
        loginBox.isEnabled = state != .unavailable
        loginApproveButton.isHidden = state != .needsApproval
        let note: String
        switch state {
        case .on:            note = "Blossom starts when you log in. Also listed in System Settings → General → Login Items."
        case .off:           note = "Blossom starts only when you open it."
        case .needsApproval: note = "macOS is waiting for you to allow Blossom in Login Items."
        case .unavailable:   note = "Available once Blossom is installed in /Applications (./build.sh install)."
        }
        loginNote.stringValue = error ?? note
        loginNote.textColor = error != nil || state == .needsApproval ? .systemOrange : .secondaryLabelColor
    }

    @objc private func loginToggled() {
        refreshLoginItem(error: LoginItem.set(loginBox.state == .on))
    }

    @objc private func openLoginItems() {
        LoginItem.openSystemSettings()
    }

    // MARK: Pages

    private func buildHotkeysPage() -> NSView {
        for mods in HotkeyManager.modifierChoices {
            modifierPopup.addItem(withTitle: Shortcut(keyCode: 0, modifiers: mods, key: "").display)
        }
        modifierPopup.target = self
        modifierPopup.action = #selector(modifiersChanged)
        var rows: [[NSView]] = [
            [label("Modifier keys:"), modifierPopup, NSGridCell.emptyContentView],
            [NSGridCell.emptyContentView, Self.helpLabel("Used with every default shortcut, here and on the Snapping tab. Shortcuts you've recorded yourself don't change."), NSGridCell.emptyContentView],
        ]
        rows += hotkeyRows(HotkeyAction.general, status: hotkeyStatus)
        let defaults = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        defaults.bezelStyle = .rounded
        rows.append([NSGridCell.emptyContentView, defaults, NSGridCell.emptyContentView])

        return page(intro: "Click a shortcut, then press the new keys. A hotkey needs ⌘, ⌃ or ⌥ (F-keys work alone).",
                    grid: grid(rows), footer: hotkeyStatus)
    }

    private func buildSnappingPage() -> NSView {
        let table = grid(hotkeyRows(HotkeyAction.snapping, status: snapStatus))
        table.column(at: 0).xPlacement = .center   // icons
        table.column(at: 1).xPlacement = .leading  // names
        table.rowAlignment = .none                 // image views have no baseline; center rows instead
        for index in 0..<table.numberOfRows { table.row(at: index).yPlacement = .center }
        table.rowSpacing = 8
        autoTileOthersBox.target = self
        autoTileOthersBox.action = #selector(autoTileOthersToggled)
        let footer = NSStackView(views: [autoTileOthersBox, snapStatus])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 6
        return page(intro: "Move the window you're working in to part of its screen. Restore Defaults on the Hotkeys tab resets these too.",
                    grid: scrolled(table, height: 270), footer: footer)
    }

    @objc private func autoTileOthersToggled() {
        tiler.autoTileOthers = autoTileOthersBox.state == .on
    }

    /// One row per action: name, recorder, Clear. Messages go to `status`.
    private func hotkeyRows(_ actions: [HotkeyAction], status: NSTextField) -> [[NSView]] {
        var rows: [[NSView]] = []
        for action in actions {
            let field = ShortcutField()
            field.onRecordingChanged = { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.hotkeys.pauseAll()
                    self.setStatus(status, "Press the new shortcut. Esc cancels.", isError: false)
                } else {
                    self.hotkeys.registerAll()
                }
            }
            field.onRecorded = { [weak self] shortcut in self?.apply(shortcut, to: action, status: status) }
            field.onRejected = { [weak self] message in self?.setStatus(status, message, isError: true) }
            fields[action] = field

            let clear = NSButton(title: "Clear", target: self, action: #selector(clearShortcut(_:)))
            clear.bezelStyle = .rounded
            clear.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
            if let position = action.snapPositions?.first {
                // Snap rows lead with a picture of the position: [icon, name, shortcut, Clear].
                let icon = NSImageView(image: position.icon(size: NSSize(width: 26, height: 18)))
                icon.contentTintColor = .labelColor
                rows.append([icon, label(action.title), field, clear])
            } else {
                rows.append([label(action.title + ":"), field, clear])
            }
        }
        return rows
    }

    private func buildTilingPage() -> NSView {
        stylePopup.addItems(withTitles: LayoutStyle.allCases.map(\.title))
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)
        floatPopup.addItems(withTitles: FloatMode.allCases.map(\.title))
        floatPopup.target = self
        floatPopup.action = #selector(floatModeChanged)
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetLearnedSizes))
        reset.bezelStyle = .rounded

        gapSlider.minValue = Double(Tiler.gapRange.lowerBound)
        gapSlider.maxValue = Double(Tiler.gapRange.upperBound)
        gapSlider.numberOfTickMarks = Int(Tiler.gapRange.upperBound - Tiler.gapRange.lowerBound) + 1  // one per point
        gapSlider.allowsTickMarkValuesOnly = true
        gapSlider.isContinuous = true            // the label follows the drag…
        gapSlider.target = self
        gapSlider.action = #selector(gapChanged)
        gapSlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        gapValue.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let gapRow = NSStackView(views: [gapSlider, gapValue])
        gapRow.spacing = 10

        let rows: [[NSView]] = [
            [label("Layout:"), stylePopup],
            [NSGridCell.emptyContentView, Self.helpLabel("Grid fits windows to a near-square grid. Master + Stack gives the frontmost window 60%. Columns puts everything in one row.")],
            [label("Floating windows:"), floatPopup],
            [NSGridCell.emptyContentView, Self.helpLabel("Floating apps are never tiled. “Tile Around Them” keeps other windows out of their way.")],
            [label("Gap between windows:"), gapRow],
            [NSGridCell.emptyContentView, Self.helpLabel("Also used for snapping. Changing it while tiled re-tiles straight away.")],
            [label("Learned window sizes:"), reset],
            [NSGridCell.emptyContentView, Self.helpLabel("Blossom remembers each app's minimum window size. Reset if an app's cells look too large.")],
        ]
        return page(intro: nil, grid: grid(rows), footer: tilingStatus)
    }

    /// Every floating app, running or not, with its own auto-tuck setting. These used to
    /// live only in each app's menu bar icon menu, which only exists while the app runs.
    private func buildFloatingAppsPage() -> NSView {
        let apps = Self.floatingApps()
        let intro = "Apps assigned to All Desktops in the Dock, or ticked under Floating Apps in Blossom's menu."
        guard !apps.isEmpty else {
            return page(intro: intro, grid: grid([[Self.helpLabel("No floating apps yet.")]]), footer: nil)
        }

        var rows: [[NSView]] = [[NSGridCell.emptyContentView, boldLabel("Auto-tuck"), boldLabel("If it has no window")]]
        for app in apps {
            let icon = NSImageView(image: app.icon ?? NSImage())
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 20).isActive = true
            let name = NSStackView(views: [icon, NSTextField(labelWithString: app.name)])
            name.spacing = 6

            let popup = NSPopUpButton()
            popup.addItems(withTitles: TuckSettings.AutoTuckMode.allCases.map(\.title))
            popup.selectItem(at: TuckSettings.AutoTuckMode.allCases.firstIndex(of: TuckSettings.autoTuckMode(for: app.id)) ?? 0)
            popup.identifier = NSUserInterfaceItemIdentifier(app.id)
            popup.target = self
            popup.action = #selector(autoTuckChanged(_:))

            let newWindow = NSButton(checkboxWithTitle: "Open a new one", target: self, action: #selector(newWindowToggled(_:)))
            newWindow.state = TuckSettings.isAutoRequestNewWindowEnabled(for: app.id) ? .on : .off
            newWindow.identifier = NSUserInterfaceItemIdentifier(app.id)
            rows.append([name, popup, newWindow])
        }
        let table = grid(rows)
        table.column(at: 0).xPlacement = .leading
        table.rowAlignment = .none
        for index in 0..<table.numberOfRows { table.row(at: index).yPlacement = .center }

        return page(intro: intro + " Each app's menu bar icon menu has the same options.", grid: scrolled(table, height: 270),
                    footer: Self.helpLabel("“When switching Spaces” hides the app when you change desktops, unless it's the app you're using."))
    }

    private func buildGeneralPage() -> NSView {
        accessibilityButton.target = self
        accessibilityButton.action = #selector(openAccessibility)
        accessibilityButton.bezelStyle = .rounded
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        loginBox.target = self
        loginBox.action = #selector(loginToggled)
        loginApproveButton.target = self
        loginApproveButton.action = #selector(openLoginItems)
        loginApproveButton.bezelStyle = .rounded
        let rows: [[NSView]] = [
            [label("Startup:"), loginBox],
            [NSGridCell.emptyContentView, loginNote],
            [NSGridCell.emptyContentView, loginApproveButton],
            [label("Accessibility:"), accessibilityLabel],
            [NSGridCell.emptyContentView, accessibilityButton],
            [NSGridCell.emptyContentView, Self.helpLabel("Blossom needs Accessibility to move and resize windows. Tuck's hide/show works without it.")],
            [label("Version:"), NSTextField(labelWithString: version)],
        ]
        return page(intro: nil, grid: grid(rows), footer: nil)
    }

    // MARK: Building blocks

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    /// Wraps content in a vertical scroll view of fixed height, for lists that can be long.
    private func scrolled(_ content: NSView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        content.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor),
            document.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: 4),
        ])
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 560).isActive = true
        return scroll
    }

    private func tab(_ title: String, _ view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    /// Optional intro line, the main content, an optional footer, all top-aligned with
    /// generous insets.
    private func page(intro: String?, grid content: NSView, footer: NSView?) -> NSView {
        var views: [NSView] = []
        if let intro { views.append(Self.helpLabel(intro)) }
        views.append(content)
        if let footer { views.append(footer) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.setHuggingPriority(.defaultHigh, for: .vertical)

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        return container
    }

    private func grid(_ rows: [[NSView]]) -> NSGridView {
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        return grid
    }

    private func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    private func boldLabel(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        return field
    }

    private static func helpLabel(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 380
        return field
    }

    private func setStatus(_ field: NSTextField, _ text: String, isError: Bool) {
        field.stringValue = text
        field.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    /// Floating apps for the list: running ones use the running app's bundle ID (the key
    /// Tuck's settings use), others resolve through Launch Services. Dock entries for apps
    /// no longer installed are skipped.
    private static func floatingApps() -> [(id: String, name: String, icon: NSImage?)] {
        var canonical: [String: String] = [:]  // lowercased → best-cased bundle ID
        for id in SpacesPrefs.dockAllDesktopsBundleIDs() { canonical[id] = id }
        for id in SpacesPrefs.manualBundleIDs() { canonical[id.lowercased()] = id }
        var running: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, canonical[id.lowercased()] != nil else { continue }
            canonical[id.lowercased()] = id
            running[id] = app
        }
        return canonical.values.compactMap { id -> (id: String, name: String, icon: NSImage?)? in
            if let app = running[id] { return (id, app.localizedName ?? id, app.icon) }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return (id, FileManager.default.displayName(atPath: url.path), NSWorkspace.shared.icon(forFile: url.path))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Actions

    private func apply(_ shortcut: Shortcut?, to action: HotkeyAction, status: NSTextField) {
        switch hotkeys.set(shortcut, for: action) {
        case .ok:
            setStatus(status, "", isError: false)
        case .takenByOtherApp:
            setStatus(status, "\(shortcut?.display ?? "That shortcut") is taken by another app. Kept the previous one.", isError: true)
        case .usedBy(let other):
            setStatus(status, "\(shortcut?.display ?? "") is already used for \(other.title).", isError: true)
        }
        fields[action]?.shortcut = hotkeys.shortcut(for: action)
        onChange()
    }

    @objc private func clearShortcut(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let action = HotkeyAction(rawValue: raw) else { return }
        apply(nil, to: action, status: action.snapPositions == nil ? hotkeyStatus : snapStatus)
    }

    @objc private func modifiersChanged() {
        let choices = HotkeyManager.modifierChoices
        guard choices.indices.contains(modifierPopup.indexOfSelectedItem) else { return }
        hotkeys.setBaseModifiers(choices[modifierPopup.indexOfSelectedItem])
        refresh()   // shows the new shortcuts, and any now taken by other apps
        onChange()  // menu titles
    }

    @objc private func restoreDefaults() {
        HotkeyManager.baseModifiers = HotkeyManager.modifierChoices[0]  // ⌃⌥
        hotkeys.resetToDefaults()
        refresh()
        onChange()
    }

    @objc private func styleChanged() {
        let index = stylePopup.indexOfSelectedItem
        guard LayoutStyle.allCases.indices.contains(index) else { return }
        tiler.setStyle(LayoutStyle.allCases[index])
        onChange()
    }

    /// Updates the label on every step of the drag, but re-tiles only when the mouse is
    /// released, so dragging doesn't shuffle windows dozens of times.
    @objc private func gapChanged() {
        let gap = CGFloat(gapSlider.doubleValue.rounded())
        gapValue.stringValue = "\(Int(gap)) pt"
        if NSApp.currentEvent?.type != .leftMouseDragged { tiler.setGap(gap) }  // click, release, or keyboard
    }

    @objc private func floatModeChanged() {
        let index = floatPopup.indexOfSelectedItem
        guard FloatMode.allCases.indices.contains(index) else { return }
        tiler.setFloatMode(FloatMode.allCases[index])
    }

    @objc private func resetLearnedSizes() {
        MinSizeCache.reset()
        setStatus(tilingStatus, "Learned window sizes cleared.", isError: false)
    }

    @objc private func autoTuckChanged(_ sender: NSPopUpButton) {
        let modes = TuckSettings.AutoTuckMode.allCases
        guard let id = sender.identifier?.rawValue, modes.indices.contains(sender.indexOfSelectedItem) else { return }
        TuckSettings.setAutoTuckMode(modes[sender.indexOfSelectedItem], for: id)
    }

    @objc private func newWindowToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if (sender.state == .on) != TuckSettings.isAutoRequestNewWindowEnabled(for: id) {
            TuckSettings.toggleAutoRequestNewWindow(for: id)
        }
    }

    @objc private func openAccessibility() {
        _ = Permissions.isTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }
}
