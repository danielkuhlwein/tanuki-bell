import Foundation
import SwiftData

actor PollCoordinator {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(
        label: "com.danielkuhlwein.tanuki-bell.poll",
        qos: .utility
    )
    private var currentInterval: TimeInterval = 30
    private var userInterval: TimeInterval = 30

    private let gitLabService: GitLabService
    private let modelContainer: ModelContainer
    private let onUpdate: @Sendable (Int, Date) -> Void

    var isRunning: Bool { timer != nil }

    /// - Parameters:
    ///   - gitLabService: The GitLab API client
    ///   - modelContainer: SwiftData container for persistence
    ///   - onUpdate: Callback with (unreadCount, pollTime) — called on each successful poll
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
        timer?.cancel()
        userInterval = interval
        currentInterval = interval

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .seconds(5)
        )
        t.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func adjustInterval(idle: Bool) {
        let interval: TimeInterval = idle ? 120 : userInterval
        guard interval != currentInterval else { return }
        currentInterval = interval

        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        t.resume()
        timer = t
    }

    // MARK: - Core poll cycle

    private func poll() async {
        guard let token = KeychainStore.loadToken() else {
            return
        }

        do {
            let connection = try await gitLabService.fetchPendingTodos(token: token)
            let newTodos = try await filterNewTodos(connection.nodes)

            var notificationCount = 0
            for todo in newTodos {
                guard let classified = NotificationClassifier.classify(todo: todo) else {
                    // Still mark as processed even if we can't classify
                    try await markProcessed(todoID: todo.id)
                    continue
                }

                NotificationDispatcher.send(classified)
                try await persist(classified: classified, todoID: todo.id)
                notificationCount += 1
            }

            // Fetch current unread count and report
            let unreadCount = try await fetchUnreadCount()
            let pollTime = Date.now
            onUpdate(unreadCount, pollTime)

            // Handle pagination
            if connection.pageInfo.hasNextPage, let cursor = connection.pageInfo.endCursor {
                await pollNextPage(token: token, cursor: cursor)
            }

        } catch let serviceError as GitLabServiceError where serviceError == .notModified {
            // 304 Not Modified — no changes, just update poll time
            let unreadCount = (try? await fetchUnreadCount()) ?? 0
            onUpdate(unreadCount, .now)
        } catch {
            print("[PollCoordinator] Poll failed: \(error)")
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

        // Mark todo as processed
        context.insert(ProcessedTodo(gitlabTodoID: todoID))

        // Save notification record
        let record = NotificationRecord(
            notificationType: classified.type.rawValue,
            title: classified.title,
            projectName: classified.projectName,
            mrIID: classified.mrIID,
            mrTitle: classified.mrTitle,
            sourceURL: classified.sourceURL?.absoluteString,
            senderName: classified.senderName,
            senderAvatarURL: classified.senderAvatarURL?.absoluteString
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
}

// Make GitLabServiceError equatable for the catch pattern
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
