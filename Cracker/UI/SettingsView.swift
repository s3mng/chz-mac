import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                accountCard
                folderCard
                retryCard
                cacheCard
                sleepNote
            }
            .padding(20)
        }
        .frame(width: 420, height: 560)
        .background(CrackerTheme.background(.light).opacity(0.001))
        .onAppear(perform: model.refreshCache)
        .sheet(isPresented: $model.showLogin) {
            LoginView(store: model.cookies) { _ in
                model.showLogin = false
                model.refreshLogin()
            }
        }
    }

    private var accountCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person")
                    .foregroundStyle(Color.cheddar)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isLoggedIn ? "네이버 연결됨" : "네이버 로그인")
                        .font(.system(size: 16, weight: .semibold))
                    Text("쿠키는 키체인에만 보관됩니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if model.isLoggedIn {
                Button("로그아웃", action: model.logout)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Button("네이버 로그인") {
                    model.showLogin = true
                }
                .buttonStyle(CheddarButtonStyle())
            }
        }
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.cheddar)
                    Text("저장 위치")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                Text(model.folderLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Button("폴더 선택", action: model.pickFolder)
                .buttonStyle(CheddarButtonStyle())
            if model.hasCustomFolder {
                Button("기본 위치로 되돌리기", action: model.resetFolder)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var retryCard: some View {
        SettingsCard {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(Color.cheddar)
                VStack(alignment: .leading, spacing: 2) {
                    Text("다시보기 재시도")
                        .font(.system(size: 16, weight: .semibold))
                    Text(model.vodRetries == 0 ? "실패하면 바로 끝냅니다" : "실패하면 최대 \(model.vodRetries)번 다시 받습니다")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        model.setRetries(model.vodRetries - 1)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(model.vodRetries <= 0)
                    Text("\(model.vodRetries)")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 18)
                    Button {
                        model.setRetries(model.vodRetries + 1)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(model.vodRetries >= AppSettings.maxRetries)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var cacheCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsCard {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(Color.cheddar)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("다운로드 캐시")
                            .font(.system(size: 16, weight: .semibold))
                        Text(model.cacheBytes == 0 ? "끊긴 받기는 없어요" : Formatters.bytes(model.cacheBytes))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("다시보기를 받다가 끊긴 조각만 남습니다. 받는 중인 파일은 지우지 않아요.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Button("캐시 지우기", action: model.clearCache)
                .buttonStyle(CheddarButtonStyle())
                .disabled(model.cacheBytes == 0)
                .opacity(model.cacheBytes == 0 ? 0.45 : 1)
        }
    }

    private var sleepNote: some View {
        Text("다운로드 중에는 맥이 혼자 잠들지 않게만 막습니다. 덮개를 닫으면 그때는 끊길 수 있어요.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct CheddarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.cheddar.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(Color.ink)
    }
}
