import Foundation

final class SleepGuard {
    private var token: NSObjectProtocol?
    private var count = 0

    var isActive: Bool { token != nil }

    func start() {
        count += 1
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "치지직 다운로드"
        )
    }

    func stop() {
        count = max(count - 1, 0)
        guard count == 0, let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
    }
}
