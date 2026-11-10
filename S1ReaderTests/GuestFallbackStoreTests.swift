import XCTest
@testable import S1Reader

@MainActor
final class GuestFallbackStoreTests: XCTestCase {
    private var storage: TemporaryDefaults!

    override func setUp() {
        super.setUp()
        storage = TemporaryDefaults()
    }

    override func tearDown() {
        storage.destroy()
        storage = nil
        super.tearDown()
    }

    func testUnknownThreadIsNotGuest() {
        let store = GuestFallbackStore(defaults: storage.defaults)
        XCTAssertFalse(store.prefersGuest(tid: "2291277"))
        XCTAssertEqual(store.count, 0)
    }

    func testMarkPersistsAcrossRelaunch() {
        GuestFallbackStore(defaults: storage.defaults).mark("2291277")
        let relaunched = GuestFallbackStore(defaults: storage.defaults)
        XCTAssertTrue(relaunched.prefersGuest(tid: "2291277"))
    }

    func testMarkingTwiceKeepsOneEntry() {
        let store = GuestFallbackStore(defaults: storage.defaults)
        store.mark("1")
        store.mark("1")
        XCTAssertEqual(store.count, 1)
    }

    func testUnmarkPersists() {
        let store = GuestFallbackStore(defaults: storage.defaults)
        store.mark("1")
        store.mark("2")
        store.unmark("1")
        XCTAssertFalse(store.prefersGuest(tid: "1"))
        XCTAssertFalse(GuestFallbackStore(defaults: storage.defaults).prefersGuest(tid: "1"))
        XCTAssertTrue(GuestFallbackStore(defaults: storage.defaults).prefersGuest(tid: "2"))
    }

    func testClearEmptiesTheList() {
        let store = GuestFallbackStore(defaults: storage.defaults)
        store.mark("1")
        store.mark("2")
        store.clear()
        XCTAssertEqual(store.count, 0)
        XCTAssertEqual(GuestFallbackStore(defaults: storage.defaults).count, 0)
    }

    func testEvictionDropsTheOldestFirst() {
        let store = GuestFallbackStore(defaults: storage.defaults)
        for tid in 0..<250 { store.mark("tid-\(tid)") }
        XCTAssertEqual(store.count, 200)
        // The thread just marked must survive: losing it would send the reader back
        // into the 503 the store exists to avoid.
        XCTAssertTrue(store.prefersGuest(tid: "tid-249"))
        XCTAssertFalse(store.prefersGuest(tid: "tid-0"))
        XCTAssertTrue(GuestFallbackStore(defaults: storage.defaults).prefersGuest(tid: "tid-249"))
    }
}
