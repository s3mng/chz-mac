import AVFoundation
import Foundation

enum Mp4Muxer {
    static func remux(from input: URL, to output: URL) async throws {
        try await mux(video: input, audio: nil, output: output)
    }

    static func mux(video: URL, audio: URL?, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)
        let videoAsset = AVURLAsset(url: video)
        let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first
        guard let videoTrack else {
            throw TransferError.message("영상 트랙을 찾지 못했어요")
        }
        let audioAsset = audio.map { AVURLAsset(url: $0) }
        let audioTrack: AVAssetTrack?
        if let audioAsset {
            audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        } else {
            audioTrack = try await videoAsset.loadTracks(withMediaType: .audio).first
        }

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        var pipes: [Pipe] = []
        if audioAsset == nil, let audioTrack {
            let reader = try AVAssetReader(asset: videoAsset)
            pipes.append(try await addPipe(track: videoTrack, reader: reader, writer: writer, mediaType: .video))
            pipes.append(try await addPipe(track: audioTrack, reader: reader, writer: writer, mediaType: .audio))
        } else {
            let videoReader = try AVAssetReader(asset: videoAsset)
            pipes.append(try await addPipe(track: videoTrack, reader: videoReader, writer: writer, mediaType: .video))
            if let audioTrack, let audioAsset {
                let audioReader = try AVAssetReader(asset: audioAsset)
                pipes.append(try await addPipe(track: audioTrack, reader: audioReader, writer: writer, mediaType: .audio))
            }
        }

        guard writer.startWriting() else {
            throw TransferError.message(writer.error?.localizedDescription ?? "파일을 합치지 못했어요")
        }
        var started = Set<ObjectIdentifier>()
        for pipe in pipes {
            let id = ObjectIdentifier(pipe.reader)
            guard started.contains(id) || pipe.reader.startReading() else {
                throw TransferError.message(pipe.reader.error?.localizedDescription ?? "파일을 읽지 못했어요")
            }
            started.insert(id)
        }

        try await copySamples(pipes: pipes, writer: writer)
        if writer.status != .completed {
            throw TransferError.message(writer.error?.localizedDescription ?? "파일을 합치지 못했어요")
        }
        try await verifyPlayable(output)
    }

    private final class Pipe {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let input: AVAssetWriterInput
        var pending: CMSampleBuffer?

        init(reader: AVAssetReader, output: AVAssetReaderTrackOutput, input: AVAssetWriterInput) {
            self.reader = reader
            self.output = output
            self.input = input
        }
    }

    private static func addPipe(
        track: AVAssetTrack,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        mediaType: AVMediaType
    ) async throws -> Pipe {
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw TransferError.message("트랙을 읽지 못했어요")
        }
        reader.add(output)
        let hint = try await track.load(.formatDescriptions).first
        let input = AVAssetWriterInput(mediaType: mediaType, outputSettings: nil, sourceFormatHint: hint)
        input.expectsMediaDataInRealTime = false
        if mediaType == .video {
            input.transform = try await track.load(.preferredTransform)
        }
        guard writer.canAdd(input) else {
            throw TransferError.message("트랙을 쓰지 못했어요")
        }
        writer.add(input)
        return Pipe(reader: reader, output: output, input: input)
    }

    private static func verifyPlayable(_ url: URL) async throws {
        let bytes = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value) ?? 0
        guard bytes > 800_000 else { return }
        let duration = try await AVURLAsset(url: url).load(.duration)
        let seconds = duration.seconds
        if seconds.isFinite && seconds > 0 && seconds < 2.5 {
            throw TransferError.message("재생 길이를 만들지 못했어요")
        }
    }

    private static func copySamples(pipes: [Pipe], writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "app.cracker.mac.mux")
            queue.async {
                var start = CMTime.invalid
                for pipe in pipes {
                    if let sample = pipe.output.copyNextSampleBuffer() {
                        pipe.pending = sample
                        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                        if !start.isValid || pts < start {
                            start = pts
                        }
                    }
                }
                writer.startSession(atSourceTime: start.isValid ? start : .zero)

                let group = DispatchGroup()
                var lastBeat = Date()
                for pipe in pipes {
                    group.enter()
                    pipe.input.requestMediaDataWhenReady(on: queue) {
                        while pipe.input.isReadyForMoreMediaData {
                            if Date().timeIntervalSince(lastBeat) >= 1 {
                                SleepGuard.shared.heartbeat()
                                lastBeat = Date()
                            }
                            let sample: CMSampleBuffer?
                            if let pending = pipe.pending {
                                sample = pending
                                pipe.pending = nil
                            } else {
                                sample = pipe.output.copyNextSampleBuffer()
                            }
                            guard let sample else {
                                pipe.input.markAsFinished()
                                group.leave()
                                return
                            }
                            if !pipe.input.append(sample) {
                                pipe.input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }
                group.notify(queue: queue) {
                    writer.finishWriting {
                        if writer.status == .completed {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: TransferError.message(writer.error?.localizedDescription ?? "파일을 합치지 못했어요"))
                        }
                    }
                }
            }
        }
    }
}
