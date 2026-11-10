import SwiftUI
import XCTest
@testable import S1Reader

/// Covers the structural layer: inline styles, links, quotes and images.
final class HTMLStructureTests: XCTestCase {

    // MARK: - Inline styles

    func testBoldStrongBItalicAndUnderline() {
        XCTAssertTrue(Fixture.parse("<b>粗</b>")[0].attributed?.hasFont == true)
        XCTAssertFalse(Fixture.parse("普通")[0].attributed?.hasFont == true, "plain text needs no font override")
        XCTAssertTrue(Fixture.parse("<i>斜</i>")[0].attributed?.hasFont == true)
        XCTAssertTrue(Fixture.parse("<u>线</u>")[0].attributed?.hasUnderline == true)
        XCTAssertTrue(Fixture.parse("<ins>线</ins>")[0].attributed?.hasUnderline == true)
    }

    func testFontTagCarriesSize() {
        let node = Fixture.parse("<font size=\"5\">大字</font>")[0]
        XCTAssertEqual(node.text, "大字")
        XCTAssertTrue(node.attributed?.hasFont == true)
    }

    func testFontTagColor() {
        XCTAssertTrue(Fixture.parse("<font color=\"#ff0000\">红</font>")[0].attributed?.hasColor == true)
        XCTAssertTrue(Fixture.parse("<span style=\"color: #00ff00\">绿</span>")[0].attributed?.hasColor == true)
    }

