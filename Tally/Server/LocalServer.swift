import Foundation
import Swifter

@MainActor
final class LocalServer {
    private var server: HttpServer?
    private let statsEngine = StatsEngine()

    // Compound stat key mappings
    private let compoundStats: [String: [String]] = [
        "clicks": ["clicks_left", "clicks_right"],
        "copy_paste": ["copy", "paste"],
    ]

    func start() {
        let server = HttpServer()

        // Serve dashboard
        server["/"] = { [weak self] _ in
            guard self != nil else { return .internalServerError }
            guard let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") else {
                return .notFound
            }
            guard let html = try? String(contentsOf: htmlURL, encoding: .utf8) else {
                return .internalServerError
            }
            return .ok(.html(html))
        }

        // API: today's stats
        server["/api/today"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            do {
                let json = try self.statsEngine.todayStatsJSON()
                return .ok(.text(json))
            } catch {
                return .internalServerError
            }
        }

        // API: history
        server["/api/history"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            do {
                let json = try self.statsEngine.historyJSON()
                return .ok(.text(json))
            } catch {
                return .internalServerError
            }
        }

        // API: achievements
        server["/api/achievements"] = { [weak self] _ in
            guard let self else { return .internalServerError }
            do {
                let json = try self.statsEngine.achievementsJSON()
                return .ok(.text(json))
            } catch {
                return .internalServerError
            }
        }

        // API: stat history (e.g., /api/stat/keystrokes/history?days=14)
        server["/api/stat/:key/history"] = { [weak self] request in
            guard let self else { return .internalServerError }
            let statKey = request.params[":key"] ?? ""
            let daysParam = request.queryParams.first(where: { $0.0 == "days" })?.1
            let days = Int(daysParam ?? "") ?? 14

            // Resolve compound keys
            let keys = self.compoundStats[statKey] ?? [statKey]

            do {
                let history = try self.statsEngine.history(for: keys, days: days)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(history)
                let json = String(data: data, encoding: .utf8) ?? "{}"
                return .ok(.text(json))
            } catch {
                return .internalServerError
            }
        }

        // API: window count timeline (e.g., /api/stat/window_count/timeline?date=2026-03-14)
        server["/api/stat/window_count/timeline"] = { [weak self] request in
            guard self != nil else { return .internalServerError }
            let dateParam = request.queryParams.first(where: { $0.0 == "date" })?.1
            let date = dateParam ?? Database.shared.todayDateString()

            do {
                let buckets = try Database.shared.timelineBuckets(statKey: "window_count", date: date)

                let values = buckets.map(\.value)
                let avg = values.isEmpty ? 0 : Int64(values.reduce(0, +)) / Int64(values.count)
                var peakTime = ""
                var peakValue: Int64 = 0
                var minTime = ""
                var minValue: Int64 = Int64.max
                for b in buckets {
                    if b.value > peakValue { peakValue = b.value; peakTime = b.time }
                    if b.value < minValue { minValue = b.value; minTime = b.time }
                }
                if buckets.isEmpty { minValue = 0 }
                let current = buckets.last?.value ?? 0

                let response: [String: Any] = [
                    "stat": "window_count",
                    "date": date,
                    "resolution_minutes": 5,
                    "points": buckets.map { ["time": $0.time, "value": $0.value] },
                    "summary": [
                        "average": avg,
                        "peak": ["time": peakTime, "value": peakValue] as [String: Any],
                        "min": ["time": minTime, "value": minValue] as [String: Any],
                        "current": current
                    ] as [String: Any]
                ]

                let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
                let json = String(data: data, encoding: .utf8) ?? "{}"
                return .ok(.text(json))
            } catch {
                return .internalServerError
            }
        }

        do {
            try server.start(7777, forceIPv4: true)
            self.server = server
            print("[LocalServer] Started on http://localhost:7777")
        } catch {
            print("[LocalServer] Failed to start: \(error)")
        }
    }

    func stop() {
        server?.stop()
        server = nil
        print("[LocalServer] Stopped")
    }
}
