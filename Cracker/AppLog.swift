import Foundation

final class AppLog: @unchecked Sendable {
    static let shared = AppLog()
    static let maxLines = 8_000

    private let lock = NSLock()
    private var lines: [String] = []
    private let url: URL
    private let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Cracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("app.log")
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            lines = text.split(whereSeparator: \.isNewline).map(String.init)
            if lines.count > Self.maxLines {
                lines = Array(lines.suffix(Self.maxLines))
                persistLocked()
            }
        }
    }

    func i(_ message: String) { append("I", message) }
    func w(_ message: String) { append("W", message) }
    func e(_ message: String) { append("E", message) }

    static func clip(_ value: String, _ limit: Int = 28) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        lines = []
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
        i("log clear")
    }

    private func append(_ level: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) \(level) \(message)"
        lock.lock()
        lines.append(line)
        let overflow = lines.count > Self.maxLines
        if overflow {
            lines.removeFirst(lines.count - Self.maxLines)
            persistLocked()
        } else {
            appendFileLocked(line)
        }
        lock.unlock()
    }

    private func appendFileLocked(_ line: String) {
        let data = Data((line + "\n").utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
        }
        persistLocked()
    }

    private func persistLocked() {
        let text = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
