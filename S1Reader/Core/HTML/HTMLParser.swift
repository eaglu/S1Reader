import SwiftUI

/// A rendered piece of a Discuz! post body.
enum PostNode: Hashable {
    case text(AttributedString)
    case image(URL, isSmiley: Bool)
    /// A quoted block (`<div class="reply_wrap">` / `<blockquote>`), rendered as
    /// its own card so it cannot be confused with the reply body.
    case quote(Quote)

    /// The pieces of a quote the reader draws separately: the "作者 发表于 时间"
    /// line as a caption, and the rest as the quoted body. `body` may hold a
    /// nested quote, which is what quoting a post that itself quotes produces.
    struct Quote: Hashable {
        /// How many quote cards the reader is willing to stack. Discuz nests
        /// quotes freely and three frames of tint read as a smudge, so anything
        /// deeper than this is flattened into the innermost card's text.
        static let maxDepth = 2

        /// The header line as plain text, already stripped of its link.
        var header: String?
        /// Quoted text (and at most one nested quote).
        var body: [PostNode]
        /// The floor this quote points at, when the original linked to it.
        var pid: String?

        /// Whether a line of quoted HTML is Discuz's quote header rather than
        /// quoted prose. S1 heads every quote with "作者 发表于 时间"; a long
        /// first line is somebody's sentence, not a header.
        static func looksLikeHeader(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 60 else { return false }
            return trimmed.contains("发表于")
        }
    }
}

/// Converts the HTML fragment returned by the mobile API into renderable nodes.
/// It intentionally supports only the tag subset S1 actually produces:
/// br/p/div, font, strong/b, em/i, u, a, img, blockquote, div.reply_wrap.
enum HTMLParser {
    struct Style {
        var color: Color?
        var bold = false
        var italic = false
        var underline = false
        var size: CGFloat?
        var link: URL?
        var quoteDepth = 0
    }

    static func parse(_ html: String, scale: CGFloat = 1) -> [PostNode] {
        var builder = PostBuilder(html: normalize(html), scale: scale)
        return builder.run()
    }

