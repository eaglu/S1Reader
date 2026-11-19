import XCTest
@testable import S1Reader

/// 往上补页的串行化：请求在飞时不排队、每次只补一页、锚点交回给视图。
@MainActor
final class ThreadDetailViewModelTests: XCTestCase {
    /// 假分页服务器：记住每一页被要了几次，并能把某一页扣在线上。
    private final class FakeThreadServer {
        private(set) var requested: [Int] = []
        /// 把某一页扣在线上：请求到这里原地让路，直到测试放开。
        var holdPage: Int?
        var isHolding = false
        var failingPages: Set<Int> = []

        func fetch(_ page: Int) async throws -> ThreadPage {
            requested.append(page)
            while isHolding, page == holdPage {
                await Task.yield()
            }
            if failingPages.contains(page) {
                throw URLError(.notConnectedToInternet)
            }
            return try decode(ThreadPage.self, Self.json(page: page))
        }

        /// 每页 40 楼，第 p 页是 (p-1)*40+1 ... p*40 楼。
        private static func json(page: Int) -> String {
            let floors = ((page - 1) * 40 + 1)...(page * 40)
            let posts = floors
                .map { #"{"pid": "p\#($0)", "tid": "\#tid)", "position": "\#($0)"}"# }
                .joined(separator: ",")
            return #"{"ppp": "40", "postlist": [\#(posts)]}"#
        }

        private static let tid = "9"
    }

    func testOneApproachAddsOnePageAndHandsBackTheAnchor() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)
        XCTAssertEqual(server.requested, [9])
        let anchor = model.posts.first?.pid
        XCTAssertEqual(anchor, "p321")

        let returned = await model.loadEarlier()

        XCTAssertEqual(server.requested, [9, 8], "一次上拉只要了一页")
        XCTAssertEqual(returned, "p321", "要把读者原来那一楼交回去定位")
        // 取回来先拿在手里：视图要等手指离开再插进列表，否则新页会顶在屏幕上。
        XCTAssertEqual(model.firstLoadedPage, 9, "还没提交就动了页窗口")
        XCTAssertEqual(model.posts.first?.pid, "p321", "还没提交就插进列表了")
        XCTAssertTrue(model.isLoadingEarlier, "页在手里时行上仍是在加载")

        let pinned = model.commitEarlier()

