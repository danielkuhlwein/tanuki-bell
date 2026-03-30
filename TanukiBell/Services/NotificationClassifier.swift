import Foundation

struct NotificationClassifier {

    static func classify(todo: GitLabTodo) -> ClassifiedNotification? {
        guard case .mergeRequest(let mr) = todo.target else {
            print("[Classify] Skipped todo \(todo.id): target is \(todo.target == nil ? "nil" : "non-MR"), action=\(todo.action)")
            return nil
        }

        let type = mapActionToType(action: todo.action, mrState: mr.state)
        let senderName = todo.author?.name ?? "Someone"
        let projectName = mr.project?.fullPath ?? todo.project?.fullPath ?? "Unknown"
        let mrIID = Int(mr.iid)

        let shortName = abbreviateName(senderName)
        let title = "\(type.displayTitle) by \(shortName)"
        let threadID = "gitlab-\(projectName)-!\(mr.iid)"

        // Only include a body excerpt for notification types where comment text adds
        // meaningful context. For review requests, assignments, etc. todo.body is
        // just the MR title — showing it would duplicate the mrTitle line.
        let bodyExcerpt: String? = type.showsBodyExcerpt ? todo.body?.strippingHTML : nil

        return ClassifiedNotification(
            type: type,
            title: title,
            projectName: projectName,
            mrTitle: mr.title,
            mrIID: mrIID,
            sourceURL: URL(string: mr.webUrl),
            senderName: senderName,
            senderAvatarURL: todo.author?.avatarUrl.flatMap(URL.init(string:)),
            threadID: threadID,
            notificationID: "todo-\(todo.id)",
            gitlabTodoID: todo.id,
            bodyExcerpt: bodyExcerpt
        )
    }

    /// Extract a project path from a GitLab MR web URL.
    /// `https://gitlab.com/org/group/project/-/merge_requests/1` → `org/group/project`
    /// Falls back to `nil` if the URL cannot be parsed.
    static func projectPath(from webUrl: String) -> String? {
        guard let url = URL(string: webUrl) else { return nil }
        // Split on "/-/" — everything before it is the project path.
        let parts = url.path.components(separatedBy: "/-/")
        guard let raw = parts.first, !raw.isEmpty else { return nil }
        // Drop the leading "/" to match the fullPath format from GraphQL.
        let path = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        return path.isEmpty ? nil : path
    }

    /// "Daniel Kuhlwein" → "Daniel K", "Alice" → "Alice"
    static func abbreviateName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        guard parts.count >= 2, let first = parts.first, let last = parts.last else {
            return name
        }
        let lastInitial = last.prefix(1).uppercased()
        return "\(first) \(lastInitial)"
    }

    private static func mapActionToType(
        action: TodoAction,
        mrState: MergeRequestState
    ) -> NotificationType {
        switch action {
        case .reviewRequested:
            return .reviewRequested
        case .assigned:
            return .assigned
        case .mentioned, .directlyAddressed:
            return .mentioned
        case .buildFailed:
            return .pipelineFailed
        case .approvalRequired:
            return .approved
        case .reviewSubmitted:
            return .approved
        case .mergeTrainRemoved:
            return mrState == .merged ? .merged : .prActivity
        case .marked, .unmergeable, .memberAccessRequested, .unknown:
            return .prActivity
        }
    }
}
