import SwiftUI
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "MenuBarView")

struct MenuBarView: View {
    var pushScheduler: PushScheduler
    var liveStats: LiveStats
    var punchline: PunchlineGenerator
    @ObservedObject var updateController: UpdateController
    @Environment(\.openWindow) private var openWindow
    @State private var stats: [String: (int: Int64, float: Double)] = [:]
    @State private var refreshTimer: Timer?
    @State private var expandedStat: String?
    @State private var historyCache: [String: StatHistory] = [:]
    @State private var windowCount: Int64 = 0
    @State private var windowPeak: Int64 = 0
    @State private var windowTimeline: [(time: String, value: Int64)] = []
    @State private var peakRamGb: Double = 0
    @State private var animPhase: Bool = false

    private let statsEngine = StatsEngine()

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

    private static let appleIntelligenceGradient = LinearGradient(
        colors: [
            Color(red: 0.20, green: 0.50, blue: 0.95),
            Color(red: 0.45, green: 0.30, blue: 0.90),
            Color(red: 0.85, green: 0.25, blue: 0.40),
            Color(red: 0.92, green: 0.45, blue: 0.15),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

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
            punchlineSection
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
            // Real-time stats from LiveStats (instant CGEventTap updates)
            expandableRow(icon: "keyboard", label: "Keystrokes", liveValue: liveStats.keystrokes, keys: ["keystrokes"], historyKey: "keystrokes")
            expandableRow(icon: "cursorarrow.click.2", label: "Clicks", liveValue: liveStats.clicksLeft + liveStats.clicksRight, keys: ["clicks_left", "clicks_right"], historyKey: "clicks")
            expandableRow(icon: "doc.on.clipboard", label: "Copy / Paste", liveValue: liveStats.copy + liveStats.paste, keys: ["copy", "paste"], historyKey: "copy_paste")
            expandableRow(icon: "arrow.uturn.backward", label: "Undos", liveValue: liveStats.cmdZ, keys: ["cmd_z"], historyKey: "undos")

            if liveStats.scrollDistanceM > 0 {
                expandableRow(
                    icon: "arrow.up.arrow.down",
                    label: "Scroll",
                    displayValue: formatDistance(liveStats.scrollDistanceM),
                    keys: ["scroll_distance_m"],
                    historyKey: "scroll"
                )
            }

            if liveStats.mouseDistanceM > 0 {
                expandableRow(
                    icon: "computermouse",
                    label: "Mouse travel",
                    displayValue: formatDistance(liveStats.mouseDistanceM),
                    keys: ["mouse_distance_m"],
                    historyKey: "mouse_travel"
                )
            }

            // Real-time file event stats
            if liveStats.screenshots > 0 {
                expandableRow(icon: "camera.viewfinder", label: "Screenshots", liveValue: liveStats.screenshots, keys: ["screenshots"], historyKey: "screenshots")
            }

            // Polled stats (from DB, updated on timer)
            let appSwitches = stats["app_switches"]?.int ?? 0
            if appSwitches > 0 {
                StatRow(icon: "arrow.triangle.swap", label: "App switches", value: formatNumber(appSwitches))
            }

            let darkM = stats["dark_mode_m"]?.int ?? 0
            let lightM = stats["light_mode_m"]?.int ?? 0
            if darkM > 0 || lightM > 0 {
                StatRow(icon: "circle.lefthalf.filled", label: "Dark mode", value: formatDuration(minutes: Int(darkM)))
            }

            // Peak RAM hidden until stale summed values flush out
            // if peakRamGb > 0 {
            //     StatRow(icon: "memorychip", label: "Peak RAM", value: String(format: "%.1f GB", peakRamGb))
            // }
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
                ForEach(apps.prefix(5), id: \.name) { app in
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


    // MARK: - Punchline Section

    @ViewBuilder
    private var punchlineSection: some View {
        if let line = punchline.currentLine {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(line)
                    .font(.system(size: 11))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Self.appleIntelligenceGradient)
                HStack(spacing: 3) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 8))
                    Text("Apple Intelligence")
                        .font(.system(size: 9))
                }
                .foregroundStyle(Self.appleIntelligenceGradient)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    // MARK: - Footer

    private var footerRow: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)
                .padding(.top, 8)
            HStack {
                Spacer()

                Button {
                    updateController.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!updateController.canCheckForUpdates)
                .help("Check for Updates")

                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "tally-api-settings")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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
        liveValue: Int64? = nil,
        displayValue: String? = nil,
        keys: [String],
        historyKey: String
    ) -> some View {
        let value = displayValue ?? formatNumber(liveValue ?? keys.reduce(Int64(0)) { $0 + (stats[$1]?.int ?? 0) })
        let isExpanded = expandedStat == historyKey

        VStack(spacing: 0) {
            StatRow(
                icon: icon,
                label: label,
                value: value,
                expandable: true,
                isExpanded: isExpanded
            ) {
                if expandedStat == historyKey {
                    withAnimation(.easeOut(duration: 0.2)) {
                        expandedStat = nil
                    }
                } else {
                    loadHistory(for: keys, historyKey: historyKey) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            expandedStat = historyKey
                        }
                    }
                }
            }

            if isExpanded, let history = historyCache[historyKey] {
                SparklineChart(history: history)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .transition(.opacity)
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
            peakRamGb = try Database.shared.peakFloat(statKey: "peak_ram_gb", since: todayPrefix)
            let dailyStats = try statsEngine.todayStats()
            punchline.maybeRegenerate(stats: dailyStats)
        } catch {
            logger.error("Failed to load stats: \(error)")
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
            .sorted { $0.minutes != $1.minutes ? $0.minutes > $1.minutes : $0.name < $1.name }
    }

    // MARK: - History

    private func loadHistory(for keys: [String], historyKey: String, then completion: @escaping () -> Void) {
        if historyCache[historyKey] != nil {
            completion()
            return
        }
        Task {
            do {
                let history = try statsEngine.history(for: keys, days: 7)
                await MainActor.run {
                    historyCache[historyKey] = history
                    completion()
                }
            } catch {
                logger.error("Failed to load history: \(error)")
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
