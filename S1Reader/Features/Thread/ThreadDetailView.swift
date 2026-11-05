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
    var errorMessage: String?
    var loadedPages = 0
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
            hasMore = posts.count < totalPosts
            didLoad = true
            ThreadVisitStore.shared.markSeen(tid: summary.tid, replies: max(0, totalPosts - 1))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Jumps back to the post the reader stopped at last time.
    func restoreReadingPosition() async {
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
            loadedPages = next
            if let info = result.thread {
                totalPosts = info.replies + 1
            }
            hasMore = posts.count < totalPosts
        } catch {
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }
}

struct ThreadDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ThreadDetailViewModel
    @State private var viewerIndex: Int?
    @State private var threadImageURLs: [URL] = []
    @State private var showComposer = false
    @State private var showLogin = false
    @State private var showPageJump = false
    @State private var onlyOriginalPoster = false
    @State private var isFavorite = false
    @State private var favoriteError: String?
    @State private var visiblePid: String?
    @State private var didRestorePosition = false
    @State private var isRestoringPosition = false
    @State private var saveTask: Task<Void, Never>?
    @State private var threadImageCount = 0
    @State private var cacheNotice: String?
    @State private var copiedDiagnostics = false

    init(summary: ThreadSummary) {
        _model = State(initialValue: ThreadDetailViewModel(summary: summary))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ThreadHeaderView(
                    title: model.title,
                    author: model.summary.author,
                    posts: model.totalPosts,
                    views: model.views
                )

                if let error = model.errorMessage, model.posts.isEmpty {
                    errorState(error)
                }

                ForEach(visiblePosts) { post in
                    PostRowView(post: post, onImageTap: openImage)
                        .id(post.pid)
                        .onAppear {
                            guard post.pid == visiblePosts.last?.pid else { return }
                            Task { await model.loadMore() }
                        }
                    Divider()
                }

                listFooter
            }
            .modifier(ReadableWidth())
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visiblePid, anchor: .top)
        .opacity(isRestoringPosition ? 0 : 1)
        .overlay {
            if isRestoringPosition {
                ProgressView()
            }
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        // A single compact button; the extra bottom margin keeps it clear of the
        // page footer while the thread scrolls under it.
        .overlay(alignment: .bottomTrailing) {
            ReplyFloatingButton {
                if app.isLoggedIn {
                    showComposer = true
                } else {
                    showLogin = true
                }
            }
        }
        // Reading a thread is a focused task: the reply bar replaces the tabs.
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: model.focusPid) { _, pid in
            guard let pid else { return }
            didRestorePosition = true
            if reduceMotion {
                visiblePid = pid
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { visiblePid = pid }
            }
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
                for _ in 0..<max(0, times) {
                    try? await Task.sleep(for: .milliseconds(500))
                    await model.loadMore()
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
                }
                .accessibilityLabel(isFavorite ? "取消收藏" : "收藏主题")
            }
            ToolbarItem(placement: .topBarTrailing) {
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
        .sensoryFeedback(.impact(weight: .light), trigger: isFavorite)
        .sensoryFeedback(.selection, trigger: onlyOriginalPoster)
        .alert(cacheNotice ?? "", isPresented: Binding(
            get: { cacheNotice != nil },
            set: { if !$0 { cacheNotice = nil } }
        )) {
            Button("好", role: .cancel) { cacheNotice = nil }
        }
        .alert("收藏失败", isPresented: Binding(
            get: { favoriteError != nil },
            set: { if !$0 { favoriteError = nil } }
        )) {
            Button("好", role: .cancel) { favoriteError = nil }
        } message: {
            Text(favoriteError ?? "")
        }
        .sheet(isPresented: $showPageJump) {
            PageJumpSheet(current: model.loadedPages, total: model.pageCount) { page in
                Task { await model.loadPage(page) }
            }
        }
        .sheet(isPresented: $showComposer) {
            ReplyComposer(threadTitle: model.title) { text in
                let pid = try await APIClient.shared.reply(tid: model.summary.tid, message: text)
                await model.loadPage(model.pageCount)
                model.focusPid = pid
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { viewerIndex != nil },
            set: { if !$0 { viewerIndex = nil } }
        )) {
            ImageBrowser(
                urls: threadImageURLs,
                index: Binding(get: { viewerIndex ?? 0 }, set: { viewerIndex = $0 })
            )
        }
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("加载失败", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error)
        } actions: {
            Button("重试") { Task { await model.reload() } }
                .buttonStyle(.borderedProminent)
            if let webURL = URL(string: "https://stage1st.com/2b/thread-\(model.summary.tid)-1-1.html") {
                Link("在浏览器中打开", destination: webURL)
                    .buttonStyle(.bordered)
            }
            if !app.isLoggedIn {
                Button("登录") { showLogin = true }
                    .buttonStyle(.bordered)
            }
            Button(copiedDiagnostics ? "已复制诊断信息" : "复制诊断信息") {
                Task {
                    let details = await APIClient.shared.diagnostics()
                    UIPasteboard.general.string = "tid: \(model.summary.tid)\n\(details)"
                    copiedDiagnostics = true
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 60)
    }

    @ViewBuilder
    private var listFooter: some View {
        if model.isLoadingMore {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .padding(.vertical, 20)
        } else if !model.posts.isEmpty {
            Text("第 \(model.loadedPages) / \(model.pageCount) 页 · 已加载 \(model.posts.count) / \(model.totalPosts) 楼")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        }
    }

    /// Opens the viewer on the tapped picture, keeping the thread's order so the
    /// reader can swipe through the rest.
    private func openImage(_ url: URL) {
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
        let htmls = model.posts.map(\.message)
        guard !htmls.isEmpty else { return }

        Task {
            let urls = await Task.detached(priority: .utility) {
                htmls.flatMap { HTMLParser.imageURLs(in: $0) }
            }.value
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
            cacheNotice = removed > 0 ? "已清除本帖的 \(removed) 张图片缓存" : "本帖没有图片缓存"
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
            } catch {
                favoriteError = error.localizedDescription
            }
        }
    }

    private var visiblePosts: [Post] {
        guard onlyOriginalPoster else { return model.posts }
        return model.posts.filter { $0.author == model.summary.author || $0.isFirst }
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
                Label(author, systemImage: "person")
                Label("\(posts) 楼", systemImage: "bubble.left.and.bubble.right")
                Label(Formatters.compactCount(views), systemImage: "eye")
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

/// Floating reply action: one button, no bar. On iOS 26 and later it is a real
/// Liquid Glass button, so it picks up the same material as the system chrome
/// instead of a hand-drawn circle.
struct ReplyFloatingButton: View {
    var action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .tint(Color.accentColor)
            .accessibilityLabel("回复本帖")
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        } else {
            Button(action: action) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回复本帖")
            .padding(.trailing, 18)
            .padding(.bottom, 18)
        }
    }
}
