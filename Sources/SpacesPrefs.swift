import Foundation

/// Which apps Tuck manages: apps assigned to "All Desktops" in the Dock, plus a manual list.
///
/// The Dock setting lives in com.apple.spaces, which Apple treats as an implementation
/// detail rather than API. We only READ it (never write), and the manual list is the
/// fallback for when the read breaks on some future macOS.
enum SpacesPrefs {
    private static let manualKey = "tuckManualBundleIDs"

    /// Lowercased bundle IDs of every floating app. Spaces may store
    /// "com.apple.mobilesms" while the running app reports "com.apple.MobileSMS", so all
    /// comparisons are case-insensitive.
    static func floatingBundleIDs() -> Set<String> {
        dockAllDesktopsBundleIDs().union(manualBundleIDs().map { $0.lowercased() })
    }

    /// Lowercased bundle IDs assigned to All Desktops in the Dock. Empty if unreadable.
    ///
    /// Stored in com.apple.spaces under `app-bindings`:
    ///   "com.apple.Safari" = "AllSpaces"      -> All Desktops
    ///   "com.apple.Safari" = "<space-uuid>"   -> one specific desktop
    ///   (absent)                              -> None
    static func dockAllDesktopsBundleIDs() -> Set<String> {
        guard let bindings = viaCFPreferences() ?? viaPlistFile() else { return [] }
        var out = Set<String>()
        for (key, value) in bindings where (value as? String) == "AllSpaces" {
            out.insert(key.lowercased())
        }
        return out
    }

    // MARK: Manual list (the fallback)

    static func manualBundleIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: manualKey) ?? [])
    }

    static func isManual(_ bundleID: String) -> Bool {
        manualBundleIDs().contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    static func toggleManual(_ bundleID: String) {
        var ids = manualBundleIDs()
        if let existing = ids.first(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            ids.remove(existing)
        } else {
            ids.insert(bundleID)
        }
        UserDefaults.standard.set(Array(ids), forKey: manualKey)
    }

    // MARK: Reading com.apple.spaces (read-only)

    private static func viaCFPreferences() -> [String: Any]? {
        let appID = "com.apple.spaces" as CFString
        _ = CFPreferencesAppSynchronize(appID)
        return CFPreferencesCopyAppValue("app-bindings" as CFString, appID) as? [String: Any]
    }

    private static func viaPlistFile() -> [String: Any]? {
        let path = NSHomeDirectory() + "/Library/Preferences/com.apple.spaces.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let parsed = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = parsed as? [String: Any] else { return nil }
        return plist["app-bindings"] as? [String: Any]
    }
}
