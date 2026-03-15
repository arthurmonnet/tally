import Foundation
import CoreServices

@MainActor
final class FileCollector {
    private var stream: FSEventStreamRef?
    private var flushTimer: Timer?
    private var watchedPaths: [String] = []
    private var screenshotPatterns: [String] = []

    // In-memory counters
    private var counters: [String: Int64] = [:]
    private var maybeScreenshots: Int64 = 0

    // Live stats for instant UI updates
    private var liveStats: LiveStats?

    private let db = Database.shared

    func configure(config: UserConfig, liveStats: LiveStats? = nil) {
        self.liveStats = liveStats
        var paths = config.screenshotFolders.map {
            NSString(string: $0).expandingTildeInPath
        }

        // Auto-discover common screenshot directories
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Desktop",
            "\(home)/Desktop/CleanShot",
            "\(home)/Library/Application Support/CleanShot/media",
            "\(home)/Documents/Screenshots",
            "\(home)/Pictures/Screenshots",
        ]
        let fm = FileManager.default
        for candidate in candidates {
            if fm.fileExists(atPath: candidate), !paths.contains(candidate) {
                paths.append(candidate)
            }
        }

        watchedPaths = paths
        screenshotPatterns = config.screenshotPatterns
    }

    func start() {
        guard !watchedPaths.isEmpty else {
            print("[FileCollector] No paths to watch")
            return
        }

        let pathsToWatch = watchedPaths as CFArray
        var context = FSEventStreamContext()

        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        context.info = rawSelf

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let collector = Unmanaged<FileCollector>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            for i in 0..<numEvents {
                let path = paths[i]
                MainActor.assumeIsolated {
                    collector.handleFSEvent(path: path)
                }
            }
        }

        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // 1 second latency
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )

        guard let stream else {
            print("[FileCollector] Failed to create FSEvent stream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)

        flushTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                self.flush()
            }
        }

        print("[FileCollector] Started watching \(watchedPaths)")
    }

    func stop() {
        flush()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        flushTimer?.invalidate()
        flushTimer = nil
        print("[FileCollector] Stopped")
    }

    private func handleFSEvent(path: String) {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        // Check if file exists (created) or not (deleted)
        if fm.fileExists(atPath: path) {
            // File created — validate extension is a clean alphanumeric extension
            if !ext.isEmpty, ext.count <= 10, ext.allSatisfy({ $0.isLetter || $0.isNumber }) {
                counters["files_created:\(ext)", default: 0] += 1
            }

            // Screenshot detection
            let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]
            if imageExtensions.contains(ext) {
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? UInt64,
                   size >= 50_000 && size <= 20_000_000 {
                    if matchesScreenshotPattern(filename: filename) {
                        counters["screenshots", default: 0] += 1
                        liveStats?.increment("screenshots")
                    } else {
                        maybeScreenshots += 1
                    }
                }
            }
        } else {
            // File deleted
            counters["files_deleted", default: 0] += 1
        }
    }

    private func matchesScreenshotPattern(filename: String) -> Bool {
        for pattern in screenshotPatterns {
            if filename.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        // Built-in fallback patterns
        let builtinPatterns = [
            "Screenshot \\d{4}-\\d{2}-\\d{2} at",
            "CleanShot \\d{4}-\\d{2}-\\d{2} at",
            "Screen Shot \\d{4}-\\d{2}-\\d{2}",
            "Xnapper-",
            "Kapture \\d{4}-\\d{2}-\\d{2}",
        ]
        for pattern in builtinPatterns {
            if filename.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    private func flush() {
        guard !counters.isEmpty else { return }

        var events: [(statKey: String, valueInt: Int64, valueFloat: Double)] = []
        for (key, value) in counters {
            events.append((statKey: key, valueInt: value, valueFloat: 0.0))
        }
        counters.removeAll()

        do {
            try db.upsertEvents(events)
        } catch {
            print("[FileCollector] Failed to flush: \(error)")
        }
    }
}
