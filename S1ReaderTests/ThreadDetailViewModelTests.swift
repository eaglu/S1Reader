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
        XCTAssertEqual(model.firstLoadedPage, 8)
        XCTAssertEqual(model.loadedPages, 9)
        XCTAssertEqual(model.posts.first?.pid, "p281")
        XCTAssertEqual(model.posts.count, 80, "假服务器每页都是满的 40 楼")
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
        XCTAssertFalse(model.isLoadingEarlier)
        XCTAssertEqual(model.firstLoadedPage, 8)
    }

    /// 第一次触顶丢掉之后，回到顶部再触顶就能补下一页。
    func testTheNextApproachAfterTheFirstOneCompletesLoadsThePageAbove() async throws {
        let server = FakeThreadServer()
        let model = makeModel(server)
        await model.loadPage(9)

        await model.loadEarlier()
        let returned = await model.loadEarlier()

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
