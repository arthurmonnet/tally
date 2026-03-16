import Foundation
import GRDB

final class Database: Sendable {
    private let dbPool: DatabasePool

    static let shared: Database = {
        do {
            return try Database()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }()

    private init() throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let tallyDir = appSupport.appendingPathComponent("Tally")

        // Migrate from old "Pulse" directory if it exists
        let oldDir = appSupport.appendingPathComponent("Pulse")
        if FileManager.default.fileExists(atPath: oldDir.path) &&
           !FileManager.default.fileExists(atPath: tallyDir.path) {
            try FileManager.default.moveItem(at: oldDir, to: tallyDir)
        }

        try FileManager.default.createDirectory(at: tallyDir, withIntermediateDirectories: true)

        let dbPath = tallyDir.appendingPathComponent("tally.db").path
        dbPool = try DatabasePool(path: dbPath)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tables") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    bucket TEXT NOT NULL,
                    stat_key TEXT NOT NULL,
                    value_int INTEGER DEFAULT 0,
                    value_float REAL DEFAULT 0.0,
                    UNIQUE(bucket, stat_key)
                );

                CREATE TABLE IF NOT EXISTS daily_summary (
                    date TEXT PRIMARY KEY,
                    stats_json TEXT NOT NULL,
                    achievements_json TEXT,
                    pushed_at TEXT
                );

                CREATE TABLE IF NOT EXISTS achievements (
                    id TEXT PRIMARY KEY,
                    unlocked_at TEXT NOT NULL,
                    trigger_value TEXT
                );

