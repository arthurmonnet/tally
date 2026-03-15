import AppKit
import UniformTypeIdentifiers

final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(for appName: String, bundleID: String? = nil) -> NSImage {
        lock.lock()
        if let cached = cache[appName] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolveIcon(appName: appName, bundleID: bundleID)

        lock.lock()
        cache[appName] = resolved
        lock.unlock()

        return resolved
    }

    private func resolveIcon(appName: String, bundleID: String?) -> NSImage {
        // Method 1: Look up by bundle ID (most reliable)
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        // Method 2: Find running app by name
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == appName
        }), let icon = app.icon {
            return icon
        }

        // Method 3: Search common app directories
        let paths = [
            "/Applications/\(appName).app",
            "/Applications/Utilities/\(appName).app",
            "/System/Applications/\(appName).app",
            "/System/Applications/Utilities/\(appName).app",
            NSHomeDirectory() + "/Applications/\(appName).app",
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }

        // Fallback: generic app icon
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
