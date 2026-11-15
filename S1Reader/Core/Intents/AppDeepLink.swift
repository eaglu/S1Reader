import Foundation

/// Every way into a screen from outside the app: `s1reader://` links (Siri,
/// Shortcuts, Spotlight, Safari) and the route an intent leaves behind when it
/// is performed.
///
/// The two halves are deliberately dumb data: parsing and building a URL is
/// testable without App Intents, without a running app and without a network.
enum AppDeepLink: Hashable, Sendable {
    case forum(fid: String)
    case thread(tid: String, pid: String?)
    case notices
    case favorites

    static let scheme = "s1reader"

    /// The canonical URL for the link; `parse` accepts it back unchanged.
    var url: URL {
        switch self {
        case .forum(let fid):
            return Self.make(host: "forum", query: ["fid": fid])
        case .thread(let tid, let pid):
            var query = ["tid": tid]
            if let pid, !pid.isEmpty { query["pid"] = pid }
            return Self.make(host: "thread", query: query)
        case .notices:
            return Self.make(host: "notices", query: [:])
        case .favorites:
            return Self.make(host: "favorites", query: [:])
        }
    }

    /// `s1reader://thread?tid=123&pid=456`, `s1reader:///forum/6` and
    /// `s1reader://notices` all arrive; anything else is not ours.
    static func parse(_ url: URL) -> AppDeepLink? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        var parts: [String] = []
        if let host = url.host, !host.isEmpty { parts.append(host) }
        parts.append(contentsOf: url.path.split(separator: "/").map(String.init))
        guard let action = parts.first?.lowercased() else { return nil }
        let path = Array(parts.dropFirst())

        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            guard let value = item.value, !value.isEmpty else { continue }
            // Dictation and hand-built shortcuts do not agree on the case of a
            // parameter name; the values (ids) are digits either way.
            query[item.name.lowercased()] = value
        }
        func value(_ name: String, at index: Int) -> String? {
            if let fromQuery = query[name], !fromQuery.isEmpty { return fromQuery }
            return index < path.count ? path[index] : nil
        }

        switch action {
        case "forum":
            guard let fid = value("fid", at: 0) else { return nil }
            return .forum(fid: fid)
        case "thread":
            guard let tid = value("tid", at: 0) else { return nil }
            return .thread(tid: tid, pid: value("pid", at: 1))
        case "notices", "notice", "alerts":
            return .notices
        case "favorites", "favourites", "bookmarks":
            return .favorites
        default:
            return nil
        }
    }

    private static func make(host: String, query: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if !query.isEmpty {
            components.queryItems = query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        // The host is a literal and every component above is percent-encoded by
        // URLComponents, so this cannot fail; falling back keeps the type total.
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }
}

/// Hands a link from an intent to the UI.
///
/// Intents run with the app in the background or not running yet, so the link
/// is written to defaults *and* announced; whichever of the two the UI is
/// listening for when it wakes up is enough, and a route left behind by a run
/// that never reached the UI is picked up on the next launch.
enum PendingDeepLink {
    static let defaultsKey = "s1.pendingDeepLink"
    static let didArrive = Notification.Name("s1.deepLinkArrived")

    static func post(_ link: AppDeepLink, defaults: UserDefaults = .standard) {
        defaults.set(link.url.absoluteString, forKey: defaultsKey)
        NotificationCenter.default.post(name: didArrive, object: nil)
    }

    /// Reads the link once; a second call returns nil.
    static func take(defaults: UserDefaults = .standard) -> AppDeepLink? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        defaults.removeObject(forKey: defaultsKey)
        guard let url = URL(string: raw) else { return nil }
        return AppDeepLink.parse(url)
    }
}
