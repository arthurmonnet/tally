import Foundation
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "LiveStats")

/// In-memory cumulative counters for today's stats.
/// CGEventTap and FSEvent callbacks increment these immediately,
/// so SwiftUI views always show the latest values without DB queries.
/// The database flush timer persists deltas to SQLite independently.
///
/// Counters automatically reset at midnight: every increment checks
/// whether the calendar day has changed and re-seeds from the database
/// for the new day.
@MainActor
@Observable
final class LiveStats {
    // MARK: - CGEventTap stats (instant updates)
    var keystrokes: Int64 = 0
    var clicksLeft: Int64 = 0
    var clicksRight: Int64 = 0
    var copy: Int64 = 0
    var paste: Int64 = 0
    var cmdZ: Int64 = 0
    var launcherOpens: Int64 = 0
    var scrollDistanceM: Double = 0
    var mouseDistanceM: Double = 0

    // MARK: - File events (instant updates)
    var screenshots: Int64 = 0

    /// The date string (yyyy-MM-dd) these counters belong to.
    /// When this no longer matches the current calendar day, counters reset.
    private var currentDate: String = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Seed from database

    /// Load today's cumulative totals from the database so counters
    /// don't start at zero on app launch.
    func seedFromDatabase() {
        currentDate = Self.dateFormatter.string(from: Date())
        do {
            let raw = try Database.shared.todayStats()
            keystrokes = raw["keystrokes"]?.int ?? 0
            clicksLeft = raw["clicks_left"]?.int ?? 0
            clicksRight = raw["clicks_right"]?.int ?? 0
            copy = raw["copy"]?.int ?? 0
            paste = raw["paste"]?.int ?? 0
            cmdZ = raw["cmd_z"]?.int ?? 0
            launcherOpens = raw["launcher_opens"]?.int ?? 0
            scrollDistanceM = raw["scroll_distance_m"]?.float ?? 0
            mouseDistanceM = raw["mouse_distance_m"]?.float ?? 0
            screenshots = raw["screenshots"]?.int ?? 0
        } catch {
            logger.error("Failed to seed from database: \(error)")
        }
    }

    // MARK: - Day rollover

    /// Check if the calendar day has changed and reset counters if so.
    /// Called before every increment to ensure counters always reflect
    /// only the current day.
    private func resetIfNewDay() {
        let today = Self.dateFormatter.string(from: Date())
        guard today != currentDate else { return }
        logger.info("Day changed from \(self.currentDate) to \(today) — resetting counters")
        seedFromDatabase()
    }

    // MARK: - Increment helpers (called from collectors)

    func increment(_ key: String) {
        resetIfNewDay()
        switch key {
        case "keystrokes": keystrokes += 1
        case "clicks_left": clicksLeft += 1
        case "clicks_right": clicksRight += 1
        case "copy": copy += 1
        case "paste": paste += 1
        case "cmd_z": cmdZ += 1
        case "launcher_opens": launcherOpens += 1
        case "screenshots": screenshots += 1
        default: break
        }
    }

    func addFloat(_ key: String, value: Double) {
        resetIfNewDay()
        switch key {
        case "scroll_distance_m": scrollDistanceM += value
        case "mouse_distance_m": mouseDistanceM += value
        default: break
        }
    }
}
