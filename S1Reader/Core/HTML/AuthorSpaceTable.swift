import Foundation

/// The table walk behind `AuthorSpaceParser`: a tolerant HTML tokenizer and the
/// `<tr>/<td>` accumulation Discuz's space pages are built from.
///
/// Kept apart from the public parser so the shape of a page (cells, links,
/// counters) and the meaning drawn from it (a thread, a reply, a page count)
/// can be read independently.
enum AuthorSpaceTable {

    struct Link {
        var href: String
        var text: String
    }

    struct Cell {
        var isHeader = false
        var classes = ""
        var isSpanning = false
        var text = ""
        var links: [Link] = []
        var cites: [String] = []
        var ems: [String] = []
    }

    struct Row {
        var cells: [Cell]
    }

    // MARK: - Rows

    static func rows(in html: String) -> [Row] {
        var result: [Row] = []
        var cells: [Cell]?
        var cellIndex: Int?
        var linkHref: String?
        var emDepth = 0
        var citeDepth = 0

        func appendText(_ raw: String) {
            let text = HTMLParser.decodeEntities(raw)
            guard !text.isEmpty, var open = cells, let index = cellIndex, open.indices.contains(index) else { return }
            open[index].text += text
            if let href = linkHref,
               let last = open[index].links.indices.last,
               open[index].links[last].href == href {
                open[index].links[last].text += text
            }
            if emDepth > 0, !open[index].ems.isEmpty {
                open[index].ems[open[index].ems.count - 1] += text
            }
            if citeDepth > 0, !open[index].cites.isEmpty {
                open[index].cites[open[index].cites.count - 1] += text
            }
            cells = open
        }

        for token in tokenize(html) {
            switch token {
            case .text(let value):
                appendText(value)
            case .tag(let name, let attributes, let isClosing):
                switch name {
                case "tr":
                    if isClosing {
                        if let open = cells { result.append(Row(cells: open)) }
                        cells = nil
                        cellIndex = nil
                        linkHref = nil
                        emDepth = 0
                        citeDepth = 0
                    } else {
                        cells = []
                    }
                case "td", "th":
                    guard var open = cells else { continue }
                    if isClosing {
                        cellIndex = nil
                    } else {
                        open.append(Cell(
                            isHeader: name == "th",
                            classes: attributes["class"] ?? "",
                            isSpanning: attributes["colspan"] != nil
                        ))
                        cells = open
                        cellIndex = open.count - 1
                    }
                case "a":
                    guard var open = cells, let index = cellIndex, open.indices.contains(index) else {
                        linkHref = nil
                        continue
                    }
                    if isClosing {
                        linkHref = nil
                    } else {
                        let href = HTMLParser.decodeEntities(attributes["href"] ?? "")
                        open[index].links.append(Link(href: href, text: ""))
                        cells = open
                        linkHref = href
                    }
                case "em":
                    emDepth = max(0, emDepth + (isClosing ? -1 : 1))
                    if !isClosing, var open = cells, let index = cellIndex, open.indices.contains(index) {
                        open[index].ems.append("")
                        cells = open
                    }
                case "br":
                    // A cell's message is a paragraph: a break is a space in the
                    // one-line snippet the card shows.
                    if !isClosing { appendText(" ") }
                case "cite":
                    citeDepth = max(0, citeDepth + (isClosing ? -1 : 1))
                    if !isClosing, var open = cells, let index = cellIndex, open.indices.contains(index) {
                        open[index].cites.append("")
                        cells = open
                    }
                default:
                    continue
                }
            }
        }
        return result
    }

    /// A thread table row as the list wants it, or nil for a header row, a
    /// reply's message row, or anything else without a thread link.
    static func threadItem(from row: Row) -> AuthorSpaceParser.ThreadItem? {
        let hasHeaderCell = row.cells.contains(where: \.isHeader)
        let hasForumLink = row.cells.contains { cell in
            cell.links.contains { $0.href.contains("forumdisplay") }
        }
        // A reply's message row is one spanning cell; a real thread row has the
        // subject header plus the forum it was posted in.
        guard hasHeaderCell || (row.cells.count >= 4 && hasForumLink) else { return nil }

        let candidates = row.cells.enumerated().flatMap { index, cell in
            cell.links
                .filter { isThreadLink($0.href) && tid(in: $0.href) != nil }
                .map { (index: index, cell: cell, link: $0) }
        }
        // Prefer the subject header and a link that actually says something;
        // the icon cell links to the same thread with no text at all.
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.cell.isHeader != rhs.cell.isHeader { return lhs.cell.isHeader }
            let lhsEmpty = cleaned(lhs.link.text).isEmpty
            let rhsEmpty = cleaned(rhs.link.text).isEmpty
            if lhsEmpty != rhsEmpty { return !lhsEmpty }
            return lhs.index < rhs.index
        }
        guard let pick = ordered.first,
              let tid = tid(in: pick.link.href) else { return nil }

