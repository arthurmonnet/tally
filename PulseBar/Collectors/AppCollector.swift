import Foundation
import AppKit

@MainActor
final class AppCollector {
    private var activeAppName: String?
    private var activeAppStartTime: Date?
    private var activationObserver: NSObjectProtocol?
    private var flushTimer: Timer?

    // In-memory counters
    private var appSwitchCount: Int64 = 0
    private var appTimeBuckets: [String: TimeInterval] = [:]
    private var nopeApps: [String: Int64] = [:]

    private let db = Database.shared

    func start() {
        // Record initial active app
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            activeAppName = frontApp.localizedName ?? "Unknown"
            activeAppStartTime = Date()
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.handleAppSwitch(notification: notification)
        }

        // Flush every 10 seconds
        flushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flush()
            }
        }

        print("[AppCollector] Started")
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

        print("[AppCollector] Stopped")
    }

    private func handleAppSwitch(notification: Notification) {
        let now = Date()

        // Record duration of previous app
        if let previousApp = activeAppName, let startTime = activeAppStartTime {
            let duration = now.timeIntervalSince(startTime)
            appTimeBuckets[previousApp, default: 0] += duration

            // "Nope" detection: app was open for less than 3 seconds
            if duration < 3.0 {
                nopeApps[previousApp, default: 0] += 1
            }
        }

        // Track new app
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let appName = app.localizedName ?? "Unknown"
        activeAppName = appName
        activeAppStartTime = now
        appSwitchCount += 1
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
            let minutes = Int64(duration / 60.0)
            if minutes > 0 {
                events.append((statKey: "app_time:\(appName)", valueInt: minutes, valueFloat: 0.0))
            }
        }
        appTimeBuckets.removeAll()

        for (appName, count) in nopeApps {
            events.append((statKey: "app_nope:\(appName)", valueInt: count, valueFloat: 0.0))
        }
        nopeApps.removeAll()

        guard !events.isEmpty else { return }

        do {
            try db.upsertEvents(events)
        } catch {
            print("[AppCollector] Failed to flush: \(error)")
        }
    }
}
