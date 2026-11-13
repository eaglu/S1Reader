import Foundation
import SwiftUI
import XCTest
@testable import S1Reader

enum Fixture {
    static func parse(_ html: String, scale: CGFloat = 1) -> [PostNode] {
        HTMLParser.parse(html, scale: scale)
    }

    static func plainText(_ html: String) -> String {
        HTMLParser.plainText(html)
    }
}

extension PostNode {
    var text: String? {
        if case .text(let value) = self { return String(value.characters) }
        return nil
    }

    var quote: (text: String, pid: String?)? {
        if case .quote(let value) = self { return (Self.plainText(value.body), value.pid) }
        return nil
    }

    /// The caption row: "作者 发表于 时间", when the quote shipped one.
    var quoteHeader: String? {
        if case .quote(let value) = self { return value.header }
        return nil
    }

    /// How many quote cards the node list would draw: a nested quote counts.
    var quoteDepth: Int {
        switch self {
        case .quote(let value):
            return 1 + (value.body.map(\.quoteDepth).max() ?? 0)
        case .text, .image:
            return 0
        }
    }

    static func plainText(_ nodes: [PostNode]) -> String {
        nodes.map { node in
            switch node {
            case .text(let value): return String(value.characters)
            case .quote(let value): return Self.plainText(value.body)
            case .image: return ""
            }
        }
        .joined()
    }

    var image: (url: URL, isSmiley: Bool)? {
        if case .image(let url, let isSmiley) = self { return (url, isSmiley) }
        return nil
    }

    var attributed: AttributedString? {
        switch self {
        case .text(let value): return value
        case .quote(let value):
            for node in value.body {
                if case .text(let text) = node { return text }
            }
            return nil
        case .image: return nil
        }
    }
}

extension AttributedString {
    /// Plain text carries no font attribute at all, so a present font means the
    /// author (or the quote wrapper) asked for one.
    var hasFont: Bool { runs.contains { $0.font != nil } }
    var isSecondary: Bool { runs.contains { $0.foregroundColor == Color.secondary } }
    var hasUnderline: Bool { runs.contains { $0.underlineStyle != nil } }
    var hasColor: Bool { runs.contains { $0.foregroundColor != nil } }
    var mostCommonLink: URL? {
        runs.compactMap(\.link).first
    }
}

/// A UserDefaults suite of its own, so a test never touches the app's real
/// settings or the settings of another test.
final class TemporaryDefaults {
    let suiteName = "S1ReaderTests." + UUID().uuidString
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    func destroy() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
