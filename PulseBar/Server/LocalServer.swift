import Foundation
import Swifter

@MainActor
final class LocalServer {
    private var server: HttpServer?
    private let statsEngine = StatsEngine()

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
