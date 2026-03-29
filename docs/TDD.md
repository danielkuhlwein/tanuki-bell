# GitLab Notifier for macOS: Technical Design Document

**Version:** 1.0 draft
**Date:** 2026-03-28
**Status:** Proposal

---

## 1. Overview

GitLab Notifier is a native macOS menu bar app that monitors GitLab for merge request activity and delivers classified, actionable native notifications. It replaces an existing multi-component system (AppleScript + Python + Swift helper + launchd + shell scripts) with a single SwiftUI application.

### 1.1 Goals

- **Single installable app** (no scripts, no LaunchAgent plists, no `install.sh`)
- **No Apple Mail dependency** (connect directly to GitLab via GraphQL API)
- **Rich native notifications** (per-MR grouping, click-to-open, action buttons)
- **Zero-config persistence** (auto-launch at login, menu bar presence, no Dock icon)
- **Distributable** (ad-hoc signed with Sparkle auto-updates; Developer ID signing as a future upgrade)

### 1.2 Non-goals (v1)

- iOS/watchOS companion apps
- Support for GitHub, Bitbucket, or other Git platforms
- Webhook reception (requires server infrastructure)
- Self-hosted GitLab instances with custom CAs (stretch goal for v1.1)

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    GitLabNotifier.app                    │
│                                                         │
│  ┌──────────┐   ┌──────────────┐   ┌────────────────┐  │
│  │ Settings │   │  Menu Bar    │   │  Notification  │  │
│  │  View    │   │  Popover     │   │    History     │  │
│  │ (SwiftUI)│   │  (SwiftUI)   │   │   (SwiftUI)   │  │
│  └────┬─────┘   └──────┬───────┘   └───────┬────────┘  │
│       │                │                    │           │
│  ─────┴────────────────┴────────────────────┴────────── │
│                    SwiftUI / SwiftData                   │
│  ─────────────────────────────────────────────────────── │
│                                                         │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │   Poll     │  │ Notification│  │   GitLab API     │  │
│  │ Coordinator│  │ Classifier  │  │    Service       │  │
│  │  (actor)   │→ │  (struct)   │→ │ (async, GraphQL) │  │
│  └────────────┘  └─────────────┘  └──────────────────┘  │
│                                                         │
│  ┌────────────┐  ┌─────────────┐  ┌──────────────────┐  │
│  │ Notification│  │  Keychain   │  │   SwiftData     │  │
│  │ Dispatcher │  │   Store     │  │   (state, hist) │  │
│  │(UNCenter)  │  │  (Security) │  │                  │  │
│  └────────────┘  └─────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.1 Component responsibilities

| Component | Responsibility |
|---|---|
| **GitLabService** | Async GraphQL/REST client. Owns URLSession, ETag caching, auth headers. |
| **PollCoordinator** | Actor. Manages poll timer, adaptive intervals, cancellation. |
| **NotificationClassifier** | Pure function. Maps GitLab todo `action_name` + MR state to one of 12 notification types. |
| **NotificationDispatcher** | Wraps `UNUserNotificationCenter`. Registers categories/actions, sends notifications, handles responses. |
| **KeychainStore** | Reads/writes GitLab PAT (and future OAuth2 refresh tokens) via Security framework. |
| **SwiftData layer** | Persists processed todo IDs, notification history, poll timestamps. |
| **MenuBarExtra** | SwiftUI popover showing pending reviews, recent notifications, quick actions. |
| **SettingsView** | SwiftUI settings window (GitLab URL, token, polling interval, notification preferences). |

---

## 3. Data flow

### 3.1 Poll cycle (every 30s)

```
PollCoordinator (timer fires)
    │
    ├─→ GitLabService.fetchPendingTodos()
    │       │
    │       ├─ POST /api/graphql  (with If-None-Match ETag)
    │       │   → 304: no changes, skip cycle
    │       │   → 200: parse TodoConnection JSON
    │       │
    │       └─→ returns [GitLabTodo]
    │
    ├─→ SwiftData: filter out already-processed todo IDs
    │       → returns [GitLabTodo] (new only)
    │
    ├─→ NotificationClassifier.classify(todo:)
    │       → returns NotificationType enum + metadata
    │
    ├─→ NotificationDispatcher.send(classification:)
    │       │
    │       ├─ Build UNMutableNotificationContent
    │       │   (title, subtitle, body, threadIdentifier, categoryIdentifier, userInfo)
    │       ├─ UNUserNotificationCenter.add(request)
    │       └─ Update menu bar badge count
    │
    └─→ SwiftData: mark todo IDs as processed, save NotificationRecord
```

