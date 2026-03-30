# MR Approval & Activity Polling — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the supplemental poll to detect approvals, pipeline changes, new commits, and changes-requested across all MRs the user authored, is assigned to, or is reviewing.

**Architecture:** A snapshot-diff engine stores key fields (SHA, pipeline status, approvers) per tracked MR in SwiftData. On each supplemental cycle, three REST list calls discover the full watched set; per-MR detail + approvals calls produce a diff against the stored snapshot. Pure diff logic and system note parsing are extracted into separate value-type structs for testability.

**Tech Stack:** Swift 6, SwiftData, XCTest, GitLab REST API v4, XcodeGen

---

## Chunk 1: Data Model

### Task 1: Extend `TrackedMergeRequest` with snapshot fields

**Files:**
- Modify: `TanukiBell/Models/TrackedMergeRequest.swift`

- [ ] **Step 1: Add four new fields to `TrackedMergeRequest`**

Open `TanukiBell/Models/TrackedMergeRequest.swift`. After the existing `var lastNoteID: Int?` line, add:

```swift
    // Snapshot fields for diff-based event detection (added v0.1.2)
    var sha: String?
    var headPipelineStatus: String?
    var approvedByUsernames: [String]
    var detailedMergeStatus: String?
```

Then update `init` to include defaults for the new fields. Add after `self.lastSeenAt = .now`:

```swift
        self.sha = nil
        self.headPipelineStatus = nil
        self.approvedByUsernames = []
        self.detailedMergeStatus = nil
```

Full updated file should look like:

```swift
import SwiftData
import Foundation

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
```

- [ ] **Step 2: Verify build passes (no test run needed yet — logic unchanged)**

```bash
cd /Users/danielkuhlwein/Developer/tanuki-bell
xcodegen generate && xcodebuild build -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add TanukiBell/Models/TrackedMergeRequest.swift
git commit -m "feat: extend TrackedMergeRequest with sha/pipeline/approvals snapshot fields"
```

---

### Task 2: Add `pipelinePassed` to `NotificationType`

**Files:**
- Modify: `TanukiBell/Models/NotificationType.swift`

- [ ] **Step 1: Add `.pipelinePassed` case**

In `TanukiBell/Models/NotificationType.swift`, add `case pipelinePassed` after `case pipelineFailed`. Then add the corresponding entries to every switch:

```swift
// In the enum body — add after pipelineFailed:
case pipelinePassed

// displayTitle:
case .pipelinePassed: return "Pipeline Passed"

// priority:
case .pipelinePassed: return 3

// defaultEnabled — opt-in only:
case .pipelinePassed: return false

// iconAssetName — reuse success icon:
case .pipelinePassed: return "PR_Merged"
```

Full updated `NotificationType.swift`:

```swift
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
    case pipelinePassed
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
        case .pipelinePassed:     return "Pipeline Passed"
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
        case .pipelinePassed:     return 3
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
        case .prActivity, .newCommitsPushed, .pipelinePassed: return false
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
        case .pipelinePassed:     return "PR_Merged"
        case .newCommitsPushed:   return "New_Commits_Pushed"
        case .prActivity:         return "PR_Activity"
        }
    }

    var iconImage: NSImage? {
        NSImage(named: iconAssetName)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodegen generate && xcodebuild build -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add TanukiBell/Models/NotificationType.swift
git commit -m "feat: add pipelinePassed NotificationType (opt-in, default disabled)"
```

---

### Task 3: Extend `GitLabAPITypes.swift` with new REST types

**Files:**
- Modify: `TanukiBell/Models/GitLabAPITypes.swift`

- [ ] **Step 1: Add `RESTMRApprovals`, `RESTApprover`, `RESTHeadPipeline`**

Append to the bottom of `TanukiBell/Models/GitLabAPITypes.swift` (after the existing `RESTUser` struct):

