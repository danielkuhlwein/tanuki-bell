import SwiftUI

struct NotificationSettingsTab: View {
    @AppStorage("sound_enabled") private var soundEnabled = true
    @State private var globalSound = SoundPreferences.globalSound()
    @State private var showResetConfirmation = false
    @State private var resetToken = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Sound
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sound")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Toggle("Play notification sound", isOn: $soundEnabled)
                        Spacer()
                        GlobalSoundPicker(
                            selectedSound: $globalSound,
                            isEnabled: soundEnabled
                        )
                    }
                }

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
                            NotificationTypeToggle(
                                type: type,
                                soundEnabled: soundEnabled,
                                resetToken: resetToken
                            )
                        }
                    }
                }

                // Reset
                Divider()

                Button("Reset sounds to defaults") {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .alert(
                    "Reset Notification Sounds?",
                    isPresented: $showResetConfirmation
                ) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive) {
                        SoundPreferences.resetToDefaults()
                        globalSound = .defaultSound
                        resetToken += 1
                    }
                } message: {
                    Text("This will reset the global sound to mongee-aoww and clear all per-type sound customizations.")
                }
            }
            .padding(.vertical)
            .padding(.horizontal, 40)
        }
    }
}

private struct NotificationTypeToggle: View {
    let type: NotificationType
    let soundEnabled: Bool
    let resetToken: Int
    @State private var isEnabled: Bool
    @State private var soundOverride: NotificationSoundName?

    init(type: NotificationType, soundEnabled: Bool, resetToken: Int) {
        self.type = type
        self.soundEnabled = soundEnabled
        self.resetToken = resetToken
        self._isEnabled = State(
            initialValue: NotificationPreferences.isEnabled(type)
        )
        self._soundOverride = State(
            initialValue: SoundPreferences.soundOverride(for: type)
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            SoundPickerIcon(
                selectedSound: soundOverride,
                isEnabled: isEnabled && soundEnabled
            ) { sound in
                soundOverride = sound
                SoundPreferences.setSoundOverride(sound, for: type)
            }

            Toggle(type.displayTitle, isOn: $isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    NotificationPreferences.setEnabled(type, value: newValue)
                }

            if let override = soundOverride {
                Spacer()
                Text(override.displayName)
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .opacity(0.7)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: resetToken) { _, _ in
            soundOverride = SoundPreferences.soundOverride(for: type)
        }
    }
}
