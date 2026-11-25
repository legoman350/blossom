import Foundation

/// Per-app Tuck preferences, stored in our own UserDefaults.
enum TuckSettings {

    /// What hides a floating app automatically. Default is `.switchSpace`.
    enum AutoTuckMode: String, CaseIterable {
        case none
        case loseFocus
        case switchSpace

        var title: String {
            switch self {
            case .none:        return "Off"
            case .loseFocus:   return "When it loses focus"
            case .switchSpace: return "When switching Spaces"
            }
        }
    }

    private static let modesKey = "autoTuckModes"                     // [bundleID: modeRawValue]
    private static let legacyKey = "autoHideBundleIDs"                // old Set<String> from early Tuck
    private static let newWindowKey = "autoRequestNewWindowBundleIDs"
    private static let importedKey = "importedStandaloneTuckSettings"
    /// The standalone Tuck app's defaults domain, imported once so settings carry over.
    private static let standaloneTuckDomain = "local.tuck.agent"

    /// Runs once per launch path; cheap after the first time.
    private static func migrateIfNeeded() {
        let defaults = UserDefaults.standard

        if !defaults.bool(forKey: importedKey) {
            defaults.set(true, forKey: importedKey)
            if let old = UserDefaults(suiteName: standaloneTuckDomain) {
                for key in [modesKey, legacyKey, newWindowKey] where defaults.object(forKey: key) == nil {
                    if let value = old.object(forKey: key) { defaults.set(value, forKey: key) }
                }
            }
        }

        // The old boolean auto-hide becomes `.loseFocus`.
        guard defaults.object(forKey: legacyKey) != nil else { return }
        var modes = defaults.dictionary(forKey: modesKey) as? [String: String] ?? [:]
        for id in defaults.stringArray(forKey: legacyKey) ?? [] where modes[id] == nil {
            modes[id] = AutoTuckMode.loseFocus.rawValue
        }
        defaults.set(modes, forKey: modesKey)
        defaults.removeObject(forKey: legacyKey)
    }

    static func autoTuckMode(for bundleID: String) -> AutoTuckMode {
        migrateIfNeeded()
        let modes = UserDefaults.standard.dictionary(forKey: modesKey) as? [String: String] ?? [:]
        return modes[bundleID].flatMap(AutoTuckMode.init(rawValue:)) ?? .switchSpace
    }

    static func setAutoTuckMode(_ mode: AutoTuckMode, for bundleID: String) {
        migrateIfNeeded()
        var modes = UserDefaults.standard.dictionary(forKey: modesKey) as? [String: String] ?? [:]
        modes[bundleID] = mode.rawValue
        UserDefaults.standard.set(modes, forKey: modesKey)
    }

    // MARK: Ask for a new window when the app has none (default off)

    static func isAutoRequestNewWindowEnabled(for bundleID: String) -> Bool {
        migrateIfNeeded()
        return Set(UserDefaults.standard.stringArray(forKey: newWindowKey) ?? []).contains(bundleID)
    }

    static func toggleAutoRequestNewWindow(for bundleID: String) {
        migrateIfNeeded()
        var ids = Set(UserDefaults.standard.stringArray(forKey: newWindowKey) ?? [])
        if ids.contains(bundleID) { ids.remove(bundleID) } else { ids.insert(bundleID) }
        UserDefaults.standard.set(Array(ids), forKey: newWindowKey)
    }
}