        let subject = cleaned(pick.link.text)
        let forumName = row.cells
            .flatMap(\.links)
            .first { $0.href.contains("forumdisplay") }
            .map { cleaned($0.text) } ?? ""

        var replies = 0
        var views = 0
        if let counters = row.cells.first(where: { $0.classes.lowercased().contains("num") }) {
            (replies, views) = counts(in: counters)
        }

        let byCell = row.cells.first { $0.classes.lowercased().contains("by") }
        let datedCell = row.cells.first { cell in
            let classes = cell.classes.lowercased()
            return !classes.contains("by") && !classes.contains("num") && !cell.ems.isEmpty
        }

        return AuthorSpaceParser.ThreadItem(
            tid: tid,
            subject: subject.isEmpty ? "（无标题）" : subject,
            forumName: forumName,
            replies: replies,
            views: views,
            lastPoster: cleaned(byCell?.cites.first ?? ""),
            lastPost: cleaned(byCell?.ems.first ?? ""),
            dateline: cleaned(datedCell?.ems.first ?? "")
        )
    }

    private static func counts(in cell: Cell) -> (replies: Int, views: Int) {
        let replies = cell.links.first
            .flatMap { integer($0.text) }
            ?? integer(cell.text) ?? 0
        let views = cell.ems.first
            .flatMap { integer($0) }
            ?? numbers(in: cell.text).dropFirst().first
            ?? 0
        return (replies, views)
    }

    // MARK: - Tokenizer

    private enum Token {
        case tag(name: String, attributes: [String: String], isClosing: Bool)
        case text(String)
    }

    /// A tag scanner that shares `HTMLParser`'s rule for what a tag is: a bare
    /// "<" in prose is text, not markup. Script and style bodies are skipped
    /// because their code is full of angle brackets.
    private static func tokenize(_ html: String) -> [Token] {
        var result: [Token] = []
        var index = html.startIndex

        while index < html.endIndex {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                result.append(.text(String(html[index...])))
                break
            }
            if tagStart > index {
                result.append(.text(String(html[index..<tagStart])))
            }
            let afterBracket = html.index(after: tagStart)
            guard afterBracket < html.endIndex else { break }
            let follower = html[afterBracket]

            if follower == "!" {
                if html[afterBracket...].hasPrefix("!--"),
                   let end = html[afterBracket...].range(of: "-->") {
                    index = end.upperBound
                } else if let end = html[tagStart...].firstIndex(of: ">") {
                    index = html.index(after: end)
                } else {
                    break
                }
                continue
            }
            if follower == "?" {
                if let end = html[tagStart...].firstIndex(of: ">") {
                    index = html.index(after: end)
                } else {
                    break
                }
                continue
            }
            guard follower == "/" || follower.isLetter else {
                result.append(.text("<"))
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

            if !isClosing, name == "script" || name == "style" {
                if let close = html[index...].range(of: "</" + name, options: .caseInsensitive) {
                    index = close.lowerBound
                } else {
                    index = html.endIndex
                }
                continue
            }
            result.append(.tag(name: name, attributes: attributes, isClosing: isClosing))
        }
        return result
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

    // MARK: - Helpers

    static func isThreadLink(_ href: String) -> Bool {
        href.contains("viewthread") || href.contains("findpost")
    }

    static func tid(in href: String) -> String? {
        digits(after: "?tid=", in: href)
            ?? digits(after: "&tid=", in: href)
            ?? digits(after: "?ptid=", in: href)
            ?? digits(after: "&ptid=", in: href)
            ?? digits(after: "tid=", in: href)
            ?? digits(after: "ptid=", in: href)
    }

    static func pid(in href: String) -> String? {
        digits(after: "?pid=", in: href)
            ?? digits(after: "&pid=", in: href)
            ?? digits(after: "pid=", in: href)
    }

    /// Digits that directly follow `marker`, so `?tid=1` and `&amp;tid=1` both
    /// work and `ptid=` cannot be mistaken for `tid=`.
    static func digits(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let value = text[range.upperBound...].prefix { $0.isNumber }
        return value.isEmpty ? nil : String(value)
    }

    static func position(in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "#\\s*(\\d+)") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let digits = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[digits])
    }

    private static func integer(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func numbers(in text: String) -> [Int] {
        var values: [Int] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                values.append(Int(current) ?? 0)
                current = ""
            }
        }
        if !current.isEmpty { values.append(Int(current) ?? 0) }
        return values
    }

    static func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
