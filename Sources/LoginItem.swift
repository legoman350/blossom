import Foundation
import ServiceManagement

/// "Open at Login" through SMAppService (macOS 13+): public API, no extra permission.
/// The state lives in System Settings → General → Login Items, not in our defaults, so it
/// is always read fresh. The user may change it there at any time.
enum LoginItem {
    enum State { case on, off, needsApproval, unavailable }

    /// Registration is tied to the app's location. Only the installed copy should register;
    /// registering a copy in build/ would make login launch a build that may be deleted.
    static var isInstalled: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    static var state: State {
        guard isInstalled else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled:          return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered:    return .off
        case .notFound:         return .unavailable
        @unknown default:       return .off
        }
    }

    /// Returns an error message to show, or nil on success.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            NSLog("Blossom: login item \(on ? "register" : "unregister") failed: \(error)")
            return "Couldn't change the login item: \(error.localizedDescription)"
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
