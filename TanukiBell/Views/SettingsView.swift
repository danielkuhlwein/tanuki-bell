import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ConnectionSettingsTab()
                .tabItem {
                    Label("Connection", systemImage: "network")
                }

            NotificationSettingsTab()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            // LSUIElement apps don't auto-activate — force the app to front
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
