import Foundation

/// Remembers threads whose `viewthread` request fails while a session cookie is
/// attached. S1's mobile API answers a handful of threads with a bare Discuz
/// "System Error" (HTTP 503) for signed-in users only, so once a thread is known
/// to misbehave the detail view talks to the API as a guest from the start.
@MainActor
final class GuestFallbackStore {
    static let shared = GuestFallbackStore()

    private let key = "{{SECRET_9t5yf6bd}}"
    private let limit = 200
    private let defaults: UserDefaults
    /// Insertion order, oldest first. A `Set` alone loses it, and evicting by
    /// arbitrary set order can drop the thread that was just marked.
    private var order: [String]
    private var tids: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded: [String] = []
        var seen: Set<String> = []
        for tid in defaults.stringArray(forKey: key) ?? [] where seen.insert(tid).inserted {
            loaded.append(tid)
        }
        self.order = loaded
        self.tids = seen
    }

    var count: Int { tids.count }

    func prefersGuest(tid: String) -> Bool {
        tids.contains(tid)
    }

    func mark(_ tid: String) {
        guard tids.insert(tid).inserted else { return }
        order.append(tid)
        persist()
    }

    func unmark(_ tid: String) {
        guard tids.remove(tid) != nil else { return }
        order.removeAll { $0 == tid }
        persist()
    }

    func clear() {
        guard !tids.isEmpty else { return }
        tids.removeAll()
        order.removeAll()
        persist()
    }

    private func persist() {
        if order.count > limit {
            order.removeFirst(order.count - limit)
            tids = Set(order)
        }
        defaults.set(order, forKey: key)
    }
}
