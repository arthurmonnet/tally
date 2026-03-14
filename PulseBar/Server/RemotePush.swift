import Foundation

struct PushResult: Sendable {
    let success: Bool
    let timestamp: Date
    let errorMessage: String?
    let httpStatusCode: Int?

    static func ok() -> PushResult {
        PushResult(success: true, timestamp: Date(), errorMessage: nil, httpStatusCode: 200)
    }

    static func failure(_ message: String, statusCode: Int? = nil) -> PushResult {
        PushResult(success: false, timestamp: Date(), errorMessage: message, httpStatusCode: statusCode)
    }

    var timeAgoString: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

enum ConnectionResult {
    case success
    case error(String)
}

struct RemotePush: Sendable {
    private let statsEngine = StatsEngine()

    // MARK: - URL Normalization

    static func normalizeURL(_ input: String) -> String {
        var url = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        if url.hasSuffix("/api/pulse") {
            url = String(url.dropLast("/api/pulse".count))
        }
        return url
    }

    // MARK: - Test Connection

    func testConnection(url: String, token: String) async -> ConnectionResult {
        let baseURL = Self.normalizeURL(url)
        guard let endpoint = URL(string: baseURL + "/api/pulse") else {
            return .error("Invalid URL")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{\"test\":true}".data(using: .utf8)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch status {
            case 200...299: return .success
            case 401: return .error("Wrong token. Check that it matches your Vercel env var.")
            case 404: return .error("Endpoint not found. Make sure the URL is correct.")
            default: return .error("Unexpected response: \(status)")
            }
        } catch {
            return .error("Can't reach the server. Is the URL correct?")
        }
    }

    // MARK: - Push

    func pushDailySummary(url: String, token: String) async -> PushResult {
        // Normalize and build endpoint URL
        let baseURL = Self.normalizeURL(url)
        guard let endpoint = URL(string: baseURL + "/api/pulse"),
              let scheme = endpoint.scheme?.lowercased(),
              let host = endpoint.host?.lowercased() else {
            return .failure("Invalid URL")
        }

        // Require HTTPS (except localhost for development)
        let isLocalhost = host == "localhost" || host == "127.0.0.1"
        if scheme != "https" && !isLocalhost {
            return .failure("HTTPS is required (except for localhost)")
        }

        // Build payload
        let payload: RemotePushPayload
        do {
            payload = try buildPayload()
        } catch {
            return .failure("Failed to build stats: \(error.localizedDescription)")
        }

        let body: Data
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            body = try encoder.encode(payload)
        } catch {
            return .failure("Failed to encode payload: \(error.localizedDescription)")
        }

        // Attempt push with one retry
        for attempt in 1...2 {
            let result = await sendRequest(endpoint: endpoint, token: token, body: body)
            if result.success {
                return result
            }

            if attempt == 1 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            } else {
                return result
            }
        }

        return .failure("Push failed after retry")
    }

    private func sendRequest(endpoint: URL, token: String, body: Data) async -> PushResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("Invalid server response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                return .ok()
            }

