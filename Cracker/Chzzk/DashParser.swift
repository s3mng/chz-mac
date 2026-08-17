import Foundation

struct DashRepresentation: Sendable {
    let id: String
    let contentType: String
    let bandwidth: Int
    let width: Int?
    let height: Int?
    let codecs: String?
    let segmentURLs: [URL]
}

enum DashParser {
    static func parse(_ xml: String, mpdURL: URL) -> [DashRepresentation] {
        let parser = DashXMLParser(mpdURL: mpdURL)
        parser.parse(xml)
        return parser.results
    }
}

private struct TimelineS {
    var t: Int64?
    var d: Int64
    var r: Int
}

private final class OpenRep {
    let id: String
    let bandwidth: Int
    let width: Int?
    let height: Int?
    var codecs: String?
    var timescale: Int64?
    var duration: Int64?
    var startNumber: Int64?
    var initTemplate: String?
    var media: String?
    var timeline: [TimelineS]?
    var segmentList: [String]?
    var base: URL

    init(id: String, bandwidth: Int, width: Int?, height: Int?, codecs: String?, base: URL) {
        self.id = id
        self.bandwidth = bandwidth
        self.width = width
        self.height = height
        self.codecs = codecs
        self.base = base
    }
}

private final class DashXMLParser: NSObject, XMLParserDelegate {
    private let root: URL
    private var baseStack: [URL]
    private(set) var results: [DashRepresentation] = []
    private var mpdDuration = 0.0
    private var periodDuration = 0.0
    private var asType = ""
    private var asCodecs = ""
    private var asBase: URL?
    private var asTimescale: Int64 = 1
    private var asDuration: Int64 = 0
    private var asStartNumber: Int64 = 1
    private var asInit: String?
    private var asMedia: String?
    private var asTimeline: [TimelineS] = []
    private var asSegmentList: [String] = []
    private var openRep: OpenRep?
    private var timelineBuf: [TimelineS] = []
    private var listBuf: [String] = []
    private var inTimeline = false
    private var inSegmentList = false
    private var currentElement = ""
    private var textBuffer = ""

    init(mpdURL: URL) {
        root = mpdURL
        baseStack = [mpdURL]
    }

