import Sparkle

/// Wraps SPUStandardUpdaterController for use from SwiftUI.
@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
