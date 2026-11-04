import Foundation

/// Remembers which images belong to which thread, so one thread's cached pictures can
/// be dropped without touching the rest of the cache.
@MainActor
final class ImageCacheIndex {
    static let shared = ImageCacheIndex()

    struct Entry: Codable, Identifiable {
        var tid: String
        var title: String
        var urls: [String]
        var updatedAt: Date

        var id: String { tid }
    }

    /// Newest first; older threads fall off the list (their files stay until cleared).
    private(set) var entries: [Entry] = []
    private let limit = 60
    private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    func urls(for tid: String) -> [URL] {
        guard let entry = entries.first(where: { $0.tid == tid }) else { return [] }
        return entry.urls.compactMap(URL.init(string:))
    }

    func register(tid: String, title: String, urls: [URL]) {
        guard !urls.isEmpty else { return }
        let incoming = urls.map(\.absoluteString)

        if let index = entries.firstIndex(where: { $0.tid == tid }) {
            var entry = entries[index]
            let merged = entry.urls + incoming.filter { !entry.urls.contains($0) }
            entry.urls = merged
            entry.title = title.isEmpty ? entry.title : title
            entry.updatedAt = Date()
            entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                Entry(tid: tid, title: title, urls: incoming, updatedAt: Date()),
                at: 0
            )
        }

        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        scheduleSave()
    }

    func remove(tid: String) async {
        guard let entry = entries.first(where: { $0.tid == tid }) else { return }
        entries.removeAll { $0.tid == tid }
        scheduleSave()
        await ImageLoader.shared.clearImages(for: entry.urls.compactMap(URL.init(string:)))
    }

    func removeAll() async {
        let all = entries.flatMap(\.urls).compactMap(URL.init(string:))
        entries.removeAll()
        scheduleSave()
        await ImageLoader.shared.clearImages(for: all)
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let base = URL.applicationSupportDirectory
        return base.appending(path: "ImageCacheIndex.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Bookkeeping only: failing to persist must never break browsing.
        }
    }
}
