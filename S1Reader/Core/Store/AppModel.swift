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
        return result
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
        } catch {
            loadError = error.localizedDescription
        }
    }
}
