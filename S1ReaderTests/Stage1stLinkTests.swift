import XCTest
@testable import S1Reader

/// Every URL shape S1 hands out has to be recognised, and nothing outside the
/// forum may be.
final class Stage1stLinkTests: XCTestCase {
    private func destination(_ string: String) -> Stage1stLink.Destination? {
        guard let url = URL(string: string) else { return nil }
        return Stage1stLink.destination(for: url)
    }

    func testRedirectToFloor() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=redirect&goto=findpost&ptid=2291277&pid=70354356"),
            .thread(tid: "2291277", pid: "70354356")
        )
    }

    func testRedirectWithoutPid() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=redirect&goto=findpost&ptid=2291277"),
            .thread(tid: "2291277", pid: nil)
        )
    }

    func testViewThreadQuery() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=viewthread&tid=99&page=3"),
            .thread(tid: "99", pid: nil)
        )
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=viewthread&tid=99&pid=1234"),
            .thread(tid: "99", pid: "1234")
        )
    }

    func testForumDisplayQuery() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=forumdisplay&fid=6"),
            .forum(fid: "6")
        )
    }

    func testThreadPath() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/thread-2291277-3-1.html"),
            .thread(tid: "2291277", pid: nil)
        )
    }

    func testThreadPathWithFloorFragment() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/thread-2291277-1-1.html#pid70354356"),
            .thread(tid: "2291277", pid: "70354356")
        )
        XCTAssertEqual(
            destination("https://stage1st.com/2b/thread-2291277-1-1.html#postmessage_70354356"),
            .thread(tid: "2291277", pid: "70354356")
        )
    }

    func testForumPath() {
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum-6-1.html"),
            .forum(fid: "6")
        )
    }

    func testLegacyHosts() {
        XCTAssertEqual(
            destination("https://bbs.saraba1st.com/2b/thread-1-1-1.html"),
            .thread(tid: "1", pid: nil)
        )
        XCTAssertEqual(
            destination("https://saraba1st.com/2b/thread-1-1-1.html"),
            .thread(tid: "1", pid: nil)
        )
        XCTAssertEqual(
            destination("https://www.stage1st.com/2b/thread-1-1-1.html"),
            .thread(tid: "1", pid: nil)
        )
    }

    func testAmpEscapedQuerySeparators() {
        // Links copied out of a post are HTML-escaped: every later parameter
        // arrives glued to a literal "amp;".
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=viewthread&amp;tid=123"),
            .thread(tid: "123", pid: nil)
        )
        XCTAssertEqual(
            destination("https://stage1st.com/2b/forum.php?mod=redirect&amp;goto=findpost&amp;ptid=123&amp;pid=456"),
            .thread(tid: "123", pid: "456")
        )
    }

    func testForeignHostIsRejected() {
        XCTAssertNil(destination("https://example.com/2b/thread-1-1-1.html"))
        XCTAssertNil(destination("https://stage1st.com.evil.example/2b/thread-1-1-1.html"))
    }

    func testLookalikeHostIsRejected() {
        // "hasSuffix" alone would accept any domain that merely ends in the same
        // letters, and a link in a post could then open inside the app.
        XCTAssertNil(destination("https://evilstage1st.com/2b/thread-1-1-1.html"))
        XCTAssertNil(destination("https://not-stage1st.com/2b/forum-6-1.html"))
    }

    func testUnrelatedPathOnTheForumIsIgnored() {
        XCTAssertNil(destination("https://stage1st.com/2b/home.php?mod=space&uid=1"))
    }

    func testViewThreadQueryWithoutTidFallsBackToThePath() {
        // Some rewritten links carry mod=viewthread but put the id in the path.
        XCTAssertEqual(
            destination("https://stage1st.com/2b/thread-555-1-1.html?mod=viewthread"),
            .thread(tid: "555", pid: nil)
        )
    }

    func testNonNumericIdsAreIgnored() {
        XCTAssertNil(destination("https://stage1st.com/2b/thread-abc-1-1.html"))
        XCTAssertNil(destination("https://stage1st.com/2b/forum-x-1.html"))
    }
}
