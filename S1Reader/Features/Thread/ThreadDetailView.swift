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
    @State private var model: ThreadDetailViewModel
    @State private var viewerImage: ImageReference?
    @State private var showComposer = false
    @State private var showLogin = false
    @State private var showPageJump = false
    @State private var onlyOriginalPoster = false
    @State private var isFavorite = false
    @State private var favoriteError: String?
    @State private var visiblePid: String?
    @State private var didRestorePosition = false
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
                header

                if let error = model.errorMessage, model.posts.isEmpty {
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

                ForEach(visiblePosts) { post in
                    PostRowView(post: post, onImageTap: { viewerImage = ImageReference(url: $0) })
                        .id(post.pid)
                        .onAppear {
                            guard post.pid == visiblePosts.last?.pid else { return }
                            Task { await model.loadMore() }
                        }
                    Divider()
                }

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
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visiblePid, anchor: .top)
        .contentMargins(.bottom, 72, for: .scrollContent)
        .onChange(of: model.focusPid) { _, pid in
            guard let pid else { return }
            didRestorePosition = true
            withAnimation(.easeInOut(duration: 0.25)) { visiblePid = pid }
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
            await model.restoreReadingPosition()
            didRestorePosition = true
            if let pid = model.resumePid {
                model.resumePid = nil
                try? await Task.sleep(for: .milliseconds(250))
                visiblePid = pid
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
            if let pid = ProcessInfo.processInfo.environment["S1_SCROLL"], !pid.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                visiblePid = pid
            }
            if let raw = ProcessInfo.processInfo.environment["S1_VIEW_IMAGE"],
               let target = URL(string: raw) {
                try? await Task.sleep(for: .milliseconds(1200))
                viewerImage = ImageReference(url: target)
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
        .overlay(alignment: .bottomTrailing) {
            Button {
                if app.isLoggedIn {
                    showComposer = true
                } else {
                    showLogin = true
                }
            } label: {
                Label("回复", systemImage: "arrowshape.turn.up.left.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 26)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        onlyOriginalPoster.toggle()
                    } label: {
                        Label(
                            onlyOriginalPoster ? "显示全部楼层" : "只看楼主",
                            systemImage: onlyOriginalPoster ? "person.2" : "person"
                        )
                    }
                    Button {
                        toggleFavorite()
                    } label: {
                        Label(isFavorite ? "取消收藏" : "收藏主题", systemImage: isFavorite ? "bookmark.fill" : "bookmark")
                    }
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
                    Button {
                        clearThreadImageCache()
                    } label: {
                        Label("清除本帖图片缓存（\(threadImageCount) 张）", systemImage: "trash")
                    }
                    .disabled(threadImageCount == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
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
        .sheet(item: $viewerImage) { reference in
            ImageViewer(url: reference.url)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Label(model.summary.author, systemImage: "person")
                Label("\(model.totalPosts) 楼", systemImage: "bubble.left.and.bubble.right")
                Label(Formatters.compactCount(model.views), systemImage: "eye")
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

private struct PageJumpSheet: View {
    let current: Int
    let total: Int
    var onJump: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int

    init(current: Int, total: Int, onJump: @escaping (Int) -> Void) {
        self.current = current
        self.total = total
        self.onJump = onJump
        _page = State(initialValue: current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $page, in: 1...max(total, 1)) {
                        Text("第 \(page) 页")
                    }
                    HStack {
                        Text("共")
                        Spacer()
                        Text("\(total) 页")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("跳转") {
                        onJump(page)
                        dismiss()
                    }
                    .disabled(page == current)
                }
            }
            .navigationTitle("跳页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}

struct ImageReference: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ImageViewer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var message: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    // Fitting the picture into the viewport height as well as its
                    // width is what shows the whole image instead of its top
                    // slice; the trailing frame reserves scroll space when zoomed.
                    RemoteImage(url: url, contentMode: .fit)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width * scale, height: proxy.size.height * scale)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(ContainerRelativeShape())
                .contentShape(Rectangle())
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(max(1, value.magnification), 4)
                        }
                        .onEnded { value in
                            withAnimation(.snappy) {
                                scale = min(max(1, value.magnification), 4)
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) { scale = scale > 1 ? 1 : 2.5 }
                }
            }
            .background(Color.black)
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) { message = nil }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await save() }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func save() async {
        do {
            try await ImageSaver.save(url)
            message = "已保存到相册"
        } catch {
            message = error.localizedDescription
        }
    }
}
