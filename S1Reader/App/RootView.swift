import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var accountPath = NavigationPath()
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $path) {
                BoardListView()
                    .navigationDestination(for: Forum.self) { forum in
                        ThreadListView(forum: forum)
                    }
                    .navigationDestination(for: ThreadSummary.self) { thread in
                        ThreadDetailView(summary: thread)
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
        switch target {
        case "notices":
            tab = 1
            accountPath.append(AccountRoute.notices)
            return
        case "favorites":
            tab = 1
            accountPath.append(AccountRoute.favorites)
            return
        case "images":
            tab = 1
            accountPath.append(AccountRoute.imageCache)
            return
        default:
            break
        }
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }

        switch parts[0] {
        case "forum":
            if let forum = model.forums.first(where: { $0.fid == parts[1] }) {
                path.append(forum)
            }
        case "thread":
            path.append(ThreadSummary(tid: parts[1], subject: "加载中…"))
        default:
            break
        }
    }
    #endif
}

#Preview {
    RootView()
        .environment(AppModel())
}
