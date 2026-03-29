import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("sound_enabled") private var soundEnabled = true

    var body: some View {
        Form {
            Section("Notification Types") {
                Text("Configure which notification types are shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // TODO: Phase 2 — per-type toggles backed by @AppStorage
                ForEach(NotificationType.allCases, id: \.self) { type in
                    Toggle(type.displayTitle, isOn: .constant(type.defaultEnabled))
                }
            }

            Section("Sound") {
                Toggle("Play notification sound", isOn: $soundEnabled)
            }
        }
        .padding()
    }
}
