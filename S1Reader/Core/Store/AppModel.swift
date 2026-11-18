import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    var member: Member?
    var forums: [Forum] = []
    var categories: [ForumCategory] = []
    var isLoading = false
    var loadError: String?
    var isLoggingIn = false
    var loginError: String?
    /// Set when something outside the app asked for a signed-in screen (Siri
    /// asking for 提醒 while signed out). 我的 shows the login sheet and clears it.
    var pendingLoginPrompt = false

    private var didLoad = false

    struct Section: Identifiable {
        let id: String
        let title: String
        let forums: [Forum]
    }

    var sections: [Section] {
        guard !forums.isEmpty else { return [] }
        guard !categories.isEmpty else {
            return [Section(id: "all", title: "版块", forums: forums)]
        }
        var result: [Section] = []
        var used = Set<String>()
        for category in categories {
            let matched = category.forumIDs.compactMap { id in forums.first { $0.fid == id } }
            guard !matched.isEmpty else { continue }
            matched.forEach { used.insert($0.fid) }
            result.append(Section(id: category.id, title: category.name, forums: matched))
        }
        let leftovers = forums.filter { !used.contains($0.fid) }
        if !leftovers.isEmpty {
            result.append(Section(id: "other", title: "其他", forums: leftovers))
        }
        return Self.pinningMainForumAheadOfHotZone(result)
    }

    // MARK: - Section order

    /// The server keeps 热门新区 ahead of 主论坛, which is not the order the app
    /// wants. Only that one pair is touched: 主论坛 is lifted to just before
    /// 热门新区 and every other section keeps the order the server sent.
    /// Anything that does not match (a renamed category, a category that is
    /// missing) leaves the input untouched.
    static func pinningMainForumAheadOfHotZone(_ input: [Section]) -> [Section] {
        guard let mainIndex = input.firstIndex(where: { isMainForum($0.title) }),
              let hotIndex = input.firstIndex(where: { isHotZone($0.title) }),
              hotIndex < mainIndex
        else { return input }
        var result = input
        // hotIndex is below mainIndex, so removing 主论坛 does not move 热门新区.
        result.insert(result.remove(at: mainIndex), at: hotIndex)
        return result
    }

    static func isMainForum(_ title: String) -> Bool {
        normalizedTitle(title).contains("主论坛")
    }

    static func isHotZone(_ title: String) -> Bool {
        normalizedTitle(title).contains("热门新区")
    }

    /// Category names arrive with stray spacing (half- or full-width) and
    /// sometimes a suffix like 「（新区）」, so matching drops whitespace and
    /// asks for a substring instead of an exact equality.
    private static func normalizedTitle(_ title: String) -> String {
        String(title.filter { !$0.isWhitespace })
    }

    var isLoggedIn: Bool { member?.isLoggedIn == true }

    @discardableResult
    func login(username: String, password: String, questionID: Int, answer: String) async -> Bool {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            let input = APIClient.LoginInput(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                questionID: questionID,
                answer: answer
            )
            member = try await APIClient.shared.login(input)
            UserDefaults.standard.set(username, forKey: "s1.lastUsername")
            return true
        } catch {
            loginError = error.localizedDescription
            return false
        }
    }

    func logout() async {
        await APIClient.shared.logout()
        member = nil
    }

    /// Re-reads the session info (group, unread notice count) without
    /// reloading the whole forum index.
    func refreshMember() async {
        #if DEBUG
        if DemoMode.isEnabled { return }
        #endif
        do {
            let index: ForumIndex = try await APIClient.shared.fetch("forumindex")
            member = index.member
            forums = index.forums.isEmpty ? forums : index.forums
            categories = index.categories.isEmpty ? categories : index.categories
            cacheForSiri()
        } catch {
            // Keep the previous state; the badge is not worth an error banner.
        }
    }

    func loadIfNeeded() async {
        guard !didLoad else { return }
        await reload()
        #if DEBUG
        // The anonymous forumindex response would overwrite the fixture.
        if DemoMode.isEnabled {
            member = DemoMode.member()
        }
        #endif
    }

    func reload() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let index: ForumIndex = try await APIClient.shared.fetch("forumindex")
            forums = index.forums
            categories = index.categories
            member = index.member
            didLoad = true
            cacheForSiri()
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Keeps the offline copies App Intents read: the board index (so a board
    /// name can be resolved without a request), the notice badge (so Siri can
    /// answer "how many notices" instantly) and the Spotlight entity index.
    private func cacheForSiri() {
        ForumDirectory.shared.save(forums)
        NoticeBadgeStore.shared.record(unread: member?.unreadNotices ?? 0, loggedIn: isLoggedIn)
        S1SpotlightIndex.index(forums: forums)
    }
}
