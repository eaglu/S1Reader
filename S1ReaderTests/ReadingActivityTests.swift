import SwiftUI
import XCTest
@testable import S1Reader

/// The reading Live Activity: the link it hands back to the app, and the state
/// it puts on the Lock Screen. Both are plain values, so no ActivityKit is
/// started here — the widget only renders what these produce.
final class ReadingActivityTests: XCTestCase {

    // MARK: - Deep link

    func testReadingLinkParsesIntoAPage() {
        let url = URL(string: "s1reader://thread?tid=2291277&page=398")!
        XCTAssertEqual(AppDeepLink.parse(url), .reading(tid: "2291277", page: 398))
    }

    /// The widget builds its own spelling of the URL; the app has to accept it
    /// unchanged, otherwise tapping the island opens nothing.
    func testWidgetLinkIsTheAppLink() {
        let widgetURL = ReadingActivityAttributes.deepLink(tid: "2291277", page: 398)
        XCTAssertEqual(widgetURL.absoluteString, "s1reader://thread?tid=2291277&page=398")
        XCTAssertEqual(AppDeepLink.parse(widgetURL), .reading(tid: "2291277", page: 398))
    }

    func testReadingLinkRoundTrips() {
        let link = AppDeepLink.reading(tid: "42", page: 7)
        XCTAssertEqual(AppDeepLink.parse(link.url), link)
    }

    /// A page number that is not a page is ignored rather than treated as page
    /// one: the link still names a thread, which is what the reader asked for.
    func testBadPageFallsBackToTheThread() {
        XCTAssertEqual(
            parse("s1reader://thread?tid=42&page=abc"),
            .thread(tid: "42", pid: nil)
        )
        XCTAssertEqual(
            parse("s1reader://thread?tid=42&page=0"),
            .thread(tid: "42", pid: nil)
        )
    }

    /// Floor links and page links are different things; the existing pid form
    /// must keep winning when there is no page.
    func testFloorLinkIsUnchanged() {
        XCTAssertEqual(
            parse("s1reader://thread?tid=42&pid=70354356"),
            .thread(tid: "42", pid: "70354356")
        )
    }

    private func parse(_ string: String) -> AppDeepLink? {
        guard let url = URL(string: string) else { return nil }
        return AppDeepLink.parse(url)
    }

    // MARK: - ContentState

    func testPageLabelsAndProgress() {
        let state = ReadingActivityAttributes.ContentState(
            title: "  有生之年还能看到续作吗  ",
            page: 398,
            pageCount: 483,
            author: " eaglu ",
            excerpt: "第一行\n第二行"
        )
        XCTAssertEqual(state.title, "有生之年还能看到续作吗")
        XCTAssertEqual(state.author, "eaglu")
        XCTAssertEqual(state.pageLabel, "第 398/483 页")
        XCTAssertEqual(state.compactPageLabel, "398/483")
        XCTAssertEqual(state.progress, 397.0 / 482.0, accuracy: 0.0001)
        XCTAssertEqual(state.excerpt, "第一行 第二行", "the lock screen line is one line")
        XCTAssertTrue(state.isReady)
    }

    /// A stale or half-loaded state still has to render something sane.
    func testStateClampsItsNumbers() {
        let tooHigh = ReadingActivityAttributes.ContentState(
            title: "t", page: 999, pageCount: 10
        )
        XCTAssertEqual(tooHigh.page, 10)
        XCTAssertEqual(tooHigh.progress, 1)

        let zero = ReadingActivityAttributes.ContentState(
            title: "t", page: 0, pageCount: 0
        )
        XCTAssertEqual(zero.page, 1)
        XCTAssertEqual(zero.pageCount, 1)
        XCTAssertEqual(zero.pageLabel, "第 1/1 页")
    }

    func testEmptyAuthorBecomesNil() {
        let state = ReadingActivityAttributes.ContentState(
            title: "t", page: 1, pageCount: 2, author: "   "
        )
        XCTAssertNil(state.author)
    }

    func testLongExcerptIsTrimmed() {
        let long = String(repeating: "很", count: ReadingActivityAttributes.ContentState.excerptLimit + 20)
        let state = ReadingActivityAttributes.ContentState(
            title: "t", page: 1, pageCount: 1, excerpt: long
        )
        XCTAssertEqual(
            state.excerpt,
            String(repeating: "很", count: ReadingActivityAttributes.ContentState.excerptLimit) + "…"
        )
    }

    /// No title means the header never arrived: starting an activity then would
    /// put an empty card on the Lock Screen.
    func testStateWithoutATitleIsNotReady() {
        let state = ReadingActivityAttributes.ContentState(
            title: "   ", page: 1, pageCount: 1
        )
        XCTAssertFalse(state.isReady)
    }

    // MARK: - The card itself

    /// Renders the exact view the widget extension puts on the Lock Screen. The
    /// simulator cannot be locked from the command line, so this is what proves
    /// the card lays out (and stays legible in both appearances); the PNGs are
    /// also written out for a human to look at.
    @MainActor
    func testLockScreenCardRenders() throws {
        for scheme in [ColorScheme.light, .dark] {
            let card = ReadingLockScreenView(
                title: "有生之年还能看到续作吗",
                pageLabel: "第 398/483 页",
                author: "eaglu",
                excerpt: "最近重看了一遍，还是觉得这一段的节奏最好，可惜后面收得太急。",
                progress: 0.82
            )
            .frame(width: 360)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: card)
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage, "\(scheme) card must render")
            XCTAssertGreaterThan(image.size.width, 300)
            XCTAssertGreaterThan(image.size.height, 60)

            let name = scheme == .dark ? "s1-lock-card-dark.png" : "s1-lock-card.png"
            try XCTUnwrap(image.pngData())
                .write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name))
        }
    }
}
