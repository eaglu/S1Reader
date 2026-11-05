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
    private var tids: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.tids = Set(defaults.stringArray(forKey: key) ?? [])
    }

    var count: Int { tids.count }

    func prefersGuest(tid: String) -> Bool {
        tids.contains(tid)
    }

    func mark(_ tid: String) {
        guard tids.insert(tid).inserted else { return }
        persist()
    }

    func unmark(_ tid: String) {
        guard tids.remove(tid) != nil else { return }
        persist()
    }

    func clear() {
        guard !tids.isEmpty else { return }
        tids.removeAll()
        persist()
    }

    private func persist() {
        var list = Array(tids)
        if list.count > limit {
            list = Array(list.suffix(limit))
            tids = Set(list)
        }
        defaults.set(list, forKey: key)
    }
}
