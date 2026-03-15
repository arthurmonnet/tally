import Foundation

struct AppFilter: Sendable {

    // Apps to always exclude from top_apps display
    static let systemApps: Set<String> = [
        // macOS system
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.SystemUIServer",
        "com.apple.loginwindow",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.screensaver",
        "com.apple.security.pboxd",

        // System utilities
        "com.apple.ActivityMonitor",
        "com.apple.systempreferences",
        "com.apple.keychainaccess",
        "com.apple.diskutility",
        "com.apple.Console",

        // Background processes that sometimes grab focus
        "com.apple.CoreServicesUIAgent",
        "com.apple.UserNotificationCenter",
        "com.apple.universalcontrol",
    ]

    // Apps to always include even if they seem utility-like
    static let alwaysInclude: Set<String> = [
        "com.apple.Terminal",
        "com.apple.dt.Xcode",
        "com.apple.Preview",
        "com.apple.iWork.Keynote",
    ]

    // Fallback: filter by display name for old data without bundle IDs
    static let systemAppNames: Set<String> = [
        "Finder",
        "Dock",
        "SystemUIServer",
        "loginwindow",
        "Control Center",
        "Notification Center",
        "Spotlight",
        "Screenshot",
        "Activity Monitor",
        "System Settings",
        "System Preferences",
        "Keychain Access",
        "Disk Utility",
        "Console",
        "CoreServicesUIAgent",
        "UserNotificationCenter",
        "UniversalControl",
    ]

    static func shouldDisplay(bundleID: String) -> Bool {
        if alwaysInclude.contains(bundleID) { return true }
        if systemApps.contains(bundleID) { return false }
        return true
    }

    static func shouldDisplay(name: String) -> Bool {
        return !systemAppNames.contains(name)
    }

    static func shouldDisplay(name: String, bundleID: String?) -> Bool {
        if let bundleID {
            return shouldDisplay(bundleID: bundleID)
        }
        return shouldDisplay(name: name)
    }
}
