import Foundation

/// The thread-list screen's slice of the API.
///
/// The view model talks to this protocol instead of `APIClient.shared`, so the
/// paging, dedupe and error-recovery rules can be tested without a network.
protocol ThreadListAPI: Sendable {
    func forumThreads(fid: String, page: Int) async throws -> ThreadListPage
}

extension APIClient: ThreadListAPI {
    func forumThreads(fid: String, page: Int) async throws -> ThreadListPage {
        try await fetch("forumdisplay", ["fid": fid, "page": String(page)])
    }
}
