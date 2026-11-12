import XCTest
@testable import S1Reader

/// A forum endpoint whose pages and failures are scripted, so paging, dedupe
/// and error recovery are exercised without a network.
final class FakeThreadListAPI: ThreadListAPI, @unchecked Sendable {
    /// Thread ids per page. A page missing from this map is an empty page.
    var pages: [Int: [String]]
    /// Pages that throw instead of answering.
    var failingPages: Set<Int> = []
    /// Every page number requested, in order.
    private(set) var requestedPages: [Int] = []
    var totalThreads = 250
    var perPage = 50

    init(pages: [Int: [String]]) {
        self.pages = pages
    }

    // All access happens on the main actor through the view model's fetch
    // closure, so the unchecked conformance is safe here.
    func forumThreads(fid: String, page: Int) async throws -> ThreadListPage {
        requestedPages.append(page)
        if failingPages.contains(page) {
            throw APIError.server("服务器返回 HTTP 503")
        }
        let rows = (pages[page] ?? []).map { tid in
            #"{"tid":"\#(tid)","subject":"主题 \#(tid)","author":"作者","replies":"3"}"#
        }
        let json = #"""
        {
          "forum": {"name": "版块", "description": "", "threads": \#(totalThreads)},
          "page": \#(page),
          "tpp": \#(perPage),
          "forum_threadlist": [\#(rows.joined(separator: ","))]
        }
        """#
        let decoder = JSONDecoder()
        return try decoder.decode(ThreadListPage.self, from: Data(json.utf8))
    }
}

@MainActor
final class ThreadListViewModelTests: XCTestCase {
    private func makeModel(_ api: FakeThreadListAPI) -> ThreadListViewModel {
        ThreadListViewModel(forum: Forum(fid: "6", name: "外野"), api: api)
    }

    private func ids(_ model: ThreadListViewModel) -> [String] {
        model.threads.map(\.tid)
    }

    func testFirstPageLoad() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"]])
        let model = makeModel(api)

        await model.loadIfNeeded()

        XCTAssertEqual(ids(model), ["1", "2"])
        XCTAssertEqual(model.pager.page, 1)
        XCTAssertEqual(model.totalThreads, 250)
        XCTAssertTrue(model.pager.hasMore)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(api.requestedPages, [1])
    }

    func testLoadMoreAppendsTheNextPage() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["3", "4"]])
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2", "3", "4"])
        XCTAssertEqual(model.pager.page, 2)
        XCTAssertEqual(api.requestedPages, [1, 2])
    }

    func testLoadMoreDropsRowsAlreadyLoaded() async {
        // S1 re-serves a thread that was bumped between the two requests.
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["2", "3"]])
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2", "3"])
    }

    func testPageOfOnlyKnownRowsEndsTheList() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["1", "2"]])
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2"])
        XCTAssertFalse(model.pager.hasMore)
    }

    func testFailedPageKeepsHasMoreSoItCanBeRetried() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["3"]])
        api.failingPages = [2]
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2"])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.pager.page, 1, "a failed page must not move the cursor")
        XCTAssertTrue(model.pager.hasMore, "one network hiccup must not end the list")
    }

    func testRetryingAfterAFailureLoadsThePage() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["3"]])
        api.failingPages = [2]
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()
        XCTAssertNotNil(model.errorMessage)

        api.failingPages = []
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2", "3"])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.pager.page, 2)
    }

    func testEmptyPageEndsTheList() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"]])
        let model = makeModel(api)
        model.pager.hasMore = true

        await model.loadIfNeeded()
        await model.loadMore()

        XCTAssertEqual(ids(model), ["1", "2"])
        XCTAssertFalse(model.pager.hasMore)
    }

    func testLoadMoreDoesNothingOnceExhausted() async {
        let api = FakeThreadListAPI(pages: [1: ["1"]])
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()
        await model.loadMore()

        XCTAssertEqual(api.requestedPages, [1, 2], "the exhausted list must stop asking")
    }

    func testReloadReplacesEveryLoadedPage() async {
        let api = FakeThreadListAPI(pages: [1: ["1", "2"], 2: ["3"]])
        let model = makeModel(api)

        await model.loadIfNeeded()
        await model.loadMore()
        api.pages = [1: ["9"]]
        await model.reload()

        XCTAssertEqual(ids(model), ["9"])
        XCTAssertEqual(model.pager.page, 1)
    }
}