### 3.2 Supplemental polls

The Todos API covers ~80% of notification types. Two supplemental polls (lower frequency, every 2-5 minutes) fill the gaps:

- **MR State Poll** (`GET /merge_requests?scope=assigned_to_me&state=all&updated_after=<timestamp>` detects merged/closed transitions not represented in todos.)
- **Notes Poll** (`GET /projects/:id/merge_requests/:iid/notes?sort=desc&per_page=5` detects edited comments (where `updated_at > created_at`) on MRs the user is involved in.)

---

## 4. GitLab API integration

### 4.1 Authentication

**v1: Personal Access Token (PAT)**
- User generates a **legacy** PAT in GitLab UI (Profile → Access Tokens)
- Required scope: **`read_api`** (grants read access to GraphQL and REST APIs, including todos, merge requests, notes, and user profile)
- `read_api` is the minimum scope that covers all v1 functionality (polling, classification, notifications)
- App stores the token in Keychain via `SecItemAdd` with `kSecAttrService: "com.danielkuhlwein.tanuki-bell"` and `kSecAttrAccount: "pat"`
- Every API request includes `PRIVATE-TOKEN: <PAT>` header (not `Authorization: Bearer`, which is for OAuth2 tokens)

**v2 (future): OAuth2 Device Authorization Grant**
- Available since GitLab 17.9 (GA)
- Uses `ASWebAuthenticationSession` for the browser-based flow
- Stores refresh token in Keychain, auto-refreshes access token

### 4.2 Primary GraphQL query

```graphql
query PendingTodos($after: String) {
  currentUser {
    todos(state: pending, first: 50, after: $after) {
      nodes {
        id
        action
        body
        createdAt
        target {
          ... on MergeRequest {
            iid
            title
            state
            webUrl
            draft
            headPipeline { status }
            author { name username avatarUrl }
            reviewers { nodes { name username } }
            project { name fullPath }
          }
        }
        author { name username avatarUrl }
        project { name fullPath }
      }
      pageInfo { endCursor hasNextPage }
    }
  }
}
```

### 4.3 Notification type mapping

| Notification type | GitLab todo `action` | Supplemental source |
|---|---|---|
| Review Requested | `review_requested` | — |
| Re-Review Requested | — | MR reviewer list diff between polls |
| PR Assigned to You | `assigned` | — |
| PR Reassigned | — | MR assignee list diff between polls |
| Changes Requested | — | Unresolved review threads (Discussions API) |
| New Comment | `mentioned`, `directly_addressed` | Notes API (`created_at` == `updated_at`) |
| Comment Edited | — | Notes API (`updated_at` > `created_at`) |
| PR Approved | `approval_required` | MR approvals endpoint |
| PR Merged | `merge_train_removed` | MR state poll (`state == "merged"`) |
| PR Closed | — | MR state poll (`state == "closed"`) |
| You Were Mentioned | `mentioned`, `directly_addressed` | — |
| Pipeline Failed | `build_failed` | — |

### 4.4 Rate limits and efficiency

- GitLab.com: 2,000 authenticated requests/minute
- Primary poll (30s) = 2 req/min = **0.1% of limit**
- Supplemental polls (120s) = ~1 req/min additional
- **ETag caching**: send `If-None-Match` header; `304 Not Modified` responses count toward rate limit but return no body (fast, low bandwidth))
- **Adaptive polling**: 30s when user active, 120s when idle (no mouse/keyboard for 5 min), 300s when screen locked)

---

## 5. Data models

### 5.1 SwiftData models

```swift
@Model
final class ProcessedTodo {
    @Attribute(.unique) var gitlabTodoID: String
    var processedAt: Date
    
    init(gitlabTodoID: String) {
        self.gitlabTodoID = gitlabTodoID
        self.processedAt = .now
    }
}

@Model
final class NotificationRecord {
    @Attribute(.unique) var id: UUID
    var notificationType: String        // "review_requested", "approved", etc.
    var title: String                   // "Review Requested by Alice"
    var projectName: String
    var mrIID: Int?
    var mrTitle: String
    var sourceURL: String?
    var senderName: String
    var senderAvatarURL: String?
    var receivedAt: Date
    var isRead: Bool
    
    // Composite group key for list grouping
    var groupKey: String {
        guard let iid = mrIID else { return "gitlab-\(projectName)" }
        return "gitlab-\(projectName)-!\(iid)"
    }
}

@Model
final class PollState {
    var lastTodoPollAt: Date?
    var lastTodoETag: String?
    var lastMRPollAt: Date?
    var lastMRETag: String?
}
```

