import XCTest
@testable import S1Reader

/// 灵动岛卡片递过来的换页请求：只交给它点名的那个帖子，而且只取一次。
///
/// 这个请求存在的理由就是「路由已经指向这个帖子」时视图不会被重建，
/// 所以它必须能独立于路由被取走，也不能被别的帖子顺手拿走。
@MainActor
final class ReadingJumpTests: XCTestCase {
    func testTheJumpGoesToItsThreadOnce() {
        let app = AppModel()
        app.requestReadingJump(tid: "42", page: 3)

        XCTAssertNil(app.takeReadingJump(for: "43"), "别的帖子不该拿走这次跳页")
        XCTAssertEqual(app.takeReadingJump(for: "42"), 3)
        XCTAssertNil(app.takeReadingJump(for: "42"), "同一次请求只跳一次")
    }

    func testAPageBelowOneIsClamped() {
        let app = AppModel()
        app.requestReadingJump(tid: "42", page: 0)

        XCTAssertEqual(app.takeReadingJump(for: "42"), 1, "页码非法时退到第 1 页")
    }

    /// 新的请求覆盖旧的：读者在卡片上看到的是最新的那一页。
    func testTheNewestRequestWins() {
        let app = AppModel()
        app.requestReadingJump(tid: "42", page: 3)
        app.requestReadingJump(tid: "42", page: 5)

        XCTAssertEqual(app.takeReadingJump(for: "42"), 5)
    }
}
