import XCTest
@testable import S1Reader

/// Malformed input has to be survivable: post bodies come from a forum, so the
/// parser sees unclosed tags, mis-nesting, truncated markup and hostile
/// attributes from real users. Nothing here should crash, hang or unbounded-grow.
final class HTMLParserFuzzTests: XCTestCase {
    private func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        body()
        return CFAbsoluteTimeGetCurrent() - start
    }

    private func assertFast(
        _ budget: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () -> Void
    ) {
        XCTAssertLessThan(elapsed(body), budget, "parsing must stay bounded", file: file, line: line)
    }

    // MARK: - Unclosed markup

    func testUnclosedInlineTagsKeepTheirText() {
        let nodes = HTMLParser.parse("开头<b>粗<i>斜")
        XCTAssertEqual(HTMLParser.plainText("开头<b>粗<i>斜"), "开头粗斜")
        XCTAssertFalse(nodes.isEmpty)
    }

    func testUnclosedQuoteDivStillEmitsTheQuote() {
        let nodes = HTMLParser.parse(#"<div class="reply_wrap">引用正文没有收尾"#)
        let quotes = nodes.compactMap { $0.quote?.text }
        XCTAssertEqual(quotes, ["引用正文没有收尾"])
    }

    func testUnclosedStyleTagKeepsTheRemainder() {
        let text = HTMLParser.plainText("<font color=\"red\">红色文字")
        XCTAssertEqual(text, "红色文字")
    }

    func testStrayClosingTagsAreHarmless() {
        let html = "</div></b></span></p></blockquote></font></a>"
        XCTAssertNoThrow(HTMLParser.parse(html))
        XCTAssertEqual(HTMLParser.plainText(html), "")
    }

    func testMisNestedTagsPreserveEveryCharacter() {
        XCTAssertEqual(HTMLParser.plainText("<b>a<i>b</b>c</i>d"), "abcd")
        XCTAssertEqual(HTMLParser.plainText("<div><span>内</div>容</span>"), "内\n容")
    }

    func testTruncatedTagStopsWithoutCrashing() {
        assertFast {
            XCTAssertNoThrow(HTMLParser.parse(#"<div class="#))
            XCTAssertNoThrow(HTMLParser.parse("<"))
            XCTAssertNoThrow(HTMLParser.parse("<a href="))
        }
    }

    // MARK: - Hostile sizes

    func testVeryLongAttributeIsParsedOnce() {
        let href = "https://example.com/" + String(repeating: "x", count: 50_000)
        let html = #"<a href="\#(href)">链接</a>"#
        assertFast {
            XCTAssertEqual(HTMLParser.plainText(html), "链接")
        }
    }

    func testManyAttributesOnOneTag() {
        let attributes = (0..<2_000).map { #"data-\#($0)="v\#($0)""# }.joined(separator: " ")
        let html = "<span \(attributes)>正文</span>"
        assertFast {
            XCTAssertEqual(HTMLParser.plainText(html), "正文")
        }
    }

    func testDeeplyNestedTagsDoNotBlowUpTheParser() {
        let depth = 5_000
        let html = String(repeating: "<b><i><u>", count: depth) + "深渊" + String(repeating: "</u></i></b>", count: depth)
        assertFast(3) {
            XCTAssertEqual(HTMLParser.plainText(html), "深渊")
        }
    }

    func testThousandsOfLineBreaksCollapse() {
        let html = "上" + String(repeating: "<br>", count: 5_000) + "下"
        assertFast {
            let text = HTMLParser.plainText(html)
            XCTAssertTrue(text.hasPrefix("上"))
            XCTAssertTrue(text.hasSuffix("下"))
            XCTAssertLessThanOrEqual(text.components(separatedBy: "\n").count, 5)
        }
    }

    func testUnclosedScriptSwallowsOnlyItsBody() {
        let html = "<p>前</p><script>var x = 1; <b>alert</b>"
        let text = HTMLParser.plainText(html)
        XCTAssertTrue(text.contains("前"))
        XCTAssertFalse(text.contains("alert"))
    }

    // MARK: - Entities

    func testBrokenEntitiesAreLeftAlone() {
        let input = "&amp;&#xZZ;&#999999999;&bogus;&&amp"
        assertFast {
            let decoded = HTMLParser.decodeEntities(input)
            XCTAssertFalse(decoded.isEmpty)
            XCTAssertTrue(decoded.contains("&"), "a bogus entity is kept verbatim")
        }
    }

    func testValidEntitiesStillDecodeAroundTheBrokenOnes() {
        XCTAssertEqual(HTMLParser.decodeEntities("&lt;&#65;&#x42;&amp;"), "<AB&")
    }

    func testEntitySoupDoesNotHang() {
        let input = String(repeating: "&#x", count: 20_000)
        assertFast {
            XCTAssertFalse(HTMLParser.decodeEntities(input).isEmpty)
        }
    }

    // MARK: - Prose that only looks like markup

    func testComparisonOperatorsSurvive() {
        XCTAssertEqual(HTMLParser.plainText("a < b 和 1<2"), "a < b 和 1<2")
    }

    // MARK: - Random soup

    func testRandomMarkupSoupParsesWithinBudget() {
        let html = Self.soup(seed: 20_261_112, length: 200_000)
        var nodes: [PostNode] = []
        assertFast(5) {
            nodes = HTMLParser.parse(html)
        }
        XCTAssertLessThan(nodes.count, 50_000, "node count must stay proportional to input")
        assertFast(5) {
            _ = HTMLParser.imageURLs(in: html)
            _ = HTMLParser.plainText(html)
        }
    }

    func testRandomSoupIsDeterministic() {
        let html = Self.soup(seed: 7, length: 5_000)
        XCTAssertEqual(HTMLParser.parse(html), HTMLParser.parse(html))
    }

    /// Deterministic pseudo-random markup: tags, quotes, entities and CJK text.
    private static func soup(seed: UInt64, length: Int) -> String {
        var state = seed
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let alphabet = Array("<>/=\"'divspanbrimgscriptabc中文&#;x0 9")
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            out.append(alphabet[Int(next() % UInt64(alphabet.count))])
        }
        return out
    }
}
