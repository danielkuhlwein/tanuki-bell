import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        registerNotificationCategories()
    }

    // MARK: - Notification setup

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
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

    // MARK: - UNUserNotificationCenterDelegate

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
        case "MARK_DONE":
            if let todoID = userInfo["todoID"] as? String {
                // TODO: Phase 1 — call GitLabService.markTodoAsDone
                print("Mark done: \(todoID)")
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
