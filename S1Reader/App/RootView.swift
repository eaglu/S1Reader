import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []
    @State private var accountPath = NavigationPath()
    @State private var tab = 0

    /// Threads hide the tab bar, the forum list above them keeps it. The state is
    /// read from the path rather than from the pushed screen, because a screen's
    /// own toolbar is only torn down after the pop animation, which left the list
    /// visible without its bar for a beat.
    private var hidesTabBar: Bool {
        switch path.last {
        case .thread, .latestThread, .linkedThread:
            return true
        default:
            return false
        }
    }

    /// Links inside posts point back at stage1st. Opening them in place keeps the
    /// reader in the app; anything else still goes to the system.
    private var linkHandler: OpenURLAction {
        OpenURLAction { url in
            guard let destination = Stage1stLink.destination(for: url) else {
                return .systemAction
            }
            tab = 0
            switch destination {
            case .thread(let tid, let pid):
                path.append(Route.linkedThread(tid: tid, pid: pid))
            case .forum(let fid):
                path.append(Route.linkedForum(fid: fid))
            }
            return .handled
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                BoardListView()
                    .toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)
                    .navigationDestination(for: Route.self) { route in
                        // "跳到最新页" is a push, so the screen needs the stack.
                        RouteDestination(route: route) { summary in
                            path.append(.latestThread(summary))
                        }
                    }
            }
            .tabItem { Label("论坛", systemImage: "list.bullet.rectangle") }
            .tag(0)

            NavigationStack(path: $accountPath) {
                AccountView()
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .badge(model.member?.unreadNotices ?? 0)
            .tag(1)
        }
        .modifier(SidebarAdaptableTabs())
        .environment(\.openURL, linkHandler)
        .task {
            await model.loadIfNeeded()
            #if DEBUG
            openDebugTargetIfNeeded()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, model.isLoggedIn else { return }
            Task { await model.refreshMember() }
        }
    }

    #if DEBUG
    /// Development helper: `S1_OPEN=thread:2206666` or `S1_OPEN=forum:6`
    /// jumps straight to a screen when launched from the command line.
    private func openDebugTargetIfNeeded() {
        if ProcessInfo.processInfo.environment["S1_TAB"] == "account" {
            tab = 1
        }
        guard let target = ProcessInfo.processInfo.environment["S1_OPEN"] else { return }
        if openDebugAccountTarget(target) { return }

        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }

        switch parts[0] {
        case "forum":
            if let forum = model.forums.first(where: { $0.fid == parts[1] }) {
                path.append(.forum(forum))
            }
        case "thread":
            path.append(.linkedThread(tid: parts[1], pid: nil))
        case "link":
            guard let url = URL(string: parts[1]), let destination = Stage1stLink.destination(for: url) else { return }
            switch destination {
            case .thread(let tid, let pid):
                path.append(.linkedThread(tid: tid, pid: pid))
            case .forum(let fid):
                path.append(.linkedForum(fid: fid))
            }
        default:
            break
        }
    }

    private func openDebugAccountTarget(_ target: String) -> Bool {
        switch target {
        case "notices":
            tab = 1
            accountPath.append(AccountRoute.notices)
            return true
        case "favorites":
            tab = 1
            accountPath.append(AccountRoute.favorites)
            return true
        case "images":
            tab = 1
            accountPath.append(AccountRoute.imageCache)
            return true
        default:
            return false
        }
    }
    #endif
}

/// What can be pushed onto the forum tab. Keeping the path typed (instead of
/// `NavigationPath`) lets the root see which screen is on top.
enum Route: Hashable {
    case forum(Forum)
    case thread(ThreadSummary)
    /// A thread opened straight at its newest page ("跳到最新页").
    case latestThread(ThreadSummary)
    /// Reached through a link, where all we know is the id.
    case linkedThread(tid: String, pid: String?)
    case linkedForum(fid: String)
}

/// Maps a `Route` to its screen. Shared by the board stack and the account
/// stack, which only needs the linked-thread cases.
struct RouteDestination: View {
    let route: Route
    /// Called when a list row asks to open a thread at its newest page.
    var onOpenAtLastPage: ((ThreadSummary) -> Void)?

    var body: some View {
        switch route {
        case .forum(let forum):
            ThreadListView(forum: forum, onOpenAtLastPage: onOpenAtLastPage)
        case .thread(let summary):
            ThreadDetailView(summary: summary)
        case .latestThread(let summary):
            ThreadDetailView(summary: summary, startAtLastPage: true)
        case .linkedThread(let tid, let pid):
            LinkedThreadView(tid: tid, pid: pid)
        case .linkedForum(let fid):
            LinkedForumView(fid: fid)
        }
    }
}

#Preview {
    RootView()
        .environment(AppModel())
        .environment(BlockedAuthorsStore.shared)
}
