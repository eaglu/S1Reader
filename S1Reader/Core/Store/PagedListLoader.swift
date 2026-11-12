import Foundation
import Observation

/// Page-by-page loading shared by the list screens.
///
/// Every paged screen used to spell out the same `isLoading` / `errorMessage` /
/// `page` / `hasMore` + `defer` skeleton, and each copy treated a failed page
/// slightly differently. This is that state machine once:
///
/// * only one page is in flight at a time;
/// * rows that are already in the list are dropped, so a page the server
///   replays cannot double up;
/// * a failed page leaves the cursor where it was, so the next pull retries the
///   same page instead of ending the list on one hiccup.
///
/// `Context` is whatever the API returned alongside the rows (per-page size,
/// totals, the thread header), handed back to the screen through `onPageLoaded`
/// so the loader itself stays ignorant of the shape of each endpoint.
@MainActor
@Observable
final class PagedListLoader<Item: Identifiable, Context> {
    /// One page as the API returned it.
    struct Page {
        var items: [Item]
        /// Whether another page exists, when the caller knows (a thread can say
        /// "page 3 of 400"). `nil` falls back to "the page came back empty",
        /// which is what the account lists rely on.
        var hasMore: Bool?
        var context: Context?

        init(items: [Item], hasMore: Bool? = nil, context: Context? = nil) {
            self.items = items
            self.hasMore = hasMore
            self.context = context
        }
    }

    /// Fetches one page. Callers close over the client they want, which is also
    /// how the tests page without a network.
    typealias Fetch = @MainActor (_ page: Int) async throws -> Page

    private(set) var items: [Item] = []
    /// Highest page that loaded; `loadMore` asks for `page + 1`.
    private(set) var page = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// True once a first page landed, so "empty" can be told apart from
    /// "not loaded yet".
    private(set) var didLoad = false
    /// Cleared when the API says there is nothing after the current page. A
    /// screen may narrow it further (the thread detail knows its page count).
    var hasMore = true

    private let fetch: Fetch

    /// Called after every successful load with the page number, the rows that
    /// were not in the list before, and the page's own context.
    var onPageLoaded: ((_ page: Int, _ newRows: [Item], _ context: Context?) -> Void)?

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    var hasLoadedOnce: Bool { didLoad }

    /// Loads the first page and replaces the rows.
    func reload() async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetch(1)
            items = result.items
            page = 1
            didLoad = true
            errorMessage = nil
            hasMore = result.hasMore ?? !result.items.isEmpty
            onPageLoaded?(1, result.items, result.context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Replaces the rows with `target` (a page the reader jumped to).
    func loadPage(_ target: Int) async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await fetch(target)
            items = result.items
            page = target
            didLoad = true
            errorMessage = nil
            hasMore = result.hasMore ?? !result.items.isEmpty
            onPageLoaded?(target, result.items, result.context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the page after the current one and appends what is new.
    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let next = page + 1
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetch(next)
            let fresh = merge(result.items, at: items.count)
            page = next
            errorMessage = nil
            hasMore = result.hasMore ?? !fresh.isEmpty
            onPageLoaded?(next, fresh, result.context)
        } catch {
            // Keep the cursor and `hasMore`: this page simply did not load, so
            // the next approach at the bottom retries it.
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the page above the current one and puts it in front of the list.
    /// Returns the rows that were added.
    @discardableResult
    func prepend(page target: Int) async -> [Item]? {
        guard !isLoading, !isLoadingMore else { return nil }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetch(target)
            let fresh = merge(result.items, at: 0)
            errorMessage = nil
            if let explicit = result.hasMore { hasMore = explicit }
            onPageLoaded?(target, fresh, result.context)
            return fresh
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Merges rows that arrived out of band (a poll for new replies) without
    /// moving the page cursor. Returns the rows that were new.
    @discardableResult
    func append(_ rows: [Item]) -> [Item] {
        merge(rows, at: items.count)
    }

    func clearError() { reportError(nil) }

    /// Sets or clears the message shown above/below the list.
    func reportError(_ message: String?) { errorMessage = message }

    /// Swaps the rows without touching the page cursor; used by optimistic
    /// edits (a favourite row that was just removed, and put back on failure).
    func replace(_ rows: [Item]) { items = rows }

    /// Drops rows that are already in the list and inserts the rest.
    private func merge(_ rows: [Item], at index: Int) -> [Item] {
        guard !rows.isEmpty else { return [] }
        let known = Set(items.map(\.id))
        let fresh = rows.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return [] }
        if index == items.count {
            items.append(contentsOf: fresh)
        } else {
            items.insert(contentsOf: fresh, at: index)
        }
        return fresh
    }
}
