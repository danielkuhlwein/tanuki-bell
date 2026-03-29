import SwiftUI

@Observable
final class AppState {
    var unreadCount: Int = 0
    var isConnected: Bool = false
    var lastPollTime: Date?
    var connectionError: String?
}
