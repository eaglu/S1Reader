import SwiftUI
import Observation

@MainActor
@Observable
final class FavoritesViewModel {
    let pager = PagedListLoader<FavoriteThread, Void> { page in
        if let demo = DebugHooks.demoFavorites {
            return .init(items: demo, hasMore: false)
        }
        return .init(items: try await APIClient.shared.favorites(page: page))
    }

    var items: [FavoriteThread] { pager.items }
    var isLoading: Bool { pager.isLoading }
    var errorMessage: String? { pager.errorMessage }

    /// Removes the row straight away and puts it back when the server refuses,
    /// so the list never claims a favourite is gone when it is not.
    func remove(_ item: FavoriteThread) async {
        let backup = pager.items
        pager.replace(backup.filter { $0.id != item.id })
        do {
            try await APIClient.shared.setFavorite(tid: item.tid, favorite: false)
        } catch {
            pager.replace(backup)
            pager.reportError(error.localizedDescription)
        }
    }

    func load(reset: Bool = false) async {
        if reset {
            await pager.reload()
        } else {
            await pager.loadMore()
        }
    }
}

struct FavoritesView: View {
    @State private var vm = FavoritesViewModel()

    var body: some View {
        List {
            if let error = vm.errorMessage, vm.items.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "bookmark.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await vm.load(reset: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(vm.items) { item in
                NavigationLink(value: item.summary) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.subject)
                            .font(.body)
                            .lineLimitForAccessibility(3)
                        HStack(spacing: 10) {
                            Text(item.author)
                            Text("\(item.replies) 回复")
                            if let date = item.dateline {
                                Text(Formatters.relative(date))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    guard item.id == vm.items.last?.id else { return }
                    Task { await vm.load() }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await vm.remove(item) }
                    } label: {
                        Label("取消收藏", systemImage: "bookmark.slash")
                    }
                }
            }

            if vm.isLoading {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonFavoriteRow()
                }
                .listRowSeparator(.hidden)
            } else if vm.items.isEmpty && vm.errorMessage == nil {
                Section {
                    ContentUnavailableView("收藏夹是空的", systemImage: "bookmark")
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load(reset: true) }
        .task {
            if vm.items.isEmpty { await vm.load(reset: true) }
        }
    }
}
private struct SkeletonFavoriteRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SkeletonBar(height: 14)
            SkeletonBar(width: 150, height: 11)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}
