import SwiftUI

struct NotificationRowView: View {
    let record: NotificationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let type = NotificationType(rawValue: record.notificationType),
               let image = type.iconImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "bell")
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline)
                    .fontWeight(record.isRead ? .regular : .semibold)

                if let iid = record.mrIID {
                    Text("\(record.projectName) \u{00B7} !\(iid)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.mrTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(record.receivedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .opacity(record.isRead ? 0.7 : 1.0)
    }
}
