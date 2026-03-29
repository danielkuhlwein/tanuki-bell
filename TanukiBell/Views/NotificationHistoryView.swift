import SwiftUI
import SwiftData

struct NotificationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NotificationRecord.receivedAt, order: .reverse)
    private var allNotifications: [NotificationRecord]

    @State private var searchText: String = ""
    @State private var typeFilter: NotificationType?

    private var filteredNotifications: [NotificationRecord] {
        allNotifications.filter { record in
            let matchesSearch = searchText.isEmpty
                || record.title.localizedCaseInsensitiveContains(searchText)
                || record.mrTitle.localizedCaseInsensitiveContains(searchText)
                || record.projectName.localizedCaseInsensitiveContains(searchText)
                || record.senderName.localizedCaseInsensitiveContains(searchText)

            let matchesType = typeFilter == nil
                || record.notificationType == typeFilter?.rawValue

            return matchesSearch && matchesType
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notifications...", text: $searchText)
                    .textFieldStyle(.plain)

                Picker("Type", selection: $typeFilter) {
                    Text("All Types").tag(nil as NotificationType?)
                    Divider()
                    ForEach(NotificationType.allCases, id: \.self) { type in
                        Text(type.displayTitle).tag(type as NotificationType?)
                    }
                }
                .frame(width: 160)
            }
            .padding(8)

            Divider()

            // Notification list
            if filteredNotifications.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(searchText.isEmpty && typeFilter == nil
                         ? "No notification history"
                         : "No matching notifications")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredNotifications) { record in
                        NotificationRowView(record: record)
                            .contentShape(Rectangle())
                            .onTapGesture { openNotification(record) }
                    }
                }
            }
        }
    }

    private func openNotification(_ record: NotificationRecord) {
        if let urlString = record.sourceURL, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        record.isRead = true
        try? modelContext.save()
    }
}
