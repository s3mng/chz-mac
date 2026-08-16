import Foundation

struct TransferRequest: Sendable {
    let job: DownloadJob
    let quality: QualityOption
    let title: String
}

final class TransferCoordinator: @unchecked Sendable {
    private let http: HTTPClient
    private let settings: SettingsStore
    private let history: JobStore
    private let transfer: MediaTransfer
    private let sleep = SleepGuard()
    private let lock = NSLock()
    private var jobs: [DownloadJob] = []
    private var queue: [String: TransferRequest] = [:]
    private var pauseFlags: [String: Bool] = [:]
    private var cancelFlags: [String: Bool] = [:]
    private var discarded = Set<String>()
    private var loopRunning = false
    private let cacheDir: URL

    var onChange: (([DownloadJob]) -> Void)?

    init(http: HTTPClient, settings: SettingsStore) {
        self.http = http
        self.settings = settings
        history = JobStore()
        transfer = MediaTransfer(http: http)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        cacheDir = caches.appendingPathComponent("cracker-staging", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        jobs = restore(history.load())
        history.save(jobs)
        publish()
    }

    var snapshot: [DownloadJob] {
        lock.lock()
        defer { lock.unlock() }
        return jobs
    }

    var hasActiveTransfer: Bool {
        snapshot.contains { [.queued, .running, .paused].contains($0.status) }
    }

    func cacheByteCount() -> Int64 {
        stagingFiles().reduce(0) { $0 + fileSize($1) }
    }

    @discardableResult
    func clearInactiveCache() -> Int64 {
        let keep = Set(snapshot.filter { [.queued, .running, .paused].contains($0.status) }.map(\.id))
        var removed: Int64 = 0
        for file in stagingFiles() {
            let id = stagingJobId(file)
            if let id, keep.contains(id) { continue }
            removed += fileSize(file)
            try? FileManager.default.removeItem(at: file)
        }
        return removed
    }

    func enqueue(meta: VideoMeta, quality: QualityOption) {
        let id = UUID().uuidString
        let job = DownloadJob(
            id: id,
            kind: meta.kind,
            title: meta.title,
            channel: meta.channel,
            quality: quality.label,
            status: .queued,
            isAdult: meta.isAdult
        )
        lock.lock()
        queue[id] = TransferRequest(job: job, quality: quality, title: meta.title)
        pauseFlags[id] = false
        cancelFlags[id] = false
        lock.unlock()
        upsert(job)
        startLoop()
    }

    func cancel(id: String) {
        lock.lock()
        cancelFlags[id] = true
        pauseFlags[id] = false
        let job = jobs.first { $0.id == id }
        lock.unlock()
        guard var job else { return }
        job.status = job.kind == .live ? .stopped : .cancelled
        job.error = nil
        upsert(job)
    }

    func remove(id: String) {
        lock.lock()
        discarded.insert(id)
        cancelFlags[id] = true
        pauseFlags[id] = false
        queue.removeValue(forKey: id)
        jobs.removeAll { $0.id == id }
        lock.unlock()
        deleteStaging(id)
        persist()
        publish()
    }

    func clearAll() {
        lock.lock()
        jobs.forEach { discarded.insert($0.id); cancelFlags[$0.id] = true; pauseFlags[$0.id] = false }
        queue.removeAll()
        jobs = []
        lock.unlock()
        sweepStaging()
        persist()
        publish()
    }

    func togglePause(id: String) {
        lock.lock()
        guard var job = jobs.first(where: { $0.id == id }), job.kind == .vod else {
            lock.unlock()
            return
        }
        switch job.status {
        case .running:
            pauseFlags[id] = true
            job.status = .paused
            jobs = [job] + jobs.filter { $0.id != id }
            lock.unlock()
            persist()
            publish()
        case .paused:
            pauseFlags[id] = false
            job.status = .running
            jobs = [job] + jobs.filter { $0.id != id }
            lock.unlock()
            persist()
            publish()
            startLoop()
        default:
            lock.unlock()
        }
    }

    private func startLoop() {
        lock.lock()
        if loopRunning {
            lock.unlock()
            return
        }
        loopRunning = true
        lock.unlock()
        Task.detached { [weak self] in
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        sleep.start()
        defer {
            sleep.stop()
            lock.lock()
            loopRunning = false
            lock.unlock()
        }
        while true {
            let next = snapshot.first { [.queued, .running, .paused].contains($0.status) }
            guard let next else { break }
            if cancelled(next.id) {
                deleteStaging(next.id)
                var copy = next
                copy.status = next.kind == .live ? .stopped : .cancelled
                copy.error = nil
                upsert(copy)
                continue
            }
            do {
                try await process(next.id)
            } catch {
                let current = snapshot.first { $0.id == next.id } ?? next
                if cancelled(next.id) {
                    var copy = current
                    copy.status = current.kind == .live ? .stopped : .cancelled
                    copy.error = nil
                    upsert(copy)
                } else {
                    var copy = current
                    copy.status = .failed
                    copy.error = error.localizedDescription
                    upsert(copy)
                }
            }
        }
    }

    private func process(_ id: String) async throws {
        lock.lock()
        let request = queue[id]
        lock.unlock()
        guard let request else { return }
        if cancelled(id) {
            deleteStaging(id)
            return
        }
        let live = request.job.kind == .live
        let extensionName: String
        if live {
            extensionName = "ts"
        } else if request.quality.protocolKind == .hls {
            extensionName = "ts"
        } else {
            extensionName = "mp4"
        }
        let maxAttempts = live ? 1 : min(max(settings.vodRetries, 0), AppSettings.maxRetries) + 1
        var current = job(id, fallback: request.job)
        current.status = .running
        current.progress = 0
        current.attempt = 1
        current.maxAttempts = maxAttempts
        current.error = nil
        upsert(current)

        let staging = stagingURL(id: id, ext: extensionName)
        var lastError: Error?
        for attempt in 1...maxAttempts {
            if cancelled(id) {
                await finishCancelled(id: id, request: request, live: live, staging: staging, startedAt: nil)
                return
            }
            if attempt > 1 {
                var retrying = job(id, fallback: request.job)
                retrying.status = .running
                retrying.progress = 0
                retrying.attempt = attempt
                retrying.maxAttempts = maxAttempts
                retrying.error = nil
                upsert(retrying)
                try await Task.sleep(for: .milliseconds(min(1_000 * attempt, 5_000)))
                if cancelled(id) {
                    await finishCancelled(id: id, request: request, live: live, staging: staging, startedAt: nil)
                    return
                }
            }
            try? FileManager.default.removeItem(at: staging)
            let startedAt = Date()
            let ticker: Task<Void, Never>? = live ? Task { [weak self] in
                while !(self?.cancelled(id) ?? true) {
                    guard let self, let current = self.snapshot.first(where: { $0.id == id }), current.status == .running else { break }
                    var copy = current
                    copy.elapsedLabel = Formatters.clock(Int64(Date().timeIntervalSince(startedAt) * 1000))
                    self.upsert(copy)
                    try? await Task.sleep(for: .seconds(1))
                }
            } : nil
            do {
                if live {
                    try await transfer.recordLive(
                        mediaPlaylistURL: request.quality.mediaURL,
                        output: staging,
                        isCancelled: { [weak self] in self?.cancelled(id) ?? true }
                    )
                } else {
                    try await transfer.downloadVod(
                        quality: request.quality,
                        output: staging,
                        onProgress: { [weak self] value in
                            guard let self else { return }
                            var current = self.job(id, fallback: request.job)
                            current.progress = value
                            current.status = self.paused(id) ? .paused : .running
                            self.upsert(current)
                        },
                        isPaused: { [weak self] in self?.paused(id) ?? false },
                        isCancelled: { [weak self] in self?.cancelled(id) ?? true }
                    )
                }
                ticker?.cancel()
                if cancelled(id) {
                    await finishCancelled(id: id, request: request, live: live, staging: staging, startedAt: startedAt)
                    return
                }
                try publish(staging, title: request.title, ext: extensionName)
                var finished = job(id, fallback: request.job)
                finished.status = .completed
                finished.progress = 1
                finished.elapsedLabel = live ? Formatters.clock(Int64(Date().timeIntervalSince(startedAt) * 1000)) : nil
                finished.error = nil
                upsert(finished)
                lock.lock()
                queue.removeValue(forKey: id)
                discarded.remove(id)
                lock.unlock()
                return
            } catch is CancellationError {
                ticker?.cancel()
                await finishCancelled(id: id, request: request, live: live, staging: staging, startedAt: startedAt)
                return
            } catch {
                ticker?.cancel()
                if cancelled(id) {
                    await finishCancelled(id: id, request: request, live: live, staging: staging, startedAt: startedAt)
                    return
                }
                lastError = error
                if live, fileSize(staging) > 0 {
                    try? publish(staging, title: request.title, ext: extensionName)
                    var stopped = job(id, fallback: request.job)
                    stopped.status = .stopped
                    stopped.elapsedLabel = Formatters.clock(Int64(Date().timeIntervalSince(startedAt) * 1000))
                    stopped.error = "연결이 끊겨서 여기까지 저장했어요"
                    upsert(stopped)
                    lock.lock()
                    queue.removeValue(forKey: id)
                    discarded.remove(id)
                    lock.unlock()
                    return
                }
                if attempt == maxAttempts {
                    throw error
                }
                try? FileManager.default.removeItem(at: staging)
            }
        }
        throw lastError ?? TransferError.message("실패")
    }

    private func finishCancelled(id: String, request: TransferRequest, live: Bool, staging: URL, startedAt: Date?) async {
        if live, fileSize(staging) > 0 {
            try? publish(staging, title: request.title, ext: staging.pathExtension)
            var stopped = job(id, fallback: request.job)
            stopped.status = .stopped
            if let startedAt {
                stopped.elapsedLabel = Formatters.clock(Int64(Date().timeIntervalSince(startedAt) * 1000))
            }
            stopped.error = nil
            upsert(stopped)
        } else {
            try? FileManager.default.removeItem(at: staging)
            var copy = job(id, fallback: request.job)
            copy.status = live ? .stopped : .cancelled
            copy.error = nil
            upsert(copy)
        }
        lock.lock()
        queue.removeValue(forKey: id)
        discarded.remove(id)
        lock.unlock()
    }

    private func publish(_ staging: URL, title: String, ext: String) throws {
        let accessed = accessFolder()
        defer { accessed.stop() }
        let folder = accessed.url
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = uniqueURL(in: folder, title: title, ext: ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: staging, to: dest)
    }

    private func accessFolder() -> (url: URL, stop: () -> Void) {
        if let custom = settings.customFolder {
            let ok = custom.startAccessingSecurityScopedResource()
            return (custom, { if ok { custom.stopAccessingSecurityScopedResource() } })
        }
        let movies = settings.defaultMoviesFolder()
        if (try? FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)) != nil {
            return (movies, {})
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let folder = downloads.appendingPathComponent(AppSettings.defaultFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (folder, {})
    }

    private func uniqueURL(in folder: URL, title: String, ext: String) -> URL {
        let base = Formatters.sanitizeFileName(title)
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        return url
    }

    private func cancelled(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelFlags[id] == true
    }

    private func paused(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return pauseFlags[id] == true
    }

    private func job(_ id: String, fallback: DownloadJob) -> DownloadJob {
        snapshot.first { $0.id == id } ?? fallback
    }

    private func stagingURL(id: String, ext: String) -> URL {
        cacheDir.appendingPathComponent("cracker-\(id).\(ext)")
    }

    private func deleteStaging(_ id: String) {
        for file in stagingFiles() where file.lastPathComponent.hasPrefix("cracker-\(id)") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func sweepStaging() {
        for file in stagingFiles() {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func stagingFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
    }

    private func stagingJobId(_ file: URL) -> String? {
        let name = file.lastPathComponent
        guard name.hasPrefix("cracker-") else { return nil }
        let rest = name.dropFirst("cracker-".count)
        guard let dot = rest.firstIndex(of: ".") else { return String(rest) }
        return String(rest[..<dot])
    }

    private func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
    }

    private func restore(_ jobs: [DownloadJob]) -> [DownloadJob] {
        jobs.map { job in
            var copy = job
            if [.queued, .running, .paused].contains(job.status) {
                copy.status = .failed
                copy.error = "앱이 종료되어 중단됐어요"
            }
            return copy
        }
    }

    private func persist() {
        history.save(snapshot)
    }

    private func upsert(_ job: DownloadJob) {
        lock.lock()
        if discarded.contains(job.id) {
            lock.unlock()
            return
        }
        let previous = jobs.first { $0.id == job.id }
        jobs = [job] + jobs.filter { $0.id != job.id }
        jobs = Array(jobs.prefix(JobStore.maxCount))
        let shouldPersist = previous == nil || previous?.status != job.status
        lock.unlock()
        if shouldPersist { persist() }
        publish()
    }

    private func publish() {
        let jobs = snapshot
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(jobs)
        }
    }
}
