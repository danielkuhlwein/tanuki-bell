import Sparkle

/// Wraps SPUStandardUpdaterController for use from SwiftUI.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        // Don't auto-start — avoids fatal error if EdDSA key isn't configured yet
        self.controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func startUpdater() {
        do {
            try controller.updater.start()
        } catch {
            print("[Sparkle] Failed to start updater: \(error)")
        }
    }

    func checkForUpdates() {
        if !controller.updater.canCheckForUpdates {
            startUpdater()
        }
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
