import Foundation
import Observation

/// Remembers how many replies a thread had when it was last read, so the thread
/// list can show how many replies arrived since.
@MainActor
@Observable
final class ThreadVisitStore {
    static let shared = ThreadVisitStore()

    struct Seen: Codable {
        let replies: Int
        let date: Date
    }

    private static let storageKey = "s1.threadVisitSeen"
    /// Keeps the defaults file small; the oldest entries go first.
    private static let limit = 800

    private var entries: [String: Seen]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: Seen].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
        #if DEBUG
        seedFromEnvironment()
        #endif
    }

    private let defaults: UserDefaults

    /// Replies added since the thread was last opened; 0 for a thread that was
    /// never opened, so untouched threads stay clean.
    func newReplies(for tid: String, replies: Int) -> Int {
        guard let seen = entries[tid] else { return 0 }
        return max(0, replies - seen.replies)
    }

    /// Records the current reply count as read.
    func markSeen(tid: String, replies: Int) {
        let current = max(0, replies)
        if let seen = entries[tid], seen.replies == current {
            entries[tid] = Seen(replies: current, date: Date())
            return
        }
        entries[tid] = Seen(replies: current, date: Date())
        prune()
        persist()
    }

    var count: Int { entries.count }

    func clear() {
        entries = [:]
        persist()
    }

    private func prune() {
        guard entries.count > Self.limit else { return }
        let keep = entries
            .sorted { $0.value.date > $1.value.date }
            .prefix(Self.limit)
        entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    #if DEBUG
    /// `S1_SEEN=<tid>:<replies>` pretends the thread was read when it had that
    /// many replies, so the list badge can be checked without clicking around.
    private func seedFromEnvironment() {
        guard let raw = ProcessInfo.processInfo.environment["S1_SEEN"] else { return }
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let replies = Int(parts[1]) else { continue }
            entries[String(parts[0])] = Seen(replies: replies, date: Date())
        }
        persist()
        print("S1_SEEN seeded \(entries.count) entries")
    }
    #endif
}
