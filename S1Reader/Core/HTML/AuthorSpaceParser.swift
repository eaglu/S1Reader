import Foundation

/// Reads a member's thread and reply lists out of their Discuz space page.
///
/// There is no mobile-API endpoint for somebody else's history: `mythread` and
/// `mypost` only ever describe the signed-in member (and S1 does not ship them
/// at all), while `module=profile` ignores the `uid` it is given. The space
/// pages below are the only place the lists exist, and they are HTML:
///
///     home.php?mod=space&uid=<uid>&do=thread&view=me&type=thread&page=N
///     home.php?mod=space&uid=<uid>&do=thread&view=me&type=reply&page=N
///
/// They need a session cookie. A guest is answered with a "请先登录后才能继续
/// 浏览" page, which `Failure.loginRequired` reports instead of pretending the
/// author never posted.
///
/// The parser keys off the table Discuz! X3.5 renders (`space_thread.htm`) but
/// stays tolerant: an unfamiliar cell is skipped rather than taking the whole
/// page down. Every entry point is a pure function so it can be tested against
/// captured markup.
enum AuthorSpaceParser {

    // MARK: - Results

    struct ThreadItem: Identifiable, Hashable, Sendable {
        let tid: String
        let subject: String
        let forumName: String
        let replies: Int
        let views: Int
        /// Who replied last, and Discuz's own relative stamp ("半小时前").
        let lastPoster: String
        let lastPost: String
        /// The thread's posting time, when the page prints it. The `view=me`
        /// table shows the *last reply* instead, so this is usually empty.
        let dateline: String

        var id: String { tid }
    }

    struct ReplyItem: Identifiable, Hashable, Sendable {
        let pid: String
        let tid: String
        let threadSubject: String
        let forumName: String
        let snippet: String
        /// Only present when the page carries it: the stock space-reply table
        /// prints the message, not the time it was written.
        let dateline: String
        /// Floor number, likewise only when the page prints it.
        let position: Int?

        var id: String { pid }
    }

    struct PageInfo: Hashable, Sendable {
        let page: Int
        let totalPages: Int?
        let hasMore: Bool
    }

    struct ThreadPage: Hashable, Sendable {
        let items: [ThreadItem]
        let pageInfo: PageInfo

        var hasMore: Bool { pageInfo.hasMore }
    }

    struct ReplyPage: Hashable, Sendable {
        let items: [ReplyItem]
        let pageInfo: PageInfo

        var hasMore: Bool { pageInfo.hasMore }
    }

    enum Failure: LocalizedError, Equatable {
        case loginRequired

        var errorDescription: String? {
            switch self {
            case .loginRequired:
                return "登录后才能查看 Ta 的更多帖子"
            }
        }
    }

    // MARK: - Entry points

    /// Threads the author started.
    static func threads(fromHTML html: String, page: Int = 1) throws -> ThreadPage {
        guard !isLoginPrompt(html) else { throw Failure.loginRequired }
        let items = AuthorSpaceTable.rows(in: html).compactMap(AuthorSpaceTable.threadItem(from:))
        return ThreadPage(items: items, pageInfo: pageInfo(in: html, page: page))
    }

    /// Replies the author wrote, one entry per floor. Discuz prints the
    /// containing thread as a header row and its floors as the rows below it.
    static func replies(fromHTML html: String, page: Int = 1) throws -> ReplyPage {
        guard !isLoginPrompt(html) else { throw Failure.loginRequired }

        var items: [ReplyItem] = []
        var seen = Set<String>()
        var context: ThreadItem?

        for row in AuthorSpaceTable.rows(in: html) {
            if let thread = AuthorSpaceTable.threadItem(from: row) {
                context = thread
                continue
            }
            guard let context,
                  let cell = row.cells.first,
                  let link = cell.links.first(where: { AuthorSpaceTable.isThreadLink($0.href) }),
                  let pid = AuthorSpaceTable.pid(in: link.href),
                  seen.insert(pid).inserted
            else { continue }

            let body = AuthorSpaceTable.cleaned(link.text)
            items.append(ReplyItem(
                pid: pid,
                tid: context.tid,
                threadSubject: context.subject,
                forumName: context.forumName,
                snippet: body.isEmpty ? "（无正文）" : body,
                dateline: AuthorSpaceTable.cleaned(cell.ems.first ?? ""),
                position: AuthorSpaceTable.position(in: cell.text)
            ))
        }
        return ReplyPage(items: items, pageInfo: pageInfo(in: html, page: page))
    }

    /// Whether the page is Discuz's "log in first" notice rather than a list.
    ///
    /// The wording is checked rather than the login-form markup: every guest
    /// page (including a list that happened to render) links to
    /// `member.php?mod=logging`, so the link alone means nothing.
    static func isLoginPrompt(_ html: String) -> Bool {
        let markers = [
            "login_before_enter_home",
            "请先登录后才能继续浏览",
            "需要先登录才能继续浏览",
            "您需要登录后才可以查看"
        ]
        return markers.contains { html.contains($0) }
    }

    // MARK: - Pagination

    /// Reads the pager. Discuz writes "共 N 页" next to links back into
    /// `home.php`, so those links are used and thread multipage links (which
    /// also carry `page=`) are ignored.
    static func pageInfo(in html: String, page: Int) -> PageInfo {
        let current = max(1, page)
        let total = totalPages(in: html)
        var lastPage = current

        if let regex = try? NSRegularExpression(
            pattern: "home\\.php\\?[^\"'<>\\s]*?(?:&amp;|[?&])page=(\\d+)"
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                if let digits = Range(match.range(at: 1), in: html),
                   let value = Int(html[digits]) {
                    lastPage = max(lastPage, value)
                }
            }
        }

        let highest = max(total ?? current, lastPage)
        return PageInfo(page: current, totalPages: total, hasMore: highest > current)
    }

    private static func totalPages(in html: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "共\\s*(\\d+)\\s*[页頁]") else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let digits = Range(match.range(at: 1), in: html) else { return nil }
        return Int(html[digits])
    }
}
