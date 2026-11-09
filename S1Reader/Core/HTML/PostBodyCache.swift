import Foundation

/// Keeps the parsed body of a post around, keyed by pid and text scale.
///
/// Rows are recycled constantly while scrolling, and a long thread re-renders
/// the same 40 posts many times; without this cache every re-appearance runs the
/// HTML parser again. It is an actor so the in-flight bookkeeping needs no locks.
actor PostBodyCache {
    static let shared = PostBodyCache()

    private final class Body: NSObject {
        let nodes: [PostNode]
        init(_ nodes: [PostNode]) { self.nodes = nodes }
    }

    private let cache: NSCache<NSString, Body> = {
        let cache = NSCache<NSString, Body>()
        cache.countLimit = 400
        return cache
    }()

    /// Parses already running, so warming and the row can share one pass.
    private var inflight: [NSString: Task<[PostNode], Never>] = [:]

    #if DEBUG
    private var parseCount = 0
    private var parseMillis: Double = 0
    #endif

    private func key(pid: String, scale: CGFloat) -> NSString {
        PostBodyCache.cacheKey(pid: pid, scale: scale) as NSString
    }

    /// Cache key, shared with `PostNodeMirror` so both stores agree.
    nonisolated static func cacheKey(pid: String, scale: CGFloat) -> String {
        "\(pid)@\(scale)"
    }

    /// Returns the parsed nodes, parsing off the caller's thread on a miss.
    /// Every result is also published to the main-actor mirror, so the *next*
    /// row built for this post can draw it synchronously.
    func nodes(pid: String, html: String, scale: CGFloat) async -> [PostNode] {
        let nodes = await parseIfNeeded(pid: pid, html: html, scale: scale)
        await MainActor.run {
            PostNodeMirror.shared.store(nodes, pid: pid, scale: scale)
        }
        return nodes
    }

    private func parseIfNeeded(pid: String, html: String, scale: CGFloat) async -> [PostNode] {
        let key = key(pid: pid, scale: scale)
        if let cached = cache.object(forKey: key) { return cached.nodes }
        if let running = inflight[key] {
            let nodes = await running.value
            cache.setObject(Body(nodes), forKey: key)
            return nodes
        }

        let task = Task.detached(priority: .userInitiated) {
            PostBodyCache.parseMeasured(html: html, scale: scale)
        }
        inflight[key] = task
        let nodes = await task.value
        inflight[key] = nil
        cache.setObject(Body(nodes), forKey: key)
        return nodes
    }

    /// Parses ahead of time so a row that scrolls in has nothing to do.
    ///
    /// Sequential on purpose: fanning out six at a time measured slower on device
    /// (839ms vs 150ms for three pages) because the parses fight for the same cores.
    func warm(posts: [Post], scale: CGFloat) async {
        for post in posts where cache.object(forKey: key(pid: post.pid, scale: scale)) == nil {
            _ = await nodes(pid: post.pid, html: post.message, scale: scale)
        }
    }

    func removeAll() {
        cache.removeAllObjects()
        inflight.removeAll()
        Task { @MainActor in PostNodeMirror.shared.removeAll() }
    }

    private static func parseMeasured(html: String, scale: CGFloat) -> [PostNode] {
        let start = Date()
        let nodes = HTMLParser.parse(html, scale: scale)
        #if DEBUG
        let elapsed = Date().timeIntervalSince(start) * 1000
        PostBodyCache.record(ms: elapsed)
        #endif
        return nodes
    }

    #if DEBUG
    /// Lock-protected counters, since parsing happens off the actor.
    private final class Stats: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var millis: Double = 0

        func add(ms: Double) {
            lock.lock()
            count += 1
            millis += ms
            lock.unlock()
        }

        func drain() -> (count: Int, millis: Double) {
            lock.lock()
            let snapshot = (count, millis)
            count = 0
            millis = 0
            lock.unlock()
            return snapshot
        }
    }

    private static let stats = Stats()

    private static func record(ms: Double) {
        stats.add(ms: ms)
    }

    /// Temporary instrumentation: `S1_PERF=1` prints how much parsing happened.
    func reportAndReset(_ label: String) {
        let snapshot = PostBodyCache.stats.drain()
        let count = snapshot.count
        let millis = snapshot.millis
        let average = count > 0 ? String(format: "%.2f", millis / Double(count)) : "0"
        print("S1_PERF \(label) parses=\(count) total=\(String(format: "%.1f", millis))ms avg=\(average)ms")
    }
    #endif
}

/// Main-actor copy of the parsed bodies, so a rebuilt row can draw its final
/// content in its *first* layout pass.
///
/// `LazyVStack` throws a row's `@State` away when it scrolls out and builds a
/// fresh one on the way back. Fetching the cached nodes from the actor takes at
/// least one frame, and in that frame the row would be a one-line skeleton: every
/// rebuilt row *above* the viewport collapsed to nothing and then grew back,
/// which is what shoved the reply being read down the screen while scrolling up.
/// Reading the mirror is synchronous, so the row is never laid out at the wrong
/// height in the first place.
@MainActor
final class PostNodeMirror {
    static let shared = PostNodeMirror()

    private var bodies: [String: [PostNode]] = [:]
    /// Keys in arrival order, so eviction drops the oldest body instead of a
    /// random slice of the dictionary.
    private var order: [String] = []
    private let limit = 400

    func nodes(pid: String, scale: CGFloat) -> [PostNode]? {
        bodies[PostBodyCache.cacheKey(pid: pid, scale: scale)]
    }

    func store(_ nodes: [PostNode], pid: String, scale: CGFloat) {
        let key = PostBodyCache.cacheKey(pid: pid, scale: scale)
        if bodies.updateValue(nodes, forKey: key) == nil {
            order.append(key)
            while order.count > limit {
                bodies.removeValue(forKey: order.removeFirst())
            }
        }
    }

    func removeAll() {
        bodies.removeAll()
        order.removeAll()
    }
}
