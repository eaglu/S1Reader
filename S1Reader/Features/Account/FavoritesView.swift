import SwiftUI
import Observation

@MainActor
@Observable
final class FavoritesViewModel {
    var items: [FavoriteThread] = []
    var isLoading = false
    var errorMessage: String?
    var page = 0
    var hasMore = true

    func remove(_ item: FavoriteThread) async {
        let backup = items
        items.removeAll { $0.id == item.id }
        do {
            try await APIClient.shared.setFavorite(tid: item.tid, favorite: false)
        } catch {
            items = backup
            errorMessage = error.localizedDescription
        }
    }

    func load(reset: Bool = false) async {
        guard !isLoading else { return }
        if reset {
            page = 0
            hasMore = true
        }
        guard hasMore else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        #if DEBUG
        if DemoMode.isEnabled {
            items = DemoMode.favorites
            hasMore = false
            return
        }
        #endif

        do {
            let fresh = try await APIClient.shared.favorites(page: page + 1)
            if fresh.isEmpty {
                hasMore = false
            } else {
                page += 1
                let existing = Set(items.map(\.id))
                items.append(contentsOf: fresh.filter { !existing.contains($0.id) })
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FavoritesView: View {
    @State private var vm = FavoritesViewModel()

    var body: some View {
        List {
            if let error = vm.errorMessage, vm.items.isEmpty {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "bookmark.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") { Task { await vm.load(reset: true) } }
                        .buttonStyle(.borderedProminent)
                }
            }

            ForEach(vm.items) { item in
                NavigationLink(value: item.summary) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.subject)
                            .font(.body)
                            .lineLimit(3)
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
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if vm.items.isEmpty && vm.errorMessage == nil {
                ContentUnavailableView("收藏夹是空的", systemImage: "bookmark")
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
