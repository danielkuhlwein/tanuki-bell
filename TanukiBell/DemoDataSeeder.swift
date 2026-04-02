import SwiftData
import Foundation

/// Seeds the SwiftData store with fictional notification data for screenshot capture.
/// Activated by the `-demo` launch argument. No real GitLab API calls are made.
@MainActor
enum DemoDataSeeder {

    /// Wipe existing records and insert curated demo notifications.
    /// Returns the number of unread notifications seeded.
    @discardableResult
    static func seed(into container: ModelContainer) -> Int {
        let context = ModelContext(container)

        // Clean slate
        do {
            try context.delete(model: NotificationRecord.self)
            try context.delete(model: ProcessedTodo.self)
            try context.delete(model: TrackedMergeRequest.self)
        } catch {
            print("[Demo] Failed to clear existing records: \(error)")
        }

        let records = buildRecords()
        for record in records {
            context.insert(record)
        }
        do {
            try context.save()
        } catch {
            print("[Demo] Failed to save demo records: \(error)")
        }

        // Fire a few system notifications for banner screenshots
        fireSystemNotifications(from: records)

        return records.filter { !$0.isRead }.count
    }

    // MARK: - Demo Data

    private static func buildRecords() -> [NotificationRecord] {
        let now = Date.now
        func ago(_ minutes: Int) -> Date {
            now.addingTimeInterval(-Double(minutes) * 60)
        }

        var records: [NotificationRecord] = []

        // ── MR !142 — endor/shield-ui ──────────────────────────────
        // Full review lifecycle: request → comment → changes requested → push → approved
        let mr142Project = "endor/shield-ui"
        let mr142Title = "Add holocron cache layer to force-push protection"
        let mr142IID = 142

        records.append(NotificationRecord(
            notificationType: NotificationType.reviewRequested.rawValue,
            title: "Review Requested by Motoko K",
            projectName: mr142Project,
            mrIID: mr142IID,
            mrTitle: mr142Title,
            sourceURL: "https://gitlab.com/endor/shield-ui/-/merge_requests/142",
            senderName: "Motoko Kusanagi",
            receivedAt: ago(45)
        ))

        let comment142 = NotificationRecord(
            notificationType: NotificationType.comment.rawValue,
            title: "New Comment by Motoko K",
            projectName: mr142Project,
            mrIID: mr142IID,
            mrTitle: mr142Title,
            sourceURL: "https://gitlab.com/endor/shield-ui/-/merge_requests/142#note_1001",
            senderName: "Motoko Kusanagi",
            bodyExcerpt: "The cache invalidation on rebase looks solid, but we should debounce the webhook handler.",
            receivedAt: ago(30)
        )
        records.append(comment142)

        records.append(NotificationRecord(
            notificationType: NotificationType.changesRequested.rawValue,
            title: "Changes Requested by Motoko K",
            projectName: mr142Project,
            mrIID: mr142IID,
            mrTitle: mr142Title,
            sourceURL: "https://gitlab.com/endor/shield-ui/-/merge_requests/142",
            senderName: "Motoko Kusanagi",
            receivedAt: ago(25)
        ))

        let push142 = NotificationRecord(
            notificationType: NotificationType.newCommitsPushed.rawValue,
            title: "New Commits by Rincewind",
            projectName: mr142Project,
            mrIID: mr142IID,
            mrTitle: mr142Title,
            sourceURL: "https://gitlab.com/endor/shield-ui/-/merge_requests/142",
            senderName: "Rincewind",
            receivedAt: ago(15)
        )
        push142.isRead = true
        records.append(push142)

        let approved142 = NotificationRecord(
            notificationType: NotificationType.approved.rawValue,
            title: "Approved by Motoko K",
            projectName: mr142Project,
            mrIID: mr142IID,
            mrTitle: mr142Title,
            sourceURL: "https://gitlab.com/endor/shield-ui/-/merge_requests/142",
            senderName: "Motoko Kusanagi",
            receivedAt: ago(5)
        )
        records.append(approved142)

        // ── MR !89 — endor/hyperdrive-api ──────────────────────────
        // Pipeline lifecycle: assigned → pipeline fail → push → pipeline pass → merged
        let mr89Project = "endor/hyperdrive-api"
        let mr89Title = "Refactor warp auth middleware to use mTLS"
        let mr89IID = 89

        let assigned89 = NotificationRecord(
            notificationType: NotificationType.assigned.rawValue,
            title: "Assigned to You by Ponder S",
            projectName: mr89Project,
            mrIID: mr89IID,
            mrTitle: mr89Title,
            sourceURL: "https://gitlab.com/endor/hyperdrive-api/-/merge_requests/89",
            senderName: "Ponder Stibbons",
            receivedAt: ago(120)
        )
        assigned89.isRead = true
        records.append(assigned89)

        let pipeFail89 = NotificationRecord(
            notificationType: NotificationType.pipelineFailed.rawValue,
            title: "Pipeline Failed",
            projectName: mr89Project,
            mrIID: mr89IID,
            mrTitle: mr89Title,
            sourceURL: "https://gitlab.com/endor/hyperdrive-api/-/merge_requests/89",
            senderName: "Ponder Stibbons",
            receivedAt: ago(60)
        )
        pipeFail89.isRead = true
        records.append(pipeFail89)

        let push89 = NotificationRecord(
            notificationType: NotificationType.newCommitsPushed.rawValue,
            title: "New Commits by Ponder S",
            projectName: mr89Project,
            mrIID: mr89IID,
            mrTitle: mr89Title,
            sourceURL: "https://gitlab.com/endor/hyperdrive-api/-/merge_requests/89",
            senderName: "Ponder Stibbons",
            receivedAt: ago(40)
        )
        push89.isRead = true
        records.append(push89)

        let pipePass89 = NotificationRecord(
            notificationType: NotificationType.pipelinePassed.rawValue,
            title: "Pipeline Passed",
            projectName: mr89Project,
            mrIID: mr89IID,
            mrTitle: mr89Title,
            sourceURL: "https://gitlab.com/endor/hyperdrive-api/-/merge_requests/89",
            senderName: "Ponder Stibbons",
            receivedAt: ago(35)
        )
        pipePass89.isRead = true
        records.append(pipePass89)

        records.append(NotificationRecord(
            notificationType: NotificationType.merged.rawValue,
            title: "MR Merged",
            projectName: mr89Project,
            mrIID: mr89IID,
            mrTitle: mr89Title,
            sourceURL: "https://gitlab.com/endor/hyperdrive-api/-/merge_requests/89",
            senderName: "Ponder Stibbons",
            receivedAt: ago(10)
        ))

        // ── MR !203 — endor/bespin-design-tokens ───────────────────
        // Single mention with body excerpt
        records.append(NotificationRecord(
            notificationType: NotificationType.mentioned.rawValue,
            title: "Mentioned by Kaylee F",
            projectName: "endor/bespin-design-tokens",
            mrIID: 203,
            mrTitle: "Update cloud city color palette for dark mode",
            sourceURL: "https://gitlab.com/endor/bespin-design-tokens/-/merge_requests/203#note_2001",
            senderName: "Kaylee Frye",
            bodyExcerpt: "Hey, does this conflict with the holocron cache PR? The token names overlap.",
            receivedAt: ago(20)
        ))

        // ── MR !67 — endor/ansible-lightsaber ──────────────────────
        // Re-review request flow
        let mr67Project = "endor/ansible-lightsaber"
        let mr67Title = "Add rate limiting docs for kyber crystal API"
        let mr67IID = 67

        let review67 = NotificationRecord(
            notificationType: NotificationType.reviewRequested.rawValue,
            title: "Review Requested by Samwise G",
            projectName: mr67Project,
            mrIID: mr67IID,
            mrTitle: mr67Title,
            sourceURL: "https://gitlab.com/endor/ansible-lightsaber/-/merge_requests/67",
            senderName: "Samwise Gamgee",
            receivedAt: ago(180)
        )
        review67.isRead = true
        records.append(review67)

        let comment67 = NotificationRecord(
            notificationType: NotificationType.comment.rawValue,
            title: "New Comment by Samwise G",
            projectName: mr67Project,
            mrIID: mr67IID,
            mrTitle: mr67Title,
            sourceURL: "https://gitlab.com/endor/ansible-lightsaber/-/merge_requests/67#note_3001",
            senderName: "Samwise Gamgee",
            bodyExcerpt: "I've been thinking — this section could use a diagram.",
            receivedAt: ago(120)
        )
        comment67.isRead = true
        records.append(comment67)

        records.append(NotificationRecord(
            notificationType: NotificationType.reReviewRequested.rawValue,
            title: "Re-Review Requested by Samwise G",
            projectName: mr67Project,
            mrIID: mr67IID,
            mrTitle: mr67Title,
            sourceURL: "https://gitlab.com/endor/ansible-lightsaber/-/merge_requests/67",
            senderName: "Samwise Gamgee",
            receivedAt: ago(60)
        ))

        return records
    }

    // MARK: - System Notification Banners

    /// Fire a few system notifications so banner screenshots can be captured.
    private static func fireSystemNotifications(from records: [NotificationRecord]) {
        let unread = records.filter { !$0.isRead }
            .sorted { $0.receivedAt > $1.receivedAt }

        // Fire the 3 most recent unread as system notifications
        for record in unread.prefix(3) {
            let classified = ClassifiedNotification(
                type: NotificationType(rawValue: record.notificationType) ?? .prActivity,
                title: record.title,
                projectName: record.projectName,
                mrTitle: record.mrTitle,
                mrIID: record.mrIID,
                sourceURL: record.sourceURL.flatMap(URL.init(string:)),
                senderName: record.senderName,
                senderAvatarURL: nil,
                threadID: record.groupKey,
                notificationID: "demo-\(record.id)",
                gitlabTodoID: "",
                bodyExcerpt: record.bodyExcerpt
            )
            NotificationDispatcher.send(classified)
        }
    }
}
