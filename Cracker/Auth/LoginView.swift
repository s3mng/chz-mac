import SwiftUI
import WebKit

private let loginURL = URL(string: "https://nid.naver.com/nidlogin.login?url=https://chzzk.naver.com/")!

struct LoginView: View {
    let store: CookieStore
    var onDone: (Bool) -> Void
    @State private var progress = 0.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    onDone(false)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("네이버 로그인")
                        .font(.system(size: 16, weight: .semibold))
                    Text("쿠키는 키체인에만 보관됩니다")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if progress > 0 && progress < 1 {
                ProgressView(value: progress)
                    .tint(.cheddar)
                    .padding(.horizontal, 16)
            }
            LoginWebView(store: store, progress: $progress, onDone: onDone)
        }
        .frame(width: 520, height: 640)
    }
}

private struct LoginWebView: NSViewRepresentable {
    let store: CookieStore
    @Binding var progress: Double
    var onDone: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, progress: $progress, onDone: onDone)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)
        context.coordinator.webView = view
        view.load(URLRequest(url: loginURL))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.removeObserver(coordinator, forKeyPath: "estimatedProgress")
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let store: CookieStore
        var progress: Binding<Double>
        var onDone: (Bool) -> Void
        weak var webView: WKWebView?
        private var finished = false

        init(store: CookieStore, progress: Binding<Double>, onDone: @escaping (Bool) -> Void) {
            self.store = store
            self.progress = progress
            self.onDone = onDone
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
            if keyPath == "estimatedProgress", let view = object as? WKWebView {
                DispatchQueue.main.async {
                    self.progress.wrappedValue = view.estimatedProgress
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let isMain = navigationAction.targetFrame?.isMainFrame ?? true
            if isMain {
                guard url.scheme == "https", let host = url.host, HostKind.isLoginNavigation(host) else {
                    decisionHandler(.cancel)
                    return
                }
            } else if url.scheme != "https" && url.scheme != "about" {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let host = webView.url?.host, HostKind.isLoginNavigation(host) else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let captured = self.store.importCookies(cookies)
                if captured && HostKind.isChzzk(host) && !self.finished {
                    self.finished = true
                    DispatchQueue.main.async {
                        self.onDone(true)
                    }
                }
            }
        }
    }
}
