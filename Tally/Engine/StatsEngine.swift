import Foundation

struct StatsEngine: Sendable {
    private let db = Database.shared

    func todayStats() throws -> DailyStats {
        let raw = try db.todayStats()
        let todayPrefix = db.todayDateString() + "T00:00:00"
        let peakRam = try db.peakFloat(statKey: "peak_ram_gb", since: todayPrefix)

        // Build displayName → bundleID map from app_bundle entries
        var bundleMap: [String: String] = [:]
        for key in raw.keys where key.hasPrefix("app_bundle:") {
            let rest = String(key.dropFirst("app_bundle:".count))
            if let colonIdx = rest.lastIndex(of: ":") {
                let name = String(rest[rest.startIndex..<colonIdx])
                let bundleID = String(rest[rest.index(after: colonIdx)...])
                bundleMap[name] = bundleID
            }
        }

        let topApps = raw
            .filter { $0.key.hasPrefix("app_time:") }
            .map { AppTimeEntry(name: String($0.key.dropFirst("app_time:".count)), minutes: $0.value.int / 60) }
            .filter { AppFilter.shouldDisplay(name: $0.name, bundleID: bundleMap[$0.name]) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }

        return DailyStats(
            keystrokes: raw["keystrokes"]?.int ?? 0,
            clicksLeft: raw["clicks_left"]?.int ?? 0,
            clicksRight: raw["clicks_right"]?.int ?? 0,
            copy: raw["copy"]?.int ?? 0,
            paste: raw["paste"]?.int ?? 0,
            cmdZ: raw["cmd_z"]?.int ?? 0,
            launcherOpens: raw["launcher_opens"]?.int ?? 0,
            scrollDistanceM: raw["scroll_distance_m"]?.float ?? 0,
            mouseDistanceM: raw["mouse_distance_m"]?.float ?? 0,
            appSwitches: raw["app_switches"]?.int ?? 0,
            screenshots: raw["screenshots"]?.int ?? 0,
            darkModeM: raw["dark_mode_m"]?.int ?? 0,
            lightModeM: raw["light_mode_m"]?.int ?? 0,
            peakRamGb: peakRam,
            sleepWakeQuick: raw["sleep_wake_quick"]?.int ?? 0,
            activeAfterMidnightM: raw["active_after_midnight_m"]?.int ?? 0,
            topApps: topApps
        )
    }

    // MARK: - Stat History

    func history(for statKeys: [String], days: Int = 7) throws -> StatHistory {
        let dayData = try db.statHistoryByDay(statKeys: statKeys, days: days)

        let values = dayData.map(\.value)
        let total = values.reduce(0, +)
        let nonZeroCount = values.filter { $0 > 0 }.count
        let average = nonZeroCount > 0 ? Double(total) / Double(nonZeroCount) : 0

        var peakDate = ""
        var peakValue: Int64 = 0
        for day in dayData {
            if day.value > peakValue {
                peakValue = day.value
                peakDate = day.date
            }
        }

        let todayValue = dayData.last?.value ?? 0
        let todayVsAverage = average > 0 ? (Double(todayValue) - average) / average : 0

        return StatHistory(
            keys: statKeys,
            days: dayData.map { StatHistoryDay(date: $0.date, value: $0.value) },
            average: average,
            peak: StatHistoryPeak(date: peakDate, value: peakValue),
            todayVsAverage: todayVsAverage
        )
    }

    func history(for statKey: String, days: Int = 7) throws -> StatHistory {
        return try history(for: [statKey], days: days)
    }

    func todayStatsJSON() throws -> String {
        let stats = try todayStats()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(stats)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func achievementsJSON() throws -> String {
        let records = try db.unlockedAchievements()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(records)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func generateDailySummary(date: String) throws {
        let stats = try todayStatsJSON()
        let achievements = try achievementsJSON()
        try db.saveDailySummary(date: date, statsJson: stats, achievementsJson: achievements)
    }

    func generateFunLine() throws -> String {
        let stats = try todayStats()
        var parts: [String] = []

        if stats.keystrokes > 0 {
            parts.append(formatNumber(stats.keystrokes) + " keystrokes")
        }
        if stats.screenshots > 0 {
            parts.append("\(stats.screenshots) screenshots")
        }
        if stats.launcherOpens > 0 {
            parts.append("\(stats.launcherOpens) launcher opens")
        }

        if let topApp = stats.topApps.first {
            parts.append("mostly in \(topApp.name)")
        }

        return parts.joined(separator: " \u{00B7} ")
    }

    private func formatNumber(_ n: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - History Types

struct StatHistory: Codable, Sendable {
    let keys: [String]
    let days: [StatHistoryDay]
    let average: Double
    let peak: StatHistoryPeak
    let todayVsAverage: Double

    enum CodingKeys: String, CodingKey {
        case keys = "stat"
        case days
        case average
        case peak
        case todayVsAverage = "today_vs_average"
    }
}

struct StatHistoryDay: Codable, Sendable {
    let date: String
    let value: Int64
}

struct StatHistoryPeak: Codable, Sendable {
    let date: String
    let value: Int64
}

extension DailyStats {
    init(
        keystrokes: Int64, clicksLeft: Int64, clicksRight: Int64,
        copy: Int64, paste: Int64, cmdZ: Int64,
        launcherOpens: Int64, scrollDistanceM: Double, mouseDistanceM: Double,
        appSwitches: Int64, screenshots: Int64,
        darkModeM: Int64, lightModeM: Int64, peakRamGb: Double,
        sleepWakeQuick: Int64, activeAfterMidnightM: Int64,
        topApps: [AppTimeEntry]
    ) {
        self.keystrokes = keystrokes
        self.clicksLeft = clicksLeft
        self.clicksRight = clicksRight
        self.copy = copy
        self.paste = paste
        self.cmdZ = cmdZ
        self.launcherOpens = launcherOpens
        self.scrollDistanceM = scrollDistanceM
        self.mouseDistanceM = mouseDistanceM
        self.appSwitches = appSwitches
        self.screenshots = screenshots
        self.darkModeM = darkModeM
        self.lightModeM = lightModeM
        self.peakRamGb = peakRamGb
        self.sleepWakeQuick = sleepWakeQuick
        self.activeAfterMidnightM = activeAfterMidnightM
        self.topApps = topApps
    }
}
