import Foundation

final class HTTPClient: @unchecked Sendable {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"

    private let cookies: CookieStore
    private let redirects: RedirectGuard
    private let session: URLSession

    init(cookies: CookieStore) {
        self.cookies = cookies
        let redirects = RedirectGuard(cookies: cookies)
        self.redirects = redirects
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 90
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "*/*",
            "Origin": "https://chzzk.naver.com",
            "Referer": "https://chzzk.naver.com/",
        ]
        session = URLSession(configuration: config, delegate: redirects, delegateQueue: nil)
    }

    func getText(_ url: URL, headers: [String: String] = [:]) async throws -> String {
        let (data, response) = try await data(from: url, headers: headers)
        guard let http = response as? HTTPURLResponse else {
            throw TransferError.message("응답이 없어요")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TransferError.message("HTTP \(http.statusCode)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    func getJSON(_ url: URL) async throws -> [String: Any] {
        let text = try await getText(url)
        guard let root = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw TransferError.message("치지직 응답이 비어 있어요")
        }
        guard let content = root["content"] as? [String: Any] else {
            throw TransferError.message("치지직 응답이 비어 있어요")
        }
        return content
    }

    func download(_ url: URL, to handle: FileHandle) async throws {
        var request = URLRequest(url: url)
        applyCookie(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TransferError.message("HTTP \(code)")
        }
        try handle.write(contentsOf: data)
    }

    func data(from url: URL, headers: [String: String] = [:]) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        applyCookie(&request)
        return try await session.data(for: request)
    }

    private func applyCookie(_ request: inout URLRequest) {
        guard let host = request.url?.host, HostKind.needsSessionCookie(host), let header = cookies.cookieHeader() else { return }
        request.setValue(header, forHTTPHeaderField: "Cookie")
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let cookies: CookieStore

    init(cookies: CookieStore) {
        self.cookies = cookies
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, url.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            return
        }
        var next = request
        if let host = url.host, HostKind.needsSessionCookie(host) {
            next.setValue(cookies.cookieHeader(), forHTTPHeaderField: "Cookie")
        } else {
            next.setValue(nil, forHTTPHeaderField: "Cookie")
        }
        completionHandler(next)
    }
}
