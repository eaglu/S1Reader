import Foundation
import Observation

/// One forum's thread list. Paging lives in `PagedListLoader`; this adds the
/// endpoint and the numbers shown in the footer.
@MainActor
@Observable
final class ThreadListViewModel {
    let forum: Forum

    var totalThreads = 0
    var perPage = 50

    let pager: PagedListLoader<ThreadSummary, ThreadListPage>

    init(forum: Forum, api: any ThreadListAPI = APIClient.shared) {
        self.forum = forum
        pager = PagedListLoader { page in
            let result = try await api.forumThreads(fid: forum.fid, page: page)
            return .init(items: result.threads, context: result)
        }
        pager.onPageLoaded = { [weak self] _, _, context in
            guard let self, let context else { return }
            perPage = context.perPage
            totalThreads = context.totalThreads
        }
    }

    var threads: [ThreadSummary] { pager.items }
    var isLoading: Bool { pager.isLoading }
    var isLoadingMore: Bool { pager.isLoadingMore }
    var errorMessage: String? { pager.errorMessage }
    var hasLoadedOnce: Bool { pager.hasLoadedOnce }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await reload()
    }

    func reload() async {
        await pager.reload()
    }

    /// Appends the next page. A failed page keeps the cursor, so pulling at the
    /// bottom again retries instead of ending the list.
    func loadMore() async {
        await pager.loadMore()
    }
}
