import SwiftUI

struct ThreadDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var mainDynamicTypeSize
    @Environment(BlockedAuthorsStore.self) private var blocks
    @State private var model: ThreadDetailViewModel
    @State private var viewerIndex: Int?
    /// Which picture the reader tapped, so the viewer can grow out of it.
    @State private var zoomSourceID: String?
    @State private var threadImageURLs: [URL] = []
    /// One slot for every sheet this screen opens: they are never shown at the
    /// same time, and one slot keeps SwiftUI from arbitrating four `.sheet`
    /// modifiers on the same view.
    @State private var sheet: Sheet?
    @State private var onlyOriginalPoster = false
    @State private var isFavorite = false
    @State private var visiblePid: String?
    @State private var didRestorePosition = false
    @State private var isRestoringPosition = false
    /// True while a jump swaps in another page: the list fades out, is replaced,
    /// and fades back in at the target floor instead of cutting.
    @State private var isCrossfading = false
    @State private var saveTask: Task<Void, Never>?
    /// Where the list stood when the last page was fetched, so a page is only
    /// pulled once per approach instead of as fast as the screen can fill.
    @State private var lastNextPageAnchor = Marker.none
    @State private var lastEarlierPageAnchor = Marker.none
    /// The floor the reader is on while an earlier page is on the wire;
    /// prepending churns `visiblePid`, so this is what has to stay put (and be
    /// saved as the reading position).
    @State private var earlierAnchorPid: String?
    /// The floor a fetched page above has to go back on. The page is held by the
    /// view model until the pull is over, so the insert never happens under a
    /// live gesture.
    @State private var pendingEarlierCommit: String?
    /// True for the update(s) between inserting a page above and putting the
    /// anchor back under it: the viewport sits on the new page there, and one
    /// blank frame is less of a jolt than the list jumping.
    @State private var isPinningEarlier = false
    /// A one-shot scroll command for the list. The token makes repeated pins to
    /// the same floor observable.
    @State private var pinRequest: PinRequest?
    @State private var pinTask: Task<Void, Never>?

    private struct PinRequest: Equatable {
        let pid: String
        let token: Int
    }
    @State private var scrollOffset: CGFloat = 0
    @State private var isScrollSettled = true
    /// Where the reader stood before jumping to a quoted floor; drives the
    /// floating button's second state.
    @State private var returnPid: String?
    @State private var highlightedPid: String?
    @State private var highlightTask: Task<Void, Never>?
    @State private var toast: ToastMessage?
    @Namespace private var imageZoom
    /// What the single sheet slot is showing.
    private enum Sheet: Identifiable {
        case pageJump
        case composer
        case login
        case author(AuthorProfile)

        var id: String {
            switch self {
            case .pageJump: "pageJump"
            case .composer: "composer"
            case .login: "login"
            case .author(let profile): "author-\(profile.authorID)"
            }
        }
    }

    /// Who the author profile sheet is about.
    struct AuthorProfile: Identifiable {
        let authorID: String
        let name: String
        var id: String { authorID }
    }

    private enum Marker {
        /// Never equal to a real anchor, so the first approach always loads.
        static let none = "\u{0}"
        static let empty = "\u{1}"
    }

    private var topAnchorKey: String { visiblePid ?? Marker.empty }

    /// `S1_MOTION_SLOW=<factor>` stretches transitions so they can be filmed on
    /// a simulator (normal playback is 1).
    private var motionScale: Double { DebugHooks.motionScale }
    @State private var threadImageCount = 0
    /// Posts already scanned for images, so appending a page doesn't rescan everything.
    @State private var scannedPostPids: Set<String> = []

    /// When a post links to another thread, the link usually points at a floor too.
    private let initialFocusPid: String?
    /// Opens the thread at its newest page instead of the first one.
    private let startAtLastPage: Bool
    /// Opens the thread at a specific page, from the reading Live Activity.
    private let startAtPage: Int?

    init(
        summary: ThreadSummary,
        focusPid: String? = nil,
        startAtLastPage: Bool = false,
        startAtPage: Int? = nil
    ) {
        self.initialFocusPid = focusPid
        self.startAtLastPage = startAtLastPage
        self.startAtPage = startAtPage
        _model = State(initialValue: ThreadDetailViewModel(summary: summary))
    }

    var body: some View {
        // The list and its reading effects go through a `Group`: one expression
        // for the whole screen is more than the type checker will take in time.
        Group {
            scrollArea
                .onChange(of: model.focusPid) { _, pid in
                    guard let pid else { return }
                    reveal(pid)
                    model.focusPid = nil
                }
                .onChange(of: visiblePid) { _, pid in
                    PerfProbe.note { $0.visiblePidWrites += 1 }
                    saveReadingPosition(pid)
                }
                // The reading card can name a page while this very thread is on
                // screen; the route alone cannot restart a view SwiftUI keeps, so
                // the jump is taken here too.
                .onChange(of: app.readingJump) { _, _ in
                    takeReadingJumpIfMine()
                }
                .onDisappear {
                    saveReadingPosition(visiblePid, immediate: true)
                    // Whatever the reader was in has been left: the card must not
                    // stay behind pointing at a screen that is gone.
                    ReadingLiveActivity.end()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Back in the app, so the island has done its job. Ending it
                        // here is what keeps it off the Lock Screen once read.
                        ReadingLiveActivity.end()
                    case .inactive, .background:
                        publishReadingActivity()
                    default:
                        break
                    }
                }
        }
        // The thread's title belongs to the page, not to the bar: it is drawn
        // once, in ThreadHeaderView. A title here repeated it — truncated — a
        // thumb's width above the full one. The bar keeps only its actions, and
        // an empty title is also what lets the back button read 返回.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.posts.count) {
            await PostBodyCache.shared.warm(posts: model.posts, scale: HTMLParser.textScale(for: mainDynamicTypeSize))
            registerThreadImages()
        }
        // Measures the list once a page is in it when `S1_PERF_SCROLL` is set;
        // inert otherwise.
        .task(id: model.posts.count) {
            await PerfProbe.runScrollScriptIfEnabled()
        }
        // A vote cast on this device is remembered per account; re-read it when
        // the reader logs in or out while the thread is open.
        .task(id: app.member?.uid) {
            model.syncPollVoterRecord(uid: app.member?.uid ?? "")
        }
        .task(id: landing) {
            await land()
            // A link from another post may point at a specific floor.
            if let pid = initialFocusPid {
                await jump(to: pid)
            }
            await ThreadDetailDebugScript(hooks: debugHooks).run()
            #if DEBUG
            await openDebugAuthorSheetIfNeeded()
            #endif
        }
        // No pull-to-refresh here: the pull past the top is this screen's
        // "earlier replies" gesture, and a refresh would replace the window with
        // page one, dropping the reader on the thread's oldest replies. New
        // replies arrive from the bottom overscroll instead.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Favourite is the most frequent action here, so it gets its own
                // button instead of hiding inside the menu.
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "bookmark.fill" : "bookmark")
                        .symbolEffect(.bounce, value: isFavorite)
                        .symbolEffectsRemoved(reduceMotion)
                }
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏主题")
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu

            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
        .sensoryFeedback(.selection, trigger: onlyOriginalPoster)
        .sensoryFeedback(.impact(weight: .light), trigger: blocks.count)
        .toast($toast)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .pageJump: pageJumpSheet
            case .composer: composerSheet
            case .login: LoginView()
            case .author(let profile): authorSheet(profile)
            }
        }
        .fullScreenCover(isPresented: isShowingViewer) {
            ImageBrowser(urls: threadImageURLs, index: viewerIndexBinding)
                .zoomPresentation(id: zoomSourceID, in: imageZoom)
        }
    }

    private var pageJumpSheet: some View {
        PageJumpSheet(current: model.loadedPages, total: model.pageCount) { page in
            Task { await model.loadPage(page) }
        }
    }

    private var composerSheet: some View {
        let tid = model.summary.tid
        return ReplyComposer(threadTitle: model.title) { text in
            let pid = try await APIClient.shared.reply(tid: tid, message: text)
            await model.loadPage(model.pageCount)
            model.focusPid = pid
        }
    }

    private var isShowingViewer: Binding<Bool> {
        Binding(get: { viewerIndex != nil }, set: { if !$0 { viewerIndex = nil } })
    }

    private var viewerIndexBinding: Binding<Int> {
        Binding(get: { viewerIndex ?? 0 }, set: { viewerIndex = $0 })
    }

    /// The "more" menu, kept out of `body` so the type checker stays fast.
    @ViewBuilder
    private var moreMenu: some View {
        Menu {
            Section {
                // A toggle, not a button that renames itself: the menu shows a
                // checkmark for the state and keeps the label stable.
                Toggle(isOn: $onlyOriginalPoster) {
                    Label("只看楼主", systemImage: "person")
                }
            }
            Section {
                Button {
                    Task { await model.jumpToLastPage() }
                } label: {
                    Label("跳到最新页", systemImage: "arrow.down.to.line")
                }
                .disabled(model.loadedPages >= model.pageCount)
                Button {
                    sheet = .pageJump
                } label: {
                    Label("跳到指定页（共 \(model.pageCount) 页）", systemImage: "number")
                }
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                if let webURL = URL(string: "https://stage1st.com/2b/thread-\(model.summary.tid)-1-1.html") {
                    ShareLink(item: webURL) {
                        Label("分享主题", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section {
                Button(role: .destructive) {
                    clearThreadImageCache()
                } label: {
                    Label("清除本帖图片缓存（\(threadImageCount) 张）", systemImage: "trash")
                }
                .disabled(threadImageCount == 0)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("更多")
    }

}

/// Thread title block, kept out of the main view so its body stays readable.
// Helpers live in an extension so the view body stays inside the length the
// lint rules allow; same file, so `private` state is still reachable.

extension ThreadDetailView {
    /// The scrolling list plus everything pinned to it. Kept out of `body` so the
    /// view stays inside what the type checker will accept in one expression.
    private var scrollArea: some View {
        PerfProbe.note { $0.listBodies += 1 }
        // One pass over the posts per body instead of one per row that appears:
        // the "next page" anchor used to re-filter every floor as it scrolled in.
        let visible = visiblePosts
        return GeometryReader { geometry in
            // Fill at least the visible height plus a spare row: how many posts
            // fit is a screen question, not a fixed three.
            let skeletonRowCount = ThreadSkeletonMetrics.rowCount(for: geometry.size.height)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ThreadHeaderView(
                            title: model.title,
                            author: model.summary.author,
                            posts: model.totalPosts,
                            views: model.views,
                            onAuthorTap: {
                                sheet = .author(
                                    AuthorProfile(
                                        authorID: model.summary.authorID,
                                        name: model.summary.author
                                    )
                                )
                            }
                        )
    
                        if let error = model.errorMessage, model.posts.isEmpty {
                            ThreadErrorState(
                                message: error,
                                tid: model.summary.tid,
                                isLoggedIn: app.isLoggedIn,
                                onRetry: { Task { await model.reload() } },
                                onLogin: { sheet = .login }
                            )
                        }
    
                        earlierRow
    
                        // First load shows the shape of the replies instead of a spinner
                        // on an empty page; a thread that really has no reply says so.
                        if model.posts.isEmpty, model.errorMessage == nil {
                            if model.isLoading || !model.hasLoadedOnce {
                                ForEach(0..<skeletonRowCount, id: \.self) { _ in SkeletonPostRow() }
                            } else {
                                ThreadEmptyState()
                            }
                        }
    
                        ForEach(visible) { post in
                            postRow(post, isLast: post.pid == visible.last?.pid)
                            // The poll belongs to the thread, not to a floor, but it is
                            // read directly under the first post: only when that post is
                            // actually on screen (a jump straight to page 400 has no
                            // head, and a ballot floating above 40 replies would be a
                            // stranger thing than no ballot at all).
                            if post.isFirst {
                                pollSection
                            }
                            if !PerfProbe.diagnostic("S1_PERF_NO_DIVIDER") {
                                Divider()
                            }
                        }
    
                        ThreadListFooter(
                            isLoadingMore: model.isLoadingMore,
                            hasPosts: !model.posts.isEmpty,
                            range: model.loadedPageRange,
                            loaded: model.posts.count,
                            total: model.totalPosts
                        )
    
                        if let error = model.errorMessage, !model.posts.isEmpty {
                            InlineNotice(
                                message: error,
                                onRetry: { Task { await model.reload() } },
                                onDismiss: { model.clearError() }
                            )
                            .noticeTransition(reduceMotion: reduceMotion)
                        }
    
                        NewRepliesButton(
                            isChecking: model.isCheckingNewReplies,
                            message: model.lastCheckMessage,
                            hasPosts: !model.posts.isEmpty,
                            isEnabled: canCheckNewReplies
                        ) {
                            Task { await model.refreshNewReplies() }
                        }
                    }
                    .modifier(ReadableWidth())
                    .scrollTargetLayout()
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.errorMessage)
                    .opacity(isCrossfading ? 0 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isCrossfading)
                }
                .scrollPosition(id: $visiblePid, anchor: .top)
                .accessibilityIdentifier("threadScroll")
                .accessibilityValue(debugWindowProbe)
                .modifier(ScrollMotionObserver(
                    onOffset: { offset in
                        PerfProbe.note { $0.scrollOffsetWrites += 1 }
                        scrollOffset = offset
                        commitEarlierWhenSettled()
                    },
                    onSettled: { settled in
                        isScrollSettled = settled
                        commitEarlierWhenSettled()
                    }
                ))
                .modifier(LoadEarlierOnOverscroll(isEnabled: model.hasEarlier) {
                    Task { await loadEarlierKeepingPlace() }
                })
                .opacity(isRestoringPosition || isPinningEarlier ? 0 : 1)
                // A saved position (or a page jump) hides the list so the top of the
                // thread never flashes by. The skeleton sits underneath in its place,
                // so hiding the list does not turn the screen into a spinner.
                .background(alignment: .top) {
                    if isRestoringPosition {
                        ThreadSkeletonList(count: skeletonRowCount)
                            .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isRestoringPosition)
                .contentMargins(.bottom, 72, for: .scrollContent)
                // A single compact button; the extra bottom margin keeps it clear of the
                // page footer while the thread scrolls under it. It turns into a way back
                // once a quote has been followed.
                .overlay(alignment: .bottomTrailing) {
                    ThreadActionButton(mode: returnPid == nil ? .reply : .back) {
                        primaryAction()
                    }
                }
                .onChange(of: pinRequest) { _, request in
                    guard let request else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(request.pid, anchor: .top)
                    }
                }
            }
        }
    }

    /// What this screen has to land on when it opens.
    ///
    /// A second tap on the reading card arrives while this very screen is
    /// already up, and the route that carries it (another `readingThread`) makes
    /// SwiftUI reuse the view: `@State` — the page in the list — is kept and a
    /// `.task` without an id never runs again, so the page on the card used to
    /// be ignored. Keying the landing on the request makes the jump happen
    /// however the screen got here.
    private struct Landing: Equatable {
        let tid: String
        let page: Int?
        let lastPage: Bool
    }

    private var landing: Landing {
        Landing(tid: model.summary.tid, page: startAtPage, lastPage: startAtLastPage)
    }

    /// Puts the list where the screen was asked to open it.
    private func land() async {
        if let startAtPage {
            // Reopened from the Live Activity: land on the page the card named,
            // and do not fetch page one first — that fetch was a second request
            // whose only job was to be thrown away, and it is what the reader
            // saw whenever the jump did not take.
            await landOn(startAtPage)
            return
        }

        await model.loadIfNeeded()

        if startAtLastPage {
            // Page one has to load either way: only the server's answer says how
            // many pages there are.
            isRestoringPosition = true
            await model.jumpToLastPage()
            didRestorePosition = true
            if let pid = model.posts.last?.pid { visiblePid = pid }
            // Give the list the same beat the saved-position path gets, so
            // the skeleton is still covering it while the scroll lands.
            try? await Task.sleep(for: .milliseconds(120))
            isRestoringPosition = false
            return
        }

        // Hiding the list until the restored post is scrolled into place keeps
        // the reader from seeing the top of the thread flash by first.
        let hasSavedPosition = ReadingProgressStore.shared.position(for: model.summary.tid) != nil
        if hasSavedPosition { isRestoringPosition = true }
        await model.restoreReadingPosition()
        didRestorePosition = true
        if let pid = model.resumePid {
            model.resumePid = nil
            try? await Task.sleep(for: .milliseconds(250))
            visiblePid = pid
        }
        if hasSavedPosition {
            try? await Task.sleep(for: .milliseconds(120))
            isRestoringPosition = false
        }
    }

    /// `S1_WINDOW_PROBE=1` publishes the window of pages the list holds, so a UI
    /// test can count how many pages one gesture added. Empty while reading.
    private var debugWindowProbe: String {
        guard DebugHooks.flag("S1_WINDOW_PROBE") else { return "" }
        return "\(model.firstLoadedPage)-\(model.loadedPages)"
    }

    /// Lands on `page` with the list hidden, then puts the top of that page under
    /// the reader's eye.
    private func landOn(_ page: Int) async {
        isRestoringPosition = true
        await model.openAtPage(page)
        if let pid = model.posts.first?.pid { visiblePid = pid }
        // The request has been honoured (or the route carried it): no second jump.
        _ = app.takeReadingJump(for: model.summary.tid)
        // The same beat the saved-position path gets, so the skeleton still
        // covers the list while the scroll lands.
        try? await Task.sleep(for: .milliseconds(120))
        didRestorePosition = true
        isRestoringPosition = false
    }

    /// Takes a page the reading card asked for while this thread was already on
    /// screen: the route cannot restart a view SwiftUI keeps, so the jump comes
    /// in through the app model instead.
    private func takeReadingJumpIfMine() {
        guard let page = app.takeReadingJump(for: model.summary.tid),
              page != model.loadedPages else { return }
        Task { await landOn(page) }
    }

    /// The page the reader is looking at. The card names this one, so a tap on
    /// it can come back to the same floors: `loadedPages` is the bottom of the
    /// window and says nothing about the floor at the top of the screen.
    private var visiblePage: Int? {
        guard let visiblePid else { return nil }
        return model.page(ofPid: visiblePid)
    }

    private var canCheckNewReplies: Bool {
        !model.posts.isEmpty && model.loadedPages >= model.pageCount
    }

    /// Mirrors the thread into the Dynamic Island / Lock Screen for the moment
    /// the reader leaves it. A card is only worth showing once the header is
    /// known: an empty title would read as a glitch.
    private func publishReadingActivity() {
        // Nothing to mirror while landing on a page: the numbers in the list
        // there describe a page the reader is not on, and publishing them is
        // what made a card say "第 1 页" and then take the reader there.
        guard model.hasLoadedOnce, !model.posts.isEmpty, !isRestoringPosition else { return }
        let state = ReadingActivityAttributes.ContentState(
            title: model.title,
            page: visiblePage ?? model.loadedPages,
            pageCount: model.pageCount,
            author: model.summary.author,
            excerpt: readingExcerpt
        )
        let tid = model.summary.tid
        Task { await ReadingLiveActivity.present(tid: tid, state: state) }
    }

    /// The opening post as plain text, for the one line under the title.
    private var readingExcerpt: String {
        let opening = model.posts.first(where: { $0.isFirst }) ?? model.posts.first
        guard let message = opening?.message, !message.isEmpty else { return "" }
        return HTMLParser.plainText(message)
    }

    private func postRow(_ post: Post, isLast: Bool) -> some View {
        PerfProbe.note { $0.rowsBuilt += 1 }
        return PostRowView(
            post: post,
            onImageTap: openImage,
            onQuoteTap: { pid in Task { await jump(to: pid, from: post.pid) } },
            onAuthorTap: { post in
                sheet = .author(AuthorProfile(authorID: post.authorID, name: post.author))
            },
            onBlockAuthor: { post in
                toggleBlock(AuthorProfile(authorID: post.authorID, name: post.author))
            },
            isAuthorBlocked: blocks.isBlocked(post.authorID),
            zoomNamespace: imageZoom
        )
        .id(post.pid)
        .rowEntrance(isNew: model.isFresh(post.pid) && !PerfProbe.diagnostic("S1_PERF_NO_MOTION"))
        .background(post.pid == highlightedPid ? Color.accentColor.opacity(0.12) : Color.clear)
        .animation(PerfProbe.diagnostic("S1_PERF_NO_MOTION") ? nil : .easeOut(duration: 0.35), value: highlightedPid)
        .onAppear {
            // Appending does not move the top, so one anchor per page is enough;
            // a request already in flight is dropped rather than queued.
            guard isLast else { return }
            guard !model.isLoadingMore else { return }
            guard lastNextPageAnchor != topAnchorKey else { return }
            lastNextPageAnchor = topAnchorKey
            Task { await model.loadMore() }
        }
    }

    /// The ballot under the first post. Hidden entirely while the thread has no
    /// poll, so a normal thread renders exactly as before.
    @ViewBuilder
    private var pollSection: some View {
        if let poll = model.poll {
            PollView(
                poll: poll,
                selection: model.selectedPollOptionIDs,
                votedOptionIDs: model.pollVotedOptionIDs,
                hasVoted: model.hasVotedPoll,
                isClosed: model.isPollClosed,
                isLoggedIn: app.isLoggedIn,
                canVote: model.canVotePoll(isLoggedIn: app.isLoggedIn),
                isSubmitting: model.isVotingPoll,
                errorMessage: model.pollVoteError,
                onToggle: { model.togglePollOption($0) },
                onSubmit: {
                    Task {
                        await model.submitPollVote(uid: app.member?.uid ?? "")
                        guard model.pollVoteError == nil else { return }
                        toast = ToastMessage(text: "投票成功", style: .success)
                    }
                },
                onLogin: { sheet = .login }
            )
        }
    }

    /// Reply normally; once a quote has been followed the same button goes back.
    private func primaryAction() {
        if returnPid != nil {
            returnToOrigin()
        } else if app.isLoggedIn {
            sheet = .composer
        } else {
            sheet = .login
        }
    }

    /// Jumps to the floor a quote points at, loading its page first when needed.
    /// `source` is the post the quote was tapped in: it is what "back" returns to,
    /// which is exact even when the scroll position has not been tracked yet.
    private func jump(to pid: String, from source: String? = nil) async {
        let origin = source ?? visiblePid ?? model.posts.first?.pid
        if !model.posts.contains(where: { $0.pid == pid }) {
            guard let page = await APIClient.shared.page(
                containingPost: pid,
                tid: model.summary.tid
            ) else {
                toast = ToastMessage(text: "找不到被引用的楼层，可能已经被删除。", style: .warning)
                return
            }
            if !reduceMotion, page != model.loadedPages {
                // Another page is a replacement, not a scroll: cross-fade it in
                // so the swap does not feel like a cut.
                withAnimation(.easeInOut(duration: 0.16 * motionScale)) { isCrossfading = true }
                try? await Task.sleep(for: .milliseconds(Int(170 * motionScale)))
                await model.loadPage(page)
                guard model.posts.contains(where: { $0.pid == pid }) else {
                    withAnimation(.easeInOut(duration: 0.2)) { isCrossfading = false }
                    toast = ToastMessage(text: "被引用的楼层不在这 40 楼里，可能已经被删除。", style: .warning)
                    return
                }
                if let origin, origin != pid { returnPid = origin }
                didRestorePosition = true
                visiblePid = pid
                highlight(pid)
                try? await Task.sleep(for: .milliseconds(Int(60 * motionScale)))
                withAnimation(.easeInOut(duration: 0.22 * motionScale)) { isCrossfading = false }
                return
            }
            await model.loadPage(page)
            guard model.posts.contains(where: { $0.pid == pid }) else {
                toast = ToastMessage(text: "被引用的楼层不在这 40 楼里，可能已经被删除。", style: .warning)
                return
            }
        }
        if let origin, origin != pid {
            returnPid = origin
        }
        reveal(pid)
    }

    private func returnToOrigin() {
        guard let pid = returnPid else { return }
        returnPid = nil
        Task {
            if !model.posts.contains(where: { $0.pid == pid }),
               let page = await APIClient.shared.page(containingPost: pid, tid: model.summary.tid) {
                await model.loadPage(page)
            }
            reveal(pid)
        }
    }

    /// Scrolls to a floor and flashes it so the jump has a visible landing spot.
    private func reveal(_ pid: String) {
        didRestorePosition = true
        if reduceMotion {
            visiblePid = pid
        } else {
            withAnimation(.easeInOut(duration: 0.3)) { visiblePid = pid }
        }
        highlight(pid)
    }

    /// Marks a floor briefly so the eye can find it after the list moves.
    private func highlight(_ pid: String) {
        highlightedPid = pid
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { highlightedPid = nil }
        }
    }

    @ViewBuilder
    private var earlierRow: some View {
        if model.hasEarlier {
            EarlierRepliesRow(
                isLoading: model.isLoadingEarlier,
                page: model.firstLoadedPage - 1
            ) {
                Task { await loadEarlierKeepingPlace(force: true) }
            }
            Divider()
        }
    }

    /// Loads the previous page and keeps the post the reader was looking at at
    /// the top, so prepending a page does not shove their floor down the screen.
    private func loadEarlierKeepingPlace(force: Bool = false) async {
        // One page at a time: a trigger that arrives while the previous page is
        // still loading is dropped, not queued. The view model raises its flag
        // before it suspends, so this is checked ahead of every `await`.
        guard !model.isLoadingEarlier, !model.isLoadingMore else { return }
        // Pulling past the top fires on every frame until the list is back in
        // place; the scroll gate holds one page per approach, this keeps the
        // explicit row from doubling up on that same approach.
        if !force {
            guard lastEarlierPageAnchor != topAnchorKey else {
                DebugHooks.log("S1 loadEarlier skipped: same approach (top=\(topAnchorKey))")
                return
            }
        }
        guard let anchor = topVisiblePid, model.hasEarlier else {
            DebugHooks.log("S1 loadEarlier: nothing to anchor (top=\(topAnchorKey))")
            return
        }
        DebugHooks.log("S1 loadEarlier start anchor=\(anchor) page=\(model.firstLoadedPage)")
        lastEarlierPageAnchor = anchor
        earlierAnchorPid = anchor
        defer { earlierAnchorPid = nil }
        // `loadEarlier` only reports failure before the fetch: a nil result
        // here means no page is in hand, so there is nothing to insert.
        guard await model.loadEarlier() != nil else { return }
        // The page is in hand; putting it in the list is a separate step, done
        // once the list is at rest. Inserting it under a live pull is what made
        // the new page sit at the top of the screen until the gesture ended.
        if isScrollSettled {
            commitEarlier(anchor)
        } else {
            pendingEarlierCommit = anchor
        }
    }

    /// Inserts a page that arrived above while the reader was pulling, once the
    /// pull is over. A live gesture owns the scroll position: a pin written
    /// during it is thrown away when the list springs back to the top, which is
    /// now the new page.
    private func commitEarlierWhenSettled() {
        guard let anchor = pendingEarlierCommit, isScrollSettled else { return }
        pendingEarlierCommit = nil
        commitEarlier(anchor)
    }

    /// Inserts the fetched page and puts `anchor` back under it in one update.
    /// The list stays blank until the pins land: between them the viewport rests
    /// on the newly inserted page, which is the frame the reader must not see.
    private func commitEarlier(_ anchor: String) {
        isPinningEarlier = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            guard model.commitEarlier() != nil else {
                isPinningEarlier = false
                return
            }
            visiblePid = anchor
        }
        DebugHooks.log(
            "S1 commit earlier anchor=\(anchor) offset=\(Int(scrollOffset))"
                + " visiblePid=\(visiblePid ?? "-")"
        )
        pinEarlier(anchor)
    }

    /// Puts `anchor` at the top in several passes. The first one lands while the
    /// page just inserted above it is still unmeasured, which leaves the anchor
    /// a row or two low; the next ones run once those rows are laid out. The
    /// list comes back when they are done.
    private func pinEarlier(_ anchor: String) {
        pinRequest = PinRequest(pid: anchor, token: (pinRequest?.token ?? 0) + 1)
        pinTask?.cancel()
        pinTask = Task { @MainActor in
            // The next run-loop turn has the rows above the anchor laid out; the
            // second pin then uses their real heights.
            await Task.yield()
            guard !Task.isCancelled else { return }
            pinRequest = PinRequest(pid: anchor, token: (pinRequest?.token ?? 0) + 1)
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealPinnedEarlier()
        }
    }

    private func revealPinnedEarlier() {
        pinTask = nil
        guard isPinningEarlier else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPinningEarlier = false }
    }

    /// The floor at the top of the list. Blocked authors and the OP filter drop
    /// rows, so the tracked id can point at a post that is not on screen at all.
    private var topVisiblePid: String? {
        let visible = visiblePosts
        if let pid = visiblePid, visible.contains(where: { $0.pid == pid }) {
            return pid
        }
        return visible.first?.pid
    }

    private var visiblePosts: [Post] {
        PerfProbe.note {
            $0.filterRuns += 1
            $0.filterPosts += model.posts.count
        }
        return model.posts.filter { post in
            // A thread the reader opened on purpose keeps its head even when its
            // author is blocked; only the replies lose that voice.
            if post.isFirst { return true }
            if blocks.isBlocked(post.authorID) { return false }
            if onlyOriginalPoster { return post.author == model.summary.author }
            return true
        }
    }

    /// Opens the viewer on the tapped picture, keeping the thread's order so the
    /// reader can swipe through the rest.
    private func openImage(_ url: URL) {
        zoomSourceID = url.absoluteString
        if let index = threadImageURLs.firstIndex(of: url) {
            viewerIndex = index
        } else {
            threadImageURLs = [url]
            viewerIndex = 0
        }
    }

    /// Remembers which images this thread uses so they can be dropped individually.
    private func registerThreadImages() {
        let tid = model.summary.tid
        let title = model.title
        // Only the posts that arrived since last time: re-scanning the whole
        // thread on every page append turned into O(n²) parsing.
        let fresh = model.posts.filter { !scannedPostPids.contains($0.pid) }
        guard !fresh.isEmpty else { return }
        let pids = fresh.map(\.pid)
        let htmls = fresh.map(\.message)
        scannedPostPids.formUnion(pids)

        Task {
            let urls = await Task.detached(priority: .utility) {
                htmls.flatMap { HTMLParser.imageURLs(in: $0) }
            }.value
            if let report = await DebugHooks.imageScanBenchmark(htmls) {
                DebugHooks.log(report)
            }
            // Reserve the right height for every picture on the page now, so
            // scrolling over them never reflows the list.
            await ImageLoader.shared.prefetchAspects(for: urls)
            ImageCacheIndex.shared.register(tid: tid, title: title, urls: urls)
            threadImageURLs = urls
            threadImageCount = ImageCacheIndex.shared.urls(for: tid).count
        }
    }

    private func clearThreadImageCache() {
        let tid = model.summary.tid
        let removed = threadImageCount
        Task {
            await ImageCacheIndex.shared.remove(tid: tid)
            threadImageCount = 0
            toast = ToastMessage(
                text: removed > 0 ? "已清除本帖的 \(removed) 张图片缓存" : "本帖没有图片缓存",
                style: .success
            )
        }
    }

    /// Stores the top-most visible post so the thread reopens in place.
    private func saveReadingPosition(_ pid: String?, immediate: Bool = false) {
        // While a page is being prepended the binding walks over rows that just
        // arrived; the reader's floor is the anchor taken before the request.
        let target = model.isLoadingEarlier ? earlierAnchorPid : pid
        // Not while the screen is still landing on its page: the rows in the
        // list there belong to whatever page the jump has not left yet.
        guard didRestorePosition,
              let position = model.readingPosition(visiblePid: target, isRestoring: isRestoringPosition)
        else { return }

        let tid = model.summary.tid
        saveTask?.cancel()

        guard !immediate else {
            ReadingProgressStore.shared.save(tid: tid, pid: position.pid, position: position.position)
            return
        }
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            ReadingProgressStore.shared.save(tid: tid, pid: position.pid, position: position.position)
        }
    }

    private func authorSheet(_ profile: AuthorProfile) -> some View {
        AuthorProfileSheet(
            name: profile.name,
            authorID: profile.authorID,
            replies: model.posts.filter { $0.authorID == profile.authorID },
            isBlocked: blocks.isBlocked(profile.authorID),
            canBlock: blocks.canBlock(profile.authorID),
            isFavorite: isFavorite,
            isLoggedIn: app.isLoggedIn,
            onOpen: { post in Task { await jump(to: post.pid) } },
            onToggleBlock: { toggleBlock(profile) },
            onToggleFavorite: toggleFavorite
        )
    }

    private func toggleBlock(_ profile: AuthorProfile) {
        let wasBlocked = blocks.isBlocked(profile.authorID)
        blocks.setBlocked(!wasBlocked, authorID: profile.authorID, name: profile.name)
        toast = ToastMessage(
            text: wasBlocked ? "已取消屏蔽 \(profile.name)" : "已屏蔽 \(profile.name)",
            style: .success
        )
    }

    private func toggleFavorite() {
        guard app.isLoggedIn else {
            sheet = .login
            return
        }
        let target = !isFavorite
        Task {
            do {
                try await APIClient.shared.setFavorite(tid: model.summary.tid, favorite: target)
                isFavorite = target
                toast = ToastMessage(text: target ? "已收藏" : "已取消收藏", style: .success)
            } catch {
                toast = ToastMessage(text: error.localizedDescription, style: .warning)
            }
        }
    }
}

