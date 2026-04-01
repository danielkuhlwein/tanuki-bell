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

enum TodoAction: Decodable, Equatable {
    case assigned
    case mentioned
    case buildFailed
    case marked
    case approvalRequired
    case unmergeable
    case directlyAddressed
    case reviewRequested
    case reviewSubmitted
    case mergeTrainRemoved
    case memberAccessRequested
    case unknown(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "assigned":                self = .assigned
        case "mentioned":               self = .mentioned
        case "build_failed":            self = .buildFailed
        case "marked":                  self = .marked
        case "approval_required":       self = .approvalRequired
        case "unmergeable":             self = .unmergeable
        case "directly_addressed":      self = .directlyAddressed
        case "review_requested":        self = .reviewRequested
        case "review_submitted":        self = .reviewSubmitted
        case "merge_train_removed":     self = .mergeTrainRemoved
        case "member_access_requested": self = .memberAccessRequested
        default:                        self = .unknown(value)
        }
    }
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

// MARK: - REST API types (supplemental polls)

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

struct RESTNote: Decodable, Identifiable {
    let id: Int
    let body: String
    let author: RESTUser
    let createdAt: Date
    let updatedAt: Date
    let system: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, author, system
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isEdited: Bool {
        updatedAt > createdAt
    }
}

struct RESTUser: Decodable {
    let id: Int
    let name: String
    let username: String
}

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
    let bodyExcerpt: String?
}
