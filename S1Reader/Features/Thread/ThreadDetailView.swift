import SwiftUI
import Observation

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
            let result: ThreadPage = try await APIClient.shared.fetch(
                "viewthread",
                ["tid": summary.tid, "page": "1"]
            )
            posts = result.posts
            perPage = result.perPage
            if let info = result.thread {
                title = info.subject
                totalPosts = info.replies + 1
                views = info.views
            }
            loadedPages = 1
            hasMore = !result.posts.isEmpty
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadPage(_ target: Int) async {
        guard !isLoading, !isLoadingMore else { return }
        let clamped = min(max(1, target), pageCount)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result: ThreadPage = try await APIClient.shared.fetch(
                "viewthread",
                ["tid": summary.tid, "page": String(clamped)]
            )
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
        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = loadedPages + 1
        do {
            let result: ThreadPage = try await APIClient.shared.fetch(
                "viewthread",
                ["tid": summary.tid, "page": String(next)]
            )
            let existing = Set(posts.map(\.pid))
            let fresh = result.posts.filter { !existing.contains($0.pid) }
            posts.append(contentsOf: fresh)
            loadedPages = next
            if result.posts.isEmpty || fresh.isEmpty {
                hasMore = false
            }
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

    init(summary: ThreadSummary) {
        _model = State(initialValue: ThreadDetailViewModel(summary: summary))
    }

    var body: some View {
        ScrollViewReader { proxy in
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
        }
        .contentMargins(.bottom, 72, for: .scrollContent)
        .onChange(of: model.focusPid) { _, pid in
            guard let pid else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(pid, anchor: .top)
            }
        }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadIfNeeded() }
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
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
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

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                RemoteImage(url: url)
                    .scaleEffect(scale)
                    .gesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(1, value.magnification)
                            }
                    )
                    .frame(maxWidth: .infinity)
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
