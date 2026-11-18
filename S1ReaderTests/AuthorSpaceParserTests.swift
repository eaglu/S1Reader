import XCTest
@testable import S1Reader

/// Covers the HTML side of the author card: the space pages are the only place
/// another member's history exists, so the parser is tested against captured
/// markup rather than a live account.
final class AuthorSpaceParserTests: XCTestCase {

    // MARK: - Thread lists

    func testThreadListReadsEveryColumn() throws {
        let page = try AuthorSpaceParser.threads(fromHTML: SpaceFixture.authorThreadsHTML)
        XCTAssertEqual(page.items.count, 2)

        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(first.tid, "12345")
        XCTAssertEqual(first.subject, "周末补番推荐 & 讨论")
        XCTAssertEqual(first.forumName, "游戏区")
        XCTAssertEqual(first.replies, 42)
        XCTAssertEqual(first.views, 310)
        XCTAssertEqual(first.lastPoster, "某甲")
        XCTAssertEqual(first.lastPost, "半小时前")

        let second = try XCTUnwrap(page.items.last)
        XCTAssertEqual(second.tid, "67890")
        XCTAssertEqual(second.subject, "有谁记得这部老番")
        XCTAssertEqual(second.replies, 0)
        XCTAssertEqual(second.views, 12)
    }

    func testHeaderRowIsNotAThread() throws {
        let page = try AuthorSpaceParser.threads(fromHTML: SpaceFixture.authorThreadsHTML)
        XCTAssertFalse(page.items.contains { $0.subject == "主题" })
        XCTAssertEqual(page.items.map(\.tid), ["12345", "67890"])
    }

    func testEmptyListIsEmptyNotAnError() throws {
        let page = try AuthorSpaceParser.threads(fromHTML: SpaceFixture.emptyThreadsHTML)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertNil(page.pageInfo.totalPages)
        XCTAssertFalse(page.hasMore)
        XCTAssertEqual(page.pageInfo.page, 1)
    }

    func testMissingFieldsFallBackWithoutDroppingTheRow() throws {
        let page = try AuthorSpaceParser.threads(fromHTML: SpaceFixture.partialThreadHTML)
        let item = try XCTUnwrap(page.items.first)
        XCTAssertEqual(item.tid, "24680")
        XCTAssertEqual(item.subject, "价格<100 的显示器")
        XCTAssertEqual(item.forumName, "")
        XCTAssertEqual(item.replies, 0)
        XCTAssertEqual(item.views, 0)
        XCTAssertEqual(item.lastPoster, "")
        XCTAssertEqual(item.lastPost, "")
    }

    func testUnclosedRowDoesNotCrashOrStealFollowingRows() throws {
        // The second row opens a <td> that is never closed. The scanner keeps
        // the row it can read and simply does not invent a third one.
        let page = try AuthorSpaceParser.threads(fromHTML: SpaceFixture.malformedThreadsHTML)
        XCTAssertEqual(page.items.map(\.tid), ["111", "222"])
    }

    func testScriptWithAngleBracketsDoesNotSwallowTheTable() throws {
        let html = """
        <script>if (a < b && c > d) { document.write("<td>"); }</script>
        <table><tr><th><a href="forum.php?mod=viewthread&tid=9">脚本之后的主题</a></th>
        <td><a href="forum.php?mod=forumdisplay&fid=2">版块</a></td>
        <td class="num"><a>1</a><em>2</em></td></tr></table>
        """
        let page = try AuthorSpaceParser.threads(fromHTML: html)
        XCTAssertEqual(page.items.first?.tid, "9")
        XCTAssertEqual(page.items.first?.subject, "脚本之后的主题")
    }

    // MARK: - Login prompt

    func testGuestPageThrowsLoginRequired() {
        XCTAssertThrowsError(try AuthorSpaceParser.threads(fromHTML: SpaceFixture.loginPromptHTML)) { error in
            XCTAssertEqual(error as? AuthorSpaceParser.Failure, .loginRequired)
            XCTAssertEqual(error.localizedDescription, "登录后才能查看 Ta 的更多帖子")
        }
    }

