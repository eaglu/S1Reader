import XCTest

/// 灵动岛 / 锁屏卡片上的「回到这一页」链接：点开必须落在卡片写的那一页。
///
/// 卡片递给系统的是 `s1reader://thread?tid=…&page=N`。用例刻意让卡片页（5）与
/// 读者离开时停的页（3）不同：跳页要是没生效，页窗口读数仍是 "3-3"，一眼就能看出来。
/// 两条用例分别走 App 收到链接的两种时机：
///
/// * 冷启动（`S1_DL_URL`）：App 起来时栈是空的，链接直接把帖子推进去；
/// * 热启动（`S1_PENDING_LINK`）：帖子已经在屏幕上，链接从外面换掉路由——
///   这正是 SwiftUI 复用同一个视图、旧代码把跳页吞掉的那条路。
final class ReadingActivityDeepLinkTests: XCTestCase {
    /// 主题 2206666 有 9 页，每页 40 楼，足够分得开。
    private let threadID = "2206666"
    private let cardPage = 5
    private let readingPage = 3
    private var app: XCUIApplication!

    override func setUpWithError() throws { continueAfterFailure = false }

    /// 冷启动：App 不在，点卡片直接落在卡片那一页。
    func testColdStartLandsOnThePageTheCardNames() throws {
        try requireNetwork()
        app = XCUIApplication()
        app.launchEnvironment["S1_DL_URL"] = "s1reader://thread?tid=\(threadID)&page=\(cardPage)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        app.launchEnvironment["S1_WINDOW_PROBE"] = "1"
        app.launch()
        waitForLanding("冷启动")
    }

    /// 热启动：读者停在第 3 页，切出去再点卡片（写的是第 5 页）。
    func testTheCardLinkLandsOnItsPageWhileAThreadIsAlreadyUp() throws {
        try requireNetwork()
        app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "thread:\(threadID)"
        app.launchEnvironment["S1_JUMP_PAGE"] = "\(readingPage)"
        app.launchEnvironment["S1_NO_RESTORE"] = "1"
        app.launchEnvironment["S1_WINDOW_PROBE"] = "1"
        // 帖子已经在屏幕上之后，从外面把链接交进来（卡片被点的时机）。
        app.launchEnvironment["S1_PENDING_LINK"] = "s1reader://thread?tid=\(threadID)&page=\(cardPage)"
        app.launch()

        XCTAssertTrue(
            bodies.element(boundBy: 0).waitForExistence(timeout: 30),
            "楼层没有渲染出来：这条用例需要网络"
        )
        waitForLanding("热启动")
    }

    // MARK: - 断言

    /// 页窗口回到卡片上写的那一页，而且只有那一页：不是先落第 1 页再补。
    private func waitForLanding(_ context: String) {
        let expected = "\(cardPage)-\(cardPage)"
        let deadline = Date().addingTimeInterval(40)
        var last = loadedPages()
        while Date() < deadline {
            last = loadedPages()
            if last == expected { break }
            usleep(400_000)
        }
        attach("landed-\(context)")
        XCTAssertEqual(
            last,
            expected,
            "\(context)点卡片后没有落在第 \(cardPage) 页，装载页窗口是：\(last ?? "?")"
        )
    }

    // MARK: - 前置

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

    private var bodies: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "postBody-"))
    }

    /// 列表当前装着的页窗口，形如 "3-3"。
    ///
    /// 换路由时 SwiftUI 会把新屏幕推在旧屏幕上面，旧的那一个还在树里：
    /// 读屏要读**看得见**的那一个，否则永远读到脚下那一页。
    private func loadedPages() -> String? {
        let matches = app.scrollViews.matching(identifier: "threadScroll")
        var fallback: String?
        for index in 0..<matches.count {
            let list = matches.element(boundBy: index)
            let value = list.value as? String
            fallback = value ?? fallback
            if list.isHittable, let value, !value.isEmpty { return value }
        }
        return fallback
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
