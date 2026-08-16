import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var jobToDelete: DownloadJob?
    @State private var confirmClearAll = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                LinearGradient(
                    colors: [CrackerTheme.wash(colorScheme), CrackerTheme.background(colorScheme)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                if model.jobs.isEmpty {
                    emptyState
                } else {
                    queueList
                }
            }
            UrlBar(value: $model.url, resolving: model.isResolving, onSubmit: model.submitURL)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .padding(.top, 8)
        }
        .background(CrackerTheme.background(colorScheme))
        .frame(minWidth: 420, idealWidth: 440, minHeight: 560, idealHeight: 720)
        .sheet(item: pendingBinding) { meta in
            QualitySheet(
                meta: meta,
                selectedQualityId: $model.selectedQualityId,
                isLoggedIn: model.isLoggedIn,
                onConfirm: model.confirmPending,
                onDismiss: model.dismissSheet,
                onLogin: { model.showLogin = true }
            )
            .sheet(isPresented: $model.showLogin) {
                loginSheet
            }
        }
        .sheet(isPresented: Binding(
            get: { model.showLogin && model.pendingMeta == nil },
            set: { model.showLogin = $0 }
        )) {
            loginSheet
        }
        .alert("큐에서 삭제", isPresented: Binding(
            get: { jobToDelete != nil },
            set: { if !$0 { jobToDelete = nil } }
        )) {
            Button("삭제", role: .destructive) {
                if let jobToDelete { model.removeJob(jobToDelete.id) }
                jobToDelete = nil
            }
            Button("취소", role: .cancel) { jobToDelete = nil }
        } message: {
            Text(jobToDelete?.title ?? "")
        }
        .alert("전체 삭제", isPresented: $confirmClearAll) {
            Button("삭제", role: .destructive, action: model.clearQueue)
            Button("취소", role: .cancel) {}
        } message: {
            Text("진행 중인 작업도 멈추고 목록을 비울까요?")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
    }

    private var loginSheet: some View {
        LoginView(store: model.cookies) { _ in
            model.showLogin = false
            model.refreshLogin()
        }
    }

    private var pendingBinding: Binding<VideoMeta?> {
        Binding(
            get: { model.pendingMeta },
            set: { model.pendingMeta = $0 }
        )
    }

    private var header: some View {
        HStack {
            Wordmark()
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .help("설정")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            CheeseMark(size: 72)
            Text("아직 아무것도 없어요")
                .font(.system(size: 22, weight: .semibold))
            Text("라이브는 녹화하고, 다시보기는 파일로 받아요.\n아래 칸에 치지직 링크만 넣으면 됩니다.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("큐")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("전체 삭제") { confirmClearAll = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12, weight: .medium))
                }
                ForEach(model.jobs) { job in
                    JobCard(
                        job: job,
                        onCancel: { model.cancelJob(job.id) },
                        onTogglePause: { model.togglePause(job.id) },
                        onDelete: { jobToDelete = job }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }
}

extension VideoMeta: Identifiable {
    var id: String { sourceURL + title }
}
