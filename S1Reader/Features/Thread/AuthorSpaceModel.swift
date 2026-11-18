import Foundation
import Observation

/// Loads the two remote lists the author card shows.
///
/// The lists page independently: each has its own `PagedListLoader`, its own
/// cursor and its own error row, so a failure on 回复 does not take 主题 down
/// with it. Nothing is fetched until the matching section asks for it, which
/// is how the sheet paints the locally known 本帖回复 first.
///
/// A space page needs a session cookie. `needsLogin` is raised both when the
/// caller already knows there is no session and when the server answers with
/// its login notice (an expired cookie), so the sheet can offer the login
/// screen instead of an empty list.
@MainActor
@Observable
final class AuthorSpaceModel {
    typealias ThreadFetch = @MainActor (_ page: Int) async throws -> AuthorSpaceParser.ThreadPage
    typealias ReplyFetch = @MainActor (_ page: Int) async throws -> AuthorSpaceParser.ReplyPage

    /// Shared between the two loaders: either one can discover that the
    /// session is gone.
    private final class LoginFlag {
        var value = false
    }

    let uid: String
    /// False until the reader signs in from this sheet.
    private(set) var canLoadRemote: Bool
    /// True when the server (or the caller) said the session is not usable.
    private(set) var needsLogin: Bool

    let threads: PagedListLoader<AuthorSpaceParser.ThreadItem, Void>
    let replies: PagedListLoader<AuthorSpaceParser.ReplyItem, Void>

    private let loginFlag: LoginFlag
    private var didStartThreads = false
    private var didStartReplies = false

    init(
        uid: String,
        isLoggedIn: Bool,
        fetchThreads: ThreadFetch? = nil,
        fetchReplies: ReplyFetch? = nil
    ) {
        self.uid = uid
        canLoadRemote = isLoggedIn
        needsLogin = !isLoggedIn

        let flag = LoginFlag()
        loginFlag = flag

        let loadThreads: ThreadFetch = fetchThreads ?? { page in
            #if DEBUG
            if let demo = DebugHooks.demoAuthorThreads {
                return AuthorSpaceParser.ThreadPage(
                    items: demo,
                    pageInfo: .init(page: page, totalPages: nil, hasMore: false)
                )
            }
            #endif
            return try await APIClient.shared.userThreads(uid: uid, page: page)
        }
        let loadReplies: ReplyFetch = fetchReplies ?? { page in
            #if DEBUG
            if let demo = DebugHooks.demoAuthorReplies {
                return AuthorSpaceParser.ReplyPage(
                    items: demo,
                    pageInfo: .init(page: page, totalPages: nil, hasMore: false)
                )
            }
            #endif
            return try await APIClient.shared.userPosts(uid: uid, page: page)
        }

        threads = PagedListLoader { page in
            do {
                let result = try await loadThreads(page)
                return .init(items: result.items, hasMore: result.hasMore)
            } catch {
                if Self.isLoginFailure(error) { flag.value = true }
                throw error
            }
        }
        replies = PagedListLoader { page in
            do {
                let result = try await loadReplies(page)
                return .init(items: result.items, hasMore: result.hasMore)
            } catch {
                if Self.isLoginFailure(error) { flag.value = true }
                throw error
            }
        }
    }

    // MARK: - State read by the sheet

    var threadItems: [AuthorSpaceParser.ThreadItem] { threads.items }
    var replyItems: [AuthorSpaceParser.ReplyItem] { replies.items }

    var isLoadingThreads: Bool { threads.isLoading }
    var isLoadingMoreThreads: Bool { threads.isLoadingMore }
    var threadsError: String? { threads.errorMessage }
    var threadHasMore: Bool { threads.hasMore }

    var isLoadingReplies: Bool { replies.isLoading }
    var isLoadingMoreReplies: Bool { replies.isLoadingMore }
    var repliesError: String? { replies.errorMessage }
    var replyHasMore: Bool { replies.hasMore }

    // MARK: - Loading

    /// Loads the first page once. Both halves are idempotent because SwiftUI
    /// re-runs `.task` when the row it is attached to is rebuilt.
    func loadThreadsIfNeeded() async {
        guard !didStartThreads, canLoadRemote else { return }
        didStartThreads = true
        await threads.loadPage(1)
        if loginFlag.value { needsLogin = true }
    }

    func loadRepliesIfNeeded() async {
        guard !didStartReplies, canLoadRemote else { return }
        didStartReplies = true
        await replies.loadPage(1)
        if loginFlag.value { needsLogin = true }
    }

    func loadMoreThreads() async {
        guard canLoadRemote, threads.hasMore, !threads.isLoading else { return }
        await threads.loadMore()
        if loginFlag.value { needsLogin = true }
    }

    func loadMoreReplies() async {
        guard canLoadRemote, replies.hasMore, !replies.isLoading else { return }
        await replies.loadMore()
        if loginFlag.value { needsLogin = true }
    }

    func retryThreads() async {
        guard canLoadRemote else { return }
        await threads.loadPage(1)
        if loginFlag.value { needsLogin = true }
    }

    func retryReplies() async {
        guard canLoadRemote else { return }
        await replies.loadPage(1)
        if loginFlag.value { needsLogin = true }
    }

    /// Called when the login sheet reports success. Both sections are fetched
    /// again from the top; they were left untouched while signed out.
    func didLogIn() async {
        canLoadRemote = true
        needsLogin = false
        loginFlag.value = false
        didStartThreads = false
        didStartReplies = false
        await loadThreadsIfNeeded()
        await loadRepliesIfNeeded()
    }

    private static func isLoginFailure(_ error: Error) -> Bool {
        if case APIError.notLoggedIn = error { return true }
        if case AuthorSpaceParser.Failure.loginRequired = error { return true }
        return false
    }
}
