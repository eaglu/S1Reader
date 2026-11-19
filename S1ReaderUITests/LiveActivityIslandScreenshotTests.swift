import XCTest

/// Screenshot-only coverage for the reading Live Activity's Dynamic Island.
///
/// The simulator cannot be long-pressed from the command line, so the expanded
/// form needs XCTest's own touch. Run one case at a time, in the appearance
/// you want to shoot, and export the attachments:
///
///     TEST_RUNNER_S1_ISLAND_SHOTS=1 xcodebuild test \
///       -scheme S1ReaderUI -only-testing:S1ReaderUITests/LiveActivityIslandScreenshotTests/testCompactIsland
///
/// Set `S1_ISLAND_SHOTS=1` (the `TEST_RUNNER_` prefix is stripped by xcodebuild)
/// or every case here is skipped: a normal UI-test run must not depend on Live
/// Activities being enabled on the device.
final class LiveActivityIslandScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["S1_ISLAND_SHOTS"] == "1",
            "screenshot-only: run with TEST_RUNNER_S1_ISLAND_SHOTS=1"
        )
    }

    /// One activity: the compact leading/trailing pair.
    func testCompactIsland() throws {
        try capture(mode: "demo", named: "compact")
    }

    /// Two activities: the newest stays compact and the other is squeezed into
    /// the minimal glyph.
    func testCompactAndMinimalIslands() throws {
        try capture(mode: "demo-pair", named: "compact-minimal")
    }

    /// Long-press the island: icon, title, page and the excerpt line.
    func testExpandedIsland() throws {
        try capture(mode: "demo", named: "expanded", expand: true)
    }

    private func capture(mode: String, named name: String, expand: Bool = false) throws {
        let app = XCUIApplication()
        app.launchEnvironment["S1_OPEN"] = "liveactivity"
        app.launchEnvironment["S1_LIVEACTIVITY"] = mode
        app.launch()

        // The activity is requested from the preview's task; give ActivityKit
        // time to hand it to SpringBoard before leaving the app.
        sleep(5)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCUIDevice.shared.press(.home)
        sleep(3)

        if expand {
            // The island sits at the top centre, about 35pt down on a 956pt
            // screen. The press has to be a real one; no simctl shortcut.
            let island = springboard.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.036)
            )
            island.press(forDuration: 1.2)
            sleep(2)
        }

        attach(XCUIScreen.main.screenshot(), named: name)
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
