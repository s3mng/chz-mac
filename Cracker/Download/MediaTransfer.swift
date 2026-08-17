import Foundation

struct MediaTransfer {
    let http: HTTPClient
    private let fragmentRetries = 5

    func recordLive(
        mediaPlaylistURL: URL,
        output: URL,
        isCancelled: @escaping () -> Bool
    ) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        AppLog.shared.i("live rec start")

        var nextSequence: Int64 = -1
        var wroteMap = false
        var playlistFailures = 0
        var wroteAny = false

        while !isCancelled() {
            try Task.checkCancellation()
            let playlist: HlsMediaPlaylist
            do {
                playlist = try await fetchMediaPlaylist(mediaPlaylistURL)
                playlistFailures = 0
            } catch {
                playlistFailures += 1
                if wroteAny && playlistFailures >= 6 {
                    AppLog.shared.w("live playlist miss \(playlistFailures) end")
                    return
                }
                if playlistFailures >= 12 {
                    AppLog.shared.e("live playlist fail \(playlistFailures)")
                    throw error
                }
                try await Task.sleep(for: .milliseconds(min(800 * playlistFailures, 4_000)))
                continue
            }

            if !wroteMap, let map = playlist.mapURI {
                try await downloadWithRetry(map, to: handle, isCancelled: isCancelled)
                wroteMap = true
                wroteAny = true
            }

            let newSegments: [HlsSegment]
            let startSeq: Int64
            if nextSequence < 0 {
                newSegments = Array(playlist.segments.suffix(3))
                startSeq = playlist.mediaSequence + Int64(playlist.segments.count - newSegments.count)
            } else {
                let drop = max(Int(nextSequence - playlist.mediaSequence), 0)
                newSegments = Array(playlist.segments.dropFirst(min(drop, playlist.segments.count)))
                startSeq = nextSequence
            }

            for (index, segment) in newSegments.enumerated() {
                if isCancelled() { return }
                try await downloadWithRetry(segment.uri, to: handle, isCancelled: isCancelled)
                nextSequence = startSeq + Int64(index) + 1
                wroteAny = true
            }

            if playlist.ended {
                AppLog.shared.i("live rec end")
                return
            }
            let wait = min(max(playlist.targetDurationSec * 500, 400), 4_000)
            try await Task.sleep(for: .milliseconds(Int(wait)))
        }
    }

    func downloadVod(
        quality: QualityOption,
        output: URL,
        onProgress: @escaping (Double) -> Void,
        isPaused: @escaping () -> Bool,
        isCancelled: @escaping () -> Bool
    ) async throws {
        switch quality.protocolKind {
        case .hls:
            try await downloadHLS(
                mediaURL: quality.mediaURL,
                output: output,
                onProgress: onProgress,
                isPaused: isPaused,
                isCancelled: isCancelled
            )
        case .dash:
            try await downloadDash(
                quality: quality,
                output: output,
                onProgress: onProgress,
                isPaused: isPaused,
                isCancelled: isCancelled
            )
        }
    }

    private func downloadHLS(
        mediaURL: URL,
        output: URL,
        onProgress: @escaping (Double) -> Void,
        isPaused: @escaping () -> Bool,
        isCancelled: @escaping () -> Bool
    ) async throws {
        let playlist = try await fetchMediaPlaylist(mediaURL)
        let extra = playlist.mapURI == nil ? 0 : 1
        let total = max(playlist.segments.count + extra, 1)
        var done = 0
        try prepareFile(output)
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }

        if let map = playlist.mapURI {
            try await waitIfPaused(isPaused: isPaused, isCancelled: isCancelled)
            try await downloadWithRetry(map, to: handle, isCancelled: isCancelled)
            done += 1
            onProgress(Double(done) / Double(total))
        }
        for segment in playlist.segments {
            if isCancelled() { return }
            try await waitIfPaused(isPaused: isPaused, isCancelled: isCancelled)
            try Task.checkCancellation()
            try await downloadWithRetry(segment.uri, to: handle, isCancelled: isCancelled)
            done += 1
            onProgress(Double(done) / Double(total))
        }
    }

    private func downloadDash(
        quality: QualityOption,
        output: URL,
        onProgress: @escaping (Double) -> Void,
        isPaused: @escaping () -> Bool,
        isCancelled: @escaping () -> Bool
    ) async throws {
        let xml = try await http.getText(quality.mediaURL, headers: ["Accept": "application/dash+xml"])
        let reps = DashParser.parse(xml, mpdURL: quality.mediaURL)
        guard let video = reps.first(where: { $0.id == quality.dashVideoRepId }) else {
            throw TransferError.message("영상 화질을 찾지 못했어요")
        }
        let audio = reps.first(where: { $0.id == quality.dashAudioRepId })
        let videoFile = output.deletingPathExtension().appendingPathExtension("video.m4s")
        let audioFile = output.deletingPathExtension().appendingPathExtension("audio.m4s")
        let urls = video.segmentURLs + (audio?.segmentURLs ?? [])
        var done = 0
        defer {
            try? FileManager.default.removeItem(at: videoFile)
            try? FileManager.default.removeItem(at: audioFile)
        }

        try prepareFile(videoFile)
        let videoHandle = try FileHandle(forWritingTo: videoFile)
        for url in video.segmentURLs {
            if isCancelled() { return }
            try await waitIfPaused(isPaused: isPaused, isCancelled: isCancelled)
            try await downloadWithRetry(url, to: videoHandle, isCancelled: isCancelled)
            done += 1
            onProgress(Double(done) / Double(max(urls.count, 1)) * 0.9)
        }
        try videoHandle.close()

        if let audio {
            try prepareFile(audioFile)
            let audioHandle = try FileHandle(forWritingTo: audioFile)
            for url in audio.segmentURLs {
                if isCancelled() { return }
                try await waitIfPaused(isPaused: isPaused, isCancelled: isCancelled)
                try await downloadWithRetry(url, to: audioHandle, isCancelled: isCancelled)
                done += 1
                onProgress(Double(done) / Double(max(urls.count, 1)) * 0.9)
            }
            try audioHandle.close()
        }

        let muxBeat = Task {
            while !Task.isCancelled {
                SleepGuard.shared.heartbeat()
                try? await Task.sleep(for: .seconds(15))
            }
        }
        do {
            AppLog.shared.i("mux start")
            try await Mp4Muxer.mux(
                video: videoFile,
                audio: audio != nil && FileManager.default.fileExists(atPath: audioFile.path) ? audioFile : nil,
                output: output
            )
            muxBeat.cancel()
            AppLog.shared.i("mux done")
        } catch {
            muxBeat.cancel()
            AppLog.shared.w("mux fail, keep video")
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.copyItem(at: videoFile, to: output)
        }
        onProgress(1)
    }

    private func fetchMediaPlaylist(_ url: URL) async throws -> HlsMediaPlaylist {
        let body = try await http.getText(url)
        return HlsParser.parseMedia(body, playlistURL: url)
    }

    private func downloadWithRetry(_ url: URL, to handle: FileHandle, isCancelled: @escaping () -> Bool) async throws {
        var lastError: Error = TransferError.message("조각을 받지 못했어요")
        for attempt in 1...fragmentRetries {
            if isCancelled() { return }
            do {
                try await http.download(url, to: handle)
                return
            } catch {
                lastError = error
                AppLog.shared.w("seg retry \(attempt)/\(fragmentRetries) \(error.localizedDescription)")
                if attempt == fragmentRetries { throw error }
                try await Task.sleep(for: .milliseconds(min(400 * attempt, 3_000)))
            }
        }
        throw lastError
    }

    private func waitIfPaused(isPaused: @escaping () -> Bool, isCancelled: @escaping () -> Bool) async throws {
        while isPaused() && !isCancelled() {
            SleepGuard.shared.heartbeat()
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private func prepareFile(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
}