                CREATE TABLE IF NOT EXISTS config (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_events_bucket ON events(bucket);
                CREATE INDEX IF NOT EXISTS idx_events_key ON events(stat_key);
            """)
        }

        try migrator.migrate(dbPool)
    }

    // MARK: - Upsert Events

    func upsertEvent(bucket: String, statKey: String, incrementInt: Int64 = 0, incrementFloat: Double = 0.0) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (bucket, stat_key, value_int, value_float)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(bucket, stat_key) DO UPDATE SET
                        value_int = value_int + excluded.value_int,
                        value_float = value_float + excluded.value_float
                """,
                arguments: [bucket, statKey, incrementInt, incrementFloat]
            )
        }
    }

    func upsertEvents(_ events: [(statKey: String, valueInt: Int64, valueFloat: Double)]) throws {
        let bucket = StatEvent.currentBucket()
        try dbPool.write { db in
            for event in events {
                try db.execute(
                    sql: """
                        INSERT INTO events (bucket, stat_key, value_int, value_float)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(bucket, stat_key) DO UPDATE SET
                            value_int = value_int + excluded.value_int,
                            value_float = value_float + excluded.value_float
                    """,
                    arguments: [bucket, event.statKey, event.valueInt, event.valueFloat]
                )
            }
        }
    }

    func upsertMax(_ events: [(statKey: String, valueFloat: Double)]) throws {
        let bucket = StatEvent.currentBucket()
        try dbPool.write { db in
            for event in events {
                try db.execute(
                    sql: """
                        INSERT INTO events (bucket, stat_key, value_int, value_float)
                        VALUES (?, ?, 0, ?)
                        ON CONFLICT(bucket, stat_key) DO UPDATE SET
                            value_float = MAX(value_float, excluded.value_float)
                    """,
                    arguments: [bucket, event.statKey, event.valueFloat]
                )
            }
        }
    }

    // MARK: - Query Today's Stats

    func todayStats() throws -> [String: (int: Int64, float: Double)] {
        let todayPrefix = todayDateString() + "T"
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT stat_key, SUM(value_int) as total_int, SUM(value_float) as total_float
                    FROM events
                    WHERE bucket >= ?
                    GROUP BY stat_key
                """,
                arguments: [todayPrefix + "00:00:00"]
            )
            var result: [String: (int: Int64, float: Double)] = [:]
            for row in rows {
                let key: String = row["stat_key"]
                let totalInt: Int64 = row["total_int"]
                let totalFloat: Double = row["total_float"]
                result[key] = (int: totalInt, float: totalFloat)
            }
            return result
        }
    }

    func statSum(statKey: String, since: String) throws -> Int64 {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT SUM(value_int) as total FROM events WHERE stat_key = ? AND bucket >= ?",
                arguments: [statKey, since]
            )
            return row?["total"] ?? 0
        }
    }

    func statSumFloat(statKey: String, since: String) throws -> Double {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT SUM(value_float) as total FROM events WHERE stat_key = ? AND bucket >= ?",
                arguments: [statKey, since]
            )
            return row?["total"] ?? 0.0
        }
    }

    // MARK: - Gauge Stats (latest value, not sum)

    /// Returns the latest value for a snapshot/gauge stat (e.g. window_count)
    func latestValue(statKey: String, since: String) throws -> Int64 {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT value_int FROM events
                    WHERE stat_key = ? AND bucket >= ?
                    ORDER BY bucket DESC LIMIT 1
                """,
                arguments: [statKey, since]
            )
            return row?["value_int"] ?? 0
        }
    }

    /// Returns the peak (max) value for a stat across all buckets since a given time
    func peakValue(statKey: String, since: String) throws -> Int64 {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(value_int), 0) as peak FROM events
                    WHERE stat_key = ? AND bucket >= ?
                """,
                arguments: [statKey, since]
            )
            return row?["peak"] ?? 0
        }
    }

    func peakFloat(statKey: String, since: String) throws -> Double {
        try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(value_float), 0) as peak FROM events
                    WHERE stat_key = ? AND bucket >= ?
                """,
                arguments: [statKey, since]
            )
            return row?["peak"] ?? 0
        }
    }

    // MARK: - Today's Achievements

    func todayAchievements() throws -> [AchievementRecord] {
        let todayPrefix = todayDateString()
        return try dbPool.read { db in
            try AchievementRecord
                .filter(Column("unlocked_at") >= todayPrefix)
                .fetchAll(db)
        }
    }

    // MARK: - Stat History by Day

    func statHistoryByDay(statKeys: [String], days: Int) throws -> [(date: String, value: Int64)] {
        let calendar = Calendar.current
        let today = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        // Calculate the start date
        guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        let startDateStr = formatter.string(from: startDate)

        // Build query for one or more stat keys
        let placeholders = statKeys.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT substr(bucket, 1, 10) as day, SUM(value_int) as total
            FROM events
            WHERE stat_key IN (\(placeholders)) AND substr(bucket, 1, 10) >= ?
            GROUP BY day
            ORDER BY day
        """
        var args: [any DatabaseValueConvertible] = statKeys.map { $0 as any DatabaseValueConvertible }
        args.append(startDateStr)

        let rows = try dbPool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
        }

        // Build a lookup from query results
        var resultMap: [String: Int64] = [:]
        for row in rows {
            let day: String = row["day"]
            let total: Int64 = row["total"]
            resultMap[day] = total
        }

        // Fill all days (including missing ones as 0)
        var result: [(date: String, value: Int64)] = []
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -(days - 1 - offset), to: today) else { continue }
            let dateStr = formatter.string(from: date)
            result.append((date: dateStr, value: resultMap[dateStr] ?? 0))
        }

        return result
    }

    // MARK: - Timeline Buckets (for intraday time-series like window_count)

    func timelineBuckets(statKey: String, date: String) throws -> [(time: String, value: Int64)] {
        return try dbPool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT bucket, value_int
                    FROM events
                    WHERE stat_key = ? AND substr(bucket, 1, 10) = ?
                    ORDER BY bucket
                """,
                arguments: [statKey, date]
            )
            return rows.map { row in
                let bucket: String = row["bucket"]
                // Extract time portion (HH:MM) from bucket like "2026-03-14T09:15:00"
                let time = bucket.count > 11 ? String(bucket.suffix(from: bucket.index(bucket.startIndex, offsetBy: 11)).prefix(5)) : bucket
                let value: Int64 = row["value_int"]
                return (time: time, value: value)
            }
        }
    }

    // MARK: - Set Event (for snapshot stats like window_count, non-cumulative)

    func setEvent(bucket: String, statKey: String, valueInt: Int64) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO events (bucket, stat_key, value_int, value_float)
                    VALUES (?, ?, ?, 0.0)
                    ON CONFLICT(bucket, stat_key) DO UPDATE SET
                        value_int = excluded.value_int
                """,
                arguments: [bucket, statKey, valueInt]
            )
        }
    }

    // MARK: - History

    func historyDays(limit: Int = 30) throws -> [DailySummary] {
        try dbPool.read { db in
            try DailySummary.order(Column("date").desc).limit(limit).fetchAll(db)
        }
    }

    // MARK: - Achievements

    func unlockedAchievements() throws -> [AchievementRecord] {
        try dbPool.read { db in
            try AchievementRecord.fetchAll(db)
        }
    }

    func isAchievementUnlocked(id: String) throws -> Bool {
        try dbPool.read { db in
            try AchievementRecord.fetchOne(db, key: id) != nil
        }
    }

    func unlockAchievement(id: String, triggerValue: String?) throws {
        let record = AchievementRecord(
            id: id,
            unlockedAt: ISO8601DateFormatter().string(from: Date()),
            triggerValue: triggerValue
        )
        try dbPool.write { db in
            try record.insert(db)
        }
    }

    // MARK: - Daily Summary

    func saveDailySummary(date: String, statsJson: String, achievementsJson: String?) throws {
        try dbPool.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO daily_summary (date, stats_json, achievements_json)
                    VALUES (?, ?, ?)
                """,
                arguments: [date, statsJson, achievementsJson]
            )
        }
    }

    // MARK: - Helpers

    func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
