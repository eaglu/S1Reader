import Foundation
import Observation

/// One thread: the page window that is in memory, the replies that arrived
/// since, and where the reader left off.
///
/// Paging itself lives in `PagedListLoader`; this adds the guest-fallback fetch,
/// the thread header numbers and the reading-position bookkeeping.
@MainActor
@Observable
final class ThreadDetailViewModel {
    let summary: ThreadSummary

    var title: String
    var totalPosts = 0
    var views = 0
    var perPage = 40
    /// True while the bottom of the list asks the server for new replies.
    var isCheckingNewReplies = false
    /// Result of the last bottom pull, shown under the last post.
    var lastCheckMessage: String?
    /// Set right after a successful reply so the list can scroll to the new post.
    var focusPid: String?
    /// Post to scroll to when reopening a thread that was read before.
    var resumePid: String?
    /// Lowest page currently in `posts`; above 1 the list can still scroll up.
    var firstLoadedPage = 1

    let pager: PagedListLoader<Post, ThreadPage>

    /// Posts that arrived in the most recent insert, so the list can give only
    /// those rows an entrance. Cleared shortly after.
    private(set) var freshPids: Set<String> = []
    private var freshToken = 0

    init(summary: ThreadSummary) {
        self.summary = summary
        title = summary.subject
        totalPosts = summary.replies + 1
        views = summary.views

        let tid = summary.tid
        pager = PagedListLoader { page in
            let result = try await ThreadPageLoader.fetch(tid: tid, page: page)
            return .init(items: result.posts, context: result)
        }
        pager.onPageLoaded = { [weak self] page, _, result in
            self?.absorb(page: page, result: result)
        }
    }

    // MARK: - State the views read

    var posts: [Post] { pager.items }
    var isLoading: Bool { pager.isLoading }
    var isLoadingMore: Bool { pager.isLoadingMore }
    var loadedPages: Int { pager.page }
    var hasLoadedOnce: Bool { pager.hasLoadedOnce }

    var hasMore: Bool {
        get { pager.hasMore }
        set { pager.hasMore = newValue }
    }

