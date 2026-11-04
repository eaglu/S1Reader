import Foundation

struct ReadingPosition: Codable, Sendable {
    let pid: String
    let position: Int
    let updatedAt: Date
}

/// Remembers where the reader left off in each thread, keyed by tid.
@MainActor
final class ReadingProgressStore {
    static let shared = ReadingProgressStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "s1.readingPositions"
    private let maxEntries = 300

    private var cache: [String: ReadingPosition]

    private init() {
        cache = Self.decode(defaults.data(forKey: storageKey))
    }

    func position(for tid: String) -> ReadingPosition? {
        cache[tid]
    }

    func save(tid: String, pid: String, position: Int) {
        guard !pid.isEmpty, position > 0 else { return }
        if let existing = cache[tid], existing.pid == pid, existing.position == position {
            return
        }
        cache[tid] = ReadingPosition(pid: pid, position: position, updatedAt: Date())
        pruneIfNeeded()
        persist()
    }

    func clear(tid: String) {
        guard cache.removeValue(forKey: tid) != nil else { return }
        persist()
    }

    private func pruneIfNeeded() {
        guard cache.count > maxEntries else { return }
        let keep = cache
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(maxEntries)
        cache = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func decode(_ data: Data?) -> [String: ReadingPosition] {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: ReadingPosition].self, from: data) else {
            return [:]
        }
        return decoded
    }
}
