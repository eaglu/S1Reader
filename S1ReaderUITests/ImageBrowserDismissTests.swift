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
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .default, thenHoldForDuration: 0.1)

        XCTAssertTrue(closeButton.exists, "横滑翻页把查看器关了")
        let after = pageTitle()
        XCTAssertNotEqual(after, before, "横滑没翻到下一张")
        add(screenshot(named: "paged"))
    }

    // MARK: - Helpers

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
        // 等第一张图真正解码出来，免得手势落在还没铺开的内容上。
        usleep(3_000_000)
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
