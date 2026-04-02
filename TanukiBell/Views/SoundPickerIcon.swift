import SwiftUI

struct SoundPickerIcon: View {
    let selectedSound: NotificationSoundName?
    let isEnabled: Bool
    let onSelect: (NotificationSoundName?) -> Void

    @State private var isHovering = false

    private var hasOverride: Bool { selectedSound != nil }

    private var iconName: String {
        if !isEnabled { return "speaker.slash" }
        return hasOverride ? "speaker.wave.2.fill" : "speaker.wave.2"
    }

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                if !hasOverride {
                    Label("Use Global Sound", systemImage: "checkmark")
                } else {
                    Text("Use Global Sound")
                }
            }

            Divider()

            ForEach(NotificationSoundName.allCatSounds) { sound in
                Button {
                    sound.playPreview()
                    onSelect(sound)
                } label: {
                    if selectedSound == sound {
                        Label(sound.displayName, systemImage: "checkmark")
                    } else {
                        Text(sound.displayName)
                    }
                }
            }

            Divider()

            Button {
                onSelect(.systemDefault)
            } label: {
                if selectedSound == .systemDefault {
                    Label(NotificationSoundName.systemDefault.displayName, systemImage: "checkmark")
                } else {
                    Text(NotificationSoundName.systemDefault.displayName)
                }
            }
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 11))
                .foregroundStyle(hasOverride && isEnabled ? .blue : .secondary)
                .opacity(isEnabled ? (hasOverride ? 1 : (isHovering ? 0.7 : 0.35)) : 0.4)
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            hasOverride && isEnabled
                                ? .blue.opacity(0.15)
                                : (isHovering && isEnabled ? .primary.opacity(0.08) : .clear)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
            if isEnabled {
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
    }
}

struct GlobalSoundPicker: View {
    @Binding var selectedSound: NotificationSoundName
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(isEnabled ? .blue : .secondary)
                .opacity(isEnabled ? 1 : 0.35)
                .frame(width: 18, height: 18)
                .background(
                    isEnabled
                        ? RoundedRectangle(cornerRadius: 4).fill(.blue.opacity(0.15))
                        : nil
                )

            Picker(selection: $selectedSound) {
                ForEach(NotificationSoundName.allCatSounds) { sound in
                    if sound == .defaultSound {
                        Text("\(sound.displayName) (default)").tag(sound)
                    } else {
                        Text(sound.displayName).tag(sound)
                    }
                }

                Divider()

                Text(NotificationSoundName.systemDefault.displayName)
                    .tag(NotificationSoundName.systemDefault)
            } label: {
                EmptyView()
            }
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!isEnabled)
            .onChange(of: selectedSound) { _, newValue in
                newValue.playPreview()
                SoundPreferences.setGlobalSound(newValue)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}
