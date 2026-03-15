import SwiftUI

@main
struct PulseBarApp: App {
    @State private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Pulse", systemImage: "waveform.path.ecg") {
            MenuBarView(pushScheduler: appState.pushScheduler)
                .onAppear {
                    if !appState.isSetupComplete {
                        openWindow(id: "onboarding")
                    }
                }
        }
        .menuBarExtraStyle(.window)

        Window("Pulse Setup", id: "onboarding") {
            OnboardingWindow()
                .onReceive(NotificationCenter.default.publisher(for: .onboardingCompleted)) { _ in
                    appState.isSetupComplete = true
                    appState.startAll()
                    NSApplication.shared.windows
                        .first { $0.identifier?.rawValue == "onboarding" }?
                        .close()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 480, height: 520)

        Window("Pulse API", id: "pulse-api-settings") {
            PulseAPISettingsView(pushScheduler: appState.pushScheduler)
        }
        .defaultSize(width: 440, height: 460)
    }
}

@MainActor
@Observable
final class AppState {
    var isSetupComplete: Bool
    let pushScheduler = PushScheduler()
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

        inputCollector.configure(launcherShortcut: config.launcherShortcut)
        inputCollector.start()

        appCollector.start()

        fileCollector.configure(config: config)
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
