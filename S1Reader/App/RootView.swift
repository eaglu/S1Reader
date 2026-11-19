import SwiftUI
import Combine

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
        case .thread, .latestThread, .linkedThread, .readingThread:
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
        #if DEBUG
        // `S1_OPEN=quotes` replaces the whole app rather than presenting a cover:
        // the gallery exists only to be screenshotted, and a cover raced the
        // first layout often enough to make that unreliable.
        if DebugHooks.string("S1_OPEN") == "quotes" {
            QuoteGalleryView()
        } else if DebugHooks.string("S1_OPEN") == "liveactivity" {
            // The Lock Screen card on its own: the simulator cannot be locked
            // from the command line, so this is how it gets looked at.
            ReadingLiveActivityPreview()
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    private var tabs: some View {
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
        // Links that come from outside the app: s1reader:// from Siri, Shortcuts
        // or Safari, and the route an intent left behind in defaults.
        .onOpenURL { url in
            apply(AppDeepLink.parse(url))
        }
        .onReceive(NotificationCenter.default.publisher(for: PendingDeepLink.didArrive)) { _ in
            consumePendingLink()
        }
        .task {
            await model.loadIfNeeded()
            #if DEBUG
            openDebugTargetIfNeeded()
            #endif
            consumePendingLink()
            // `S1_DL_URL` is the cold-start half of a widget link: the route an
            // outside tap hands the app, applied with no thread on screen yet.
            if let raw = DebugHooks.string("S1_DL_URL"), let link = URL(string: raw).flatMap(AppDeepLink.parse) {
                apply(link)
            }
            // `S1_PERF_SCROLL` needs a screen to measure in a Release build too,
            // where the DEBUG-only `S1_OPEN` hook does not exist.
            if let tid = PerfProbe.threadID {
                path.append(.linkedThread(tid: tid, pid: nil))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // An intent performed while the app was in the background (or not
            // running) leaves its route in defaults; this is where it lands.
            consumePendingLink()
            guard model.isLoggedIn else { return }
            Task { await model.refreshMember() }
        }
    }

    private func consumePendingLink() {
        apply(PendingDeepLink.take())
    }

    /// Sends a link to the screen it names. Replaces the board stack instead of
    /// pushing, so asking Siri twice does not leave a second copy underneath.
    private func apply(_ link: AppDeepLink?) {
        guard let link else { return }
        switch link {
        case .forum(let fid):
            tab = 0
            path = [.linkedForum(fid: fid)]
        case .thread(let tid, let pid):
            tab = 0
            path = [.linkedThread(tid: tid, pid: pid)]
        case .reading(let tid, let page):
            // The reading Live Activity's way back in: same thread, the page the
            // reader left off on, instead of the one their saved position says.
            tab = 0
            // The route is what makes the screen appear; the page itself is a
            // request the thread screen takes. A route that replaces the screen
            // already showing that thread is not a new view in SwiftUI, so the
            // page cannot ride on the route alone.
            model.requestReadingJump(tid: tid, page: page)
            path = [.readingThread(tid: tid, page: page)]
        case .notices:
            tab = 1
            guard model.isLoggedIn else {
                // 提醒 needs a session: show the login sheet on 我的 rather than
                // an empty list with a spinner that never resolves.
                model.pendingLoginPrompt = true
                return
            }
            accountPath = NavigationPath()
            accountPath.append(AccountRoute.notices)
        case .favorites:
            tab = 1
            guard model.isLoggedIn else {
                model.pendingLoginPrompt = true
                return
            }
            accountPath = NavigationPath()
            accountPath.append(AccountRoute.favorites)
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
    /// Reopened from the reading Live Activity: a thread and the page to land on.
    case readingThread(tid: String, page: Int)
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
        case .readingThread(let tid, let page):
            LinkedThreadView(tid: tid, pid: nil, page: page)
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
