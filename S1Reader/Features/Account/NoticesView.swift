import SwiftUI
import Observation

@MainActor
@Observable
final class NoticesViewModel {
    let pager = PagedListLoader<Notice, Void> { page in
        if let demo = DebugHooks.demoNotices {
            return .init(items: demo, hasMore: false)
        }
        return .init(items: try await APIClient.shared.notices(page: page))
    }

    var notices: [Notice] { pager.items }
    var isLoading: Bool { pager.isLoading }
    var errorMessage: String? { pager.errorMessage }
    var page: Int { pager.page }

    func load(reset: Bool = false) async {
        if reset {
            await pager.reload()
        } else {
            await pager.loadMore()
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
                NavigationLink(
                    value: Route.linkedThread(
                        tid: notice.tid,
                        pid: notice.pid.isEmpty ? nil : notice.pid
                    )
                ) {
                    NoticeRow(notice: notice)
                }
                .onAppear {
                    guard notice.id == vm.notices.last?.id else { return }
                    Task { await vm.load() }
                }
            }

            if vm.isLoading {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonNoticeRow()
                }
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
                    .lineLimitForAccessibility(4)
            }
        }
        .padding(.vertical, 4)
    }
}
private struct SkeletonNoticeRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkeletonBar(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 7) {
                SkeletonBar(width: 180, height: 13)
                SkeletonBar(height: 11)
            }
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}
