import SwiftUI

struct MenuBarView: View {
    var pushScheduler: PushScheduler
    @Environment(\.openWindow) private var openWindow
    @State private var stats: [String: (int: Int64, float: Double)] = [:]
    @State private var refreshTimer: Timer?
    @State private var expandedStat: String?
    @State private var historyCache: [String: StatHistory] = [:]

    private let statsEngine = StatsEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(todayFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Divider()

            // Stats grid with expandable rows
            expandableStatRow(icon: "keyboard", label: "keystrokes", key: "keystrokes")
            expandableStatRow(icon: "cursorarrow.click.2", label: "clicks", keys: ["clicks_left", "clicks_right"], historyKey: "clicks")
            expandableStatRow(icon: "doc.on.clipboard", label: "copy/paste", keys: ["copy", "paste"], historyKey: "copy_paste")
            expandableStatRow(icon: "camera.viewfinder", label: "screenshots", key: "screenshots")
            expandableStatRow(icon: "arrow.uturn.backward", label: "undos", key: "cmd_z")
            expandableStatRow(icon: "bolt.fill", label: "launcher opens", key: "launcher_opens")

            if let scrollM = stats["scroll_distance_m"]?.float, scrollM > 0 {
                HStack {
                    Image(systemName: "arrow.up.arrow.down")
                        .frame(width: 16)
                    Text(formatDistance(scrollM))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("scroll")
                        .foregroundStyle(.secondary)
                }
            }

            if let mouseM = stats["mouse_distance_m"]?.float, mouseM > 0 {
                HStack {
                    Image(systemName: "computermouse")
                        .frame(width: 16)
                    Text(formatDistance(mouseM))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("mouse travel")
                        .foregroundStyle(.secondary)
                }
            }

            // Window count row
            let windowCount = stats["window_count"]?.int ?? 0
            if windowCount > 0 {
                HStack {
                    Image(systemName: "macwindow.on.rectangle")
                        .frame(width: 16)
                    Text(formatNumber(windowCount))
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("windows open")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Top Apps
            Text("Top Apps")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(topApps.prefix(5), id: \.name) { app in
                HStack {
                    Text(app.name)
                        .lineLimit(1)
                    Spacer()
                    Text(formatMinutes(app.minutes))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            // Git section
            let commits = stats["git_commits"]?.int ?? 0
            let stashes = stats["git_stashes"]?.int ?? 0
            if commits > 0 || stashes > 0 {
                Divider()
                Text("Git")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(commits) commits \u{00B7} \(stashes) stashes")
                    .font(.system(.body, design: .monospaced))
            }

            Divider()

            // Footer
            HStack {
                Button("Open Dashboard") {
                    if let url = URL(string: "http://localhost:7777") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)

                Spacer()

                Button {
                    openWindow(id: "pulse-api-settings")
                } label: {
                    HStack(spacing: 4) {
                        pushStatusDot
                        Text("API")
                    }
                }
                .buttonStyle(.link)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(width: 280)
        .task {
            await loadStats()
        }
        .onAppear {
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

    // MARK: - Push Status

    @ViewBuilder
    private var pushStatusDot: some View {
        if pushScheduler.isEnabled {
            if let result = pushScheduler.lastPushResult {
                Circle()
                    .fill(result.success ? .green : .red)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(.gray)
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Data

    private func loadStats() async {
        do {
            stats = try Database.shared.todayStats()
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
            .map { (name: String($0.key.dropFirst("app_time:".count)), minutes: $0.value.int) }
            .filter { AppFilter.shouldDisplay(name: $0.name, bundleID: bundles[$0.name]) }
            .sorted { $0.minutes > $1.minutes }
    }

    // MARK: - Expandable Stat Rows

    @ViewBuilder
    private func expandableStatRow(icon: String, label: String, key: String) -> some View {
        expandableStatRow(icon: icon, label: label, keys: [key], historyKey: key)
    }

    @ViewBuilder
    private func expandableStatRow(icon: String, label: String, keys: [String], historyKey: String) -> some View {
        let value = keys.reduce(Int64(0)) { $0 + (stats[$1]?.int ?? 0) }
        let isExpanded = expandedStat == historyKey

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(formatNumber(value))
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text(label)
                    .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedStat == historyKey {
                        expandedStat = nil
                    } else {
                        expandedStat = historyKey
                        loadHistory(for: keys, historyKey: historyKey)
                    }
                }
            }

            if isExpanded, let history = historyCache[historyKey] {
                sparklineChart(history: history)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func sparklineChart(history: StatHistory) -> some View {
        let maxVal = history.days.map(\.value).max() ?? 1
        let effectiveMax = max(maxVal, 1)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(history.days.enumerated()), id: \.offset) { index, day in
                    let isToday = index == history.days.count - 1
                    let height = CGFloat(day.value) / CGFloat(effectiveMax) * 32
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isToday ? Color.white.opacity(0.6) : Color.white.opacity(0.2))
                        .frame(height: max(height, 2))
                }
            }
            .frame(height: 32)

            Text("avg: \(formatNumber(Int64(history.average)))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

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

    // MARK: - View Helpers

    private var todayFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: Date())
    }

    private func formatNumber(_ n: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatMinutes(_ minutes: Int64) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return "\(h)h \(m)m"
        }
        return "\(minutes)m"
    }
}
