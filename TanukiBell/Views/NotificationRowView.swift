import SwiftUI

struct NotificationRowView: View {
    let record: NotificationRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Per-type icon
            if let type = NotificationType(rawValue: record.notificationType),
               let image = type.iconImage {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "bell")
                    .frame(width: 24, height: 24)
            }

            // Content — takes full remaining width
            VStack(alignment: .leading, spacing: 3) {
                // Title + timestamp on same line
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(.system(size: 13))
                        .fontWeight(record.isRead ? .regular : .semibold)
                        .lineLimit(2)

                    Spacer(minLength: 4)

                    Text(shortRelativeTime(record.receivedAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                // MR reference: "!1003 - frontend/cav-ts-apps-tools"
                if let iid = record.mrIID {
                    Text("!\(iid, format: .number.grouping(.never)) \u{2014} \(stripOrg(record.projectName))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // MR title
                Text(record.mrTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                // Body excerpt (comment content, etc.)
                if let excerpt = record.bodyExcerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 5)
        .opacity(record.isRead ? 0.7 : 1.0)
    }

    /// Strip the org/group prefix from project path.
    /// "cavnue/frontend/cav-ts-apps-tools" → "frontend/cav-ts-apps-tools"
    private func stripOrg(_ fullPath: String) -> String {
        let parts = fullPath.split(separator: "/")
        guard parts.count > 1 else { return fullPath }
        return parts.dropFirst().joined(separator: "/")
    }

    /// Short relative time: "2m", "1h", "3d" etc.
    private func shortRelativeTime(_ date: Date) -> String {
        let seconds = Int(Date.now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)d"
    }
}
