import Foundation
import UserNotifications

@MainActor
final class AchievementEngine {
    private var checkTimer: Timer?
    private var definitions: [AchievementDefinition] = []

    private let db = Database.shared
    private let statsEngine = StatsEngine()

    func start() {
        loadDefinitions()

        // Check every 60 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                self.checkAchievements()
            }
        }

        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        print("[AchievementEngine] Started with \(definitions.count) definitions")
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
        print("[AchievementEngine] Stopped")
    }

    private func loadDefinitions() {
        guard let url = Bundle.main.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("[AchievementEngine] No achievements.json found in bundle")
            return
        }

        do {
            definitions = try JSONDecoder().decode([AchievementDefinition].self, from: data)
        } catch {
            print("[AchievementEngine] Failed to decode achievements: \(error)")
        }
    }

    private func checkAchievements() {
        do {
            let stats = try statsEngine.todayStats()

            for definition in definitions {
                guard !(try db.isAchievementUnlocked(id: definition.id)) else { continue }

                if checkCondition(definition.condition, stats: stats) {
                    try db.unlockAchievement(
                        id: definition.id,
                        triggerValue: conditionTriggerValue(definition.condition, stats: stats)
                    )
                    sendNotification(for: definition)
                    print("[AchievementEngine] Unlocked: \(definition.name)")
                }
            }
        } catch {
            print("[AchievementEngine] Error checking: \(error)")
        }
    }

    private func checkCondition(_ condition: AchievementCondition, stats: DailyStats) -> Bool {
        // Simple threshold check
        if let stat = condition.stat, let threshold = condition.threshold {
            let value = statValue(stat, stats: stats)
            guard value >= threshold else { return false }

            // Check "also" condition if present
            if let also = condition.also {
                let alsoValue = statValue(also.stat, stats: stats)
                guard alsoValue <= Double(also.max) else { return false }
            }

            return true
        }

        // Stat comparison
        if let compare = condition.statCompare, compare.count == 3 {
            let leftValue = statValue(compare[0], stats: stats)
            let rightValue = statValue(compare[2], stats: stats)
            let op = compare[1]
            switch op {
            case ">": return leftValue > rightValue
            case "<": return leftValue < rightValue
            case ">=": return leftValue >= rightValue
            case "<=": return leftValue <= rightValue
            default: return false
            }
        }

        return false
    }

    private func statValue(_ key: String, stats: DailyStats) -> Double {
        switch key {
        case "keystrokes": return Double(stats.keystrokes)
        case "clicks_left": return Double(stats.clicksLeft)
        case "clicks_right": return Double(stats.clicksRight)
        case "copy": return Double(stats.copy)
        case "paste": return Double(stats.paste)
        case "cmd_z": return Double(stats.cmdZ)
        case "cmd_k": return Double(stats.cmdK)
        case "launcher_opens": return Double(stats.launcherOpens)
        case "scroll_distance_m": return stats.scrollDistanceM
        case "mouse_distance_m": return stats.mouseDistanceM
        case "app_switches": return Double(stats.appSwitches)
        case "screenshots": return Double(stats.screenshots)
        case "files_deleted": return Double(stats.filesDeleted)
        case "git_commits": return Double(stats.gitCommits)
        case "git_stashes": return Double(stats.gitStashes)
        case "dark_mode_m": return Double(stats.darkModeM)
        case "light_mode_m": return Double(stats.lightModeM)
        case "peak_ram_gb": return stats.peakRamGb
        case "sleep_wake_quick": return Double(stats.sleepWakeQuick)
        case "active_time_after_midnight_m", "active_after_midnight_m": return Double(stats.activeAfterMidnightM)
        case "files_created_total":
            return Double(stats.filesCreated.values.reduce(0, +))
        default:
            // Handle files_created:ext
            if key.hasPrefix("files_created:") {
                let ext = String(key.dropFirst("files_created:".count))
                return Double(stats.filesCreated[ext] ?? 0)
            }
            return 0
        }
    }

    private func conditionTriggerValue(_ condition: AchievementCondition, stats: DailyStats) -> String? {
        if let stat = condition.stat {
            let value = statValue(stat, stats: stats)
            return String(format: "%.0f", value)
        }
        return nil
    }

    private func sendNotification(for achievement: AchievementDefinition) {
        let content = UNMutableNotificationContent()
        content.title = "\(achievement.icon) \(achievement.name)"
        content.body = achievement.description
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "achievement_\(achievement.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
