import Foundation

// ActivityKit exists in the macOS SDK but its types are unavailable there, so
// the file is wrapped for the platform that has them. Every real target is iOS.
#if os(iOS)
import ActivityKit

/// One reading session, mirrored into the Lock Screen and the Dynamic Island
/// while the reader is away from the app.
///
/// The file lives in `Shared/` because both sides compile it: the app starts and
/// updates the activity, the `S1ReaderWidgets` extension renders it. Everything
/// here is plain data, so the app has no reason to hand the extension anything
/// but a `ContentState`.
struct ReadingActivityAttributes: ActivityAttributes {
    /// What changes while the reader is in the thread: the page they are on and
    /// the header they are looking at. The thread id is fixed for the life of
    /// the activity, so it stays an attribute.
    struct ContentState: Codable, Hashable {
        var title: String
        var page: Int
        var pageCount: Int
        var author: String?
        var excerpt: String

        /// Longest excerpt kept for the Lock Screen line: one line of text, not
        /// the opening post.
        static let excerptLimit = 80

        init(
            title: String,
            page: Int,
            pageCount: Int,
            author: String? = nil,
            excerpt: String = ""
        ) {
            // The widget renders whatever it is given, including a stale state
            // written before the server said how many pages there are, so the
            // numbers are made sane here rather than in three view builders.
            let safeCount = max(1, pageCount)
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.page = min(max(1, page), safeCount)
            self.pageCount = safeCount
            let name = author?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.author = (name?.isEmpty ?? true) ? nil : name
            self.excerpt = Self.shorten(excerpt)
        }

        /// "第 398/483 页" — the lock screen and the expanded island.
        var pageLabel: String { "第 \(page)/\(pageCount) 页" }

        /// "398/483" — the compact island has room for numbers, not words.
        var compactPageLabel: String { "\(page)/\(pageCount)" }

        /// How far through the thread the reader is, for the lock-screen bar.
        var progress: Double {
            guard pageCount > 1 else { return page > 0 ? 1 : 0 }
            return min(1, max(0, Double(page - 1) / Double(pageCount - 1)))
        }

        /// True before the header has a title: nothing worth putting on the lock
        /// screen, so the activity is not started at all.
        var isReady: Bool { !title.isEmpty }

        private static func shorten(_ text: String) -> String {
            let flattened = text
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard flattened.count > excerptLimit else { return flattened }
            return String(flattened.prefix(excerptLimit)) + "…"
        }
    }

    /// The thread being read. `s1reader://thread?tid=…&page=…` carries the same
    /// id back when the island is tapped.
    var tid: String

    /// Where a tap on the activity lands. Built here (and parsed by
    /// `AppDeepLink`) so the widget and the tests agree on one spelling.
    static func deepLink(tid: String, page: Int) -> URL {
        var components = URLComponents()
        components.scheme = "s1reader"
        components.host = "thread"
        components.queryItems = [
            URLQueryItem(name: "tid", value: tid),
            URLQueryItem(name: "page", value: String(max(1, page))),
        ]
        // Every component is a literal or a number, so nothing here can fail.
        return components.url ?? URL(string: "s1reader://thread")!
    }
}
#endif