            return .failure("Server returned \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func buildPayload() throws -> RemotePushPayload {
        let stats = try statsEngine.todayStats()
        let funLine = try statsEngine.generateFunLine()
        let db = Database.shared
        let achievements = try db.unlockedAchievements()
        let todayAchievements = achievements
            .filter { $0.unlockedAt.hasPrefix(db.todayDateString()) }
            .map(\.id)

        // Window stats from timeline
        let windowBuckets = try db.timelineBuckets(statKey: "window_count", date: db.todayDateString())
        let windowValues = windowBuckets.map(\.value)
        let peakWindows = windowValues.max() ?? 0
        let avgWindows = windowValues.isEmpty ? Int64(0) : windowValues.reduce(0, +) / Int64(windowValues.count)

        // 7-day history for major stats
        let history = try buildHistory()

        return RemotePushPayload(
            version: 2,
            date: db.todayDateString(),
            keystrokes: stats.keystrokes,
            clicks: stats.clicksLeft + stats.clicksRight,
            copyPaste: stats.copy + stats.paste,
            screenshots: stats.screenshots,
            cmdZ: stats.cmdZ,
            launcherOpens: stats.launcherOpens,
            appSwitches: stats.appSwitches,
            scrollDistanceM: stats.scrollDistanceM,
            mouseDistanceM: stats.mouseDistanceM,
            darkModeMinutes: stats.darkModeM,
            lightModeMinutes: stats.lightModeM,
            topApps: stats.topApps,
            filesCreated: stats.filesCreated,
            filesDeleted: stats.filesDeleted,
            gitCommits: stats.gitCommits,
            gitStashes: stats.gitStashes,
            peakRamGb: stats.peakRamGb,
            activeHours: Double(stats.keystrokes > 0 ? 8 : 0),
            achievementsUnlocked: todayAchievements,
            funLine: funLine,
            peakWindows: peakWindows,
            avgWindows: avgWindows,
            history: history
        )
    }

    private func buildHistory() throws -> PushHistory? {
        let engine = statsEngine

        let keystrokesH = try engine.history(for: "keystrokes", days: 7)
        let clicksH = try engine.history(for: ["clicks_left", "clicks_right"], days: 7)
        let screenshotsH = try engine.history(for: "screenshots", days: 7)
        let copyPasteH = try engine.history(for: ["copy", "paste"], days: 7)
        let gitCommitsH = try engine.history(for: "git_commits", days: 7)

        return PushHistory(
            keystrokes: keystrokesH.days.map(\.value),
            clicks: clicksH.days.map(\.value),
            screenshots: screenshotsH.days.map(\.value),
            copyPaste: copyPasteH.days.map(\.value),
            gitCommits: gitCommitsH.days.map(\.value)
        )
    }
}

struct RemotePushPayload: Codable, Sendable {
    let version: Int
    let date: String
    let keystrokes: Int64
    let clicks: Int64
    let copyPaste: Int64
    let screenshots: Int64
    let cmdZ: Int64
    let launcherOpens: Int64
    let appSwitches: Int64
    let scrollDistanceM: Double
    let mouseDistanceM: Double
    let darkModeMinutes: Int64
    let lightModeMinutes: Int64
    let topApps: [AppTimeEntry]
    let filesCreated: [String: Int64]
    let filesDeleted: Int64
    let gitCommits: Int64
    let gitStashes: Int64
    let peakRamGb: Double
    let activeHours: Double
    let achievementsUnlocked: [String]
    let funLine: String
    let peakWindows: Int64
    let avgWindows: Int64
    let history: PushHistory?

    enum CodingKeys: String, CodingKey {
        case version, date, keystrokes, clicks, screenshots
        case copyPaste = "copy_paste"
        case cmdZ = "cmd_z"
        case launcherOpens = "launcher_opens"
        case appSwitches = "app_switches"
        case scrollDistanceM = "scroll_distance_m"
        case mouseDistanceM = "mouse_distance_m"
        case darkModeMinutes = "dark_mode_minutes"
        case lightModeMinutes = "light_mode_minutes"
        case topApps = "top_apps"
        case filesCreated = "files_created"
        case filesDeleted = "files_deleted"
        case gitCommits = "git_commits"
        case gitStashes = "git_stashes"
        case peakRamGb = "peak_ram_gb"
        case activeHours = "active_hours"
        case achievementsUnlocked = "achievements_unlocked"
        case funLine = "fun_line"
        case peakWindows = "peak_windows"
        case avgWindows = "avg_windows"
        case history
    }
}

struct PushHistory: Codable, Sendable {
    let keystrokes: [Int64]
    let clicks: [Int64]
    let screenshots: [Int64]
    let copyPaste: [Int64]
    let gitCommits: [Int64]

    enum CodingKeys: String, CodingKey {
        case keystrokes, clicks, screenshots
        case copyPaste = "copy_paste"
        case gitCommits = "git_commits"
    }
}
