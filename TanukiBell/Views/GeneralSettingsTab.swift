import SwiftUI
import ServiceManagement

struct GeneralSettingsTab: View {
    @AppStorage("polling_interval") private var pollingInterval: Double = 30

    @State private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Polling") {
                HStack {
                    Text("Poll interval: \(Int(pollingInterval))s")
                    Slider(value: $pollingInterval, in: 15...300, step: 15)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .padding()
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