    func testLoginMarkerFromDiscuzKeyIsRecognised() {
        XCTAssertTrue(AuthorSpaceParser.isLoginPrompt("<p>login_before_enter_home</p>"))
        XCTAssertTrue(AuthorSpaceParser.isLoginPrompt("<p>请先登录后才能继续浏览</p>"))
    }

    func testNormalPageIsNotMistakenForALoginPrompt() throws {
        // Every guest page (and every signed-in page) carries the "请 登录 后
        // 使用快捷导航" header; it must not be read as the login notice.
        let html = SpaceFixture.authorThreadsHTML
            .replacingOccurrences(of: "<body>", with: "<body><p>请 登录 后使用快捷导航</p>")
        XCTAssertFalse(AuthorSpaceParser.isLoginPrompt(html))
        XCTAssertEqual(try AuthorSpaceParser.threads(fromHTML: html).items.count, 2)
    }

    // MARK: - Reply lists

    func testReplyListAttachesFloorsToTheirThread() throws {
        let page = try AuthorSpaceParser.replies(fromHTML: SpaceFixture.authorRepliesHTML)

        XCTAssertEqual(page.items.map(\.pid), ["111", "222", "333"])
        let first = try XCTUnwrap(page.items.first)
        XCTAssertEqual(first.tid, "900")
        XCTAssertEqual(first.threadSubject, "主题甲")
        XCTAssertEqual(first.forumName, "游戏区")
        XCTAssertEqual(first.snippet, "这是回复的正文 第二行")

        let third = try XCTUnwrap(page.items.last)
        XCTAssertEqual(third.tid, "901")
        XCTAssertEqual(third.threadSubject, "主题乙")
        XCTAssertEqual(third.snippet, "另一个主题里的回复")
    }

    func testDuplicateFloorsAreDropped() throws {
        let page = try AuthorSpaceParser.replies(fromHTML: SpaceFixture.authorRepliesHTML)
        XCTAssertEqual(Set(page.items.map(\.pid)).count, page.items.count)
    }

    func testMessageRowBeforeAnyThreadIsIgnored() throws {
        let html = """
        <table><tr><td colspan="5"><a href="forum.php?mod=redirect&goto=findpost&ptid=1&pid=1">孤儿回复</a></td></tr></table>
        """
        XCTAssertTrue(try AuthorSpaceParser.replies(fromHTML: html).items.isEmpty)
    }

    func testEmptyFloorTextBecomesAPlaceholder() throws {
        let html = """
        <table>
        <tr><th><a href="forum.php?mod=redirect&goto=findpost&ptid=5&pid=10">主题</a></th>
        <td><a href="forum.php?mod=forumdisplay&fid=1">版</a></td>
        <td class="num"><a>0</a><em>1</em></td><td class="by"><cite>甲</cite><em>刚刚</em></td></tr>
        <tr><td colspan="5"><a href="forum.php?mod=redirect&goto=findpost&ptid=5&pid=10"></a></td></tr>
        </table>
        """
        let page = try AuthorSpaceParser.replies(fromHTML: html)
        XCTAssertEqual(page.items.first?.pid, "10")
        XCTAssertEqual(page.items.first?.snippet, "（无正文）")
    }

    func testReplyStringsAreDecodedAndWhitespaceCollapsed() throws {
        let page = try AuthorSpaceParser.replies(fromHTML: SpaceFixture.authorRepliesHTML)
        let second = try XCTUnwrap(page.items.dropFirst().first)
        XCTAssertEqual(second.snippet, "引用的 & 符号")
    }

    // MARK: - Pagination

    func testPagerReadsTotalPagesAndNextPage() {
        let info = AuthorSpaceParser.pageInfo(in: SpaceFixture.authorThreadsHTML, page: 1)
        XCTAssertEqual(info.page, 1)
        XCTAssertEqual(info.totalPages, 3)
        XCTAssertTrue(info.hasMore)
    }

