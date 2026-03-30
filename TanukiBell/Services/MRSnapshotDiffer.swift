import Foundation

/// Value-type snapshot used for diffing. Copied from SwiftData model fields before comparison.
struct MRSnapshot {
    let sha: String?
    let headPipelineStatus: String?
    let approvedByUsernames: [String]
}

/// Output events produced by a single diff cycle.
enum MRDiffEvent: Equatable {
    case newCommitsPushed
    case pipelineFailed
    case pipelinePassed
    case approved(byUsername: String)
}

/// Pure snapshot-diff logic. No SwiftData, no async, no side effects.
enum MRSnapshotDiffer {

    /// Compare `current` MR state against `snapshot` and return events for anything that changed.
    /// Returns an empty array on first encounter (when `snapshot.sha == nil`).
    static func diff(
        current: RESTMergeRequest,
        approvals: RESTMRApprovals,
        snapshot: MRSnapshot
    ) -> [MRDiffEvent] {
        // First encounter — no previous snapshot to diff against.
        guard snapshot.sha != nil else { return [] }

        var events: [MRDiffEvent] = []

        // New commits: SHA changed.
        if let currentSHA = current.sha, currentSHA != snapshot.sha {
            events.append(.newCommitsPushed)
        }

        // Pipeline status changed.
        if let currentStatus = current.headPipeline?.status,
           currentStatus != snapshot.headPipelineStatus {
            switch currentStatus {
            case "failed":
                events.append(.pipelineFailed)
            case "success":
                events.append(.pipelinePassed)
            default:
                break
            }
        }

        // New approvers.
        let currentApprovers = approvals.approvedBy.map(\.user.username)
        let newApprovers = currentApprovers.filter { !snapshot.approvedByUsernames.contains($0) }
        events.append(contentsOf: newApprovers.map { .approved(byUsername: $0) })

        return events
    }
}