```swift
// MARK: - MR approvals

struct RESTMRApprovals: Decodable {
    let approvedBy: [RESTApprover]

    enum CodingKeys: String, CodingKey {
        case approvedBy = "approved_by"
    }
}

struct RESTApprover: Decodable {
    let user: RESTUser
}

// MARK: - Head pipeline

struct RESTHeadPipeline: Decodable {
    let status: String
}
```

- [ ] **Step 2: Extend `RESTMergeRequest` with new optional fields**

In the existing `RESTMergeRequest` struct, add three new optional stored properties and their coding keys:

```swift
struct RESTMergeRequest: Decodable, Identifiable {
    let id: Int
    let iid: Int
    let title: String
    let state: String
    let webUrl: String
    let author: RESTUser?
    let projectId: Int
    let sha: String?
    let detailedMergeStatus: String?
    let headPipeline: RESTHeadPipeline?

    enum CodingKeys: String, CodingKey {
        case id, iid, title, state, sha
        case webUrl = "web_url"
        case author
        case projectId = "project_id"
        case detailedMergeStatus = "detailed_merge_status"
        case headPipeline = "head_pipeline"
    }
}
```

- [ ] **Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild build -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add TanukiBell/Models/GitLabAPITypes.swift
git commit -m "feat: add RESTMRApprovals/RESTHeadPipeline types, extend RESTMergeRequest"
```

---

## Chunk 2: API Layer

### Task 4: Refactor and extend `GitLabService`

**Files:**
- Modify: `TanukiBell/Services/GitLabService.swift`

- [ ] **Step 1: Replace `fetchAssignedMergeRequests` with generic `fetchMergeRequests`**

Remove the existing `fetchAssignedMergeRequests(token:updatedAfter:)` method entirely and replace it with:

```swift
// MARK: - MR list (multi-scope discovery)

func fetchMergeRequests(
    token: String,
    scope: String,
    state: String = "opened",
    updatedAfter: Date? = nil
) async throws -> [RESTMergeRequest] {
    var components = URLComponents(
        url: baseURL.appendingPathComponent("api/v4/merge_requests"),
        resolvingAgainstBaseURL: false
    )!
    var queryItems: [URLQueryItem] = [
        URLQueryItem(name: "scope", value: scope),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "per_page", value: "50"),
    ]
    if let updatedAfter {
        queryItems.append(URLQueryItem(
            name: "updated_after",
            value: ISO8601DateFormatter().string(from: updatedAfter)
        ))
    }
    components.queryItems = queryItems

    var request = URLRequest(url: components.url!)
    request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GitLabServiceError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
        throw GitLabServiceError.httpError(httpResponse.statusCode)
    }
    return try JSONDecoder().decode([RESTMergeRequest].self, from: data)
}
```

- [ ] **Step 2: Add `fetchMRDetail`**

Append after `fetchMergeRequests`:

```swift
// MARK: - MR detail (single MR with sha/pipeline/reviewers)

func fetchMRDetail(
    token: String,
    projectID: Int,
    mrIID: Int
) async throws -> RESTMergeRequest {
    let path = "api/v4/projects/\(projectID)/merge_requests/\(mrIID)"
    let url = baseURL.appendingPathComponent(path)
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GitLabServiceError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
        throw GitLabServiceError.httpError(httpResponse.statusCode)
    }
    return try JSONDecoder().decode(RESTMergeRequest.self, from: data)
}
```

- [ ] **Step 3: Add `fetchMRApprovals`**

Append after `fetchMRDetail`:

```swift
// MARK: - MR approvals

