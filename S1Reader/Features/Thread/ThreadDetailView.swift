import SwiftUI
import Observation
import UIKit

@MainActor
@Observable
final class ThreadDetailViewModel {
    let summary: ThreadSummary

    var posts: [Post] = []
    var title: String
    var totalPosts = 0
    var views = 0
    var perPage = 40
    var isLoading = false
    var isLoadingMore = false
    /// True while the bottom of the list asks the server for new replies.
    var isCheckingNewReplies = false
    /// Result of the last bottom pull, shown under the last post.
    var lastCheckMessage: String?
    var errorMessage: String?
    var loadedPages = 0
    /// Lowest page currently in `posts`; above 1 the list can still scroll up.
    var firstLoadedPage = 1
    /// Set right after a successful reply so the list can scroll to the new post.
    var focusPid: String?
    /// Post to scroll to when reopening a thread that was read before.
    var resumePid: String?

    private var hasMore = true
    private var didLoad = false

    init(summary: ThreadSummary) {
        self.summary = summary
        self.title = summary.subject
        self.totalPosts = summary.replies + 1
        self.views = summary.views
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(totalPosts) / Double(perPage))))
    }

    var hasLoadedOnce: Bool { didLoad }

    /// True when the reader is sitting on the first page of a jump (say page 400
    /// of 400) and the replies above have not been fetched yet.
    var hasEarlier: Bool { firstLoadedPage > 1 && !posts.isEmpty }

    /// Page range currently loaded, e.g. "第 399–400 / 400 页".
    var loadedPageRange: String {
        firstLoadedPage == loadedPages
            ? "第 \(loadedPages) / \(pageCount) 页"
            : "第 \(firstLoadedPage)–\(loadedPages) / \(pageCount) 页"
    }

    /// S1 answers some threads with a bare Discuz "System Error" (HTTP 503) only when
    /// a session cookie is attached. A 5xx is retried once as a guest, and the thread
    /// is remembered so later visits skip the doomed signed-in request entirely.
    private func fetchPage(_ page: Int) async throws -> ThreadPage {
        let params = ["tid": summary.tid, "page": String(page)]

        if GuestFallbackStore.shared.prefersGuest(tid: summary.tid) {
            #if DEBUG
            print("S1 fetchPage tid=\(summary.tid) page=\(page) guest-first")
            #endif
            do {
                return try await APIClient.shared.fetch("viewthread", params, guest: true)
            } catch {
                // The guest request stopped working (or the server recovered), so let
                // the next visit try the signed-in path again.
                GuestFallbackStore.shared.unmark(summary.tid)
                throw error
            }
        }

        do {
            #if DEBUG
            print("S1 fetchPage tid=\(summary.tid) page=\(page) signed-in")
            #endif
            return try await APIClient.shared.fetch("viewthread", params)
        } catch let error as APIError {
            guard Self.isServerSide(error) else { throw error }
            let guest: ThreadPage = try await APIClient.shared.fetch(
                "viewthread",
                params,
                guest: true
            )
            GuestFallbackStore.shared.mark(summary.tid)
            #if DEBUG
            print("S1 fetchPage tid=\(summary.tid) page=\(page) guest-fallback")
            #endif
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

    func loadIfNeeded() async {
        guard !didLoad else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await fetchPage(1)
            posts = result.posts
            perPage = result.perPage
            if let info = result.thread {
                title = info.subject
                totalPosts = info.replies + 1
                views = info.views
            }
            loadedPages = 1
            firstLoadedPage = 1
            hasMore = posts.count < totalPosts
            didLoad = true
            ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Jumps back to the post the reader stopped at last time.
    func restoreReadingPosition() async {
        // S1_NO_RESTORE=1 lets a screenshot start at page 1 even when this thread
        // remembers a position (the app otherwise re-saves on every scroll).
        #if DEBUG
        if ProcessInfo.processInfo.environment["S1_NO_RESTORE"] != nil { return }
        #endif
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

    func loadPage(_ target: Int) async {
        guard !isLoading, !isLoadingMore else { return }
        let clamped = min(max(1, target), pageCount)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await fetchPage(clamped)
            posts = result.posts
            perPage = result.perPage
            if let info = result.thread {
                title = info.subject
                totalPosts = info.replies + 1
                views = info.views
            }
            loadedPages = clamped
            firstLoadedPage = clamped
            hasMore = clamped < pageCount && !result.posts.isEmpty
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        let next = loadedPages + 1
        guard next <= pageCount else {
            hasMore = false
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetchPage(next)
            let existing = Set(posts.map(\.pid))
            let fresh = result.posts.filter { !existing.contains($0.pid) }
            if fresh.isEmpty {
                // S1 replays the last page for pages past the end, so a page
                // without new posts means we are done; keep loadedPages put.
                hasMore = false
                return
            }
            posts.append(contentsOf: fresh)
            markFresh(fresh.map(\.pid))
            loadedPages = next
            #if DEBUG
            print("S1 loadMore page=\(next) added=\(fresh.count) posts=\(posts.count) top=\(posts.first?.pid ?? "-")")
            #endif
            if let info = result.thread {
                totalPosts = info.replies + 1
            }
            hasMore = posts.count < totalPosts
        } catch {
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }

    /// Posts that arrived in the most recent insert, so the list can give only
    /// those rows an entrance. Cleared shortly after.
    private(set) var freshPids: Set<String> = []
    private var freshToken = 0

    func isFresh(_ pid: String) -> Bool { freshPids.contains(pid) }

    /// Dismisses a non-blocking error notice without refetching.
    func clearError() { errorMessage = nil }

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

    /// Re-fetches the last loaded page and appends replies that arrived since.
    /// Returns how many were added, or `nil` when the request failed.
    @discardableResult
    func refreshNewReplies() async -> Int? {
        guard !isCheckingNewReplies, !posts.isEmpty, !isLoading else { return nil }
        isCheckingNewReplies = true
        lastCheckMessage = nil
        defer { isCheckingNewReplies = false }

        do {
            let result = try await fetchPage(max(1, loadedPages))
            let known = Set(posts.map(\.pid))
            let fresh = result.posts.filter { !known.contains($0.pid) }
            if let info = result.thread {
                title = info.subject
                views = info.views
                totalPosts = info.replies + 1
            }
            if !fresh.isEmpty {
                posts.append(contentsOf: fresh)
                markFresh(fresh.map(\.pid))
                hasMore = posts.count < totalPosts
                ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
            }
            lastCheckMessage = fresh.isEmpty ? "暂无新回复" : "已加载 \(fresh.count) 条新回复"
            #if DEBUG
            print("S1 refreshNewReplies page=\(loadedPages) added=\(fresh.count) posts=\(posts.count) total=\(totalPosts)")
            #endif
            return fresh.count
        } catch {
            lastCheckMessage = "检查失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// Fetches the page above the one that is loaded and puts it in front of the
    /// list. Returns the post that was on top so the reader keeps their place.
    @discardableResult
    func loadEarlier() async -> String? {
        guard hasEarlier, !isLoading, !isLoadingMore else { return nil }
        let target = firstLoadedPage - 1
        let anchor = posts.first?.pid
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await fetchPage(target)
            let existing = Set(posts.map(\.pid))
            let older = result.posts.filter { !existing.contains($0.pid) }
            if !older.isEmpty {
                // No entrance here: these rows land above the viewport, so the
                // fade would play where nobody can see it.
                posts.insert(contentsOf: older, at: 0)
            }
            firstLoadedPage = target
            if let info = result.thread {
                totalPosts = info.replies + 1
            }
            hasMore = posts.count < totalPosts
            #if DEBUG
            print("S1 loadEarlier page=\(target) added=\(older.count) range=\(loadedPageRange) posts=\(posts.count) anchor=\(anchor ?? "-")")
            #endif
            return older.isEmpty ? nil : anchor
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

struct ThreadDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var mainDynamicTypeSize
    @State private var model: ThreadDetailViewModel
    @State private var viewerIndex: Int?
    /// Which picture the reader tapped, so the viewer can grow out of it.
    @State private var zoomSourceID: String?
    @State private var threadImageURLs: [URL] = []
    @State private var showComposer = false
    @State private var showLogin = false
    @State private var showPageJump = false
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

    private enum Marker {
        /// Never equal to a real anchor, so the first approach always loads.
        static let none = "\u{0}"
        static let empty = "\u{1}"
    }

    private var topAnchorKey: String { visiblePid ?? Marker.empty }

    /// DEBUG hook: `S1_MOTION_SLOW=<factor>` stretches transitions so they can be
    /// filmed on a simulator (normal playback is 1).
    private var motionScale: Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["S1_MOTION_SLOW"], let factor = Double(raw) {
            return max(1, factor)
        }
        #endif
        return 1
    }
    @State private var threadImageCount = 0
    /// Posts already scanned for images, so appending a page doesn't rescan everything.
    @State private var scannedPostPids: Set<String> = []

    init(summary: ThreadSummary) {
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
            #if DEBUG
            // S1_SCROLL=<pid> jumps to a post so scrolling/saving can be checked
            // from the command line (the simulator cannot be tapped).
            // S1_LOADMORE=<n> appends n pages so pagination can be checked.
            if let raw = ProcessInfo.processInfo.environment["S1_LOADMORE"], let times = Int(raw) {
                let perfLogging = ProcessInfo.processInfo.environment["S1_PERF"] != nil
                for _ in 0..<max(0, times) {
                    try? await Task.sleep(for: .milliseconds(500))
                    await model.loadMore()
                    // S1_FRESH_SCROLL=1 reveals the rows that just arrived so the
                    // entrance can be filmed (they normally land off-screen).
                    if ProcessInfo.processInfo.environment["S1_FRESH_SCROLL"] != nil,
                       let first = model.posts.first(where: { model.isFresh($0.pid) }) {
                        try? await Task.sleep(for: .milliseconds(60))
                        visiblePid = first.pid
                    }
                }
                if perfLogging { PostBodyCache.shared.reportAndReset("after-loadmore") }
            }
            // S1_JUMP_PAGE=<n> then S1_LOAD_EARLIER=<n> exercise jumping to a late
            // page and loading the replies above it.
            if let raw = ProcessInfo.processInfo.environment["S1_JUMP_PAGE"], let page = Int(raw) {
                await model.loadPage(page)
                didRestorePosition = true
                // S1_TOP_ROW=1 parks the list one post down so the "load earlier"
                // row above the first post is on screen for a screenshot.
                let offset = ProcessInfo.processInfo.environment["S1_TOP_ROW"] == "1" ? 1 : 0
                visiblePid = model.posts.dropFirst(offset).first?.pid
                try? await Task.sleep(for: .milliseconds(600))
            }
            if let raw = ProcessInfo.processInfo.environment["S1_LOAD_EARLIER"], let times = Int(raw) {
                for _ in 0..<max(0, times) {
                    try? await Task.sleep(for: .milliseconds(400))
                    await loadEarlierKeepingPlace(force: true)
                }
            }
            // S1_LOAD_EARLIER_GATED=<n> replays the scroll-triggered path, which
            // must load only the first page and then hold until the list moves.
            if let raw = ProcessInfo.processInfo.environment["S1_LOAD_EARLIER_GATED"],
               let times = Int(raw) {
                for _ in 0..<max(0, times) {
                    try? await Task.sleep(for: .milliseconds(500))
                    await loadEarlierKeepingPlace()
                }
            }
            // S1_JUMP_SHEET=1 opens the page picker so its input field can be checked.
            if ProcessInfo.processInfo.environment["S1_JUMP_SHEET"] == "1" {
                try? await Task.sleep(for: .milliseconds(1200))
                showPageJump = true
            }
            if let pid = ProcessInfo.processInfo.environment["S1_SCROLL"], !pid.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                visiblePid = pid
            }
            if let raw = ProcessInfo.processInfo.environment["S1_VIEW_IMAGE"],
               let target = URL(string: raw) {
                try? await Task.sleep(for: .milliseconds(1200))
                openImage(target)
            }
            // S1_TOAST=<text> shows the toast so its look and timing can be filmed.
            if let text = ProcessInfo.processInfo.environment["S1_TOAST"], !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(400))
                let hold = ProcessInfo.processInfo.environment["S1_TOAST_HOLD"].flatMap(Int.init) ?? 2200
                toast = ToastMessage(text: text, style: .success, duration: .milliseconds(hold))
            }
            // S1_INLINE_NOTICE=<text> forces the inline retry notice.
            if let text = ProcessInfo.processInfo.environment["S1_INLINE_NOTICE"], !text.isEmpty {
                model.errorMessage = text
            }
            // S1_QUOTE_TAP=<pid> follows a quote (the button turns into "back");
            // S1_QUOTE_BACK=1 then takes it, so both states can be filmed.
            if let pid = ProcessInfo.processInfo.environment["S1_QUOTE_TAP"], !pid.isEmpty {
                // Wait for the first page, otherwise there is no origin to return to.
                for _ in 0..<25 where model.posts.isEmpty {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                try? await Task.sleep(for: .milliseconds(600))
                await jump(
                    to: pid,
                    from: ProcessInfo.processInfo.environment["S1_QUOTE_FROM"]
                )
                if ProcessInfo.processInfo.environment["S1_QUOTE_BACK"] == "1" {
                    try? await Task.sleep(for: .milliseconds(1800))
                    returnToOrigin()
                }
            }
            // S1_CHECK_NEW=1 exercises the bottom pull without a gesture.
            if ProcessInfo.processInfo.environment["S1_CHECK_NEW"] == "1" {
                try? await Task.sleep(for: .milliseconds(1500))
                let added = await model.refreshNewReplies()
                let addedText: String = added.map { String($0) } ?? "nil"
                let messageText: String = model.lastCheckMessage ?? "-"
                print("S1_CHECK_NEW added=" + addedText + " message=" + messageText)
            }
            // S1_POP=1 pops back to the list so the tab bar's return can be filmed.
            if ProcessInfo.processInfo.environment["S1_POP"] == "1" {
                try? await Task.sleep(for: .milliseconds(2500))
                dismiss()
            }
            // S1_CLEAR_IMAGES=1 drops this thread's cached pictures so the eviction
            // path can be checked without tapping the menu.
            if ProcessInfo.processInfo.environment["S1_CLEAR_IMAGES"] == "1" {
                try? await Task.sleep(for: .milliseconds(1500))
                let before = await ImageLoader.shared.diskUsage()
                clearThreadImageCache()
                try? await Task.sleep(for: .milliseconds(800))
                let after = await ImageLoader.shared.diskUsage()
                print("S1_CLEAR_IMAGES \(before) -> \(after)")
            }
            #endif
        }
        .refreshable { await model.reload() }
        .overlay {
            if model.isLoading && model.posts.isEmpty {
                ProgressView()
            }
        }
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
        .toast($toast)
        .sheet(isPresented: $showPageJump) { pageJumpSheet }
        .sheet(isPresented: $showComposer) { composerSheet }
        .sheet(isPresented: $showLogin) { LoginView() }
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
                            Button {
                                onlyOriginalPoster.toggle()
                            } label: {
                                Label(
                                    onlyOriginalPoster ? "显示全部楼层" : "只看楼主",
                                    systemImage: onlyOriginalPoster ? "person.2" : "person"
                                )
                            }
                        }
                        Section {
                            Button {
                                showPageJump = true
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
struct ThreadHeaderView: View {
    let title: String
    let author: String
    let posts: Int
    let views: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                if !author.isEmpty {
                    IconText(systemImage: "person", text: author)
                }
                IconText(systemImage: "bubble.left.and.bubble.right", text: "\(posts) 楼")
                IconText(systemImage: "eye", text: Formatters.compactCount(views))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Floating action in the bottom-trailing corner. One button, two states: reply,
/// and — once a quote has been followed — back to where the reader was. On
/// iOS 26 and later it is a real Liquid Glass button, so it picks up the same
/// material as the system chrome instead of a hand-drawn circle.
struct ThreadActionButton: View {
    enum Mode {
        case reply
        case back
    }

    let mode: Mode
    var action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                glyphs
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Color.accentColor)
            .accessibilityLabel(mode == .reply ? "回复本帖" : "返回到刚才的楼")
            .sensoryFeedback(.impact(weight: .light), trigger: mode)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        } else {
            Button(action: action) {
                glyphs
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(mode == .reply ? "回复本帖" : "返回到刚才的楼")
            .sensoryFeedback(.impact(weight: .light), trigger: mode)
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
    }

    /// Both glyphs share one font, so the two states keep the same weight; the
    /// outgoing one turns and shrinks away while the incoming one lands.
    private var glyphs: some View {
        ZStack {
            glyph(.reply).modifier(SwapTransition(isActive: mode == .reply, reduceMotion: reduceMotion))
            glyph(.back).modifier(SwapTransition(isActive: mode == .back, reduceMotion: reduceMotion))
        }
    }

    private func glyph(_ glyphMode: Mode) -> some View {
        Image(systemName: glyphMode == .reply ? "arrow.turn.up.left" : "arrow.backward.to.line")
            .font(.system(size: 20, weight: .semibold))
    }
}

/// Turning one glyph out while the other turns in, so the change reads as a
/// single control swapping purpose rather than a second button appearing.
private struct SwapTransition: ViewModifier {
    let isActive: Bool
    let reduceMotion: Bool

    private var turn: Double { reduceMotion ? 0 : (isActive ? 0 : (isActive ? 120 : -120)) }

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .rotationEffect(.degrees(isActive ? 0 : 120))
            .scaleEffect(isActive ? 1 : (reduceMotion ? 1 : 0.72))
            .animation(
                reduceMotion
                    ? .easeInOut(duration: 0.2)
                    : .spring(response: 0.42, dampingFraction: 0.72),
                value: isActive
            )
    }
}

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
                    views: model.views
                )

                if let error = model.errorMessage, model.posts.isEmpty {
                    ThreadErrorState(
                        message: error,
                        tid: model.summary.tid,
                        isLoggedIn: app.isLoggedIn,
                        onRetry: { Task { await model.reload() } },
                        onLogin: { showLogin = true }
                    )
                }

                earlierRow

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
            showComposer = true
        } else {
            showLogin = true
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
                #if DEBUG
                print("S1 loadEarlier skipped: same approach (top=\(topAnchorKey))")
                #endif
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
        guard onlyOriginalPoster else { return model.posts }
        return model.posts.filter { $0.author == model.summary.author || $0.isFirst }
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

        #if DEBUG
        let timing = ProcessInfo.processInfo.environment["S1_PERF_BENCH"] != nil
        #endif

        Task {
            let started = Date()
            let urls = await Task.detached(priority: .utility) {
                htmls.flatMap { HTMLParser.imageURLs(in: $0) }
            }.value
            #if DEBUG
            if timing {
                let fast = Date().timeIntervalSince(started) * 1000
                let slowStart = Date()
                _ = await Task.detached(priority: .utility) {
                    htmls.flatMap { html in
                        HTMLParser.parse(html).compactMap { node -> URL? in
                            if case .image(let url, let isSmiley) = node, !isSmiley { return url }
                            return nil
                        }
                    }
                }.value
                let slow = Date().timeIntervalSince(slowStart) * 1000
                print("S1_PERF imageURLs posts=\(htmls.count) scan=\(String(format: "%.1f", fast))ms fullParse=\(String(format: "%.1f", slow))ms")
            }
            #endif
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

    private func toggleFavorite() {
        guard app.isLoggedIn else {
            showLogin = true
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
