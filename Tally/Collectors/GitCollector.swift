import Foundation

@MainActor
final class GitCollector {
    private var pollTimer: Timer?
    private var gitRepos: [String] = []
    private var lastStashCounts: [String: Int] = [:]

    private let db = Database.shared

    func configure(repos: [String]) {
        gitRepos = repos.map { NSString(string: $0).expandingTildeInPath }
    }

    func start() {
        guard !gitRepos.isEmpty else {
            print("[GitCollector] No repos configured")
            return
        }

        // Poll every 5 minutes
        pollTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }

        // Initial poll
        poll()
        print("[GitCollector] Started tracking \(gitRepos.count) repos")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        print("[GitCollector] Stopped")
    }

    private func poll() {
        var totalCommits: Int64 = 0
        var totalStashDelta: Int64 = 0

        for repo in gitRepos {
            guard FileManager.default.fileExists(atPath: repo) else { continue }

            // Today's commits
            let commitOutput = shell("git -C '\(repo)' log --since=midnight --oneline 2>/dev/null | wc -l")
            let commits = Int64(commitOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            totalCommits += commits

            // Stash count (track delta since last poll)
            let stashOutput = shell("git -C '\(repo)' stash list 2>/dev/null | wc -l")
            let currentStashCount = Int(stashOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let lastCount = lastStashCounts[repo] ?? currentStashCount
            let delta = currentStashCount - lastCount
            if delta > 0 {
                totalStashDelta += Int64(delta)
            }
            lastStashCounts[repo] = currentStashCount
        }

        var events: [(statKey: String, valueInt: Int64, valueFloat: Double)] = []

        if totalCommits > 0 {
            events.append((statKey: "git_commits", valueInt: totalCommits, valueFloat: 0.0))
        }
        if totalStashDelta > 0 {
            events.append((statKey: "git_stashes", valueInt: totalStashDelta, valueFloat: 0.0))
        }

        guard !events.isEmpty else { return }

        do {
            try db.upsertEvents(events)
        } catch {
            print("[GitCollector] Failed to write: \(error)")
        }
    }

    private func shell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