    /// Multiplier that makes Discuz's absolute font sizes follow Dynamic Type.
    static func textScale(for size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.35
        case .accessibility1: 1.65
        case .accessibility2: 1.94
        case .accessibility3: 2.35
        case .accessibility4: 2.76
        case .accessibility5: 3.12
        @unknown default: 1
        }
    }

    /// Plain text of a post body, used by "复制文字".
    static func plainText(_ html: String) -> String {
        var text = ""
        for node in parse(html) {
            switch node {
            case .text(let value):
                text += String(value.characters)
            case .quote(let quote):
                // A quote is its own block in the reader, so it needs a line of
                // its own here too; otherwise "引用正文" glues the two together.
                if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
                if let header = quote.header { text += header + "\n" }
                text += Self.plainText(nodes: quote.body)
                text += "\n"
            case .image:
                continue
            }
        }
        var lines: [String] = []
        var blankRun = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                blankRun += 1
                if blankRun > 2 { continue }
            } else {
                blankRun = 0
            }
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Flattens a node list to text, used for quote bodies. Images are dropped;
    /// they are dropped from quotes by the parser in the first place.
    private static func plainText(nodes: [PostNode]) -> String {
        var text = ""
        for node in nodes {
            switch node {
            case .text(let value):
                text += String(value.characters)
            case .quote(let quote):
                if let header = quote.header { text += header + "\n" }
                text += plainText(nodes: quote.body)
            case .image:
                continue
            }
        }
        return text
    }

    /// Floor id of a `goto=findpost` link, used to make quotes tappable.
    static func pidInFindPost(_ href: String) -> String? {
        guard href.contains("findpost"), let range = href.range(of: "pid=") else { return nil }
        let digits = href[range.upperBound...].prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    /// Non-smiley images referenced by a post, used for cache bookkeeping.
    /// Pulls the post images out of the markup without building attributed
    /// strings.
    ///
    /// The full parser is a lot of work to answer "which images", but the answer
    /// has to match what the parser renders: a URL the renderer shows and this
    /// function misses keeps a guessed aspect ratio, and the row re-sizes when the
    /// picture lands. So it applies the same rules in the same order (attachment
    /// attributes before `src`, placeholders dropped, quotes skipped) over a
    /// shared tag scan.
    static func imageURLs(in html: String) -> [URL] {
        guard html.contains("<img") else { return [] }
        var urls: [URL] = []
        var seen = Set<String>()
        var divDepth = 0
        var quoteDivDepths: [Int] = []
        var blockquoteDepth = 0

        for tag in tags(in: html) {
            switch tag.name {
            case "blockquote":
                blockquoteDepth = max(0, blockquoteDepth + (tag.isClosing ? -1 : 1))
            case "div":
                if tag.isClosing {
                    if quoteDivDepths.last == divDepth { quoteDivDepths.removeLast() }
                    divDepth = max(0, divDepth - 1)
                } else {
                    divDepth += 1
                    let classes = tag.attributes["class"]?.lowercased() ?? ""
                    if classes.contains("reply_wrap") || classes.contains("quote") {
                        quoteDivDepths.append(divDepth)
                    }
                }
            case "img":
                guard !tag.isClosing, quoteDivDepths.isEmpty, blockquoteDepth == 0 else { continue }
                guard let urlString = imageSource(in: tag.attributes), let url = resolveURL(urlString) else { continue }
                guard seen.insert(url.absoluteString).inserted else { continue }
                urls.append(url)
            default:
                continue
            }
        }
        return urls
    }

    /// The URL an `<img>` should show: Discuz keeps the full picture in `file` /
    /// `zoomfile` and only a thumbnail (or a loading placeholder) in `src`.
    fileprivate static func imageSource(in attributes: [String: String]) -> String? {
        let candidate = attributes["file"]
            ?? attributes["zoomfile"]
            ?? attributes["data-src"]
            ?? attributes["data-original"]
            ?? attributes["src"]
            ?? ""
        let decoded = decodeEntities(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decoded.isEmpty, !isPlaceholderImage(decoded) else { return nil }
        return decoded
    }

    fileprivate static func isPlaceholderImage(_ raw: String) -> Bool {
        raw.hasPrefix("static/image/common/none")
            || raw.contains("/common/loading.gif")
            || raw.contains("/common/none.gif")
    }

    /// One tag at a time, sharing the tokenizer rules with the body builder: a
    /// bare `<` in prose is text, not the start of a tag.
    fileprivate struct Tag {
        let name: String
        let attributes: [String: String]
        let isClosing: Bool
    }

    fileprivate static func tags(in html: String) -> [Tag] {
        var result: [Tag] = []
        var index = html.startIndex
        while let tagStart = html[index...].firstIndex(of: "<") {
            let afterBracket = html.index(after: tagStart)
            guard afterBracket < html.endIndex else { break }
            let follower = html[afterBracket]
            guard follower == "/" || follower == "!" || follower == "?" || follower.isLetter else {
                index = afterBracket
                continue
            }
            guard let tagEnd = html[tagStart...].firstIndex(of: ">") else { break }
            let body = html[html.index(after: tagStart)..<tagEnd]
            index = html.index(after: tagEnd)

            var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let isClosing = text.hasPrefix("/")
            if isClosing { text.removeFirst() }
            if text.hasSuffix("/") { text.removeLast() }
            let pieces = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard let name = pieces.first?.lowercased(), !name.isEmpty else { continue }
            let attributes = pieces.count > 1 ? parseAttributes(String(pieces[1])) : [:]
            result.append(Tag(name: name, attributes: attributes, isClosing: isClosing))
        }
        return result
    }

    // MARK: - Text attributes

    /// Quoted text drops one type step (15pt body → 13pt, `.footnote`) so the
    /// card is a layer rather than a second reply.
    fileprivate static let quoteTextScale: CGFloat = 13.0 / 15.0

    static func fontSize(base: CGFloat) -> CGFloat {
        base * quoteTextScale
    }

    fileprivate static func apply(_ style: Style, to string: inout AttributedString, scale: CGFloat = 1) {
        if style.quoteDepth > 0 {
            // Quoted text is one size step down, whatever inline formatting the
            // original author used, and larger `font` sizes are clamped so a
            // quote cannot outshout the reply around it. The colour is left to
            // the card (QuoteStyle.body): it owns the fill the text sits on, so
            // it is the only place that can hold the contrast floor.
            var font = Font.system(size: fontSize(base: min(style.size ?? 15 * scale, 15 * scale)))
            if style.bold { font = font.bold() }
            if style.italic { font = font.italic() }
            string.font = font
            if let link = style.link {
                string.link = link
                string.foregroundColor = .accentColor
                string.underlineStyle = .single
            } else if style.underline {
                string.underlineStyle = .single
            }
            return
        }
        if style.bold || style.italic || style.size != nil {
            var font = Font.system(size: (style.size ?? 17) * scale)
            if style.bold { font = font.bold() }
            if style.italic { font = font.italic() }
            string.font = font
        }
        if let link = style.link {
            string.link = link
            string.foregroundColor = .accentColor
            string.underlineStyle = .single
        }
        if let color = style.color {
            string.foregroundColor = color
        }
        if style.underline {
            string.underlineStyle = .single
        }
    }

    // MARK: - Tag helpers

    fileprivate static func parseAttributes(_ source: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = "([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for match in regex.matches(in: source, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
            let name = source[nameRange].lowercased()
            for group in 2...4 {
                if let valueRange = Range(match.range(at: group), in: source) {
                    result[name] = String(source[valueRange])
                    break
                }
            }
        }
        return result
    }

    fileprivate static func cssColor(in style: String) -> String? {
        let pattern = "color\\s*:\\s*([#a-zA-Z0-9(),.% ]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(style.startIndex..<style.endIndex, in: style)
        guard let match = regex.firstMatch(in: style, range: range),
              let valueRange = Range(match.range(at: 1), in: style) else { return nil }
        return String(style[valueRange]).trimmingCharacters(in: .whitespaces)
    }

    static func fontPointSize(for discuzSize: Int) -> CGFloat {
        switch discuzSize {
        case 1: return 12
        case 2: return 14
        case 3: return 17
        case 4: return 20
        case 5: return 24
        case 6: return 30
        default: return 36
        }
    }

    /// Drops the whitespace and line breaks Discuz leaves at the edges of a
    /// block, so a quote does not start with a blank line.
    fileprivate static func trimmingEdges(_ string: AttributedString) -> AttributedString {
        var copy = string
        while let first = copy.characters.first, first == "\n" || first == " " {
            copy.removeSubrange(copy.startIndex..<copy.index(copy.startIndex, offsetByCharacters: 1))
        }
        while let last = copy.characters.last, last == "\n" || last == " " {
            copy.removeSubrange(copy.index(copy.endIndex, offsetByCharacters: -1)..<copy.endIndex)
        }
        return copy
    }

    fileprivate static func resolveURL(_ raw: String) -> URL? {
        let value = raw.hasPrefix("//") ? "https:" + raw : raw
        if value.hasPrefix("http") {
            return URL(string: value)
        }
        return URL(string: value, relativeTo: APIClient.baseURL)?.absoluteURL
    }

    fileprivate static func isSmiley(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/smiley/") || path.contains("/smilies/")
    }

    /// Collapses the `<br /><br /><br />&nbsp;` noise Discuz leaves behind.
    fileprivate static func normalize(_ html: String) -> String {
        var result = html
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(
            of: "(?i)(?:<br\\s*/?>\\s*){3,}",
            with: "<br /><br />",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?i)<br\\s*/?>[ \\t]*(?:<br\\s*/?>[ \\t]*)+",
            with: "<br /><br />",
            options: .regularExpression
        )
        return result
    }

    static func decodeEntities(_ input: String) -> String {
        // Discuz sometimes double-encodes entities ("&amp;amp;"), so run twice.
        var result = decodeEntitiesOnce(input)
        if result.contains("&") {
            result = decodeEntitiesOnce(result)
        }
        return result
    }

    private static func decodeEntitiesOnce(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var output = input
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&ldquo;": "“",
            "&rdquo;": "”", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"
        ]
        for (key, value) in named {
            output = output.replacingOccurrences(of: key, with: value)
        }
        guard output.contains("&#") else { return output }
        let pattern = "&#(x?)([0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return output }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: output),
                  let flagRange = Range(match.range(at: 1), in: output),
                  let numberRange = Range(match.range(at: 2), in: output) else { continue }
            let isHex = !output[flagRange].isEmpty
            let digits = String(output[numberRange])
            if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                output.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
        }
        return output
    }
}

