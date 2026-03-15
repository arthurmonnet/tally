import SwiftUI

@main
struct TallyApp: App {
    @State private var appState = AppState()

    init() {
        // On first launch, show as a regular app (dock icon visible)
        // so the onboarding window appears in the foreground.
        if !(UserConfig.load()?.onboardingCompleted ?? false) {
            NSApplication.shared.setActivationPolicy(.regular)
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("Tally", image: "MenuBarIcon") {
            MenuBarView(pushScheduler: appState.pushScheduler, liveStats: appState.liveStats)
        }
        .menuBarExtraStyle(.window)

        Window("Tally Setup", id: "onboarding") {
            OnboardingWindow(liveStats: appState.liveStats)
                .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                    appState.isSetupComplete = true
                    appState.startAll()

                    // Close the onboarding window and drop into menubar-only mode
                    NSApplication.shared.windows
                        .first { $0.identifier?.rawValue == "onboarding" }?
                        .close()
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
                .onAppear {
                    guard !appState.isSetupComplete else { return }
                    // Ensure the onboarding window is visible and focused
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let window = NSApplication.shared.windows.first(where: {
                            $0.identifier?.rawValue == "onboarding"
                        }) {
                            window.makeKeyAndOrderFront(nil)
                            NSApplication.shared.activate(ignoringOtherApps: true)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 480, height: 520)

        Window("Tally API", id: "tally-api-settings") {
            TallyAPISettingsView(pushScheduler: appState.pushScheduler)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 120)
    }
}

@MainActor
@Observable
final class AppState {
    var isSetupComplete: Bool
    let pushScheduler = PushScheduler()
    let liveStats = LiveStats()
    private var collectorsStarted = false

    private let inputCollector = InputCollector()
    private let appCollector = AppCollector()
    private let fileCollector = FileCollector()
    private let gitCollector = GitCollector()
    private let systemCollector = SystemCollector()
    private let localServer = LocalServer()
    private let achievementEngine = AchievementEngine()

    init() {
        let config = UserConfig.load()
        isSetupComplete = config?.onboardingCompleted ?? false

        let effectiveConfig = config ?? UserConfig.defaultConfig
        startCollectors(config: effectiveConfig)
    }

    func startAll() {
        let config = UserConfig.load() ?? UserConfig.defaultConfig
        startCollectors(config: config)
    }

    private func startCollectors(config: UserConfig) {
        guard !collectorsStarted else { return }
        collectorsStarted = true

        liveStats.seedFromDatabase()

        inputCollector.configure(launcherShortcut: config.launcherShortcut, liveStats: liveStats)
        inputCollector.start()

        appCollector.start()

        fileCollector.configure(config: config, liveStats: liveStats)
        fileCollector.start()

        gitCollector.configure(repos: config.gitRepos)
        gitCollector.start()

        systemCollector.start()
        localServer.start()
        achievementEngine.start()

        // Start push scheduler if configured
        pushScheduler.start()

        // Push on quit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [pushScheduler] _ in
            pushScheduler.pushOnQuit()
        }

        print("[AppState] All collectors started (setup complete: \(isSetupComplete))")
    }
}
