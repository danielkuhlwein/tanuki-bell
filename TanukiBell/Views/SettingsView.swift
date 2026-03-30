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

            NotificationHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 500)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
