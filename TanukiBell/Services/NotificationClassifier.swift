import Foundation

struct NotificationClassifier {

    static func classify(todo: GitLabTodo) -> ClassifiedNotification? {
        guard case .mergeRequest(let mr) = todo.target else {
            return nil
        }

        let type = mapActionToType(action: todo.action, mrState: mr.state)
        let senderName = todo.author?.name ?? "Someone"
        let projectName = mr.project?.fullPath ?? todo.project?.fullPath ?? "Unknown"
        let mrIID = Int(mr.iid)

        let title = "\(type.displayTitle) by \(senderName)"
        let threadID = "gitlab-\(projectName)-!\(mr.iid)"

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
            gitlabTodoID: todo.id
        )
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
