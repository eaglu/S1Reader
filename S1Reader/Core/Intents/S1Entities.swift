import AppIntents
import CoreSpotlight
import Foundation

/// A board, as Siri and Shortcuts see it.
///
/// Everything here is deliberately offline: the entity is built from the
/// directory the app saved, so resolving a parameter never blocks on the
/// network.
struct ForumEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Board")
    static let defaultQuery = ForumEntityQuery()

    let fid: String
    let name: String
    let summary: String

    var id: String { fid }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: summary.isEmpty ? nil : "\(summary)"
        )
    }

    init(fid: String, name: String, summary: String = "") {
        self.fid = fid
        self.name = name
        self.summary = summary
    }

    init(record: ForumRecord) {
        self.init(fid: record.fid, name: record.name, summary: record.summary)
    }
}

/// A thread the reader has opened before.
struct ThreadEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Thread")
    static let defaultQuery = ThreadEntityQuery()

    let tid: String
    let subject: String
    let author: String
    let fid: String

    var id: String { tid }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(subject)",
            subtitle: author.isEmpty ? nil : "by \(author)"
        )
    }

    init(tid: String, subject: String, author: String = "", fid: String = "") {
        self.tid = tid
        self.subject = subject
        self.author = author
        self.fid = fid
    }

    init(thread: RecentThread) {
        self.init(tid: thread.tid, subject: thread.subject, author: thread.author, fid: thread.fid)
    }
}

/// Resolves boards by id (Shortcuts passing an entity along) and by words
/// (Siri matching what was said against the saved board index).
struct ForumEntityQuery: EntityStringQuery {
    var directory: ForumDirectory

    /// `EntityQuery` requires a no-argument initialiser; tests inject a store on
    /// its own defaults through the second one.
    init() {
        self.directory = .shared
    }

    init(directory: ForumDirectory) {
        self.directory = directory
    }

    func entities(for identifiers: [String]) async throws -> [ForumEntity] {
        identifiers.compactMap { directory.record(fid: $0) }.map(ForumEntity.init(record:))
    }

    func entities(matching string: String) async throws -> [ForumEntity] {
        directory.records(matching: string).map(ForumEntity.init(record:))
    }

    func suggestedEntities() async throws -> [ForumEntity] {
        directory.records.prefix(12).map(ForumEntity.init(record:))
    }
}

/// Resolves threads by id, by words from the title, and by "the last one".
struct ThreadEntityQuery: EntityStringQuery {
    var store: RecentThreadStore

    init() {
        self.store = .shared
    }

    init(store: RecentThreadStore) {
        self.store = store
    }

    func entities(for identifiers: [String]) async throws -> [ThreadEntity] {
        identifiers.compactMap { store.thread(tid: $0) }.map(ThreadEntity.init(thread:))
    }

    func entities(matching string: String) async throws -> [ThreadEntity] {
        store.threads(matching: string).map(ThreadEntity.init(thread:))
    }

    func suggestedEntities() async throws -> [ThreadEntity] {
        store.threads.prefix(12).map(ThreadEntity.init(thread:))
    }
}

// MARK: - Spotlight

// `IndexedEntity` and `indexAppEntities` are iOS 18 APIs and the app still runs
// on iOS 17, so the conformance is availability-gated rather than raising the
// app's floor. Everything below only ever runs behind the same check.
@available(iOS 18.0, *)
extension ForumEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.title = name
        if !summary.isEmpty { attributes.contentDescription = summary }
        return attributes
    }
}

@available(iOS 18.0, *)
extension ThreadEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.title = subject
        if !author.isEmpty { attributes.creator = author }
        return attributes
    }
}

/// Puts boards and threads into the Spotlight semantic index, which is what lets
/// Siri AI surface them later ("那个聊 X 的主题") without a schema.
///
/// A named index, not the default one: the default index is for prototyping and
/// is shared with everything else Spotlight holds for the app.
enum S1SpotlightIndex {
    static let name = "S1ReaderEntities"

    static func index(forums: [Forum]) {
        guard #available(iOS 18.0, *) else { return }
        let entities = ForumDirectory.records(from: forums).map(ForumEntity.init(record:))
        guard !entities.isEmpty else { return }
        Task {
            try? await CSSearchableIndex(name: name).indexAppEntities(entities)
        }
    }

    static func index(thread: RecentThread) {
        guard #available(iOS 18.0, *) else { return }
        let entity = ThreadEntity(thread: thread)
        Task {
            try? await CSSearchableIndex(name: name).indexAppEntities([entity])
        }
    }

    static func removeAll() {
        guard #available(iOS 18.0, *) else { return }
        Task {
            try? await CSSearchableIndex(name: name).deleteAllSearchableItems()
        }
    }
}
