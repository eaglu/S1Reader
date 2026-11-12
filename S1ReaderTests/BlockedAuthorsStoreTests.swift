import XCTest
@testable import S1Reader

@MainActor
final class BlockedAuthorsStoreTests: XCTestCase {
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

    func testStartsEmpty() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.count, 0)
        XCTAssertFalse(store.isBlocked("123"))
    }

    func testBlockPersistsAcrossRelaunch() {
        BlockedAuthorsStore(defaults: storage.defaults).block("123", name: "老王")
        let relaunched = BlockedAuthorsStore(defaults: storage.defaults)
        XCTAssertTrue(relaunched.isBlocked("123"))
        XCTAssertEqual(relaunched.count, 1)
        XCTAssertEqual(relaunched.entries.first?.name, "老王")
    }

    func testUnblockPersists() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        store.block("123", name: "老王")
        store.unblock("123")
        XCTAssertFalse(store.isBlocked("123"))
        XCTAssertFalse(BlockedAuthorsStore(defaults: storage.defaults).isBlocked("123"))
    }

    func testSetBlockedMatchesFlag() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        store.setBlocked(true, authorID: "9", name: "甲")
        XCTAssertTrue(store.isBlocked("9"))
        // Re-blocking keeps one entry and updates the name.
        store.setBlocked(true, authorID: "9", name: "乙")
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.entries.first?.name, "乙")
        store.setBlocked(false, authorID: "9", name: "乙")
        XCTAssertEqual(store.count, 0)
    }

    func testEntriesAreSortedByName() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        store.block("3", name: "c")
        store.block("1", name: "a")
        store.block("2", name: "b")
        XCTAssertEqual(store.entries.map(\.name), ["a", "b", "c"])
    }

    /// Guests have no author id, so they must never become blockable.
    func testGuestAndEmptyIDsCannotBeBlocked() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        XCTAssertFalse(store.canBlock(""))
        XCTAssertFalse(store.canBlock("0"))
        XCTAssertTrue(store.canBlock("123"))
    }

    /// A notice or a floor can arrive without a usable name.
    func testBlankNameGetsAPlaceholder() {
        let store = BlockedAuthorsStore(defaults: storage.defaults)
        store.block("123", name: "   ")
        XCTAssertEqual(store.entries.first?.name, "（未知作者）")
    }
}
