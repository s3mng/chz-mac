import Foundation
import Security

final class CookieStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pair: (aut: String, ses: String)?
    private let service = "app.cracker.mac.naver"

    var isLoggedIn: Bool {
        lock.lock()
        defer { lock.unlock() }
        return pair != nil
    }

    init() {
        if let saved = load() {
            pair = saved
        }
    }

    func cookieHeader() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let pair else { return nil }
        return "NID_AUT=\(pair.aut); NID_SES=\(pair.ses)"
    }

    @discardableResult
    func importCookieHeader(_ header: String) -> Bool {
        var map: [String: String] = [:]
        for part in header.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            map[key] = value
        }
        guard let aut = map["NID_AUT"], let ses = map["NID_SES"], !aut.isEmpty, !ses.isEmpty else {
            return false
        }
        save(aut: aut, ses: ses)
        return true
    }

    func importCookies(_ cookies: [HTTPCookie]) -> Bool {
        let naver = cookies.filter { HostKind.isNaver($0.domain) }
        let header = naver.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return importCookieHeader(header)
    }

    func save(aut: String, ses: String) {
        lock.lock()
        pair = (aut, ses)
        lock.unlock()
        persist(aut: aut, ses: ses)
    }

    func clear() {
        lock.lock()
        pair = nil
        lock.unlock()
        delete()
    }

    private func persist(aut: String, ses: String) {
        let payload = "\(aut)\n\(ses)".data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "nid",
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = payload
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func load() -> (aut: String, ses: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "nid",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    private func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "nid",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
