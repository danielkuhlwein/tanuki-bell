import Foundation
import UserNotifications

enum SoundPreferences {
    private static let globalKey = "global_notification_sound"
    private static let perTypePrefix = "notification_sound_"

    static func globalSound() -> NotificationSoundName {
        guard let raw = UserDefaults.standard.string(forKey: globalKey),
              let sound = NotificationSoundName(rawValue: raw) else {
            return .defaultSound
        }
        return sound
    }

    static func setGlobalSound(_ sound: NotificationSoundName) {
        UserDefaults.standard.set(sound.rawValue, forKey: globalKey)
    }

    static func soundOverride(for type: NotificationType) -> NotificationSoundName? {
        let key = perTypePrefix + type.rawValue
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return NotificationSoundName(rawValue: raw)
    }

    static func setSoundOverride(_ sound: NotificationSoundName?, for type: NotificationType) {
        let key = perTypePrefix + type.rawValue
        if let sound {
            UserDefaults.standard.set(sound.rawValue, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func resolvedSound(for type: NotificationType) -> UNNotificationSound {
        if let override = soundOverride(for: type) {
            return override.notificationSound
        }
        return globalSound().notificationSound
    }

    static func hasAnyOverrides() -> Bool {
        NotificationType.allCases.contains { soundOverride(for: $0) != nil }
    }

    static func resetToDefaults() {
        setGlobalSound(.defaultSound)
        for type in NotificationType.allCases {
            setSoundOverride(nil, for: type)
        }
    }
}
