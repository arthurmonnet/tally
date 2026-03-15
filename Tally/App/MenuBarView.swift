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
    @State private var windowTimeline: [(time: String, value: Int64)] = []
    @State private var todayAchievementRecords: [AchievementRecord] = []
    @State private var animPhase: Bool = false

    private let statsEngine = StatsEngine()

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
            statsSection
            appsSection
            windowsSection
            achievementsSection
            footerRow
        }
        .frame(width: 320)
        .padding(.vertical, 12)
        .task {
            await loadStats()
        }
        .onAppear {
            animPhase = true
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
            .opacity(animPhase ? 1.0 : 0.6)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animPhase)
    }

    // MARK: - Stats Section (flat list, no headers)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandableRow(icon: "keyboard", label: "Keystrokes", keys: ["keystrokes"], historyKey: "keystrokes")
            expandableRow(icon: "cursorarrow.click.2", label: "Clicks", keys: ["clicks_left", "clicks_right"], historyKey: "clicks")
            expandableRow(icon: "doc.on.clipboard", label: "Copy / Paste", keys: ["copy", "paste"], historyKey: "copy_paste")
            expandableRow(icon: "arrow.uturn.backward", label: "Undos", keys: ["cmd_z"], historyKey: "undos")

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

            // Build stats merged into flat list
            let screenshots = stats["screenshots"]?.int ?? 0
            if screenshots > 0 {
                expandableRow(icon: "camera.viewfinder", label: "Screenshots", keys: ["screenshots"], historyKey: "screenshots")
            }

            let commits = stats["git_commits"]?.int ?? 0
            if commits > 0 {
                expandableRow(icon: "point.3.connected.trianglepath.dotted", label: "Commits", keys: ["git_commits"], historyKey: "commits")
            }

            let stashes = stats["git_stashes"]?.int ?? 0
            if stashes > 0 {
                StatRow(icon: "tray.and.arrow.down", label: "Stashes", value: formatNumber(stashes))
            }
        }
    }

    // MARK: - APPS Section

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "APPS")

            let apps = topApps
            let bundles = bundleMap
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
                        proportion: proportion,
                        icon: AppIconCache.shared.icon(for: app.name, bundleID: bundles[app.name])
                    )
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - WINDOWS Section

    @ViewBuilder
    private var windowsSection: some View {
        if windowCount > 0 || !windowTimeline.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "WINDOWS")
                WindowChart(
                    points: windowTimeline,
                    current: windowCount,
                    peak: windowPeak
                )
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
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "tally-api-settings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
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

    // MARK: - Data

    private func loadStats() async {
        do {
            stats = try Database.shared.todayStats()

            let todayDate = Database.shared.todayDateString()
            let todayPrefix = todayDate + "T00:00:00"
            windowCount = try Database.shared.latestValue(statKey: "window_count", since: todayPrefix)
            windowPeak = try Database.shared.peakValue(statKey: "window_count", since: todayPrefix)
            windowTimeline = try Database.shared.timelineBuckets(statKey: "window_count", date: todayDate)
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
