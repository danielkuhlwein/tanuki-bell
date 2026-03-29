import SwiftUI
import SwiftData

@main
struct TanukiBellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
                .frame(width: 360, height: 480)
        } label: {
            Image(systemName: appState.unreadCount > 0 ? "bell.badge" : "bell")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
