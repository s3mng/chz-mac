import Foundation

struct HlsVariant: Sendable {
    let uri: URL
    let bandwidth: Int
    let width: Int?
    let height: Int?
}

struct HlsSegment: Sendable {
    let uri: URL
    let durationSec: Double
}

struct HlsMediaPlaylist: Sendable {
    let targetDurationSec: Double
    let mediaSequence: Int64
    let ended: Bool
    let mapURI: URL?
    let segments: [HlsSegment]
}

enum HlsParser {
    static func isMaster(_ body: String) -> Bool {
        body.split(whereSeparator: \.isNewline).contains { $0.trimmingCharacters(in: .whitespaces).uppercased().hasPrefix("#EXT-X-STREAM-INF") }
    }

    static func parseMaster(_ body: String, playlistURL: URL) -> [HlsVariant] {
        let lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var variants: [HlsVariant] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.uppercased().hasPrefix("#EXT-X-STREAM-INF") {
                let attrs = attributes(String(line.split(separator: ":", maxSplits: 1).last ?? ""))
                let next = i + 1 < lines.count ? lines[i + 1] : nil
                if let next, !next.hasPrefix("#"), let uri = resolve(playlistURL, next) {
                    let resolution = attrs["RESOLUTION"]
                    variants.append(
                        HlsVariant(
                            uri: uri,
                            bandwidth: Int(attrs["BANDWIDTH"] ?? "") ?? 0,
                            width: resolution.flatMap { Int($0.split(separator: "x").first.map(String.init) ?? "") },
                            height: resolution.flatMap { Int($0.split(separator: "x").dropFirst().first.map(String.init) ?? "") }
                        )
                    )
                    i += 1
                }
            }
            i += 1
        }
        return variants.sorted { ($0.height ?? $0.bandwidth) > ($1.height ?? $1.bandwidth) }
    }

    static func parseMedia(_ body: String, playlistURL: URL) -> HlsMediaPlaylist {
        var target = 6.0
        var sequence: Int64 = 0
        var ended = false
        var mapURI: URL?
        var duration = 0.0
        var segments: [HlsSegment] = []
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper.hasPrefix("#EXT-X-TARGETDURATION") {
                target = Double(line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "") ?? target
            } else if upper.hasPrefix("#EXT-X-MEDIA-SEQUENCE") {
                sequence = Int64(line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "") ?? sequence
            } else if upper.hasPrefix("#EXT-X-MAP") {
                if let uri = attributes(String(line.split(separator: ":", maxSplits: 1).last ?? ""))["URI"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                   let resolved = resolve(playlistURL, uri) {
                    mapURI = resolved
                }
            } else if upper.hasPrefix("#EXTINF") {
                let value = line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? ""
                duration = Double(value.split(separator: ",").first.map(String.init) ?? "") ?? 0
            } else if upper.hasPrefix("#EXT-X-ENDLIST") {
                ended = true
            } else if !line.isEmpty && !line.hasPrefix("#"), let uri = resolve(playlistURL, line) {
                segments.append(HlsSegment(uri: uri, durationSec: duration))
                duration = 0
            }
        }
        return HlsMediaPlaylist(
            targetDurationSec: target,
            mediaSequence: sequence,
            ended: ended,
            mapURI: mapURI,
            segments: segments
        )
    }

    private static func resolve(_ base: URL, _ ref: String) -> URL? {
        URL(string: ref, relativeTo: base)?.absoluteURL
    }

    private static func attributes(_ raw: String) -> [String: String] {
        var out: [String: String] = [:]
        let pattern = #"([A-Z0-9-]+)=("(?:\\.|[^"])*"|[^,]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return out }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        regex.enumerateMatches(in: raw, options: [], range: range) { match, _, _ in
            guard let match,
                  let keyRange = Range(match.range(at: 1), in: raw),
                  let valueRange = Range(match.range(at: 2), in: raw) else { return }
            let value = raw[valueRange].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            out[raw[keyRange].uppercased()] = value
        }
        return out
    }
}