func fetchMRApprovals(
    token: String,
    projectID: Int,
    mrIID: Int
) async throws -> RESTMRApprovals {
    let path = "api/v4/projects/\(projectID)/merge_requests/\(mrIID)/approvals"
    let url = baseURL.appendingPathComponent(path)
    var request = URLRequest(url: url)
    request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw GitLabServiceError.invalidResponse
    }
    guard httpResponse.statusCode == 200 else {
        throw GitLabServiceError.httpError(httpResponse.statusCode)
    }
    return try JSONDecoder().decode(RESTMRApprovals.self, from: data)
}
```

- [ ] **Step 4: Build to verify**

```bash
xcodegen generate && xcodebuild build -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD FAILED` — the only error should be `use of unresolved identifier 'fetchAssignedMergeRequests'` in `PollCoordinator.swift`. That compile error is intentional and is fixed in Task 7.

Any other errors indicate a problem with the new method signatures that must be resolved before continuing.

- [ ] **Step 5: Commit**

```bash
git add TanukiBell/Services/GitLabService.swift
git commit -m "feat: add fetchMergeRequests/fetchMRDetail/fetchMRApprovals, remove fetchAssignedMergeRequests"
```

---

## Chunk 3: Pure Logic + Tests

### Task 5: Create `MRSnapshotDiffer`

**Files:**
- Create: `TanukiBell/Services/MRSnapshotDiffer.swift`
- Create: `TanukiBellTests/MRSnapshotDifferTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `TanukiBellTests/MRSnapshotDifferTests.swift`:

```swift
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
            projectId: 42,
            sha: sha,
            detailedMergeStatus: detailedMergeStatus,
            headPipeline: pipelineStatus.map { RESTHeadPipeline(status: $0) }
        )
    }

    private func makeApprovals(_ usernames: [String]) -> RESTMRApprovals {
        RESTMRApprovals(approvedBy: usernames.map {
            RESTApprover(user: RESTUser(id: 0, name: $0, username: $0))
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
        XCTAssertTrue(events.contains(.approved(byUsername: "bob")))
    }

    func testExistingApproverDoesNotRefire() {
        let mr = makeMR()
        let approvals = makeApprovals(["bob"])
        let snapshot = makeSnapshot(approvedBy: ["bob"])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.approved(byUsername: "bob")))
    }

    func testMultipleNewApproversEmitMultipleEvents() {
        let mr = makeMR()
        let approvals = makeApprovals(["bob", "carol"])
        let snapshot = makeSnapshot(approvedBy: [])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertTrue(events.contains(.approved(byUsername: "bob")))
        XCTAssertTrue(events.contains(.approved(byUsername: "carol")))
    }

    func testPartialNewApproversOnlyEmitNew() {
        let mr = makeMR()
        let approvals = makeApprovals(["alice", "bob"])
        let snapshot = makeSnapshot(approvedBy: ["alice"])

        let events = MRSnapshotDiffer.diff(current: mr, approvals: approvals, snapshot: snapshot)
        XCTAssertFalse(events.contains(.approved(byUsername: "alice")))
        XCTAssertTrue(events.contains(.approved(byUsername: "bob")))
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
```

- [ ] **Step 2: Run tests — verify they fail with "cannot find type 'MRSnapshotDiffer'"**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|cannot find"
```

Expected: compile error `cannot find type 'MRSnapshotDiffer' in scope`

- [ ] **Step 3: Create `MRSnapshotDiffer.swift`**

Create `TanukiBell/Services/MRSnapshotDiffer.swift`:

```swift
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
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "MRSnapshotDiffer|error:|Test Suite.*passed|failed"
```

Expected: all `MRSnapshotDifferTests` pass

- [ ] **Step 5: Commit**

```bash
git add TanukiBell/Services/MRSnapshotDiffer.swift TanukiBellTests/MRSnapshotDifferTests.swift
git commit -m "feat: add MRSnapshotDiffer with full test coverage"
```

---

### Task 6: Create `SystemNoteParser`

**Files:**
- Create: `TanukiBell/Services/SystemNoteParser.swift`
- Create: `TanukiBellTests/SystemNoteParserTests.swift`

- [ ] **Step 1: Write the failing tests first**

Create `TanukiBellTests/SystemNoteParserTests.swift`:

```swift
import XCTest
@testable import TanukiBell

