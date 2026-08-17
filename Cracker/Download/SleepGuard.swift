import Foundation
import IOKit.pwr_mgt

final class SleepGuard: @unchecked Sendable {
    static let shared = SleepGuard()
    static let timeoutSeconds: CFTimeInterval = 180

    var onExpired: (() -> Void)?

    private let lock = NSLock()
    private var count = 0
    private var assertionID: IOPMAssertionID = 0
    private var lastBeat = Date.distantPast
    private var watchdog: DispatchSourceTimer?

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return count > 0 && assertionID != 0
    }

    func start() {
        lock.lock()
        count += 1
        lastBeat = Date()
        if assertionID == 0 {
            createLocked()
        } else {
            refreshLocked()
        }
        startWatchdogLocked()
        lock.unlock()
    }

    func stop() {
        lock.lock()
        count = max(count - 1, 0)
        if count == 0 {
            releaseLocked(reason: "sleep off")
        }
        lock.unlock()
    }

    func heartbeat() {
        lock.lock()
        lastBeat = Date()
        if count > 0 {
            if assertionID == 0 {
                createLocked()
            } else {
                refreshLocked()
            }
        }
        lock.unlock()
    }

    func forceStop(reason: String) {
        lock.lock()
        count = 0
        releaseLocked(reason: reason)
        lock.unlock()
    }

    private func createLocked() {
        var id: IOPMAssertionID = 0
        let status = IOPMAssertionCreateWithDescription(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "Cracker" as CFString,
            "다운로드 또는 다시보기 대기" as CFString,
            "받는 동안 맥이 혼자 잠들지 않게 막습니다" as CFString,
            nil,
            Self.timeoutSeconds,
            kIOPMAssertionTimeoutActionRelease as CFString,
            &id
        )
        if status == kIOReturnSuccess {
            assertionID = id
            AppLog.shared.i("sleep on")
        } else {
            assertionID = 0
            AppLog.shared.e("sleep fail \(status)")
        }
    }

    private func refreshLocked() {
        guard assertionID != 0 else { return }
        let seconds = Self.timeoutSeconds as CFNumber
        let status = IOPMAssertionSetProperty(
            assertionID,
            kIOPMAssertionTimeoutKey as CFString,
            seconds
        )
        if status != kIOReturnSuccess {
            AppLog.shared.w("sleep refresh-fail")
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            createLocked()
        }
    }

    private func releaseLocked(reason: String) {
        stopWatchdogLocked()
        guard assertionID != 0 else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        AppLog.shared.i(reason)
    }

    private func startWatchdogLocked() {
        guard watchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        timer.resume()
        watchdog = timer
    }

    private func stopWatchdogLocked() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func watchdogTick() {
        lock.lock()
        let holding = count > 0
        let stale = Date().timeIntervalSince(lastBeat) >= Self.timeoutSeconds
        lock.unlock()
        guard holding, stale else { return }
        AppLog.shared.e("sleep stale")
        forceStop(reason: "sleep force-off")
        onExpired?()
    }
}
