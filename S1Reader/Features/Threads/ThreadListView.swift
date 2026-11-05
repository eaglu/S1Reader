import SwiftUI
import Observation

@MainActor
@Observable
final class ThreadListViewModel {
    let forum: Forum

    var threads: [ThreadSummary] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var totalThreads = 0
    var perPage = 50

    private var page = 0
    private var hasMore = true
    private var didLoad = false

    init(forum: Forum) {
        self.forum = forum
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
            let result: ThreadListPage = try await APIClient.shared.fetch(
                "forumdisplay",
                ["fid": forum.fid, "page": "1"]
            )
            threads = result.threads
            perPage = result.perPage
            totalThreads = result.totalThreads
            page = 1
            hasMore = !result.threads.isEmpty
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = page + 1
        do {
            let result: ThreadListPage = try await APIClient.shared.fetch(
                "forumdisplay",
                ["fid": forum.fid, "page": String(next)]
            )
            let existing = Set(threads.map(\.tid))
            let fresh = result.threads.filter { !existing.contains($0.tid) }
            threads.append(contentsOf: fresh)
            page = next
            if result.threads.isEmpty || fresh.isEmpty {
                hasMore = false
            }
        } catch {
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }
}

struct ThreadListView: View {
    let forum: Forum

    @State private var model: ThreadListViewModel
    @State private var showOnlyToday = false
    @State private var query = Self.initialQuery

    /// Debug hook so the search field can be filled from the command line.
    private static var initialQuery: String {
        #if DEBUG
        ProcessInfo.processInfo.environment["S1_SEARCH"] ?? ""
        #else
        ""
        #endif
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(forum: Forum) {
        self.forum = forum
        _model = State(initialValue: ThreadListViewModel(forum: forum))
    }

    private var visibleThreads: [ThreadSummary] {
        let base = showOnlyToday
            ? model.threads.filter(\.isPinned) + model.threads.filter { !$0.isPinned && $0.isToday }
            : model.threads
        guard !trimmedQuery.isEmpty else { return base }
        return base.filter {
            $0.subject.localizedStandardContains(trimmedQuery)
                || $0.author.localizedStandardContains(trimmedQuery)
        }
    }

    var body: some View {
        List {
            if let error = model.errorMessage, model.threads.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await model.reload() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            if model.isLoading && model.threads.isEmpty {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonThreadRow()
                }
            } else if !trimmedQuery.isEmpty && visibleThreads.isEmpty {
                Section {
                    ContentUnavailableView.search(text: trimmedQuery)
                }
            }

            ForEach(visibleThreads) { thread in
                NavigationLink(value: thread) {
                    ThreadRow(thread: thread)
                }
                .listRowSeparator(.visible)
                .onAppear {
                    guard thread.tid == visibleThreads.last?.tid else { return }
                    Task { await model.loadMore() }
                }
            }

            if model.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .modifier(AdaptiveThreadListStyle())
        .navigationTitle(forum.name)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索主题或作者")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.reload() }
        .task { await model.loadIfNeeded() }
        .overlay {
            if !model.isLoading && model.threads.isEmpty && model.errorMessage == nil && trimmedQuery.isEmpty {
                ContentUnavailableView("暂无主题", systemImage: "text.bubble")
            }
        }
        .sensoryFeedback(.selection, trigger: showOnlyToday)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("只看今日新帖", isOn: $showOnlyToday)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("筛选主题")
            }
        }
    }
}

private struct SkeletonThreadRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这是一个用来占位的主题标题，长度大约两行")
                .font(.callout.weight(.medium))
            Text("作者 · 回复 · 浏览")
                .font(.caption)
        }
        .redacted(reason: .placeholder)
        .padding(.vertical, 4)
    }
}

private struct ThreadRow: View {
    let thread: ThreadSummary

    private var newReplies: Int {
        ThreadVisitStore.shared.newReplies(for: thread.tid, replies: thread.replies)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if thread.isPinned {
                    Text("置顶")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.red)
                } else if thread.isDigest {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                Text(thread.subject.isEmpty ? "（无标题）" : thread.subject)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: 10) {
                Label(thread.author, systemImage: "person")
                Label("\(thread.replies)", systemImage: "bubble.left")
                if newReplies > 0 {
                    Text("+\(newReplies)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("上次浏览后新增 \(newReplies) 条回复")
                }
                Label(Formatters.compactCount(thread.views), systemImage: "eye")
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            HStack(spacing: 4) {
                Text(thread.lastPoster)
                Text("·")
                Text(Formatters.relative(thread.lastPost))
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private extension ThreadSummary {
    var isToday: Bool {
        guard let date = Formatters.date(from: lastPost) else { return false }
        return Calendar.current.isDateInToday(date)
    }
}
