import Foundation
import SwiftData

@MainActor
final class PollCoordinator {
    private var primaryTimer: DispatchSourceTimer?
    private var supplementalTimer: DispatchSourceTimer?
    private let queue = DispatchQueue.main
    private var currentInterval: TimeInterval = 30
    private var userInterval: TimeInterval = 30

    private let gitLabService: GitLabService
    private let modelContainer: ModelContainer
    private let onUpdate: (Int, Date) -> Void

    var isRunning: Bool { primaryTimer != nil }

    init(
        gitLabService: GitLabService,
        modelContainer: ModelContainer,
        onUpdate: @escaping (Int, Date) -> Void
    ) {
        self.gitLabService = gitLabService
        self.modelContainer = modelContainer
        self.onUpdate = onUpdate
    }

    func start(interval: TimeInterval = 30) {
        primaryTimer?.cancel()
        supplementalTimer?.cancel()
        userInterval = interval
        currentInterval = interval

        // Primary poll (todos) — user-configured interval
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            self?.pollTodos()
        }
        t.resume()
        primaryTimer = t

        // Supplemental poll (MR state + notes) — 2 minutes
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now() + 10, repeating: 120, leeway: .seconds(10))
        s.setEventHandler { [weak self] in
            self?.pollSupplemental()
        }
        s.resume()
        supplementalTimer = s
    }

    func stop() {
        primaryTimer?.cancel()
        primaryTimer = nil
        supplementalTimer?.cancel()
        supplementalTimer = nil
    }

    func adjustInterval(idle: Bool) {
        let interval: TimeInterval = idle ? 120 : userInterval
        guard interval != currentInterval else { return }
        currentInterval = interval

        primaryTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            self?.pollTodos()
        }
        t.resume()
        primaryTimer = t

        // Supplemental: 5min when idle, 2min when active
        let suppInterval: TimeInterval = idle ? 300 : 120
        supplementalTimer?.cancel()
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now(), repeating: suppInterval, leeway: .seconds(10))
        s.setEventHandler { [weak self] in
            self?.pollSupplemental()
        }
        s.resume()
        supplementalTimer = s
    }

    // MARK: - Primary poll (todos)

    private func pollTodos() {
        guard let token = KeychainStore.loadToken() else {
            print("[Poll] No token found, skipping")
            return
        }

        Task {
            do {
                let connection = try await gitLabService.fetchPendingTodos(token: token)
                let total = connection.nodes.count
                let newTodos = filterNewTodos(connection.nodes)

                print("[Poll] Fetched \(total) todos, \(newTodos.count) new")

                for todo in newTodos {
                    guard let classified = NotificationClassifier.classify(todo: todo) else {
                        print("[Poll]   Skipped (non-MR target): \(todo.id)")
                        markProcessed(todoID: todo.id)
                        continue
                    }
                    print("[Poll]   \(classified.type.rawValue): \"\(classified.title)\" — \(classified.projectName) !\(classified.mrIID ?? 0)")
                    NotificationDispatcher.send(classified)
                    persist(classified: classified, todoID: todo.id)
                }

                let unreadCount = fetchUnreadCount()
                onUpdate(unreadCount, .now)
                print("[Poll] Unread count: \(unreadCount)")

                if connection.pageInfo.hasNextPage, let cursor = connection.pageInfo.endCursor {
                    print("[Poll] Fetching next page...")
                    await pollNextPage(token: token, cursor: cursor)
                }

            } catch let serviceError as GitLabServiceError where serviceError == .notModified {
                print("[Poll] 304 Not Modified")
                let unreadCount = fetchUnreadCount()
                onUpdate(unreadCount, .now)
            } catch {
                print("[Poll] Todo poll failed: \(error)")
            }
        }
    }

    private func pollNextPage(token: String, cursor: String) async {
        do {
            let connection = try await gitLabService.fetchPendingTodos(token: token, after: cursor)
            let newTodos = filterNewTodos(connection.nodes)

            for todo in newTodos {
                guard let classified = NotificationClassifier.classify(todo: todo) else {
                    markProcessed(todoID: todo.id)
                    continue
                }
                NotificationDispatcher.send(classified)
                persist(classified: classified, todoID: todo.id)
            }

            if connection.pageInfo.hasNextPage, let next = connection.pageInfo.endCursor {
                await pollNextPage(token: token, cursor: next)
            }
        } catch {
            print("[PollCoordinator] Pagination failed: \(error)")
        }
    }

    // MARK: - Supplemental poll (MR state + notes)

    private func pollSupplemental() {
        guard let token = KeychainStore.loadToken() else { return }

        print("[Supplemental] Starting MR state + notes poll")
        Task {
            await pollTrackedMRs(token: token)
            await pollNotes(token: token)
            cleanupOldRecords()
            print("[Supplemental] Done")
        }
    }

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
            // MRs are processed sequentially (not withTaskGroup) because diffAndNotify
            // performs SwiftData writes per MR. Parallel writes would require separate
            // ModelContext instances per task — add withTaskGroup only if poll latency
            // becomes a user-visible concern.
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

            // Resolve project name: prefer stored record, then parse from webUrl,
            // finally fall back to numeric ID if the URL can't be parsed.
            let projectName = existing?.projectName
                ?? NotificationClassifier.projectPath(from: mr.webUrl)
                ?? "Project #\(mr.projectId)"

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
                    projectName: NotificationClassifier.projectPath(from: mr.webUrl) ?? "Project #\(mr.projectId)",
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

    /// Detect edited comments on tracked MRs
    private func pollNotes(token: String) async {
        do {
            let snapshots = fetchTrackedMRSnapshots()
            print("[Supplemental] Notes: checking \(snapshots.count) tracked MRs")

            for snap in snapshots {
                let notes = try await gitLabService.fetchMRNotes(
                    token: token, projectID: snap.projectID, mrIID: snap.iid
                )

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
                            bodyExcerpt: note.body.strippingHTML
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

                if let latestID = notes.first?.id {
                    updateTrackedMRNoteID(mrID: snap.mrID, noteID: latestID)
                }
            }
        } catch {
            print("[PollCoordinator] Notes poll failed: \(error)")
        }
    }

    // MARK: - SwiftData operations

    private func filterNewTodos(_ todos: [GitLabTodo]) -> [GitLabTodo] {
        let context = ModelContext(modelContainer)
        let allIDs = todos.map(\.id)

        let descriptor = FetchDescriptor<ProcessedTodo>(
            predicate: #Predicate { allIDs.contains($0.gitlabTodoID) }
        )
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingIDs = Set(existing.map(\.gitlabTodoID))

        return todos.filter { !existingIDs.contains($0.id) }
    }

    private func markProcessed(todoID: String) {
        let context = ModelContext(modelContainer)
        context.insert(ProcessedTodo(gitlabTodoID: todoID))
        try? context.save()
    }

    private func persist(classified: ClassifiedNotification, todoID: String) {
        let context = ModelContext(modelContainer)
        context.insert(ProcessedTodo(gitlabTodoID: todoID))

        let record = NotificationRecord(
            notificationType: classified.type.rawValue,
            title: classified.title,
            projectName: classified.projectName,
            mrIID: classified.mrIID,
            mrTitle: classified.mrTitle,
            sourceURL: classified.sourceURL?.absoluteString,
            senderName: classified.senderName,
            senderAvatarURL: classified.senderAvatarURL?.absoluteString,
            bodyExcerpt: classified.bodyExcerpt
        )
        context.insert(record)
        try? context.save()
    }

    private func persistNotificationRecord(_ notification: ClassifiedNotification) {
        let context = ModelContext(modelContainer)
        let record = NotificationRecord(
            notificationType: notification.type.rawValue,
            title: notification.title,
            projectName: notification.projectName,
            mrIID: notification.mrIID,
            mrTitle: notification.mrTitle,
            sourceURL: notification.sourceURL?.absoluteString,
            senderName: notification.senderName,
            senderAvatarURL: notification.senderAvatarURL?.absoluteString,
            bodyExcerpt: notification.bodyExcerpt
        )
        context.insert(record)
        try? context.save()
    }

    private func fetchUnreadCount() -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { !$0.isRead }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    struct TrackedMRSnapshot {
        let mrID: Int
        let iid: Int
        let projectID: Int
        let projectName: String
        let title: String
        let webUrl: String
        let lastNoteID: Int?
    }

    private func fetchTrackedMRSnapshots() -> [TrackedMRSnapshot] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map { mr in
            TrackedMRSnapshot(
                mrID: mr.mrID, iid: mr.iid, projectID: mr.projectID,
                projectName: mr.projectName, title: mr.title,
                webUrl: mr.webUrl, lastNoteID: mr.lastNoteID
            )
        }
    }

    private func updateTrackedMRNoteID(mrID: Int, noteID: Int) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            predicate: #Predicate { $0.mrID == mrID }
        )
        if let tracked = try? context.fetch(descriptor).first {
            tracked.lastNoteID = noteID
            try? context.save()
        }
    }

    // MARK: - TTL cleanup

    private func cleanupOldRecords() {
        let context = ModelContext(modelContainer)
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)

        do {
            for todo in try context.fetch(FetchDescriptor<ProcessedTodo>(
                predicate: #Predicate { $0.processedAt < cutoff }
            )) { context.delete(todo) }

            for record in try context.fetch(FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { $0.receivedAt < cutoff }
            )) { context.delete(record) }

            for mr in try context.fetch(FetchDescriptor<TrackedMergeRequest>(
                predicate: #Predicate { $0.lastSeenAt < cutoff }
            )) { context.delete(mr) }

            try context.save()
        } catch {
            print("[PollCoordinator] Cleanup failed: \(error)")
        }
    }
}

extension GitLabServiceError: Equatable {
    static func == (lhs: GitLabServiceError, rhs: GitLabServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.notModified, .notModified): return true
        case (.invalidResponse, .invalidResponse): return true
        case (.noData, .noData): return true
        case (.httpError(let a), .httpError(let b)): return a == b
        case (.graphQLErrors(let a), .graphQLErrors(let b)): return a == b
        default: return false
        }
    }
}
