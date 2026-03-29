import SwiftData
import Foundation

@Model
final class ProcessedTodo {
    @Attribute(.unique) var gitlabTodoID: String
    var processedAt: Date

    init(gitlabTodoID: String) {
        self.gitlabTodoID = gitlabTodoID
        self.processedAt = .now
    }
}
