import Foundation
import ImageIO
import UIKit

/// Remembers the aspect ratio of every picture we have seen.
///
/// Without it a post image is a mystery box until it arrives: the row grows from
/// a guess to the real height and everything below jumps. Knowing the ratio up
/// front lets the placeholder take exactly the space the picture will need.
@MainActor
final class ImageAspectStore {
    static let shared = ImageAspectStore()

    private let defaults: UserDefaults
    private let key = "s1.imageAspects"
    private let limit = 800
    private var cache: [String: CGFloat]
    private var pendingFlush: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: CGFloat].self, from: data) {
            cache = decoded
        } else {
            cache = [:]
        }
    }

    func aspect(for url: URL) -> CGFloat? {
        cache[url.absoluteString]
    }

    func store(aspect: CGFloat, for url: URL) {
        guard aspect.isFinite, aspect > 0.02, aspect < 50 else { return }
        let key = url.absoluteString
        if let existing = cache[key], abs(existing - aspect) < 0.01 { return }
        cache[key] = aspect
        if cache.count > limit {
            // Cheap eviction: the dictionary has no order, so drop a slice.
            for candidate in cache.keys.prefix(cache.count - limit) {
                cache.removeValue(forKey: candidate)
            }
        }
        scheduleFlush()
    }

    /// Writing on every image would hammer UserDefaults while scrolling.
    private func scheduleFlush() {
        pendingFlush?.cancel()
        pendingFlush = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.flush()
        }
    }

    func flush() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: key)
    }
}
