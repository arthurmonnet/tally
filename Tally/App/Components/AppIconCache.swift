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

    func base64PNG(for appName: String, bundleID: String? = nil, size: CGFloat = 32) -> String? {
        let image = icon(for: appName, bundleID: bundleID)
        let targetSize = NSSize(width: size, height: size)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()

        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.8]) else {
            return nil
        }
        return png.base64EncodedString()
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
