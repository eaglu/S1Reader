import Foundation
import Observation

/// Someone the reader never wants to see again.
struct BlockedAuthor: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

/// Locally blocked authors.
///
/// S1 has no usable per-user block list from the app, so this stays on device:
/// a set of author ids in `UserDefaults`, applied before a floor or a thread row
/// is drawn. Blocking never hides a thread's first post — a thread the reader
/// opened on purpose keeps its head, the replies below it just lose one voice.
@MainActor
@Observable
final class BlockedAuthorsStore {
    static let shared = BlockedAuthorsStore()

    private static let key = "{{NAME_8x3kq2}}"

    /// Author id → the name they were blocked under, so the manage screen can
    /// say who is on the list instead of showing bare ids.
    private(set) var authors: [String: String]

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authors = Self.load(from: defaults)
    }

    var entries: [BlockedAuthor] {
        authors
            .map { BlockedAuthor(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var count: Int { authors.count }

    /// Guest posts ("uid 0") cannot be blocked: the next guest would be hidden
    /// with them.
    func canBlock(_ authorID: String) -> Bool {
        !authorID.isEmpty && authorID != "0"
    }

    func isBlocked(_ authorID: String) -> Bool {
        guard canBlock(authorID) else { return false }
        return authors[authorID] != nil
    }

    func block(_ authorID: String, name: String) {
        guard canBlock(authorID) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        authors[authorID] = trimmed.isEmpty ? "（未知作者）" : trimmed
        save()
    }

    func unblock(_ authorID: String) {
        guard authors[authorID] != nil else { return }
        authors[authorID] = nil
        save()
    }

    func setBlocked(_ blocked: Bool, authorID: String, name: String) {
        if blocked {
            block(authorID, name: name)
        } else {
            unblock(authorID)
        }
    }

    private func save() {
        defaults.set(authors, forKey: Self.key)
    }

    private static func load(from defaults: UserDefaults) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
