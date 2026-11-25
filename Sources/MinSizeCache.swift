import Foundation

/// Minimum window sizes learned per app, persisted in UserDefaults.
///
/// No public API reports a window's minimum size. Some apps expose AXMinimumSize, but most
/// don't, so we can't rely on it. Shrinking a window to 1×1 to measure it would flicker and
/// can upset the app's own resize logic. Instead we learn from ordinary tiling: when a
/// window comes back larger than the size we asked for, that size is its minimum.
///
/// Keyed per app, not per window. An app's windows can differ (main window vs. a palette),
/// so this errs on the large side, and a too-big cell beats an overlap.
enum MinSizeCache {
    private static let key = "learnedMinSizes"  // [bundleID: [width, height]]

    static func minSize(for bundleID: String?) -> CGSize {
        guard let bundleID, let pair = all()[bundleID], pair.count == 2 else { return .zero }
        return CGSize(width: pair[0], height: pair[1])
    }

    /// Only ever grows: a minimum doesn't shrink because one window happened to be smaller.
    static func learn(_ observed: CGSize, for bundleID: String?) {
        guard let bundleID, observed.width > 0 || observed.height > 0 else { return }
        let old = minSize(for: bundleID)
        let merged = CGSize(width: max(old.width, observed.width), height: max(old.height, observed.height))
        guard merged != old else { return }
        var dict = all()
        dict[bundleID] = [Double(merged.width), Double(merged.height)]
        UserDefaults.standard.set(dict, forKey: key)
        NSLog("Blossom: learned min size \(merged) for \(bundleID)")
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func all() -> [String: [Double]] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
    }
}
