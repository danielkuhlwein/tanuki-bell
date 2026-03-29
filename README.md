# Tanuki Bell

Native macOS menu bar app that monitors GitLab for merge request activity and delivers classified, actionable notifications.

## Features

- **Menu bar app** — lives in your menu bar, no Dock icon
- **Native notifications** — per-MR grouping, click-to-open, action buttons (Open in GitLab, Mark as Done)
- **14 notification types** — review requested, approved, merged, closed, mentioned, pipeline failed, and more
- **Per-type icons** — each notification type has a distinct colored icon
- **Smart polling** — 30s active, 2min idle, with ETag caching for efficiency
- **Notification preferences** — enable/disable each type individually
- **Auto-updates** — via Sparkle with EdDSA signature verification
- **Launch at login** — via SMAppService (no LaunchAgent plist needed)

## Requirements

- macOS 14.0 (Sonoma) or later
- GitLab.com or self-hosted GitLab instance
- Personal Access Token with `read_api` scope

## Installation

### From DMG

1. Download the latest `.dmg` from [Releases](https://github.com/danielkuhlwein/tanuki-bell/releases)
2. Drag **Tanuki Bell** to Applications
3. On first launch: right-click the app → **Open** → confirm (one-time Gatekeeper bypass for ad-hoc signed apps)

### From source

```bash
# Clone
git clone https://github.com/danielkuhlwein/tanuki-bell.git
cd tanuki-bell

# Generate Xcode project (requires xcodegen)
xcodegen generate

# Build
xcodebuild -project TanukiBell.xcodeproj -scheme TanukiBell -configuration Release build
```

## Setup

1. Launch Tanuki Bell — a bell icon appears in your menu bar
2. Click the bell → **Settings...**
3. In the **Connection** tab:
   - Set your GitLab URL (default: `https://gitlab.com`)
   - Create a **legacy** Personal Access Token in GitLab (Profile → Access Tokens) with the **`read_api`** scope
   - Paste the token and click **Test Connection**
   - Click **Save & Start Polling**
4. Enable notifications when prompted (or manually in System Settings → Notifications → Tanuki Bell)

## How it works

Tanuki Bell polls GitLab's GraphQL API for pending todos every 30 seconds (configurable). Each todo is classified into one of 14 notification types and dispatched as a native macOS notification with a per-type icon.

Supplemental REST API polls (every 2 minutes) detect:
- MR state transitions (merged/closed) not covered by the Todos API
- Edited comments on MRs you're involved in

Polling automatically slows to 2-minute intervals when your machine is idle (no mouse/keyboard for 5 minutes).

## Notification types

| Type | Icon color | Trigger |
|------|-----------|---------|
| Review Requested | Purple | `review_requested` todo |
| Re-Review Requested | Purple | Reviewer list diff |
| Assigned to You | Blue | `assigned` todo |
| Reassigned | Blue | Assignee list diff |
| Changes Requested | Amber | Unresolved review threads |
| New Comment | Green | `mentioned` / `directly_addressed` todo |
| Comment Edited | Teal | Notes API (updated_at > created_at) |
| Approved | Green | `approval_required` / `review_submitted` todo |
| Merged | Purple | MR state poll |
| Closed | Red | MR state poll |
| Mentioned | Pink | `mentioned` todo |
| Pipeline Failed | Red | `build_failed` todo |

## Building a release

```bash
# Build and create DMG
./scripts/build-release.sh 1.0.0

# Generate Sparkle EdDSA keys (one-time)
./scripts/generate-sparkle-keys.sh
```

## Project structure

```
TanukiBell/
├── TanukiBellApp.swift           # @main, MenuBarExtra scene
├── AppDelegate.swift             # Notification delegate, permission prompt
├── AppState.swift                # @Observable, polling lifecycle
├── Services/
│   ├── GitLabService.swift       # GraphQL + REST client
│   ├── PollCoordinator.swift     # Actor, primary + supplemental timers
│   ├── NotificationClassifier.swift
│   ├── NotificationDispatcher.swift
│   ├── NotificationPreferences.swift
│   ├── KeychainStore.swift
│   ├── IdleMonitor.swift
│   └── UpdaterController.swift   # Sparkle wrapper
├── Models/
│   ├── GitLabAPITypes.swift      # Codable types
│   ├── NotificationType.swift    # 14 types with metadata
│   ├── ProcessedTodo.swift       # SwiftData
│   ├── NotificationRecord.swift  # SwiftData
│   ├── PollState.swift           # SwiftData
│   └── TrackedMergeRequest.swift # SwiftData
├── Views/
│   ├── MenuBarPopover.swift
│   ├── NotificationRowView.swift
│   ├── SettingsView.swift
│   ├── ConnectionSettingsTab.swift
│   ├── NotificationSettingsTab.swift
│   ├── GeneralSettingsTab.swift
│   └── NotificationHistoryView.swift
└── Resources/
    ├── Assets.xcassets
    └── GraphQL/Queries.swift
```

## License

MIT
