import XCTest

/// Drives the real app on a simulator: 版块列表 → 主题列表 → 帖子详情.
///
/// This is the one test that needs the network. What it covers is exactly what
/// unit tests cannot see: a floor's body must end up as text. The bug where every
/// floor kept showing a grey placeholder bar shipped because nothing ever opened
/// a thread and looked.
final class ThreadRenderingTests: XCTestCase {
    private var app: XCUIApplication!

    private var bodies: XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "postBody-"))
    }

    private var placeholders: XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "postPlaceholder-"))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testOpeningAThreadRendersEveryFloor() throws {
        try openSomeThread()
        XCTAssertTrue(
            bodies.element(boundBy: 0).waitForExistence(timeout: 20),
            "楼层正文一直没出现"
        )
        // How many floors fit depends on the screen: the point is that what is on
        // screen is body text and not a placeholder bar.
        XCTAssertGreaterThanOrEqual(bodies.count, 1, "没有一层渲染出正文")
        XCTAssertEqual(placeholders.count, 0, "楼层正文仍然是骨架条")
        add(screenshot(named: "thread"))
    }

    /// 标题只画一次：在 ThreadHeaderView 里，不在顶栏里。
    ///
    /// 顶栏再放一份时，它会被截断成「为啥中文网络上各家 AI 的拟…」，
    /// 而正文里那份完整标题就摆在它下面：同一句话在屏幕上出现两次。
    func testTheThreadTitleIsDrawnOnce() throws {
        try openSomeThread()
        XCTAssertTrue(bodies.element(boundBy: 0).waitForExistence(timeout: 20))

        let bar = app.navigationBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "顶栏没出现")
        // 顶栏只剩动作；标题是正文的内容，不是栏的标题。
        XCTAssertEqual(
            bar.staticTexts.count, 0,
            "顶栏里又出现了文字（标题或截断后的标题）：\(bar.debugDescription)"
        )
        add(screenshot(named: "thread-top"))
    }

    func testScrollingForwardKeepsFloorsRendered() throws {
        try openSomeThread()
        XCTAssertTrue(bodies.element(boundBy: 0).waitForExistence(timeout: 20))

        for _ in 0..<6 {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertGreaterThan(bodies.count, 0, "滚动后没有任何一层渲染出正文")
        XCTAssertEqual(placeholders.count, 0, "滚动后出现了骨架条")
        add(screenshot(named: "thread-scrolled"))
    }

    // MARK: - Helpers

    private func openSomeThread() throws {
        // A board row is a NavigationLink whose Button does not answer taps, so the
        // label itself is the reliable target.
        let board = app.staticTexts["手游页游"]
        guard board.waitForExistence(timeout: 30) else {
            throw XCTSkip("版块列表没加载出来：这条用例需要网络")
        }
        board.tap()

        let firstCell = app.cells.element(boundBy: 0)
        guard firstCell.waitForExistence(timeout: 30) else {
            throw XCTSkip("主题列表没加载出来：这条用例需要网络")
        }
        firstCell.staticTexts.element(boundBy: 0).tap()
    }

    private func screenshot(named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