/// Tokenizes a Discuz post body and accumulates `PostNode`s.
private struct PostBuilder {
    private let html: String
    private let scale: CGFloat
    private var index: String.Index
    private var nodes: [PostNode] = []
    private var text = AttributedString()
    private var pendingNewlines = 0
    private var stack: [(tag: String, style: HTMLParser.Style)] = [("root", HTMLParser.Style())]
    private var skipping: String?
    private var atLineStart = true
    private var quoteFrames: [QuoteFrame] = []
    /// One entry per open quote tag: whether that level got a card of its own
    /// (levels past `PostNode.Quote.maxDepth` are flattened into the parent).
    private var quoteLevels: [Bool] = []
    private var divDepth = 0
    private var quoteDivDepths: [Int] = []

    /// A quote being collected: its text, the cards already completed inside it,
    /// and the header/floor Discuz shipped with it.
    private struct QuoteFrame {
        var body: [PostNode] = []
        var text = AttributedString()
        var header: String?
        var pid: String?
    }

    init(html: String, scale: CGFloat = 1) {
        self.html = html
        self.scale = scale
        index = html.startIndex
    }

    private var currentStyle: HTMLParser.Style { stack.last?.style ?? HTMLParser.Style() }

    mutating func run() -> [PostNode] {
        while index < html.endIndex {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                append(HTMLParser.decodeEntities(String(html[index...])))
                break
            }
            if tagStart > index {
                append(HTMLParser.decodeEntities(String(html[index..<tagStart])))
            }
            let afterBracket = html.index(after: tagStart)
            guard afterBracket < html.endIndex else {
                index = afterBracket
                append("<")
                break
            }
            // A bare "<" is ordinary prose on a tech forum ("a < b", "价格<100").
            // Treating it as a tag would eat everything up to the next ">".
            let follower = html[afterBracket]
            guard follower == "/" || follower == "!" || follower == "?" || follower.isLetter else {
                index = afterBracket
                append("<")
                continue
            }
            guard let tagEnd = html[tagStart...].firstIndex(of: ">") else { break }
            let rawTag = String(html[html.index(after: tagStart)..<tagEnd])
            index = html.index(after: tagEnd)
            handleTag(rawTag)
        }
        if !quoteLevels.isEmpty { closeDanglingQuotes() }
        flush()
        return nodes
    }

    // MARK: - Tokens

    private mutating func handleTag(_ rawTag: String) {
        var body = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = body.hasPrefix("/")
        if isClosing { body.removeFirst() }
        let selfClosing = body.hasSuffix("/")
        if selfClosing { body.removeLast() }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        let pieces = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let name = pieces.first?.lowercased() ?? ""
        let attributes = pieces.count > 1 ? HTMLParser.parseAttributes(String(pieces[1])) : [:]

        if let skipTag = skipping {
            if isClosing && name == skipTag { skipping = nil }
            return
        }

        switch name {
        case "script", "style":
            if !isClosing {
                skipping = name
                skipBody(of: name)
            }
        case "br":
            append("\n")
        case "p", "div", "tr", "li", "blockquote":
            handleBlock(name, attributes: attributes, isClosing: isClosing, selfClosing: selfClosing)
        case "img":
            if !isClosing { appendImage(attributes) }
        default:
            handleInline(name, attributes: attributes, isClosing: isClosing)
        }
    }

    /// Jumps to the closing tag: a script body may contain "<", which the tag
    /// scanner would otherwise mistake for markup and swallow the rest of the post.
    private mutating func skipBody(of name: String) {
        guard let close = html.range(of: "</" + name, options: .caseInsensitive, range: index..<html.endIndex) else {
            index = html.endIndex
            return
        }
        index = close.lowerBound
    }

    /// A block boundary. Unlike `<br>` these do not stack: "</p><p>" is one line
    /// break, not a blank line.
    private mutating func blockBreak() {
        pendingNewlines = max(pendingNewlines, 1)
        atLineStart = true
    }

    private mutating func handleBlock(
        _ name: String,
        attributes: [String: String],
        isClosing: Bool,
        selfClosing: Bool
    ) {
        switch name {
        case "blockquote":
            if isClosing { closeQuote() } else { openQuote() }
        case "div":
            handleDiv(attributes: attributes, isClosing: isClosing, selfClosing: selfClosing)
        default:
            if isClosing || !selfClosing { blockBreak() }
        }
    }

    /// Discuz wraps quotes in `<div class="reply_wrap">`; without this the quoted
    /// text is indistinguishable from the reply. The closing `</div>` carries no
    /// attributes, so the open containers are tracked by nesting depth.
    private mutating func handleDiv(attributes: [String: String], isClosing: Bool, selfClosing: Bool) {
        let classes = attributes["class"]?.lowercased() ?? ""
        let isQuote = classes.contains("reply_wrap") || classes.contains("quote")

        if isClosing {
            if quoteDivDepths.last == divDepth {
                quoteDivDepths.removeLast()
                closeQuote()
            } else {
                blockBreak()
            }
            divDepth = max(0, divDepth - 1)
            return
        }
        if selfClosing { return }

        divDepth += 1
        if isQuote {
            quoteDivDepths.append(divDepth)
            openQuote()
        } else {
            blockBreak()
        }
    }

    private mutating func handleInline(_ name: String, attributes: [String: String], isClosing: Bool) {
        switch name {
        case "strong", "b":
            update(tag: "strong", isClosing: isClosing) { $0.bold = true }
        case "em", "i":
            update(tag: "em", isClosing: isClosing) { $0.italic = true }
        case "u", "ins":
            update(tag: "u", isClosing: isClosing) { $0.underline = true }
        case "font":
            update(tag: "font", isClosing: isClosing) { style in
                if let hex = attributes["color"], let color = Color(hex: hex) {
                    style.color = color
                }
                if let size = attributes["size"], let value = Int(size) {
                    style.size = HTMLParser.fontPointSize(for: value)
                }
            }
        case "span":
            update(tag: "span", isClosing: isClosing) { style in
                guard let value = attributes["style"],
                      let hex = HTMLParser.cssColor(in: value),
                      let color = Color(hex: hex) else { return }
                style.color = color
            }
        case "a":
            // The link Discuz wraps its quote header in carries the floor being
            // quoted. Only the header counts: a link further down is the quoted
            // post talking about some other floor.
            if !isClosing, let href = attributes["href"],
               let pid = HTMLParser.pidInFindPost(HTMLParser.decodeEntities(href)),
               isInQuoteHeader {
                quoteFrames[quoteFrames.count - 1].pid = pid
            }
            update(tag: "a", isClosing: isClosing) { style in
                guard let href = attributes["href"], let url = HTMLParser.resolveURL(href) else { return }
                style.link = url
            }
        default:
            break
        }
    }

    // MARK: - Text

    private mutating func append(_ raw: String) {
        guard skipping == nil, !raw.isEmpty else { return }
        let style = currentStyle
        for character in raw {
            if character == "\n" {
                pendingNewlines += 1
                atLineStart = true
                continue
            }
            if character == " " || character == "\t" || character == "\u{00A0}" {
                if atLineStart { continue }
                if pendingNewlines > 0 { flushPendingNewlines(style) }
                var space = AttributedString(" ")
                HTMLParser.apply(style, to: &space, scale: scale)
                emit(space)
                continue
            }
            if pendingNewlines > 0 { flushPendingNewlines(style) }
            var chunk = AttributedString(String(character))
            HTMLParser.apply(style, to: &chunk, scale: scale)
            emit(chunk)
            atLineStart = false
        }
    }

    private mutating func flushPendingNewlines(_ style: HTMLParser.Style) {
        let count = min(pendingNewlines, 2)
        var newlines = AttributedString(String(repeating: "\n", count: count))
        HTMLParser.apply(style, to: &newlines, scale: scale)
        emit(newlines)
        pendingNewlines = 0
    }

    private mutating func emit(_ string: AttributedString) {
        if quoteFrames.isEmpty {
            text += string
        } else {
            quoteFrames[quoteFrames.count - 1].text += string
        }
    }

    /// True while the innermost quote has not drawn anything but its header yet.
    private var isInQuoteHeader: Bool {
        guard let frame = quoteFrames.last else { return false }
        return frame.body.isEmpty && frame.text.characters.isEmpty
    }

    private mutating func appendNode(_ node: PostNode) {
        if quoteFrames.isEmpty {
            nodes.append(node)
        } else {
            quoteFrames[quoteFrames.count - 1].body.append(node)
        }
    }

    private mutating func flush() {
        // Text is buffered twice: once for the reply, once for the quote being
        // collected, so whichever buffer is active is the one that lands.
        var pending: AttributedString
        if quoteFrames.isEmpty {
            pending = text
            text = AttributedString()
        } else {
            pending = quoteFrames[quoteFrames.count - 1].text
            quoteFrames[quoteFrames.count - 1].text = AttributedString()
        }
        pendingNewlines = 0
        let copy = HTMLParser.trimmingEdges(pending)
        guard !copy.characters.isEmpty else { return }
        appendNode(.text(copy))
    }

    // MARK: - Quotes

    private mutating func openQuote() {
        flush()
        var style = currentStyle
        style.quoteDepth += 1
        style.color = .secondary
        stack.append(("quote", style))

        let drawsOwnCard = quoteLevels.count < PostNode.Quote.maxDepth
        quoteLevels.append(drawsOwnCard)
        if drawsOwnCard { quoteFrames.append(QuoteFrame()) }
    }

    private mutating func closeQuote() {
        popTag("quote")
        guard let drawsOwnCard = quoteLevels.popLast() else { return }
        if drawsOwnCard { closeFrame() }
        if quoteLevels.isEmpty {
            // Breaks inside the quote belong to the quote; they must not prepend a
            // blank line to the reply text that follows.
            pendingNewlines = 0
            atLineStart = true
        }
    }

    /// Ends the innermost card and hands it to whatever contains it.
    private mutating func closeFrame() {
        guard !quoteFrames.isEmpty else { return }
        flush()
        var frame = quoteFrames.removeLast()
        splitHeader(&frame)
        guard !frame.body.isEmpty else { return }
        appendNode(.quote(PostNode.Quote(header: frame.header, body: frame.body, pid: frame.pid)))
    }

    /// Discuz puts "作者 发表于 时间" on the quote's first line, inside the link
    /// that points at the floor. Pulling it out lets the card draw it as a
    /// caption instead of as a paragraph of quoted prose.
    private func splitHeader(_ frame: inout QuoteFrame) {
        guard frame.header == nil,
              case .text(let first)? = frame.body.first,
              let newline = first.characters.firstIndex(of: "\n") else { return }
        let line = String(first.characters[first.startIndex..<newline])
        guard PostNode.Quote.looksLikeHeader(line) else { return }

        var rest = first
        rest.removeSubrange(rest.startIndex..<rest.index(afterCharacter: newline))
        rest = HTMLParser.trimmingEdges(rest)

        // A quote that is nothing but a header would render as an empty card, so
        // it stays whole text instead.
        guard !rest.characters.isEmpty || frame.body.count > 1 else { return }
        frame.header = line.trimmingCharacters(in: .whitespaces)
        if rest.characters.isEmpty {
            frame.body.removeFirst()
        } else {
            frame.body[0] = .text(rest)
        }
    }

    /// Closes whatever quote tags were left open by the end of the post: an
    /// unclosed `reply_wrap` div is common enough that the quote must survive it.
    private mutating func closeDanglingQuotes() {
        while let drawsOwnCard = quoteLevels.popLast() {
            if drawsOwnCard { closeFrame() }
        }
    }

    // MARK: - Images

    private mutating func appendImage(_ attributes: [String: String]) {
        // Images inside a quote are dropped: the quote renders as one text card,
        // and the original picture is one tap away.
        guard quoteFrames.isEmpty else { return }
        guard let decoded = HTMLParser.imageSource(in: attributes),
              let url = HTMLParser.resolveURL(decoded) else { return }
        flush()
        appendNode(.image(url, isSmiley: HTMLParser.isSmiley(url)))
    }

    // MARK: - Style stack

    private mutating func update(tag: String, isClosing: Bool, _ mutate: (inout HTMLParser.Style) -> Void) {
        if isClosing {
            popTag(tag)
        } else {
            var style = currentStyle
            mutate(&style)
            stack.append((tag, style))
        }
    }

    private mutating func popTag(_ tag: String) {
        guard stack.count > 1 else { return }
        if let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 {
            stack.removeSubrange(index...)
        } else {
            stack.removeLast()
        }
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 3,
              let number = UInt32(value, radix: 16) else { return nil }
        let red, green, blue: Double
        if value.count == 3 {
            red = Double((number >> 8) & 0xF) / 15
            green = Double((number >> 4) & 0xF) / 15
            blue = Double(number & 0xF) / 15
        } else {
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
        }
        self.init(red: red, green: green, blue: blue)
    }
}
