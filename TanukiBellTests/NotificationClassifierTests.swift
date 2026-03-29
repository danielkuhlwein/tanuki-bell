import XCTest
@testable import TanukiBell

final class NotificationClassifierTests: XCTestCase {

    private func makeTodo(
        id: String = "gid://gitlab/Todo/1",
        action: TodoAction,
        mrState: MergeRequestState = .opened,
        authorName: String = "Alice",
        mrTitle: String = "feat: add feature",
        mrIID: String = "42",
        projectPath: String = "group/project"
    ) -> GitLabTodo {
        GitLabTodo(
            id: id,
            action: action,
            body: nil,
            createdAt: "2026-03-28T10:00:00Z",
            target: .mergeRequest(MergeRequestTarget(
                iid: mrIID,
                title: mrTitle,
                state: mrState,
                webUrl: "https://gitlab.com/\(projectPath)/-/merge_requests/\(mrIID)",
                draft: false,
                headPipeline: nil,
                author: GitLabUser(name: authorName, username: "alice", avatarUrl: nil),
                reviewers: nil,
                project: GitLabProject(name: "project", fullPath: projectPath)
            )),
            author: GitLabUser(name: authorName, username: "alice", avatarUrl: nil),
            project: GitLabProject(name: "project", fullPath: projectPath)
        )
    }

    func testReviewRequested() {
        let todo = makeTodo(action: .reviewRequested)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .reviewRequested)
    }

    func testAssigned() {
        let todo = makeTodo(action: .assigned)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .assigned)
    }

    func testMentioned() {
        let todo = makeTodo(action: .mentioned)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .mentioned)
    }

    func testDirectlyAddressed() {
        let todo = makeTodo(action: .directlyAddressed)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .mentioned)
    }

    func testBuildFailed() {
        let todo = makeTodo(action: .buildFailed)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .pipelineFailed)
    }

    func testMergeTrainRemovedWithMergedState() {
        let todo = makeTodo(action: .mergeTrainRemoved, mrState: .merged)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .merged)
    }

    func testMergeTrainRemovedWithOpenState() {
        let todo = makeTodo(action: .mergeTrainRemoved, mrState: .opened)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .prActivity)
    }

    func testTitleFormat() {
        let todo = makeTodo(action: .reviewRequested, authorName: "Bob")
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.title, "Review Requested by Bob")
    }

    func testThreadIDFormat() {
        let todo = makeTodo(action: .assigned, mrIID: "99", projectPath: "team/repo")
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.threadID, "gitlab-team/repo-!99")
    }

    func testReviewSubmitted() {
        let todo = makeTodo(action: .reviewSubmitted)
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .approved)
    }

    func testUnknownActionMapsToActivity() {
        let todo = makeTodo(action: .unknown("some_future_action"))
        let result = NotificationClassifier.classify(todo: todo)
        XCTAssertEqual(result?.type, .prActivity)
    }

    func testNonMRTargetReturnsNil() {
        let todo = GitLabTodo(
            id: "gid://gitlab/Todo/2",
            action: .assigned,
            body: nil,
            createdAt: "2026-03-28T10:00:00Z",
            target: .unknown,
            author: nil,
            project: nil
        )
        XCTAssertNil(NotificationClassifier.classify(todo: todo))
    }
}
