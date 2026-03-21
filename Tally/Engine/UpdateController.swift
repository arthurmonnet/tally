import Combine
import Sparkle
import os

private let logger = Logger(subsystem: "arthurmonnet.Tally", category: "UpdateController")

// Uses ObservableObject (not @Observable) because Sparkle's SPUUpdater exposes
// canCheckForUpdates via KVO, which bridges naturally to Combine's @Published.
@MainActor
final class UpdateController: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Observe Sparkle's canCheckForUpdates KVO property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        logger.info("Sparkle updater initialized (feed: \(self.updaterController.updater.feedURL?.absoluteString ?? "none"))")
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}