    func testLastPageHasNoMore() {
        let info = AuthorSpaceParser.pageInfo(in: SpaceFixture.authorThreadsHTML, page: 3)
        XCTAssertEqual(info.page, 3)
        XCTAssertEqual(info.totalPages, 3)
        XCTAssertFalse(info.hasMore)
    }

    func testThreadMultipageLinksDoNotCountAsPager() {
        // A subject's own "1 2 3 4 …" links also carry page=; only links back
        // into home.php describe the space list's pagination.
        let html = """
        <table><tr><th><a href="forum.php?mod=viewthread&tid=1&page=99">长帖</a>
        <span class="tps"><a href="forum.php?mod=viewthread&tid=1&page=98">98</a></span></th>
        <td class="num"><a>1</a><em>2</em></td></tr></table>
        """
        let info = AuthorSpaceParser.pageInfo(in: html, page: 1)
        XCTAssertNil(info.totalPages)
        XCTAssertFalse(info.hasMore)
    }

    func testEntityEncodedPagerLinksAreRead() {
        let html = """
        <div class="pg"><a href="home.php?mod=space&amp;uid=7&amp;do=thread&amp;page=2">2</a></div>
        """
        let info = AuthorSpaceParser.pageInfo(in: html, page: 1)
        XCTAssertEqual(info.page, 1)
        XCTAssertTrue(info.hasMore)

        let samePage = AuthorSpaceParser.pageInfo(in: html, page: 2)
        XCTAssertFalse(samePage.hasMore)
    }

    func testPageNumberBelowOneIsClamped() {
        let info = AuthorSpaceParser.pageInfo(in: SpaceFixture.authorThreadsHTML, page: 0)
        XCTAssertEqual(info.page, 1)
    }
}

// MARK: - Model

@MainActor
final class AuthorSpaceModelTests: XCTestCase {

    private func threadPage(_ ids: [String], hasMore: Bool) -> AuthorSpaceParser.ThreadPage {
        let items = ids.map {
            AuthorSpaceParser.ThreadItem(
                tid: $0,
                subject: "主题 \($0)",
                forumName: "版块",
                replies: 0,
                views: 0,
                lastPoster: "",
                lastPost: "",
                dateline: ""
            )
        }
        return AuthorSpaceParser.ThreadPage(
            items: items,
            pageInfo: .init(page: 1, totalPages: nil, hasMore: hasMore)
        )
    }

    func testSignedOutSheetDoesNotRequestAnything() async {
        var calls = 0
        let model = AuthorSpaceModel(
            uid: "7",
            isLoggedIn: false,
            fetchThreads: { _ in
                calls += 1
                return self.threadPage(["1"], hasMore: false)
            },
            fetchReplies: { _ in
                calls += 1
                return AuthorSpaceParser.ReplyPage(items: [], pageInfo: .init(page: 1, totalPages: nil, hasMore: false))
            }
        )

        XCTAssertTrue(model.needsLogin)
        await model.loadThreadsIfNeeded()
        await model.loadRepliesIfNeeded()
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(model.threadItems.isEmpty)
    }

    func testThreadPaginationAppendsTheSecondPage() async {
        var requested: [Int] = []
        let model = AuthorSpaceModel(
            uid: "7",
            isLoggedIn: true,
            fetchThreads: { page in
                requested.append(page)
                return page == 1
                    ? self.threadPage(["1", "2"], hasMore: true)
                    : self.threadPage(["3"], hasMore: false)
            },
            fetchReplies: { _ in
                AuthorSpaceParser.ReplyPage(items: [], pageInfo: .init(page: 1, totalPages: nil, hasMore: false))
            }
        )

        await model.loadThreadsIfNeeded()
        XCTAssertEqual(model.threadItems.map(\.tid), ["1", "2"])
        XCTAssertTrue(model.threadHasMore)
        XCTAssertFalse(model.needsLogin)

        await model.loadMoreThreads()
        XCTAssertEqual(requested, [1, 2])
        XCTAssertEqual(model.threadItems.map(\.tid), ["1", "2", "3"])
        XCTAssertFalse(model.threadHasMore)
    }

