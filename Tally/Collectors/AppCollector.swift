import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "AppCollector")

@MainActor
final class AppCollector {
    private var activeAppName: String?
    private var activeAppStartTime: Date?
    private var activationObserver: NSObjectProtocol?
    private var flushTimer: Timer?

    // In-memory counters
    private var appSwitchCount: Int64 = 0
    private var appTimeBuckets: [String: TimeInterval] = [:]
    private var appBundleIDs: [String: String] = [:]  // displayName → bundleID

    private let db = Database.shared

    func start() {
        // Record initial active app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            activeAppName = frontApp.localizedName ?? "Unknown"
            activeAppStartTime = Date()
            if let bundleID = frontApp.bundleIdentifier,
               let name = frontApp.localizedName {
                appBundleIDs[name] = bundleID
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            MainActor.assumeIsolated {
                self.handleAppSwitch(notification: notification)
            }
        }

        // Flush every 10 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                self.flush()
            }
        }

        logger.info("Started")
    }

    func stop() {
        // Record time for current app before stopping
        recordActiveAppDuration()
        flush()

        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        flushTimer?.invalidate()
        flushTimer = nil

        logger.info("Stopped")
    }

    private func handleAppSwitch(notification: Notification) {
        let now = Date()

        // Record duration of previous app
        if let previousApp = activeAppName, let startTime = activeAppStartTime {
            let duration = now.timeIntervalSince(startTime)
            appTimeBuckets[previousApp, default: 0] += duration

        }

        // Track new app
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let appName = app.localizedName ?? "Unknown"
        activeAppName = appName
        activeAppStartTime = now
        appSwitchCount += 1

        // Capture bundle ID
        if let bundleID = app.bundleIdentifier {
            appBundleIDs[appName] = bundleID
        }
    }

    private func recordActiveAppDuration() {
        if let currentApp = activeAppName, let startTime = activeAppStartTime {
            let duration = Date().timeIntervalSince(startTime)
            appTimeBuckets[currentApp, default: 0] += duration
            activeAppStartTime = Date()  // Reset for next period
        }
    }

    private func flush() {
        recordActiveAppDuration()

        var events: [(statKey: String, valueInt: Int64, valueFloat: Double)] = []

        if appSwitchCount > 0 {
            events.append((statKey: "app_switches", valueInt: appSwitchCount, valueFloat: 0.0))
            appSwitchCount = 0
        }

        for (appName, duration) in appTimeBuckets {
            let seconds = Int64(duration)
            if seconds > 0 {
                events.append((statKey: "app_time:\(appName)", valueInt: seconds, valueFloat: 0.0))
            }
        }
        appTimeBuckets.removeAll()

        // Store bundle ID mappings (valueInt=1 is a marker, the key encodes the mapping)
        for (appName, bundleID) in appBundleIDs {
            events.append((statKey: "app_bundle:\(appName):\(bundleID)", valueInt: 1, valueFloat: 0.0))
        }

        guard !events.isEmpty else { return }

        do {
            try db.upsertEvents(events)
        } catch {
            logger.error("Failed to flush: \(error)")
        }
    }
}