    var errorMessage: String? {
        get { pager.errorMessage }
        set { pager.reportError(newValue) }
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(totalPosts) / Double(perPage))))
    }

    /// True when the reader is sitting on the first page of a jump (say page 400
    /// of 400) and the replies above have not been fetched yet.
    var hasEarlier: Bool { firstLoadedPage > 1 && !posts.isEmpty }

    /// Page range currently loaded, e.g. "第 399–400 / 400 页".
    var loadedPageRange: String {
        firstLoadedPage == loadedPages
            ? "第 \(loadedPages) / \(pageCount) 页"
            : "第 \(firstLoadedPage)–\(loadedPages) / \(pageCount) 页"
    }

    func isFresh(_ pid: String) -> Bool { freshPids.contains(pid) }

    /// Dismisses a non-blocking error notice without refetching.
    func clearError() { pager.clearError() }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await reload()
    }

    func reload() async {
        await pager.reload()
        guard pager.page == 1, pager.errorMessage == nil else { return }
        firstLoadedPage = 1
        ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
    }

    func loadPage(_ target: Int) async {
        let clamped = min(max(1, target), pageCount)
        await pager.loadPage(clamped)
        guard pager.page == clamped, pager.errorMessage == nil else { return }
        firstLoadedPage = clamped
    }

    /// Jumps to the newest page of the thread. The page count comes from the
    /// page the server just returned, so nobody has to type a page number.
    func jumpToLastPage() async {
        guard hasLoadedOnce, pageCount > loadedPages else { return }
        await loadPage(pageCount)
    }

    func loadMore() async {
        guard hasMore else { return }
        guard pager.page < pageCount else {
            hasMore = false
            return
        }
        await pager.loadMore()
    }

    /// Fetches the page above the one that is loaded and puts it in front of the
    /// list. Returns the post that was on top so the reader keeps their place.
    @discardableResult
    func loadEarlier() async -> String? {
        guard hasEarlier else { return nil }
        let target = firstLoadedPage - 1
        let anchor = posts.first?.pid
        guard let older = await pager.prepend(page: target) else { return nil }
        firstLoadedPage = target
        DebugHooks.log(
            "S1 loadEarlier page=\(target) added=\(older.count) range=\(loadedPageRange)"
                + " posts=\(posts.count) anchor=\(anchor ?? "-")"
        )
        return older.isEmpty ? nil : anchor
    }

    /// Jumps back to the post the reader stopped at last time.
    func restoreReadingPosition() async {
        // S1_NO_RESTORE=1 lets a screenshot start at page 1 even when this
        // thread remembers a position (the app otherwise re-saves on every
        // scroll).
        if DebugHooks.flag("S1_NO_RESTORE") { return }
        guard let saved = ReadingProgressStore.shared.position(for: summary.tid) else { return }
        let perPage = max(1, self.perPage)
        let targetPage = max(1, Int(ceil(Double(saved.position) / Double(perPage))))
        if targetPage != loadedPages {
            await loadPage(targetPage)
        }
        if posts.contains(where: { $0.pid == saved.pid }) {
            resumePid = saved.pid
        }
    }

    /// Re-fetches the last loaded page and appends replies that arrived since.
    /// Returns how many were added, or `nil` when the request failed.
    @discardableResult
    func refreshNewReplies() async -> Int? {
        guard !isCheckingNewReplies, !posts.isEmpty, !isLoading else { return nil }
        isCheckingNewReplies = true
        lastCheckMessage = nil
        defer { isCheckingNewReplies = false }

        do {
            let result = try await ThreadPageLoader.fetch(
                tid: summary.tid,
                page: max(1, loadedPages)
            )
            if let info = result.thread {
                title = info.subject
                views = info.views
                totalPosts = info.replies + 1
            }
            let fresh = pager.append(result.posts)
            if !fresh.isEmpty {
                markFresh(fresh.map(\.pid))
                hasMore = loadedPages < pageCount
                ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
            }
            lastCheckMessage = fresh.isEmpty ? "暂无新回复" : "已加载 \(fresh.count) 条新回复"
            DebugHooks.log(
                "S1 refreshNewReplies page=\(loadedPages) added=\(fresh.count)"
                    + " posts=\(posts.count) total=\(totalPosts)"
            )
            return fresh.count
        } catch {
            lastCheckMessage = "检查失败：\(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Internals

    /// Folds a freshly loaded page's header numbers into the view state.
    private func absorb(page: Int, result: ThreadPage?) {
        guard let result else { return }
        perPage = result.perPage
        if let info = result.thread {
            title = info.subject
            totalPosts = info.replies + 1
            views = info.views
        }
        // Another page exists while the loaded page is not the last one.
        hasMore = page < pageCount && !posts.isEmpty
    }

    private func markFresh(_ pids: [String]) {
        guard !pids.isEmpty else { return }
        freshPids = Set(pids)
        freshToken += 1
        let token = freshToken
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard token == self.freshToken else { return }
            self.freshPids = []
        }
    }
}

/// The fetch behind a thread page.
///
/// S1 answers some threads with a bare Discuz "System Error" (HTTP 503) only
/// when a session cookie is attached. A 5xx is retried once as a guest, and the
/// thread is remembered so later visits skip the doomed signed-in request
/// entirely.
@MainActor
enum ThreadPageLoader {
    static func fetch(tid: String, page: Int) async throws -> ThreadPage {
        let params = ["tid": tid, "page": String(page)]

        if GuestFallbackStore.shared.prefersGuest(tid: tid) {
            DebugHooks.log("S1 fetchPage tid=\(tid) page=\(page) guest-first")
            do {
                return try await APIClient.shared.fetch("viewthread", params, guest: true)
            } catch {
                // The guest request stopped working (or the server recovered), so
                // let the next visit try the signed-in path again.
                GuestFallbackStore.shared.unmark(tid)
                throw error
            }
        }

        do {
            DebugHooks.log("S1 fetchPage tid=\(tid) page=\(page) signed-in")
            return try await APIClient.shared.fetch("viewthread", params)
        } catch let error as APIError {
            guard isServerSide(error) else { throw error }
            let guest: ThreadPage = try await APIClient.shared.fetch(
                "viewthread",
                params,
                guest: true
            )
            GuestFallbackStore.shared.mark(tid)
            DebugHooks.log("S1 fetchPage tid=\(tid) page=\(page) guest-fallback")
            return guest
        }
    }

    private static func isServerSide(_ error: APIError) -> Bool {
        switch error {
        case .http(let code):
            return code >= 500
        case .server:
            return true
        default:
            return false
        }
    }
}