    func testServerLoginNoticeRaisesNeedsLogin() async {
        let model = AuthorSpaceModel(
            uid: "7",
            isLoggedIn: true,
            fetchThreads: { _ in throw APIError.notLoggedIn },
            fetchReplies: { _ in throw APIError.notLoggedIn }
        )

        XCTAssertFalse(model.needsLogin)
        await model.loadThreadsIfNeeded()
        XCTAssertTrue(model.needsLogin)
        XCTAssertNotNil(model.threadsError)
    }

    func testFailedPageKeepsTheCursorForARetry() async {
        var failNext = true
        var requested: [Int] = []
        let model = AuthorSpaceModel(
            uid: "7",
            isLoggedIn: true,
            fetchThreads: { page in
                requested.append(page)
                if page == 2, failNext {
                    failNext = false
                    throw APIError.http(500)
                }
                return page == 1
                    ? self.threadPage(["1"], hasMore: true)
                    : self.threadPage(["2"], hasMore: false)
            },
            fetchReplies: { _ in
                AuthorSpaceParser.ReplyPage(items: [], pageInfo: .init(page: 1, totalPages: nil, hasMore: false))
            }
        )

        await model.loadThreadsIfNeeded()
        await model.loadMoreThreads()
        XCTAssertEqual(model.threadItems.map(\.tid), ["1"])
        XCTAssertNotNil(model.threadsError)

        await model.loadMoreThreads()
        XCTAssertEqual(requested, [1, 2, 2], "the failed page is asked for again")
        XCTAssertEqual(model.threadItems.map(\.tid), ["1", "2"])
    }
}

// MARK: - Markup

private enum SpaceFixture {
    /// The shape `space_thread.htm` renders for `type=thread`, trimmed to the
    /// cells the parser reads.
    static let authorThreadsHTML = """
    <!DOCTYPE html><html><head><title>某甲的个人空间</title></head><body>
    <div id="ct">
    <div class="tl">
    <table cellspacing="0" cellpadding="0">
    <tr class="th">
      <td class="icn">&nbsp;</td>
      <th>主题</th>
      <td class="frm">版块</td>
      <td class="num">回复</td>
      <td class="by"><cite>最后回复</cite></td>
    </tr>
    <tr>
      <td class="icn"><a href="forum.php?mod=viewthread&tid=12345" title="open"><img src="folder_new.gif" /></a></td>
      <th><a href="forum.php?mod=viewthread&tid=12345" target="_blank">周末补番推荐 &amp; 讨论</a></th>
      <td><a href="forum.php?mod=forumdisplay&fid=6" class="xg1" target="_blank">游戏区</a></td>
      <td class="num"><a href="forum.php?mod=viewthread&tid=12345" class="xi2" target="_blank">42</a><em>310</em></td>
      <td class="by">
        <cite><a href="home.php?mod=space&username=x" target="_blank">某甲</a></cite>
        <em><a href="forum.php?mod=redirect&tid=12345&goto=lastpost#lastpost" target="_blank">半小时前</a></em>
      </td>
    </tr>
    <tr>
      <td class="icn"><a href="forum.php?mod=viewthread&tid=67890"><img src="folder_common.gif" /></a></td>
      <th><a href="forum.php?mod=viewthread&tid=67890">有谁记得这部老番</a></th>
      <td><a href="forum.php?mod=forumdisplay&fid=2">动漫区</a></td>
      <td class="num"><a href="forum.php?mod=viewthread&tid=67890">0</a><em>12</em></td>
      <td class="by"><cite><a href="home.php?mod=space&username=y">某乙</a></cite><em>昨天</em></td>
    </tr>
    </table>
    <div class="pgs cl mtm"><div class="pg">
      <strong>1</strong>
      <a href="home.php?mod=space&uid=7&do=thread&view=me&type=thread&page=2">2</a>
      <a href="home.php?mod=space&uid=7&do=thread&view=me&type=thread&page=3">3</a>
      <label>共 3 页</label>
    </div></div>
    </div>
    </div>
    </body></html>
    """

