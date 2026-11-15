import Foundation

/// Case- and accent-insensitive containment, used by every "find the board or
/// thread whose title has these words" path.
enum TextMatch {
    static func matches(_ keyword: String, in text: String) -> Bool {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// A board as Siri needs to see it: enough to name it and to open it.
struct ForumRecord: Codable, Hashable, Sendable {
    let fid: String
    let name: String
    let summary: String
}

/// The board index, kept on disk so an intent can resolve "打开游戏版" without a
/// network round trip. The app writes it whenever the index loads.
///
/// `UserDefaults` is documented as thread-safe and the entity queries call into
/// this off the main actor, hence `@unchecked Sendable`.
struct ForumDirectory: @unchecked Sendable {
    static let shared = ForumDirectory()
    static let storageKey = "s1.forumDirectory"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var records: [ForumRecord] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([ForumRecord].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Replaces the whole directory. Sub-boards are flattened in, because a
    /// person says "打开手游版" and does not care that it lives under 游戏.
    func save(_ forums: [Forum]) {
        let records = Self.records(from: forums)
        guard !records.isEmpty, let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// The flattened board list, in list order, without touching disk. Also what
    /// the Spotlight donation indexes.
    static func records(from forums: [Forum]) -> [ForumRecord] {
        var seen = Set<String>()
        var records: [ForumRecord] = []
        func add(_ forum: Forum) {
            guard seen.insert(forum.fid).inserted else { return }
            records.append(ForumRecord(fid: forum.fid, name: forum.name, summary: forum.description))
            forum.subforums.forEach(add)
        }
        forums.forEach(add)
        return records
    }

    func record(fid: String) -> ForumRecord? {
        records.first { $0.fid == fid }
    }

    func records(matching keyword: String) -> [ForumRecord] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return records }
        return records.filter {
            TextMatch.matches(needle, in: $0.name) || TextMatch.matches(needle, in: $0.summary)
        }
    }
}

/// A thread the reader has opened, with the title Siri needs to recognise it.
struct RecentThread: Codable, Hashable, Sendable {
    let tid: String
    let subject: String
    let author: String
    let fid: String
    let date: Date
}

/// The threads this reader has actually looked at.
///
/// S1 has no search endpoint the app may call, so "打开《…》那个主题" is answered
/// from the threads already opened plus whatever Spotlight was given: enough for
/// the second visit, and it needs no request inside `perform()`.
struct RecentThreadStore: @unchecked Sendable {
    static let shared = RecentThreadStore()
    static let storageKey = "s1.recentThreads"
    static let limit = 60

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Newest first.
    var threads: [RecentThread] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([RecentThread].self, from: data) else {
            return []
        }
        return decoded
    }

    func record(_ thread: RecentThread) {
        var current = threads.filter { $0.tid != thread.tid }
        current.insert(thread, at: 0)
        if current.count > Self.limit {
            current = Array(current.prefix(Self.limit))
        }
        guard let data = try? JSONEncoder().encode(current) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func thread(tid: String) -> RecentThread? {
        threads.first { $0.tid == tid }
    }

    func threads(matching keyword: String) -> [RecentThread] {
        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return threads }
        return threads.filter {
            TextMatch.matches(needle, in: $0.subject) || TextMatch.matches(needle, in: $0.author)
        }
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

/// The unread-notice count as of the last time the app saw it.
struct NoticeBadge: Codable, Hashable, Sendable {
    let unread: Int
    let loggedIn: Bool
    let date: Date
}

/// Caches the notice badge so "读一下我的提醒" can answer out loud without
/// going to the network inside `perform()`.
struct NoticeBadgeStore: @unchecked Sendable {
    static let shared = NoticeBadgeStore()
    static let storageKey = "s1.noticeBadge"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var badge: NoticeBadge? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(NoticeBadge.self, from: data)
    }

    func record(unread: Int, loggedIn: Bool, at date: Date = Date()) {
        let badge = NoticeBadge(unread: max(0, unread), loggedIn: loggedIn, date: date)
        guard let data = try? JSONEncoder().encode(badge) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
