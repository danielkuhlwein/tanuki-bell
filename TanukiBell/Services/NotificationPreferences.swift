import Foundation

/// Reads/writes per-type notification enable/disable state from UserDefaults.
enum NotificationPreferences {
    private static let prefix = "notification_enabled_"

    static func isEnabled(_ type: NotificationType) -> Bool {
        let key = prefix + type.rawValue
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return type.defaultEnabled
    }

    static func setEnabled(_ type: NotificationType, value: Bool) {
        let key = prefix + type.rawValue
        UserDefaults.standard.set(value, forKey: key)
    }
}
