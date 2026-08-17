import SwiftUI

struct JobCard: View {
    let job: DownloadJob
    var onCancel: () -> Void
    var onTogglePause: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ChannelMark(name: job.channel, kind: job.kind, running: job.status == .running)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        StatusChip(job: job)
                        if job.isAdult {
                            Text("19")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.adultClay)
                        }
                        Text(job.quality)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(job.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                JobActions(job: job, onCancel: onCancel, onTogglePause: onTogglePause)
            }
            if !job.kind.isLive && job.kind != .watch && ![.completed, .failed, .cancelled].contains(job.status) {
                ProgressView(value: min(max(job.progress, 0), 1))
                    .tint(.white)
            }
            if job.kind == .watch && job.status == .running && job.isWatchHold {
                LivePulseBar()
            }
            if job.kind == .watch && ![.completed, .failed, .cancelled].contains(job.status) && !job.isWatchHold {
                ProgressView(value: min(max(job.progress, 0), 1))
                    .tint(.white)
            }
            if job.kind.isLive && job.status == .running {
                LivePulseBar()
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            Button("큐에서 삭제", role: .destructive, action: onDelete)
        }
    }

    private var caption: String {
        [job.channel, job.elapsedLabel, job.speedLabel, statusCaption(job)].compactMap { $0 }.joined(separator: "  ·  ")
    }
}

private struct JobActions: View {
    let job: DownloadJob
    var onCancel: () -> Void
    var onTogglePause: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if job.kind.canPause && [.running, .paused].contains(job.status) {
                Button(action: onTogglePause) {
                    Image(systemName: job.status == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.plain)
                .help(job.status == .paused ? "다시 받기" : "일시정지")
            }
            if [.running, .paused, .queued].contains(job.status) {
                Button(action: onCancel) {
                    Image(systemName: job.kind.isLive ? "stop.fill" : "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(job.kind.isLive ? "녹화 중지" : "취소")
            }
        }
        .font(.system(size: 13, weight: .semibold))
    }
}

private struct StatusChip: View {
    let job: DownloadJob

    var body: some View {
        let pair: (String, Color) = {
            if job.kind.isLive && job.status == .running { return ("LIVE", .liveCoral) }
            if job.kind == .watch && job.status == .running && job.isWatchHold { return ("WAIT", Color.secondary) }
            switch job.status {
            case .paused: return ("PAUSED", Color.secondary)
            case .completed: return ("DONE", .okSage)
            case .cancelled: return ("CANCEL", Color.secondary)
            case .failed: return ("FAIL", .liveCoral)
            case .stopped: return ("STOP", Color.secondary)
            case .queued: return ("WAIT", Color.secondary)
            case .running: return (job.kind == .clip ? "CLIP" : "VOD", Color.primary)
            }
        }()
        Text(pair.0)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(pair.1)
    }
}

private struct ChannelMark: View {
    let name: String
    let kind: JobKind
    let running: Bool

    var body: some View {
        let palette: [Color] = [.okSage, .liveCoral, .adultClay, Color(red: 0.48, green: 0.64, blue: 0.77), Color(white: 0.55)]
        let color = palette[abs(name.hashValue) % palette.count]
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.22))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                }
            if kind.isLive && running {
                Circle()
                    .fill(Color.liveCoral)
                    .frame(width: 9, height: 9)
                    .offset(x: 2, y: -2)
            }
        }
    }
}

private struct LivePulseBar: View {
    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.28))
            .frame(height: 5)
    }
}

private func statusCaption(_ job: DownloadJob) -> String? {
    switch job.status {
    case .running:
        if job.kind.isLive { return "녹화 중" }
        if job.kind == .watch && job.isWatchHold {
            return job.isReplayHold ? "다시보기 대기" : "방송 중"
        }
        let percent = Int(job.progress * 100)
        if job.attempt > 1 { return "\(percent)% · 재시도 \(job.attempt)/\(job.maxAttempts)" }
        return "\(percent)%"
    case .paused: return "일시정지"
    case .completed: return "저장됨"
    case .cancelled: return "취소"
    case .failed: return job.error ?? "실패"
    case .stopped: return job.error ?? "중지"
    case .queued: return "대기"
    }
}
