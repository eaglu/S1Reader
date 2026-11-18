import XCTest

/// 底部继续上滑检查新回复：滑到最后一楼之后再往上拉一次，应该去问服务器。
final class BottomNewRepliesOverscrollTests: XCTestCase {
    private let lastPage = 9
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    func testPullUpAtTheBottomAsksTheServer() throws {
        launch(jumpingTo: lastPage)
        scrollToTheBottom()
        let idle = hint("看看有没有新回复")
        XCTAssertTrue(idle.waitForExistence(timeout: 5), "到底了也没看到提示行")
        sleep(2)
        pullPastTheBottom()
        let answered = hint("暂无新回复")
        // "已加载 N 条新回复", not the "已加载 7 / 327 楼" page footer.
        let loaded = hint("条新回复")
        let failed = hint("检查失败")
        XCTAssertTrue(answered.waitForExistence(timeout: 10) || loaded.exists || failed.exists,
                      "拉到过滚位置也没有去问服务器，提示行仍是：\(idle.label)")
        let state = answered.exists ? "暂无新回复" : (loaded.exists ? "已加载" : "检查失败")
        XCTAssertFalse(idle.waitForExistence(timeout: 1),
                       "问完之后提示行又变回「继续上滑」，说明一次拉动触发了不止一次：\(state)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after-bottom-pull"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func launch(jumpingTo page: Int) {
        app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "thread:2206666"
        app.launchEnvironment["S1_JUMP_PAGE"] = "\(page)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        app.launch()
        XCTAssertTrue(bodies.element(boundBy: 0).waitForExistence(timeout: 30), "楼层没有渲染出来：这条用例需要网络")
    }

    private func scrollToTheBottom() {
        for _ in 0..<4 { app.swipeUp(velocity: .fast) }
        sleep(1)
    }

    private func pullPastTheBottom() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.2, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        sleep(3)
    }

    private var bodies: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "postBody-"))
    }

    private func hint(_ fragment: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }
}
