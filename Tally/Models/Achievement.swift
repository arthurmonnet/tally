import Foundation
import GRDB

struct AchievementRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "achievements"

    let id: String
    let unlockedAt: String
    let triggerValue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case unlockedAt = "unlocked_at"
        case triggerValue = "trigger_value"
    }
}

struct AchievementDefinition: Codable, Sendable {
    let id: String
    let name: String
    let icon: String
    let description: String
    let condition: AchievementCondition
}

struct AchievementCondition: Codable, Sendable {
    let stat: String?
    let threshold: Double?
    let period: String?
    let also: AchievementAlso?
    let statCompare: [String]?

    enum CodingKeys: String, CodingKey {
        case stat
        case threshold
        case period
        case also
        case statCompare = "stat_compare"
    }
}

struct AchievementAlso: Codable, Sendable {
    let stat: String
    let max: Int64
}
