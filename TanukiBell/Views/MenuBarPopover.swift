import SwiftUI
import SwiftData

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<NotificationRecord> { !$0.isRead },
        sort: \NotificationRecord.receivedAt,
        order: .reverse
    )
    private var unreadNotifications: [NotificationRecord]

    @Query(
        filter: #Predicate<NotificationRecord> { $0.isRead },
        sort: \NotificationRecord.receivedAt,
        order: .reverse
    )
    private var readNotifications: [NotificationRecord]

    /// Recent read notifications (capped to 10)
    private var recentRead: [NotificationRecord] {
        Array(readNotifications.prefix(10))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
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
            if !appState.isConnected {
                notConnectedView
            } else if unreadNotifications.isEmpty && recentRead.isEmpty {
                emptyStateView
            } else {
                notificationListView
            }

            Divider()

            // Footer
            HStack {
                Button("Mark All Read") {
                    markAllRead()
                }
                .disabled(unreadNotifications.isEmpty)

                Spacer()

                SettingsLink {
                    Text("Settings...")
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Subviews

    private var notConnectedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not connected")
                .font(.headline)
            Text("Open Settings to add your GitLab token.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsLink {
                Text("Open Settings...")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No notifications")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notificationListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !unreadNotifications.isEmpty {
                    sectionHeader("New (\(unreadNotifications.count))")

                    ForEach(unreadNotifications) { record in
                        NotificationRowView(record: record)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { openNotification(record) }
                        Divider()
                            .padding(.leading, 46)
                    }
                }

                if !recentRead.isEmpty {
                    sectionHeader("Seen")

                    ForEach(recentRead) { record in
                        NotificationRowView(record: record)
                            .padding(.horizontal, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { openNotification(record) }
                        Divider()
                            .padding(.leading, 46)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    // MARK: - Actions

    private func openNotification(_ record: NotificationRecord) {
        if let urlString = record.sourceURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        record.isRead = true
        try? modelContext.save()
        appState.unreadCount = unreadNotifications.count
    }

    private func markAllRead() {
        for record in unreadNotifications {
            record.isRead = true
        }
        try? modelContext.save()
        appState.unreadCount = 0
    }
}
