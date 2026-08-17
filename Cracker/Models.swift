import SwiftUI

enum JobKind: String, Codable, Sendable {
    case live
    case vod
    case clip
    case watch

    var isLive: Bool { self == .live }
    var canPause: Bool { self == .vod || self == .clip }
}

enum JobStatus: String, Codable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case stopped
    case cancelled
}

enum StreamProtocolKind: String, Codable, Sendable {
    case hls
    case dash
}

struct QualityOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let note: String
    let protocolKind: StreamProtocolKind
    let mediaURL: URL
    var dashVideoRepId: String?
    var dashAudioRepId: String?
}

struct VideoMeta: Sendable {
    let sourceURL: String
    let kind: JobKind
    let title: String
    let channel: String
    let isAdult: Bool
    let durationLabel: String?
    let qualities: [QualityOption]
    var channelId: String? = nil
    var openDate: String? = nil
}

struct DownloadJob: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var kind: JobKind
    var title: String
    var channel: String
    var quality: String
    var status: JobStatus
    var progress: Double = 0
    var elapsedLabel: String?
    var speedLabel: String?
    var isAdult: Bool = false
    var error: String?
    var attempt: Int = 1
    var maxAttempts: Int = 1
    var lookingForReplay: Bool? = nil

    var isWatchHold: Bool {
        kind == .watch && status == .running && (lookingForReplay != nil || (progress > 0 && progress < 0.1))
    }

    var isReplayHold: Bool {
        lookingForReplay == true || (lookingForReplay == nil && progress > 0 && progress < 0.1)
    }
}

enum ExtractResult: Sendable {
    case ready(VideoMeta)
    case needsLogin(String)
    case offline(String?)
    case failed(String)
}

enum TransferError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): value
        }
    }
}

enum HostKind {
    static func isNaver(_ host: String) -> Bool {
        let value = normalized(host)
        return value == "naver.com" || value.hasSuffix(".naver.com")
    }

    static func isChzzk(_ host: String) -> Bool {
        let value = normalized(host)
        return value == "chzzk.naver.com" || value.hasSuffix(".chzzk.naver.com")
    }

    static func needsSessionCookie(_ host: String) -> Bool {
        let value = normalized(host)
        switch value {
        case "api.chzzk.naver.com", "apis.naver.com", "chzzk.naver.com":
            return true
        default:
            return value.hasSuffix(".apis.naver.com")
        }
    }

    static func isLoginNavigation(_ host: String) -> Bool {
        let value = normalized(host)
        switch value {
        case "naver.com", "www.naver.com",
             "nid.naver.com", "chzzk.naver.com":
            return true
        default:
            return value.hasSuffix(".nid.naver.com") || value.hasSuffix(".chzzk.naver.com")
        }
    }

    private static func normalized(_ host: String) -> String {
        var value = host.lowercased()
        if value.hasPrefix(".") {
            value.removeFirst()
        }
        return value
    }
}

enum Formatters {
    static func clock(_ milliseconds: Int64) -> String {
        let total = max(milliseconds / 1000, 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    static func duration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
        if h > 0 { return "\(h)시간" }
        if m > 0 { return "\(m)분" }
        return "\(seconds)초"
    }

    static func isoDurationSeconds(_ value: String) -> Double {
        let pattern = #"^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else { return 0 }
        func group(_ index: Int) -> Double {
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: value) else { return 0 }
            return Double(value[swiftRange]) ?? 0
        }
        return group(3) * 86_400 + group(4) * 3_600 + group(5) * 60 + group(6)
    }

    static func sanitizeFileName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "chzzk" : cleaned
        return String(base.prefix(80))
    }

    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(max(bytesPerSecond, 0).rounded())) + "/s"
    }
}

enum VideoCodec {
    static func isH264(_ codecs: String?) -> Bool {
        let value = (codecs ?? "").lowercased()
        return value.contains("avc1") || value.contains("avc3")
    }

    static func shortLabel(_ codecs: String?) -> String? {
        let value = (codecs ?? "").lowercased()
        if isH264(codecs) { return "H.264" }
        if value.contains("hvc1") || value.contains("hev1") { return "HEVC" }
        if value.contains("av01") { return "AV1" }
        return nil
    }

    static func betterForPlayback(
        _ lhs: (height: Int?, codecs: String?, bandwidth: Int),
        _ rhs: (height: Int?, codecs: String?, bandwidth: Int)
    ) -> Bool {
        let leftHeight = lhs.height ?? 0
        let rightHeight = rhs.height ?? 0
        if leftHeight != rightHeight { return leftHeight > rightHeight }
        let leftH264 = isH264(lhs.codecs)
        let rightH264 = isH264(rhs.codecs)
        if leftH264 != rightH264 { return leftH264 }
        return lhs.bandwidth > rhs.bandwidth
    }
}
