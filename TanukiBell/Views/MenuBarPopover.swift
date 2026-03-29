import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tanuki Bell")
                    .font(.headline)
                Spacer()
                if let lastPoll = appState.lastPollTime {
                    Text("Last: \(lastPoll, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Content
            if appState.isConnected {
                Text("No notifications yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Not connected")
                        .font(.headline)
                    Text("Open Settings to add your GitLab token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings...") {
                        NSApp.sendAction(
                            Selector(("showSettingsWindow:")),
                            to: nil, from: nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Footer
            HStack {
                Button("Mark All Read") {
                    // TODO: Phase 2
                }
                .disabled(appState.unreadCount == 0)

                Spacer()

                Button("Settings...") {
                    NSApp.sendAction(
                        Selector(("showSettingsWindow:")),
                        to: nil, from: nil
                    )
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
        }
    }
}
