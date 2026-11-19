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
    /// True from the moment an earlier page is asked for until it has been
    /// merged. Set before the first suspension point, so a second request that
    /// arrives while the page is still on the wire is dropped instead of
    /// queued behind it.
    private(set) var isLoadingEarlier = false
    /// A page fetched for above the list that has not been inserted yet. Held
    /// until the reader's pull is over: the list only takes it at rest.
    private var pendingEarlier: (target: Int, anchor: String?, page: PagedListLoader<Post, ThreadPage>.Page)?

    // MARK: - Poll

    /// The thread's poll, when it has one. It lives next to the first post, not
    /// inside it, and survives page jumps: every page response carries it.
    private(set) var poll: Poll?
    /// Option ids this account already voted for, from `PollVoteStore`.
    private(set) var pollVotedOptionIDs: Set<String> = []
    /// Options ticked in the ballot but not sent yet.
    var selectedPollOptionIDs: Set<String> = []
    private(set) var isVotingPoll = false
    /// Failure text under the ballot; also carries the "too many choices" hint.
    var pollVoteError: String?

    private var threadFID = ""
    /// Set once the thread has been handed to `RecentThreadStore`, so paging
    /// does not rewrite it on every page.
    private var didRecordRecentThread = false
    private var pollThreadIsClosed = false
    /// A page fetched as a guest cannot say whether this account voted.
    private var pollPageIsGuest = true
    /// `allowvote` empty on a signed-in, open thread means the account already
    /// voted: Discuz's permission is "group may vote && has not voted && open".
    private var pollInferredVoted = false

    let pager: PagedListLoader<Post, ThreadPage>

    /// One page of a thread. Injectable so tests can page without a network.
    typealias PageFetch = @MainActor (_ page: Int) async throws -> ThreadPage

    /// Posts that arrived in the most recent insert, so the list can give only
    /// those rows an entrance. Cleared shortly after.
    private(set) var freshPids: Set<String> = []
    private var freshToken = 0

    init(summary: ThreadSummary, fetch: PageFetch? = nil) {
        self.summary = summary
        title = summary.subject
        totalPosts = summary.replies + 1
        views = summary.views

        let tid = summary.tid
        let fetcher = fetch ?? { page in
            try await ThreadPageLoader.fetch(tid: tid, page: page)
        }
        pager = PagedListLoader { page in
            let result = try await fetcher(page)
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

    // MARK: - Poll state

    var hasVotedPoll: Bool { !pollVotedOptionIDs.isEmpty || pollInferredVoted }

    var isPollClosed: Bool { (poll?.isClosed() ?? false) || pollThreadIsClosed }

    /// True when the ballot should accept taps: a poll exists, the account is
    /// signed in, the server allows a vote, and nothing was voted or closed.
    func canVotePoll(isLoggedIn: Bool) -> Bool {
        guard let poll, isLoggedIn, !isPollClosed, !hasVotedPoll else { return false }
        return poll.allowsVoting
    }

    /// Loads the local "I voted" record for the account now signed in.
    func syncPollVoterRecord(uid: String) {
        guard !uid.isEmpty else {
            pollVotedOptionIDs = []
            return
        }
        pollVotedOptionIDs = Set(PollVoteStore.shared.votedOptions(tid: summary.tid, uid: uid))
    }

    func togglePollOption(_ id: String) {
        guard let poll, !isVotingPoll else { return }
        pollVoteError = nil
        if poll.multiple {
            if selectedPollOptionIDs.contains(id) {
                selectedPollOptionIDs.remove(id)
            } else if selectedPollOptionIDs.count < poll.maxChoices {
                selectedPollOptionIDs.insert(id)
            } else {
                pollVoteError = "最多只能选择 \(poll.maxChoices) 项"
            }
        } else {
            selectedPollOptionIDs = selectedPollOptionIDs.contains(id) ? [] : [id]
        }
    }

    /// Sends the ballot and folds the result into the poll in place, so the
    /// reply list never reloads for a vote.
    func submitPollVote(uid: String) async {
        guard let poll, !isVotingPoll, !selectedPollOptionIDs.isEmpty else { return }
        let chosen = selectedPollOptionIDs
        isVotingPoll = true
        pollVoteError = nil
        defer { isVotingPoll = false }

        do {
            try await APIClient.shared.votePoll(
                tid: summary.tid,
                fid: threadFID,
                optionIDs: Array(chosen)
            )
        } catch {
            pollVoteError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return
        }

        self.poll = poll.applyingVote(chosen)
        pollVotedOptionIDs = chosen
        pollInferredVoted = true
        selectedPollOptionIDs = []
        if !uid.isEmpty {
            PollVoteStore.shared.record(tid: summary.tid, uid: uid, options: Array(chosen))
        }
    }

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
        await waitForPager()
        await pager.loadPage(clamped)
        guard pager.page == clamped, pager.errorMessage == nil else { return }
        firstLoadedPage = clamped
    }

    /// Opens the thread straight at `target`, without fetching page one first.
    ///
    /// The reading Live Activity hands back the page the reader left on. Loading
    /// the head of the thread before jumping to it is what used to leave them on
    /// page one: the jump could be dropped (a page was still on the wire) while
    /// page one — already in the list — stayed put. One request, one page.
    func openAtPage(_ target: Int) async {
        await loadPage(target)
        guard loadedPages == min(max(1, target), pageCount) else {
            // The jump did not take (a failed request): a thread whose head is
            // on screen beats a screen with nothing on it.
            await loadIfNeeded()
            return
        }
        ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
    }

    /// Waits out a page that is already on the wire. `loadPage` is a jump, not a
    /// scroll: dropping it because the list happens to be loading the next page
    /// of a scroll is exactly how "land on page 398" used to end up on page one.
    private func waitForPager(timeout: Duration = .seconds(3)) async {
        let deadline = ContinuousClock.now + timeout
        while pager.isLoading || pager.isLoadingMore {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The floor worth remembering right now, if any.
    ///
    /// `isRestoring` covers the window between "the screen opened" and "it
    /// landed on its page": the rows in the list there belong to whichever page
    /// the jump left behind, and remembering them would overwrite the reader's
    /// real position with it.
    func readingPosition(visiblePid: String?, isRestoring: Bool) -> (pid: String, position: Int)? {
        guard !isRestoring,
              hasLoadedOnce,
              let visiblePid,
              let post = posts.first(where: { $0.pid == visiblePid }),
              post.position > 0 else { return nil }
        return (visiblePid, post.position)
    }

    /// The page a floor belongs to, for the reading card: the last *loaded* page
    /// is the bottom of the window, which is not where a reader who scrolled up
    /// is looking.
    func page(ofPid pid: String) -> Int? {
        guard let post = posts.first(where: { $0.pid == pid }), post.position > 0 else { return nil }
        let page = Int(ceil(Double(post.position) / Double(max(1, perPage))))
        return min(pageCount, max(1, page))
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
        // `pager.loadMore` guards on its own flags, but checking here too keeps
        // the list from spawning a task per visible frame while a page lands.
        guard !pager.isLoading, !pager.isLoadingMore else { return }
        await pager.loadMore()
    }

    /// Fetches the page above the one that is loaded and keeps it in hand.
    /// Returns the post that was on top, so the reader keeps their place.
    ///
    /// The rows only enter the list in `commitEarlier`: inserting them while the
    /// reader is still pulling moves the content above their floor, and the new
    /// page stays on screen until the gesture ends. The view commits at rest.
    @discardableResult
    func loadEarlier() async -> String? {
        // The flag is raised before anything can suspend. A pull that arrives
        // while this page is in flight is dropped: the reader is looking at the
        // page they already have, and queuing would keep prepending pages under
        // their floor.
        guard hasEarlier, !isLoadingEarlier, !pager.isLoading, !isLoadingMore else { return nil }
        isLoadingEarlier = true

        let target = firstLoadedPage - 1
        let anchor = posts.first?.pid
        guard let older = await pager.fetchPrepend(page: target), !older.items.isEmpty else {
            isLoadingEarlier = false
            return nil
        }
        pendingEarlier = (target, anchor, older)
        DebugHooks.log(
            "S1 loadEarlier fetched page=\(target) rows=\(older.items.count)"
                + " anchor=\(anchor ?? "-")"
        )
        return anchor
    }

    /// Puts the page `loadEarlier` fetched above the list. The reader's floor
    /// stays exactly where it was: the rows are inserted and the list is put
    /// back on the anchor by the caller in the same update.
    @discardableResult
    func commitEarlier() -> String? {
        guard let pending = pendingEarlier, isLoadingEarlier else { return nil }
        pendingEarlier = nil
        isLoadingEarlier = false
        // A jump or a reload while the page was in hand replaced the window it
        // belongs to; inserting it now would drop it under the wrong pages.
        guard pending.target == firstLoadedPage - 1 else {
            DebugHooks.log("S1 loadEarlier dropped stale page=\(pending.target)")
            return nil
        }
        let fresh = pager.commitPrepend(pending.page, page: pending.target)
        firstLoadedPage = pending.target
        DebugHooks.log(
            "S1 loadEarlier page=\(pending.target) added=\(fresh.count) range=\(loadedPageRange)"
                + " posts=\(posts.count) anchor=\(pending.anchor ?? "-")"
        )
        return fresh.isEmpty ? nil : pending.anchor
    }

    /// Drops a fetched page that will never be inserted (a jump took over).
    func discardPendingEarlier() {
        pendingEarlier = nil
        isLoadingEarlier = false
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
            if !info.fid.isEmpty { threadFID = info.fid }
            pollThreadIsClosed = info.isClosed
            recordRecentThread(info)
        }
        if let fresh = result.poll {
            poll = fresh
            pollPageIsGuest = !result.member.isLoggedIn
            // Drop ticks for options the server no longer offers.
            let ids = Set(fresh.options.map(\.id))
            selectedPollOptionIDs.formIntersection(ids)
            pollInferredVoted = !pollPageIsGuest
                && !fresh.allowsVoting
                && !fresh.isClosed()
        }
        // Another page exists while the loaded page is not the last one.
        hasMore = page < pageCount && !posts.isEmpty
    }

    /// Hands the thread to the offline copies Siri reads: `RecentThreadStore`
    /// for "open the thread I read yesterday", and the Spotlight index for
    /// everything else.
    private func recordRecentThread(_ info: ThreadInfo) {
        guard !didRecordRecentThread else { return }
        didRecordRecentThread = true
        let thread = RecentThread(
            tid: summary.tid,
            subject: info.subject,
            author: info.author,
            fid: info.fid.isEmpty ? threadFID : info.fid,
            date: Date()
        )
        RecentThreadStore.shared.record(thread)
        S1SpotlightIndex.index(thread: thread)
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
