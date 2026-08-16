import Foundation

struct AppSettings {
    static let maxRetries = 5
    static let defaultRetries = 2
    static let defaultFolderName = "cracker"
    static let defaultFolderLabel = "Movies/cracker"
}

final class SettingsStore: @unchecked Sendable {
    private let defaults = UserDefaults.standard
    private let retriesKey = "vodRetries"
    private let bookmarkKey = "downloadFolderBookmark"
    private let lock = NSLock()

    var vodRetries: Int {
        get {
            if defaults.object(forKey: retriesKey) == nil { return AppSettings.defaultRetries }
            return min(max(defaults.integer(forKey: retriesKey), 0), AppSettings.maxRetries)
        }
        set {
            defaults.set(min(max(newValue, 0), AppSettings.maxRetries), forKey: retriesKey)
        }
    }

    var customFolder: URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale {
            if let refreshed = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(refreshed, forKey: bookmarkKey)
            }
        }
        return url
    }

    func setCustomFolder(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    func clearCustomFolder() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: bookmarkKey)
    }

    func folderLabel() -> String {
        if let custom = customFolder {
            return custom.lastPathComponent
        }
        return AppSettings.defaultFolderLabel
    }

    func defaultMoviesFolder() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies")
        return movies.appendingPathComponent(AppSettings.defaultFolderName, isDirectory: true)
    }
}

final class JobStore {
    private let url: URL
    static let maxCount = 80

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = dir.appendingPathComponent("Cracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("jobs.json")
    }

    func load() -> [DownloadJob] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DownloadJob].self, from: data)) ?? []
    }

    func save(_ jobs: [DownloadJob]) {
        let sliced = Array(jobs.prefix(Self.maxCount))
        guard let data = try? JSONEncoder().encode(sliced) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