    func parse(_ xml: String) {
        let xmlParser = XMLParser(data: Data(xml.utf8))
        xmlParser.delegate = self
        xmlParser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        textBuffer = ""
        switch elementName {
        case "MPD":
            if let value = attributeDict["mediaPresentationDuration"] {
                mpdDuration = Formatters.isoDurationSeconds(value)
            }
        case "Period":
            periodDuration = attributeDict["duration"].map(Formatters.isoDurationSeconds) ?? mpdDuration
            asType = ""
            asCodecs = ""
            asBase = nil
            asTimescale = 1
            asDuration = 0
            asStartNumber = 1
            asInit = nil
            asMedia = nil
            asTimeline = []
            asSegmentList = []
        case "AdaptationSet":
            asType = attributeDict["contentType"]
                ?? attributeDict["mimeType"]?.split(separator: "/").first.map(String.init)
                ?? ""
            asCodecs = attributeDict["codecs"] ?? ""
        case "Representation":
            let mime = attributeDict["mimeType"] ?? ""
            let type: String
            if !asType.isEmpty {
                type = asType
            } else if mime.hasPrefix("video") {
                type = "video"
            } else if mime.hasPrefix("audio") {
                type = "audio"
            } else if attributeDict["height"] != nil {
                type = "video"
            } else {
                type = "audio"
            }
            asType = type
            openRep = OpenRep(
                id: attributeDict["id"] ?? "",
                bandwidth: Int(attributeDict["bandwidth"] ?? "") ?? 0,
                width: Int(attributeDict["width"] ?? ""),
                height: Int(attributeDict["height"] ?? ""),
                codecs: {
                    let value = attributeDict["codecs"] ?? asCodecs
                    return value.isEmpty ? nil : value
                }(),
                base: asBase ?? baseStack.last ?? root
            )
        case "SegmentTemplate":
            let timescale = Int64(attributeDict["timescale"] ?? "") ?? 1
            let duration = Int64(attributeDict["duration"] ?? "") ?? 0
            let start = Int64(attributeDict["startNumber"] ?? "") ?? 1
            if let rep = openRep {
                rep.timescale = timescale
                rep.duration = duration
                rep.startNumber = start
                rep.initTemplate = attributeDict["initialization"]
                rep.media = attributeDict["media"]
            } else {
                asTimescale = timescale
                asDuration = duration
                asStartNumber = start
                asInit = attributeDict["initialization"]
                asMedia = attributeDict["media"]
            }
        case "SegmentTimeline":
            inTimeline = true
            timelineBuf = []
        case "S":
            if inTimeline {
                timelineBuf.append(
                    TimelineS(
                        t: attributeDict["t"].flatMap(Int64.init),
                        d: Int64(attributeDict["d"] ?? "") ?? 0,
                        r: Int(attributeDict["r"] ?? "") ?? 0
                    )
                )
            }
        case "SegmentList":
            inSegmentList = true
            listBuf = []
        case "Initialization":
            let source = attributeDict["sourceURL"] ?? attributeDict["media"]
            if let source {
                if let rep = openRep {
                    rep.initTemplate = source
                } else {
                    asInit = source
                }
            }
        case "SegmentURL":
            if inSegmentList, let media = attributeDict["media"] {
                listBuf.append(media)
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "BaseURL" {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "BaseURL":
            let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, let last = baseStack.last, let resolved = URL(string: text, relativeTo: last)?.absoluteURL {
                baseStack.append(resolved)
                if let rep = openRep {
                    rep.base = resolved
                } else {
                    asBase = resolved
                }
            }
        case "SegmentTimeline":
            inTimeline = false
            if let rep = openRep {
                rep.timeline = timelineBuf
            } else {
                asTimeline = timelineBuf
            }
        case "SegmentList":
            inSegmentList = false
            if let rep = openRep {
                rep.segmentList = listBuf
            } else {
                asSegmentList = listBuf
            }
        case "Representation":
            if let rep = openRep {
                let urls = buildURLs(
                    base: rep.base,
                    repId: rep.id,
                    bandwidth: rep.bandwidth,
                    initTemplate: rep.initTemplate ?? asInit,
                    media: rep.media ?? asMedia,
                    list: rep.segmentList ?? asSegmentList,
                    timeline: rep.timeline ?? asTimeline,
                    timescale: rep.timescale ?? asTimescale,
                    duration: rep.duration ?? asDuration,
                    startNumber: rep.startNumber ?? asStartNumber,
                    periodSeconds: periodDuration
                )
                if !urls.isEmpty {
                    results.append(
                        DashRepresentation(
                            id: rep.id,
                            contentType: asType.isEmpty ? "video" : asType,
                            bandwidth: rep.bandwidth,
                            width: rep.width,
                            height: rep.height,
                            codecs: rep.codecs,
                            segmentURLs: urls
                        )
                    )
                }
            }
            openRep = nil
        case "Period", "AdaptationSet":
            while baseStack.count > 1 {
                baseStack.removeLast()
            }
        default:
            break
        }
        currentElement = ""
        textBuffer = ""
    }

    private func buildURLs(
        base: URL,
        repId: String,
        bandwidth: Int,
        initTemplate: String?,
        media: String?,
        list: [String],
        timeline: [TimelineS],
        timescale: Int64,
        duration: Int64,
        startNumber: Int64,
        periodSeconds: Double
    ) -> [URL] {
        func resolve(_ ref: String, number: Int64? = nil, time: Int64? = nil) -> URL? {
            let expanded = expandTemplate(ref, repId: repId, bandwidth: bandwidth, number: number, time: time)
            return URL(string: expanded, relativeTo: base)?.absoluteURL
        }
        var urls: [URL] = []
        if let initTemplate, let url = resolve(initTemplate, number: startNumber, time: 0) {
            urls.append(url)
        }
        if !list.isEmpty {
            urls.append(contentsOf: list.compactMap { resolve($0) })
            return urls
        }
        guard let media else { return urls }
        if !timeline.isEmpty {
            var time = timeline.first?.t ?? 0
            var number = startNumber
            for item in timeline {
                if let t = item.t { time = t }
                for _ in 0..<(item.r + 1) {
                    if let url = resolve(media, number: number, time: time) {
                        urls.append(url)
                    }
                    time += item.d
                    number += 1
                }
            }
            return urls
        }
        if duration > 0 && periodSeconds > 0 {
            let count = max(Int(ceil(periodSeconds * Double(timescale) / Double(duration))), 1)
            for i in 0..<count {
                let number = startNumber + Int64(i)
                let time = Int64(i) * duration
                if let url = resolve(media, number: number, time: time) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func expandTemplate(_ template: String, repId: String, bandwidth: Int, number: Int64?, time: Int64?) -> String {
        var value = template
            .replacingOccurrences(of: "$RepresentationID$", with: repId)
            .replacingOccurrences(of: "$Bandwidth$", with: String(bandwidth))
        value = replaceToken(value, name: "Number", raw: number)
        value = replaceToken(value, name: "Time", raw: time)
        return value
    }

    private func replaceToken(_ input: String, name: String, raw: Int64?) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\$\(name)(%[^$]+)?\\$") else { return input }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        var output = input
        let matches = regex.matches(in: input, options: [], range: range).reversed()
        for match in matches {
            guard let full = Range(match.range, in: output) else { continue }
            guard let raw else { continue }
            let fmtRange = match.range(at: 1)
            let replacement: String
            if fmtRange.location != NSNotFound, let fmt = Range(fmtRange, in: output) {
                let spec = String(output[fmt].dropFirst())
                replacement = String(format: "%\(spec)", raw)
            } else {
                replacement = String(raw)
            }
            output.replaceSubrange(full, with: replacement)
        }
        return output
    }
}
