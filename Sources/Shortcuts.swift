import AppKit
import Carbon.HIToolbox

/// A key combination for a global hotkey, in Carbon terms (what RegisterEventHotKey takes).
struct Shortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon flags: cmdKey, shiftKey, optionKey, controlKey
    var key: String        // display name of the key: "T", "F5", "←"

    /// Modifiers in the standard macOS order: ⌃⌥⇧⌘.
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// Builds a shortcut from a key press in the recorder. Returns nil for combinations
    /// that would hijack ordinary typing: a hotkey needs ⌘, ⌃ or ⌥, unless it's an F-key.
    static func from(event: NSEvent) -> Shortcut? {
        let mods = carbonModifiers(event.modifierFlags)
        let isFunctionKey = functionKeys[event.keyCode] != nil
        guard mods & UInt32(cmdKey | controlKey | optionKey) != 0 || isFunctionKey else { return nil }
        return Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods,
                        key: keyName(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    ]
    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    /// The display name is captured when recording, from the active keyboard layout, so
    /// non-US layouts show the right letter. It's stored with the key code.
    private static func keyName(keyCode: UInt16, characters: String?) -> String {
        if let name = functionKeys[keyCode] ?? specialKeys[keyCode] { return name }
        let chars = (characters ?? "").uppercased()
        return chars.isEmpty ? "#\(keyCode)" : chars
    }

    // MARK: Persistence

    var plist: [String: Any] { ["keyCode": Int(keyCode), "modifiers": Int(modifiers), "key": key] }

    init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    init?(plist: [String: Any]) {
        guard let code = plist["keyCode"] as? Int, let mods = plist["modifiers"] as? Int,
              let key = plist["key"] as? String else { return nil }
        self.init(keyCode: UInt32(code), modifiers: UInt32(mods), key: key)
    }
}

/// Everything a hotkey can trigger.
enum HotkeyAction: String, CaseIterable {
    case tile, tileOthers, tuckAll, nextLayout, forgetLayout
    case fillSpace  // grow the focused window into the largest empty space
    // Snap the focused window. Raw values are the persisted keys; don't rename them.
    case snapLeftHalf = "snap.leftHalf", snapRightHalf = "snap.rightHalf"
    case snapTopHalf = "snap.topHalf", snapBottomHalf = "snap.bottomHalf"
    case snapTopLeft = "snap.topLeft", snapTopRight = "snap.topRight"
    case snapBottomLeft = "snap.bottomLeft", snapBottomRight = "snap.bottomRight"
    // One key per group: each press moves to the next position in the cycle.
    case snapThirds = "snapCycle.thirds", snapTwoThirds = "snapCycle.twoThirds"
    case snapMaximize = "snap.maximize", snapCenter = "snap.center"

    /// The positions this action snaps to: one for a plain snap, several for a cycle.
    /// nil for non-snap actions.
    var snapPositions: [SnapPosition]? {
        switch self {
        case .snapThirds:    return [.firstThird, .centerThird, .lastThird]
        case .snapTwoThirds: return [.firstTwoThirds, .lastTwoThirds]
        // Pressing the top/bottom key again stretches the window to full height.
        case .snapTopHalf:    return [.topHalf, .stretchVertical]
        case .snapBottomHalf: return [.bottomHalf, .stretchVertical]
        default:
            guard rawValue.hasPrefix("snap.") else { return nil }
            return SnapPosition(rawValue: String(rawValue.dropFirst("snap.".count))).map { [$0] }
        }
    }

    /// Snapping actions in display order, grouped like the screen: halves, corners, thirds,
    /// then whole-window moves. The Snap Window menu and Settings → Snapping are both built
    /// from this list, so they always show the same items in the same order.
    static let snapGroups: [[HotkeyAction]] = [
        [.snapLeftHalf, .snapRightHalf, .snapTopHalf, .snapBottomHalf],
        [.snapTopLeft, .snapTopRight, .snapBottomLeft, .snapBottomRight],
        [.snapThirds, .snapTwoThirds],
        [.snapMaximize, .snapCenter, .fillSpace],
    ]

    static var snapping: [HotkeyAction] { snapGroups.flatMap { $0 } }
    static var general: [HotkeyAction] { allCases.filter { !snapping.contains($0) } }

    var title: String {
        switch self {
        case .tile:         return "Tile / Restore"
        case .tileOthers:   return "Tile Others"
        case .tuckAll:      return "Tuck All / Show All"
        case .nextLayout:   return "Next Layout"
        case .forgetLayout: return "Forget Saved Layout"
        case .fillSpace:    return "Fill Empty Space"
        case .snapMaximize:  return "Maximize / Restore"
        case .snapCenter:    return "Center / Restore"
        case .snapThirds:    return "Thirds"
        case .snapTwoThirds: return "Two Thirds"
        default:            return snapPositions?.first?.title ?? rawValue
        }
    }

