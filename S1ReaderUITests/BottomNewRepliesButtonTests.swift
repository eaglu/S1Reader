import XCTest

/// 底部「检查新回复」：滚到最后一楼，点一下按钮，应该去问服务器。
///
/// 这条以前是一次上拉手势触发的，手势换成了按钮之后，验证的东西没变：
/// 点一下要真的发出请求，并且把结果显示出来。
final class BottomNewRepliesButtonTests: XCTestCase {
    private let lastPage = 9
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    func testTappingTheButtonAsksTheServer() throws {
        try requireNetwork()
        launch(jumpingTo: lastPage)
        waitForFullScreenWindow()
        scrollToTheBottom()

        let button = checkButton
        XCTAssertTrue(button.waitForExistence(timeout: 10), "到底了也没看到「检查新回复」按钮")
        attach("at-bottom", button)
        XCTAssertTrue(button.isHittable, "按钮在屏幕外或点不到")
        XCTAssertEqual(button.label, "检查新回复", "默认态文案不对")
        // 整行至少 44pt，手指点得中。滚到底之后按钮要整个露出来，
        // 否则 XCUI 报的是被列表裁掉后的高度。
        XCTAssertGreaterThanOrEqual(button.frame.height, 44, "点击区不到 44pt")

        button.tap()

        // 请求可能很快就回来，所以「正在检查」和三种结果任一个出现都算数。
        let answered = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@ OR label CONTAINS %@ OR label == %@ OR label BEGINSWITH %@",
                "正在检查新回复", "条新回复", "暂无新回复", "检查失败"
            ),
            object: button
        )
        let verdict = XCTWaiter().wait(for: [answered], timeout: 15)
        attach("after-tap", button)
        XCTAssertEqual(verdict, .completed, "点了按钮也没有去问服务器，按钮仍是：\(button.label)")

        // 等结果自己退回默认态，按钮可以再点一次。
        let backToIdle = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "检查新回复"),
            object: button
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [backToIdle], timeout: 12),
            .completed,
            "结果没有回到默认态，按钮仍是：\(button.label)"
        )
        XCTAssertTrue(button.isEnabled, "回到默认态后按钮应该还能再点")
    }

    // MARK: - 网络前置

    /// 这条用例要打开线上主题才有按钮可点。连不上 stage1st.com 时跳过，
    /// 而不是红在一条与代码无关的断言上（同 EarlierPageOverscrollTests）。
    private func requireNetwork() throws {
        var request = URLRequest(url: URL(string: "https://stage1st.com/2b/")!)
        request.timeoutInterval = 10

        final class Probe {
            var answered = false
        }
        let probe = Probe()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            probe.answered = (response as? HTTPURLResponse) != nil
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 15)

        guard probe.answered else {
            throw XCTSkip("需要网络：连不上 stage1st.com，跳过这条依赖线上主题的用例")
        }
    }

    private var checkButton: XCUIElement {
        app.buttons["checkNewReplies"]
    }

    private func launch(jumpingTo page: Int) {
        app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "thread:2206666"
        app.launchEnvironment["S1_JUMP_PAGE"] = "\(page)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        app.launch()
        XCTAssertTrue(bodies.element(boundBy: 0).waitForExistence(timeout: 30), "楼层没有渲染出来：这条用例需要网络")
    }

    /// 这台机器上的模拟器是共享的：别的用例把 app 挤到后台时，窗口会缩成一小块，
    /// 量出来的点都是错的。等到窗口真正铺满屏幕再开始。
    private func waitForFullScreenWindow() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20), "没有拿到 app 的窗口")
        for _ in 0..<30 {
            if window.frame.height > 400 { return }
            usleep(500_000)
        }
        XCTFail("窗口不是全屏（高度 \(window.frame.height)）：app 可能被别的测试挤到后台了")
    }

    /// 一直滑到按钮整个露出来为止：按钮贴在列表最后，滑过头只是回弹。
    private func scrollToTheBottom() {
        for _ in 0..<8 {
            app.swipeUp(velocity: .fast)
            if checkButton.exists, checkButton.frame.height >= 44 { break }
            usleep(300_000)
        }
        sleep(1)
    }

    private var bodies: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "postBody-"))
    }

    private func attach(_ name: String, _ element: XCUIElement) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(name)-\(element.label)"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
