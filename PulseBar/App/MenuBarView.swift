import SwiftUI

struct MenuBarView: View {
    var pushScheduler: PushScheduler
    @Environment(\.openWindow) private var openWindow
    @State private var stats: [String: (int: Int64, float: Double)] = [:]
    @State private var refreshTimer: Timer?
    @State private var expandedStat: String?
    @State private var historyCache: [String: StatHistory] = [:]
    @State private var windowCount: Int64 = 0
    @State private var windowPeak: Int64 = 0
    @State private var todayAchievementRecords: [AchievementRecord] = []
    @State private var pulsePhase: Bool = false

    private let statsEngine = StatsEngine()
    private let expandableStats: Set<String> = ["keystrokes", "copy_paste", "scroll", "mouse_travel"]

    private static let achievementDefs: [AchievementDefinition] = {
        guard let url = Bundle.main.url(forResource: "achievements", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let defs = try? JSONDecoder().decode([AchievementDefinition].self, from: data) else {
            return []
        }
        return defs
    }()

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let isoFormatter = ISO8601DateFormatter()

    private static let dayInitialFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private static let dateParsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            inputSection
            appsSection
            buildSection
            achievementsSection
            footerRow
        }
        .frame(width: 320)
        .padding(.vertical, 12)
        .task {
            await loadStats()
        }
        .onAppear {
            pulsePhase = true
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
                Task { @MainActor in
                    await loadStats()
                }
            }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Text("Today")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(todayFormatted)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            liveIndicator
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var liveIndicator: some View {
        Circle()
            .fill(accessibilityGranted ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
            .opacity(pulsePhase ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulsePhase)
    }

    // MARK: - INPUT Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "INPUT")

            expandableRow(icon: "keyboard", label: "Keystrokes", keys: ["keystrokes"], historyKey: "keystrokes")
            staticRow(icon: "cursorarrow.click.2", label: "Clicks", keys: ["clicks_left", "clicks_right"])
            expandableRow(icon: "doc.on.clipboard", label: "Copy / Paste", keys: ["copy", "paste"], historyKey: "copy_paste")
            staticRow(icon: "arrow.uturn.backward", label: "Undos", keys: ["cmd_z"])

            if let scrollM = stats["scroll_distance_m"]?.float, scrollM > 0 {
                expandableRow(
                    icon: "arrow.up.arrow.down",
                    label: "Scroll",
                    displayValue: formatDistance(scrollM),
                    keys: ["scroll_distance_m"],
                    historyKey: "scroll"
                )
            }

            if let mouseM = stats["mouse_distance_m"]?.float, mouseM > 0 {
                expandableRow(
                    icon: "computermouse",
                    label: "Mouse travel",
                    displayValue: formatDistance(mouseM),
                    keys: ["mouse_distance_m"],
                    historyKey: "mouse_travel"
                )
            }
        }
    }

    // MARK: - APPS Section

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "APPS")

            let apps = topApps
            if apps.isEmpty {
                Text("No app data yet")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            } else {
                let maxMinutes = apps.first?.minutes ?? 1
                ForEach(Array(apps.prefix(5).enumerated()), id: \.offset) { _, app in
                    let proportion = maxMinutes > 0 ? Double(app.minutes) / Double(maxMinutes) : 0
                    AppBar(
                        name: app.name,
                        time: formatDuration(minutes: Int(app.minutes)),
                        proportion: proportion
                    )
                    .padding(.vertical, 4)
                }
            }

            // Window count line
            if windowCount > 0 {
                let windowText: String = {
                    if windowPeak <= windowCount {
                        return "\(formatNumber(windowCount)) windows open (peak)"
                    }
                    return "\(formatNumber(windowCount)) windows open \u{00B7} peak \(formatNumber(windowPeak))"
                }()
                Text(windowText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - BUILD Section

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            let commits = stats["git_commits"]?.int ?? 0
            let stashes = stats["git_stashes"]?.int ?? 0
            let screenshots = stats["screenshots"]?.int ?? 0
            let totalFilesCreated = filesCreatedByExtension.values.reduce(Int64(0), +)

            if commits > 0 || stashes > 0 || screenshots > 0 || totalFilesCreated > 0 {
                SectionHeader(title: "BUILD")

                if commits > 0 {
                    StatRow(icon: "point.3.connected.trianglepath.dotted", label: "Commits", value: formatNumber(commits))
                }
                if stashes > 0 {
                    StatRow(icon: "tray.and.arrow.down", label: "Stashes", value: formatNumber(stashes))
                }
                if screenshots > 0 {
                    StatRow(icon: "camera.viewfinder", label: "Screenshots", value: formatNumber(screenshots))
                }
                if totalFilesCreated > 0 {
                    StatRow(icon: "doc.badge.plus", label: "Files created", value: formatNumber(totalFilesCreated))
                    // File extension breakdown (top 3)
                    let topExtensions = filesCreatedByExtension
                        .sorted { $0.value > $1.value }
                        .prefix(3)
                        .map { ".\($0.key) \($0.value)" }
                        .joined(separator: " \u{00B7} ")
                    if !topExtensions.isEmpty {
                        Text(topExtensions)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 32)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Achievements Section

    @ViewBuilder
    private var achievementsSection: some View {
        if !todayUnlockedAchievements.isEmpty {
            VStack(spacing: 4) {
                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                HStack(spacing: 12) {
                    Spacer()
                    ForEach(todayUnlockedAchievements, id: \.id) { achievement in
                        let isRecent = isRecentlyUnlocked(achievement)
                        Text("\(achievement.icon) \(achievement.name)")
                            .font(.system(size: 10))
                            .foregroundStyle(isRecent ? .primary : .secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)
            HStack {
                Button("Open Dashboard") {
                    if let url = URL(string: "http://localhost:7777") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))

                Spacer()

                Button("Settings") {
                    openWindow(id: "pulse-api-settings")
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func expandableRow(
        icon: String,
        label: String,
        displayValue: String? = nil,
        keys: [String],
        historyKey: String
    ) -> some View {
        let value = displayValue ?? formatNumber(keys.reduce(Int64(0)) { $0 + (stats[$1]?.int ?? 0) })
        let isExpanded = expandedStat == historyKey

        VStack(spacing: 0) {
            StatRow(
                icon: icon,
                label: label,
                value: value,
                expandable: true,
                isExpanded: isExpanded
            ) {
                withAnimation(.easeOut(duration: 0.2)) {
                    if expandedStat == historyKey {
                        expandedStat = nil
                    } else {
                        expandedStat = historyKey
                        loadHistory(for: keys, historyKey: historyKey)
                    }
                }
            }

            if isExpanded, let history = historyCache[historyKey] {
                SparklineChart(history: history)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func staticRow(icon: String, label: String, keys: [String]) -> some View {
        let value = keys.reduce(Int64(0)) { $0 + (stats[$1]?.int ?? 0) }
        return StatRow(icon: icon, label: label, value: formatNumber(value))
    }

    // MARK: - Data

    private func loadStats() async {
        do {
            stats = try Database.shared.todayStats()

            let todayPrefix = Database.shared.todayDateString() + "T00:00:00"
            windowCount = try Database.shared.latestValue(statKey: "window_count", since: todayPrefix)
            windowPeak = try Database.shared.peakValue(statKey: "window_count", since: todayPrefix)
            todayAchievementRecords = try Database.shared.todayAchievements()
        } catch {
            print("[MenuBarView] Failed to load stats: \(error)")
        }
    }

    private var bundleMap: [String: String] {
        var map: [String: String] = [:]
        for key in stats.keys where key.hasPrefix("app_bundle:") {
            let rest = String(key.dropFirst("app_bundle:".count))
            if let colonIdx = rest.lastIndex(of: ":") {
                let name = String(rest[rest.startIndex..<colonIdx])
                let bundleID = String(rest[rest.index(after: colonIdx)...])
                map[name] = bundleID
            }
        }
        return map
    }

    private var topApps: [(name: String, minutes: Int64)] {
        let bundles = bundleMap
        return stats
            .filter { $0.key.hasPrefix("app_time:") }
            .map { (name: String($0.key.dropFirst("app_time:".count)), minutes: $0.value.int / 60) }
            .filter { AppFilter.shouldDisplay(name: $0.name, bundleID: bundles[$0.name]) }
            .filter { $0.minutes > 0 }
            .sorted { $0.minutes > $1.minutes }
    }

    private static let ignoredExtensions: Set<String> = [
        "ds_store", "localized", "swp", "tmp", "lock", "log",
    ]

    private var filesCreatedByExtension: [String: Int64] {
        stats
            .filter { $0.key.hasPrefix("files_created:") }
            .reduce(into: [String: Int64]()) { result, entry in
                let ext = String(entry.key.dropFirst("files_created:".count))
                // Filter invalid/noisy extensions
                guard !ext.isEmpty,
                      ext.count <= 10,
                      ext.allSatisfy({ $0.isLetter || $0.isNumber }),
                      !Self.ignoredExtensions.contains(ext) else { return }
                result[ext, default: 0] += entry.value.int
            }
    }

    // MARK: - Achievement Helpers

    private var todayUnlockedAchievements: [AchievementDefinition] {
        let unlockedIDs = Set(todayAchievementRecords.map(\.id))
        return Self.achievementDefs.filter { unlockedIDs.contains($0.id) }
    }

    private func isRecentlyUnlocked(_ achievement: AchievementDefinition) -> Bool {
        guard let record = todayAchievementRecords.first(where: { $0.id == achievement.id }) else {
            return false
        }
        guard let unlockedDate = Self.isoFormatter.date(from: record.unlockedAt) else {
            return false
        }
        return Date().timeIntervalSince(unlockedDate) < 3600  // Within last hour
    }

    // MARK: - History

    private func loadHistory(for keys: [String], historyKey: String) {
        guard historyCache[historyKey] == nil else { return }
        Task {
            do {
                let history = try statsEngine.history(for: keys, days: 7)
                await MainActor.run {
                    historyCache[historyKey] = history
                }
            } catch {
                print("[MenuBarView] Failed to load history: \(error)")
            }
        }
    }

    // MARK: - Formatting

    private var todayFormatted: String {
        Self.dateFormatter.string(from: Date())
    }

    private func formatNumber(_ n: Int64) -> String {
        Self.numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return "\(Int(meters)) m"
    }

    private func formatDuration(minutes: Int) -> String {
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    // MARK: - System

    private var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }
}