### 5.2 API response types (Codable)

```swift
struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct TodosQueryData: Decodable {
    let currentUser: CurrentUser
}

struct CurrentUser: Decodable {
    let todos: TodoConnection
}

struct TodoConnection: Decodable {
    let nodes: [GitLabTodo]
    let pageInfo: PageInfo
}

struct GitLabTodo: Decodable, Identifiable {
    let id: String
    let action: TodoAction
    let body: String?
    let createdAt: String
    let target: TodoTarget?
    let author: GitLabUser?
    let project: GitLabProject?
}

enum TodoAction: String, Decodable {
    case assigned, mentioned, buildFailed = "build_failed"
    case marked, approvalRequired = "approval_required"
    case unmergeable, directlyAddressed = "directly_addressed"
    case reviewRequested = "review_requested"
    case mergeTrainRemoved = "merge_train_removed"
    case memberAccessRequested = "member_access_requested"
}
```

### 5.3 Classification output

```swift
enum NotificationType: String, CaseIterable {
    case reviewRequested, reReviewRequested, assigned, reassigned
    case changesRequested, comment, commentEdited
    case approved, merged, closed, mentioned, pipelineFailed
    case newCommitsPushed, prActivity  // catch-all
    
    var displayTitle: String { /* ... */ }
    var priority: Int { /* 1 = highest */ }
    var defaultEnabled: Bool { /* user can toggle each type */ }
    
    /// Filename of the bundled PNG icon in Assets.xcassets.
    /// These are the existing project's custom icons (rounded-rect with
    /// a distinct color and glyph per type), carried forward from icons/.
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
        case .pipelineFailed:     return "PR_Closed"      // reuses red X icon
        case .newCommitsPushed:   return "New_Commits_Pushed"
        case .prActivity:         return "PR_Activity"
        }
    }
    
    /// NSImage loaded from the bundled asset catalog.
    var iconImage: NSImage? {
        NSImage(named: iconAssetName)
    }
}

struct ClassifiedNotification {
    let type: NotificationType
    let title: String           // "Review Requested by Alice"
    let projectName: String
    let mrTitle: String
    let mrIID: Int?
    let sourceURL: URL?
    let senderName: String
    let senderAvatarURL: URL?
    let threadID: String        // for UNNotification threadIdentifier
    let notificationID: String  // for UNNotification identifier (replacement)
}
```

---

## 6. Notification system

### 6.1 Categories and actions

```swift
// Registered at app launch
let openAction = UNNotificationAction(
    identifier: "OPEN_IN_BROWSER",
    title: "Open in GitLab",
    options: [.foreground]
)

let markDoneAction = UNNotificationAction(
    identifier: "MARK_DONE",
    title: "Mark as Done",
    options: []
)

let mrCategory = UNNotificationCategory(
    identifier: "MERGE_REQUEST",
    actions: [openAction, markDoneAction],
    intentIdentifiers: []
)

UNUserNotificationCenter.current()
    .setNotificationCategories([mrCategory])
```

### 6.2 Notification construction

```swift
func send(_ notification: ClassifiedNotification) {
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.subtitle = notification.projectName
    content.body = notification.mrTitle
    content.threadIdentifier = notification.threadID
    content.categoryIdentifier = "MERGE_REQUEST"
    content.sound = .default
    content.userInfo = [
        "url": notification.sourceURL?.absoluteString ?? "",
        "todoID": notification.gitlabTodoID
    ]
    
    // Attach the per-type PNG icon (bundled in Assets.xcassets).
    // UNNotificationAttachment on macOS requires a file URL, so we
    // write the icon to a temp directory from the asset catalog.
    if let image = notification.type.iconImage,
       let tiffData = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        try? pngData.write(to: tempURL)
        if let attachment = try? UNNotificationAttachment(
            identifier: "icon",
            url: tempURL,
            options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
        ) {
            content.attachments = [attachment]
        }
    }
    
    let request = UNNotificationRequest(
        identifier: notification.notificationID,  // same ID = replaces previous
        content: content,
        trigger: nil  // deliver immediately
    )
    
    UNUserNotificationCenter.current().add(request)
}
```

