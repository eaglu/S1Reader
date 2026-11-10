import Foundation

/// Recognises stage1st URLs so a link inside a post can open in the app instead
/// of bouncing out to Safari.
enum Stage1stLink {
    enum Destination: Hashable {
        case thread(tid: String, pid: String?)
        case forum(fid: String)
    }

    private static let hosts = ["stage1st.com", "www.stage1st.com", "bbs.saraba1st.com", "saraba1st.com"]

    static func destination(for url: URL) -> Destination? {
        guard let host = url.host?.lowercased(), isOwnHost(host) else { return nil }
        let query = Self.query(of: url)
        let path = url.path
        let fragment = url.fragment

        // forum.php?mod=redirect&goto=findpost&ptid=…&pid=…
        if query["goto"] == "findpost", let tid = query["ptid"] ?? query["tid"] {
            let pid = query["pid"] ?? pidInFragment(fragment)
            return .thread(tid: tid, pid: pid)
        }
        if query["mod"] == "viewthread", let tid = query["tid"] {
            return .thread(tid: tid, pid: query["pid"] ?? pidInFragment(fragment))
        }
        if query["mod"] == "forumdisplay", let fid = query["fid"] {
            return .forum(fid: fid)
        }
        if query["mod"] == "viewthread" || query["tid"] != nil, let tid = query["tid"] ?? tidInPath(path) {
            return .thread(tid: tid, pid: query["pid"] ?? pidInFragment(fragment))
        }

        // thread-2291277-3-1.html
        if let tid = tidInPath(path) {
            return .thread(tid: tid, pid: pidInFragment(fragment))
        }
        // forum-6-1.html
        if let fid = fidInPath(path) {
            return .forum(fid: fid)
        }
        return nil
    }

    // MARK: - Parsing details

    /// Exact host or a subdomain of it: a plain suffix test would also accept
    /// `evilstage1st.com`, and opening a stranger's link in the in-app web view is
    /// not what tapping a link in a post should do.
    private static func isOwnHost(_ host: String) -> Bool {
        hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func query(of url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var result: [String: String] = [:]
        for item in items where item.value != nil {
            // Discuz double-encodes separators (`&amp;amp;`), which can leave a
            // literal `amp;` glued to the parameter name.
            var name = item.name
            while name.hasPrefix("amp;") { name.removeFirst(4) }
            var value = item.value ?? ""
            while value.hasPrefix("amp;") { value.removeFirst(4) }
            result[name] = value
        }
        return result
    }

    /// `#pid70354356` and `#postmessage_70354356` both point at a floor.
    private static func pidInFragment(_ fragment: String?) -> String? {
        guard let fragment else { return nil }
        let digits = fragment.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if fragment.hasPrefix("pid") || fragment.hasPrefix("postmessage_") { return digits }
        return nil
    }

    /// `thread-2291277-3-1.html` → `2291277`
    private static func tidInPath(_ path: String) -> String? {
        guard let token = path.split(separator: "/").last,
              token.hasPrefix("thread-") else { return nil }
        let parts = token.dropFirst("thread-".count).split(separator: "-")
        guard let first = parts.first, first.allSatisfy(\.isNumber) else { return nil }
        return String(first)
    }

    /// `forum-6-1.html` → `6`
    private static func fidInPath(_ path: String) -> String? {
        guard let token = path.split(separator: "/").last,
              token.hasPrefix("forum-") else { return nil }
        let parts = token.dropFirst("forum-".count).split(separator: "-")
        guard let first = parts.first, first.allSatisfy(\.isNumber) else { return nil }
        return String(first)
    }
}
