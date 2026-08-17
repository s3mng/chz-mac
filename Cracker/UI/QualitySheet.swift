import SwiftUI

struct QualitySheet: View {
    let meta: VideoMeta
    let isLoggedIn: Bool
    var onConfirm: () -> Void
    var onDismiss: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kindTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(meta.kind.isLive ? Color.liveCoral : Color.secondary)
            Text(meta.title)
                .font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text([meta.channel, meta.durationLabel].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if meta.isAdult {
                AdultBanner(isLoggedIn: isLoggedIn)
            }
            Text(autoPickLine)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            let needsLogin = meta.isAdult && !isLoggedIn
            Button(action: needsLogin ? onLogin : onConfirm) {
                Text(buttonTitle(needsLogin: needsLogin))
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Color.black)
            Button("취소", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 420)
    }

    private func buttonTitle(needsLogin: Bool) -> String {
        if needsLogin { return "로그인하고 받기" }
        switch meta.kind {
        case .live: return "녹화 시작"
        case .watch: return "대기 시작"
        case .vod, .clip: return "다운로드"
        }
    }

    private var kindTitle: String {
        switch meta.kind {
        case .live: "라이브 녹화"
        case .vod: "다시보기 저장"
        case .clip: "클립 저장"
        case .watch: "다시보기 대기"
        }
    }

    private var autoPickLine: String {
        if meta.kind == .watch {
            return "방송이 끝나면 다시보기를 최대 15분 기다립니다. 다시보기는 가장 잘 열리는 화질로 받습니다."
        }
        guard let quality = meta.qualities.first else {
            return "가장 잘 열리는 화질로 저장합니다."
        }
        let codec = quality.note
            .replacingOccurrences(of: " · 추천", with: "")
            .replacingOccurrences(of: "추천", with: "")
            .trimmingCharacters(in: .whitespaces)
        if codec.isEmpty || codec == "HLS" || codec == "DASH" {
            return "\(quality.label)로 저장합니다."
        }
        return "\(quality.label) · \(codec)로 저장합니다."
    }
}

private struct AdultBanner: View {
    let isLoggedIn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("성인 콘텐츠")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.adultClay)
            Text(
                isLoggedIn
                    ? "로그인된 네이버 계정으로만 기기에 요청합니다. 쿠키는 밖으로 나가지 않아요."
                    : "이 영상은 본인 인증된 네이버 로그인이 필요합니다. 쿠키는 이 기기의 키체인에만 둡니다."
            )
            .font(.system(size: 13))
            .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.adultClay.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

