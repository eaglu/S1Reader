import XCTest
@testable import S1Reader

/// Entity resolution and the copy the intents speak, without App Intents, a
/// device or a network in the way.
final class SiriIntentTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "s1.tests.intents"

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - Boards

    private func directory() -> ForumDirectory {
        let directory = ForumDirectory(defaults: defaults)
        directory.save([
            Forum(fid: "6", name: "游戏论坛", description: "聊游戏"),
            Forum(
                fid: "2",
                name: "动漫论坛",
                description: "",
                subforums: [Forum(fid: "60", name: "手游版", description: "只聊手游")]
            )
        ])
        return directory
    }

    func testDirectoryFlattensSubboards() {
        let records = directory().records
        XCTAssertEqual(records.map(\.fid), ["6", "2", "60"])
        XCTAssertEqual(records.first { $0.fid == "60" }?.name, "手游版")
    }

    func testDirectoryKeywordSearch() {
        let directory = directory()
        XCTAssertEqual(directory.records(matching: "手游").map(\.fid), ["60"])
        XCTAssertEqual(directory.records(matching: "游戏").map(\.fid), ["6"])
        XCTAssertEqual(directory.records(matching: "   ").count, 3, "an empty query lists everything")
        XCTAssertTrue(directory.records(matching: "不存在的版块").isEmpty)
    }

    /// S1 board names are Chinese, and dictation arrives with different case
    /// and accents for the Latin ones.
    func testMatchIsCaseAndDiacriticInsensitive() {
        XCTAssertTrue(TextMatch.matches("podcast", in: "Podcast 版"))
        XCTAssertTrue(TextMatch.matches("cafe", in: "Café"))
        XCTAssertTrue(TextMatch.matches("", in: "anything"))
        XCTAssertFalse(TextMatch.matches("podcast", in: "播客版"))
    }

    func testForumEntityQueryResolvesIdentifiersAndWords() async throws {
        let query = ForumEntityQuery(directory: directory())

        let byID = try await query.entities(for: ["60", "missing"])
        XCTAssertEqual(byID.map(\.fid), ["60"])
        XCTAssertEqual(byID.first?.name, "手游版")

        let byName = try await query.entities(matching: "游戏")
        XCTAssertEqual(byName.map(\.fid), ["6"])

        let none = try await query.entities(matching: "不存在")
        XCTAssertTrue(none.isEmpty)
    }

    func testForumEntityResolvesANewBoardWithoutAnyCacheMiss() async throws {
        // A board the directory knows nothing about still opens: only the id is
        // needed, and the screen fetches the rest.
        let query = ForumEntityQuery(directory: ForumDirectory(defaults: defaults))
        let found = try await query.entities(matching: "游戏")
        XCTAssertTrue(found.isEmpty)
        let entity = ForumEntity(fid: "6", name: "游戏论坛", summary: "聊游戏")
        XCTAssertEqual(entity.id, "6")
        XCTAssertEqual(directory().record(fid: "6")?.name, "游戏论坛")
    }

    func testSuggestedBoardsAreCapped() async throws {
        let directory = ForumDirectory(defaults: defaults)
        directory.save((0..<30).map { Forum(fid: "\($0)", name: "版块 \($0)") })
        let suggested = try await ForumEntityQuery(directory: directory).suggestedEntities()
        XCTAssertEqual(suggested.count, 12)
    }

    // MARK: - Threads

    private func store() -> RecentThreadStore {
        let store = RecentThreadStore(defaults: defaults)
        store.record(RecentThread(tid: "1", subject: "旧的", author: "a", fid: "6", date: Date(timeIntervalSince1970: 100)))
        store.record(RecentThread(tid: "2", subject: "新しい iPhone 讨论", author: "b", fid: "6", date: Date(timeIntervalSince1970: 200)))
        store.record(RecentThread(tid: "3", subject: "旧的", author: "c", fid: "6", date: Date(timeIntervalSince1970: 300)))
        return store
    }

    func testRecentThreadsAreNewestFirst() {
        XCTAssertEqual(store().threads.map(\.tid), ["3", "2", "1"])
    }

    func testRevisitingAThreadMovesItToTheFrontWithoutDuplicating() {
        let store = store()
        store.record(RecentThread(tid: "1", subject: "旧的", author: "a", fid: "6", date: Date(timeIntervalSince1970: 400)))
        XCTAssertEqual(store.threads.map(\.tid), ["1", "3", "2"])
        XCTAssertEqual(store.threads.filter { $0.tid == "1" }.count, 1)
    }

    func testRecentThreadsAreCapped() {
        let store = RecentThreadStore(defaults: defaults)
        for index in 0..<(RecentThreadStore.limit + 15) {
            store.record(RecentThread(tid: "\(index)", subject: "主题 \(index)", author: "a", fid: "6", date: Date()))
        }
        XCTAssertEqual(store.threads.count, RecentThreadStore.limit)
        XCTAssertEqual(store.threads.first?.tid, "\(RecentThreadStore.limit + 14)")
    }

    func testThreadSearchMatchesTitleAndAuthor() {
        let store = store()
        XCTAssertEqual(store.threads(matching: "iphone").map(\.tid), ["2"])
        XCTAssertEqual(store.threads(matching: "旧的").map(\.tid), ["3", "1"])
        XCTAssertEqual(store.threads(matching: "c").map(\.tid), ["3"])
        XCTAssertTrue(store.threads(matching: "没有这个").isEmpty)
    }

    func testThreadEntityQueryResolvesByIDAndByTitle() async throws {
        let query = ThreadEntityQuery(store: store())

        let byID = try await query.entities(for: ["2", "404"])
        XCTAssertEqual(byID.map(\.tid), ["2"])
        XCTAssertEqual(byID.first?.subject, "新しい iPhone 讨论")

        let byTitle = try await query.entities(matching: "iPhone")
        XCTAssertEqual(byTitle.map(\.tid), ["2"])

        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.tid), ["3", "2", "1"])
    }

    // MARK: - Intent decisions

    func testResolveThreadCoversAllThreeShapes() {
        let store = store()
        XCTAssertEqual(SiriIntentLogic.resolveThread(.entity(tid: "2"), store: store)?.tid, "2")
        XCTAssertEqual(SiriIntentLogic.resolveThread(.keyword("旧的"), store: store)?.tid, "3")
        XCTAssertEqual(SiriIntentLogic.resolveThread(.recent, store: store)?.tid, "3")
    }

    func testResolveThreadRejectsWhatItCannotFind() {
        let empty = RecentThreadStore(defaults: defaults)
        XCTAssertNil(SiriIntentLogic.resolveThread(.entity(tid: "1"), store: empty))
        XCTAssertNil(SiriIntentLogic.resolveThread(.keyword("没有"), store: empty))
        XCTAssertNil(SiriIntentLogic.resolveThread(.recent, store: empty))
    }

    func testNoticeReplyReadsTheCachedCount() {
        XCTAssertEqual(
            SiriIntentLogic.noticesReply(badge: NoticeBadge(unread: 7, loggedIn: true, date: Date()), speakCount: true),
            "You have 7 unread notices in S1."
        )
        XCTAssertEqual(
            SiriIntentLogic.noticesReply(badge: NoticeBadge(unread: 1, loggedIn: true, date: Date()), speakCount: true),
            "You have 1 unread notice in S1."
        )
        XCTAssertEqual(
            SiriIntentLogic.noticesReply(badge: NoticeBadge(unread: 0, loggedIn: true, date: Date()), speakCount: true),
            "You have no unread notices in S1."
        )
    }

    func testNoticeReplyWithoutAskingForTheCount() {
        let badge = NoticeBadge(unread: 7, loggedIn: true, date: Date())
        XCTAssertEqual(SiriIntentLogic.noticesReply(badge: badge, speakCount: false), "Opening your notices in S1.")
    }

    /// Signed out, and never synced: both have to say something usable rather
    /// than return a count that means nothing.
    func testNoticeReplyFallsBackWhenItCannotAnswer() {
        XCTAssertEqual(
            SiriIntentLogic.noticesReply(badge: NoticeBadge(unread: 3, loggedIn: false, date: Date()), speakCount: true),
            "You're signed out in S1, so there's nothing to read yet."
        )
        XCTAssertEqual(
            SiriIntentLogic.noticesReply(badge: nil, speakCount: true),
            "Opening your notices in S1. I haven't synced the unread count yet."
        )
    }

    func testBadgeStoreRoundTrip() {
        let store = NoticeBadgeStore(defaults: defaults)
        XCTAssertNil(store.badge)
        store.record(unread: -2, loggedIn: true, at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(store.badge?.unread, 0, "a negative count is clamped")
        XCTAssertEqual(store.badge?.loggedIn, true)
        store.clear()
        XCTAssertNil(store.badge)
    }
}
