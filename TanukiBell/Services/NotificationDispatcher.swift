import Foundation
import UserNotifications
import AppKit

struct NotificationDispatcher {
    // Holds NSSound references during playback — NSSound stops if its object is deallocated.
    @MainActor private static var activeSounds: [NSSound] = []

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
            let soundName = SoundPreferences.soundOverride(for: notification.type) ?? SoundPreferences.globalSound()
            print("[Dispatch] Sound for \(notification.type.rawValue): \(soundName.rawValue)")
            if soundName == .systemDefault {
                // Let UNNotificationSound handle the macOS system alert sound.
                content.sound = .default
            } else {
                // UNNotificationSound(named:) silently falls back to system default on macOS
                // because UserNotificationsServer cannot reliably access app-bundled files.
                // For a menu bar app that is always running, playing via NSSound is reliable.
                content.sound = nil
                Task { @MainActor in
                    guard let url = Bundle.main.url(forResource: soundName.rawValue, withExtension: "wav"),
                          let sound = NSSound(contentsOf: url, byReference: false) else { return }
                    activeSounds.append(sound)
                    sound.play()
                    try? await Task.sleep(for: .seconds(3))
                    activeSounds.removeAll { $0 === sound }
                }
            }
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
