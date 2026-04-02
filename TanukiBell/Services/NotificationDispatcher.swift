import Foundation
import UserNotifications
import AppKit

struct NotificationDispatcher {

    /// Deliver the notification if the type is enabled.
    /// Returns `true` if it was actually sent, `false` if skipped (type disabled).
    /// Callers should only persist to history when this returns `true`.
    @discardableResult
    static func send(_ notification: ClassifiedNotification) -> Bool {
        guard NotificationPreferences.isEnabled(notification.type) else {
            print("[Dispatch] Skipped (disabled): \(notification.type.rawValue)")
            return false
        }
        print("[Dispatch] Sending: \(notification.type.rawValue) — \(notification.title)")

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = NotificationClassifier.stripOrg(notification.projectName)
        if let excerpt = notification.bodyExcerpt, !excerpt.isEmpty {
            content.body = "\(notification.mrTitle)\n\(excerpt)"
        } else {
            content.body = notification.mrTitle
        }
        content.threadIdentifier = notification.threadID
        content.categoryIdentifier = "MERGE_REQUEST"
        if UserDefaults.standard.bool(forKey: "sound_enabled") {
            let resolved = SoundPreferences.resolvedSound(for: notification.type)
            print("[Dispatch] Sound for \(notification.type.rawValue): \(resolved)")
            content.sound = resolved
        } else {
            content.sound = nil
        }
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
        return true
    }
}