    func testInvalidColourIsIgnoredNotCrashed() {
        let nodes = Fixture.parse("<font color=\"nope\">字</font>")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].text, "字")
        XCTAssertNil(nodes[0].attributed?.hasColor == true ? "coloured" : nil)
    }

    func testNestedStyleDoesNotLeakPastItsTag() {
        let nodes = Fixture.parse("<b>粗</b>正文")
        XCTAssertEqual(nodes.count, 1)
        guard let attributed = nodes[0].attributed else { return XCTFail("expected text") }
        let plain = attributed.runs.filter { $0.font == nil }
        XCTAssertEqual(plain.map { String(attributed[$0.range].characters) }, ["正文"])
    }

    func testUnclosedBoldEndsWithParagraph() {
        // A post that never closes <b> keeps it bold to the end, like a browser
        // would, but the text after the paragraph must all still be there.
        let nodes = Fixture.parse("一<b>粗<p>二</p>")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].text, "一粗\n二")
    }

    // MARK: - Links

    func testLinkAttributeIsResolved() {
        let node = Fixture.parse("<a href=\"https://example.com/x\">链</a>")[0]
        XCTAssertEqual(node.attributed?.mostCommonLink, URL(string: "https://example.com/x"))
        XCTAssertTrue(node.attributed?.hasColor == true, "a link is tinted like one")
    }

    func testProtocolRelativeLinkBecomesHTTPS() {
        let node = Fixture.parse("<a href=\"//stage1st.com/2b/thread-1-1-1.html\">链</a>")[0]
        XCTAssertEqual(node.attributed?.mostCommonLink?.scheme, "https")
    }

    func testRelativeLinkIsResolvedAgainstTheForum() {
        let node = Fixture.parse("<a href=\"thread-1-1-1.html\">链</a>")[0]
        XCTAssertEqual(node.attributed?.mostCommonLink?.host, "stage1st.com")
        XCTAssertEqual(node.attributed?.mostCommonLink?.path, "/2b/thread-1-1-1.html")
    }

    func testLinkTextSurvivesWhenHrefIsMissing() {
        let nodes = Fixture.parse("<a>无链接</a>")
        XCTAssertEqual(nodes.first?.text, "无链接")
    }

    // MARK: - Quotes

    func testReplyWrapBecomesQuoteNode() {
        let nodes = Fixture.parse("<div class=\"reply_wrap\">引用内容</div>正文")
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0].quote?.text, "引用内容")
        XCTAssertEqual(nodes[1].text, "正文")
    }

    func testBlockquoteBecomesQuoteNode() {
        let nodes = Fixture.parse("<blockquote>引用</blockquote>正文")
        XCTAssertEqual(nodes.first?.quote?.text, "引用")
    }

    func testQuoteIsSecondaryAndSmaller() {
        let quote = Fixture.parse("<div class=\"reply_wrap\">引用</div>")[0]
        XCTAssertTrue(quote.attributed?.isSecondary == true)
        XCTAssertTrue(quote.attributed?.hasFont == true, "quotes are drawn at a fixed smaller size")
    }

    func testQuotedFloorComesFromTheHeaderLink() {
        let html = """
        <div class="reply_wrap"><a href="forum.php?mod=redirect&amp;goto=findpost&amp;ptid=1&amp;pid=70354356" target="_blank">发表于 2024-1-1</a><br />原帖内容<br /></div>回复
        """
        let nodes = Fixture.parse(html)
        XCTAssertEqual(nodes.first?.quote?.pid, "70354356")
        XCTAssertTrue(nodes.first?.quote?.text.contains("原帖内容") == true)
        XCTAssertEqual(nodes.last?.text, "回复")
    }

    func testNestedQuotesCollapseToOneCard() {
        let html = "<div class=\"reply_wrap\">甲<blockquote>乙</blockquote>丙</div>正文"
        let nodes = Fixture.parse(html)
        XCTAssertEqual(nodes.count, 2, "a quote inside a quote stays one card")
        XCTAssertTrue(nodes[0].quote?.text.contains("甲") == true)
        XCTAssertTrue(nodes[0].quote?.text.contains("乙") == true)
    }

    func testUnclosedQuoteStillRenders() {
        let nodes = Fixture.parse("<div class=\"reply_wrap\">没有结束标签")
        XCTAssertEqual(nodes.first?.quote?.text, "没有结束标签")
    }

    // MARK: - Images

    func testImageIsParsedWithAbsoluteURL() {
        let node = Fixture.parse("<img src=\"https://example.com/a.jpg\" />").first
        XCTAssertEqual(node?.image?.url, URL(string: "https://example.com/a.jpg"))
        XCTAssertEqual(node?.image?.isSmiley, false)
    }

    func testRelativeImageResolvesToTheForum() {
        let node = Fixture.parse("<img src=\"static/image/common/back.gif\" />").first
        XCTAssertEqual(node?.image?.url.host, "stage1st.com")
        XCTAssertEqual(node?.image?.url.path, "/2b/static/image/common/back.gif")
    }

    func testSmileyIsFlagged() {
        let node = Fixture.parse("<img src=\"static/image/smiley/default/tuzki.gif\" />").first
        XCTAssertEqual(node?.image?.isSmiley, true)
        XCTAssertEqual(Fixture.parse("<img src=\"https://stage1st.com/2b/static/image/smilies/a.gif\" />").first?.image?.isSmiley, true)
    }

    func testPlaceholderImageIsDropped() {
        XCTAssertTrue(Fixture.parse("<img src=\"static/image/common/none.gif\" />").isEmpty)
        XCTAssertTrue(Fixture.parse("<img src=\"static/image/common/none.gif\" file=\"static/image/common/none.gif\" />").isEmpty)
    }

    func testAttachmentUsesFileAttributeOverThumbnail() {
        // Discuz renders an attachment as <img file="big" src="thumb">; the body
        // must show the full picture, not the thumbnail.
        let node = Fixture.parse(
            "<img src=\"static/image/common/thumb.jpg\" file=\"https://example.com/big.jpg\" />"
        ).first
        XCTAssertEqual(node?.image?.url, URL(string: "https://example.com/big.jpg"))
    }

    func testLazyLoadedImageUsesRealSource() {
        // Anything that lazy-loads leaves a placeholder in src and the real
        // picture in data-src; showing src would show a blank box forever.
        let node = Fixture.parse(
            "<img src=\"static/image/common/loading.gif\" data-src=\"https://example.com/real.jpg\" />"
        ).first
        XCTAssertEqual(node?.image?.url, URL(string: "https://example.com/real.jpg"))
    }

    func testImageInsideQuoteIsDropped() {
        let nodes = Fixture.parse("<div class=\"reply_wrap\">引用<img src=\"https://example.com/a.jpg\" /></div>")
        XCTAssertEqual(nodes.count, 1)
        XCTAssertNil(nodes[0].image)
    }

    func testSmileyAndTextShareOneNode() {
        // The renderer folds consecutive text runs into one line, so a smiley in
        // the middle of a sentence must not become a line of its own.
        XCTAssertEqual(Fixture.plainText("前<img src=\"static/image/smiley/default/a.gif\" />后"), "前后")
        let nodes = Fixture.parse("前<img src=\"static/image/smiley/default/a.gif\" />后")
        XCTAssertEqual(nodes.compactMap(\.text), ["前", "后"])
        XCTAssertEqual(nodes.compactMap(\.image).map(\.isSmiley), [true])
    }

    // MARK: - Image bookkeeping

    func testImageURLsMatchWhatTheBodyRenders() {
        // ThreadDetailView prefetches aspect ratios from imageURLs(in:); a URL the
        // renderer shows but this function misses keeps a 4:3 guess and the row
        // re-sizes when the picture lands.
        let html = """
        <img src="static/image/smiley/default/a.gif" />
        <img src="static/image/common/none.gif" />
        <img src="https://example.com/a.jpg" />
        <img src="static/image/common/thumb.jpg" file="https://example.com/big.jpg" />
        <div class="reply_wrap">引用<img src="https://example.com/quoted.jpg" /></div>
        """
        let rendered = Fixture.parse(html).compactMap { $0.image?.url }
        let listed = HTMLParser.imageURLs(in: html)
        XCTAssertEqual(listed, rendered)
    }

    func testImageURLsAreUniqueAndOrdered() {
        let html = """
        <img src="https://example.com/a.jpg" /><img src="https://example.com/b.jpg" /><img src="https://example.com/a.jpg" />
        """
        XCTAssertEqual(HTMLParser.imageURLs(in: html).map(\.absoluteString), [
            "https://example.com/a.jpg", "https://example.com/b.jpg"
        ])
    }

    func testImageURLsSkipsPostsWithoutImages() {
        XCTAssertTrue(HTMLParser.imageURLs(in: "纯文字，提到 <img 也只是文字").isEmpty)
    }
}
