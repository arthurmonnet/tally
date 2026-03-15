import Foundation
import GRDB

struct DailySummary: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "daily_summary"

    let date: String
    let statsJson: String
    let achievementsJson: String?
    let pushedAt: String?

    enum CodingKeys: String, CodingKey {
        case date
        case statsJson = "stats_json"
        case achievementsJson = "achievements_json"
        case pushedAt = "pushed_at"
    }
}

struct DailyStats: Codable, Sendable {
    let keystrokes: Int64
    let clicksLeft: Int64
    let clicksRight: Int64
    let copy: Int64
    let paste: Int64
    let cmdZ: Int64
    let cmdK: Int64
    let launcherOpens: Int64
    let scrollDistanceM: Double
    let mouseDistanceM: Double
    let appSwitches: Int64
    let screenshots: Int64
    let filesDeleted: Int64
    let gitCommits: Int64
    let gitStashes: Int64
    let darkModeM: Int64
    let lightModeM: Int64
    let peakRamGb: Double
    let sleepWakeQuick: Int64
    let activeAfterMidnightM: Int64
    let topApps: [AppTimeEntry]
    let filesCreated: [String: Int64]

    init() {
        self.keystrokes = 0
        self.clicksLeft = 0
        self.clicksRight = 0
        self.copy = 0
        self.paste = 0
        self.cmdZ = 0
        self.cmdK = 0
        self.launcherOpens = 0
        self.scrollDistanceM = 0
        self.mouseDistanceM = 0
        self.appSwitches = 0
        self.screenshots = 0
        self.filesDeleted = 0
        self.gitCommits = 0
        self.gitStashes = 0
        self.darkModeM = 0
        self.lightModeM = 0
        self.peakRamGb = 0
        self.sleepWakeQuick = 0
        self.activeAfterMidnightM = 0
        self.topApps = []
        self.filesCreated = [:]
    }
}

struct AppTimeEntry: Codable, Sendable {
    let name: String
    let minutes: Int64
}
