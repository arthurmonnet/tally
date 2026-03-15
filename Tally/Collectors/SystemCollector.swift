import Foundation
import AppKit
import CoreGraphics

@MainActor
final class SystemCollector {
    private var pollTimer: Timer?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lastSleepTime: Date?
    private var lastDarkModeState: Bool?
    private var darkModeStartTime: Date?

    // In-memory counters
    private var counters: [String: Int64] = [:]
    private var peakRam: Double = 0

    private let db = Database.shared

    func start() {
        // Track dark mode
        lastDarkModeState = isDarkMode
        darkModeStartTime = Date()

        // Sleep/wake observers
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSleep()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWake()
        }

        // Poll every 60 seconds for RAM + dark mode + window count
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }

        print("[SystemCollector] Started")
    }

    func stop() {
        flush()
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        pollTimer?.invalidate()
        pollTimer = nil
        print("[SystemCollector] Stopped")
    }

    private func handleSleep() {
        lastSleepTime = Date()
        flushDarkModeTime()
    }

    private func handleWake() {
        guard let sleepTime = lastSleepTime else { return }
        let interval = Date().timeIntervalSince(sleepTime)

        // "One More Thing" — reopened within 5 minutes
        if interval < 300 {
            counters["sleep_wake_quick", default: 0] += 1
        }

        lastSleepTime = nil
        darkModeStartTime = Date()
        lastDarkModeState = isDarkMode
    }

    private func poll() {
        // Peak RAM
        let ramGB = currentRAMUsageGB()
        if ramGB > peakRam {
            peakRam = ramGB
        }

        // Dark mode tracking
        let currentDarkMode = isDarkMode
        if currentDarkMode != lastDarkModeState {
            flushDarkModeTime()
            lastDarkModeState = currentDarkMode
            darkModeStartTime = Date()
        } else {
            flushDarkModeTime()
            darkModeStartTime = Date()
        }

        // After-midnight activity tracking
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 6 {  // Between midnight and 6 AM
            counters["active_after_midnight_m", default: 0] += 1  // 1 minute per poll
        }

        // Window count (snapshot stat — uses setEvent, not upsert)
        let windowCount = countVisibleWindows()
        if windowCount > 0 {
            let bucket = windowCountBucket()
            do {
                try db.setEvent(bucket: bucket, statKey: "window_count", valueInt: Int64(windowCount))
            } catch {
                print("[SystemCollector] Failed to store window count: \(error)")
            }
        }

        flush()
    }

    private func flushDarkModeTime() {
        guard let startTime = darkModeStartTime else { return }
        let minutes = Int64(Date().timeIntervalSince(startTime) / 60.0)
        guard minutes > 0 else { return }

        let key = (lastDarkModeState ?? false) ? "dark_mode_m" : "light_mode_m"
        counters[key, default: 0] += minutes
    }

    private func flush() {
        var events: [(statKey: String, valueInt: Int64, valueFloat: Double)] = []

        for (key, value) in counters {
            events.append((statKey: key, valueInt: value, valueFloat: 0.0))
        }
        counters.removeAll()

        if peakRam > 0 {
            events.append((statKey: "peak_ram_gb", valueInt: 0, valueFloat: peakRam))
            peakRam = 0
        }

        guard !events.isEmpty else { return }

        do {
            try db.upsertEvents(events)
        } catch {
            print("[SystemCollector] Failed to flush: \(error)")
        }
    }

    // MARK: - Window Count

    private func countVisibleWindows() -> Int {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return 0 }

        return windowList.filter { info in
            // Only count regular windows (layer 0), filter out tiny windows (<100px)
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { return false }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let height = bounds["Height"] as? Int else { return false }
            return height > 100
        }.count
    }

    /// 1-minute bucket for window count (finer granularity than the standard 5-min bucket)
    private func windowCountBucket() -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:00",
            components.year ?? 2026,
            components.month ?? 1,
            components.day ?? 1,
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    // MARK: - System Info

    private var isDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    private func currentRAMUsageGB() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let usedBytes = Double(stats.active_count + stats.wire_count) * pageSize
        return usedBytes / (1024 * 1024 * 1024)
    }
}
