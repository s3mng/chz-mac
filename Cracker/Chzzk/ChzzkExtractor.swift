import Foundation

struct ChzzkExtractor: Sendable {
    let http: HTTPClient

    func resolve(_ rawURL: String) async -> ExtractResult {
        guard let target = ChzzkURL.parse(rawURL) else {
            return .failed("치지직 라이브, 다시보기, 클립, 채널 링크를 붙여 주세요")
        }
        do {
            switch target.kind {
            case .live:
                return try await resolveLive(rawURL, channelId: target.id)
            case .vod:
                return try await resolveVideo(rawURL, videoId: target.id)
            case .clip:
                return try await resolveClip(rawURL, clipId: target.id)
            case .watch:
                return try await resolveWatch(rawURL, channelId: target.id)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func resolveLive(_ sourceURL: String, channelId: String) async throws -> ExtractResult {
        guard let api = URL(string: "https://api.chzzk.naver.com/service/v3/channels/\(channelId)/live-detail") else {
            return .failed("주소를 읽지 못했어요")
        }
        let content = try await http.getJSON(api)
        let channel = ((content["channel"] as? [String: Any])?["channelName"] as? String)?.nilIfBlank
        if (content["status"] as? String) == "CLOSE" {
            return .offline(channel)
        }
        let adult = content["adult"] as? Bool ?? false
        if adult && !isAdultAllowed(content) {
            return .needsLogin(adultReason(content))
        }
        guard let playbackRaw = (content["livePlaybackJson"] as? String)?.nilIfBlank, playbackRaw != "null",
              let playbackData = playbackRaw.data(using: .utf8),
              let playback = try JSONSerialization.jsonObject(with: playbackData) as? [String: Any],
              let media = playback["media"] as? [[String: Any]] else {
            return adult ? .needsLogin(adultReason(content)) : .failed("재생 정보를 받지 못했어요")
        }
        var hlsPath: String?
        for item in media {
            guard let path = item["path"] as? String, !path.isEmpty else { continue }
            if (item["mediaId"] as? String) != "LLHLS" {
                hlsPath = path
                break
            }
            if hlsPath == nil { hlsPath = path }
        }
        guard let hlsPath, let masterURL = URL(string: hlsPath) else {
            return .failed("HLS 주소를 찾지 못했어요")
        }
        let qualities = try await hlsQualities(masterURL)
        guard !qualities.isEmpty else { return .failed("화질 목록을 읽지 못했어요") }
        return .ready(
            VideoMeta(
                sourceURL: sourceURL,
                kind: .live,
                title: (content["liveTitle"] as? String)?.nilIfBlank ?? "치지직 라이브",
                channel: channel ?? "치지직",
                isAdult: adult,
                durationLabel: nil,
                qualities: qualities
            )
        )
    }

    private func resolveVideo(_ sourceURL: String, videoId: String) async throws -> ExtractResult {
        guard let api = URL(string: "https://api.chzzk.naver.com/service/v3/videos/\(videoId)") else {
            return .failed("주소를 읽지 못했어요")
        }
        let content = try await http.getJSON(api)
        let adult = content["adult"] as? Bool ?? false
        if adult && !isAdultAllowed(content) {
            return .needsLogin(adultReason(content))
        }
        let channel = ((content["channel"] as? [String: Any])?["channelName"] as? String)?.nilIfBlank ?? "치지직"
        let title = (content["videoTitle"] as? String)?.nilIfBlank ?? "치지직 다시보기"
        let duration = content["duration"] as? Int ?? 0
        let vodStatus = content["vodStatus"] as? String ?? ""
        let qualities: [QualityOption]
        if vodStatus == "ABR_HLS" {
            guard let nid = (content["videoId"] as? String)?.nilIfBlank, nid != "null",
                  let key = (content["inKey"] as? String)?.nilIfBlank, key != "null" else {
                return .failed("재생 키가 없어요. 로그인 상태를 확인해 주세요")
            }
            qualities = try await neonplayerQualities(videoId: nid, inKey: key, preferVersion: "v1")
        } else {
            guard let rewind = (content["liveRewindPlaybackJson"] as? String)?.nilIfBlank, rewind != "null",
                  let rewindData = rewind.data(using: .utf8),
                  let playback = try JSONSerialization.jsonObject(with: rewindData) as? [String: Any],
                  let media = playback["media"] as? [[String: Any]],
                  let path = media.first?["path"] as? String, let url = URL(string: path) else {
                return adult ? .needsLogin(adultReason(content)) : .failed("아직 받을 수 없는 다시보기예요")
            }
            qualities = try await hlsQualities(url)
        }
        guard !qualities.isEmpty else { return .failed("화질 목록을 읽지 못했어요") }
        return .ready(
            VideoMeta(
                sourceURL: sourceURL,
                kind: .vod,
                title: title,
                channel: channel,
                isAdult: adult,
                durationLabel: Formatters.duration(duration).nilIfBlank,
                qualities: qualities
            )
        )
    }

    private func resolveClip(_ sourceURL: String, clipId: String) async throws -> ExtractResult {
        guard let encoded = clipId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let api = URL(string: "https://api.chzzk.naver.com/service/v1/play-info/clip/\(encoded)") else {
            return .failed("주소를 읽지 못했어요")
        }
        let content = try await http.getJSON(api)
        let adult = content["adult"] as? Bool ?? false
        if adult && !isAdultAllowed(content) {
            return .needsLogin(adultReason(content))
        }
        guard let nid = (content["videoId"] as? String)?.nilIfBlank, nid != "null",
              let key = (content["inKey"] as? String)?.nilIfBlank, key != "null" else {
            return adult ? .needsLogin(adultReason(content)) : .failed("받을 수 없는 클립이에요")
        }
        let qualities = try await neonplayerQualities(videoId: nid, inKey: key, preferVersion: "v2")
        guard !qualities.isEmpty else { return .failed("화질 목록을 읽지 못했어요") }
        let channel = ((content["ownerChannel"] as? [String: Any])?["channelName"] as? String)?.nilIfBlank ?? "치지직"
        return .ready(
            VideoMeta(
                sourceURL: sourceURL,
                kind: .clip,
                title: (content["contentTitle"] as? String)?.nilIfBlank ?? "치지직 클립",
                channel: channel,
                isAdult: adult,
                durationLabel: nil,
                qualities: qualities
            )
        )
    }

    private func resolveWatch(_ sourceURL: String, channelId: String) async throws -> ExtractResult {
        let snapshot = try await liveSnapshot(channelId)
        if !snapshot.isOpen {
            return .offline(snapshot.channel)
        }
        if snapshot.adult && !snapshot.adultAllowed {
            return .needsLogin(snapshot.adultReason)
        }
        guard let page = URL(string: "https://chzzk.naver.com/\(channelId)") else {
            return .failed("주소를 읽지 못했어요")
        }
        return .ready(
            VideoMeta(
                sourceURL: sourceURL,
                kind: .watch,
                title: snapshot.title,
                channel: snapshot.channel ?? "치지직",
                isAdult: snapshot.adult,
                durationLabel: "방송 끝나면 다시보기",
                qualities: [
                    QualityOption(
                        id: QualityOption.watchPlaceholderId,
                        label: "최고",
                        note: "최대 15분 대기",
                        protocolKind: .dash,
                        mediaURL: page
                    )
                ],
                channelId: channelId,
                openDate: snapshot.openDate
            )
        )
    }

    func liveSnapshot(_ channelId: String) async throws -> LiveSnapshot {
        guard let api = URL(string: "https://api.chzzk.naver.com/service/v3/channels/\(channelId)/live-detail") else {
            throw TransferError.message("주소를 읽지 못했어요")
        }
        let content = try await http.getJSON(api)
        let adult = content["adult"] as? Bool ?? false
        return LiveSnapshot(
            isOpen: (content["status"] as? String) == "OPEN",
            liveId: content["liveId"] as? Int ?? (content["liveId"] as? NSNumber)?.intValue,
            title: (content["liveTitle"] as? String)?.nilIfBlank ?? "치지직 라이브",
            channel: ((content["channel"] as? [String: Any])?["channelName"] as? String)?.nilIfBlank,
            openDate: (content["openDate"] as? String)?.nilIfBlank,
            adult: adult,
            adultAllowed: isAdultAllowed(content),
            adultReason: adultReason(content)
        )
    }

    func findReplayVideoNo(channelId: String, liveTitle: String, openDate: String?) async throws -> String? {
        guard let api = URL(
            string: "https://api.chzzk.naver.com/service/v1/channels/\(channelId)/videos?sortType=LATEST&pagingType=PAGE&page=0&size=20&videoType=REPLAY"
        ) else {
            return nil
        }
        let content = try await http.getJSON(api)
        let rows = (content["data"] as? [[String: Any]]) ?? (content["videos"] as? [[String: Any]]) ?? []
        func videoNo(_ row: [String: Any]) -> String? {
            if let value = row["videoNo"] as? Int { return String(value) }
            if let value = row["videoNo"] as? NSNumber { return value.stringValue }
            return (row["videoNo"] as? String)?.nilIfBlank
        }
        if let match = rows.first(where: { ($0["videoTitle"] as? String) == liveTitle }),
           let no = videoNo(match) {
            if openDate == nil { return no }
            if let detailURL = URL(string: "https://api.chzzk.naver.com/service/v3/videos/\(no)") {
                let detail = try await http.getJSON(detailURL)
                if (detail["liveOpenDate"] as? String) == openDate {
                    return no
                }
            }
        }
        guard let openDate else { return nil }
        for row in rows.prefix(8) {
            guard let no = videoNo(row),
                  let detailURL = URL(string: "https://api.chzzk.naver.com/service/v3/videos/\(no)") else {
                continue
            }
            let detail = try await http.getJSON(detailURL)
            if (detail["liveOpenDate"] as? String) == openDate {
                return no
            }
        }
        return nil
    }

    func videoIfReady(videoId: String) async throws -> VideoMeta? {
        let result = try await resolveVideo("https://chzzk.naver.com/video/\(videoId)", videoId: videoId)
        switch result {
        case .ready(let meta):
            return meta
        case .needsLogin(let reason):
            throw TransferError.message(reason)
        case .offline:
            return nil
        case .failed(let message):
            if message.contains("아직") || message.contains("재생 키") {
                return nil
            }
            throw TransferError.message(message)
        }
    }

    private func neonplayerQualities(videoId: String, inKey: String, preferVersion: String) async throws -> [QualityOption] {
        let versions = preferVersion == "v2" ? ["v2", "v1"] : ["v1", "v2"]
        var lastError: Error?
        for version in versions {
            var components = URLComponents(string: "https://apis.naver.com/neonplayer/vodplay/\(version)/playback/\(videoId)")
            var query = [URLQueryItem(name: "key", value: inKey)]
            if version == "v1" {
                query += [
                    URLQueryItem(name: "env", value: "real"),
                    URLQueryItem(name: "lc", value: "en_US"),
                    URLQueryItem(name: "cpl", value: "en_US"),
                ]
            }
            components?.queryItems = query
            guard let mpdURL = components?.url else { continue }
            do {
                let qualities = try await dashQualities(mpdURL)
                if !qualities.isEmpty { return qualities }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    private func hlsQualities(_ url: URL) async throws -> [QualityOption] {
        let body = try await http.getText(url)
        if !HlsParser.isMaster(body) {
            return [
                QualityOption(id: "source", label: "원본", note: "HLS", protocolKind: .hls, mediaURL: url)
            ]
        }
        return HlsParser.parseMaster(body, playlistURL: url).enumerated().map { index, variant in
            let label = variant.height.map { "\($0)p" } ?? "\(variant.bandwidth / 1000)k"
            let codec = VideoCodec.shortLabel(variant.codecs)
            let noteParts = [codec, index == 0 ? "추천" : nil].compactMap { $0 }
            return QualityOption(
                id: "hls-\(index)-\(variant.height ?? variant.bandwidth)",
                label: label,
                note: noteParts.isEmpty ? "HLS" : noteParts.joined(separator: " · "),
                protocolKind: .hls,
                mediaURL: variant.uri
            )
        }
    }

    private func dashQualities(_ mpdURL: URL) async throws -> [QualityOption] {
        let xml = try await http.getText(mpdURL, headers: ["Accept": "application/dash+xml"])
        let reps = DashParser.parse(xml, mpdURL: mpdURL)
        let videos = reps.filter { $0.contentType == "video" }.sorted {
            VideoCodec.betterForPlayback(
                ($0.height, $0.codecs, $0.bandwidth),
                ($1.height, $1.codecs, $1.bandwidth)
            )
        }
        let audioId = reps.filter { $0.contentType == "audio" }.max(by: { $0.bandwidth < $1.bandwidth })?.id
        return videos.enumerated().map { index, video in
            let codec = VideoCodec.shortLabel(video.codecs)
            let noteParts = [codec, index == 0 ? "추천" : nil].compactMap { $0 }
            return QualityOption(
                id: "dash-\(video.id)",
                label: video.height.map { "\($0)p" } ?? video.id,
                note: noteParts.isEmpty ? "DASH" : noteParts.joined(separator: " · "),
                protocolKind: .dash,
                mediaURL: mpdURL,
                dashVideoRepId: video.id,
                dashAudioRepId: audioId
            )
        }
    }

    private func isAdultAllowed(_ content: [String: Any]) -> Bool {
        (content["userAdultStatus"] as? String) == "ADULT"
    }

    private func adultReason(_ content: [String: Any]) -> String {
        if (content["userAdultStatus"] as? String) == "ADULT" {
            return "성인 인증이 필요해요"
        }
        return "성인 영상은 본인 인증된 네이버 로그인이 필요해요"
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct LiveSnapshot: Sendable {
    let isOpen: Bool
    let liveId: Int?
    let title: String
    let channel: String?
    let openDate: String?
    let adult: Bool
    let adultAllowed: Bool
    let adultReason: String
}

extension QualityOption {
    static let watchPlaceholderId = "watch-best"
}
