import Foundation
import UserNotifications
import AppKit

enum NotificationSoundName: String, CaseIterable, Identifiable {
    case aahuhhww
    case aeuw
    case auwhEwh = "AUWH-EWH"
    case eeaawww
    case maAuheh = "ma-auheh"
    case mahEhw = "mah-ehw"
    case mahehwehw
    case mbrreaowww
    case meeOOWW
    case mhhm
    case mmmraoweh
    case mongeeAoww = "mongee-aoww"
    case mrrbr
    case mrwmw
    case systemDefault = "_system_default"

    var id: String { rawValue }

    static let defaultSound: NotificationSoundName = .mongeeAoww

    static let allCatSounds: [NotificationSoundName] = {
        let rest = allCases
            .filter { $0 != .systemDefault && $0 != .defaultSound }
            .sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
        return [defaultSound] + rest
    }()

    var displayName: String {
        if self == .systemDefault { return "System Default" }
        return rawValue
    }

    var fileName: String? {
        if self == .systemDefault { return nil }
        return rawValue + ".wav"
    }

    var notificationSound: UNNotificationSound {
        guard let fileName else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
    }

    @MainActor private static var currentPreview: NSSound?

    @MainActor
    func playPreview() {
        Self.currentPreview?.stop()
        guard self != .systemDefault,
              let url = Bundle.main.url(forResource: rawValue, withExtension: "wav") else {
            Self.currentPreview = nil
            return
        }
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.play()
        Self.currentPreview = sound
    }
}
