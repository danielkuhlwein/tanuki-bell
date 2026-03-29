import Foundation

// MARK: - GraphQL response wrapper

struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GraphQLError]?
}

struct GraphQLError: Decodable {
    let message: String
    let locations: [GraphQLErrorLocation]?
}

struct GraphQLErrorLocation: Decodable {
    let line: Int
    let column: Int
}

// MARK: - Todos query types

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

struct PageInfo: Decodable {
    let endCursor: String?
    let hasNextPage: Bool
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
    case assigned
    case mentioned
    case buildFailed = "build_failed"
    case marked
    case approvalRequired = "approval_required"
    case unmergeable
    case directlyAddressed = "directly_addressed"
    case reviewRequested = "review_requested"
    case mergeTrainRemoved = "merge_train_removed"
    case memberAccessRequested = "member_access_requested"
}

// MARK: - Target types

enum TodoTarget: Decodable {
    case mergeRequest(MergeRequestTarget)
    case unknown

    private enum CodingKeys: String, CodingKey {
        case typename = "__typename"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typename = try? container.decode(String.self, forKey: .typename)

        switch typename {
        case "MergeRequest":
            let mr = try MergeRequestTarget(from: decoder)
            self = .mergeRequest(mr)
        default:
            self = .unknown
        }
    }
}

struct MergeRequestTarget: Decodable {
    let iid: String
    let title: String
    let state: MergeRequestState
    let webUrl: String
    let draft: Bool?
    let headPipeline: HeadPipeline?
    let author: GitLabUser?
    let reviewers: ReviewerConnection?
    let project: GitLabProject?
}

enum MergeRequestState: String, Decodable {
    case opened
    case closed
    case merged
    case locked
}

struct HeadPipeline: Decodable {
    let status: String
}

struct ReviewerConnection: Decodable {
    let nodes: [GitLabUser]
}

// MARK: - Common types

struct GitLabUser: Decodable {
    let name: String
    let username: String
    let avatarUrl: String?
}

struct GitLabProject: Decodable {
    let name: String
    let fullPath: String
}

// MARK: - Classification output

struct ClassifiedNotification {
    let type: NotificationType
    let title: String
    let projectName: String
    let mrTitle: String
    let mrIID: Int?
    let sourceURL: URL?
    let senderName: String
    let senderAvatarURL: URL?
    let threadID: String
    let notificationID: String
    let gitlabTodoID: String
}
