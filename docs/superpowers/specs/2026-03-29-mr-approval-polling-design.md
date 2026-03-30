# MR Approval & Activity Polling — Design Spec

**Date:** 2026-03-29
**Branch:** `feature/mr-approval-polling`
**Status:** Approved

---

## Problem

The current supplemental poll uses `scope=assigned_to_me` to discover merge requests. This misses the most important class of events: activity on MRs the user *authored*. Because GitLab authors rarely assign themselves, approvals, pipeline changes, new commits, and changes-requested on the user's own MRs are never detected.

Additionally, the Todos API (primary poll) does not surface approvals at all — GitLab does not create a todo when a teammate approves your MR.

**Four gaps to close:**

| Event | Why current approach misses it |
|---|---|
| Someone approved your MR | Todos API never creates a todo for this |
| Someone requested changes on your MR | Todos API never creates a todo for this |
| New commits pushed to an MR you're reviewing | `assigned_to_me` scope excludes reviewed MRs |
| Pipeline status changed on your MR | `assigned_to_me` scope excludes authored MRs |

---

## Approach

**Snapshot-diff engine.** The supplemental poll discovers all MRs the user is involved in across three scopes, stores a snapshot of key fields per MR, and on each poll computes a diff to emit typed notifications for any change.

---

## Section 1: Architecture

The supplemental poll becomes a two-phase operation:

### Phase 1 — Discovery
Fetch open MRs across three scopes, deduplicate by `id`:

- `scope=created_by_me` — MRs the user authored
- `scope=assigned_to_me` — MRs assigned to the user
- `scope=reviews_for_me` — MRs where the user is a reviewer

### Phase 2 — Diff loop
For each MR in the watched set, fetch detail + approvals concurrently, compare against the stored snapshot, emit notifications for any signal that changed:

| Signal | Source | Notification type |
|---|---|---|
| `sha` changed | MR detail | `.newCommitsPushed` |
| `head_pipeline.status` changed to `"failed"` | MR detail | `.pipelineFailed` |
| `head_pipeline.status` changed to `"success"` (was `"failed"`/`"running"`) | MR detail | `.pipelinePassed` |
| New username in `approved_by[]` | Approvals endpoint | `.approved` |
| System note body contains `"requested changes"` | Notes endpoint | `.changesRequested` |

**API call budget:** 3 discovery calls + 2 per tracked MR (detail + approvals). At 20 MRs: ~43 calls per 2-minute cycle — well within GitLab's rate limits.

`pollNotes` continues to run after `pollTrackedMRs` and handles:
- New non-system comments → `.comment`
- Edited comments → `.commentEdited`
- System notes matching `"requested changes"` → `.changesRequested` with the reviewer's name as sender

---

## Section 2: Data Model

### `TrackedMergeRequest` additions

Four new fields added to the existing SwiftData model. All use optional/default values — SwiftData lightweight migration handles this without an explicit migration plan.

```swift
var sha: String?                  // HEAD commit SHA
var headPipelineStatus: String?   // "success" | "failed" | "running" | etc.
var approvedByUsernames: [String] // usernames of approvers, default []
var detailedMergeStatus: String?  // e.g. "requested_changes", "mergeable", etc.
```

**Deduplication:** `mrID: Int` is already `@Attribute(.unique)` — re-fetching an MR across multiple scopes safely upserts.

**TTL:** unchanged — records older than 7 days are cleaned up by the existing `cleanupOldRecords()` method.

### New REST decodable types (`GitLabAPITypes.swift`)

```swift
struct RESTMRApprovals: Decodable {
    let approvedBy: [RESTApprover]
    enum CodingKeys: String, CodingKey {
        case approvedBy = "approved_by"
    }
}

struct RESTApprover: Decodable {
    let user: RESTUser
}

struct RESTHeadPipeline: Decodable {
    let status: String
}
```

### `RESTMergeRequest` additions

Three new optional fields decoded from the MR detail response:

```swift
let sha: String?
let detailedMergeStatus: String?
let headPipeline: RESTHeadPipeline?

// CodingKeys additions:
// "detailed_merge_status", "head_pipeline"
```

### New `NotificationType` case

```swift
case pipelinePassed   // defaultEnabled = false (opt-in, to avoid noise)
```

---

## Section 3: API Layer (`GitLabService`)

### Replaced method

