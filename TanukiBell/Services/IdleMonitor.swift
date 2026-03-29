import Foundation
import CoreGraphics

/// Monitors user activity and reports idle state changes.
/// Idle = no mouse/keyboard for 5 minutes.
final class IdleMonitor: @unchecked Sendable {
    private var timer: Timer?
    private let idleThreshold: TimeInterval = 300 // 5 minutes
    private let checkInterval: TimeInterval = 60  // check every minute
    private let onIdleChanged: @Sendable (Bool) -> Void

    init(onIdleChanged: @escaping @Sendable (Bool) -> Void) {
        self.onIdleChanged = onIdleChanged
    }

    @MainActor
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkIdle()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkIdle() {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .mouseMoved
        )
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: .keyDown
        )
        let leastIdle = min(idleSeconds, keyboardIdle)
        let isIdle = leastIdle > idleThreshold
        onIdleChanged(isIdle)
    }
}
