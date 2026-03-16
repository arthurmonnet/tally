import Foundation
import GRDB

struct StatEvent: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "events"

    let id: Int64?
    let bucket: String
    let statKey: String
    let valueInt: Int64
    let valueFloat: Double

    enum CodingKeys: String, CodingKey {
        case id
        case bucket
        case statKey = "stat_key"
        case valueInt = "value_int"
        case valueFloat = "value_float"
    }

    init(bucket: String, statKey: String, valueInt: Int64 = 0, valueFloat: Double = 0.0) {
        self.id = nil
        self.bucket = bucket
        self.statKey = statKey
        self.valueInt = valueInt
        self.valueFloat = valueFloat
    }

    static func currentBucket() -> String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let roundedMinute = (components.minute ?? 0) / 5 * 5
        let bucketDate = calendar.date(
            from: DateComponents(
                year: components.year,
                month: components.month,
                day: components.day,
                hour: components.hour,
                minute: roundedMinute,
                second: 0
            )
        ) ?? now

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        let full = formatter.string(from: bucketDate)
        // Trim to seconds precision: "2026-03-13T14:35:00"
        if let range = full.range(of: "T") {
            let datePart = String(full[full.startIndex..<range.lowerBound])
            let hourMin = String(format: "%02d:%02d:00", components.hour ?? 0, roundedMinute)
            return "\(datePart)T\(hourMin)"
        }
        return full
    }
}