    static let emptyThreadsHTML = """
    <table>
      <tr class="th"><td class="icn">&nbsp;</td><th>主题</th><td class="frm">版块</td></tr>
      <tr><td colspan="5"><p class="emp">没有相关帖子</p></td></tr>
    </table>
    """

    /// A row missing the forum, the counters and the last-post cell, with a
    /// bare "<" in the title.
    static let partialThreadHTML = """
    <table>
      <tr>
        <th><a href="forum.php?mod=viewthread&tid=24680">价格<100 的显示器</a></th>
      </tr>
    </table>
    """

    /// The first row is closed normally; the second starts a cell and never
    /// closes it. Nothing after it should be read.
    static let malformedThreadsHTML = """
    <table>
      <tr>
        <th><a href="forum.php?mod=viewthread&tid=111">第一条</a></th>
        <td><a href="forum.php?mod=forumdisplay&fid=1">版</a></td>
        <td class="num"><a>1</a><em>2</em></td>
      </tr>
      <tr>
        <th><a href="forum.php?mod=viewthread&tid=222">第二条</a></th>
        <td><a href="forum.php?mod=forumdisplay&fid=1">版</a></td>
        <td class="num"><a>3</a><em>4</em></td>
      </tr>
      <tr>
        <th><a href="forum.php?mod=viewthread&tid=333">第三条<td>没有收尾
    </table>
    """

    static let loginPromptHTML = """
    <!DOCTYPE html><html><head><title>提示信息 - Stage1st</title></head><body>
    <div class="alert_error">
      <h2>提示信息</h2>
      <p>请先登录后才能继续浏览</p>
    </div>
    </body></html>
    """

    /// `type=reply`: a thread row followed by one row per floor, exactly as
    /// `space_thread.htm` renders `$tids[$stid]`.
    static let authorRepliesHTML = """
    <table>
    <tr class="th">
      <td class="icn">&nbsp;</td>
      <th>回复</th>
      <td class="frm">版块</td>
      <td class="num">回复</td>
      <td class="by"><cite>最后回复</cite></td>
    </tr>
    <tr class="bw0_all">
      <td class="icn"><a href="forum.php?mod=viewthread&tid=900"><img src="folder_common.gif" /></a></td>
      <th><a href="forum.php?mod=redirect&goto=findpost&ptid=900&pid=111">主题甲</a></th>
      <td><a href="forum.php?mod=forumdisplay&fid=6">游戏区</a></td>
      <td class="num"><a>42</a><em>310</em></td>
      <td class="by"><cite><a>某乙</a></cite><em>1 小时前</em></td>
    </tr>
    <tr>
      <td colspan="5" class="xg1">&nbsp;<img src="icon_quote_m_s.gif" />
        <a href="forum.php?mod=redirect&goto=findpost&ptid=900&pid=111">这是回复的<b>正文</b><br />第二行</a>
        <img src="icon_quote_m_e.gif" />
      </td>
    </tr>
    <tr>
      <td colspan="5" class="xg1">&nbsp;<img src="icon_quote_m_s.gif" />
        <a href="forum.php?mod=redirect&goto=findpost&ptid=900&pid=222">引用的 &amp;amp; 符号</a>
      </td>
    </tr>
    <tr class="bw0_all">
      <td class="icn"><a href="forum.php?mod=viewthread&tid=901"><img src="folder_common.gif" /></a></td>
      <th><a href="forum.php?mod=redirect&goto=findpost&ptid=901&pid=333">主题乙</a></th>
      <td><a href="forum.php?mod=forumdisplay&fid=2">动漫区</a></td>
      <td class="num"><a>3</a><em>9</em></td>
      <td class="by"><cite><a>某甲</a></cite><em>昨天</em></td>
    </tr>
    <tr>
      <td colspan="5" class="xg1"><a href="forum.php?mod=redirect&goto=findpost&ptid=901&pid=333">另一个主题里的回复</a></td>
    </tr>
    <tr>
      <td colspan="5" class="xg1"><a href="forum.php?mod=redirect&goto=findpost&ptid=900&pid=111">重复的楼层</a></td>
    </tr>
    </table>
    """
}