### 6.3 Response handling

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler handler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo
    
    switch response.actionIdentifier {
    case "OPEN_IN_BROWSER", UNNotificationDefaultActionIdentifier:
        if let urlString = userInfo["url"] as? String,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    case "MARK_DONE":
        if let todoID = userInfo["todoID"] as? String {
            Task { await gitLabService.markTodoAsDone(id: todoID) }
        }
    default:
        break
    }
    
    handler()
}
```

---

## 7. App lifecycle and background execution

### 7.1 App entry point

```swift
@main
struct GitLabNotifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environmentObject(appState)
                .frame(width: 360, height: 480)
        } label: {
            Image(systemName: appState.unreadCount > 0 ? "bell.badge" : "bell")
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
```

### 7.2 Info.plist keys

```xml
<key>LSUIElement</key>
<true/>                              <!-- No Dock icon -->

<key>CFBundleIdentifier</key>
<string>com.danielkuhlwein.gitlab-notifier</string>

<key>NSUserNotificationAlertStyle</key>
<string>banner</string>              <!-- Default to banner, user can change in System Settings -->
```

### 7.3 Login item registration

```swift
import ServiceManagement

// In AppDelegate.applicationDidFinishLaunching
#if !DEBUG
try? SMAppService.mainApp.register()
#endif
```

This appears in **System Settings → General → Login Items** with a toggle. No helper app, no LaunchAgent plist, no `com.apple.provenance` issues.

### 7.4 Polling timer

```swift
actor PollCoordinator {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.gitlab-notifier.poll", qos: .utility)
    
    func start(interval: TimeInterval = 30) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .seconds(5)       // allow coalescing for battery
        )
        t.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        t.resume()
        timer = t
    }
    
    func adjustInterval(idle: Bool) {
        let interval: TimeInterval = idle ? 120 : 30
        start(interval: interval)
    }
    
    private func poll() async {
        // ... fetch, classify, dispatch (see section 3.1)
    }
}
```

### 7.5 Idle detection for adaptive polling

```swift
// Monitor user activity via CGEventSource
func setupIdleMonitor() {
    Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        let isIdle = idleSeconds > 300  // 5 minutes
        Task { await pollCoordinator.adjustInterval(idle: isIdle) }
    }
}
```

---

## 8. UI design

### 8.1 Menu bar popover

Each notification row displays its **bundled PNG icon** (from the existing project's `icons/` directory) at the leading edge. These are the same icons currently used by `notify_helper.swift`, carried forward into the asset catalog.

```
┌──────────────────────────────────────┐
│  GitLab Notifier      ⟳  Last: 12s  │
├──────────────────────────────────────┤
│  [icon] Pending Reviews (3)          │
│  ┌──────────────────────────────────┐│
│  │ [Review_Requested]               ││
│  │ Review Requested by Alice        ││
│  │   cav-ts-apps · !942            ││
│  │   feat: semantic releases        ││
│  │                       2m ago  →  ││
│  ├──────────────────────────────────┤│
│  │ [Review_Requested]               ││
│  │ Review Requested by Bob          ││
│  │   deployments · !415            ││
│  │   fix: slackbot token rename     ││
│  │                       8m ago  →  ││
│  └──────────────────────────────────┘│
│                                      │
│  Recent (5)                          │
│  ┌──────────────────────────────────┐│
│  │ [PR_Approved]   Approved by Morgan       ││
│  │ [New_Comment]   Comment by Mallory       ││
│  │ [PR_Merged]     Merged (!891)            ││
│  │ [PR_Closed]     Pipeline Failed (main)   ││
│  │ [PR_Assigned]   Assigned by Chris        ││
│  └──────────────────────────────────┘│
├──────────────────────────────────────┤
│  Mark All Read     Settings...  Quit │
└──────────────────────────────────────┘
```

### 8.2 Icon asset inventory

The following PNG icons are bundled in `Assets.xcassets`, imported from the existing project's `icons/` directory. Each is a ~512x512 rounded-rect with a dark background, colored border, and distinct glyph.

| Asset name | Color | Glyph | Used for |
|---|---|---|---|
| `Review_Requested` | Purple | Chat bubble + pencil | Review Requested |
| `Re-Review_Requested` | Purple | Refresh arrow | Re-Review Requested |
| `PR_Assigned_to_You` | Blue | ID badge | Assigned |
| `PR_Reassigned` | Blue | Bidirectional arrows | Reassigned |
| `Changes_Requested` | Amber | Document + pencil | Changes Requested |
| `New_Comment` | Green | Chat bubble | New Comment |
| `Comment_Edited` | Teal | Pencil | Comment Edited |
| `PR_Approved` | Green | Checkmark circle | PR Approved |
| `PR_Merged` | Purple | Merge arrow | PR Merged |
| `PR_Closed` | Red | X circle | PR Closed, Pipeline Failed |
| `You_Were_Mentioned` | Pink | @ symbol | You Were Mentioned |
| `New_Commits_Pushed` | Teal | Commit node | New Commits Pushed |
| `PR_Activity` | Blue | Bell circle | Catch-all activity |

### 8.2 Settings view (tabs)

**Connection tab:**
- GitLab instance URL (default: `https://gitlab.com`)
- Personal access token (secure field, stored in Keychain)
- "Test Connection" button
- Connection status indicator