        XCTAssertEqual(pinned, "p321")
        XCTAssertEqual(model.firstLoadedPage, 8)
        XCTAssertEqual(model.loadedPages, 9)
        XCTAssertEqual(model.posts.first?.pid, "p281")
        XCTAssertEqual(model.posts.count, 80, "假服务器每页都是满的 40 楼")
        XCTAssertFalse(model.isLoadingEarlier)
    }

    /// 提交只发生一次：视图每帧只有一条路径会调它。
    func testCommittingTwiceInsertsThePageOnce() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)
        await model.loadEarlier()

        XCTAssertEqual(model.commitEarlier(), "p321")
        XCTAssertNil(model.commitEarlier(), "同一页不该插第二次")
        XCTAssertEqual(model.posts.count, 80)
        XCTAssertEqual(model.posts.first?.pid, "p281")
        XCTAssertEqual(server.requested, [9, 8])
    }

    /// 取回来的页被丢掉时列表不动，下一次触顶照常补页。
    func testDiscardingTheFetchedPageLeavesTheListAlone() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)
        await model.loadEarlier()

        model.discardPendingEarlier()

        XCTAssertNil(model.commitEarlier())
        XCTAssertFalse(model.isLoadingEarlier)
        XCTAssertEqual(model.posts.first?.pid, "p321")
        XCTAssertEqual(model.firstLoadedPage, 9)

        let retried = await model.loadEarlier()
        XCTAssertEqual(retried, "p321")
        XCTAssertEqual(server.requested, [9, 8, 8])
    }

    /// 拿到页之后跳去了别的页：这一页已经不属于当前窗口，提交时要丢掉。
    func testAPageFetchedForAnOldWindowIsDroppedOnCommit() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)
        await model.loadEarlier()

        await model.loadPage(3)
        XCTAssertNil(model.commitEarlier(), "跳页后旧窗口的上一页不能再插进来")
        XCTAssertEqual(model.firstLoadedPage, 3)
        XCTAssertEqual(model.posts.first?.pid, "p81")
    }

    /// 上拉请求还没回来时，后面的触顶直接丢弃，不排队。
    func testARequestThatArrivesWhileAPageIsOnTheWireIsDropped() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)

        server.holdPage = 8
        server.isHolding = true

        let inFlight = Task { await model.loadEarlier() }
        await waitUntil("第 8 页已经发出去了") { server.requested == [9, 8] }

        let dropped = await model.loadEarlier()
        XCTAssertNil(dropped, "请求在飞时不该再补一页")
        XCTAssertFalse(dropped == model.posts.first?.pid)
        XCTAssertEqual(server.requested, [9, 8], "后来的触顶被丢掉，没有排队")
        XCTAssertTrue(model.isLoadingEarlier, "在飞的时候行上要显示正在加载")

        server.isHolding = false
        let landed = await inFlight.value
        XCTAssertEqual(landed, "p321")
        XCTAssertEqual(server.requested, [9, 8])
        XCTAssertTrue(model.isLoadingEarlier, "页已经到手，但要等视图提交")

        model.commitEarlier()
        XCTAssertFalse(model.isLoadingEarlier)
        XCTAssertEqual(model.firstLoadedPage, 8)
    }

    /// 第一次触顶丢掉之后，回到顶部再触顶就能补下一页。
    func testTheNextApproachAfterTheFirstOneCompletesLoadsThePageAbove() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)

        await model.loadEarlier()
        model.commitEarlier()
        let returned = await model.loadEarlier()
        model.commitEarlier()

        XCTAssertEqual(server.requested, [9, 8, 7])
        XCTAssertEqual(returned, "p281")
        XCTAssertEqual(model.firstLoadedPage, 7)
        XCTAssertEqual(model.posts.first?.pid, "p241")
        XCTAssertEqual(model.posts.count, 120)
    }

    /// 翻页失败时游标不动，闸门放开，下次触顶重试同一页。
    func testAFailedPageKeepsTheCursorAndReleasesTheGate() async throws {
        let server = FakeThreadServer()
        server.failingPages = [8]
        let model = makeModel(server)
        await model.loadPage(9)

        let returned = await model.loadEarlier()

        XCTAssertNil(returned)
        XCTAssertEqual(model.firstLoadedPage, 9)
        XCTAssertFalse(model.isLoadingEarlier)
        XCTAssertEqual(model.posts.first?.pid, "p321")

        server.failingPages = []
        let retried = await model.loadEarlier()
        model.commitEarlier()
        XCTAssertEqual(retried, "p321")
        XCTAssertEqual(model.firstLoadedPage, 8)
    }

    /// 没有更早的页时什么都不发。
    func testNothingIsRequestedOnTheFirstPage() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(1)

        let returned = await model.loadEarlier()
        XCTAssertNil(returned)
        XCTAssertEqual(server.requested, [1])
        XCTAssertFalse(model.hasEarlier)
    }

    /// 卡片上写的就是这一页：只该发这一个请求，不要把第 1 页先拉一遍再丢掉。
    func testOpeningFromTheCardLoadsOnlyThePageOnTheCard() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        ReadingProgressStore.shared.clear(tid: "9")

        await model.openAtPage(3)

        XCTAssertEqual(server.requested, [3], "跳页只该要卡片上那一页")
        XCTAssertEqual(model.loadedPages, 3)
        XCTAssertEqual(model.firstLoadedPage, 3)
        XCTAssertEqual(model.posts.first?.pid, "p81")
        XCTAssertNil(
            ReadingProgressStore.shared.position(for: "9"),
            "落地过程中不能把第 1 页写成阅读进度"
        )
    }

    /// 翻页还在线上时点卡片回来：跳页要等它落地，不能被吞掉后停在第 1 页。
    func testTheJumpSurvivesAPageThatIsAlreadyOnTheWire() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadIfNeeded()
        XCTAssertEqual(model.loadedPages, 1)

        server.holdPage = 2
        server.isHolding = true
        let scrolling = Task { await model.loadMore() }
        await waitUntil("第 2 页还没发出去") { server.requested == [1, 2] }

        let jumping = Task { await model.openAtPage(5) }
        // 让跳页真正等在这条请求后面，再把它放掉。
        try? await Task.sleep(for: .milliseconds(150))
        server.isHolding = false
        await scrolling.value
        await jumping.value

        XCTAssertEqual(model.loadedPages, 5, "跳页不能被正在飞的翻页吞掉")
        XCTAssertEqual(model.firstLoadedPage, 5)
        XCTAssertEqual(model.posts.first?.pid, "p161")
    }

    /// 跳页途中不记阅读进度：那几行属于还没跳走的那一页。
    func testNoReadingPositionWhileLanding() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadIfNeeded()

        XCTAssertNil(
            model.readingPosition(visiblePid: "p1", isRestoring: true),
            "落地途中不能把第 1 页写进阅读进度"
        )

        await model.openAtPage(3)

        let saved = model.readingPosition(visiblePid: "p81", isRestoring: false)
        XCTAssertEqual(saved?.pid, "p81")
        XCTAssertEqual(saved?.position, 81, "落地之后记的是目标页那一楼")
    }

    /// 卡片该写读者正在看的那一页，而不是窗口最下面那一页。
    func testTheCardPageFollowsTheFloorOnScreenNotTheLastLoadedPage() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(3)
        await model.loadEarlier()
        model.commitEarlier()

        XCTAssertEqual(model.loadedPages, 3, "窗口底部仍是第 3 页")
        XCTAssertEqual(model.page(ofPid: "p50"), 2, "读者翻上去了，卡片该写第 2 页")
        XCTAssertEqual(model.page(ofPid: "p100"), 3)
        XCTAssertNil(model.page(ofPid: "p1"), "不在列表里的楼层没有页码")
    }

    // MARK: - 支撑

    private func makeModel(_ server: FakeThreadServer) -> ThreadDetailViewModel {
        // 20 页的帖子：800 楼。
        let summary = ThreadSummary(tid: "9", subject: "标题", replies: 799)
        return ThreadDetailViewModel(summary: summary) { page in
            try await server.fetch(page)
        }
    }

    private func waitUntil(
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("等不到：\(message)", file: file, line: line)
    }
}
