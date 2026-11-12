import SwiftUI

struct ThreadDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
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
    /// Where the reader stood before jumping to a quoted floor; drives the
    /// floating button's second state.
    @State private var returnPid: String?
    @State private var highlightedPid: String?
    @State private var highlightTask: Task<Void, Never>?
    @State private var toast: ToastMessage?
    @Namespace private var imageZoom
    /// Overscroll is ignored briefly after a jump, so the programmatic scroll
    /// cannot be mistaken for the reader pulling the list.
    @State private var ignoreOverscrollUntil = Date.distantPast

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

    init(summary: ThreadSummary, focusPid: String? = nil, startAtLastPage: Bool = false) {
        self.initialFocusPid = focusPid
        self.startAtLastPage = startAtLastPage
        _model = State(initialValue: ThreadDetailViewModel(summary: summary))
    }

    var body: some View {
        scrollArea
            .onChange(of: model.focusPid) { _, pid in
                guard let pid else { return }
                reveal(pid)
                model.focusPid = nil
            }
            .onChange(of: visiblePid) { _, pid in
                saveReadingPosition(pid)
            }
            .onDisappear {
                saveReadingPosition(visiblePid, immediate: true)
            }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.posts.count) {
            await PostBodyCache.shared.warm(posts: model.posts, scale: HTMLParser.textScale(for: mainDynamicTypeSize))
            registerThreadImages()
        }
        .task {
            await model.loadIfNeeded()
            if startAtLastPage {
                // Page one has to load first either way: only the server's answer
                // says how many pages there are.
                isRestoringPosition = true
                await model.jumpToLastPage()
                didRestorePosition = true
                if let pid = model.posts.last?.pid { visiblePid = pid }
                isRestoringPosition = false
            } else {
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
            // A link from another post may point at a specific floor.
            if let pid = initialFocusPid {
                await jump(to: pid)
            }
            await ThreadDetailDebugScript(hooks: debugHooks).run()
        }
        .refreshable { await model.reload() }
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
                        ForEach(0..<3, id: \.self) { _ in SkeletonPostRow() }
                    } else {
                        ThreadEmptyState()
                    }
                }

                ForEach(visiblePosts) { post in
                    postRow(post)
                    Divider()
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

                NewRepliesHint(
                    isChecking: model.isCheckingNewReplies,
                    message: model.lastCheckMessage,
                    hasPosts: !model.posts.isEmpty
                )
            }
            .modifier(ReadableWidth())
            .scrollTargetLayout()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: model.errorMessage)
            .opacity(isCrossfading ? 0 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isCrossfading)
        }
        .scrollPosition(id: $visiblePid, anchor: .top)
        .modifier(LoadEarlierOnOverscroll(isEnabled: model.hasEarlier) {
            Task { await loadEarlierKeepingPlace() }
        })
        .modifier(CheckNewRepliesOnOverscroll(isEnabled: canCheckNewReplies) {
            Task { await model.refreshNewReplies() }
        })
        .opacity(isRestoringPosition ? 0 : 1)
        .overlay { if isRestoringPosition { ProgressView() } }
        .contentMargins(.bottom, 72, for: .scrollContent)
        // A single compact button; the extra bottom margin keeps it clear of the
        // page footer while the thread scrolls under it. It turns into a way back
        // once a quote has been followed.
        .overlay(alignment: .bottomTrailing) {
            ThreadActionButton(mode: returnPid == nil ? .reply : .back) {
                primaryAction()
            }
        }
    }

    private var canCheckNewReplies: Bool {
        !model.posts.isEmpty && model.loadedPages >= model.pageCount
    }

    private func postRow(_ post: Post) -> some View {
        PostRowView(
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
        .rowEntrance(isNew: model.isFresh(post.pid))
        .background(post.pid == highlightedPid ? Color.accentColor.opacity(0.12) : Color.clear)
        .animation(.easeOut(duration: 0.35), value: highlightedPid)
        .onAppear {
            guard post.pid == visiblePosts.last?.pid else { return }
            guard lastNextPageAnchor != topAnchorKey else { return }
            lastNextPageAnchor = topAnchorKey
            Task { await model.loadMore() }
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
                ignoreOverscrollUntil = Date().addingTimeInterval(1.2)
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
        ignoreOverscrollUntil = Date().addingTimeInterval(1.2)
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
                isLoading: model.isLoadingMore,
                page: model.firstLoadedPage - 1
            ) {
                Task { await loadEarlierKeepingPlace(force: true) }
            }
            Divider()
        }
    }

    /// Loads the previous page and scrolls back to the post that was on top, so
    /// prepending content does not shove the reader's place down the screen.
    private func loadEarlierKeepingPlace(force: Bool = false) async {
        guard !model.isLoadingMore else { return }
        guard Date() > ignoreOverscrollUntil else { return }
        // Pulling past the top fires many times in a row; one page per approach.
        if !force {
            guard lastEarlierPageAnchor != topAnchorKey else {
                DebugHooks.log("S1 loadEarlier skipped: same approach (top=\(topAnchorKey))")
                return
            }
        }
        lastEarlierPageAnchor = topAnchorKey
        let topBefore = visiblePid
        guard let fallback = await model.loadEarlier() else {
            return
        }
        // Pin the post the reader was looking at; prepending a page would
        // otherwise shove them up by exactly one page of replies.
        let anchor = topBefore ?? fallback
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visiblePid = anchor
        }
    }

    private var visiblePosts: [Post] {
        model.posts.filter { post in
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
        guard didRestorePosition,
              let pid,
              let post = model.posts.first(where: { $0.pid == pid }) else { return }

        let tid = model.summary.tid
        let position = post.position
        saveTask?.cancel()

        guard !immediate else {
            ReadingProgressStore.shared.save(tid: tid, pid: pid, position: position)
            return
        }
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            ReadingProgressStore.shared.save(tid: tid, pid: pid, position: position)
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
