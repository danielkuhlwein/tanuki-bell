import SwiftUI
import SwiftData
import ServiceManagement

struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @AppStorage("polling_interval") private var pollingInterval: Double = 30
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Polling
            VStack(alignment: .leading, spacing: 6) {
                Text("Polling")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Slider(value: $pollingInterval, in: 15...300, step: 15)
                    .onChange(of: pollingInterval) { _, _ in
                        if appState.isConnected {
                            appState.restartPolling(modelContainer: modelContext.container)
                        }
                    }

                Text("Poll interval: \(Int(pollingInterval))s")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Startup
            VStack(alignment: .leading, spacing: 6) {
                Text("Startup")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .padding(.vertical)
        .padding(.horizontal, 40)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }
}
