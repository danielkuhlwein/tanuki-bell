import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("sound_enabled") private var soundEnabled = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Notification Types
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notification Types")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Choose which notification types trigger alerts.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(NotificationType.allCases, id: \.self) { type in
                            NotificationTypeToggle(type: type)
                        }
                    }
                }

                // Sound
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sound")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Toggle("Play notification sound", isOn: $soundEnabled)
                }
            }
            .padding(.vertical)
            .padding(.horizontal, 40)
        }
    }
}

/// Individual toggle backed by UserDefaults keyed per notification type.
private struct NotificationTypeToggle: View {
    let type: NotificationType
    @State private var isEnabled: Bool

    init(type: NotificationType) {
        self.type = type
        self._isEnabled = State(
            initialValue: NotificationPreferences.isEnabled(type)
        )
    }

    var body: some View {
        Toggle(type.displayTitle, isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                NotificationPreferences.setEnabled(type, value: newValue)
            }
    }
}
