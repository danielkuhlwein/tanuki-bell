import Foundation
import UserNotifications
import AppKit

struct NotificationDispatcher {

    static func send(_ notification: ClassifiedNotification) {
        // Skip if user has disabled this notification type
        guard NotificationPreferences.isEnabled(notification.type) else {
            print("[Dispatch] Skipped (disabled): \(notification.type.rawValue)")
            return
        }
        print("[Dispatch] Sending: \(notification.type.rawValue) — \(notification.title)")

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.projectName
        content.body = notification.mrTitle
        content.threadIdentifier = notification.threadID
        content.categoryIdentifier = "MERGE_REQUEST"
        content.sound = UserDefaults.standard.bool(forKey: "sound_enabled") ? .default : nil
        content.userInfo = [
            "url": notification.sourceURL?.absoluteString ?? "",
            "todoID": notification.gitlabTodoID,
            "notificationType": notification.type.rawValue,
            "mrTitle": notification.mrTitle,
        ]

        // Attach per-type icon from asset catalog
        if let image = notification.type.iconImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".png")
            try? pngData.write(to: tempURL)
            if let attachment = try? UNNotificationAttachment(
                identifier: "icon",
                url: tempURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            ) {
                content.attachments = [attachment]
            }
        }

        let request = UNNotificationRequest(
            identifier: notification.notificationID,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to deliver notification: \(error)")
            }
        }
    }
}
