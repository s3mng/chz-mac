import SwiftUI

struct QualitySheet: View {
    let meta: VideoMeta
    @Binding var selectedQualityId: String?
    let isLoggedIn: Bool
    var onConfirm: () -> Void
    var onDismiss: () -> Void
    var onLogin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kindTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(meta.kind.isLive ? Color.liveCoral : Color.cheddar)
            Text(meta.title)
                .font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text([meta.channel, meta.durationLabel].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if meta.isAdult {
                AdultBanner(isLoggedIn: isLoggedIn)
            }
            Text("화질")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            FlowQualities(qualities: meta.qualities, selectedId: $selectedQualityId)
            let needsLogin = meta.isAdult && !isLoggedIn
            Button(action: needsLogin ? onLogin : onConfirm) {
                Text(buttonTitle(needsLogin: needsLogin))
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(Color.cheddar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(Color.ink)
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
        return meta.kind.isLive ? "녹화 시작" : "다운로드"
    }

    private var kindTitle: String {
        switch meta.kind {
        case .live: "라이브 녹화"
        case .vod: "다시보기 저장"
        case .clip: "클립 저장"
        }
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

private struct FlowQualities: View {
    let qualities: [QualityOption]
    @Binding var selectedId: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(qualities) { option in
                let selected = option.id == selectedId
                Button {
                    selectedId = option.id
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.system(size: 13, weight: .semibold))
                        Text(option.note)
                            .font(.system(size: 10, weight: .medium))
                            .opacity(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selected ? Color.cheddar : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(selected ? Color.ink : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
