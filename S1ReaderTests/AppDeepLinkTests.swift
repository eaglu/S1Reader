import XCTest
@testable import S1Reader

/// The `s1reader://` shapes Siri and Shortcuts hand back, and the defaults
/// hand-off an intent uses when the app is not on screen yet.
final class AppDeepLinkTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "s1.tests.deeplink"

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

    private func parse(_ string: String) -> AppDeepLink? {
        guard let url = URL(string: string) else { return nil }
        return AppDeepLink.parse(url)
    }

    func testForumRoundTrip() {
        let link = AppDeepLink.forum(fid: "6")
        XCTAssertEqual(link.url.absoluteString, "s1reader://forum?fid=6")
        XCTAssertEqual(AppDeepLink.parse(link.url), link)
    }

    func testThreadRoundTrip() {
        let withoutPid = AppDeepLink.thread(tid: "2291277", pid: nil)
        XCTAssertEqual(withoutPid.url.absoluteString, "s1reader://thread?tid=2291277")
        XCTAssertEqual(AppDeepLink.parse(withoutPid.url), withoutPid)

        let withPid = AppDeepLink.thread(tid: "2291277", pid: "70354356")
        XCTAssertEqual(withPid.url.absoluteString, "s1reader://thread?pid=70354356&tid=2291277")
        XCTAssertEqual(AppDeepLink.parse(withPid.url), withPid)
    }

    func testAccountRoundTrip() {
        XCTAssertEqual(AppDeepLink.notices.url.absoluteString, "s1reader://notices")
        XCTAssertEqual(AppDeepLink.parse(AppDeepLink.notices.url), .notices)
        XCTAssertEqual(AppDeepLink.favorites.url.absoluteString, "s1reader://favorites")
        XCTAssertEqual(AppDeepLink.parse(AppDeepLink.favorites.url), .favorites)
    }

    /// Shortcuts, Safari and hand-typed links do not agree on where the path
    /// starts, so both spellings are accepted.
    func testPathForm() {
        XCTAssertEqual(parse("s1reader:///forum/6"), .forum(fid: "6"))
        XCTAssertEqual(parse("s1reader://forum/6"), .forum(fid: "6"))
        XCTAssertEqual(parse("s1reader:///thread/2291277/70354356"), .thread(tid: "2291277", pid: "70354356"))
    }

    func testSchemeIsCaseInsensitive() {
        XCTAssertEqual(parse("S1Reader://THREAD?TID=42"), .thread(tid: "42", pid: nil))
    }

    /// `notice`, `alerts`, `favourites` and `bookmarks` are what dictation and
    /// other people's shortcuts tend to produce.
    func testAliases() {
        XCTAssertEqual(parse("s1reader://notice"), .notices)
        XCTAssertEqual(parse("s1reader://alerts"), .notices)
        XCTAssertEqual(parse("s1reader://favourites"), .favorites)
        XCTAssertEqual(parse("s1reader://bookmarks"), .favorites)
    }

    func testRejectsForeignLinks() {
        XCTAssertNil(parse("https://stage1st.com/2b/thread-2291277-1-1.html"))
        XCTAssertNil(parse("s1reader://"))
        XCTAssertNil(parse("s1reader://unknown"))
        XCTAssertNil(parse("s1reader://forum"))
        XCTAssertNil(parse("s1reader://thread?tid="))
        XCTAssertNil(parse("not a url"))
    }

    func testPendingLinkIsTakenOnce() {
        XCTAssertNil(PendingDeepLink.take(defaults: defaults))

        PendingDeepLink.post(.thread(tid: "42", pid: nil), defaults: defaults)
        XCTAssertEqual(PendingDeepLink.take(defaults: defaults), .thread(tid: "42", pid: nil))
        XCTAssertNil(PendingDeepLink.take(defaults: defaults), "a route must not be replayed")
    }

    func testPendingLinkSurvivesGarbage() {
        defaults.set("nonsense", forKey: PendingDeepLink.defaultsKey)
        XCTAssertNil(PendingDeepLink.take(defaults: defaults))
        XCTAssertNil(defaults.string(forKey: PendingDeepLink.defaultsKey), "the bad entry is dropped")
    }
}
