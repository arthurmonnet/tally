import SwiftUI

struct MenuBarView: View {
    var pushScheduler: PushScheduler
    @Environment(\.openWindow) private var openWindow
    @State private var stats: [String: (int: Int64, float: Double)] = [:]
    @State private var refreshTimer: Timer?

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

            // Stats grid
            statRow(icon: "keyboard", label: "keystrokes", key: "keystrokes")
            statRow(icon: "cursorarrow.click.2", label: "clicks", keys: ["clicks_left", "clicks_right"])
            statRow(icon: "doc.on.clipboard", label: "copy/paste", keys: ["copy", "paste"])
            statRow(icon: "camera.viewfinder", label: "screenshots", key: "screenshots")
            statRow(icon: "arrow.uturn.backward", label: "undos", key: "cmd_z")
            statRow(icon: "bolt.fill", label: "launcher opens", key: "launcher_opens")

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

    private var topApps: [(name: String, minutes: Int64)] {
        stats
            .filter { $0.key.hasPrefix("app_time:") }
            .map { (name: String($0.key.dropFirst("app_time:".count)), minutes: $0.value.int) }
            .sorted { $0.minutes > $1.minutes }
    }

    // MARK: - View Helpers

    private func statRow(icon: String, label: String, key: String) -> some View {
        let value = stats[key]?.int ?? 0
        return HStack {
            Image(systemName: icon)
                .frame(width: 16)
            Text(formatNumber(value))
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(icon: String, label: String, keys: [String]) -> some View {
        let value = keys.reduce(Int64(0)) { $0 + (stats[$1]?.int ?? 0) }
        return HStack {
            Image(systemName: icon)
                .frame(width: 16)
            Text(formatNumber(value))
                .font(.system(.body, design: .monospaced))
            Spacer()
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

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
