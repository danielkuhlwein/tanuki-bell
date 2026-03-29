import SwiftUI
import SwiftData

@main
struct TanukiBellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    let modelContainer: ModelContainer = {
        let schema = Schema([
            ProcessedTodo.self,
            NotificationRecord.self,
            PollState.self,
            TrackedMergeRequest.self,
        ])
        let config = ModelConfiguration(
            "TanukiBell",
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
                .modelContainer(modelContainer)
                .frame(width: 360, height: 480)
                .onAppear {
                    // Share model container with AppDelegate for notification handling
                    appDelegate.modelContainer = modelContainer

                    // Auto-start polling if token exists
                    if KeychainStore.loadToken() != nil {
                        appState.startPolling(modelContainer: modelContainer)
                    }
                }
        } label: {
            Image(systemName: appState.unreadCount > 0 ? "bell.badge" : "bell")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(modelContainer)
        }
    }
}
