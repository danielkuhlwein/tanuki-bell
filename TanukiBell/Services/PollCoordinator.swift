import Foundation

actor PollCoordinator {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(
        label: "com.danielkuhlwein.tanuki-bell.poll",
        qos: .utility
    )
    private var currentInterval: TimeInterval = 30

    var isRunning: Bool { timer != nil }

    func start(interval: TimeInterval = 30) {
        timer?.cancel()
        currentInterval = interval

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: interval,
            leeway: .seconds(5)
        )
        t.setEventHandler { [weak self] in
            Task { await self?.poll() }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    func adjustInterval(idle: Bool) {
        let interval: TimeInterval = idle ? 120 : 30
        guard interval != currentInterval else { return }
        start(interval: interval)
    }

    private func poll() async {
        // TODO: Phase 1 — implement fetch -> classify -> dispatch -> persist cycle
    }
}
