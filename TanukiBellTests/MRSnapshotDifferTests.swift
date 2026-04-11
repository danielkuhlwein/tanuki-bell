import XCTest
@testable import TanukiBell

final class MRSnapshotDifferTests: XCTestCase {

    // MARK: - Helpers

    private func makeMR(
        sha: String? = "abc123",
        pipelineStatus: String? = nil,
        detailedMergeStatus: String? = "mergeable"
    ) -> RESTMergeRequest {
        RESTMergeRequest(
            id: 1, iid: 1, title: "Test MR", state: "opened",
            webUrl: "https://gitlab.com/test/-/merge_requests/1",
            author: RESTUser(id: 1, name: "Alice", username: "alice"),
            mergeUser: nil,
            mergedBy: nil,
            closedBy: nil,
            projectId: 42,
            sha: sha,
            detailedMergeStatus: detailedMergeStatus,
            headPipeline: pipelineStatus.map { RESTHeadPipeline(status: $0) }
        )
    }

    private func makeApprovals(_ usernames: [String]) -> RESTMRApprovals {
        RESTMRApprovals(approvedBy: usernames.map {
            RESTApprover(user: RESTUser(id: 0, name: "\($0)-display", username: $0))
        })
    }

    private func makeSnapshot(
        sha: String? = "abc123",
        pipelineStatus: String? = nil,
        approvedBy: [String] = []
    ) -> MRSnapshot {
        MRSnapshot(sha: sha, headPipelineStatus: pipelineStatus, approvedByUsernames: approvedBy)
    }

    // MARK: - First encounter (nil sha in snapshot)

    func testFirstEncounterEmitsNoEvents() {
        let mr = makeMR(sha: "abc123")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(sha: nil)

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.isEmpty, "First encounter should emit no events")
    }

    func testFirstEncounterWithApprovalsEmitsNoEvents() {
        let mr = makeMR(sha: "abc123")
        let approvals = makeApprovals(["bob"])
        let snapshot = makeSnapshot(sha: nil)

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.isEmpty, "First encounter should not emit approval events")
    }

    // MARK: - New commits

    func testSHAChangedEmitsNewCommitsPushed() {
        let mr = makeMR(sha: "def456")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(sha: "abc123")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.newCommitsPushed))
    }

    func testSHAUnchangedEmitsNoCommitEvent() {
        let mr = makeMR(sha: "abc123")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(sha: "abc123")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.newCommitsPushed))
    }

    // MARK: - Pipeline

    func testPipelineChangedToFailedEmitsPipelineFailed() {
        let mr = makeMR(pipelineStatus: "failed")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(pipelineStatus: "running")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.pipelineFailed))
    }

    func testPipelineChangedToSuccessEmitsPipelinePassed() {
        let mr = makeMR(pipelineStatus: "success")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(pipelineStatus: "running")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.pipelinePassed))
    }

    func testPipelineAlreadySuccessDoesNotRefire() {
        let mr = makeMR(pipelineStatus: "success")
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(pipelineStatus: "success")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.pipelinePassed))
    }

    func testPipelineNilDoesNotEmit() {
        let mr = makeMR(pipelineStatus: nil)
        let approvals = makeApprovals([])
        let snapshot = makeSnapshot(pipelineStatus: "running")

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.pipelineFailed))
        XCTAssertFalse(events.contains(.pipelinePassed))
    }

    // MARK: - Approvals

    func testNewApproverEmitsApprovedEvent() {
        let mr = makeMR()
        let approvals = makeApprovals(["bob"])
        let snapshot = makeSnapshot(approvedBy: [])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.approved(byUsername: "bob", displayName: "bob-display")))
    }

    func testExistingApproverDoesNotRefire() {
        let mr = makeMR()
        let approvals = makeApprovals(["bob"])
        let snapshot = makeSnapshot(approvedBy: ["bob"])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.approved(byUsername: "bob", displayName: "bob-display")))
    }

    func testMultipleNewApproversEmitMultipleEvents() {
        let mr = makeMR()
        let approvals = makeApprovals(["bob", "carol"])
        let snapshot = makeSnapshot(approvedBy: [])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.approved(byUsername: "bob", displayName: "bob-display")))
        XCTAssertTrue(events.contains(.approved(byUsername: "carol", displayName: "carol-display")))
    }

    func testPartialNewApproversOnlyEmitNew() {
        let mr = makeMR()
        let approvals = makeApprovals(["alice", "bob"])
        let snapshot = makeSnapshot(approvedBy: ["alice"])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.approved(byUsername: "alice", displayName: "alice-display")))
        XCTAssertTrue(events.contains(.approved(byUsername: "bob", displayName: "bob-display")))
    }

    // MARK: - No spurious events

    func testNoChangeEmitsNoEvents() {
        let mr = makeMR(sha: "abc123", pipelineStatus: "success")
        let approvals = makeApprovals(["alice"])
        let snapshot = makeSnapshot(sha: "abc123", pipelineStatus: "success", approvedBy: ["alice"])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.isEmpty)
    }
}
