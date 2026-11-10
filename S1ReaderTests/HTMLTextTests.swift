import SwiftUI
import XCTest
@testable import S1Reader

/// Covers the text layer of the parser: entities, whitespace, line breaks, the
/// plain-text export and the Dynamic Type scale.
final class HTMLTextTests: XCTestCase {

    // MARK: - Entities

    func testNamedEntitiesAreDecoded() {
        XCTAssertEqual(Fixture.plainText("a&amp;b&lt;c&gt;d&quot;e&apos;f"), "a&b<c>d\"e'f")
    }

    func testDoubleEncodedEntitiesAreDecodedOnceMore() {
        // Discuz re-encodes text that was already escaped, so `<` arrives as
        // "&amp;lt;" and would otherwise show up literally.
        XCTAssertEqual(Fixture.plainText("&amp;lt;b&amp;gt;"), "<b>")
    }

    func testNumericEntities() {
        XCTAssertEqual(Fixture.plainText("&#20013;&#x6587;"), "中文")
        XCTAssertEqual(Fixture.plainText("&#x1F600;"), "😀")
    }

    func testInvalidEntityIsLeftAlone() {
        // U+110000 does not exist: the text must survive instead of vanishing.
        XCTAssertEqual(Fixture.plainText("&#1114112;"), "&#1114112;")
    }

    func testNonBreakingSpaceBecomesSpace() {
        XCTAssertEqual(Fixture.plainText("一&nbsp;二"), "一 二")
    }

    // MARK: - Line breaks

    func testSingleBreakIsOneNewline() {
        XCTAssertEqual(Fixture.plainText("上<br>下"), "上\n下")
        XCTAssertEqual(Fixture.plainText("上<br/>下"), "上\n下")
        XCTAssertEqual(Fixture.plainText("上<br />下"), "上\n下")
    }

    func testLongRunOfBreaksCollapsesToParagraph() {
        XCTAssertEqual(Fixture.plainText("上<br /><br /><br /><br /><br />下"), "上\n\n下")
    }

    func testParagraphTagsBreakLines() {
        XCTAssertEqual(Fixture.plainText("<p>一</p><p>二</p>"), "一\n二")
    }

    func testLeadingBreaksAreDropped() {
        // Discuz opens many posts with a stray <br />; it must not push every
        // post down by two blank lines.
        XCTAssertEqual(Fixture.plainText("<br /><br />正文"), "正文")
    }

    func testThreeBlankLinesCollapseInPlainText() {
        XCTAssertEqual(Fixture.plainText("一<br /><br /><br /><br /><br />二"), "一\n\n二")
    }

    // MARK: - Whitespace

    func testIndentationSpacesAreDroppedAtLineStart() {
        XCTAssertEqual(Fixture.plainText("<br />   缩进"), "缩进")
    }

    func testTrailingWhitespaceIsTrimmed() {
        XCTAssertEqual(Fixture.plainText("正文   <br /><br />"), "正文")
    }

    // MARK: - Non-content tags

    func testScriptAndStyleBodiesAreSkipped() {
        XCTAssertEqual(Fixture.plainText("<script>var a = 1 < 2;</script>可见"), "可见")
        XCTAssertEqual(Fixture.plainText("<style>p { color: red }</style>可见"), "可见")
    }

    func testUnknownTagIsIgnoredButItsTextKept() {
        XCTAssertEqual(Fixture.plainText("<span>甲</span><table><tr><td>乙</td></tr></table>"), "甲\n乙")
    }

    // MARK: - Plain text export

    func testPlainTextDropsImagesEntirely() {
        XCTAssertEqual(Fixture.plainText("前<img src=\"https://example.com/a.jpg\" />后"), "前后")
    }

    func testPlainTextKeepsQuoteText() {
        XCTAssertEqual(
            Fixture.plainText("<div class=\"reply_wrap\">引用</div>正文"),
            "引用\n正文"
        )
    }

    func testPlainTextTrimsOuterWhitespace() {
        XCTAssertEqual(Fixture.plainText("\n\n 有内容 \n\n"), "有内容")
    }

    // MARK: - Dynamic Type scale

    func testTextScaleIsMonotonic() {
        let order: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large,
            .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5
        ]
        let scales = order.map(HTMLParser.textScale(for:))
        XCTAssertEqual(scales, scales.sorted(), "scale must never shrink as the text size grows")
        XCTAssertEqual(HTMLParser.textScale(for: .large), 1)
    }

    func testTextScaleReachesAccessibilitySizes() {
        XCTAssertGreaterThan(HTMLParser.textScale(for: .accessibility5), 3)
        XCTAssertLessThan(HTMLParser.textScale(for: .accessibility5), 3.5)
    }

    func testFontSizeTable() {
        XCTAssertEqual(HTMLParser.fontPointSize(for: 1), 12)
        XCTAssertEqual(HTMLParser.fontPointSize(for: 3), 17)
        XCTAssertEqual(HTMLParser.fontPointSize(for: 6), 30)
        XCTAssertEqual(HTMLParser.fontPointSize(for: 7), 36, "unknown sizes fall back to the largest step")
        XCTAssertEqual(HTMLParser.fontPointSize(for: 0), 36)
    }

    // MARK: - Floor ids

    func testPidInFindPost() {
        XCTAssertEqual(
            HTMLParser.pidInFindPost("forum.php?mod=redirect&goto=findpost&ptid=1&pid=70354356"),
            "70354356"
        )
        XCTAssertNil(HTMLParser.pidInFindPost("forum.php?mod=viewthread&tid=1"))
        XCTAssertNil(HTMLParser.pidInFindPost("forum.php?goto=findpost&pid=abc"))
        XCTAssertNil(HTMLParser.pidInFindPost(""))
    }

    // MARK: - Stability

    func testParsingIsDeterministic() {
        // PostRowView compares a freshly fetched body with the one already on
        // screen; if two parses of the same HTML differed, every row would be
        // re-laid out on each appearance.
        let html = "<b>粗</b><br />正文 <img src=\"https://example.com/a.jpg\" /> 尾巴"
        XCTAssertEqual(Fixture.parse(html), Fixture.parse(html))
    }
}
