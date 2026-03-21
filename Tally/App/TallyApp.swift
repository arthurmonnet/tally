import SwiftUI
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "AppState")

// MARK: - App Delegate

@MainActor
final class TallyAppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var onboardingWindow: NSWindow?

    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.handleLaunch()
        }
    }

    private func handleLaunch() {
        guard !appState.isSetupComplete else { return }
        showOnboarding()
    }

    nonisolated func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            DispatchQueue.main.async {
                if !self.appState.isSetupComplete {
                    self.showOnboarding()
                }
            }
        }
        return true
    }

    func showOnboarding() {
        // If window already exists, just bring it forward
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)

        let view = OnboardingWindow(liveStats: appState.liveStats)
            .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { [weak self] _ in
                self?.completeOnboarding()
            }

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 480, height: 520))
        window.styleMask = [.titled, .closable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        onboardingWindow = window
    }

    private func completeOnboarding() {
        appState.isSetupComplete = true
        appState.startAll()

        onboardingWindow?.close()
        onboardingWindow = nil
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

// MARK: - App Entry Point

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(TallyAppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("Tally", image: "MenuBarIcon") {
            MenuBarView(
                pushScheduler: delegate.appState.pushScheduler,
                liveStats: delegate.appState.liveStats,
                punchline: delegate.appState.punchline,
                updateController: delegate.appState.updateController
            )
        }
        .menuBarExtraStyle(.window)

        Window("Tally API", id: "tally-api-settings") {
            TallyAPISettingsView(pushScheduler: delegate.appState.pushScheduler)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 120)
    }
}

// MARK: - App State

@MainActor
@Observable
final class AppState {
    var isSetupComplete: Bool
    let pushScheduler = PushScheduler()
    let liveStats = LiveStats()
    let punchline = PunchlineGenerator()
    let updateController = UpdateController()
    private var collectorsStarted = false

    private let inputCollector = InputCollector()
    private let appCollector = AppCollector()
    private let fileCollector = FileCollector()
    private let systemCollector = SystemCollector()
    private let achievementEngine = AchievementEngine()

    init() {
        let config = UserConfig.load()
        isSetupComplete = config?.onboardingCompleted ?? false

        let effectiveConfig = config ?? UserConfig.defaultConfig
        startCollectors(config: effectiveConfig)
    }

    func startAll() {
        let config = UserConfig.load() ?? UserConfig.defaultConfig

        // If collectors already started (pre-onboarding), start FileCollector now
        if collectorsStarted {
            fileCollector.configure(config: config, liveStats: liveStats)
            fileCollector.start()
        } else {
            startCollectors(config: config)
        }
    }

    private func startCollectors(config: UserConfig) {
        guard !collectorsStarted else { return }
        collectorsStarted = true

        liveStats.seedFromDatabase()

        inputCollector.configure(launcherShortcut: config.launcherShortcut, liveStats: liveStats)
        inputCollector.start()

        appCollector.start()

        // Defer FileCollector until onboarding completes — its auto-discovery
        // of ~/Desktop etc. triggers a Finder permission dialog too early.
        if isSetupComplete {
            fileCollector.configure(config: config, liveStats: liveStats)
            fileCollector.start()
        }

        systemCollector.start()
        achievementEngine.start()

        // Start push scheduler if configured
        pushScheduler.start()

        // Push on quit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [pushScheduler] _ in
            MainActor.assumeIsolated {
                pushScheduler.pushOnQuit()
            }
        }

        logger.info("All collectors started (setup complete: \(self.isSetupComplete))")
    }
}
