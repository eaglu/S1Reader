import SwiftUI

/// A rendered piece of a Discuz! post body.
enum PostNode: Hashable {
    case text(AttributedString)
    case image(URL, isSmiley: Bool)
}

/// Converts the HTML fragment returned by the mobile API into renderable nodes.
/// It intentionally supports only the tag subset S1 actually produces:
/// br/p/div, font, strong/b, em/i, u, a, img, blockquote.
enum HTMLParser {
    private struct Style {
        var color: Color?
        var bold = false
        var italic = false
        var underline = false
        var size: CGFloat?
        var link: URL?
        var quoteDepth = 0
    }

    static func parse(_ html: String) -> [PostNode] {
        let html = normalize(html)
        var nodes: [PostNode] = []
        var text = AttributedString()
        var pendingNewlines = 0
        var stack: [(tag: String, style: Style)] = [("root", Style())]
        var skipping: String?
        var atLineStart = true
        var index = html.startIndex

        func currentStyle() -> Style { stack.last?.style ?? Style() }

        func append(_ raw: String) {
            guard skipping == nil, !raw.isEmpty else { return }
            let style = currentStyle()
            for character in raw {
                if character == "\n" {
                    pendingNewlines += 1
                    atLineStart = true
                    continue
                }
                if character == " " || character == "\t" || character == "\u{00A0}" {
                    if atLineStart { continue }
                    if pendingNewlines > 0 {
                        let count = min(pendingNewlines, 2)
                        var newlines = AttributedString(String(repeating: "\n", count: count))
                        apply(style, to: &newlines)
                        text += newlines
                        pendingNewlines = 0
                    }
                    var space = AttributedString(" ")
                    apply(style, to: &space)
                    text += space
                    continue
                }
                if pendingNewlines > 0 {
                    let count = min(pendingNewlines, 2)
                    var newlines = AttributedString(String(repeating: "\n", count: count))
                    apply(style, to: &newlines)
                    text += newlines
                    pendingNewlines = 0
                }
                var chunk = AttributedString(String(character))
                apply(style, to: &chunk)
                text += chunk
                atLineStart = false
            }
        }

        func flush() {
            var copy = text
            while let last = copy.characters.last, last == "\n" || last == " " {
                let end = copy.endIndex
                let start = copy.index(end, offsetByCharacters: -1)
                copy.removeSubrange(start..<end)
            }
            if !copy.characters.isEmpty {
                nodes.append(.text(copy))
            }
            text = AttributedString()
            pendingNewlines = 0
        }

        func appendImage(_ attributes: [String: String]) {
            let candidate = attributes["file"] ?? attributes["zoomfile"] ?? attributes["src"] ?? ""
            let decoded = decodeEntities(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decoded.isEmpty, !decoded.hasPrefix("static/image/common/none"),
                  let url = resolveURL(decoded) else { return }
            flush()
            nodes.append(.image(url, isSmiley: isSmiley(url)))
        }

        while index < html.endIndex {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                append(decodeEntities(String(html[index...])))
                break
            }
            if tagStart > index {
                append(decodeEntities(String(html[index..<tagStart])))
            }
            guard let tagEnd = html[tagStart...].firstIndex(of: ">") else { break }
            let rawTag = String(html[html.index(after: tagStart)..<tagEnd])
            index = html.index(after: tagEnd)

            var body = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
            let isClosing = body.hasPrefix("/")
            if isClosing { body.removeFirst() }
            let selfClosing = body.hasSuffix("/")
            if selfClosing { body.removeLast() }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)

            let pieces = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let name = pieces.first?.lowercased() ?? ""
            let attributes = pieces.count > 1 ? parseAttributes(String(pieces[1])) : [:]

            if let skipTag = skipping {
                if isClosing && name == skipTag { skipping = nil }
                continue
            }

            switch name {
            case "script", "style":
                if !isClosing { skipping = name }

            case "br":
                append("\n")

            case "p", "div", "tr", "li":
                if isClosing || !selfClosing { append("\n") }

            case "blockquote":
                if isClosing {
                    popTag("blockquote", from: &stack)
                    append("\n")
                } else {
                    append("\n")
                    var style = currentStyle()
                    style.quoteDepth += 1
                    style.color = .secondary
                    stack.append(("blockquote", style))
                }

            case "strong", "b":
                update(&stack, tag: "strong", isClosing: isClosing) { $0.bold = true }

            case "em", "i":
                update(&stack, tag: "em", isClosing: isClosing) { $0.italic = true }

            case "u", "ins":
                update(&stack, tag: "u", isClosing: isClosing) { $0.underline = true }

            case "font":
                update(&stack, tag: "font", isClosing: isClosing) { style in
                    if let hex = attributes["color"], let color = Color(hex: hex) {
                        style.color = color
                    }
                    if let size = attributes["size"], let value = Int(size) {
                        style.size = fontPointSize(for: value)
                    }
                }

            case "span":
                update(&stack, tag: "span", isClosing: isClosing) { style in
                    if let value = attributes["style"], let hex = cssColor(in: value), let color = Color(hex: hex) {
                        style.color = color
                    }
                }

            case "a":
                update(&stack, tag: "a", isClosing: isClosing) { style in
                    if let href = attributes["href"], let url = resolveURL(href) {
                        style.link = url
                    }
                }

            case "img":
                if !isClosing { appendImage(attributes) }

            default:
                break
            }
        }

        flush()
        return nodes
    }

    /// Non-smiley images referenced by a post, used for cache bookkeeping.
    static func imageURLs(in html: String) -> [URL] {
        parse(html).compactMap { node in
            if case .image(let url, let isSmiley) = node, !isSmiley { return url }
            return nil
        }
    }

    // MARK: - Helpers

    private static func apply(_ style: Style, to string: inout AttributedString) {
        if style.bold || style.italic || style.size != nil {
            var font = Font.system(size: style.size ?? 17)
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

    private static func update(
        _ stack: inout [(tag: String, style: Style)],
        tag: String,
        isClosing: Bool,
        _ mutate: (inout Style) -> Void
    ) {
        if isClosing {
            popTag(tag, from: &stack)
        } else {
            var style = stack.last?.style ?? Style()
            mutate(&style)
            stack.append((tag, style))
        }
    }

    private static func popTag(_ tag: String, from stack: inout [(tag: String, style: Style)]) {
        guard stack.count > 1 else { return }
        if let index = stack.lastIndex(where: { $0.tag == tag }), index > 0 {
            stack.removeSubrange(index...)
        } else {
            stack.removeLast()
        }
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
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

    private static func cssColor(in style: String) -> String? {
        let pattern = "color\\s*:\\s*([#a-zA-Z0-9(),.% ]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(style.startIndex..<style.endIndex, in: style)
        guard let match = regex.firstMatch(in: style, range: range),
              let valueRange = Range(match.range(at: 1), in: style) else { return nil }
        return String(style[valueRange]).trimmingCharacters(in: .whitespaces)
    }

    private static func fontPointSize(for discuzSize: Int) -> CGFloat {
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

    private static func resolveURL(_ raw: String) -> URL? {
        let value = raw.hasPrefix("//") ? "https:" + raw : raw
        if value.hasPrefix("http") {
            return URL(string: value)
        }
        return URL(string: value, relativeTo: APIClient.baseURL)?.absoluteURL
    }

    private static func isSmiley(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.contains("/smiley/") || path.contains("/smilies/")
    }

    /// Collapses the `<br /><br /><br />&nbsp;` noise Discuz leaves behind.
    private static func normalize(_ html: String) -> String {
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
