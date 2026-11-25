import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility is the only permission this app uses. With `prompt: true`, macOS shows
    /// its own dialog the first time; after that it's a silent check.
    static func isTrusted(prompt: Bool = false) -> Bool {
        // The literal value of kAXTrustedCheckOptionPrompt. Using the string avoids touching
        // a mutable C global, which Swift 6 concurrency checking rejects.
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
