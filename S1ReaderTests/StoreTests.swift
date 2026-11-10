import XCTest
@testable import S1Reader

/// The stores keep state across launches, so every test uses its own defaults
/// suite and checks both the in-memory answer and what a fresh instance reads.
@MainActor
final class StoreTests: XCTestCase {
    private var storage: TemporaryDefaults!

    override func setUp() async throws {
        try await super.setUp()
        storage = TemporaryDefaults()
    }

    override func tearDown() async throws {
        storage.destroy()
        storage = nil
        try await super.tearDown()
    }

    // MARK: - ReadingProgressStore

    func testReadingPositionRoundTrip() {
        let store = ReadingProgressStore(defaults: storage.defaults)
        store.save(tid: "1", pid: "100", position: 100)
        XCTAssertEqual(store.position(for: "1")?.pid, "100")
        XCTAssertEqual(store.position(for: "1")?.position, 100)
    }

    func testReadingPositionSurvivesRelaunch() {
        ReadingProgressStore(defaults: storage.defaults).save(tid: "1", pid: "100", position: 100)
        let reopened = ReadingProgressStore(defaults: storage.defaults)
        XCTAssertEqual(reopened.position(for: "1")?.pid, "100")
    }

    func testReadingPositionIgnoresEmptyPidAndZeroFloor() {
        let store = ReadingProgressStore(defaults: storage.defaults)
        store.save(tid: "1", pid: "", position: 10)
        store.save(tid: "1", pid: "100", position: 0)
        XCTAssertNil(store.position(for: "1"))
    }

    func testReadingPositionIsOverwritten() {
        let store = ReadingProgressStore(defaults: storage.defaults)
        store.save(tid: "1", pid: "100", position: 100)
        store.save(tid: "1", pid: "200", position: 200)
        XCTAssertEqual(store.position(for: "1")?.pid, "200")
        XCTAssertEqual(ReadingProgressStore(defaults: storage.defaults).position(for: "1")?.pid, "200")
    }

    func testReadingPositionClear() {
        let store = ReadingProgressStore(defaults: storage.defaults)
        store.save(tid: "1", pid: "100", position: 100)
        store.clear(tid: "1")
        XCTAssertNil(store.position(for: "1"))
        XCTAssertNil(ReadingProgressStore(defaults: storage.defaults).position(for: "1"))
    }

    func testReadingPositionPrunesOldest() {
        let store = ReadingProgressStore(defaults: storage.defaults)
        for index in 0..<305 {
            store.save(tid: "\(index)", pid: "\(index)", position: index + 1)
        }
        XCTAssertNil(store.position(for: "0"), "the oldest entry is dropped")
        XCTAssertNotNil(store.position(for: "304"))
        let reopened = ReadingProgressStore(defaults: storage.defaults)
        XCTAssertNil(reopened.position(for: "0"), "pruning must be persisted too")
        XCTAssertNotNil(reopened.position(for: "304"))
    }

    func testReadingPositionSurvivesGarbageInDefaults() {
        storage.defaults.set(Data("not json".utf8), forKey: "s1.readingPositions")
        let store = ReadingProgressStore(defaults: storage.defaults)
        XCTAssertNil(store.position(for: "1"))
        store.save(tid: "1", pid: "1", position: 1)
        XCTAssertNotNil(store.position(for: "1"))
    }

    // MARK: - ThreadVisitStore

    func testNewRepliesCountsOnlyWhatArrived() {
        let store = ThreadVisitStore(defaults: storage.defaults)
        store.markSeen(tid: "1", replies: 100)
        XCTAssertEqual(store.newReplies(for: "1", replies: 100), 0)
        XCTAssertEqual(store.newReplies(for: "1", replies: 140), 40)
    }

    func testUnvisitedThreadHasNoBadge() {
        let store = ThreadVisitStore(defaults: storage.defaults)
        XCTAssertEqual(store.newReplies(for: "未知", replies: 500), 0)
    }

