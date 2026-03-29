import AppKit

enum NotificationType: String, CaseIterable, Codable {
    case reviewRequested
    case reReviewRequested
    case assigned
    case reassigned
    case changesRequested
    case comment
    case commentEdited
    case approved
    case merged
    case closed
    case mentioned
    case pipelineFailed
    case newCommitsPushed
    case prActivity

    var displayTitle: String {
        switch self {
        case .reviewRequested:    return "Review Requested"
        case .reReviewRequested:  return "Re-Review Requested"
        case .assigned:           return "Assigned to You"
        case .reassigned:         return "Reassigned"
        case .changesRequested:   return "Changes Requested"
        case .comment:            return "New Comment"
        case .commentEdited:      return "Comment Edited"
        case .approved:           return "Approved"
        case .merged:             return "Merged"
        case .closed:             return "Closed"
        case .mentioned:          return "Mentioned"
        case .pipelineFailed:     return "Pipeline Failed"
        case .newCommitsPushed:   return "New Commits Pushed"
        case .prActivity:         return "MR Activity"
        }
    }

    var priority: Int {
        switch self {
        case .reviewRequested:    return 1
        case .reReviewRequested:  return 1
        case .assigned:           return 2
        case .changesRequested:   return 2
        case .pipelineFailed:     return 2
        case .mentioned:          return 3
        case .approved:           return 3
        case .merged:             return 3
        case .comment:            return 4
        case .closed:             return 4
        case .commentEdited:      return 5
        case .reassigned:         return 5
        case .newCommitsPushed:   return 6
        case .prActivity:         return 7
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .prActivity, .newCommitsPushed: return false
        default: return true
        }
    }

    var iconAssetName: String {
        switch self {
        case .reviewRequested:    return "Review_Requested"
        case .reReviewRequested:  return "Re-Review_Requested"
        case .assigned:           return "PR_Assigned_to_You"
        case .reassigned:         return "PR_Reassigned"
        case .changesRequested:   return "Changes_Requested"
        case .comment:            return "New_Comment"
        case .commentEdited:      return "Comment_Edited"
        case .approved:           return "PR_Approved"
        case .merged:             return "PR_Merged"
        case .closed:             return "PR_Closed"
        case .mentioned:          return "You_Were_Mentioned"
        case .pipelineFailed:     return "PR_Closed"
        case .newCommitsPushed:   return "New_Commits_Pushed"
        case .prActivity:         return "PR_Activity"
        }
    }

    var iconImage: NSImage? {
        NSImage(named: iconAssetName)
    }
}
