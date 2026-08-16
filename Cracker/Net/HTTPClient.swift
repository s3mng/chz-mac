import Foundation

final class HTTPClient: @unchecked Sendable {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/132.0.0.0 Safari/537.36"

    private let cookies: CookieStore
    private let session: URLSession

    init(cookies: CookieStore) {
        self.cookies = cookies
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
        session = URLSession(configuration: config)
    }

    func getText(_ url: URL) async throws -> String {
        let (data, response) = try await data(from: url)
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

    func data(from url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        applyCookie(&request)
        return try await session.data(for: request)
    }

    private func applyCookie(_ request: inout URLRequest) {
        guard let host = request.url?.host, HostKind.isNaver(host), let header = cookies.cookieHeader() else { return }
        request.setValue(header, forHTTPHeaderField: "Cookie")
    }
}
