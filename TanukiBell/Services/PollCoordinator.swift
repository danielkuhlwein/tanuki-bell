import Foundation
import SwiftData

actor PollCoordinator {
    private var primaryTimer: DispatchSourceTimer?
    private var supplementalTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(
        label: "com.danielkuhlwein.tanuki-bell.poll",
        qos: .utility
    )
    private var currentInterval: TimeInterval = 30
    private var userInterval: TimeInterval = 30

    private let gitLabService: GitLabService
    private let modelContainer: ModelContainer
    private let onUpdate: @Sendable (Int, Date) -> Void

    var isRunning: Bool { primaryTimer != nil }

    init(
        gitLabService: GitLabService,
        modelContainer: ModelContainer,
        onUpdate: @escaping @Sendable (Int, Date) -> Void
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
            Task { await self?.pollTodos() }
        }
        t.resume()
        primaryTimer = t

        // Supplemental poll (MR state + notes) — 2 minutes
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now() + 10, repeating: 120, leeway: .seconds(10))
        s.setEventHandler { [weak self] in
            Task { await self?.pollSupplemental() }
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
            Task { await self?.pollTodos() }
        }
        t.resume()
        primaryTimer = t

        // Supplemental: 5min when idle, 2min when active
        let suppInterval: TimeInterval = idle ? 300 : 120
        supplementalTimer?.cancel()
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now(), repeating: suppInterval, leeway: .seconds(10))
        s.setEventHandler { [weak self] in
            Task { await self?.pollSupplemental() }
        }
        s.resume()
        supplementalTimer = s
    }

    // MARK: - Primary poll (todos)

    private func pollTodos() async {
        guard let token = KeychainStore.loadToken() else {
            print("[Poll] No token found, skipping")
            return
        }

        do {
            let connection = try await gitLabService.fetchPendingTodos(token: token)
            let total = connection.nodes.count
            let newTodos = try await filterNewTodos(connection.nodes)

            print("[Poll] Fetched \(total) todos, \(newTodos.count) new")

            for todo in newTodos {
                guard let classified = NotificationClassifier.classify(todo: todo) else {
                    print("[Poll]   Skipped (non-MR target): \(todo.id)")
                    try await markProcessed(todoID: todo.id)
                    continue
                }
                print("[Poll]   \(classified.type.rawValue): \"\(classified.title)\" — \(classified.projectName) !\(classified.mrIID ?? 0)")
                NotificationDispatcher.send(classified)
                try await persist(classified: classified, todoID: todo.id)
            }

            let unreadCount = try await fetchUnreadCount()
            onUpdate(unreadCount, .now)
            print("[Poll] Unread count: \(unreadCount)")

            if connection.pageInfo.hasNextPage, let cursor = connection.pageInfo.endCursor {
                print("[Poll] Fetching next page...")
                await pollNextPage(token: token, cursor: cursor)
            }

        } catch let serviceError as GitLabServiceError where serviceError == .notModified {
            print("[Poll] 304 Not Modified")
            let unreadCount = (try? await fetchUnreadCount()) ?? 0
            onUpdate(unreadCount, .now)
        } catch {
            print("[Poll] Todo poll failed: \(error)")
        }
    }

    private func pollNextPage(token: String, cursor: String) async {
        do {
            let connection = try await gitLabService.fetchPendingTodos(token: token, after: cursor)
            let newTodos = try await filterNewTodos(connection.nodes)

            for todo in newTodos {
                guard let classified = NotificationClassifier.classify(todo: todo) else {
                    try await markProcessed(todoID: todo.id)
                    continue
                }
                NotificationDispatcher.send(classified)
                try await persist(classified: classified, todoID: todo.id)
            }

            if connection.pageInfo.hasNextPage, let next = connection.pageInfo.endCursor {
                await pollNextPage(token: token, cursor: next)
            }
        } catch {
            print("[PollCoordinator] Pagination failed: \(error)")
        }
    }

    // MARK: - Supplemental poll (MR state + notes)

    private func pollSupplemental() async {
        guard let token = KeychainStore.loadToken() else { return }

        print("[Supplemental] Starting MR state + notes poll")
        await pollMRStates(token: token)
        await pollNotes(token: token)
        await cleanupOldRecords()
        print("[Supplemental] Done")
    }

    /// Detect merged/closed MR transitions
    private func pollMRStates(token: String) async {
        do {
            let since = Date.now.addingTimeInterval(-300)
            let mergeRequests = try await gitLabService.fetchAssignedMergeRequests(
                token: token, updatedAfter: since
            )
            print("[Supplemental] MR state: \(mergeRequests.count) MRs updated recently")

            for mr in mergeRequests {
                let transition = try await detectMRTransition(mr)
                guard let transition else { continue }
                print("[Supplemental] MR state transition: !\(mr.iid) → \(transition.rawValue)")

                let notification = ClassifiedNotification(
                    type: transition,
                    title: "\(transition.displayTitle): \(mr.title)",
                    projectName: "Project #\(mr.projectId)",
                    mrTitle: mr.title,
                    mrIID: mr.iid,
                    sourceURL: URL(string: mr.webUrl),
                    senderName: NotificationClassifier.abbreviateName(mr.author?.name ?? "Someone"),
                    senderAvatarURL: nil,
                    threadID: "gitlab-\(mr.projectId)-!\(mr.iid)",
                    notificationID: "mr-state-\(mr.id)-\(mr.state)",
                    gitlabTodoID: "",
                    bodyExcerpt: nil
                )
                NotificationDispatcher.send(notification)
                try await persistNotificationRecord(notification)
            }
        } catch {
            print("[PollCoordinator] MR state poll failed: \(error)")
        }
    }

    /// Detect edited comments on tracked MRs
    private func pollNotes(token: String) async {
        do {
            let snapshots = try await fetchTrackedMRSnapshots()
            print("[Supplemental] Notes: checking \(snapshots.count) tracked MRs")

            for snap in snapshots {
                let notes = try await gitLabService.fetchMRNotes(
                    token: token, projectID: snap.projectID, mrIID: snap.iid
                )

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
                        try await persistNotificationRecord(notification)
                    }
                }

                if let latestID = notes.first?.id {
                    try await updateTrackedMRNoteID(mrID: snap.mrID, noteID: latestID)
                }
            }
        } catch {
            print("[PollCoordinator] Notes poll failed: \(error)")
        }
    }

    // MARK: - MR state transition detection

    @MainActor
    private func detectMRTransition(_ mr: RESTMergeRequest) throws -> NotificationType? {
        let context = ModelContext(modelContainer)
        let mrID = mr.id
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            predicate: #Predicate { $0.mrID == mrID }
        )
        let existing = try context.fetch(descriptor).first

        if let tracked = existing {
            let oldState = tracked.state
            let newState = mr.state

            // Update tracked state
            tracked.state = newState
            tracked.lastSeenAt = .now
            try context.save()

            if oldState != newState {
                switch newState {
                case "merged": return .merged
                case "closed": return .closed
                default: return nil
                }
            }
            return nil
        } else {
            // First time seeing this MR — start tracking, no notification
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
            context.insert(tracked)
            try context.save()
            return nil
        }
    }

    // MARK: - SwiftData operations

    @MainActor
    private func filterNewTodos(_ todos: [GitLabTodo]) throws -> [GitLabTodo] {
        let context = ModelContext(modelContainer)
        let allIDs = todos.map(\.id)

        let descriptor = FetchDescriptor<ProcessedTodo>(
            predicate: #Predicate { allIDs.contains($0.gitlabTodoID) }
        )
        let existing = try context.fetch(descriptor)
        let existingIDs = Set(existing.map(\.gitlabTodoID))

        return todos.filter { !existingIDs.contains($0.id) }
    }

    @MainActor
    private func markProcessed(todoID: String) throws {
        let context = ModelContext(modelContainer)
        context.insert(ProcessedTodo(gitlabTodoID: todoID))
        try context.save()
    }

    @MainActor
    private func persist(classified: ClassifiedNotification, todoID: String) throws {
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
        try context.save()
    }

    @MainActor
    private func persistNotificationRecord(_ notification: ClassifiedNotification) throws {
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
        try context.save()
    }

    @MainActor
    private func fetchUnreadCount() throws -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<NotificationRecord>(
            predicate: #Predicate { !$0.isRead }
        )
        return try context.fetchCount(descriptor)
    }

    /// Sendable snapshot of TrackedMergeRequest for cross-actor use
    struct MRSnapshot: Sendable {
        let mrID: Int
        let iid: Int
        let projectID: Int
        let projectName: String
        let title: String
        let webUrl: String
        let lastNoteID: Int?
    }

    @MainActor
    private func fetchTrackedMRSnapshots() throws -> [MRSnapshot] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            sortBy: [SortDescriptor(\.lastSeenAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { mr in
            MRSnapshot(
                mrID: mr.mrID, iid: mr.iid, projectID: mr.projectID,
                projectName: mr.projectName, title: mr.title,
                webUrl: mr.webUrl, lastNoteID: mr.lastNoteID
            )
        }
    }

    @MainActor
    private func updateTrackedMRNoteID(mrID: Int, noteID: Int) throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<TrackedMergeRequest>(
            predicate: #Predicate { $0.mrID == mrID }
        )
        if let tracked = try context.fetch(descriptor).first {
            tracked.lastNoteID = noteID
            try context.save()
        }
    }

    // MARK: - TTL cleanup

    @MainActor
    private func cleanupOldRecords() async {
        let context = ModelContext(modelContainer)
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60) // 7 days

        do {
            let oldTodos = FetchDescriptor<ProcessedTodo>(
                predicate: #Predicate { $0.processedAt < cutoff }
            )
            for todo in try context.fetch(oldTodos) {
                context.delete(todo)
            }

            let oldNotifications = FetchDescriptor<NotificationRecord>(
                predicate: #Predicate { $0.receivedAt < cutoff }
            )
            for record in try context.fetch(oldNotifications) {
                context.delete(record)
            }

            let oldMRs = FetchDescriptor<TrackedMergeRequest>(
                predicate: #Predicate { $0.lastSeenAt < cutoff }
            )
            for mr in try context.fetch(oldMRs) {
                context.delete(mr)
            }

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
