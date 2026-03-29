import Foundation

actor GitLabService {
    private let session: URLSession
    private var baseURL: URL
    private var lastETag: String?

    init(baseURL: URL = URL(string: "https://gitlab.com")!) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "TanukiBell/1.0"]
        self.session = URLSession(configuration: config)
    }

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // MARK: - Todos (GraphQL)

    func fetchPendingTodos(token: String, after: String? = nil) async throws -> TodoConnection {
        let url = baseURL.appendingPathComponent("api/graphql")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let etag = lastETag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let query = GraphQLQueries.pendingTodos
        let variables: [String: String?] = ["after": after]
        let body: [String: Any] = [
            "query": query,
            "variables": variables,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabServiceError.invalidResponse
        }

        if httpResponse.statusCode == 304 {
            throw GitLabServiceError.notModified
        }

        if let etag = httpResponse.value(forHTTPHeaderField: "ETag") {
            lastETag = etag
        }

        guard httpResponse.statusCode == 200 else {
            throw GitLabServiceError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        let graphQLResponse = try decoder.decode(
            GraphQLResponse<TodosQueryData>.self, from: data
        )

        if let errors = graphQLResponse.errors, !errors.isEmpty {
            throw GitLabServiceError.graphQLErrors(errors.map(\.message))
        }

        guard let todosData = graphQLResponse.data else {
            throw GitLabServiceError.noData
        }

        return todosData.currentUser.todos
    }

    // MARK: - Test connection

    func testConnection(token: String) async throws -> String {
        let url = baseURL.appendingPathComponent("api/v4/user")
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GitLabServiceError.httpError(httpResponse.statusCode)
        }

        struct UserResponse: Decodable {
            let name: String
            let username: String
        }

        let user = try JSONDecoder().decode(UserResponse.self, from: data)
        return user.name
    }

    // MARK: - Mark todo as done

    func markTodoAsDone(id: String, token: String) async throws {
        let url = baseURL.appendingPathComponent("api/graphql")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let mutation = """
            mutation TodoMarkDone($id: TodoableID!) {
                todoMarkDone(input: { id: $id }) {
                    errors
                }
            }
            """
        let body: [String: Any] = [
            "query": mutation,
            "variables": ["id": id],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GitLabServiceError.invalidResponse
        }
    }
}

enum GitLabServiceError: LocalizedError {
    case invalidResponse
    case notModified
    case httpError(Int)
    case graphQLErrors([String])
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid server response"
        case .notModified: return "Not modified (304)"
        case .httpError(let code): return "HTTP error: \(code)"
        case .graphQLErrors(let msgs): return "GraphQL errors: \(msgs.joined(separator: ", "))"
        case .noData: return "No data in response"
        }
    }
}
