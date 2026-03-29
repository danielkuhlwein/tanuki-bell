import SwiftData
import Foundation

@Model
final class PollState {
    var lastTodoPollAt: Date?
    var lastTodoETag: String?
    var lastMRPollAt: Date?
    var lastMRETag: String?

    init() {}
}