    func testReplyCountGoingDownShowsNoBadge() {
        // Moderation deletes replies; the badge must not show a negative count.
        let store = ThreadVisitStore(defaults: storage.defaults)
        store.markSeen(tid: "1", replies: 100)
        XCTAssertEqual(store.newReplies(for: "1", replies: 90), 0)
        store.markSeen(tid: "1", replies: 90)
        XCTAssertEqual(store.seen(tid: "1")?.replies, 90, "the new count is recorded")
    }

    func testMarkSeenPersists() {
        ThreadVisitStore(defaults: storage.defaults).markSeen(tid: "1", replies: 100)
        XCTAssertEqual(ThreadVisitStore(defaults: storage.defaults).seen(tid: "1")?.replies, 100)
    }

    func testMarkSeenWithUnchangedCountIsPersistedToo() {
        // Re-reading a thread with no new replies must still move its "seen"
        // date, otherwise pruning throws away the thread that was just read.
        ThreadVisitStore(defaults: storage.defaults).markSeen(tid: "1", replies: 100)
        let afterFirst = ThreadVisitStore(defaults: storage.defaults).seen(tid: "1")!.date

        let store = ThreadVisitStore(defaults: storage.defaults)
        let later = Date().addingTimeInterval(5)
        store.markSeen(tid: "1", replies: 100, at: later)

        let reopened = ThreadVisitStore(defaults: storage.defaults).seen(tid: "1")!
        XCTAssertEqual(reopened.replies, 100)
        XCTAssertEqual(reopened.date.timeIntervalSince1970, later.timeIntervalSince1970, accuracy: 1)
        XCTAssertGreaterThan(reopened.date, afterFirst)
    }

    func testMarkSeenPrunesToLimit() {
        let store = ThreadVisitStore(defaults: storage.defaults)
        for index in 0..<805 {
            store.markSeen(tid: "\(index)", replies: index)
        }
        XCTAssertEqual(store.count, 800)
        XCTAssertNotNil(store.seen(tid: "804"))
        XCTAssertNil(store.seen(tid: "0"), "the oldest entries go first")
    }

    func testClear() {
        let store = ThreadVisitStore(defaults: storage.defaults)
        store.markSeen(tid: "1", replies: 1)
        store.clear()
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(ThreadVisitStore(defaults: storage.defaults).count, 0)
    }

    // MARK: - ImageAspectStore

    func testAspectRoundTrip() {
        let store = ImageAspectStore(defaults: storage.defaults)
        let url = URL(string: "https://example.com/a.jpg")!
        store.store(aspect: 1.5, for: url)
        XCTAssertEqual(store.aspect(for: url), 1.5)
    }

    func testAspectRejectsImpossibleValues() {
        let store = ImageAspectStore(defaults: storage.defaults)
        let url = URL(string: "https://example.com/a.jpg")!
        for bad in [CGFloat(0), -1, .infinity, .nan, 0.001, 100] {
            store.store(aspect: bad, for: url)
        }
        XCTAssertNil(store.aspect(for: url))
    }

    func testAspectFlushPersists() {
        let store = ImageAspectStore(defaults: storage.defaults)
        let url = URL(string: "https://example.com/a.jpg")!
        store.store(aspect: 2, for: url)
        store.flush()
        XCTAssertEqual(ImageAspectStore(defaults: storage.defaults).aspect(for: url), 2)
    }

    func testAspectStoreEvictsBeyondLimit() {
        let store = ImageAspectStore(defaults: storage.defaults)
        for index in 0..<810 {
            store.store(aspect: 2, for: URL(string: "https://example.com/\(index).jpg")!)
        }
        let last = URL(string: "https://example.com/809.jpg")!
        XCTAssertNotNil(store.aspect(for: last))
        let filled = (0..<810).filter { store.aspect(for: URL(string: "https://example.com/\($0).jpg")!) != nil }
        XCTAssertEqual(filled.count, 800, "the store must stay at its limit instead of growing forever")
    }
}
