import Foundation

struct ChzzkExtractor: Sendable {
    let http: HTTPClient

    func resolve(_ rawURL: String) async -> ExtractResult {
        guard let target = ChzzkURL.parse(rawURL) else {
            return .failed("치지직 라이브나 다시보기 링크를 붙여 주세요")
        }
        do {
            switch target.kind {
            case .live:
                return try await resolveLive(rawURL, channelId: target.id)
            case .vod:
                return try await resolveVideo(rawURL, videoId: target.id)
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
            var components = URLComponents(string: "https://apis.naver.com/neonplayer/vodplay/v1/playback/\(nid)")
            components?.queryItems = [
                URLQueryItem(name: "key", value: key),
                URLQueryItem(name: "env", value: "real"),
                URLQueryItem(name: "lc", value: "en_US"),
                URLQueryItem(name: "cpl", value: "en_US"),
            ]
            guard let mpdURL = components?.url else { return .failed("재생 주소를 만들지 못했어요") }
            qualities = try await dashQualities(mpdURL)
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

    private func hlsQualities(_ url: URL) async throws -> [QualityOption] {
        let body = try await http.getText(url)
        if !HlsParser.isMaster(body) {
            return [
                QualityOption(id: "source", label: "원본", note: "HLS", protocolKind: .hls, mediaURL: url)
            ]
        }
        return HlsParser.parseMaster(body, playlistURL: url).enumerated().map { index, variant in
            let label = variant.height.map { "\($0)p" } ?? "\(variant.bandwidth / 1000)k"
            return QualityOption(
                id: "hls-\(index)-\(variant.height ?? variant.bandwidth)",
                label: label,
                note: index == 0 ? "HLS · 추천" : "HLS",
                protocolKind: .hls,
                mediaURL: variant.uri
            )
        }
    }

    private func dashQualities(_ mpdURL: URL) async throws -> [QualityOption] {
        let xml = try await http.getText(mpdURL)
        let reps = DashParser.parse(xml, mpdURL: mpdURL)
        let videos = reps.filter { $0.contentType == "video" }.sorted { ($0.height ?? 0) > ($1.height ?? 0) }
        let audioId = reps.filter { $0.contentType == "audio" }.max(by: { $0.bandwidth < $1.bandwidth })?.id
        return videos.enumerated().map { index, video in
            QualityOption(
                id: "dash-\(video.id)",
                label: video.height.map { "\($0)p" } ?? video.id,
                note: index == 0 ? "DASH · 추천" : "DASH",
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
