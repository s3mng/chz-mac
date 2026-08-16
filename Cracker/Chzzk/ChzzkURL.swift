import Foundation

struct ChzzkTarget: Equatable, Sendable {
    let kind: JobKind
    let id: String
}

enum ChzzkURL {
    private static let live = try! NSRegularExpression(
        pattern: #"chzzk\.naver\.com/live/([\da-f]+)"#,
        options: [.caseInsensitive]
    )
    private static let video = try! NSRegularExpression(
        pattern: #"chzzk\.naver\.com/video/(\d+)"#,
        options: [.caseInsensitive]
    )

    static func parse(_ raw: String) -> ChzzkTarget? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = live.firstMatch(in: text, options: [], range: range),
           let idRange = Range(match.range(at: 1), in: text) {
            return ChzzkTarget(kind: .live, id: String(text[idRange]))
        }
        if let match = video.firstMatch(in: text, options: [], range: range),
           let idRange = Range(match.range(at: 1), in: text) {
            return ChzzkTarget(kind: .vod, id: String(text[idRange]))
        }
        return nil
    }
}
