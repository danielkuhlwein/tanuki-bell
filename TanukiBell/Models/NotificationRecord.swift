import SwiftData
import Foundation

@Model
final class NotificationRecord {
    @Attribute(.unique) var id: UUID
    var notificationType: String
    var title: String
    var projectName: String
    var mrIID: Int?
    var mrTitle: String
    var sourceURL: String?
    var senderName: String
    var senderAvatarURL: String?
    var bodyExcerpt: String?
    var receivedAt: Date
    var isRead: Bool

    var groupKey: String {
        guard let iid = mrIID else { return "gitlab-\(projectName)" }
        return "gitlab-\(projectName)-!\(iid)"
    }

    init(
        notificationType: String,
        title: String,
        projectName: String,
        mrIID: Int? = nil,
        mrTitle: String,
        sourceURL: String? = nil,
        senderName: String,
        senderAvatarURL: String? = nil,
        bodyExcerpt: String? = nil
    ) {
        self.id = UUID()
        self.notificationType = notificationType
        self.title = title
        self.projectName = projectName
        self.mrIID = mrIID
        self.mrTitle = mrTitle
        self.sourceURL = sourceURL
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.bodyExcerpt = bodyExcerpt
        self.receivedAt = .now
        self.isRead = false
    }
}