**Notifications tab:**
- Toggles for each of the 12 notification types
- Sound on/off
- "Show in Do Not Disturb" toggle

**General tab:**
- Polling interval slider (15s–300s, default 30s)
- Launch at login toggle (bound to `SMAppService`)
- "Check for Updates" button (Sparkle)

---

## 9. Distribution

### 9.1 Signing strategy: ad-hoc (no paid Apple Developer account)

The initial release uses **ad-hoc code signing** (free) rather than a Developer ID certificate ($99/year Apple Developer Program). Sparkle's update verification uses its own EdDSA key pair, which is independent of Apple's signing infrastructure, so auto-updates work identically regardless of Apple signing tier.

**Trade-offs of this approach:**

| Concern | Impact | Mitigation |
|---|---|---|
| Gatekeeper blocks first launch | User sees "unidentified developer" dialog on first open | Right-click → Open → confirm (one-time); documented in README + DMG background |
| No notarization | Cannot submit to Apple's notary service | Not required for functionality; target audience (developers) is comfortable with the bypass |
| UNUserNotificationCenter | Requires a proper app bundle with `CFBundleIdentifier` and code signing, but ad-hoc signing satisfies this on macOS | Verified: ad-hoc signed `.app` bundles can request and receive notification permission |
| Library Validation | Hardened Runtime's library validation rejects Sparkle when loaded from an ad-hoc signed app | Disable library validation via entitlement (see 9.1.2) |
| Future upgrade path | Can layer Developer ID signing on top at any time without changing Sparkle integration or app architecture | EdDSA key pair carries forward; Apple signing is additive |

#### 9.1.1 Build and package workflow

| Step | Command / tool |
|---|---|
| Archive | Xcode → Product → Archive → "Copy App" (not "Developer ID") |
| Ad-hoc sign | `codesign --sign - --force --deep GitLabNotifier.app` (Xcode does this automatically with "Sign to Run Locally") |
| Create DMG | `create-dmg --volname "GitLab Notifier" --window-size 600 400 --app-drop-link 450 200 GitLabNotifier.dmg GitLabNotifier.app` |
| Sign DMG | Not required for ad-hoc distribution |

The DMG background image should include a visible instruction: **"Drag to Applications, then right-click → Open on first launch."**

#### 9.1.2 Entitlements (ad-hoc specific)