final class SystemNoteParserTests: XCTestCase {

    private func makeNote(
        id: Int,
        body: String,
        authorName: String = "Alice",
        system: Bool = true
    ) -> RESTNote {
        let now = Date()
        return RESTNote(
            id: id,
            body: body,
            author: RESTUser(id: 1, name: authorName, username: authorName.lowercased()),
            createdAt: now,
            updatedAt: now,
            system: system
        )
    }

    // MARK: - Changes-requested detection

    func testExactMatchDetected() {
        let notes = [makeNote(id: 1, body: "requested changes")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testLongerBodyContainingPhraseDetected() {
        let notes = [makeNote(id: 1, body: "requested changes on this merge request")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testCaseInsensitiveMatch() {
        let notes = [makeNote(id: 1, body: "Requested Changes")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result, ["Alice"])
    }

    func testNonMatchingSystemNoteIgnored() {
        let notes = [makeNote(id: 1, body: "approved this merge request")]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testNonSystemNoteIgnored() {
        let notes = [makeNote(id: 1, body: "requested changes", system: false)]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - lastNoteID watermark

    func testNoteAtOrBelowWatermarkSkipped() {
        let notes = [
            makeNote(id: 5, body: "requested changes", authorName: "Bob"),
            makeNote(id: 3, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: 4)
        XCTAssertEqual(result, ["Bob"])
        XCTAssertFalse(result.contains("Alice"))
    }

    func testNilWatermarkIncludesAllNotes() {
        let notes = [
            makeNote(id: 2, body: "requested changes", authorName: "Bob"),
            makeNote(id: 1, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertEqual(result.count, 2)
    }

    func testEmptyNotesReturnsEmpty() {
        let result = SystemNoteParser.changesRequestedAuthors(in: [], after: nil)
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleMatchingNotesReturnsAllAuthors() {
        let notes = [
            makeNote(id: 2, body: "requested changes", authorName: "Bob"),
            makeNote(id: 1, body: "requested changes", authorName: "Alice"),
        ]
        let result = SystemNoteParser.changesRequestedAuthors(in: notes, after: nil)
        XCTAssertTrue(result.contains("Bob"))
        XCTAssertTrue(result.contains("Alice"))
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "cannot find|SystemNoteParser"
```

Expected: compile error `cannot find type 'SystemNoteParser' in scope`

- [ ] **Step 3: Create `SystemNoteParser.swift`**

Create `TanukiBell/Services/SystemNoteParser.swift`:

```swift
import Foundation

/// Pure system note parsing logic. No SwiftData, no async, no side effects.
enum SystemNoteParser {

    // NOTE: Matches English GitLab system note wording.
    // GitLab writes "requested changes on this merge request" (or similar) when a reviewer
    // requests changes. This string is stable but could change on major GitLab versions.
    // Update this constant if the system note copy changes.
    static let changesRequestedPattern = "requested changes"

    /// Returns the author names of system notes that indicate a reviewer requested changes,
    /// filtered to only notes newer than `lastNoteID` (if provided).
    static func changesRequestedAuthors(
        in notes: [RESTNote],
        after lastNoteID: Int?
    ) -> [String] {
        notes
            .filter { note in
                guard note.system else { return false }
                if let lastID = lastNoteID, note.id <= lastID { return false }
                return note.body.lowercased().contains(changesRequestedPattern)
            }
            .map(\.author.name)
    }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "SystemNoteParser|error:|Test Suite.*passed|failed"
```

Expected: all `SystemNoteParserTests` pass

- [ ] **Step 5: Commit**

```bash
git add TanukiBell/Services/SystemNoteParser.swift TanukiBellTests/SystemNoteParserTests.swift
git commit -m "feat: add SystemNoteParser for changes-requested detection with full test coverage"
```

---

## Chunk 4: PollCoordinator Wiring

### Task 7: Replace `pollMRStates` with `pollTrackedMRs`

**Files:**
- Modify: `TanukiBell/Services/PollCoordinator.swift`

- [ ] **Step 1: Replace `pollMRStates` with `pollTrackedMRs`**

In `PollCoordinator.swift`, find the `pollSupplemental()` method and replace the `await pollMRStates(token: token)` call with `await pollTrackedMRs(token: token)`.

Then delete the entire `pollMRStates(token:)` method and replace it with `pollTrackedMRs(token:)`:

```swift
/// Discover all watched MRs across 3 scopes, diff snapshots, emit notifications.
private func pollTrackedMRs(token: String) async {
    do {
        // Phase 1: Discover watched MR set across all relevant scopes.
        // TODO: If any single scope returns a 403 (e.g. reviews_for_me on older GitLab tiers),
        // the entire try await will throw and all discovery is skipped.
        // Future improvement: fetch scopes independently and union the results so a partial
        // failure only loses one scope rather than the full watched set.
        async let authored = gitLabService.fetchMergeRequests(token: token, scope: "created_by_me")
        async let assigned = gitLabService.fetchMergeRequests(token: token, scope: "assigned_to_me")
        async let reviewing = gitLabService.fetchMergeRequests(token: token, scope: "reviews_for_me")

        let all = try await authored + assigned + reviewing
        // Deduplicate by MR id (same MR can appear in multiple scopes).
        var seen = Set<Int>()
        let unique = all.filter { seen.insert($0.id).inserted }

        print("[Supplemental] Watched MRs: \(unique.count) across created/assigned/reviewing scopes")

        // Phase 2: Diff each MR against its stored snapshot.
        for mr in unique {
            await diffAndNotify(mr: mr, token: token)
        }

    } catch {
        print("[Supplemental] MR discovery failed: \(error)")
    }
}

private func diffAndNotify(mr: RESTMergeRequest, token: String) async {
    do {
        async let detail = gitLabService.fetchMRDetail(token: token, projectID: mr.projectId, mrIID: mr.iid)
        async let approvals = gitLabService.fetchMRApprovals(token: token, projectID: mr.projectId, mrIID: mr.iid)

        let (currentDetail, currentApprovals) = try await (detail, approvals)

        let context = ModelContext(modelContainer)
        let mrID = mr.id
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            predicate: #Predicate { $0.mrID == mrID }
        )
        let existing = try context.fetch(descriptor).first

        // Build snapshot from stored record (or empty snapshot for first encounter).
        let snapshot = MRSnapshot(
            sha: existing?.sha,
            headPipelineStatus: existing?.headPipelineStatus,
            approvedByUsernames: existing?.approvedByUsernames ?? []
        )

        let events = MRSnapshotDiffer.diff(
            current: currentDetail,
            approvals: currentApprovals,
            snapshot: snapshot
        )

        // Resolve project name from stored record or fall back to ID.
        let projectName = existing?.projectName ?? "Project #\(mr.projectId)"

        for event in events {
            let notification = classifiedNotification(
                for: event,
                mr: currentDetail,
                projectName: projectName
            )
            print("[Supplemental] Diff event: \(event) on !\(mr.iid)")
            NotificationDispatcher.send(notification)
            persistNotificationRecord(notification)
        }

        // Upsert snapshot.
        if let tracked = existing {
            tracked.state = currentDetail.state
            tracked.sha = currentDetail.sha
            tracked.headPipelineStatus = currentDetail.headPipeline?.status
            tracked.approvedByUsernames = currentApprovals.approvedBy.map(\.user.username)
            tracked.detailedMergeStatus = currentDetail.detailedMergeStatus
            tracked.lastSeenAt = .now
        } else {
            let tracked = TrackedMergeRequest(
                mrID: mr.id,
                iid: mr.iid,
                projectID: mr.projectId,
                projectName: "Project #\(mr.projectId)",
                title: mr.title,
                state: mr.state,
                webUrl: mr.webUrl,
                authorName: mr.author?.name ?? "Unknown"
            )
            tracked.sha = currentDetail.sha
            tracked.headPipelineStatus = currentDetail.headPipeline?.status
            tracked.approvedByUsernames = currentApprovals.approvedBy.map(\.user.username)
            tracked.detailedMergeStatus = currentDetail.detailedMergeStatus
            context.insert(tracked)
        }
        try context.save()

    } catch {
        print("[Supplemental] Diff failed for MR !\(mr.iid): \(error)")
    }
}

private func classifiedNotification(
    for event: MRDiffEvent,
    mr: RESTMergeRequest,
    projectName: String
) -> ClassifiedNotification {
    let threadID = "gitlab-\(projectName)-!\(mr.iid)"

    switch event {
    case .newCommitsPushed:
        return ClassifiedNotification(
            type: .newCommitsPushed,
            title: "New Commits Pushed",
            projectName: projectName,
            mrTitle: mr.title,
            mrIID: mr.iid,
            sourceURL: URL(string: mr.webUrl),
            senderName: mr.author?.name ?? "Someone",
            senderAvatarURL: nil,
            threadID: threadID,
            notificationID: "commits-\(mr.id)-\(mr.sha ?? "")",
            gitlabTodoID: "",
            bodyExcerpt: nil
        )
    case .pipelineFailed:
        return ClassifiedNotification(
            type: .pipelineFailed,
            title: "Pipeline Failed",
            projectName: projectName,
            mrTitle: mr.title,
            mrIID: mr.iid,
            sourceURL: URL(string: mr.webUrl),
            senderName: mr.author?.name ?? "Someone",
            senderAvatarURL: nil,
            threadID: threadID,
            notificationID: "pipeline-failed-\(mr.id)",
            gitlabTodoID: "",
            bodyExcerpt: nil
        )
    case .pipelinePassed:
        return ClassifiedNotification(
            type: .pipelinePassed,
            title: "Pipeline Passed",
            projectName: projectName,
            mrTitle: mr.title,
            mrIID: mr.iid,
            sourceURL: URL(string: mr.webUrl),
            senderName: mr.author?.name ?? "Someone",
            senderAvatarURL: nil,
            threadID: threadID,
            notificationID: "pipeline-passed-\(mr.id)",
            gitlabTodoID: "",
            bodyExcerpt: nil
        )
    case .approved(let byUsername):
        return ClassifiedNotification(
            type: .approved,
            title: "Approved by \(NotificationClassifier.abbreviateName(byUsername))",
            projectName: projectName,
            mrTitle: mr.title,
            mrIID: mr.iid,
            sourceURL: URL(string: mr.webUrl),
            senderName: byUsername,
            senderAvatarURL: nil,
            threadID: threadID,
            notificationID: "approved-\(mr.id)-\(byUsername)",
            gitlabTodoID: "",
            bodyExcerpt: nil
        )
    }
}
```

- [ ] **Step 2: Remove `detectMRTransition(_:)` (now unused)**

In `PollCoordinator.swift`, delete the entire `detectMRTransition(_:)` method. It was only ever called from the old `pollMRStates` method which was removed in Step 1.

Search for `private func detectMRTransition` and delete the entire method body (from the `private func` line through its closing `}`).

- [ ] **Step 3: Build to verify**

```bash
xcodegen generate && xcodebuild build -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Run all tests**

```bash
xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: all suites pass

- [ ] **Step 5: Commit**

```bash
git add TanukiBell/Services/PollCoordinator.swift
git commit -m "feat: replace pollMRStates with snapshot-diff pollTrackedMRs covering 3 scopes"
```

---

### Task 8: Extend `pollNotes` for system note parsing

**Files:**
- Modify: `TanukiBell/Services/PollCoordinator.swift`

- [ ] **Step 1: Confirm existing `pollNotes` scope, then extend it**

First, open `PollCoordinator.swift` and read the `for note in notes where !note.system` loop in `pollNotes`. Confirm it **only** contains an `if note.isEdited { ... }` branch (`.commentEdited`) — there is no `else` branch and no separate block handling `.comment` new-comment notifications. (Verified in source: new-comment `.comment` notifications are not currently emitted from `pollNotes`.)

The current inner loop looks like:

```swift
for note in notes where !note.system {
    if let lastID = snap.lastNoteID, note.id <= lastID { continue }
    // ... commentEdited handling only — no .comment branch
}
```

Replace the entire `for note in notes` loop (plus add the system note block below it) with:

```swift
// Process non-system notes (new comments, edited comments).
for note in notes where !note.system {
    if let lastID = snap.lastNoteID, note.id <= lastID { continue }

    if note.isEdited {
        let shortName = NotificationClassifier.abbreviateName(note.author.name)
        let notification = ClassifiedNotification(
            type: .commentEdited,
            title: "Comment Edited by \(shortName)",
            projectName: snap.projectName,
            mrTitle: snap.title,
            mrIID: snap.iid,
            sourceURL: URL(string: snap.webUrl),
            senderName: note.author.name,
            senderAvatarURL: nil,
            threadID: "gitlab-\(snap.projectName)-!\(snap.iid)",
            notificationID: "note-edited-\(note.id)",
            gitlabTodoID: "",
            bodyExcerpt: note.body
        )
        NotificationDispatcher.send(notification)
        persistNotificationRecord(notification)
    }
}

// Process system notes for changes-requested events.
let changesRequestedAuthors = SystemNoteParser.changesRequestedAuthors(
    in: notes,
    after: snap.lastNoteID
)
for authorName in changesRequestedAuthors {
    let shortName = NotificationClassifier.abbreviateName(authorName)
    let notification = ClassifiedNotification(
        type: .changesRequested,
        title: "Changes Requested by \(shortName)",
        projectName: snap.projectName,
        mrTitle: snap.title,
        mrIID: snap.iid,
        sourceURL: URL(string: snap.webUrl),
        senderName: authorName,
        senderAvatarURL: nil,
        threadID: "gitlab-\(snap.projectName)-!\(snap.iid)",
        notificationID: "changes-requested-\(snap.mrID)-\(authorName)",
        gitlabTodoID: "",
        bodyExcerpt: nil
    )
    print("[Supplemental] Changes requested by \(shortName) on !\(snap.iid)")
    NotificationDispatcher.send(notification)
    persistNotificationRecord(notification)
}
```

- [ ] **Step 2: Build and run all tests**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: all test suites pass, `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add TanukiBell/Services/PollCoordinator.swift
git commit -m "feat: extend pollNotes with system note parsing for changesRequested detection"
```

---

### Task 9: Final verification and push

- [ ] **Step 1: Run full test suite one last time**

```bash
xcodegen generate && xcodebuild test -project TanukiBell.xcodeproj -scheme TanukiBell -destination 'platform=macOS,name=My Mac' 2>&1 | grep -E "Test Suite|passed|failed|error:"
```

Expected: all suites pass with 0 failures

- [ ] **Step 2: Push feature branch**

```bash
git push -u origin feature/mr-approval-polling
```

- [ ] **Step 3: Manual smoke test checklist**

After building and running the app locally:

1. Open the app with a valid GitLab PAT configured
2. Open an MR you authored in a browser — have a teammate (or second account) click **Approve**
3. Wait up to 2 minutes — a notification "Approved by [Name]" should appear
4. Push a new commit to the MR branch — wait up to 2 minutes — "New Commits Pushed" notification should appear
5. Check the menu bar popover — both notifications should appear in the "New" section
6. Verify no duplicate notifications fire on subsequent polls (snapshot updated correctly)
