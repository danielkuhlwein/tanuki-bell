import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppState {
    var unreadCount: Int = 0
    var isConnected: Bool = false
    var lastPollTime: Date?
    var connectionError: String?

    private var pollCoordinator: PollCoordinator?
    private var gitLabService: GitLabService?
    private var idleMonitor: IdleMonitor?

    /// Start polling with the given model container.
    /// Reads token from Keychain and GitLab URL from UserDefaults.
    func startPolling(modelContainer: ModelContainer) {
        guard let token = KeychainStore.loadToken(), !token.isEmpty else {
            isConnected = false
            connectionError = "No token configured"
            return
        }

        let baseURLString = UserDefaults.standard.string(forKey: "gitlab_url") ?? "https://gitlab.com"
        let baseURL = URL(string: baseURLString) ?? URL(string: "https://gitlab.com")!

        let service = GitLabService(baseURL: baseURL)
        self.gitLabService = service

        let coordinator = PollCoordinator(
            gitLabService: service,
            modelContainer: modelContainer,
            onUpdate: { [weak self] unreadCount, pollTime in
                self?.unreadCount = unreadCount
                self?.lastPollTime = pollTime
                self?.isConnected = true
                self?.connectionError = nil
            }
        )
        self.pollCoordinator = coordinator

        let interval = UserDefaults.standard.double(forKey: "polling_interval")
        let pollInterval = interval > 0 ? interval : 30.0
        coordinator.start(interval: pollInterval)

        // Start idle monitoring for adaptive polling
        let monitor = IdleMonitor { [weak coordinator] isIdle in
            Task { @MainActor in
                coordinator?.adjustInterval(idle: isIdle)
            }
        }
        monitor.start()
        self.idleMonitor = monitor

        isConnected = true
    }

    /// Stop polling (e.g. when token is removed).
    func stopPolling() {
        idleMonitor?.stop()
        idleMonitor = nil
        pollCoordinator?.stop()
        pollCoordinator = nil
        gitLabService = nil
        isConnected = false
    }

    /// Restart polling (e.g. after settings change).
    func restartPolling(modelContainer: ModelContainer) {
        stopPolling()
        startPolling(modelContainer: modelContainer)
    }
}
