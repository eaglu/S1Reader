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
        if case .quote(let value, let pid) = self { return (String(value.characters), pid) }
        return nil
    }

    var image: (url: URL, isSmiley: Bool)? {
        if case .image(let url, let isSmiley) = self { return (url, isSmiley) }
        return nil
    }

    var attributed: AttributedString? {
        switch self {
        case .text(let value), .quote(let value, _): return value
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
