import AVFoundation
import Foundation

enum Mp4Muxer {
    static func mux(video: URL, audio: URL?, output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        guard let srcVideo = videoTracks.first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw TransferError.message("영상 트랙을 찾지 못했어요")
        }
        let duration = try await videoAsset.load(.duration)
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: srcVideo, at: .zero)

        if let audio {
            let audioAsset = AVURLAsset(url: audio)
            if let srcAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let audioDuration = try await audioAsset.load(.duration)
                let range = CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, audioDuration))
                try? compAudio.insertTimeRange(range, of: srcAudio, at: .zero)
            }
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw TransferError.message("파일을 합치지 못했어요")
        }
        exporter.outputURL = output
        exporter.outputFileType = .mp4
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }
        if exporter.status != .completed {
            throw TransferError.message(exporter.error?.localizedDescription ?? "파일을 합치지 못했어요")
        }
    }
}
