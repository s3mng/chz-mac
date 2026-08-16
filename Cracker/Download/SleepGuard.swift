import Foundation

final class SleepGuard {
    private var token: NSObjectProtocol?

    var isActive: Bool { token != nil }

    func start() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "치지직 다운로드"
        )
    }

    func stop() {
        if let token {
            ProcessInfo.processInfo.endActivity(token)
        }
        token = nil
    }
}
