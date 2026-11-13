import XCTest

/// 图片查看器关得掉吗 —— 下拉、左边缘右滑，以及缩放状态下这两条是不是该让开。
///
/// 手势只能这样验：`simctl` 注入不了触摸，`simvyn input swipe` 在 iOS 上直接
/// 报 “Input injection not supported”。这些用例要网络（外链图片 p.sda1.dev）。
final class ImageBrowserDismissTests: XCTestCase {
    /// 塞尔达专楼第一页第一张外链图：拿它开查看器，多图横滑才有东西翻。
    private static let threadID = "2283078"
    private static let image = "https://p.sda1.dev/32/ba2f5cc556b0a43f013c7fabcecee980/20260609_225727.jpg"

    private var app: XCUIApplication!

    /// 工具栏里的关闭按钮：查看器开着它就在，关掉它就没了。
    private var closeButton: XCUIElement { app.buttons["关闭"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // 用例失败时上一个 App 实例可能还开着，别把下一次 launch 卡在"杀掉它"上。
        if let app, app.state != .notRunning {
            app.terminate()
        }
        app = nil
    }

    func testPullingDownClosesTheViewer() throws {
        launchViewer()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        // 按住不放一会儿：一是让录制能看清跟手状态，二是确认拖到位后松手才关。
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.6)

        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5), "未缩放状态下拉没关掉")
        add(screenshot(named: "closed-by-pull"))
    }

    func testShortPullSpringsBack() throws {
        launchViewer()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.47))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)

        // 松手后弹回去，人还留在查看器里。
        usleep(600_000)
        XCTAssertTrue(closeButton.exists, "轻微下拉就把查看器关了")
        add(screenshot(named: "sprung-back"))
    }

    func testPullingDownWhileZoomedPansThePicture() throws {
        launchViewer(zoom: 2)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)

        usleep(800_000)
        XCTAssertTrue(closeButton.exists, "缩放状态下拉把查看器关了：应该只是平移图片")
        add(screenshot(named: "zoomed-pull"))
    }

    func testSwipingInFromTheLeftEdgeClosesTheViewer() throws {
        launchViewer()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.004, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)

        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5), "左边缘右滑没关掉")
        add(screenshot(named: "closed-by-edge-swipe"))
    }

    func testHorizontalSwipeStillPages() throws {
        launchViewer()
        let before = pageTitle()
        XCTAssertNotNil(before, "没读到页码标题")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        // 慢一点、松手前停一下：快速一甩在慢机器上不一定被 pager 当成翻页。
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)

        XCTAssertTrue(closeButton.exists, "横滑翻页把查看器关了")

        // 页码要等翻页动画结束才换，所以是轮询而不是只读一次。
        var after = waitForPageChange(from: before, seconds: 8)
        if after == before {
            // 拖动没翻页时再试一次系统标准的轻扫，好把"手势没综合出来"和
            // "pager 真的不翻"区分开。
            app.swipeLeft()
            after = waitForPageChange(from: before, seconds: 8)
        }
        if after == before {
            let dots = app.pageIndicators.firstMatch
            XCTFail("横滑没翻到下一张：title=\(before ?? "nil") dots=\(dots.exists ? "\(dots.value ?? "nil")" : "none") frame=\(app.frame) orientation=\(XCUIDevice.shared.orientation.rawValue)")
        }
        add(screenshot(named: "paged"))
    }

    // MARK: - Helpers

    /// 等到页码离开 `before` 为止；超时就把最后读到的值回去。
    private func waitForPageChange(from before: String?, seconds: TimeInterval) -> String? {
        var current = pageTitle()
        let deadline = Date().addingTimeInterval(seconds)
        while current == before, Date() < deadline {
            usleep(200_000)
            current = pageTitle()
        }
        return current
    }

    /// 查看器容器：`value` 是 `fit` 或 `zoomed`，手势怎么分工就看这个。
    private var viewer: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "image-viewer").firstMatch
    }

    private func launchViewer(zoom: Int? = nil) {
        app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "thread:\(Self.threadID)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        app.launchEnvironment["S1_VIEW_IMAGE"] = Self.image
        if let zoom { app.launchEnvironment["S1_ZOOM"] = String(zoom) }
        app.launch()

        guard closeButton.waitForExistence(timeout: 40) else {
            XCTFail("图片查看器没打开：这些用例要网络")
            return
        }
        // 等查看器自己报出缩放状态，而不是拿一个固定的 sleep 去猜：慢机器上
        // 拖在"还没进入状态"的查看器上，两种手势的结论会变得完全不一样。
        let expected = zoom == nil ? "fit" : "zoomed"
        let deadline = Date().addingTimeInterval(20)
        while (viewer.value as? String) != expected, Date() < deadline {
            usleep(200_000)
        }
        XCTAssertEqual(viewer.value as? String, expected, "查看器没有进入预期的缩放状态")
        // 再等图片真正解码出来，免得手势落在还没铺开的内容上。
        usleep(1_000_000)
    }

    /// 「5 / 12」这种页码标题；单张图时是「图片」，返回 nil 也无所谓。
    private func pageTitle() -> String? {
        let element = app.staticTexts
            .matching(NSPredicate(format: "label MATCHES %@", "[0-9]+ / [0-9]+"))
            .firstMatch
        guard element.waitForExistence(timeout: 5) else { return nil }
        return element.label
    }

    private func screenshot(named name: String) -> XCTAttachment {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        return attachment
    }
}
