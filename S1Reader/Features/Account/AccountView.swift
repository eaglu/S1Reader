import SwiftUI

/// Value-based routes for the 我的 tab so deep links can push them.
enum AccountRoute: Hashable {
    case notices
    case favorites
    case imageCache
    case blockedAuthors
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(BlockedAuthorsStore.self) private var blocks
    @State private var showLogin = false
    @State private var cacheBytes = 0
    @State private var guestFallbackCount = 0
    @State private var showLogoutConfirm = false
    @State private var toast: ToastMessage?
    /// The 灵动岛 switch. Stored under the key the Live Activity controller reads,
    /// and on by default so the feature works without a visit to 我的.
    @AppStorage(ReadingLiveActivity.enabledKey) private var showsReadingActivity = true

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    if model.isLoggedIn, let member = model.member {
                        AvatarView(uid: member.uid, name: member.username, size: 52)
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isLoggedIn ? (model.member?.username ?? "") : "未登录")
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            Section("功能") {
                if model.isLoggedIn {
                    // System badge: it scales with Dynamic Type and announces
                    // itself to VoiceOver without a capsule of our own.
                    NavigationLink(value: AccountRoute.notices) {
                        Label("提醒", systemImage: "bell")
                    }
                    .badge(model.member?.unreadNotices ?? 0)
                    NavigationLink(value: AccountRoute.favorites) {
                        Label("收藏夹", systemImage: "bookmark")
                    }
                } else {
                    Button {
                        showLogin = true
                    } label: {
                        Label("登录", systemImage: "person.badge.key")
                    }
                    Button {
                        showLogin = true
                    } label: {
                        HStack {
                            Label("提醒", systemImage: "bell")
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("登录后可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        showLogin = true
                    } label: {
                        HStack {
                            Label("收藏夹", systemImage: "bookmark")
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("登录后可用")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if model.isLoggedIn {
                Section {
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }

            Section {
                NavigationLink(value: AccountRoute.imageCache) {
                    HStack {
                        Label("图片缓存", systemImage: "photo.on.rectangle.angled")
                        Spacer()
                        Text(cacheDescription)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("清除缓存", role: .destructive) {
                    Task {
                        await ImageLoader.shared.clearCaches()
                        await refreshCacheUsage()
                        toast = ToastMessage(text: "已清除图片缓存", style: .success)
                    }
                }
                .disabled(cacheBytes == 0)
                NavigationLink(value: AccountRoute.blockedAuthors) {
                    Label("黑名单", systemImage: "person.slash")
                        .badge(blocks.count)
                }
                if guestFallbackCount > 0 {
                    Button("清除接口降级记录（\(guestFallbackCount)）") {
                        GuestFallbackStore.shared.clear()
                        guestFallbackCount = 0
                    }
                }
            } header: {
                Text("存储")
            } footer: {
                Text("帖子里的图片会缓存在本地，重新打开主题时不再重新下载。部分主题在登录状态下会被 S1 接口拒绝，客户端会自动改用游客身份读取，这里的记录用于重试登录态。")
            }

            Section {
                Toggle(isOn: $showsReadingActivity) {
                    Label("灵动岛显示正在阅读", systemImage: "text.book.closed")
                }
            } header: {
                Text("阅读")
            } footer: {
                Text("切出应用时，在灵动岛和锁屏显示当前帖子的标题与页码，点一下回到那一页。关掉后不会再出现。")
            }

            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("数据来源")
                    Spacer()
                    Text("stage1st.com")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("非官方客户端，与 Stage1st 官方无关。")
            }
        }
        .navigationTitle("我的")
        .toast($toast)
        .onChange(of: showsReadingActivity) { _, isOn in
            // The card must not outlive the switch: turning it off while the app
            // is open takes away the one the reader can still see in the island.
            guard !isOn else { return }
            ReadingLiveActivity.end()
        }
        .refreshable {
            await model.refreshMember()
            await refreshCacheUsage()
        }
        .task { await refreshCacheUsage() }
        .sheet(isPresented: $showLogin) {
            LoginView()
        }
        .confirmationDialog("确定退出登录？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                Task { await model.logout() }
            }
            Button("取消", role: .cancel) {}
        }
        .navigationDestination(for: ThreadSummary.self) { thread in
            ThreadDetailView(summary: thread)
        }
        .navigationDestination(for: AccountRoute.self) { route in
            switch route {
            case .notices: NoticesView()
            case .favorites: FavoritesView()
            case .imageCache: ImageCacheView()
            case .blockedAuthors: BlockedAuthorsView()
            }
        }
        // Notices link to a specific floor, so the account stack resolves the
        // same Route values the board stack does.
        .navigationDestination(for: Route.self) { route in
            RouteDestination(route: route, onOpenAtLastPage: nil)
        }
        .task {
            await model.refreshMember()
            #if DEBUG
            if ProcessInfo.processInfo.environment["S1_OPEN"] == "login" {
                showLogin = true
            }
            #endif
            showLoginIfRequested()
        }
        .onChange(of: model.pendingLoginPrompt) { _, _ in
            showLoginIfRequested()
        }
    }

    /// A deep link — or Siri — asked for a screen that needs a session.
    private func showLoginIfRequested() {
        guard model.pendingLoginPrompt else { return }
        model.pendingLoginPrompt = false
        showLogin = true
    }

    private var cacheDescription: String {
        guard cacheBytes > 0 else { return "无" }
        return ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file)
    }

    private func refreshCacheUsage() async {
        cacheBytes = await ImageLoader.shared.diskUsage()
        guestFallbackCount = GuestFallbackStore.shared.count
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var subtitle: String {
        guard model.isLoggedIn, let member = model.member else {
            return "以游客身份浏览"
        }
        return member.groupTitle.isEmpty ? "已登录" : member.groupTitle
    }
}