Because Sparkle is a dynamically loaded framework, macOS's library validation (part of Hardened Runtime) will reject it when the host app is ad-hoc signed. Add this entitlement to `GitLabNotifier.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
```

This entitlement is only needed because we're not using Developer ID signing. When/if a paid Apple Developer account is added, this entitlement can be removed and replaced with standard Hardened Runtime.

#### 9.1.3 First-launch user experience

The user's first launch will be blocked by Gatekeeper with a dialog stating the app is from an "unidentified developer." The bypass is:

1. Right-click (or Control-click) the app in Applications
2. Select "Open" from the context menu
3. Click "Open" in the confirmation dialog

This is a **one-time** step. All subsequent launches (and all Sparkle-delivered updates) open without any prompt. This workflow is well-understood by the target audience (developers using GitLab daily).

#### 9.1.4 Future: upgrading to Developer ID ($99/year)

When/if an Apple Developer Program membership is added, the upgrade is non-breaking:

1. Obtain a Developer ID Application certificate
2. Replace ad-hoc signing with `codesign --sign "Developer ID Application: ..." --options runtime`
3. Submit to `notarytool` for notarization, staple the ticket
4. Remove the `com.apple.security.cs.disable-library-validation` entitlement
5. Sparkle's EdDSA key pair continues to work unchanged (EdDSA verification is independent of Apple code signing)
6. Existing users receive the Developer ID-signed build as a normal Sparkle update

No changes to app code, Sparkle configuration, or appcast hosting are required.

### 9.2 Auto-updates (Sparkle with EdDSA-only signing)

Sparkle 2.x is integrated via SPM. Update integrity is verified using Sparkle's own **EdDSA (Ed25519)** key pair (free, no Apple account needed). This is independent of and complementary to Apple code signing.

**Setup:**

1. Generate EdDSA key pair: `./bin/generate_keys` (from Sparkle's tools in the SPM artifacts directory)
2. Store the private key securely (never commit to git; back up offline)
3. Set `SUPublicEDKey` in Info.plist to the generated public key
4. Set `SUFeedURL` in Info.plist pointing to the appcast XML (ie: GitHub Pages or raw GitHub URL)

**Release workflow:**

1. Build and archive the app
2. Package into a DMG (or ZIP)
3. Run `./bin/generate_appcast /path/to/updates/` to generate the appcast XML with EdDSA signatures and delta updates
4. Upload the DMG + appcast XML to GitHub Releases
5. Sparkle checks the appcast on a schedule, downloads the update, verifies the EdDSA signature, and installs it

**Info.plist keys:**

```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/danielkuhlwein/gitlab-notifier-app/main/appcast.xml</string>

<key>SUPublicEDKey</key>
<string>your-base64-encoded-ed25519-public-key</string>
```

**UI integration:**

"Check for Updates..." menu item in the menu bar popover, bound to `SPUStandardUpdaterController`. Sparkle automatically checks every 24 hours by default.

### 9.3 Homebrew Cask (post-launch)

```ruby
cask "gitlab-notifier" do
  version "1.0.0"
  sha256 "abc123..."
  url "https://github.com/danielkuhlwein/gitlab-notifier/releases/download/v#{version}/GitLabNotifier.dmg"
  name "GitLab Notifier"
  desc "Native macOS notifications for GitLab merge requests"
  homepage "https://github.com/danielkuhlwein/gitlab-notifier"
  depends_on macos: ">= :sonoma"
  app "GitLab Notifier.app"
  zap trash: [
    "~/Library/Application Support/com.danielkuhlwein.gitlab-notifier",
    "~/Library/Preferences/com.danielkuhlwein.gitlab-notifier.plist",
  ]
end
```

Note: Homebrew Cask will show a caveat about the app being unsigned. Users installing via `brew install --cask gitlab-notifier` will still need to do the right-click → Open bypass on first launch. This caveat disappears if Developer ID signing is added later.

---

## 10. Platform requirements

| Requirement | Value | Rationale |
|---|---|---|
| macOS minimum | 14.0 (Sonoma) | SwiftData, MenuBarExtra `.window` style |
| Swift version | 6.0+ | Strict concurrency, actors |
| Xcode | 16+ | SwiftData support |
| Signing | Ad-hoc (v1); Developer ID Application (future) | Ad-hoc is free and sufficient for dev-audience distribution; Developer ID ($99/yr) removes Gatekeeper friction |
| Sandbox | Disabled | No sandbox needed (network, keychain work by default) |
| Entitlements | Disable library validation | Required for Sparkle to load under ad-hoc signing; removable once Developer ID signing is adopted |

---

## 11. Project structure (Xcode)

```
GitLabNotifier/
├── GitLabNotifierApp.swift            # @main, MenuBarExtra scene
├── AppDelegate.swift                  # UNUserNotificationCenter delegate, lifecycle
├── AppState.swift                     # @Observable, unread count, connection status
│
├── Services/
│   ├── GitLabService.swift            # GraphQL client, URLSession, ETag caching
│   ├── PollCoordinator.swift          # Actor, timer management, adaptive intervals
│   ├── NotificationClassifier.swift   # Todo → NotificationType mapping
│   ├── NotificationDispatcher.swift   # UNUserNotificationCenter wrapper
│   └── KeychainStore.swift            # Security framework PAT storage
│
├── Models/
│   ├── GitLabAPITypes.swift           # Codable structs for GraphQL responses
│   ├── NotificationType.swift         # Enum with 12 types + metadata
│   ├── ProcessedTodo.swift            # SwiftData @Model
│   ├── NotificationRecord.swift       # SwiftData @Model
│   └── PollState.swift                # SwiftData @Model
│
├── Views/
│   ├── MenuBarPopover.swift           # Main popover content
│   ├── NotificationRowView.swift      # Single notification in list
│   ├── SettingsView.swift             # Settings window (tabbed)
│   ├── ConnectionSettingsTab.swift
│   ├── NotificationSettingsTab.swift
│   └── GeneralSettingsTab.swift
│
├── Resources/
│   ├── Assets.xcassets                # App icon + 13 per-type notification icons (PNG, from icons/)
│   └── GraphQL/
│       └── Queries.swift              # GraphQL query string constants
│
├── Info.plist
├── GitLabNotifier.entitlements        # disable-library-validation (for ad-hoc + Sparkle)
│
└── Tests/
    ├── NotificationClassifierTests.swift
    ├── GitLabServiceTests.swift
    └── PollCoordinatorTests.swift