/// The `S1_*` rehearsal hooks, wired to this screen's own state.
extension ThreadDetailView {
    #if DEBUG
    /// `S1_AUTHOR_SHEET=<pid|first>` opens the author card for a floor. The
    /// simulator cannot be tapped from the command line, so this is how the
    /// sheet's logged-out and signed-in states get photographed.
    func openDebugAuthorSheetIfNeeded() async {
        guard let target = DebugHooks.string("S1_AUTHOR_SHEET") else { return }
        for _ in 0..<50 where model.posts.isEmpty {
            try? await Task.sleep(for: .milliseconds(150))
        }
        let post = target == "first"
            ? model.posts.first
            : model.posts.first(where: { $0.pid == target })
        guard let post else { return }
        try? await Task.sleep(for: .milliseconds(700))
        sheet = .author(AuthorProfile(authorID: post.authorID, name: post.author))
    }
    #endif

    var debugHooks: ThreadDetailDebugScript.Hooks {
        ThreadDetailDebugScript.Hooks(
            model: model,
            jump: { pid, from in await jump(to: pid, from: from) },
            returnToOrigin: returnToOrigin,
            loadEarlier: { force in await loadEarlierKeepingPlace(force: force) },
            reveal: reveal,
            setVisiblePid: { pid in visiblePid = pid },
            showPageJump: { sheet = .pageJump },
            openImage: openImage,
            showToast: { toast = $0 },
            dismiss: { dismiss() },
            clearThreadImageCache: clearThreadImageCache
        )
    }
}
