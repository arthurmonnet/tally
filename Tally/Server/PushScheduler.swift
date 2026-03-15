import AppKit
import Foundation

@MainActor
@Observable
final class PushScheduler {
    var lastPushResult: PushResult?
    var isPushing = false

    private var scheduledTask: Task<Void, Never>?
    private let remotePush = RemotePush()

    var isEnabled: Bool {
        guard let config = UserConfig.load() else { return false }
        return config.isRemotePushEnabled && KeychainHelper.remotePushToken != nil
    }

    func start() {
        guard isEnabled else { return }
        scheduleNextPush()
        observeWake()
    }

    func stop() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    func updateSchedule() {
        stop()
        if isEnabled {
            scheduleNextPush()
        }
    }

    func pushNow() async {
        guard !isPushing else { return }
        await performPush()
    }

    func pushOnQuit() {
        guard isEnabled,
              let config = UserConfig.load(),
              let url = config.remotePushUrl,
              let token = KeychainHelper.remotePushToken else { return }

        let semaphore = DispatchSemaphore(value: 0)

        Task.detached {
            let result = await self.remotePush.pushDailySummary(url: url, token: token)
            print("[PushScheduler] Quit push: \(result.success ? "ok" : result.errorMessage ?? "failed")")
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)
    }

    // MARK: - Private

    private func scheduleNextPush() {
        guard let config = UserConfig.load(),
              let frequency = config.remotePushFrequency,
              let interval = frequency.intervalSeconds else { return }

        scheduledTask?.cancel()
        scheduledTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.performPush()
            }
        }
    }

    private func performPush() async {
        guard let config = UserConfig.load(),
              let url = config.remotePushUrl,
              let token = KeychainHelper.remotePushToken else {
            lastPushResult = .failure("Not configured")
            return
        }

        isPushing = true
        let result = await remotePush.pushDailySummary(url: url, token: token)
        lastPushResult = result
        isPushing = false

        print("[PushScheduler] Push \(result.success ? "succeeded" : "failed: \(result.errorMessage ?? "")")")
    }

    private func observeWake() {
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.isEnabled else { return }

                // If last push was long enough ago, push now
                if let lastResult = self.lastPushResult {
                    let config = UserConfig.load()
                    let interval = config?.remotePushFrequency?.intervalSeconds ?? 3600
                    let elapsed = Date().timeIntervalSince(lastResult.timestamp)
                    if elapsed >= interval {
                        await self.performPush()
                    }
                } else {
                    await self.performPush()
                }
            }
        }
    }
}