`fetchAssignedMergeRequests(token:updatedAfter:)` is removed and replaced with:

```swift
func fetchMergeRequests(
    token: String,
    scope: String,           // "created_by_me" | "assigned_to_me" | "reviews_for_me"
    state: String = "opened",
    updatedAfter: Date? = nil
) async throws -> [RESTMergeRequest]
// GET /api/v4/merge_requests?scope=:scope&state=:state
```

### New methods

```swift
func fetchMRDetail(
    token: String,
    projectID: Int,
    mrIID: Int
) async throws -> RESTMergeRequest
// GET /api/v4/projects/:id/merge_requests/:iid

func fetchMRApprovals(
    token: String,
    projectID: Int,
    mrIID: Int
) async throws -> RESTMRApprovals
// GET /api/v4/projects/:id/merge_requests/:iid/approvals
```

---

## Section 4: `PollCoordinator` Diffing Logic

### `pollMRStates` → `pollTrackedMRs`

```
1. Fetch 3 scopes sequentially → deduplicate by mr.id → watchedMRs

2. For each mr in watchedMRs:
     async let detail   = fetchMRDetail(projectID: mr.projectId, mrIID: mr.iid)
     async let approvals = fetchMRApprovals(projectID: mr.projectId, mrIID: mr.iid)

     diff against TrackedMergeRequest snapshot:

     if detail.sha != snapshot.sha && snapshot.sha != nil:
         → emit .newCommitsPushed

     if detail.headPipeline?.status != snapshot.headPipelineStatus:
         let new = detail.headPipeline?.status
         if new == "failed":
             → emit .pipelineFailed
         if new == "success" && snapshot.headPipelineStatus != "success":
             → emit .pipelinePassed

     let newApprovers = approvals.approvedBy.map(\.user.username)
                            .filter { !snapshot.approvedByUsernames.contains($0) }
     for approver in newApprovers:
         → emit .approved (sender = approver)

     // detailedMergeStatus stored in snapshot for reference.
     // .changesRequested is fired exclusively from pollNotes (system note parsing)
     // so we don't double-fire.

     upsert snapshot with new sha, pipelineStatus, approvedByUsernames, detailedMergeStatus
```

### `pollNotes` extension

Extend the existing system note skip (`!note.system`) to also process specific system notes:

```
For each system note (note.system == true) newer than lastNoteID:
    // NOTE: matches English GitLab system note wording.
    // Update this string if GitLab changes the copy.
    if note.body.lowercased().contains("requested changes"):
        → emit .changesRequested (sender = note.author.name)
```

Non-system note handling (`.comment`, `.commentEdited`) is unchanged.

**Single source of truth:** `.changesRequested` is only ever emitted from `pollNotes`. `pollTrackedMRs` stores `detailedMergeStatus` in the snapshot but does not emit a notification for it.

---

## Section 5: Feature Branch & Delivery

**Branch:** `feature/mr-approval-polling`

### Commit order

1. `feat: extend TrackedMergeRequest with sha/pipeline/approvals/detailedMergeStatus fields`
2. `feat: add pipelinePassed NotificationType`
3. `feat: generalise fetchMergeRequests + add fetchMRDetail/fetchMRApprovals to GitLabService`
4. `feat: replace pollMRStates with snapshot-diff pollTrackedMRs in PollCoordinator`
5. `feat: extend pollNotes to detect changesRequested from system notes`
6. `test: unit tests for snapshot diffing logic and system note parsing`

### Testing

- **Unit tests:** inject a `TrackedMergeRequest` snapshot + `RESTMergeRequest` + `RESTMRApprovals` and assert the correct `[NotificationType]` array is produced for each diff scenario
- **Notes unit test:** assert system note with body `"requested changes on this merge request"` produces `.changesRequested` with correct sender
- **Manual smoke test:** open an MR, have a teammate approve → notification fires within ~2 min supplemental cycle

### Known limitations

- `reviews_for_me` new-commit notifications may be noisy for busy review queues. Left as a `// TODO: make configurable` in `PollCoordinator`.
- System note text matching for changesRequested is English-only and tied to GitLab's current copy. Documented in code with the matching string isolated for easy update.

---

## Out of Scope

- Configurable per-scope notification filtering (future settings tab addition)
- `pipelinePassed` enabled by default (opt-in only)
- Self-hosted GitLab locale variants for system note parsing
