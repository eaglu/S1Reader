import XCTest

/// 底部「检查新回复」：滚到最后一楼，点一下按钮，应该去问服务器。
///
/// 这条以前是一次上拉手势触发的，手势换成了按钮之后，验证的东西没变：
/// 点一下要真的发出请求，并且把结果显示出来。结果本身不是按钮：它是一行
/// 静态文本，几秒后自己退回可点的默认态。
final class BottomNewRepliesButtonTests: XCTestCase {
    private let lastPage = 9
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    func testTappingTheButtonAsksTheServer() throws {
        try requireNetwork()
        launch(jumpingTo: lastPage)
        waitForFullScreenWindow()
        scrollToTheBottom()

        let button = app.buttons["checkNewReplies"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "到底了也没看到「检查新回复」按钮")
        attach("at-bottom", button)
        XCTAssertTrue(button.isHittable, "按钮在屏幕外或点不到")
        XCTAssertEqual(button.label, "检查新回复", "默认态文案不对")
        // 整行至少 44pt，手指点得中。滚到底之后按钮要整个露出来，
        // 否则 XCUI 报的是被列表裁掉后的高度。
        XCTAssertGreaterThanOrEqual(button.frame.height, 44, "点击区不到 44pt")
        let idleMidY = button.frame.midY

        button.tap()

        // 请求可能很快就回来，所以「正在检查」和三种结果任一个出现都算数。
        let row = checkRow
        let answered = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@ OR label CONTAINS %@ OR label == %@ OR label BEGINSWITH %@",
                "正在检查…", "条新回复", "暂无新回复", "检查失败"
            ),
            object: row
        )
        let verdict = XCTWaiter().wait(for: [answered], timeout: 15)
        attach("after-tap", row)
        XCTAssertEqual(verdict, .completed, "点了按钮也没有去问服务器，按钮仍是：\(row.label)")

        // 结果降级成一行静态文本：不再是一个按钮，高度和不点之前一样，
        // 所以列表不会因为“暂无新回复”跳一下。
        let result = app.staticTexts["checkNewReplies"]
        XCTAssertTrue(result.waitForExistence(timeout: 15), "检查完没有把结果显示成一行文本")
        // 这一行只活 4 秒，而 CI 上每次查询都要将近一秒：先量高度、再查
        // “不是按钮”，截图放最后，别让后置步骤把结果等没了。
        XCTAssertEqual(result.frame.midY, idleMidY, accuracy: 2, "结果态换了高度，列表会跳")
        // 结果态不是控件：这一行现在是一行静态文本，而不是按钮。用
        // matching(identifier:) 精确按 identifier 查——下标写法
        // （buttons["checkNewReplies"]）在切换的残影上会给出过期的结果，CI 与
        // 本地都因此误报过“还是按钮”；也不能改成“等它不存在”，等久了会等到
        // 这一行 4 秒后自己变回按钮的那一下。
        XCTAssertEqual(
            app.buttons.matching(identifier: "checkNewReplies").count, 0,
            "结果态不该还是一个按钮"
        )
        attach("result", result)

        // 等结果自己退回默认态，按钮可以再点一次。用 waitForExistence 而不是
        // XCTNSPredicateExpectation：行在切换的瞬间会短暂不在无障碍树里，谓词
        // 求值撞上那个空隙会直接报 “Failed to get matching snapshot”。
        let idleAgain = app.buttons["checkNewReplies"]
        XCTAssertTrue(idleAgain.waitForExistence(timeout: 12), "结果没有回到默认态：按钮一直没回来")
        XCTAssertEqual(idleAgain.label, "检查新回复", "结果没有回到默认态")
        XCTAssertTrue(idleAgain.isEnabled, "回到默认态后按钮应该还能再点")

        // 「正在检查」在线路上只停几百毫秒，按下去的瞬间抓不稳。用 hold 钩子
        // 把它停在原地，单独拍一张，三种状态才算都看得到。
        app.terminate()
        launch(jumpingTo: lastPage, extraEnvironment: ["S1_CHECK_NEW_HOLD": "1"])
        waitForFullScreenWindow()
        scrollToTheBottom()
        let checking = app.buttons["checkNewReplies"]
        XCTAssertTrue(checking.waitForExistence(timeout: 10), "hold 钩子没把行停在检查中")
        XCTAssertEqual(checking.label, "正在检查…", "检查中文案不对")
        XCTAssertFalse(checking.isEnabled, "检查中不应该还能再点")
        attach("checking", checking)
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

    /// 三种状态共用同一个 identifier：默认/检查中是按钮，结果是一行静态文本。
    private var checkRow: XCUIElement {
        app.descendants(matching: .any)["checkNewReplies"]
    }

    private func launch(jumpingTo page: Int, extraEnvironment: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "thread:2206666"
        app.launchEnvironment["S1_JUMP_PAGE"] = "\(page)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        for (key, value) in extraEnvironment {
            app.launchEnvironment[key] = value
        }
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

    /// 一直滑到整行露在窗口里为止：按钮贴在列表最后，滑过头只是回弹。
    /// `exists` 对屏幕外的行也是真，所以要量它到底在不在可视区。
    private func scrollToTheBottom() {
        let window = app.windows.firstMatch
        for _ in 0..<12 {
            if rowIsFullyVisible(in: window) { break }
            app.swipeUp(velocity: .fast)
            usleep(400_000)
        }
        sleep(1)
        XCTAssertTrue(rowIsFullyVisible(in: window), "滑到底也没把整行露出来")
    }

    private func rowIsFullyVisible(in window: XCUIElement) -> Bool {
        let row = checkRow
        guard row.exists else { return false }
        let frame = row.frame
        return frame.height >= 44
            && frame.minY >= window.frame.minY
            && frame.maxY <= window.frame.maxY - 8
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
