import XCTest

/// 往上翻补更早的页：一次触顶只能补一页，而且读者看的那一楼不能动。
///
/// 这一条只能用真实手势验证：缺陷来自滚动回调和 prepend 之间的相互触发，
/// 单元测试看不到那个循环。需要网络。
final class EarlierPageOverscrollTests: XCTestCase {
    /// 主题 2206666 有 328 楼，9 页，每页 40 楼：第 8 页是 #281–#320，第 9 页是 #321–#328。
    private let lastPage = 9
    private let floorsPerPage = 40
    private var firstFloorOfLastPage: Int { (lastPage - 1) * floorsPerPage + 1 }

    private var app: XCUIApplication!

    private var bodies: XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "postBody-"))
    }

    private var screenHeight: CGFloat { app.windows.firstMatch.frame.height }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 跳到最后一页后往上翻一次：只补第 8 页，读者那一楼还在原来的位置。
    func testOnePullAboveTheTopLoadsOnePageAndKeepsTheFloor() throws {
        launch(jumpingTo: lastPage)
        let topBefore = topFloorLabel()
        XCTAssertEqual(topBefore, "#\(firstFloorOfLastPage)")
        XCTAssertEqual(loadedPages(), "\(lastPage)-\(lastPage)")

        pullAboveTheTop()

        let state = describe(topBefore: topBefore)
        XCTAssertEqual(loadedPages(), "\(lastPage - 1)-\(lastPage)", "一次触顶加载了不止一页：\(state)")
        XCTAssertAtTop(topBefore, "翻页后阅读位置跳了：\(state)")
    }

    /// 停留在一页中间时往上滑只是往回看，不该触发任何加载。
    func testPullingInsideTheListLoadsNothing() throws {
        launch(jumpingTo: lastPage)
        pullAboveTheTop()
        XCTAssertEqual(loadedPages(), "\(lastPage - 1)-\(lastPage)")

        // 补上来的第 8 页有 40 楼，人现在停在这一页中间，离列表顶部还很远。
        let topBefore = topFloorLabel()
        pullAboveTheTop()

        let state = describe(topBefore: topBefore)
        XCTAssertEqual(loadedPages(), "\(lastPage - 1)-\(lastPage)", "离开顶部也在加载：\(state)")
    }

    // MARK: - 启动与手势

    private func launch(jumpingTo page: Int) {
        app = XCUIApplication()
        // 打开一个已知有多页的主题，直接停在指定页。
        app.launchEnvironment["S1_OPEN"] = "thread:2206666"
        app.launchEnvironment["S1_JUMP_PAGE"] = "\(page)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        // 列表把当前装载的页窗口挂在 accessibilityValue 上，补了几页一读便知。
        app.launchEnvironment["S1_WINDOW_PROBE"] = "1"
        app.launch()
        XCTAssertTrue(
            bodies.element(boundBy: 0).waitForExistence(timeout: 30),
            "楼层没有渲染出来：这条用例需要网络"
        )
    }

    /// 一次很慢的触顶：手指停在超滚位置，回弹前会连发很多次 offset 回调。
    private func pullAboveTheTop() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(
            forDuration: 0.2,
            thenDragTo: end,
            withVelocity: .slow,
            thenHoldForDuration: 0.4
        )
        sleep(3)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "pull-above-the-top"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 读屏

    /// 列表当前装着哪几页，形如 "8-9"。
    private func loadedPages() -> String? {
        let list = app.scrollViews["threadScroll"]
        guard list.exists else { return nil }
        return list.value as? String
    }

    /// 屏上最靠上的那一楼，例如 "#321"。
    private func topFloorLabel() -> String? {
        floorsOnScreen().first?.label
    }

    /// 读者原来那一楼还在屏幕上方，没有被新页顶下去或顶掉。
    /// 顶栏高约 115pt，再加一层楼的余量：贴顶的那些行不算"还在读"。
    private func XCTAssertAtTop(
        _ label: String?,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let label else {
            XCTFail("没有拿到楼层号：\(message())", file: file, line: line)
            return
        }
        guard let minY = floorsOnScreen().first(where: { $0.label == label })?.minY else {
            XCTFail("\(label) 已经不在屏幕上了：\(message())", file: file, line: line)
            return
        }
        XCTAssertLessThan(minY, 260, message(), file: file, line: line)
    }

    /// 屏上可见的楼层号，从上到下。列表会把屏幕外的行也挂在树上，所以要按可见范围过滤；
    /// 一次快照读完，避免边读边变导致 "No matches found for Element" 的抖动。
    private func floorsOnScreen() -> [(label: String, minY: CGFloat)] {
        guard let root = try? app.snapshot() else { return [] }
        var found: [(label: String, minY: CGFloat)] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText, node.label.hasPrefix("#") {
                let frame = node.frame
                if frame.height > 0, frame.maxY > 40, frame.minY < screenHeight - 40 {
                    found.append((node.label, frame.minY))
                }
            }
            for child in node.children {
                walk(child)
            }
        }
        walk(root)
        return found.sorted { $0.minY < $1.minY }
    }

    private func describe(topBefore: String?) -> String {
        let after = floorsOnScreen().map(\.label).joined(separator: ",")
        return "顶部 \(topBefore ?? "?") -> \(after)，装载页窗口：\(loadedPages() ?? "?")"
    }
}
