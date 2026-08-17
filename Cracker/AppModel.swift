import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    var url = ""
    var jobs: [DownloadJob] = []
    var isLoggedIn = false
    var isResolving = false
    var pendingMeta: VideoMeta?
    var toast: String?
    var showLogin = false
    var vodRetries: Int
    var folderLabel: String
    var hasCustomFolder: Bool
    var cacheBytes: Int64 = 0

    var logText = ""

    let cookies: CookieStore
    private let settings: SettingsStore
    private let extractor: ChzzkExtractor
    private let coordinator: TransferCoordinator
    private var toastTask: Task<Void, Never>?

    init() {
        let cookies = CookieStore()
        let settings = SettingsStore()
        let http = HTTPClient(cookies: cookies)
        self.cookies = cookies
        self.settings = settings
        extractor = ChzzkExtractor(http: http)
        coordinator = TransferCoordinator(http: http, settings: settings)
        isLoggedIn = cookies.isLoggedIn
        vodRetries = settings.vodRetries
        folderLabel = settings.folderLabel()
        hasCustomFolder = settings.customFolder != nil
        jobs = coordinator.snapshot
        cacheBytes = coordinator.cacheByteCount()
        logText = AppLog.shared.snapshot()
        coordinator.onChange = { [weak self] jobs in
            Task { @MainActor in
                self?.jobs = jobs
                self?.cacheBytes = self?.coordinator.cacheByteCount() ?? 0
            }
        }
    }

    var hasActiveTransfer: Bool { coordinator.hasActiveTransfer }

    func submitURL() {
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        isResolving = true
        toast = nil
        Task {
            AppLog.shared.i("resolve \(AppLog.clip(raw, 48))")
            let result = await extractor.resolve(raw)
            isResolving = false
            switch result {
            case .ready(let meta):
                pendingMeta = meta
                AppLog.shared.i("resolve \(meta.kind.rawValue) \(AppLog.clip(meta.title, 20)) q=\(meta.qualities.count)")
            case .needsLogin(let reason):
                AppLog.shared.w("resolve login \(reason)")
                flash(reason)
            case .offline(let channel):
                AppLog.shared.i("resolve offline \(channel ?? "-")")
                flash((channel.map { "\($0)님은 " } ?? "") + "지금 방송 중이 아니에요")
            case .failed(let message):
                AppLog.shared.e("resolve fail \(message)")
                flash(message)
            }
        }
    }

    func dismissSheet() {
        pendingMeta = nil
    }

    func confirmPending() {
        guard let meta = pendingMeta else { return }
        if meta.isAdult && !cookies.isLoggedIn {
            flash("성인 영상은 네이버 로그인이 필요해요")
            return
        }
        guard let quality = meta.qualities.first else { return }
        coordinator.enqueue(meta: meta, quality: quality)
        url = ""
        pendingMeta = nil
    }

    func cancelJob(_ id: String) { coordinator.cancel(id: id) }
    func removeJob(_ id: String) { coordinator.remove(id: id) }
    func clearQueue() { coordinator.clearAll() }
    func togglePause(_ id: String) { coordinator.togglePause(id: id) }

    func logout() {
        cookies.clear()
        refreshLogin()
        AppLog.shared.i("logout")
    }

    func refreshLogin() {
        isLoggedIn = cookies.isLoggedIn
    }

    func setRetries(_ value: Int) {
        settings.vodRetries = value
        vodRetries = settings.vodRetries
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "선택"
        panel.message = "영상을 저장할 폴더"
        if let current = settings.customFolder {
            panel.directoryURL = current
        } else {
            panel.directoryURL = settings.defaultMoviesFolder()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setCustomFolder(url)
        folderLabel = settings.folderLabel()
        hasCustomFolder = true
        AppLog.shared.i("folder \(url.path)")
    }

    func resetFolder() {
        settings.clearCustomFolder()
        folderLabel = settings.folderLabel()
        hasCustomFolder = false
        AppLog.shared.i("folder reset")
    }

    func refreshCache() {
        cacheBytes = coordinator.cacheByteCount()
    }

    func clearCache() {
        let removed = coordinator.clearInactiveCache()
        cacheBytes = coordinator.cacheByteCount()
        if removed <= 0 {
            flash("지울 캐시가 없어요")
        } else {
            AppLog.shared.i("cache clear \(Formatters.bytes(removed))")
            flash("캐시 \(Formatters.bytes(removed))를 지웠어요")
        }
    }

    func refreshLog() {
        logText = AppLog.shared.snapshot()
    }

    func copyLog() {
        let text = AppLog.shared.snapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text.isEmpty ? "로그가 없어요" : text, forType: .string)
        flash("로그를 복사했어요")
    }

    func clearLog() {
        AppLog.shared.clear()
        logText = AppLog.shared.snapshot()
    }

    func flash(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { toast = nil }
        }
    }
}
