import AppKit
import UserNotifications
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {

    var modelContainer: ModelContainer?
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        registerNotificationCategories()
        requestNotificationPermission()
    }

    // MARK: - Notification setup

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if !granted {
                        DispatchQueue.main.async { self?.showNotificationPermissionAlert() }
                    }
                }
            case .denied:
                DispatchQueue.main.async { self?.showNotificationPermissionAlert() }
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    @MainActor
    private func showNotificationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Notifications Are Disabled"
        alert.informativeText = "Tanuki Bell needs notification permission to alert you about GitLab activity. Please enable notifications in System Settings."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func registerNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_IN_BROWSER",
            title: "Open in GitLab",
            options: [.foreground]
        )

        let markDoneAction = UNNotificationAction(
            identifier: "MARK_DONE",
            title: "Mark as Done",
            options: []
        )

        let mrCategory = UNNotificationCategory(
            identifier: "MERGE_REQUEST",
            actions: [openAction, markDoneAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current()
            .setNotificationCategories([mrCategory])
    }

    // MARK: - Mark notification as read in SwiftData

    @MainActor
    private func markNotificationRead(mrTitle: String) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { $0.mrTitle == mrTitle && !$0.isRead }
        )
        do {
            let records = try context.fetch(descriptor)
            for record in records {
                record.isRead = true
            }
            try context.save()

            // Update bell badge
            let unreadDescriptor = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { !$0.isRead }
            )
            let unreadCount = try context.fetchCount(unreadDescriptor)
            appState?.unreadCount = unreadCount
        } catch {
            print("[AppDelegate] Failed to mark notification read: \(error)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "OPEN_IN_BROWSER", UNNotificationDefaultActionIdentifier:
            if let urlString = userInfo["url"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
            // Mark as read in SwiftData
            if let mrTitle = userInfo["mrTitle"] as? String {
                Task { @MainActor in
                    self.markNotificationRead(mrTitle: mrTitle)
                }
            }
        case "MARK_DONE":
            if let todoID = userInfo["todoID"] as? String,
               let token = KeychainStore.loadToken() {
                let baseURLString = UserDefaults.standard.string(forKey: "gitlab_url") ?? "https://gitlab.com"
                let service = GitLabService(baseURL: URL(string: baseURLString) ?? URL(string: "https://gitlab.com")!)
                Task {
                    try? await service.markTodoAsDone(id: todoID, token: token)
                }
            }
            // Also mark as read
            if let mrTitle = userInfo["mrTitle"] as? String {
                Task { @MainActor in
                    self.markNotificationRead(mrTitle: mrTitle)
                }
            }
        default:
            break
        }

        handler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        handler([.banner, .sound])
    }
}
