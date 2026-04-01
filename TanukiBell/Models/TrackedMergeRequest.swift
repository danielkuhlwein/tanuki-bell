import SwiftData
import Foundation

/// Tracks the last-known state of MRs the user is involved in,
/// so we can detect merged/closed transitions between polls.
@Model
final class TrackedMergeRequest {
    @Attribute(.unique) var mrID: Int
    var iid: Int
    var projectID: Int
    var projectName: String
    var title: String
    var state: String
    var webUrl: String
    var authorName: String
    var lastSeenAt: Date
    var lastNoteID: Int?

    // Snapshot fields for diff-based event detection (added v0.1.2)
    var sha: String?
    var headPipelineStatus: String?
    var approvedByUsernames: [String]
    var detailedMergeStatus: String?

    init(
        mrID: Int,
        iid: Int,
        projectID: Int,
        projectName: String,
        title: String,
        state: String,
        webUrl: String,
        authorName: String
    ) {
        self.mrID = mrID
        self.iid = iid
        self.projectID = projectID
        self.projectName = projectName
        self.title = title
        self.state = state
        self.webUrl = webUrl
        self.authorName = authorName
        self.lastSeenAt = .now
        self.sha = nil
        self.headPipelineStatus = nil
        self.approvedByUsernames = []
        self.detailedMergeStatus = nil
    }
}