```

---

## 12. Implementation phases

### Phase 1: Core loop (weeks 1-2)

- Xcode project scaffold (MenuBarExtra, Info.plist, entitlements)
- Import 13 notification-type PNG icons from existing project's `icons/` into `Assets.xcassets`
- `KeychainStore` for PAT storage
- `GitLabService` with GraphQL todos query + ETag caching
- `NotificationClassifier` mapping `TodoAction` → `NotificationType`
- `NotificationDispatcher` sending `UNNotification`s with per-type icon attachments
- `PollCoordinator` actor with 30s timer
- Minimal settings view (GitLab URL + PAT input + test button)
- Port existing `test_classifier.py` test cases to XCTest

### Phase 2: Polish and UI (weeks 3-4)

- Menu bar popover with notification list (SwiftData `@Query`)
- Notification actions (Open in Browser, Mark as Done)
- Per-type notification icons (bundled PNGs from existing project's `icons/` directory)
- Adaptive polling (idle detection)
- `SMAppService` login item registration
- Notification type toggles in settings
- Click-to-open URL handling via `UNNotificationResponse`

### Phase 3: Supplemental coverage (weeks 5-6)

- MR state polling (merged/closed detection)
- Notes polling (comment edits)
- Re-review and reassignment detection via MR diff
- `ProcessedTodo` TTL cleanup (auto-delete records > 7 days)
- Notification history view with search/filter

### Phase 4: Distribution (week 7)

- Ad-hoc code signing + `disable-library-validation` entitlement
- Sparkle integration with EdDSA key pair (no Apple Developer account needed)
- Appcast XML hosting on GitHub Pages or raw GitHub URL
- DMG creation with `create-dmg` (including first-launch instructions in background image)
- README, screenshots, GitHub Release
- Document right-click → Open bypass for first launch

### Phase 5: Enhancements (post-launch)

- Apple Developer Program enrollment ($99/yr) for Developer ID signing + notarization (removes Gatekeeper friction)
- OAuth2 Device Authorization Grant flow
- Self-hosted GitLab instance support (custom base URL + optional CA cert)
- App Intents ("Show pending reviews" via Siri/Shortcuts)
- Focus Filters (suppress notification types per Focus mode)
- WidgetKit widget (pending review count)
- Homebrew Cask submission

---

## 13. Migration path from current system

For existing users of the script-based system:

| Current component | Replacement | Migration action |
|---|---|---|
| `wrapper.applescript` | `GitLabService` (GraphQL) | Not needed (no Mail.app dependency) |
| `gitlab_notifier.py` | `NotificationClassifier` | Classification logic ported to Swift |
| `notify_helper.swift` | `NotificationDispatcher` | Notification code integrated into main app |
| `run_notifier.sh` | `PollCoordinator` | Not needed |
| `com.daniel.gitlab-notifier.plist` | `SMAppService.mainApp` | Not needed (no LaunchAgent) |
| `install.sh` | Drag-to-install DMG | Not needed (one-time right-click → Open on first launch) |
| `.notifier_state.json` | SwiftData `ProcessedTodo` | Auto-created on first launch |
| Mail.app rule | Not needed | User can disable/remove the rule |

The user generates a GitLab PAT, pastes it into the app's settings, and the system is running. No Terminal commands, no manual plist creation, no TCC permissions for Mail.app. The only one-time friction is the right-click → Open Gatekeeper bypass on first launch (eliminated if Developer ID signing is adopted later).
