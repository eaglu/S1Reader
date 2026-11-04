import SwiftUI
import Observation

@MainActor
@Observable
final class NoticesViewModel {
    var notices: [Notice] = []
    var isLoading = false
    var errorMessage: String?
    var page = 0
    var hasMore = true

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
            notices = DemoMode.notices
            hasMore = false
            return
        }
        #endif

        do {
            let fresh = try await APIClient.shared.notices(page: page + 1)
            if fresh.isEmpty {
                hasMore = false
            } else {
                page += 1
                let existing = Set(notices.map(\.id))
                notices.append(contentsOf: fresh.filter { !existing.contains($0.id) })
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NoticesView: View {
    @Environment(AppModel.self) private var model
    @State private var vm = NoticesViewModel()

    var body: some View {
        List {
            if let error = vm.errorMessage, vm.notices.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "bell.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await vm.load(reset: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(vm.notices) { notice in
                NavigationLink(value: threadSummary(for: notice)) {
                    NoticeRow(notice: notice)
                }
                .onAppear {
                    guard notice.id == vm.notices.last?.id else { return }
                    Task { await vm.load() }
                }
            }

            if vm.isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowSeparator(.hidden)
            } else if vm.notices.isEmpty && vm.errorMessage == nil {
                Section {
                    ContentUnavailableView("没有新提醒", systemImage: "bell")
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await vm.load(reset: true)
            await model.refreshMember()
        }
        .task {
            if vm.notices.isEmpty { await vm.load(reset: true) }
        }
    }

    private func threadSummary(for notice: Notice) -> ThreadSummary {
        ThreadSummary(tid: notice.tid, subject: notice.note)
    }
}

private struct NoticeRow: View {
    let notice: Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.15))
                .overlay {
                    Text(String(notice.author.prefix(1)))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(notice.author)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    if let date = notice.dateline {
                        Text(Formatters.relative(date))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(notice.note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.vertical, 4)
    }
}
