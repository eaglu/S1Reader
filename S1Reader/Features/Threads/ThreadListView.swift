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

    init(forum: Forum) {
        self.forum = forum
        _model = State(initialValue: ThreadListViewModel(forum: forum))
    }

    private var visibleThreads: [ThreadSummary] {
        showOnlyToday ? model.threads.filter(\.isPinned) + model.threads.filter { !$0.isPinned && $0.isToday } : model.threads
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
        .listStyle(.plain)
        .navigationTitle(forum.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.reload() }
        .task { await model.loadIfNeeded() }
        .overlay {
            if model.isLoading && model.threads.isEmpty {
                ProgressView()
            } else if !model.isLoading && model.threads.isEmpty && model.errorMessage == nil {
                ContentUnavailableView("暂无主题", systemImage: "text.bubble")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("只看今日新帖", isOn: $showOnlyToday)
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }
}

private struct ThreadRow: View {
    let thread: ThreadSummary

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
