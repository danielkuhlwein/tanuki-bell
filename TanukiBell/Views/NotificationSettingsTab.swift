import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("sound_enabled") private var soundEnabled = true

    var body: some View {
        Form {
            Section("Notification Types") {
                Text("Choose which notification types trigger alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(NotificationType.allCases, id: \.self) { type in
                    NotificationTypeToggle(type: type)
                }
            }

            Section("Sound") {
                Toggle("Play notification sound", isOn: $soundEnabled)
            }
        }
        .padding()
    }
}

/// Individual toggle backed by @AppStorage keyed per notification type.
private struct NotificationTypeToggle: View {
    let type: NotificationType
    @State private var isEnabled: Bool

    init(type: NotificationType) {
        self.type = type
        // Read initial value from UserDefaults, falling back to the type's default
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