    /// Every default is the global modifier combination (Settings → Hotkeys, ⌃⌥ unless
    /// changed) plus one key: arrows and letters laid out like the screen (U I / J K for
    /// corners). Thirds and two thirds each need only one key, since pressing again cycles.
    var defaultShortcut: Shortcut? {
        let base = HotkeyManager.baseModifiers
        func key(_ code: Int, _ name: String, _ mods: UInt32) -> Shortcut { Shortcut(keyCode: UInt32(code), modifiers: mods, key: name) }
        switch self {
        case .tile:               return key(kVK_ANSI_T, "T", base)
        case .tileOthers:         return key(kVK_ANSI_A, "A", base)
        case .tuckAll:            return key(kVK_ANSI_H, "H", base)
        case .nextLayout:         return key(kVK_ANSI_N, "N", base)
        case .forgetLayout:       return nil
        case .fillSpace:          return key(kVK_ANSI_Z, "Z", base)
        case .snapLeftHalf:       return key(kVK_LeftArrow, "←", base)
        case .snapRightHalf:      return key(kVK_RightArrow, "→", base)
        case .snapTopHalf:        return key(kVK_UpArrow, "↑", base)
        case .snapBottomHalf:     return key(kVK_DownArrow, "↓", base)
        case .snapTopLeft:        return key(kVK_ANSI_U, "U", base)
        case .snapTopRight:       return key(kVK_ANSI_I, "I", base)
        case .snapBottomLeft:     return key(kVK_ANSI_J, "J", base)
        case .snapBottomRight:    return key(kVK_ANSI_K, "K", base)
        case .snapThirds:         return key(kVK_ANSI_D, "D", base)
        case .snapTwoThirds:      return key(kVK_ANSI_E, "E", base)
        case .snapMaximize:       return key(kVK_Return, "↩", base)
        case .snapCenter:         return key(kVK_ANSI_C, "C", base)
        }
    }
}

/// Owns every global hotkey: reads the user's choices, registers them, and re-registers
/// on change. Settings are stored in UserDefaults under `hotkeys`. A missing entry means
/// "default"; an empty entry means the user cleared it.
final class HotkeyManager {
    enum SetResult { case ok, takenByOtherApp, usedBy(HotkeyAction) }

    private static let defaultsKey = "hotkeys"
    private static let baseModifiersKey = "hotkeyBaseModifiers"

    /// The modifier combinations offered for the defaults. Each needs ⌃, ⌥ or ⌘ so
    /// the arrows and letters don't swallow ordinary typing.
    static let modifierChoices: [UInt32] = [
        UInt32(controlKey | optionKey),
        UInt32(controlKey | cmdKey),
        UInt32(optionKey | cmdKey),
        UInt32(controlKey | optionKey | cmdKey),
        UInt32(controlKey | optionKey | shiftKey),
    ]

    /// The modifiers every default shortcut uses. Shortcuts the user recorded themselves
    /// are stored whole and don't change with this.
    static var baseModifiers: UInt32 {
        get {
            let stored = UInt32(UserDefaults.standard.integer(forKey: baseModifiersKey))
            return modifierChoices.contains(stored) ? stored : modifierChoices[0]
        }
        set { UserDefaults.standard.set(Int(newValue), forKey: baseModifiersKey) }
    }

    /// Switches the base modifiers and re-registers every hotkey that uses a default.
    func setBaseModifiers(_ modifiers: UInt32) {
        Self.baseModifiers = modifiers
        registerAll()
    }
    private var handlers: [HotkeyAction: () -> Void] = [:]
    private var registered: [HotkeyAction: Hotkey] = [:]
    /// Actions whose shortcut another app already holds.
    private(set) var unavailable: Set<HotkeyAction> = []

    func setHandler(for action: HotkeyAction, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    func shortcut(for action: HotkeyAction) -> Shortcut? {
        let stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) ?? [:]
        guard let entry = stored[action.rawValue] as? [String: Any] else { return action.defaultShortcut }
        return Shortcut(plist: entry)  // empty entry → nil → cleared
    }

    func registerAll() {
        for action in HotkeyAction.allCases { register(action) }
    }

    /// Unregisters everything while the recorder is listening, so pressing a combination
    /// Blossom already owns records it instead of firing it.
    func pauseAll() {
        registered.removeAll()
    }

    /// Changes one action's shortcut (nil clears it). If another app holds the combination,
    /// the previous shortcut is kept.
    func set(_ shortcut: Shortcut?, for action: HotkeyAction) -> SetResult {
        if let shortcut, let other = HotkeyAction.allCases.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            return .usedBy(other)
        }
        let previous = self.shortcut(for: action)
        save(shortcut, for: action)
        if register(action) { return .ok }
        save(previous, for: action)
        register(action)
        return .takenByOtherApp
    }

    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        registerAll()
    }

    // MARK: Private

    private func save(_ shortcut: Shortcut?, for action: HotkeyAction) {
        var stored = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) ?? [:]
        stored[action.rawValue] = shortcut?.plist ?? [String: Any]()
        UserDefaults.standard.set(stored, forKey: Self.defaultsKey)
    }

    /// Returns false only when a shortcut is set and macOS refused it.
    @discardableResult
    private func register(_ action: HotkeyAction) -> Bool {
        registered[action] = nil  // deinit unregisters the old one
        unavailable.remove(action)
        guard let shortcut = shortcut(for: action), let handler = handlers[action] else { return true }
        if let hotkey = Hotkey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, action: handler) {
            registered[action] = hotkey
            return true
        }
        unavailable.insert(action)
        return false
    }
}
