import Foundation
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "PunchlineGenerator")

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
@Observable
final class PunchlineGenerator {
    var currentLine: String?

    private var lastStats: DailyStats?
    private var lastGeneratedAt: Date?
    private var isGenerating = false

    private let cooldown: TimeInterval = 3600
    private let changeThreshold: Double = 0.2

    func maybeRegenerate(stats: DailyStats) {
        guard !isGenerating else { return }
        guard shouldRegenerate(stats: stats) else { return }

        isGenerating = true

        Task {
            let line = await generate(stats: stats)
            if let line {
                self.currentLine = line
            }
            self.lastStats = stats
            self.lastGeneratedAt = Date()
            self.isGenerating = false
        }
    }

    private func shouldRegenerate(stats: DailyStats) -> Bool {
        if currentLine == nil { return true }

        if let lastTime = lastGeneratedAt,
           Date().timeIntervalSince(lastTime) < cooldown {
            return false
        }

        if let last = lastStats {
            let delta = abs(stats.keystrokes - last.keystrokes)
            let threshold = max(Double(last.keystrokes) * changeThreshold, 500)
            return Double(delta) > threshold
        }

        return true
    }

    private func generate(stats: DailyStats) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return nil }

        guard case .available = SystemLanguageModel.default.availability else {
            logger.info("Model not available")
            return nil
        }

        let prompt = buildPrompt(stats: stats)

        do {
            let session = LanguageModelSession()
            let fullPrompt = instructions + "\n\n" + prompt
            let response = try await session.respond(to: fullPrompt)
            let raw = response.content
            logger.debug("Raw response: \(raw)")
            let line = raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            guard !line.isEmpty, line.count < 150 else {
                logger.warning("Rejected: empty or too long (\(line.count) chars)")
                return nil
            }
            return line
        } catch {
            logger.error("Failed: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private let instructions = """
        You write snarky commentary for a developer activity tracker. \
        Given today's stats, write ONE witty observation. Rules:

        - 10 to 25 words
        - Pick ONE interesting stat or ratio to riff on — never list multiple numbers
        - Dry, sarcastic developer humor — like a coworker roasting your day
        - Lowercase, no period at the end
        - No emoji, no hashtags, no quotes around the line
        - Be specific and creative, not generic
        - Never motivational, never mean — just wry

        Bad: "28m of scrolling, 44m of mouse travel, and still no bug found"
        Bad: "1,200 keystrokes, 45 undos, 12 screenshots — busy day"
        Good: "mass-producing code or undo'ing it — hard to tell"
        Good: "scrolled past 3 football fields looking for that one function"
        Good: "the clipboard did most of the heavy lifting today"

        Write the line and nothing else.
        """

    private func buildPrompt(stats: DailyStats) -> String {
        // Context
        let hour = Calendar.current.component(.hour, from: Date())
        let weekday = Calendar.current.component(.weekday, from: Date())
        let dayNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let timeOfDay: String
        switch hour {
        case 0..<6: timeOfDay = "late night"
        case 6..<12: timeOfDay = "morning"
        case 12..<14: timeOfDay = "lunchtime"
        case 14..<18: timeOfDay = "afternoon"
        case 18..<22: timeOfDay = "evening"
        default: timeOfDay = "late night"
        }

        var context = "It's \(dayNames[weekday]) \(timeOfDay)."
        if let weather = currentWeatherDescription() {
            context += " Weather: \(weather)."
        }

        // Stats
        var lines: [String] = []
        lines.append("- \(stats.keystrokes) keystrokes")
        lines.append("- \(stats.clicksLeft + stats.clicksRight) clicks")
        lines.append("- \(stats.copy + stats.paste) copy/paste")
        lines.append("- \(stats.cmdZ) undos")
        lines.append("- \(stats.screenshots) screenshots")
        lines.append("- \(stats.appSwitches) app switches")

        if let top = stats.topApps.first {
            lines.append("- Top app: \(top.name) (\(top.minutes)min)")
        }
        if stats.scrollDistanceM > 10 {
            lines.append("- Scroll distance: \(Int(stats.scrollDistanceM))m")
        }
        if stats.mouseDistanceM > 10 {
            lines.append("- Mouse travel: \(Int(stats.mouseDistanceM))m")
        }
        if stats.launcherOpens > 0 {
            lines.append("- \(stats.launcherOpens) launcher opens")
        }

        return "\(context)\n\nToday's stats:\n" + lines.joined(separator: "\n")
    }

    private nonisolated func currentWeatherDescription() -> String? {
        // WeatherKit via WeatherService requires no extra permissions for basic current weather
        #if canImport(WeatherKit)
        return nil // WeatherKit needs async + location — skip for now
        #else
        return nil
        #endif
    }
}
