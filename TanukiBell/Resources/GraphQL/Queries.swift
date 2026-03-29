import Foundation

enum GraphQLQueries {
    static let pendingTodos = """
        query PendingTodos($after: String) {
          currentUser {
            todos(state: pending, first: 50, after: $after) {
              nodes {
                id
                action
                body
                createdAt
                target {
                  __typename
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
        """
}
